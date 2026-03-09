import ArgumentParser
import ApplicationServices
import Foundation
import AppKit
import AgentSwiftLib

struct AgentSwift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-swift",
        abstract: "CLI for AI agents to control macOS apps via Accessibility API",
        version: "0.2.1",
        subcommands: [
            DoctorCommand.self,
            ConnectCommand.self,
            DisconnectCommand.self,
            StatusCommand.self,
            SnapshotCommand.self,
            PressCommand.self,
            FillCommand.self,
            GetCommand.self,
            FindCommand.self,
            ScreenshotCommand.self,
            IsCommand.self,
            WaitCommand.self,
            ScrollCommand.self,
            ClickCommand.self,
            SchemaCommand.self
        ]
    )

}

// Resolve JSON mode: --json flag > AGENT_SWIFT_JSON env > non-TTY auto-detect
func resolveJsonMode() {
    // If --json is already in args, do nothing
    let args = CommandLine.arguments
    if args.contains("--json") { return }
    // Check env var
    if ProcessInfo.processInfo.environment["AGENT_SWIFT_JSON"] == "1" {
        setenv("AGENT_SWIFT_JSON", "1", 1)
    } else if isatty(STDOUT_FILENO) == 0 {
        // Non-TTY → auto-JSON
        setenv("AGENT_SWIFT_JSON", "1", 1)
    }
}
resolveJsonMode()

do {
    var command = try AgentSwift.parseAsRoot()
    try command.run()
} catch {
    let exitCode = AgentSwift.exitCode(for: error)
    let msg = AgentSwift.fullMessage(for: error)
    if exitCode == .success {
        // --help and --version
        if !msg.isEmpty { print(msg) }
    } else {
        // Errors -> stderr, remap all non-zero to exit 2 (agent contract)
        if !msg.isEmpty {
            FileHandle.standardError.write(Data((msg + "\n").utf8))
        }
    }
    Darwin.exit(exitCode.rawValue == 0 ? 0 : exitCode.rawValue == 1 ? 1 : 2)
}

// MARK: - Global options

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Output JSON")
    var json = false

    /// Resolved JSON mode: flag > env var > TTY detection
    var useJson: Bool {
        return json || ProcessInfo.processInfo.environment["AGENT_SWIFT_JSON"] == "1"
    }
}

// MARK: - Doctor

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "doctor", abstract: "Check prerequisites and diagnose issues")

    @OptionGroup var globals: GlobalOptions

    struct Check: Codable {
        let name: String
        let status: String
        let message: String
        var fix: String?
    }

    struct DoctorResult: Codable {
        let checks: [Check]
        let allPass: Bool
    }

    func run() throws {
        var checks: [Check] = []

        let trusted = AXClient.isTrusted(prompt: false)
        checks.append(Check(
            name: "accessibility",
            status: trusted ? "pass" : "fail",
            message: trusted ? "Accessibility access granted" : "Accessibility access NOT granted",
            fix: trusted ? nil : "Grant access in System Settings > Privacy & Security > Accessibility"
        ))

        let session = SessionStore().load()
        if session.isConnected, let pid = session.pid {
            let running = AXClient.isProcessRunning(pid: pid)
            checks.append(Check(
                name: "target_app",
                status: running ? "pass" : "fail",
                message: running ? "Target app (PID \(pid)) is running" : "Target app (PID \(pid)) is NOT running",
                fix: running ? nil : "Reconnect with: agent-swift connect"
            ))
        }

        let allPass = checks.allSatisfy { $0.status == "pass" }
        let result = DoctorResult(checks: checks, allPass: allPass)

        if globals.useJson {
            print(Output.json(result))
        } else {
            for check in checks {
                let icon = check.status == "pass" ? "✓" : "✗"
                print("\(icon) \(check.message)")
                if let fix = check.fix {
                    print("  fix: \(fix)")
                }
            }
        }
    }
}

// MARK: - Connect

