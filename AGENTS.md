# AGENTS.md — agent-swift

Integration guide for AI agents using `agent-swift` to control native macOS apps via Accessibility (`AXUIElement`).

## What agent-swift is

`agent-swift` is a CLI automation interface for macOS apps.

It provides a consistent workflow:

1. Connect to an app
2. Snapshot the UI tree to generate `@ref`s
3. Interact via refs (`press`, `click`, `fill`, `scroll`)
4. Read/assert/wait for state (`get`, `is`, `wait`, `find`)
5. Re-snapshot after mutations

It is Selenium-like automation for native macOS apps.

Coverage includes 74 AX role mappings (100% official macOS SDK coverage).

## Prerequisites

1. macOS 13+
2. Xcode command line tools (`swift --version` works)
3. Accessibility permission for the terminal/agent process
4. Target app running and exposing accessibility elements
5. If running over SSH: execute in GUI user context

```bash
sudo launchctl asuser 501 sudo -u <gui-user> agent-swift snapshot -i
```

Find GUI user:

```bash
stat -f %Su /dev/console
id -u <username>
```

## State Machine

```text
[disconnected] --connect--> [connected] --snapshot--> [refs valid]
     ^                          |                        |
     |                      disconnect          press/click/fill/scroll/find(action)
     |                          |                        |
     +----------<---------------+----<---- [refs stale] --snapshot--> [refs valid]
```

Rules:

- `doctor` and `status` are safe in any state.
- All UI operations require connected state.
- Mutating actions can stale refs; run `snapshot` again before next selection.

## Command Reference (15)

| Command | Purpose | Typical human output | JSON output shape |
|---|---|---|---|
| `doctor` | Host and permission checks | `✓ Accessibility access granted` | `{ "checks": [...], "allPass": true }` |
| `connect` | Connect by `--pid`/`--bundle-id` | `Connected to PID 12345 (com.apple.TextEdit)` | `{ "connected": true, "pid": 12345, "bundleId": "...", "connectedAt": "..." }` |
| `disconnect` | Clear active session | `Disconnected` | `{ "disconnected": true }` |
| `status` | Session state + refs count | `Connected ...` / `Not connected` | `{ "connected": true, "pid": 12345, "bundleId": "...", "connectedAt": "...", "refs": 12 }` |
| `snapshot` | Build `@eN` refs from AX tree | `@e1 [button] "Save"` | `[ { "ref": "e1", "type": "button", "label": "Save", "role": "AXButton", ... } ]` |
| `press` | Activate ref via AXPress/AXConfirm; fallback click | `Pressed @e1` | `{ "pressed": "@e1", "success": true }` |
| `click` | Direct CGEvent click by ref or `x y` | `Clicked @e1 at (420, 280)` | `{ "clicked": "@e1", "x": 420.0, "y": 280.0, "success": true }` |
| `fill` | Set text value on ref | `Filled @e2 with "hello"` | `{ "filled": "@e2", "text": "hello", "success": true }` |
| `get` | Read `text/type/role/identifier/attrs` | value text or attrs lines | `{ "ref": "@e2", "property": "text", "value": "hello" }` or attrs object |
| `find` | Locate by `role/text/identifier` (+ optional action) | `@e3 [button] "Save"` / `Found @e3 → pressed` | `{ "ref": "@e3", ... }` or action result object |
| `screenshot` | Save PNG of target app window | `Screenshot saved to /tmp/shot.png` | `{ "path": "/tmp/shot.png", "success": true }` |
| `is` | Assertion check (`exists/visible/enabled/focused`) | `true` / `false` | `{ "ref": "@e1", "condition": "exists", "result": true }` |
| `wait` | Poll for `exists/visible/text/gone` or delay | `Condition met: text Saved (320ms)` | `{ "condition": "text", "target": "Saved", "success": true, "elapsed": 320 }` |
| `scroll` | `up/down` or scroll ref into view | `Scrolled down` / `Scrolled @e8 into view` | `{ "target": "down", "success": true }` |
| `schema` | Machine-readable command schema | JSON only | `{ "name": "press", "args": [...], "flags": [...], "exitCodes": {...} }` |

## Canonical Workflow

```bash
agent-swift doctor
agent-swift connect --bundle-id com.apple.TextEdit
agent-swift snapshot -i
agent-swift press @e1
agent-swift snapshot -i
agent-swift disconnect
```

## JSON Mode

JSON output is enabled when any of these are true:

1. `--json` is passed
2. `AGENT_SWIFT_JSON=1`
3. stdout is non-TTY (auto JSON)

Example:

```bash
agent-swift doctor --json
agent-swift status --json
agent-swift snapshot -i --json
```

## Output Shapes

`snapshot` (human):

```text
@e1 [button] "Save"
@e2 [textfield] "Name"
@e3 [label] "Ready"
```

`snapshot --json`:

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

`status --json`:

```json
{
  "connected": true,
  "pid": 12345,
  "bundleId": "com.apple.TextEdit",
  "connectedAt": "2026-03-09T00:00:00Z",
  "refs": 12
}
```

Error shape (all commands in JSON mode):

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

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Assertion false (`is` command only) |
| `2` | Error |

