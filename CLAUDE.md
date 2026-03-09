# agent-swift

CLI for AI agents to control macOS apps via the Accessibility API.

## Quick Reference

| Command | Description |
|---------|-------------|
| `agent-swift doctor` | Check prerequisites (AX access, target app) |
| `agent-swift connect --bundle-id <id>` | Connect to app |
| `agent-swift snapshot -i` | List interactive elements with @refs |
| `agent-swift press @e3` | Tap element by ref |
| `agent-swift status` | Show connection state |
| `agent-swift disconnect` | End session |

All commands support `--json` flag for structured output.

## Build & Test

```bash
swift build                    # debug build
swift test                     # run tests
swift build -c release --arch arm64 --arch x86_64  # universal binary
```

## Project Structure

```
Sources/
  agent-swift/main.swift              # CLI entry point, all subcommands
  AgentSwiftLib/
    AX/AXClient.swift                 # Accessibility API wrapper
    Session/SessionStore.swift        # File-based session persistence
    Output/SnapshotFormatter.swift    # Human/JSON output formatting
    Output/JsonEnvelope.swift         # Shared JSON helpers
Tests/
  agent-swiftTests/                   # Unit tests
```

## Key Conventions

- Exit codes: 0 = success, 1 = assertion false, 2 = error
- Refs format: `@e1`, `@e2`, etc. — assigned per snapshot, invalidated by UI changes
- Session stored at `~/.agent-swift/session.json`
- Error JSON: `{"error": {"code": "...", "message": "...", "hint": "..."}}`
- All mutating actions (press) make refs stale — re-run `snapshot` after

## Release Process

No CI — manual release. See `install.sh` for the install script.
Full release steps are in jin's playbook (`~/team/jin/playbook.md`).

## See Also

- `AGENTS.md` — full agent workflow guide with state machine, recipes, error recovery