struct ConnectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "connect", abstract: "Connect to a macOS app")

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Process ID")
    var pid: Int?

    @Option(name: .long, help: "Bundle identifier")
    var bundleId: String?

    struct ConnectResult: Codable {
        let connected: Bool
        let pid: Int
        let bundleId: String?
        let connectedAt: String
    }

    func run() throws {
        guard AXClient.isTrusted() else {
            Output.printError(code: "AX_NOT_TRUSTED", message: "Accessibility permission not granted",
                            hint: "Grant access in System Settings > Privacy & Security > Accessibility", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let resolvedPid: Int
        let resolvedBundleId: String?

        if let p = pid {
            guard AXClient.isProcessRunning(pid: p) else {
                Output.printError(code: "APP_NOT_RUNNING", message: "No running process with PID: \(p)",
                                hint: "Check with: ps -p \(p)", useJson: globals.useJson)
                throw ExitCode(2)
            }
            resolvedPid = p
            // Resolve bundleId from PID if not provided
            resolvedBundleId = bundleId ?? NSRunningApplication(processIdentifier: pid_t(p))?.bundleIdentifier
        } else if let bid = bundleId {
            guard let p = AXClient.resolvePID(bundleId: bid) else {
                Output.printError(code: "APP_NOT_FOUND", message: "No running app with bundle ID: \(bid)",
                                hint: "Launch the app first, or use --pid", useJson: globals.useJson)
                throw ExitCode(2)
            }
            resolvedPid = p
            resolvedBundleId = bid
        } else {
            Output.printError(code: "INVALID_ARGS", message: "Must specify --pid or --bundle-id",
                            hint: "Example: agent-swift connect --bundle-id com.apple.TextEdit", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        var session = SessionData.empty
        session.pid = resolvedPid
        session.bundleId = resolvedBundleId
        session.connectedAt = now

        let store = SessionStore()
        try store.save(session)

        let result = ConnectResult(connected: true, pid: resolvedPid, bundleId: resolvedBundleId, connectedAt: now)

        if globals.useJson {
            print(Output.json(result))
        } else {
            print("Connected to PID \(resolvedPid)" + (resolvedBundleId.map { " (\($0))" } ?? ""))
        }
    }
}

// MARK: - Disconnect

struct DisconnectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "disconnect", abstract: "Disconnect from the connected app")

    @OptionGroup var globals: GlobalOptions

    func run() throws {
        let store = SessionStore()
        try store.clear()
        if globals.useJson {
            print(Output.json(["disconnected": true]))
        } else {
            print("Disconnected")
        }
    }
}

// MARK: - Status

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show connection status")

    @OptionGroup var globals: GlobalOptions

    struct StatusResult: Codable {
        let connected: Bool
        let pid: Int?
        let bundleId: String?
        let connectedAt: String?
        let refs: Int
    }

    func run() throws {
        let session = SessionStore().load()
        let result = StatusResult(
            connected: session.isConnected,
            pid: session.pid,
            bundleId: session.bundleId,
            connectedAt: session.connectedAt,
            refs: session.refs.count
        )

        if globals.useJson {
            print(Output.json(result))
        } else {
            if session.isConnected {
                print("Connected to PID \(session.pid!)" + (session.bundleId.map { " (\($0))" } ?? ""))
                print("Since: \(session.connectedAt ?? "unknown")")
                print("Refs: \(session.refs.count)")
            } else {
                print("Not connected")
            }
        }
    }
}

// MARK: - Snapshot