## Environment Variables

| Variable | Purpose | Example |
|---|---|---|
| `AGENT_SWIFT_JSON` | Force JSON output | `AGENT_SWIFT_JSON=1` |
| `AGENT_SWIFT_TIMEOUT` | Default `wait` timeout (ms) | `AGENT_SWIFT_TIMEOUT=10000` |
| `AGENT_SWIFT_HOME` | Session home dir (`session.json`) | `AGENT_SWIFT_HOME=/tmp/agent-swift` |

## Error Recovery Playbook

| Error code | Typical cause | Recovery |
|---|---|---|
| `AX_NOT_TRUSTED` | Accessibility permission missing | Grant permission; re-run `doctor` |
| `APP_NOT_FOUND` | Bundle ID not running | Launch app, reconnect |
| `APP_NOT_RUNNING` | Connected PID exited | Reconnect (`connect`) then `snapshot` |
| `NOT_CONNECTED` | No active session | `connect`, then `snapshot` |
| `ELEMENT_NOT_FOUND` | Ref missing/stale | Re-run `snapshot -i` and use fresh ref |
| `INVALID_INPUT` | Bad ref/arg format | Use `@eN` refs or valid coordinates |
| `INVALID_ARGS` | Unsupported locator/action/condition | Run `--help` and fix arguments |
| `ACTION_NOT_SUPPORTED` | Element does not support action | Pick a different control |
| `NO_BOUNDS` | Element has no visible bounds | Scroll into view or use a different target |
| `CLICK_FAILED` | CGEvent click failed | Verify AX trust and app focus |
| `SCROLL_FAILED` | Scroll action failed | Try directional scroll (`up/down`) |
| `SCREENSHOT_FAILED` | Window capture failed | Ensure target window is visible |
| `TIMEOUT` | Wait condition not met in time | Increase timeout and verify target state |

## Locator Strategy

Use this order:

1. Stable `identifier`
2. Role + label text (`[button] "Save"`)
3. Role-only fallback (`AXButton`, `AXTextField`)

Guidance:

- Prefer deterministic controls, not volatile status text.
- Avoid index/depth assumptions when `identifier` is available.
- Re-snapshot after UI transitions.

## Idempotency and Retry Safety

| Command | Idempotent | Retry safety | Notes |
|---|---|---|---|
| `doctor` | Yes | Safe | Read-only checks |
| `connect` | Yes | Safe | Refreshes session target |
| `disconnect` | Yes | Safe | Clears session |
| `status` | Yes | Safe | Read-only |
| `snapshot` | Yes | Safe | Rebuilds refs |
| `press` | No | Caution | May trigger action twice |
| `click` | No | Caution | Re-click can duplicate side effects |
| `fill` | No | Caution | May overwrite/duplicate text |
| `get` | Yes | Safe | Read-only |
| `find` | Depends | Depends | Safe when read-only; caution with chained action |
| `screenshot` | Yes | Safe | Overwrites same output path |
| `is` | Yes | Safe | Assertion-only |
| `wait` | Yes | Safe | Polling/read-only |
| `scroll` | No | Caution | Re-scroll can move context further |
| `schema` | Yes | Safe | Static metadata |

## Recipes

### Press by ref

```bash
agent-swift connect --bundle-id com.apple.TextEdit
agent-swift snapshot -i
agent-swift press @e1
```

### Click for SwiftUI navigation (direct CGEvent)

```bash
agent-swift connect --bundle-id com.example.MySwiftUIApp
agent-swift snapshot -i
agent-swift click @e4
```

### `press` fallback for SwiftUI `NavigationLink`

```bash
agent-swift find text "Settings" press
```

If AXPress is unsupported, `press` auto-falls back to click at the element center when bounds are available.

### Fill and verify

```bash
agent-swift fill @e2 "hello world"
agent-swift get text @e2
agent-swift is focused @e2
```

### Wait for state change

```bash
agent-swift wait text "Saved" --timeout 8000
agent-swift wait gone @e7
```

### Scroll workflows

```bash
agent-swift scroll down --amount 8
agent-swift scroll @e12
```

### JSON-first automation

```bash
AGENT_SWIFT_JSON=1 agent-swift status
agent-swift snapshot -i --json
agent-swift find identifier saveButton click --json
```

## `CLAUDE.md` Snippet For Your Project

Paste this into your project-level `CLAUDE.md` when you want agents to use `agent-swift`:

```md
## macOS UI Automation via agent-swift

Use `agent-swift` for native macOS UI automation.

Workflow:
1. `agent-swift doctor`
2. `agent-swift connect --bundle-id <target.bundle.id>`
3. `agent-swift snapshot -i`
4. Interact with refs (`press`, `click`, `fill`, `scroll`, `find`)
5. Verify (`get`, `is`, `wait`) and capture evidence (`screenshot`)
6. Re-run `snapshot -i` after mutating actions
7. `agent-swift disconnect`

Defaults:
- Prefer `identifier` locators, then role+text.
- Use `--json` (or `AGENT_SWIFT_JSON=1`) for machine parsing.
- Respect exit codes: 0 success, 1 assertion false (`is`), 2 error.
```
