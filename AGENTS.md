# AGENTS.md — agent-swift loop

Operating guide for AI agents working in the agent-swift build loop.

## What this loop builds

`agent-swift` — a native Swift CLI for AI agents to control macOS apps through Accessibility (`AXUIElement`) using the same `snapshot -> @ref -> action` workflow used by agent-flutter and agent-browser.

## Prerequisites

1. macOS 13+ with Xcode command line tools (`swift --version` works)
2. Accessibility trust enabled for the terminal/agent process running `agent-swift`
3. Target app is running and exposes accessibility elements
4. Read current `program*.md` and `eval.sh` before changing code
5. **If running over SSH**: AX tree access requires the GUI session context. Run commands as the console user:
   ```bash
   sudo launchctl asuser 501 sudo -u <gui-user> agent-swift snapshot -i
   ```
   Find the GUI user UID with `id -u <username>` and username with `stat -f %Su /dev/console`.

## Canonical workflow

```bash
# 1) Verify host readiness
agent-swift doctor

# 2) Connect to target app
agent-swift connect --bundle-id com.apple.TextEdit
# or
agent-swift connect --pid 12345

# 3) Capture refs
agent-swift snapshot -i

# 4) Interact using refs
agent-swift press @e1

# 5) Re-snapshot after mutations
agent-swift snapshot -i

# 6) Disconnect when done
agent-swift disconnect
```

## State machine

```text
[disconnected] --connect--> [connected] --snapshot--> [refs valid]
     ^                          |                        |
     |                      disconnect               press/fill/etc
     |                          |                        |
     +----------<---------------+----<---- [refs stale] --snapshot--> [refs valid]
```

- `status` and `doctor` are safe in any state.
- `snapshot`, `press`, `fill`, `get`, `find`, `wait`, `is`, `screenshot` require connected state.
- Mutating actions can stale refs; refresh with `snapshot`.

## Output shapes

### `snapshot` (human)
```text
@e1 [button] "Save"
@e2 [textfield] "Name"
@e3 [statictext] "Ready"
```

### `snapshot --json`
```json
[
  {
    "ref": "e1",
    "type": "button",
    "label": "Save",
    "role": "AXButton",
    "identifier": "saveButton",
    "enabled": true,
    "focused": false,
    "bounds": {"x": 400, "y": 220, "width": 80, "height": 30}
  }
]
```

### `status --json`
```json
{
  "connected": true,
  "pid": 12345,
  "bundleId": "com.apple.TextEdit",
  "connectedAt": "2026-03-09T00:00:00Z",
  "refs": 12
}
```

### error shape (all commands in JSON mode)
```json
{
  "error": {
    "code": "NOT_CONNECTED",
    "message": "No active session",
    "hint": "Run: agent-swift connect --bundle-id <id>",
    "diagnosticId": "a3f2b1c0"
  }
}
```

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Assertion false (`is` command only) |
| `2` | Error |

## Error recovery playbook

| Error code | Typical cause | Recovery |
|---|---|---|
| `AX_NOT_TRUSTED` | Accessibility permission missing | Grant Accessibility access, re-run `doctor` |
| `APP_NOT_FOUND` | Bundle ID or PID not running | Launch app, verify ID/PID, reconnect |
| `NOT_CONNECTED` | Session missing or stale | Run `connect`, then `snapshot` |
| `ELEMENT_NOT_FOUND` | Ref missing/stale | Re-run `snapshot -i`, use new ref |
| `ACTION_NOT_SUPPORTED` | Element has no press/settable action | Pick a different target from snapshot |
| `TIMEOUT` | Wait condition not met | Increase timeout or verify target state |
| `INVALID_ARGS` / `INVALID_INPUT` | Bad CLI arguments | Check `--help`, fix argument format |
| `COMMAND_FAILED` | Underlying AX/AppKit failure | Capture output + diagnosticId, retry with fresh snapshot |

## Locator strategy

Use this order for robust automation:

1. Stable accessibility identifier (`identifier`)
2. Role + label (`[button] "Save"`)
3. Role-only fallback (`AXButton`, `AXTextField`) as last resort

Guidance:
- Prefer deterministic controls over volatile text.
- Avoid relying on tree depth/index when identifier exists.
- Re-snapshot after UI transitions before selecting next ref.

## Idempotency and retry safety

| Command | Idempotent | Retry safety | Notes |
|---|---|---|---|
| `doctor` | Yes | Safe | Read-only checks |
| `connect` | Yes | Safe | Refreshes session target |
| `disconnect` | Yes | Safe | Clears session |
| `status` | Yes | Safe | Read-only |
| `snapshot` | Yes | Safe | Refreshes refs |
| `press` | No | Caution | Action may trigger twice |
| `fill` | No | Caution | Text may duplicate/replace unexpectedly |
| `get` | Yes | Safe | Read-only |
| `find` | Depends | Depends | Safe without action; caution with chained mutating actions |
| `wait` | Yes | Safe | Polling/read-only |
| `is` | Yes | Safe | Assertion-only |
| `screenshot` | Yes | Safe | Overwrites path if reused |
| `schema` | Yes | Safe | Static metadata |

## Recipes

### Press a button by ref
```bash
agent-swift doctor
agent-swift connect --bundle-id com.apple.TextEdit
agent-swift snapshot -i
agent-swift press @e1
agent-swift disconnect
```

### Recover from stale refs
```bash
agent-swift press @e4
# if ELEMENT_NOT_FOUND:
agent-swift snapshot -i
agent-swift press @e2
```

### JSON-first automation
```bash
agent-swift doctor --json
agent-swift status --json
agent-swift snapshot -i --json
```

## Loop control files

| File | Role | Mutable? |
|---|---|---|
| `program*.md` | Phase objectives and acceptance criteria | No (during active loop) |
| `eval.sh` | Pass/fail evaluator | No (during active loop) |
| `e2e-test.ts` / `e2e-test.sh` | Runtime validation | No (during active loop) |
| `agent-swift/` | Build target code | Yes |

## Guardrails

- Keep scope phase-local
- Do not add speculative features outside current phase
- Preserve deterministic output and exit-code contract
- Do not weaken evaluator thresholds
- Do not skip required e2e gates when enabled
- Keep evidence reproducible

## Blocked protocol

If blocked by device/network/permissions:
1. State blocker
2. State why it prevents completion
3. State exact next command/action to unblock