struct SnapshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "snapshot", abstract: "Capture element tree with refs")

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .shortAndLong, help: "Interactive elements only")
    var interactive = false

    func run() throws {
        let store = SessionStore()
        var session = store.load()

        guard session.isConnected, let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard AXClient.isProcessRunning(pid: pid) else {
            Output.printError(code: "APP_NOT_RUNNING", message: "Target app (PID \(pid)) is no longer running",
                            hint: "Reconnect with: agent-swift connect", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let root = AXClient.appElement(pid: pid)
        let tree = AXClient.walkTree(element: root)
        var allNodes = AXClient.flattenTree(tree)

        if interactive {
            allNodes = allNodes.filter { $0.isInteractive }
        }

        var elements: [(ref: String, node: AXNode)] = []
        var refs: [String: SessionData.RefEntry] = [:]
        for (i, node) in allNodes.enumerated() {
            let ref = "e\(i + 1)"
            elements.append((ref: ref, node: node))
            refs[ref] = node.toRefEntry()
        }

        session.refs = refs
        session.lastSnapshotAt = ISO8601DateFormatter().string(from: Date())
        session.interactiveSnapshot = interactive
        try store.save(session)

        if globals.useJson {
            print(SnapshotFormatter.formatJson(elements: elements))
        } else {
            print(SnapshotFormatter.formatHuman(elements: elements))
        }
    }
}

// MARK: - Press

struct PressCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "press", abstract: "Press element by ref")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Element ref (e.g. @e1)")
    var ref: String

    struct PressResult: Codable {
        let pressed: String
        let success: Bool
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected, let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let refKey = ref.hasPrefix("@") ? String(ref.dropFirst()) : ref
        guard session.refs[refKey] != nil else {
            Output.printError(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(ref)",
                            hint: "Re-run: agent-swift snapshot -i", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard let _ = Int(String(refKey.dropFirst())) else {
            Output.printError(code: "INVALID_INPUT", message: "Invalid ref format: \(ref)",
                            hint: "Use @eN format (e.g. @e1)", useJson: globals.useJson)
            throw ExitCode(2)
        }
        let index = Int(String(refKey.dropFirst()))! - 1

        let root = AXClient.appElement(pid: pid)
        let useInteractive = session.interactiveSnapshot ?? false

        var elements: [AXUIElement] = []
        AXClient.collectElements(element: root, interactiveOnly: useInteractive, into: &elements)

        guard index >= 0 && index < elements.count else {
            Output.printError(code: "ELEMENT_NOT_FOUND", message: "Element \(ref) no longer exists (stale ref)",
                            hint: "Re-run: agent-swift snapshot -i", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let target = elements[index]
        var acted = AXClient.performPress(element: target, actionName: "AXPress")
        if !acted {
            acted = AXClient.performPress(element: target, actionName: "AXConfirm")
        }

        // Fallback: CGEvent click when AXPress/AXConfirm fail (SwiftUI NavigationLink)
        if !acted {
            let tree = AXClient.walkTree(element: root)
            let allNodes = AXClient.flattenTree(tree)
            let nodes = useInteractive ? allNodes.filter { $0.isInteractive } : allNodes
            if index < nodes.count, let pos = nodes[index].position, let sz = nodes[index].size {
                let center = CGPoint(x: pos.x + sz.width / 2, y: pos.y + sz.height / 2)
                if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
                    app.activate()
                    Thread.sleep(forTimeInterval: 0.1)
                }
                acted = AXClient.performClick(at: center)
            }
        }

        if acted {
            if globals.useJson {
                print(Output.json(PressResult(pressed: ref, success: true)))
            } else {
                print("Pressed \(ref)")
            }
        } else {
            Output.printError(code: "ACTION_NOT_SUPPORTED", message: "Cannot press \(ref)",
                            hint: "Pick a different target from snapshot", useJson: globals.useJson)
            throw ExitCode(2)
        }
    }
}

// MARK: - Ref Resolution Helper

struct ResolvedRef {
    let refKey: String
    let index: Int
    let element: AXUIElement
    let node: AXNode
}

func resolveRef(_ ref: String, session: SessionData, pid: Int, useJson: Bool) throws -> ResolvedRef {
    let refKey = ref.hasPrefix("@") ? String(ref.dropFirst()) : ref
    guard session.refs[refKey] != nil else {
        Output.printError(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(ref)",
                        hint: "Re-run: agent-swift snapshot -i", useJson: useJson)
        throw ExitCode(2)
    }

    guard let _ = Int(String(refKey.dropFirst())) else {
        Output.printError(code: "INVALID_INPUT", message: "Invalid ref format: \(ref)",
                        hint: "Use @eN format (e.g. @e1)", useJson: useJson)
        throw ExitCode(2)
    }
    let index = Int(String(refKey.dropFirst()))! - 1

    let root = AXClient.appElement(pid: pid)
    let useInteractive = session.interactiveSnapshot ?? false

    var elements: [AXUIElement] = []
    AXClient.collectElements(element: root, interactiveOnly: useInteractive, into: &elements)

    guard index >= 0 && index < elements.count else {
        Output.printError(code: "ELEMENT_NOT_FOUND", message: "Element \(ref) no longer exists (stale ref)",
                        hint: "Re-run: agent-swift snapshot -i", useJson: useJson)
        throw ExitCode(2)
    }

    let tree = AXClient.walkTree(element: root)
    let allNodes = AXClient.flattenTree(tree)
    let nodes = useInteractive ? allNodes.filter { $0.isInteractive } : allNodes

    let node = index < nodes.count ? nodes[index] : AXNode(
        role: "AXUnknown", subrole: nil, title: nil, axDescription: nil, value: nil,
        identifier: nil, childStaticText: nil, enabled: false, focused: false,
        position: nil, size: nil, actions: [], children: [])

    return ResolvedRef(refKey: refKey, index: index, element: elements[index], node: node)
}

// MARK: - Fill

struct FillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "fill", abstract: "Enter text into element by ref")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Element ref (e.g. @e1)")
    var ref: String

    @Argument(help: "Text to enter")
    var text: String

    struct FillResult: Codable {
        let filled: String
        let text: String
        let success: Bool
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected, let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let resolved = try resolveRef(ref, session: session, pid: pid, useJson: globals.useJson)
        let success = AXClient.performFill(element: resolved.element, text: text)

        if success {
            if globals.useJson {
                print(Output.json(FillResult(filled: ref, text: text, success: true)))
            } else {
                print("Filled \(ref) with \"\(text)\"")
            }
        } else {
            Output.printError(code: "ACTION_NOT_SUPPORTED", message: "Cannot fill \(ref)",
                            hint: "Element may not accept text input. Use a textfield or textarea.", useJson: globals.useJson)
            throw ExitCode(2)
        }
    }
}

// MARK: - Get

