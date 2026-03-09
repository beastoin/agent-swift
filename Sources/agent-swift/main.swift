import ArgumentParser
import ApplicationServices
import Foundation
import AppKit
import AgentSwiftLib

struct AgentSwift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-swift",
        abstract: "CLI for AI agents to control macOS apps via Accessibility API",
        version: "0.1.0",
        subcommands: [
            DoctorCommand.self,
            ConnectCommand.self,
            DisconnectCommand.self,
            StatusCommand.self,
            SnapshotCommand.self,
            PressCommand.self
        ]
    )

}

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
    Darwin.exit(exitCode == .success ? 0 : 2)
}

// MARK: - Global options

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Output JSON")
    var json = false
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

        if globals.json {
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
                            hint: "Grant access in System Settings > Privacy & Security > Accessibility", useJson: globals.json)
            throw ExitCode(2)
        }

        let resolvedPid: Int
        let resolvedBundleId: String?

        if let p = pid {
            guard AXClient.isProcessRunning(pid: p) else {
                Output.printError(code: "APP_NOT_RUNNING", message: "No running process with PID: \(p)",
                                hint: "Check with: ps -p \(p)", useJson: globals.json)
                throw ExitCode(2)
            }
            resolvedPid = p
            // Resolve bundleId from PID if not provided
            resolvedBundleId = bundleId ?? NSRunningApplication(processIdentifier: pid_t(p))?.bundleIdentifier
        } else if let bid = bundleId {
            guard let p = AXClient.resolvePID(bundleId: bid) else {
                Output.printError(code: "APP_NOT_FOUND", message: "No running app with bundle ID: \(bid)",
                                hint: "Launch the app first, or use --pid", useJson: globals.json)
                throw ExitCode(2)
            }
            resolvedPid = p
            resolvedBundleId = bid
        } else {
            Output.printError(code: "INVALID_ARGS", message: "Must specify --pid or --bundle-id",
                            hint: "Example: agent-swift connect --bundle-id com.apple.TextEdit", useJson: globals.json)
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

        if globals.json {
            print(Output.json(result))
        } else {
            print("Connected to PID \(resolvedPid)" + (resolvedBundleId.map { " (\($0))" } ?? ""))
        }
    }
}

// MARK: - Disconnect

struct DisconnectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "disconnect", abstract: "Disconnect from app")

    @OptionGroup var globals: GlobalOptions

    func run() throws {
        let store = SessionStore()
        try store.clear()
        if globals.json {
            print(Output.json(["disconnected": true]))
        } else {
            print("Disconnected")
        }
    }
}

// MARK: - Status

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show connection state")

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

        if globals.json {
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
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.json)
            throw ExitCode(2)
        }

        guard AXClient.isProcessRunning(pid: pid) else {
            Output.printError(code: "APP_NOT_RUNNING", message: "Target app (PID \(pid)) is no longer running",
                            hint: "Reconnect with: agent-swift connect", useJson: globals.json)
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
        try store.save(session)

        if globals.json {
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
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.json)
            throw ExitCode(2)
        }

        let refKey = ref.hasPrefix("@") ? String(ref.dropFirst()) : ref
        guard session.refs[refKey] != nil else {
            Output.printError(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(ref)",
                            hint: "Re-run: agent-swift snapshot -i", useJson: globals.json)
            throw ExitCode(2)
        }

        guard let numStr = refKey.dropFirst().first.map({ String($0) }) ?? nil,
              let _ = Int(String(refKey.dropFirst())) else {
            Output.printError(code: "INVALID_INPUT", message: "Invalid ref format: \(ref)",
                            hint: "Use @eN format (e.g. @e1)", useJson: globals.json)
            throw ExitCode(2)
        }
        let index = Int(String(refKey.dropFirst()))! - 1

        let root = AXClient.appElement(pid: pid)
        let tree = AXClient.walkTree(element: root)
        let allNodes = AXClient.flattenTree(tree)
        let interactiveNodes = allNodes.filter { $0.isInteractive }
        let useInteractive = session.refs.count == interactiveNodes.count && session.refs.count != allNodes.count

        var elements: [AXUIElement] = []
        AXClient.collectElements(element: root, interactiveOnly: useInteractive, into: &elements)

        guard index >= 0 && index < elements.count else {
            Output.printError(code: "ELEMENT_NOT_FOUND", message: "Element \(ref) no longer exists (stale ref)",
                            hint: "Re-run: agent-swift snapshot -i", useJson: globals.json)
            throw ExitCode(2)
        }

        let target = elements[index]
        var acted = AXClient.performPress(element: target, actionName: "AXPress")
        if !acted {
            acted = AXClient.performPress(element: target, actionName: "AXConfirm")
        }

        if acted {
            if globals.json {
                print(Output.json(PressResult(pressed: ref, success: true)))
            } else {
                print("Pressed \(ref)")
            }
        } else {
            Output.printError(code: "ACTION_NOT_SUPPORTED", message: "Cannot press \(ref)",
                            hint: "Pick a different target from snapshot", useJson: globals.json)
            throw ExitCode(2)
        }
    }
}
