# CLAUDE.md — agent-swift contributors

Contributor reference for `agent-swift` (`v0.2.1`).

## What this project is

`agent-swift` is a native Swift CLI that lets AI agents automate macOS apps through Accessibility APIs.

Core model:

1. `connect` to app
2. `snapshot` to generate `@eN` refs
3. act on refs (`press/click/fill/scroll/find`)
4. verify/read (`get/is/wait`)
5. `disconnect`

## Quick Command Reference (15)

| Command | Purpose | Example |
|---|---|---|
| `doctor` | Check AX trust and host readiness | `agent-swift doctor` |
| `connect` | Connect by PID or bundle ID | `agent-swift connect --bundle-id com.apple.TextEdit` |
| `disconnect` | Clear session | `agent-swift disconnect` |
| `status` | Show session state | `agent-swift status` |
| `snapshot` | Capture tree and assign refs | `agent-swift snapshot -i` |
| `press` | AXPress/AXConfirm with click fallback | `agent-swift press @e1` |
| `click` | CGEvent click by ref or coordinates | `agent-swift click @e1` |
| `fill` | Set text into element | `agent-swift fill @e2 "hello"` |
| `get` | Read element property | `agent-swift get attrs @e2` |
| `find` | Locate element + optional chained action | `agent-swift find text Save press` |
| `screenshot` | Capture app screenshot | `agent-swift screenshot /tmp/app.png` |
| `is` | Assertion (`exists/visible/enabled/focused`) | `agent-swift is exists @e1` |
| `wait` | Poll for condition or delay | `agent-swift wait text "Saved" --timeout 8000` |
| `scroll` | Scroll direction or ref into view | `agent-swift scroll down --amount 6` |
| `schema` | Command metadata JSON | `agent-swift schema` |

## Project Structure

```text
Sources/
  agent-swift/
    main.swift                          # CLI entry point and all command implementations
  AgentSwiftLib/
    AX/
      AXClient.swift                    # AX tree walk, role mapping, actions, screenshot/click helpers
    Session/
      SessionStore.swift                # session persistence and AGENT_SWIFT_HOME handling
    Output/
      SnapshotFormatter.swift           # human + JSON snapshot output
      JsonEnvelope.swift                # error envelope and JSON helpers
      CommandSchema.swift               # schema model used by `schema` command
Tests/
  agent-swiftTests/                     # unit tests for mappings, behavior, output contracts
assets/
  e2e-demo.gif
install.sh
```

## Build and Test

```bash
# Debug build
swift build

# Run tests
swift test

# Release build
swift build -c release

# Universal release binary
swift build -c release --arch arm64 --arch x86_64
```

## Key Conventions

- Exit codes:
1. `0` success
2. `1` assertion false (`is` only)
3. `2` all other errors
- Refs:
1. Format is `@eN`
2. Ref index is snapshot-order based and can become stale after UI mutation
3. Re-run `snapshot` (often `snapshot -i`) after mutating actions
- Session:
1. Default path: `~/.agent-swift/session.json`
2. Override directory via `AGENT_SWIFT_HOME`
3. `disconnect` clears session file
- JSON mode resolution order:
1. `--json`
2. `AGENT_SWIFT_JSON=1`
3. non-TTY stdout auto-enables JSON
- Wait timeout resolution order:
1. `wait --timeout <ms>`
2. `AGENT_SWIFT_TIMEOUT`
3. default `5000`

## Development Notes

- Keep CLI output deterministic and script-friendly.
- Preserve error envelope contract in JSON mode:
  `{"error":{"code","message","hint","diagnosticId"}}`
- Maintain schema parity in `allSchemas()` when adding/changing commands.
- `press` fallback to CGEvent click is intentional for SwiftUI `NavigationLink` behavior.

## Release Process

1. Update version string in `Sources/agent-swift/main.swift` (`CommandConfiguration.version`).
2. Run `swift test` and ensure green.
3. Build release binary (`swift build -c release --arch arm64 --arch x86_64`).
4. Package tarball + checksum matching `install.sh` expectations: `agent-swift-<version>-macos-universal.tar.gz` and `.sha256`.
5. Create GitHub release tag `v<version>` and upload artifacts.
6. Verify install paths:
   `brew install beastoin/tap/agent-swift`
   `curl -fsSL https://raw.githubusercontent.com/beastoin/agent-swift/main/install.sh | sh`
7. Sanity check:
   `agent-swift --version`
   `agent-swift schema`
   `agent-swift doctor`