struct GetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Read element property by ref")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Property: text, type, role, identifier, or attrs")
    var property: String

    @Argument(help: "Element ref (e.g. @e1)")
    var ref: String

    struct GetResult: Codable {
        let ref: String
        let property: String
        let value: String?
    }

    struct AttrsResult: Codable {
        let ref: String
        let role: String
        let type: String
        let label: String?
        let identifier: String?
        let value: String?
        let enabled: Bool
        let focused: Bool
        let bounds: SessionData.RefEntry.Bounds?
        let actions: [String]
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected, let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let resolved = try resolveRef(ref, session: session, pid: pid, useJson: globals.useJson)
        let node = resolved.node

        switch property {
        case "text":
            let text = node.displayLabel
            if globals.useJson {
                print(Output.json(GetResult(ref: ref, property: "text", value: text)))
            } else {
                print(text ?? "")
            }
        case "type":
            let type = node.displayType
            if globals.useJson {
                print(Output.json(GetResult(ref: ref, property: "type", value: type)))
            } else {
                print(type)
            }
        case "role":
            if globals.useJson {
                print(Output.json(GetResult(ref: ref, property: "role", value: node.role)))
            } else {
                print(node.role)
            }
        case "identifier":
            if globals.useJson {
                print(Output.json(GetResult(ref: ref, property: "identifier", value: node.identifier)))
            } else {
                print(node.identifier ?? "")
            }
        case "attrs":
            let attrs = AttrsResult(
                ref: ref,
                role: node.role,
                type: node.displayType,
                label: node.displayLabel,
                identifier: node.identifier,
                value: node.value,
                enabled: node.enabled,
                focused: node.focused,
                bounds: node.bounds,
                actions: node.actions
            )
            if globals.useJson {
                print(Output.json(attrs))
            } else {
                print("role: \(node.role)")
                print("type: \(node.displayType)")
                if let label = node.displayLabel { print("label: \(label)") }
                if let id = node.identifier { print("identifier: \(id)") }
                if let val = node.value { print("value: \(val)") }
                print("enabled: \(node.enabled)")
                print("focused: \(node.focused)")
                if let b = node.bounds { print("bounds: \(b.x),\(b.y) \(b.width)x\(b.height)") }
                if !node.actions.isEmpty { print("actions: \(node.actions.joined(separator: ", "))") }
            }
        default:
            Output.printError(code: "INVALID_ARGS", message: "Unknown property: \(property)",
                            hint: "Use: text, type, role, identifier, or attrs", useJson: globals.useJson)
            throw ExitCode(2)
        }
    }
}

// MARK: - Find

