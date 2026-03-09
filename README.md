# agent-swift

CLI for AI agents to control macOS apps via the Accessibility API.

## Install

### Homebrew (recommended)

```bash
brew install beastoin/tap/agent-swift
```

### Shell script

```bash
curl -fsSL https://raw.githubusercontent.com/beastoin/agent-swift/main/install.sh | sh
```

### Build from source

```bash
git clone https://github.com/beastoin/agent-swift.git
cd agent-swift
swift build -c release
cp .build/release/agent-swift /usr/local/bin/
```

## Prerequisites

1. **macOS 13+** (Ventura or later)
2. **Accessibility permission** — grant your terminal in System Settings > Privacy & Security > Accessibility

## Quick start

```bash
# Verify setup
agent-swift doctor

# Connect to an app
agent-swift connect --bundle-id com.apple.TextEdit

# See interactive elements with @refs
agent-swift snapshot -i

# Tap an element
agent-swift press @e3

# Check status
agent-swift status

# Disconnect
agent-swift disconnect
```

## Commands

| Command | Description |
|---------|-------------|
| `doctor` | Check prerequisites (Accessibility access, target app) |
| `connect` | Connect to app by `--pid` or `--bundle-id` |
| `disconnect` | End session |
| `status` | Show connection state |
| `snapshot` | Capture element tree with refs (`-i` for interactive only) |
| `press` | Tap element by ref (`@e1`) |

## JSON output

```bash
agent-swift snapshot --json
agent-swift doctor --json
agent-swift status --json
```

## For AI agents

See [AGENTS.md](AGENTS.md) for the full agent integration guide including state machine, error recovery, and recipes.

## License

MIT