struct FindCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "find", abstract: "Find element by locator")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Locator type: role, text, or identifier")
    var locator: String

    @Argument(help: "Value to match")
    var value: String

    @Argument(help: "Optional chained action: press, click, fill, or get")
    var action: String?

    @Argument(help: "Action argument (text for fill, property for get)")
    var actionArg: String?

    struct FindResult: Codable {
        let ref: String
        let type: String
        let label: String?
        let identifier: String?
    }

    struct FindActionResult: Codable {
        let found: String
        let action: String
        let success: Bool
    }

    struct FindFillResult: Codable {
        let found: String
        let action: String
        let text: String
        let success: Bool
    }

    struct FindGetResult: Codable {
        let found: String
        let action: String
        let property: String
        let value: String
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected, let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        // Walk tree to get nodes
        let root = AXClient.appElement(pid: pid)
        let tree = AXClient.walkTree(element: root)
        let allNodes = AXClient.flattenTree(tree)
        let useInteractive = session.interactiveSnapshot ?? false
        let nodes = useInteractive ? allNodes.filter { $0.isInteractive } : allNodes

        // Find matching element
        var matchIndex: Int? = nil
        for (i, node) in nodes.enumerated() {
            switch locator {
            case "role":
                if node.role == value || node.displayType == value {
                    matchIndex = i
                }
            case "text":
                if let label = node.displayLabel, label.contains(value) {
                    matchIndex = i
                }
            case "identifier":
                if node.identifier == value {
                    matchIndex = i
                }
            default:
                Output.printError(code: "INVALID_ARGS", message: "Unknown locator: \(locator)",
                                hint: "Use: role, text, or identifier", useJson: globals.useJson)
                throw ExitCode(2)
            }
            if matchIndex != nil { break }
        }

        guard let idx = matchIndex else {
            Output.printError(code: "ELEMENT_NOT_FOUND", message: "No element matches \(locator)=\"\(value)\"",
                            hint: "Re-run: agent-swift snapshot -i", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let matchedNode = nodes[idx]
        let matchedRef = "@e\(idx + 1)"

        // If no chained action, just print the match
        guard let action = action else {
            if globals.useJson {
                print(Output.json(FindResult(ref: matchedRef, type: matchedNode.displayType,
                                            label: matchedNode.displayLabel, identifier: matchedNode.identifier)))
            } else {
                var line = "\(matchedRef) [\(matchedNode.displayType)]"
                if let label = matchedNode.displayLabel { line += " \"\(label)\"" }
                if let id = matchedNode.identifier { line += "  identifier=\(id)" }
                print(line)
            }
            return
        }

        // Resolve AXUIElement for chained action
        var elements: [AXUIElement] = []
        AXClient.collectElements(element: root, interactiveOnly: useInteractive, into: &elements)

        guard idx < elements.count else {
            Output.printError(code: "ELEMENT_NOT_FOUND", message: "Element \(matchedRef) no longer exists",
                            hint: "Re-run: agent-swift snapshot -i", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let target = elements[idx]

        switch action {
        case "press":
            var acted = AXClient.performPress(element: target, actionName: "AXPress")
            if !acted { acted = AXClient.performPress(element: target, actionName: "AXConfirm") }
            // Fallback: CGEvent click when AXPress/AXConfirm fail (SwiftUI NavigationLink)
            if !acted, let pos = matchedNode.position, let sz = matchedNode.size {
                let center = CGPoint(x: pos.x + sz.width / 2, y: pos.y + sz.height / 2)
                if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
                    app.activate()
                    Thread.sleep(forTimeInterval: 0.1)
                }
                acted = AXClient.performClick(at: center)
            }
            if acted {
                if globals.useJson {
                    print(Output.json(FindActionResult(found: matchedRef, action: "press", success: true)))
                } else {
                    print("Found \(matchedRef) → pressed")
                }
            } else {
                Output.printError(code: "ACTION_NOT_SUPPORTED", message: "Cannot press \(matchedRef)",
                                hint: "Pick a different target", useJson: globals.useJson)
                throw ExitCode(2)
            }
        case "click":
            guard let pos = matchedNode.position, let sz = matchedNode.size else {
                Output.printError(code: "NO_BOUNDS", message: "Element \(matchedRef) has no position/size",
                                hint: "Element may be offscreen", useJson: globals.useJson)
                throw ExitCode(2)
            }
            let center = CGPoint(x: pos.x + sz.width / 2, y: pos.y + sz.height / 2)
            if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
                app.activate()
                Thread.sleep(forTimeInterval: 0.1)
            }
            if AXClient.performClick(at: center) {
                if globals.useJson {
                    print(Output.json(FindActionResult(found: matchedRef, action: "click", success: true)))
                } else {
                    print("Found \(matchedRef) → clicked at (\(Int(center.x)), \(Int(center.y)))")
                }
            } else {
                Output.printError(code: "CLICK_FAILED", message: "Failed to click \(matchedRef)",
                                hint: "Ensure Accessibility permission is granted", useJson: globals.useJson)
                throw ExitCode(2)
            }
        case "fill":
            guard let text = actionArg else {
                Output.printError(code: "INVALID_ARGS", message: "fill requires text argument",
                                hint: "Example: agent-swift find identifier \"field\" fill \"text\"", useJson: globals.useJson)
                throw ExitCode(2)
            }
            let success = AXClient.performFill(element: target, text: text)
            if success {
                if globals.useJson {
                    print(Output.json(FindFillResult(found: matchedRef, action: "fill", text: text, success: true)))
                } else {
                    print("Found \(matchedRef) → filled with \"\(text)\"")
                }
            } else {
                Output.printError(code: "ACTION_NOT_SUPPORTED", message: "Cannot fill \(matchedRef)",
                                hint: "Element may not accept text input", useJson: globals.useJson)
                throw ExitCode(2)
            }
        case "get":
            let prop = actionArg ?? "text"
            let val: String?
            switch prop {
            case "text": val = matchedNode.displayLabel
            case "type": val = matchedNode.displayType
            case "role": val = matchedNode.role
            case "identifier": val = matchedNode.identifier
            default: val = matchedNode.displayLabel
            }
            if globals.useJson {
                print(Output.json(FindGetResult(found: matchedRef, action: "get", property: prop, value: val ?? "")))
            } else {
                print(val ?? "")
            }
        default:
            Output.printError(code: "INVALID_ARGS", message: "Unknown action: \(action)",
                            hint: "Use: press, click, fill, or get", useJson: globals.useJson)
            throw ExitCode(2)
        }
    }
}

// MARK: - Screenshot

struct ScreenshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "screenshot", abstract: "Capture app screenshot")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Output file path (default: /tmp/agent-swift-screenshot.png)")
    var path: String?

    struct ScreenshotResult: Codable {
        let path: String
        let success: Bool
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected, let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard AXClient.isProcessRunning(pid: pid) else {
            Output.printError(code: "APP_NOT_RUNNING", message: "Target app (PID \(pid)) is no longer running",
                            hint: "Reconnect with: agent-swift connect", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let outputPath = path ?? "/tmp/agent-swift-screenshot.png"
        let success = AXClient.captureScreenshot(pid: pid, path: outputPath)

        if success {
            if globals.useJson {
                print(Output.json(ScreenshotResult(path: outputPath, success: true)))
            } else {
                print("Screenshot saved to \(outputPath)")
            }
        } else {
            Output.printError(code: "SCREENSHOT_FAILED", message: "Failed to capture screenshot",
                            hint: "Ensure the app window is visible on screen", useJson: globals.useJson)
            throw ExitCode(2)
        }
    }
}

// MARK: - Is

struct IsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "is", abstract: "Assert element condition")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Condition: exists, visible, enabled, or focused")
    var condition: String

    @Argument(help: "Element ref (e.g. @e1)")
    var ref: String

    struct IsResult: Codable {
        let ref: String
        let condition: String
        let result: Bool
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard ["exists", "visible", "enabled", "focused"].contains(condition) else {
            Output.printError(code: "INVALID_ARGS", message: "Unknown condition: \(condition)",
                            hint: "Use: exists, visible, enabled, or focused", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard session.isConnected, let pid = session.pid else {
            // No session: element can't exist/be visible/enabled/focused → assertion false
            if globals.useJson {
                print(Output.json(IsResult(ref: ref, condition: condition, result: false)))
            } else {
                print("false")
            }
            throw ExitCode(1)
        }

        let refKey = ref.hasPrefix("@") ? String(ref.dropFirst()) : ref

        // For "exists", we check if the ref resolves at all
        let root = AXClient.appElement(pid: pid)
        let tree = AXClient.walkTree(element: root)
        let allNodes = AXClient.flattenTree(tree)
        let useInteractive = session.interactiveSnapshot ?? false
        let nodes = useInteractive ? allNodes.filter { $0.isInteractive } : allNodes

        guard let numIndex = Int(String(refKey.dropFirst())) else {
            Output.printError(code: "INVALID_INPUT", message: "Invalid ref format: \(ref)",
                            hint: "Use @eN format (e.g. @e1)", useJson: globals.useJson)
            throw ExitCode(2)
        }
        let index = numIndex - 1

        let elementExists = index >= 0 && index < nodes.count
        let result: Bool

        switch condition {
        case "exists":
            result = elementExists
        case "visible":
            result = elementExists && nodes[index].position != nil && nodes[index].size != nil
        case "enabled":
            result = elementExists && nodes[index].enabled
        case "focused":
            result = elementExists && nodes[index].focused
        default:
            result = false
        }

        if globals.useJson {
            print(Output.json(IsResult(ref: ref, condition: condition, result: result)))
        } else {
            print(result ? "true" : "false")
        }

        // Exit 0 for true, exit 1 for false (NOT exit 2 — 1 means assertion false)
        if !result {
            throw ExitCode(1)
        }
    }
}

// MARK: - Wait

struct WaitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "wait", abstract: "Wait for condition or delay")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Condition (exists, visible, text, gone) or delay in ms")
    var condition: String

    @Argument(help: "Target: ref (@e1) or text to match")
    var target: String?

    @Option(name: .long, help: "Timeout in ms (default: 5000, or AGENT_SWIFT_TIMEOUT)")
    var timeout: Int?

    @Option(name: .long, help: "Poll interval in ms (default: 250)")
    var interval: Int = 250

    /// Resolved timeout: --timeout flag > AGENT_SWIFT_TIMEOUT env > 5000ms default
    var resolvedTimeout: Int {
        if let t = timeout { return t }
        if let envStr = ProcessInfo.processInfo.environment["AGENT_SWIFT_TIMEOUT"],
           let envVal = Int(envStr) { return envVal }
        return 5000
    }

    struct WaitResult: Codable {
        let condition: String
        let target: String?
        let success: Bool
        let elapsed: Int
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        // Simple delay: wait <ms>
        if let delayMs = Int(condition) {
            Thread.sleep(forTimeInterval: Double(delayMs) / 1000.0)
            if globals.useJson {
                print(Output.json(WaitResult(condition: "delay", target: "\(delayMs)ms", success: true, elapsed: delayMs)))
            } else {
                print("Waited \(delayMs)ms")
            }
            return
        }

        guard session.isConnected, let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard ["exists", "visible", "text", "gone"].contains(condition) else {
            Output.printError(code: "INVALID_ARGS", message: "Unknown condition: \(condition)",
                            hint: "Use: exists, visible, text, gone, or a delay in ms", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard let target = target else {
            Output.printError(code: "INVALID_ARGS", message: "Missing target for condition '\(condition)'",
                            hint: "Example: agent-swift wait exists @e1", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let useInteractive = session.interactiveSnapshot ?? false
        let startTime = Date()
        let timeoutSec = Double(resolvedTimeout) / 1000.0
        let intervalSec = Double(interval) / 1000.0

        while true {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed >= timeoutSec {
                Output.printError(code: "TIMEOUT", message: "Timed out waiting for \(condition) \(target) after \(resolvedTimeout)ms",
                                hint: "Increase --timeout or verify target state", useJson: globals.useJson)
                throw ExitCode(2)
            }

            let root = AXClient.appElement(pid: pid)
            let tree = AXClient.walkTree(element: root)
            let allNodes = AXClient.flattenTree(tree)
            let nodes = useInteractive ? allNodes.filter { $0.isInteractive } : allNodes

            var conditionMet = false

            switch condition {
            case "exists":
                let refKey = target.hasPrefix("@") ? String(target.dropFirst()) : target
                if let numIndex = Int(String(refKey.dropFirst())) {
                    conditionMet = (numIndex - 1) >= 0 && (numIndex - 1) < nodes.count
                }
            case "visible":
                let refKey = target.hasPrefix("@") ? String(target.dropFirst()) : target
                if let numIndex = Int(String(refKey.dropFirst())) {
                    let idx = numIndex - 1
                    if idx >= 0 && idx < nodes.count {
                        conditionMet = nodes[idx].position != nil && nodes[idx].size != nil
                    }
                }
            case "text":
                conditionMet = nodes.contains { node in
                    node.displayLabel?.contains(target) == true
                }
            case "gone":
                let refKey = target.hasPrefix("@") ? String(target.dropFirst()) : target
                if let numIndex = Int(String(refKey.dropFirst())) {
                    conditionMet = (numIndex - 1) < 0 || (numIndex - 1) >= nodes.count
                }
            default:
                break
            }

            if conditionMet {
                let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
                if globals.useJson {
                    print(Output.json(WaitResult(condition: condition, target: target, success: true, elapsed: elapsedMs)))
                } else {
                    print("Condition met: \(condition) \(target) (\(elapsedMs)ms)")
                }
                return
            }

            Thread.sleep(forTimeInterval: intervalSec)
        }
    }
}

// MARK: - Scroll

struct ScrollCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "scroll", abstract: "Scroll by direction or element ref")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Target: @ref, up, or down")
    var target: String

    @Option(name: .long, help: "Scroll amount in lines (default: 5)")
    var amount: Int = 5

    struct ScrollResult: Codable {
        let target: String
        let success: Bool
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected, let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard AXClient.isProcessRunning(pid: pid) else {
            Output.printError(code: "APP_NOT_RUNNING", message: "Target app (PID \(pid)) is no longer running",
                            hint: "Reconnect with: agent-swift connect", useJson: globals.useJson)
            throw ExitCode(2)
        }

        switch target {
        case "up", "down":
            let scrollAmount = target == "up" ? Int32(amount) : -Int32(amount)
            if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: scrollAmount, wheel2: 0, wheel3: 0) {
                // Bring app to front
                if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
                    app.activate()
                    Thread.sleep(forTimeInterval: 0.1)
                }
                event.post(tap: .cgSessionEventTap)
                if globals.useJson {
                    print(Output.json(ScrollResult(target: target, success: true)))
                } else {
                    print("Scrolled \(target)")
                }
            } else {
                Output.printError(code: "SCROLL_FAILED", message: "Failed to create scroll event",
                                hint: "Ensure Accessibility permission is granted", useJson: globals.useJson)
                throw ExitCode(2)
            }
        default:
            // Treat as ref — scroll element into view
            let resolved = try resolveRef(target, session: session, pid: pid, useJson: globals.useJson)
            let acted = AXClient.performPress(element: resolved.element, actionName: "AXScrollToVisible")
            if acted {
                if globals.useJson {
                    print(Output.json(ScrollResult(target: target, success: true)))
                } else {
                    print("Scrolled \(target) into view")
                }
            } else {
                // Fallback: try to scroll the parent scroll area
                Output.printError(code: "SCROLL_FAILED", message: "Cannot scroll \(target) into view",
                                hint: "Try: agent-swift scroll up/down", useJson: globals.useJson)
                throw ExitCode(2)
            }
        }
    }
}

// MARK: - Click

struct ClickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "click", abstract: "Click element or coordinates via CGEvent")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Target: @ref or x-coordinate")
    var target: String

    @Argument(help: "Y-coordinate (when using x y)")
    var y: Double?

    struct ClickResult: Codable {
        let clicked: String
        let x: Double
        let y: Double
        let success: Bool
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected, let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard AXClient.isProcessRunning(pid: pid) else {
            Output.printError(code: "APP_NOT_RUNNING", message: "Target app (PID \(pid)) is no longer running",
                            hint: "Reconnect with: agent-swift connect", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let clickPoint: CGPoint
        let clickLabel: String

        if target.hasPrefix("@") || target.hasPrefix("e") {
            // Ref-based click
            let resolved = try resolveRef(target, session: session, pid: pid, useJson: globals.useJson)
            guard let pos = resolved.node.position, let sz = resolved.node.size else {
                Output.printError(code: "NO_BOUNDS", message: "Element \(target) has no position/size",
                                hint: "Element may be offscreen. Try: agent-swift scroll \(target)", useJson: globals.useJson)
                throw ExitCode(2)
            }
            clickPoint = CGPoint(x: pos.x + sz.width / 2, y: pos.y + sz.height / 2)
            clickLabel = target.hasPrefix("@") ? target : "@\(target)"
        } else {
            // Coordinate-based click
            guard let x = Double(target), let yCoord = y else {
                Output.printError(code: "INVALID_INPUT", message: "Invalid click target: \(target)",
                                hint: "Use @eN for element ref or 'x y' for coordinates", useJson: globals.useJson)
                throw ExitCode(2)
            }
            clickPoint = CGPoint(x: x, y: yCoord)
            clickLabel = "\(Int(x)),\(Int(yCoord))"
        }

        // Bring app to front
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            app.activate()
            Thread.sleep(forTimeInterval: 0.1)
        }

        if AXClient.performClick(at: clickPoint) {
            if globals.useJson {
                print(Output.json(ClickResult(clicked: clickLabel, x: clickPoint.x, y: clickPoint.y, success: true)))
            } else {
                print("Clicked \(clickLabel) at (\(Int(clickPoint.x)), \(Int(clickPoint.y)))")
            }
        } else {
            Output.printError(code: "CLICK_FAILED", message: "Failed to create click event",
                            hint: "Ensure Accessibility permission is granted", useJson: globals.useJson)
            throw ExitCode(2)
        }
    }
}

// MARK: - Schema

// CommandSchema is defined in AgentSwiftLib/Output/CommandSchema.swift

func allSchemas() -> [CommandSchema] { return [
    CommandSchema(name: "doctor", description: "Check prerequisites and diagnose issues",
        args: [], flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "connect", description: "Connect to a macOS app",
        args: [], flags: [
            .init(name: "--pid", type: "int", defaultValue: nil),
            .init(name: "--bundle-id", type: "string", defaultValue: nil),
            .init(name: "--json", type: "bool", defaultValue: "false")
        ], exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "disconnect", description: "Disconnect from app",
        args: [], flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "status", description: "Show connection state",
        args: [], flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "snapshot", description: "Capture element tree with refs",
        args: [], flags: [
            .init(name: "-i", type: "bool", defaultValue: "false"),
            .init(name: "--json", type: "bool", defaultValue: "false")
        ], exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "press", description: "Press element by ref",
        args: [.init(name: "ref", type: "string", required: true)],
        flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "fill", description: "Enter text into element by ref",
        args: [.init(name: "ref", type: "string", required: true), .init(name: "text", type: "string", required: true)],
        flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "get", description: "Read element property by ref",
        args: [.init(name: "property", type: "string", required: true), .init(name: "ref", type: "string", required: true)],
        flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "find", description: "Find element by locator",
        args: [.init(name: "locator", type: "string", required: true), .init(name: "value", type: "string", required: true),
               .init(name: "action", type: "string", required: false), .init(name: "actionArg", type: "string", required: false)],
        flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "screenshot", description: "Capture app screenshot",
        args: [.init(name: "path", type: "string", required: false)],
        flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "is", description: "Assert element condition",
        args: [.init(name: "condition", type: "string", required: true), .init(name: "ref", type: "string", required: true)],
        flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "assertion true", "1": "assertion false", "2": "error"]),
    CommandSchema(name: "wait", description: "Wait for condition or delay",
        args: [.init(name: "condition", type: "string", required: true), .init(name: "target", type: "string", required: false)],
        flags: [
            .init(name: "--timeout", type: "int", defaultValue: "5000"),
            .init(name: "--interval", type: "int", defaultValue: "250"),
            .init(name: "--json", type: "bool", defaultValue: "false")
        ], exitCodes: ["0": "success", "2": "error/timeout"]),
    CommandSchema(name: "scroll", description: "Scroll element or direction",
        args: [.init(name: "target", type: "string", required: true)],
        flags: [
            .init(name: "--amount", type: "int", defaultValue: "5"),
            .init(name: "--json", type: "bool", defaultValue: "false")
        ], exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "click", description: "Click element or coordinates via CGEvent",
        args: [.init(name: "target", type: "string", required: true),
               .init(name: "y", type: "number", required: false)],
        flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "schema", description: "Show command schema",
        args: [.init(name: "command", type: "string", required: false)],
        flags: [], exitCodes: ["0": "success", "2": "error"]),
]}

struct SchemaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "schema", abstract: "Show command schema")

    @Argument(help: "Command name (omit for all)")
    var command: String?

    func run() throws {
        if let cmd = command {
            guard let schema = allSchemas().first(where: { $0.name == cmd }) else {
                Output.printError(code: "INVALID_ARGS", message: "Unknown command: \(cmd)",
                                hint: "Run: agent-swift schema", useJson: true)
                throw ExitCode(2)
            }
            print(Output.json(schema))
        } else {
            print(Output.json(allSchemas()))
        }
    }
}
