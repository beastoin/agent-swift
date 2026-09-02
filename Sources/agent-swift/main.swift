import ArgumentParser
import ApplicationServices
import Foundation
import AppKit
import Vision
import AgentSwiftLib

struct AgentSwift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-swift",
        abstract: "CLI for AI agents to control macOS apps via Accessibility API",
        version: "0.10.0",
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
            TypeCommand.self,
            SwipeCommand.self,
            RecordCommand.self,
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

        let session = SessionStore().load()

        if session.isMirrorMode {
            let mirrorRunning = MirrorBridge.isRunning()
            checks.append(Check(
                name: "iphone_mirroring",
                status: mirrorRunning ? "pass" : "fail",
                message: mirrorRunning ? "iPhone Mirroring is running" : "iPhone Mirroring is not running",
                fix: mirrorRunning ? nil : "Open iPhone Mirroring: open -a 'iPhone Mirroring'"
            ))

            let axTrusted = AXClient.isTrusted(prompt: false)
            checks.append(Check(
                name: "accessibility",
                status: axTrusted ? "pass" : "fail",
                message: axTrusted ? "Accessibility access granted" : "Accessibility access NOT granted",
                fix: axTrusted ? nil : "Grant access in System Settings > Privacy & Security > Accessibility"
            ))
        } else if session.isSimulatorMode {
            let idbAvail = IdbBridge.isIdbAvailable()
            checks.append(Check(
                name: "idb",
                status: idbAvail ? "pass" : "fail",
                message: idbAvail ? "idb CLI available" : "idb CLI not found",
                fix: idbAvail ? nil : "Install: brew install facebook/fb/idb-companion facebook/fb/idb-cli"
            ))

            if let udid = session.simulatorUDID {
                let bridge = SimulatorBridge(udid: udid)
                let devices = (try? SimulatorBridge.listDevices()) ?? []
                let booted = devices.first(where: { $0.udid == udid && $0.isBooted })
                checks.append(Check(
                    name: "simulator",
                    status: booted != nil ? "pass" : "fail",
                    message: booted != nil ? "Simulator \(session.simulatorDeviceType ?? udid) is booted" : "Simulator \(udid) is not booted",
                    fix: booted != nil ? nil : "Boot simulator: xcrun simctl boot \(udid)"
                ))
                _ = bridge
            }
        } else {
            let trusted = AXClient.isTrusted(prompt: false)
            checks.append(Check(
                name: "accessibility",
                status: trusted ? "pass" : "fail",
                message: trusted ? "Accessibility access granted" : "Accessibility access NOT granted",
                fix: trusted ? nil : "Grant access in System Settings > Privacy & Security > Accessibility"
            ))

            if session.isConnected, let pid = session.pid {
                let running = AXClient.isProcessRunning(pid: pid)
                checks.append(Check(
                    name: "target_app",
                    status: running ? "pass" : "fail",
                    message: running ? "Target app (PID \(pid)) is running" : "Target app (PID \(pid)) is NOT running",
                    fix: running ? nil : "Reconnect with: agent-swift connect"
                ))
            }
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
    static let configuration = CommandConfiguration(commandName: "connect", abstract: "Connect to a macOS app or iOS Simulator")

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Process ID")
    var pid: Int?

    @Option(name: .long, help: "Bundle identifier")
    var bundleId: String?

    @Option(name: .long, help: "Connect to iOS Simulator (optional UDID, omit for auto-detect)")
    var simulator: String?

    @Option(name: .long, help: "Simulator UDID (alias for --simulator)")
    var udid: String?

    @Flag(name: .long, help: "Enable simulator mode (auto-detect booted device)")
    var sim = false

    @Flag(name: .long, help: "Connect via iPhone Mirroring (real device)")
    var mirror = false

    struct ConnectResult: Codable {
        let connected: Bool
        let pid: Int?
        let bundleId: String?
        let connectedAt: String
        let mode: String?
        let simulatorUDID: String?
        let simulatorDeviceType: String?
    }

    func run() throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let store = SessionStore()

        if mirror {
            try connectMirror(store: store, now: now)
            return
        }

        if sim || simulator != nil || udid != nil {
            try connectSimulator(store: store, now: now)
            return
        }

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
            Output.printError(code: "INVALID_ARGS", message: "Must specify --pid, --bundle-id, or --sim",
                            hint: "Example: agent-swift connect --bundle-id com.apple.TextEdit\n  or:     agent-swift connect --sim", useJson: globals.useJson)
            throw ExitCode(2)
        }

        var session = SessionData.empty
        session.pid = resolvedPid
        session.bundleId = resolvedBundleId
        session.connectedAt = now

        try store.save(session)

        let result = ConnectResult(connected: true, pid: resolvedPid, bundleId: resolvedBundleId,
                                   connectedAt: now, mode: "desktop", simulatorUDID: nil, simulatorDeviceType: nil)

        if globals.useJson {
            print(Output.json(result))
        } else {
            print("Connected to PID \(resolvedPid)" + (resolvedBundleId.map { " (\($0))" } ?? ""))
        }
    }

    private func connectSimulator(store: SessionStore, now: String) throws {
        let bridge: SimulatorBridge
        let resolvedUdid = udid ?? simulator
        do {
            if let udid = resolvedUdid, !udid.isEmpty {
                bridge = try SimulatorBridge.device(udid: udid)
            } else {
                bridge = try SimulatorBridge.bootedDevice()
            }
        } catch let error as SimulatorError {
            Output.printError(code: error.code, message: error.description,
                            hint: error.hint, useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard SimulatorBridge.isSimulatorRunning() else {
            Output.printError(code: "SIM_APP_NOT_RUNNING", message: "Simulator.app is not running",
                            hint: "Open Simulator: open -a Simulator", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let idb = IdbBridge(udid: bridge.udid)
        try? idb.enableAccessibility()

        let info = try? bridge.deviceInfo()
        let simPid = AXClient.resolvePID(bundleId: "com.apple.iphonesimulator")

        var session = SessionData.empty
        session.pid = simPid
        session.bundleId = "com.apple.iphonesimulator"
        session.connectedAt = now
        session.simulatorUDID = bridge.udid
        session.simulatorDeviceType = info?.name

        try store.save(session)

        if let app = simPid.flatMap({ NSRunningApplication(processIdentifier: pid_t($0)) }) {
            app.activate()
        }

        let result = ConnectResult(connected: true, pid: simPid, bundleId: "com.apple.iphonesimulator",
                                   connectedAt: now, mode: "simulator",
                                   simulatorUDID: bridge.udid, simulatorDeviceType: info?.name)

        if globals.useJson {
            print(Output.json(result))
        } else {
            print("Connected to Simulator: \(info?.name ?? bridge.udid)")
        }
    }

    private func connectMirror(store: SessionStore, now: String) throws {
        guard MirrorBridge.isRunning() else {
            Output.printError(code: "MIRROR_NOT_RUNNING", message: "iPhone Mirroring is not running",
                            hint: "Open iPhone Mirroring: open -a 'iPhone Mirroring'", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard AXClient.isTrusted() else {
            Output.printError(code: "AX_NOT_TRUSTED", message: "Accessibility permission not granted",
                            hint: "Grant access in System Settings > Privacy & Security > Accessibility", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let mirrorPid = AXClient.resolvePID(bundleId: MirrorBridge.bundleId)

        var session = SessionData.empty
        session.pid = mirrorPid
        session.bundleId = MirrorBridge.bundleId
        session.connectedAt = now
        session.mirrorMode = true

        try store.save(session)

        if let app = mirrorPid.flatMap({ NSRunningApplication(processIdentifier: pid_t($0)) }) {
            app.activate()
        }

        let result = ConnectResult(connected: true, pid: mirrorPid, bundleId: MirrorBridge.bundleId,
                                   connectedAt: now, mode: "mirror",
                                   simulatorUDID: nil, simulatorDeviceType: nil)

        if globals.useJson {
            print(Output.json(result))
        } else {
            print("Connected via iPhone Mirroring")
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
        let mode: String?
        let simulatorUDID: String?
        let simulatorDeviceType: String?
    }

    func run() throws {
        let session = SessionStore().load()
        let mode: String? = session.isConnected ? (session.isMirrorMode ? "mirror" : session.isSimulatorMode ? "simulator" : "desktop") : nil
        let result = StatusResult(
            connected: session.isConnected,
            pid: session.pid,
            bundleId: session.bundleId,
            connectedAt: session.connectedAt,
            refs: session.refs.count,
            mode: mode,
            simulatorUDID: session.simulatorUDID,
            simulatorDeviceType: session.simulatorDeviceType
        )

        if globals.useJson {
            print(Output.json(result))
        } else {
            if session.isConnected {
                if session.isMirrorMode {
                    print("Connected via iPhone Mirroring")
                } else if session.isSimulatorMode {
                    print("Connected to Simulator: \(session.simulatorDeviceType ?? session.simulatorUDID ?? "unknown")")
                    print("UDID: \(session.simulatorUDID ?? "unknown")")
                } else {
                    print("Connected to PID \(session.pid!)" + (session.bundleId.map { " (\($0))" } ?? ""))
                }
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

    @Flag(name: .long, help: "Include off-screen and clipped elements")
    var all = false

    func run() throws {
        let store = SessionStore()
        var session = store.load()

        guard session.isConnected else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        if session.isSimulatorMode, let udid = session.simulatorUDID {
            try snapshotSimulator(store: store, session: &session, udid: udid)
            return
        }

        guard let pid = session.pid else {
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

    private func snapshotSimulator(store: SessionStore, session: inout SessionData, udid: String) throws {
        let idb = IdbBridge(udid: udid)
        let idbElements: [IdbElement]
        do {
            idbElements = try idb.describeAll(includeAll: all)
        } catch let error as IdbError {
            Output.printError(code: error.code, message: error.description,
                            hint: error.hint, useJson: globals.useJson)
            throw ExitCode(2)
        }

        var filtered = idbElements
        if interactive && !all {
            filtered = filtered.filter { $0.isInteractive }
        }

        var elements: [(ref: String, node: AXNode)] = []
        var refs: [String: SessionData.RefEntry] = [:]
        for (i, idbEl) in filtered.enumerated() {
            let ref = "e\(i + 1)"
            let node = idbEl.toAXNode()
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

        guard session.isConnected else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let refKey = ref.hasPrefix("@") ? String(ref.dropFirst()) : ref
        guard let refEntry = session.refs[refKey] else {
            Output.printError(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(ref)",
                            hint: "Re-run: agent-swift snapshot -i", useJson: globals.useJson)
            throw ExitCode(2)
        }

        if session.isSimulatorMode, let udid = session.simulatorUDID {
            guard let bounds = refEntry.bounds else {
                Output.printError(code: "NO_BOUNDS", message: "Element \(ref) has no position",
                                hint: "Re-run: agent-swift snapshot -i", useJson: globals.useJson)
                throw ExitCode(2)
            }
            let center = CGPoint(x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2)
            let idb = IdbBridge(udid: udid)
            do {
                try idb.tap(x: center.x, y: center.y)
                if globals.useJson {
                    print(Output.json(PressResult(pressed: ref, success: true)))
                } else {
                    print("Pressed \(ref)")
                }
                return
            } catch {
                // idb failed — fall through to CGEvent through Simulator window
            }
            let bridge = SimulatorBridge(udid: udid)
            do {
                try bridge.tap(x: center.x, y: center.y)
                if globals.useJson {
                    print(Output.json(PressResult(pressed: ref, success: true)))
                } else {
                    print("Pressed \(ref)")
                }
            } catch let error as SimulatorError {
                Output.printError(code: error.code, message: error.description,
                                hint: error.hint, useJson: globals.useJson)
                throw ExitCode(2)
            }
            return
        }

        guard let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
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

        guard session.isConnected else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        if session.isSimulatorMode, let udid = session.simulatorUDID {
            let refKey = ref.hasPrefix("@") ? String(ref.dropFirst()) : ref
            guard let refEntry = session.refs[refKey] else {
                Output.printError(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(ref)",
                                hint: "Re-run: agent-swift snapshot -i", useJson: globals.useJson)
                throw ExitCode(2)
            }
            let idb = IdbBridge(udid: udid)
            do {
                if let bounds = refEntry.bounds {
                    let center = CGPoint(x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2)
                    try idb.tap(x: center.x, y: center.y)
                    Thread.sleep(forTimeInterval: 0.3)
                }
                try idb.text(input: text)
                if globals.useJson {
                    print(Output.json(FillResult(filled: ref, text: text, success: true)))
                } else {
                    print("Filled \(ref) with \"\(text)\"")
                }
            } catch let error as IdbError {
                Output.printError(code: error.code, message: error.description,
                                hint: error.hint, useJson: globals.useJson)
                throw ExitCode(2)
            }
            return
        }

        guard let pid = session.pid else {
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
    static let configuration = CommandConfiguration(commandName: "find",
        abstract: "Find element by locator",
        discussion: """
        Locators: role, text, identifier, label, value
        Actions: press, click, fill <text>, get [property]

        Single locator:
          agent-swift find text Save press
          agent-swift find role button

        Compound locators (AND logic):
          agent-swift find role button text Open press
          agent-swift find identifier myField text Hello fill "world"
        """)

    @OptionGroup var globals: GlobalOptions

    @Argument(parsing: .remaining,
              help: "Locator/value pairs followed by optional action: <locator> <value> [<locator> <value>...] [action] [actionArg]")
    var remaining: [String] = []

    struct FindResult: Codable {
        let ref: String
        let type: String
        let label: String?
        let identifier: String?
        let matchCount: Int?
    }

    struct FindActionResult: Codable {
        let found: String
        let action: String
        let success: Bool
        let matchCount: Int?
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

    // Known locator names and action names for compound parsing
    static let locatorNames: Set<String> = ["role", "text", "identifier", "label", "value"]
    static let actionNames: Set<String> = ["press", "click", "fill", "get"]

    /// Parse remaining args into locator pairs + optional action + actionArg
    func parseCompoundArgs() -> (locatorPairs: [(String, String)], action: String?, actionArg: String?) {
        var locatorPairs: [(String, String)] = []
        var action: String? = nil
        var actionArg: String? = nil
        var i = 0
        let args = remaining

        while i < args.count {
            let current = args[i]
            if Self.locatorNames.contains(current) {
                // It's a locator — next arg is its value
                if i + 1 < args.count {
                    locatorPairs.append((current, args[i + 1]))
                    i += 2
                } else {
                    // Locator with no value — treat as error
                    break
                }
            } else if Self.actionNames.contains(current) {
                action = current
                if i + 1 < args.count {
                    actionArg = args[i + 1]
                }
                break
            } else if locatorPairs.isEmpty {
                // Backwards compat: first two args are locator value without compound
                if i + 1 < args.count {
                    locatorPairs.append((current, args[i + 1]))
                    i += 2
                } else {
                    break
                }
            } else {
                // Unknown token — could be an action
                action = current
                if i + 1 < args.count {
                    actionArg = args[i + 1]
                }
                break
            }
        }

        return (locatorPairs, action, actionArg)
    }

    /// Check if a node matches a single locator pair
    func nodeMatches(_ node: AXNode, locator: String, value: String) -> Bool {
        switch locator {
        case "role":
            return node.role == value || node.displayType == value
        case "text", "label":
            if let label = node.displayLabel, label.contains(value) { return true }
            return false
        case "identifier":
            return node.identifier == value
        case "value":
            if let v = node.displayLabel, v.contains(value) { return true }
            return false
        default:
            return false
        }
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected, let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let parsed = parseCompoundArgs()
        let locatorPairs = parsed.locatorPairs
        let action = parsed.action
        let actionArg = parsed.actionArg

        guard !locatorPairs.isEmpty else {
            Output.printError(code: "INVALID_ARGS", message: "No locator specified",
                            hint: "Usage: agent-swift find <locator> <value> [action]\n  Locators: role, text, identifier, label, value\n  Actions: press, click, fill <text>, get [property]\n  Compound: find role button text Open press", useJson: globals.useJson)
            throw ExitCode(2)
        }

        // Validate locator names
        for (loc, _) in locatorPairs {
            if !Self.locatorNames.contains(loc) {
                var hint = "Use: role, text, identifier, label, or value"
                // Suggest corrections for common typos
                if loc == "label" || loc == "title" || loc == "name" {
                    hint = "Did you mean 'text'? Use: role, text, identifier, label, or value"
                } else if loc == "type" {
                    hint = "Did you mean 'role'? Use: role, text, identifier, label, or value"
                }
                Output.printError(code: "INVALID_ARGS", message: "Unknown locator: \(loc)",
                                hint: hint, useJson: globals.useJson)
                throw ExitCode(2)
            }
        }

        // Validate action name if provided
        if let action = action, !Self.actionNames.contains(action) {
            var hint = "Use: press, click, fill, or get"
            if action == "tap" {
                hint = "Did you mean 'press'? Use: press, click, fill, or get"
            }
            Output.printError(code: "INVALID_ARGS", message: "Unknown action: \(action)",
                            hint: hint, useJson: globals.useJson)
            throw ExitCode(2)
        }

        // Walk tree to get nodes
        let root = AXClient.appElement(pid: pid)
        let tree = AXClient.walkTree(element: root)
        let allNodes = AXClient.flattenTree(tree)
        let useInteractive = session.interactiveSnapshot ?? false
        let nodes = useInteractive ? allNodes.filter { $0.isInteractive } : allNodes

        // Find ALL matching elements (compound AND logic)
        var matchIndices: [Int] = []
        for (i, node) in nodes.enumerated() {
            let matchesAll = locatorPairs.allSatisfy { (loc, val) in
                nodeMatches(node, locator: loc, value: val)
            }
            if matchesAll {
                matchIndices.append(i)
            }
        }

        guard let idx = matchIndices.first else {
            let desc = locatorPairs.map { "\($0.0)=\"\($0.1)\"" }.joined(separator: " AND ")
            Output.printError(code: "ELEMENT_NOT_FOUND", message: "No element matches \(desc)",
                            hint: "Re-run: agent-swift snapshot -i", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let matchedNode = nodes[idx]
        let matchedRef = "@e\(idx + 1)"
        let matchCount = matchIndices.count

        // If no chained action, just print the match
        guard let action = action else {
            if globals.useJson {
                print(Output.json(FindResult(ref: matchedRef, type: matchedNode.displayType,
                                            label: matchedNode.displayLabel, identifier: matchedNode.identifier,
                                            matchCount: matchCount)))
            } else {
                var line = "\(matchedRef) [\(matchedNode.displayType)]"
                if let label = matchedNode.displayLabel { line += " \"\(label)\"" }
                if let id = matchedNode.identifier { line += "  identifier=\(id)" }
                if matchCount > 1 { line += "  (\(matchCount) matches)" }
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
                    print(Output.json(FindActionResult(found: matchedRef, action: "press", success: true, matchCount: matchCount)))
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
                    print(Output.json(FindActionResult(found: matchedRef, action: "click", success: true, matchCount: matchCount)))
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
        let mode: String?
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let outputPath = path ?? "/tmp/agent-swift-screenshot.png"

        if session.isMirrorMode {
            let mirror = MirrorBridge()
            do {
                try mirror.screenshot(to: outputPath)
                if globals.useJson {
                    print(Output.json(ScreenshotResult(path: outputPath, success: true, mode: "mirror")))
                } else {
                    print("Screenshot saved to \(outputPath)")
                }
            } catch let error as MirrorError {
                Output.printError(code: error.code, message: error.description,
                                hint: error.hint, useJson: globals.useJson)
                throw ExitCode(2)
            }
            return
        }

        if session.isSimulatorMode, let udid = session.simulatorUDID {
            let bridge = SimulatorBridge(udid: udid)
            do {
                try bridge.screenshot(to: outputPath)
                if globals.useJson {
                    print(Output.json(ScreenshotResult(path: outputPath, success: true, mode: "simulator")))
                } else {
                    print("Screenshot saved to \(outputPath)")
                }
            } catch let error as SimulatorError {
                Output.printError(code: error.code, message: error.description,
                                hint: error.hint, useJson: globals.useJson)
                throw ExitCode(2)
            }
            return
        }

        guard let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard AXClient.isProcessRunning(pid: pid) else {
            Output.printError(code: "APP_NOT_RUNNING", message: "Target app (PID \(pid)) is no longer running",
                            hint: "Reconnect with: agent-swift connect", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let success = AXClient.captureScreenshot(pid: pid, path: outputPath)

        if success {
            if globals.useJson {
                print(Output.json(ScreenshotResult(path: outputPath, success: true, mode: "desktop")))
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

        guard session.isConnected else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        if session.isMirrorMode {
            try scrollMirror()
            return
        }

        if session.isSimulatorMode, let udid = session.simulatorUDID {
            try scrollSimulator(udid: udid)
            return
        }

        guard let pid = session.pid else {
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
            let resolved = try resolveRef(target, session: session, pid: pid, useJson: globals.useJson)
            let acted = AXClient.performPress(element: resolved.element, actionName: "AXScrollToVisible")
            if acted {
                if globals.useJson {
                    print(Output.json(ScrollResult(target: target, success: true)))
                } else {
                    print("Scrolled \(target) into view")
                }
            } else {
                Output.printError(code: "SCROLL_FAILED", message: "Cannot scroll \(target) into view",
                                hint: "Try: agent-swift scroll up/down", useJson: globals.useJson)
                throw ExitCode(2)
            }
        }
    }

    private func scrollSimulator(udid: String) throws {
        let bridge = SimulatorBridge(udid: udid)
        switch target {
        case "up", "down", "left", "right":
            let coords = SimulatorBridge.directionToSwipeCoords(direction: target)
            do {
                try bridge.swipe(fromX: coords.fromX, fromY: coords.fromY,
                                toX: coords.toX, toY: coords.toY)
                if globals.useJson {
                    print(Output.json(ScrollResult(target: target, success: true)))
                } else {
                    print("Scrolled \(target)")
                }
            } catch let error as SimulatorError {
                Output.printError(code: error.code, message: error.description,
                                hint: error.hint, useJson: globals.useJson)
                throw ExitCode(2)
            }
        default:
            Output.printError(code: "INVALID_INPUT", message: "Simulator scroll supports: up, down, left, right",
                            hint: "Example: agent-swift scroll down", useJson: globals.useJson)
            throw ExitCode(2)
        }
    }

    private func scrollMirror() throws {
        let mirror = MirrorBridge()
        switch target {
        case "up", "down", "left", "right":
            let coords = MirrorBridge.directionToSwipeCoords(direction: target)
            do {
                try mirror.swipe(fromX: coords.fromX, fromY: coords.fromY,
                                toX: coords.toX, toY: coords.toY)
                if globals.useJson {
                    print(Output.json(ScrollResult(target: target, success: true)))
                } else {
                    print("Scrolled \(target)")
                }
            } catch let error as MirrorError {
                Output.printError(code: error.code, message: error.description,
                                hint: error.hint, useJson: globals.useJson)
                throw ExitCode(2)
            }
        default:
            Output.printError(code: "INVALID_INPUT", message: "Mirror scroll supports: up, down, left, right",
                            hint: "Example: agent-swift scroll down", useJson: globals.useJson)
            throw ExitCode(2)
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
        let mode: String?
        let iosPoint: [String: Double]?
        let screenPoint: [String: Double]?
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        if session.isMirrorMode {
            try clickMirror()
            return
        }

        if session.isSimulatorMode {
            try clickSimulator(session: session)
            return
        }

        guard let pid = session.pid else {
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
            let resolved = try resolveRef(target, session: session, pid: pid, useJson: globals.useJson)
            guard let pos = resolved.node.position, let sz = resolved.node.size else {
                Output.printError(code: "NO_BOUNDS", message: "Element \(target) has no position/size",
                                hint: "Element may be offscreen. Try: agent-swift scroll \(target)", useJson: globals.useJson)
                throw ExitCode(2)
            }
            clickPoint = CGPoint(x: pos.x + sz.width / 2, y: pos.y + sz.height / 2)
            clickLabel = target.hasPrefix("@") ? target : "@\(target)"
        } else {
            guard let x = Double(target), let yCoord = y else {
                Output.printError(code: "INVALID_INPUT", message: "Invalid click target: \(target)",
                                hint: "Use @eN for element ref or 'x y' for coordinates", useJson: globals.useJson)
                throw ExitCode(2)
            }
            clickPoint = CGPoint(x: x, y: yCoord)
            clickLabel = "\(Int(x)),\(Int(yCoord))"
        }

        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            app.activate()
            Thread.sleep(forTimeInterval: 0.1)
        }

        if AXClient.performClick(at: clickPoint) {
            if globals.useJson {
                print(Output.json(ClickResult(clicked: clickLabel, x: clickPoint.x, y: clickPoint.y,
                                              success: true, mode: "desktop", iosPoint: nil, screenPoint: nil)))
            } else {
                print("Clicked \(clickLabel) at (\(Int(clickPoint.x)), \(Int(clickPoint.y)))")
            }
        } else {
            Output.printError(code: "CLICK_FAILED", message: "Failed to create click event",
                            hint: "Ensure Accessibility permission is granted", useJson: globals.useJson)
            throw ExitCode(2)
        }
    }

    private func clickSimulator(session: SessionData) throws {
        guard let udid = session.simulatorUDID else {
            Output.printError(code: "NOT_CONNECTED", message: "No simulator UDID in session",
                            hint: "Reconnect: agent-swift connect --sim", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let tapX: Double
        let tapY: Double
        let clickLabel: String

        if target.hasPrefix("@") || target.hasPrefix("e") {
            let refKey = target.hasPrefix("@") ? String(target.dropFirst()) : target
            guard let refEntry = session.refs[refKey] else {
                Output.printError(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(target)",
                                hint: "Re-run: agent-swift snapshot -i", useJson: globals.useJson)
                throw ExitCode(2)
            }
            guard let bounds = refEntry.bounds else {
                Output.printError(code: "NO_BOUNDS", message: "Element \(target) has no position",
                                hint: "Re-run: agent-swift snapshot -i", useJson: globals.useJson)
                throw ExitCode(2)
            }
            tapX = bounds.x + bounds.width / 2
            tapY = bounds.y + bounds.height / 2
            clickLabel = target.hasPrefix("@") ? target : "@\(target)"

            let idb = IdbBridge(udid: udid)
            do {
                try idb.tap(x: tapX, y: tapY)
                if globals.useJson {
                    print(Output.json(ClickResult(
                        clicked: clickLabel, x: tapX, y: tapY, success: true,
                        mode: "simulator",
                        iosPoint: ["x": tapX, "y": tapY],
                        screenPoint: nil
                    )))
                } else {
                    print("Tapped iOS (\(Int(tapX)), \(Int(tapY)))")
                }
                return
            } catch {
                // idb failed — fall through to CGEvent
            }
        } else {
            guard let x = Double(target), let yCoord = y else {
                Output.printError(code: "INVALID_INPUT", message: "Invalid click target: \(target)",
                                hint: "Use @eN for element ref or 'x y' for coordinates", useJson: globals.useJson)
                throw ExitCode(2)
            }
            tapX = x
            tapY = yCoord
            clickLabel = "\(Int(x)),\(Int(yCoord))"
        }

        let bridge = SimulatorBridge(udid: udid)
        do {
            let info = try bridge.windowInfo()
            let screenPoint = SimulatorBridge.iosPointToScreen(CGPoint(x: tapX, y: tapY), windowInfo: info)
            try bridge.tap(x: tapX, y: tapY)
            if globals.useJson {
                print(Output.json(ClickResult(
                    clicked: clickLabel, x: tapX, y: tapY, success: true,
                    mode: "simulator",
                    iosPoint: ["x": tapX, "y": tapY],
                    screenPoint: ["x": screenPoint.x, "y": screenPoint.y]
                )))
            } else {
                print("Tapped iOS (\(Int(tapX)), \(Int(tapY))) → screen (\(Int(screenPoint.x)), \(Int(screenPoint.y)))")
            }
        } catch let error as SimulatorError {
            Output.printError(code: error.code, message: error.description,
                            hint: error.hint, useJson: globals.useJson)
            throw ExitCode(2)
        }
    }

    private func clickMirror() throws {
        guard let tapX = Double(target), let tapY = y else {
            Output.printError(code: "INVALID_INPUT", message: "Mirror mode requires x y coordinates",
                            hint: "Example: agent-swift click 200 400", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let mirror = MirrorBridge()
        do {
            let info = try mirror.windowInfo()
            let screenPoint = MirrorBridge.iosPointToScreen(CGPoint(x: tapX, y: tapY), windowInfo: info)
            try mirror.tap(x: tapX, y: tapY)
            let clickLabel = "\(Int(tapX)),\(Int(tapY))"
            if globals.useJson {
                print(Output.json(ClickResult(
                    clicked: clickLabel, x: tapX, y: tapY, success: true,
                    mode: "mirror",
                    iosPoint: ["x": tapX, "y": tapY],
                    screenPoint: ["x": screenPoint.x, "y": screenPoint.y]
                )))
            } else {
                print("Tapped iOS (\(Int(tapX)), \(Int(tapY))) → screen (\(Int(screenPoint.x)), \(Int(screenPoint.y)))")
            }
        } catch let error as MirrorError {
            Output.printError(code: error.code, message: error.description,
                            hint: error.hint, useJson: globals.useJson)
            throw ExitCode(2)
        }
    }
}

// MARK: - Type

struct TypeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "type", abstract: "Type text into focused field")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Text to type")
    var text: String

    struct TypeResult: Codable {
        let typed: String
        let success: Bool
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        if session.isSimulatorMode, let udid = session.simulatorUDID {
            try typeSimulator(udid: udid)
            return
        }

        if session.isMirrorMode {
            try typeMirror()
            return
        }

        guard let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        // macOS AX mode: find focused element and fill it
        guard AXClient.isProcessRunning(pid: pid) else {
            Output.printError(code: "APP_NOT_RUNNING", message: "Target app (PID \(pid)) is no longer running",
                            hint: "Reconnect with: agent-swift connect", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let root = AXClient.appElement(pid: pid)
        // Try to find the focused element and fill it
        let focusedElement = AXClient.focusedElement(of: root)
        if let focused = focusedElement {
            if AXClient.performFill(element: focused, text: text) {
                if globals.useJson {
                    print(Output.json(TypeResult(typed: text, success: true)))
                } else {
                    print("Typed \"\(text)\"")
                }
                return
            }
        }

        // Fallback: use CGEvent key-by-key typing
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            app.activate()
            Thread.sleep(forTimeInterval: 0.1)
        }
        typeViaCGEvent(text: text)
        if globals.useJson {
            print(Output.json(TypeResult(typed: text, success: true)))
        } else {
            print("Typed \"\(text)\" (via keystroke)")
        }
    }

    private func typeSimulator(udid: String) throws {
        let idb = IdbBridge(udid: udid)
        do {
            try idb.text(input: text)
            if globals.useJson {
                print(Output.json(TypeResult(typed: text, success: true)))
            } else {
                print("Typed \"\(text)\"")
            }
        } catch let error as IdbError {
            Output.printError(code: error.code, message: error.description,
                            hint: error.hint, useJson: globals.useJson)
            throw ExitCode(2)
        }
    }

    private func typeMirror() throws {
        typeViaCGEvent(text: text)
        if globals.useJson {
            print(Output.json(TypeResult(typed: text, success: true)))
        } else {
            print("Typed \"\(text)\" (via keystroke)")
        }
    }

    private func typeViaCGEvent(text: String) {
        #if canImport(AppKit)
        for char in text {
            let str = String(char)
            let src = CGEventSource(stateID: .hidSystemState)
            if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                let nsStr = str as NSString
                var unichar = nsStr.character(at: 0)
                keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                keyDown.post(tap: .cgSessionEventTap)
                Thread.sleep(forTimeInterval: 0.02)
                keyUp.post(tap: .cgSessionEventTap)
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        #endif
    }
}

// MARK: - Swipe

struct SwipeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "swipe", abstract: "Swipe gesture by coordinates")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Start X coordinate")
    var fromX: Double

    @Argument(help: "Start Y coordinate")
    var fromY: Double

    @Argument(help: "End X coordinate")
    var toX: Double

    @Argument(help: "End Y coordinate")
    var toY: Double

    @Option(name: .long, help: "Swipe duration in seconds (default: 0.3)")
    var duration: Double = 0.3

    struct SwipeResult: Codable {
        let from: [String: Double]
        let to: [String: Double]
        let success: Bool
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        guard session.isConnected else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        if session.isSimulatorMode, let udid = session.simulatorUDID {
            try swipeSimulator(udid: udid)
            return
        }

        if session.isMirrorMode {
            try swipeMirror()
            return
        }

        guard let pid = session.pid else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect --bundle-id <id>", useJson: globals.useJson)
            throw ExitCode(2)
        }

        // macOS desktop mode: CGEvent drag
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            app.activate()
            Thread.sleep(forTimeInterval: 0.1)
        }
        swipeViaCGEvent(from: CGPoint(x: fromX, y: fromY), to: CGPoint(x: toX, y: toY), duration: duration)

        let result = SwipeResult(from: ["x": fromX, "y": fromY], to: ["x": toX, "y": toY], success: true)
        if globals.useJson {
            print(Output.json(result))
        } else {
            print("Swiped from (\(Int(fromX)), \(Int(fromY))) to (\(Int(toX)), \(Int(toY)))")
        }
    }

    private func swipeSimulator(udid: String) throws {
        let bridge = SimulatorBridge(udid: udid)
        do {
            try bridge.swipe(fromX: fromX, fromY: fromY, toX: toX, toY: toY, duration: duration)
            let result = SwipeResult(from: ["x": fromX, "y": fromY], to: ["x": toX, "y": toY], success: true)
            if globals.useJson {
                print(Output.json(result))
            } else {
                print("Swiped from (\(Int(fromX)), \(Int(fromY))) to (\(Int(toX)), \(Int(toY)))")
            }
        } catch let error as SimulatorError {
            Output.printError(code: error.code, message: error.description,
                            hint: error.hint, useJson: globals.useJson)
            throw ExitCode(2)
        }
    }

    private func swipeMirror() throws {
        let mirror = MirrorBridge()
        do {
            try mirror.swipe(fromX: fromX, fromY: fromY, toX: toX, toY: toY, duration: duration)
            let result = SwipeResult(from: ["x": fromX, "y": fromY], to: ["x": toX, "y": toY], success: true)
            if globals.useJson {
                print(Output.json(result))
            } else {
                print("Swiped from (\(Int(fromX)), \(Int(fromY))) to (\(Int(toX)), \(Int(toY)))")
            }
        } catch let error as MirrorError {
            Output.printError(code: error.code, message: error.description,
                            hint: error.hint, useJson: globals.useJson)
            throw ExitCode(2)
        }
    }

    private func swipeViaCGEvent(from: CGPoint, to: CGPoint, duration: Double) {
        #if canImport(AppKit)
        let steps = max(Int(duration * 60), 5) // ~60fps
        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                       mouseCursorPosition: from, mouseButton: .left) else { return }
        mouseDown.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.02)

        for i in 1...steps {
            let progress = Double(i) / Double(steps)
            let x = from.x + (to.x - from.x) * progress
            let y = from.y + (to.y - from.y) * progress
            if let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                   mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                drag.post(tap: .cgSessionEventTap)
            }
            Thread.sleep(forTimeInterval: duration / Double(steps))
        }

        if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                  mouseCursorPosition: to, mouseButton: .left) {
            mouseUp.post(tap: .cgSessionEventTap)
        }
        #endif
    }
}

// MARK: - Record

struct RecordCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Screen video recording",
        discussion: """
            Record screen video and extract frames at any timestamp.

            Workflow:
              1. record start       → begin recording
              2. record frame --at 0  → live screenshot (current screen only)
              3. record stop        → finalize video
              4. record frame --at 4  → extract frame at 4th second from video

            NOTE: Frame lookback (--at a past timestamp) is only available AFTER
            record stop. During recording, record frame returns a live screenshot
            of the current screen regardless of --at value. Plan your workflow:
            record first, then extract any frame you need from the finished video.
            """,
        subcommands: [
            RecordStartCommand.self,
            RecordStopCommand.self,
            RecordFrameCommand.self,
            RecordFramesCommand.self,
            RecordStatusCommand.self
        ]
    )
}

struct RecordStartCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "start", abstract: "Start screen recording")

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Output video file path (default: ~/.agent-swift/recording-<sessionId>.mp4)")
    var output: String?

    struct StartResult: Codable {
        let sessionId: String
        let videoPath: String
        let startTime: String
        let mode: String
    }

    func run() throws {
        let store = SessionStore()
        var session = store.load()

        guard session.isConnected else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session",
                            hint: "Run: agent-swift connect first", useJson: globals.useJson)
            throw ExitCode(2)
        }

        if session.recording != nil {
            Output.printError(code: "RECORDING_ACTIVE", message: "A recording is already in progress",
                            hint: "Stop it first: agent-swift record stop", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let sessionId = String(UUID().uuidString.prefix(8)).lowercased()
        let now = ISO8601DateFormatter().string(from: Date())

        let videoPath: String
        if let customPath = output {
            // Ensure parent directory exists
            let parentDir = (customPath as NSString).deletingLastPathComponent
            if !parentDir.isEmpty {
                try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            }
            videoPath = customPath
        } else {
            let sessionDir: String
            if let home = ProcessInfo.processInfo.environment["AGENT_SWIFT_HOME"] {
                sessionDir = home
            } else {
                sessionDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".agent-swift").path
            }
            try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
            videoPath = "\(sessionDir)/recording-\(sessionId).mp4"
        }

        let mode: String
        let recordProcess = Process()

        if session.isSimulatorMode, let udid = session.simulatorUDID {
            mode = "simulator"
            // xcrun simctl io <udid> recordVideo --codec h264 --force <path>
            recordProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            recordProcess.arguments = ["simctl", "io", udid, "recordVideo", "--codec", "h264", "--force", videoPath]
        } else if session.isMirrorMode {
            mode = "mirror"
            // screencapture -v <path> — records screen video
            recordProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            recordProcess.arguments = ["-v", videoPath]
        } else {
            mode = "desktop"
            recordProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            recordProcess.arguments = ["-v", videoPath]
        }

        recordProcess.standardOutput = FileHandle.nullDevice
        recordProcess.standardError = FileHandle.nullDevice

        do {
            try recordProcess.run()
        } catch {
            Output.printError(code: "RECORD_START_FAILED", message: "Failed to start recording: \(error.localizedDescription)",
                            hint: nil, useJson: globals.useJson)
            throw ExitCode(2)
        }

        // Small delay to let the recording process initialize
        Thread.sleep(forTimeInterval: 0.5)

        guard recordProcess.isRunning else {
            Output.printError(code: "RECORD_START_FAILED", message: "Recording process exited immediately",
                            hint: "Check if simctl/screencapture is available", useJson: globals.useJson)
            throw ExitCode(2)
        }

        let recordingSession = RecordingSession(
            sessionId: sessionId,
            pid: recordProcess.processIdentifier,
            videoPath: videoPath,
            startTime: now,
            mode: mode
        )
        session.recording = recordingSession
        try store.save(session)

        let result = StartResult(sessionId: sessionId, videoPath: videoPath, startTime: now, mode: mode)
        if globals.useJson {
            print(Output.json(result))
        } else {
            print("Recording started (session: \(sessionId), mode: \(mode))")
            print("Video: \(videoPath)")
        }
    }
}

struct RecordStopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop screen recording")

    @OptionGroup var globals: GlobalOptions

    struct StopResult: Codable {
        let sessionId: String
        let videoPath: String
        let duration: Double?
        let fileSize: Int64?
    }

    func run() throws {
        let store = SessionStore()
        var session = store.load()

        guard let recording = session.recording else {
            Output.printError(code: "NO_RECORDING", message: "No active recording",
                            hint: "Start one first: agent-swift record start", useJson: globals.useJson)
            throw ExitCode(2)
        }

        // Send SIGINT to the recording process
        let pid = recording.pid
        kill(pid, SIGINT)

        // Wait for the process to finish (up to 5 seconds)
        var waited = 0.0
        while waited < 5.0 {
            if kill(pid, 0) != 0 { break } // process is gone
            Thread.sleep(forTimeInterval: 0.2)
            waited += 0.2
        }

        // If still running after 5s, force kill
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
            Thread.sleep(forTimeInterval: 0.5)
        }

        let sessionId = recording.sessionId
        let videoPath = recording.videoPath

        // Clear recording but preserve video path for frame extraction
        session.lastVideoPath = recording.videoPath
        session.recording = nil
        try store.save(session)

        // Get video metadata
        var duration: Double? = nil
        var fileSize: Int64? = nil

        let fm = FileManager.default
        if fm.fileExists(atPath: videoPath) {
            if let attrs = try? fm.attributesOfItem(atPath: videoPath) {
                fileSize = attrs[.size] as? Int64
            }

            // Try ffprobe for duration
            duration = Self.getVideoDuration(path: videoPath)
        }

        let result = StopResult(sessionId: sessionId, videoPath: videoPath, duration: duration, fileSize: fileSize)
        if globals.useJson {
            print(Output.json(result))
        } else {
            print("Recording stopped (session: \(sessionId))")
            print("Video: \(videoPath)")
            if let d = duration {
                print("Duration: \(String(format: "%.1f", d))s")
            }
            if let s = fileSize {
                let kb = s / 1024
                print("Size: \(kb)KB")
            }
        }
    }

    static func getVideoDuration(path: String) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let format = json["format"] as? [String: Any],
               let durationStr = format["duration"] as? String,
               let d = Double(durationStr) {
                return d
            }
        } catch {}
        return nil
    }
}

struct RecordFrameCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "frame",
        abstract: "Extract frame from recording at timestamp",
        discussion: """
            During recording: returns a live screenshot (current screen).
            After record stop: extracts the exact frame at --at timestamp from the finalized video.
            Lookback to a past timestamp requires stopping the recording first.

            Video resolution order:
              1. --video flag (explicit path — always wins)
              2. Active recording's video path
              3. Last stopped recording's video path (from session)
              4. Error — no guessing

            Processing flags (applied after extraction):
              --max-width <pixels>  Downscale to fit width (preserves aspect ratio, no upscale)
              --crop <x,y,w,h>      Crop to region (clamped to valid area)
              --dedup-threshold <0-1> Skip if similar to last extracted frame
              --grayscale           Convert to grayscale (3x smaller file)
              --format <png|jpeg>   Output format (default: png)
              --quality <1-100>     JPEG quality (default: 80, only with --format jpeg)
              --ocr                 Extract text via Vision OCR instead of returning image
            """
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Timestamp in seconds (e.g. 4.0)")
    var at: Double

    @Option(name: .long, help: "Path to video file (default: last recording from session)")
    var video: String?

    @Option(name: .long, help: "Output file path (default: auto-generated)")
    var output: String?

    @Option(name: .long, help: "Max width in pixels — downscale to fit (no upscale)")
    var maxWidth: Int?

    @Option(name: .long, help: "Crop region: x,y,width,height (clamped to frame bounds)")
    var crop: String?

    @Option(name: .long, help: "Skip if similarity to last frame >= threshold (0.0-1.0)")
    var dedupThreshold: Double?

    @Flag(name: .long, help: "Convert to grayscale (reduces file size ~3x)")
    var grayscale: Bool = false

    @Option(name: .long, help: "Output format: png (default) or jpeg")
    var format: String?

    @Option(name: .long, help: "JPEG quality 1-100 (default: 80, only with --format jpeg)")
    var quality: Int?

    @Flag(name: .long, help: "Extract text via Vision OCR (returns texts array instead of image)")
    var ocr: Bool = false

    struct OcrTextBlock: Codable {
        let text: String
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let confidence: Double
    }

    struct FrameResult: Codable {
        let path: String
        let timestamp: Double
        let source: String  // "live" or "video"
        let success: Bool
        let width: Int?
        let height: Int?
        let skipped: Bool?
        let reason: String?
        let similarity: Double?
        let texts: [OcrTextBlock]?
    }

    func run() throws {
        let store = SessionStore()
        var session = store.load()

        guard at >= 0 else {
            Output.printError(code: "INVALID_ARGS", message: "Timestamp must be >= 0",
                            hint: "Example: agent-swift record frame --at 4.0", useJson: globals.useJson)
            throw ExitCode(2)
        }

        if let threshold = dedupThreshold {
            guard threshold >= 0 && threshold <= 1.0 else {
                Output.printError(code: "INVALID_ARGS", message: "dedup-threshold must be between 0.0 and 1.0",
                                hint: "Example: --dedup-threshold 0.95", useJson: globals.useJson)
                throw ExitCode(2)
            }
        }

        if let cropStr = crop {
            let parts = cropStr.split(separator: ",")
            guard parts.count == 4, parts.allSatisfy({ Int($0) != nil }) else {
                Output.printError(code: "INVALID_ARGS", message: "crop format must be x,y,width,height (integers)",
                                hint: "Example: --crop 0,200,1206,800", useJson: globals.useJson)
                throw ExitCode(2)
            }
        }

        if let fmt = format {
            guard fmt == "png" || fmt == "jpeg" else {
                Output.printError(code: "INVALID_ARGS", message: "format must be 'png' or 'jpeg'",
                                hint: "Example: --format jpeg --quality 60", useJson: globals.useJson)
                throw ExitCode(2)
            }
        }

        if let q = quality {
            guard q >= 1 && q <= 100 else {
                Output.printError(code: "INVALID_ARGS", message: "quality must be between 1 and 100",
                                hint: "Example: --quality 80", useJson: globals.useJson)
                throw ExitCode(2)
            }
            guard format == "jpeg" else {
                Output.printError(code: "INVALID_ARGS", message: "--quality requires --format jpeg",
                                hint: "Example: --format jpeg --quality 60", useJson: globals.useJson)
                throw ExitCode(2)
            }
        }

        // Check if ffmpeg is available
        guard Self.isFfmpegAvailable() else {
            Output.printError(code: "FFMPEG_NOT_FOUND", message: "ffmpeg is not installed",
                            hint: "Install with: brew install ffmpeg", useJson: globals.useJson)
            throw ExitCode(2)
        }

        // Determine output path
        let sessionDir = Self.resolveSessionDir()
        try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
        let outputPath = output ?? "\(sessionDir)/frame-\(String(format: "%.1f", at))s.png"

        if let recording = session.recording {
            if kill(recording.pid, 0) == 0 {
                try extractLiveFrame(session: session, outputPath: outputPath, store: store)
                return
            }
        }

        // Video resolution: --video flag > active recording > lastVideoPath > error
        let resolvedVideo: String
        if let explicit = video {
            resolvedVideo = explicit
        } else if let recordingPath = session.recording?.videoPath {
            resolvedVideo = recordingPath
        } else if let lastPath = session.lastVideoPath {
            resolvedVideo = lastPath
        } else {
            Output.printError(code: "NO_VIDEO", message: "No recording video found",
                            hint: "Use --video <path> or run record start/stop first", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard FileManager.default.fileExists(atPath: resolvedVideo) else {
            Output.printError(code: "VIDEO_NOT_FOUND", message: "Video file does not exist: \(resolvedVideo)",
                            hint: "Check the path or start a new recording", useJson: globals.useJson)
            throw ExitCode(2)
        }

        // Extract frame
        try Self.extractFrame(from: resolvedVideo, at: at, to: outputPath, useJson: globals.useJson)

        // Apply crop
        if let cropStr = crop {
            try Self.applyCrop(to: outputPath, cropStr: cropStr)
        }

        // Apply grayscale
        if grayscale {
            Self.applyGrayscale(to: outputPath)
        }

        // Apply resize
        if let maxW = maxWidth {
            Self.applyResize(to: outputPath, maxWidth: maxW)
        }

        // Apply format conversion
        var finalPath = outputPath
        if format == "jpeg" {
            finalPath = Self.convertToJpeg(path: outputPath, quality: quality ?? 80)
        }

        // Dedup check
        if let threshold = dedupThreshold, let lastFrame = session.lastFramePath,
           FileManager.default.fileExists(atPath: lastFrame) {
            let similarity = Self.computeSimilarity(file1: lastFrame, file2: finalPath)
            if similarity >= threshold {
                try? FileManager.default.removeItem(atPath: finalPath)
                let result = FrameResult(path: finalPath, timestamp: at, source: "video", success: true,
                                        width: nil, height: nil, skipped: true, reason: "duplicate", similarity: similarity, texts: nil)
                if globals.useJson {
                    print(Output.json(result))
                } else {
                    print("Skipped (similarity \(String(format: "%.2f", similarity)) >= \(threshold))")
                }
                return
            }
        }

        // OCR
        let ocrTexts: [OcrTextBlock]? = ocr ? Self.performOCR(imagePath: finalPath) : nil

        // Get dimensions
        let dims = Self.getImageDimensions(path: finalPath)

        // Update lastFramePath
        session.lastFramePath = finalPath
        try store.save(session)

        let result = FrameResult(path: finalPath, timestamp: at, source: "video", success: true,
                                width: dims?.0, height: dims?.1, skipped: false, reason: nil, similarity: nil, texts: ocrTexts)
        if globals.useJson {
            print(Output.json(result))
        } else {
            var msg = "Frame extracted at \(at)s → \(finalPath)"
            if let (w, h) = dims { msg += " (\(w)×\(h))" }
            if let texts = ocrTexts { msg += " [\(texts.count) text blocks]" }
            print(msg)
        }
    }

    private func extractLiveFrame(session: SessionData, outputPath: String, store: SessionStore) throws {
        let screenshotPath = outputPath
        if session.isSimulatorMode, let udid = session.simulatorUDID {
            let bridge = SimulatorBridge(udid: udid)
            do { try bridge.screenshot(to: screenshotPath) } catch {
                Output.printError(code: "LIVE_FRAME_FAILED", message: "Failed to capture live frame: \(error)",
                                hint: nil, useJson: globals.useJson)
                throw ExitCode(2)
            }
        } else if session.isMirrorMode {
            let mirror = MirrorBridge()
            do { try mirror.screenshot(to: screenshotPath) } catch {
                Output.printError(code: "LIVE_FRAME_FAILED", message: "Failed to capture live frame: \(error)",
                                hint: nil, useJson: globals.useJson)
                throw ExitCode(2)
            }
        } else if let pid = session.pid {
            let success = AXClient.captureScreenshot(pid: pid, path: screenshotPath)
            guard success else {
                Output.printError(code: "LIVE_FRAME_FAILED", message: "Failed to capture live frame",
                                hint: nil, useJson: globals.useJson)
                throw ExitCode(2)
            }
        } else {
            Output.printError(code: "NOT_CONNECTED", message: "No active session for live capture",
                            hint: nil, useJson: globals.useJson)
            throw ExitCode(2)
        }

        // Apply processing to live frames too
        if let cropStr = crop {
            try Self.applyCrop(to: screenshotPath, cropStr: cropStr)
        }
        if grayscale {
            Self.applyGrayscale(to: screenshotPath)
        }
        if let maxW = maxWidth {
            Self.applyResize(to: screenshotPath, maxWidth: maxW)
        }
        var liveFinalPath = screenshotPath
        if format == "jpeg" {
            liveFinalPath = Self.convertToJpeg(path: screenshotPath, quality: quality ?? 80)
        }

        let ocrTexts: [OcrTextBlock]? = ocr ? Self.performOCR(imagePath: liveFinalPath) : nil
        let dims = Self.getImageDimensions(path: liveFinalPath)
        var updatedSession = session
        updatedSession.lastFramePath = liveFinalPath
        try store.save(updatedSession)

        let result = FrameResult(path: liveFinalPath, timestamp: at, source: "live", success: true,
                                width: dims?.0, height: dims?.1, skipped: false, reason: nil, similarity: nil, texts: ocrTexts)
        if globals.useJson {
            print(Output.json(result))
        } else {
            var msg = "Live frame captured → \(liveFinalPath)"
            if let texts = ocrTexts { msg += " [\(texts.count) text blocks]" }
            print(msg)
        }
    }

    // MARK: - Frame processing helpers (static for reuse by RecordFramesCommand)

    static func resolveSessionDir() -> String {
        if let home = ProcessInfo.processInfo.environment["AGENT_SWIFT_HOME"] {
            return home
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-swift").path
    }

    static func extractFrame(from video: String, at timestamp: Double, to outputPath: String, useJson: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ffmpeg", "-y", "-ss", String(timestamp), "-i", video, "-frames:v", "1", "-update", "1", outputPath]
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Output.printError(code: "FRAME_EXTRACT_FAILED", message: "Failed to run ffmpeg: \(error.localizedDescription)",
                            hint: nil, useJson: useJson)
            throw ExitCode(2)
        }
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: outputPath) else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lastLine = stderrText.components(separatedBy: "\n").last ?? ""
            let hint = lastLine.isEmpty
                ? "Video: \(video) — check if timestamp \(timestamp)s is within video duration"
                : "ffmpeg: \(lastLine)"
            Output.printError(code: "FRAME_EXTRACT_FAILED", message: "ffmpeg failed to extract frame at \(timestamp)s from \(video)",
                            hint: hint, useJson: useJson)
            throw ExitCode(2)
        }
    }

    static func applyResize(to path: String, maxWidth: Int) {
        // sips -Z resizes to fit within a square, but we want max-width only
        // Get current dimensions first
        guard let (w, _) = getImageDimensions(path: path), w > maxWidth else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["--resampleWidth", String(maxWidth), path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    static func applyCrop(to path: String, cropStr: String) throws {
        let parts = cropStr.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 4 else { return }
        var x = parts[0], y = parts[1], w = parts[2], h = parts[3]

        // Get current dimensions and clamp
        if let (imgW, imgH) = getImageDimensions(path: path) {
            x = max(0, min(x, imgW - 1))
            y = max(0, min(y, imgH - 1))
            w = min(w, imgW - x)
            h = min(h, imgH - y)
        }
        guard w > 0 && h > 0 else { return }

        // sips crop: --cropToHeightWidth <h> <w> removes from bottom-right,
        // then --cropOffset <y> <x> shifts the crop origin
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["--cropToHeightWidth", String(h), String(w), "--cropOffset", String(y), String(x), path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    static func getImageDimensions(path: String) -> (Int, Int)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["-g", "pixelWidth", "-g", "pixelHeight", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            var width: Int?, height: Int?
            for line in output.components(separatedBy: "\n") {
                if line.contains("pixelWidth") {
                    width = Int(line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
                } else if line.contains("pixelHeight") {
                    height = Int(line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
                }
            }
            if let w = width, let h = height { return (w, h) }
        } catch {}
        return nil
    }

    static func computeSimilarity(file1: String, file2: String) -> Double {
        // Thumbnail-based comparison: resize both to 32x32, compare pixel data
        let tmpDir = NSTemporaryDirectory()
        let thumb1 = "\(tmpDir)/dedup-thumb1.png"
        let thumb2 = "\(tmpDir)/dedup-thumb2.png"
        defer {
            try? FileManager.default.removeItem(atPath: thumb1)
            try? FileManager.default.removeItem(atPath: thumb2)
        }

        // Create thumbnails with sips
        for (src, dst) in [(file1, thumb1), (file2, thumb2)] {
            try? FileManager.default.copyItem(atPath: src, toPath: dst)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            process.arguments = ["-Z", "32", dst]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }

        // Load both as NSImage and compare pixel data
        guard let img1 = NSImage(contentsOfFile: thumb1),
              let img2 = NSImage(contentsOfFile: thumb2),
              let rep1 = img1.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) }),
              let rep2 = img2.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) }) else {
            return 0.0
        }

        let w = min(rep1.pixelsWide, rep2.pixelsWide)
        let h = min(rep1.pixelsHigh, rep2.pixelsHigh)
        guard w > 0 && h > 0 else { return 0.0 }

        var totalDiff: Double = 0
        var pixelCount = 0
        for y in 0..<h {
            for x in 0..<w {
                guard let c1 = rep1.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let c2 = rep2.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let dr = abs(c1.redComponent - c2.redComponent)
                let dg = abs(c1.greenComponent - c2.greenComponent)
                let db = abs(c1.blueComponent - c2.blueComponent)
                totalDiff += Double(dr + dg + db) / 3.0
                pixelCount += 1
            }
        }
        guard pixelCount > 0 else { return 0.0 }
        return 1.0 - (totalDiff / Double(pixelCount))
    }

    static func performOCR(imagePath: String) -> [OcrTextBlock] {
        guard let image = NSImage(contentsOfFile: imagePath),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            return []
        }

        let imgWidth = cgImage.width
        let imgHeight = cgImage.height

        var results: [OcrTextBlock] = []
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let bbox = observation.boundingBox
                // Vision: normalized (0-1), origin at bottom-left → pixel coords, origin at top-left
                let x = Int(bbox.origin.x * Double(imgWidth))
                let y = Int(Double(imgHeight) - (bbox.origin.y + bbox.height) * Double(imgHeight))
                let w = Int(bbox.width * Double(imgWidth))
                let h = Int(bbox.height * Double(imgHeight))
                results.append(OcrTextBlock(
                    text: candidate.string,
                    x: x, y: y, width: w, height: h,
                    confidence: Double(candidate.confidence)
                ))
            }
        }
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        // Sort top-to-bottom, left-to-right
        results.sort { ($0.y, $0.x) < ($1.y, $1.x) }
        return results
    }

    static func applyGrayscale(to path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["--matchTo", "/System/Library/ColorSync/Profiles/Generic Gray Profile.icc", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    static func convertToJpeg(path: String, quality: Int) -> String {
        // Change extension from .png to .jpg
        let jpegPath: String
        if path.hasSuffix(".png") {
            jpegPath = String(path.dropLast(4)) + ".jpg"
        } else {
            jpegPath = path + ".jpg"
        }
        // Copy then convert (sips modifies in-place)
        try? FileManager.default.copyItem(atPath: path, toPath: jpegPath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["--setProperty", "format", "jpeg", "--setProperty", "formatOptions", String(quality), jpegPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        // Remove original PNG
        try? FileManager.default.removeItem(atPath: path)
        return jpegPath
    }

    static func isFfmpegAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ffmpeg", "-version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

struct RecordStatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show recording state")

    @OptionGroup var globals: GlobalOptions

    struct StatusResult: Codable {
        let active: Bool
        let sessionId: String?
        let videoPath: String?
        let startTime: String?
        let elapsedSeconds: Double?
        let mode: String?
    }

    func run() throws {
        let store = SessionStore()
        let session = store.load()

        if let recording = session.recording {
            let isAlive = kill(recording.pid, 0) == 0
            var elapsed: Double? = nil
            if let startDate = ISO8601DateFormatter().date(from: recording.startTime) {
                elapsed = Date().timeIntervalSince(startDate)
            }

            if isAlive {
                let result = StatusResult(
                    active: true,
                    sessionId: recording.sessionId,
                    videoPath: recording.videoPath,
                    startTime: recording.startTime,
                    elapsedSeconds: elapsed,
                    mode: recording.mode
                )
                if globals.useJson {
                    print(Output.json(result))
                } else {
                    print("Recording active (session: \(recording.sessionId), mode: \(recording.mode))")
                    if let e = elapsed {
                        print("Elapsed: \(String(format: "%.1f", e))s")
                    }
                    print("Video: \(recording.videoPath)")
                }
            } else {
                // Process dead but recording wasn't cleaned up
                let result = StatusResult(active: false, sessionId: recording.sessionId,
                                         videoPath: recording.videoPath, startTime: recording.startTime,
                                         elapsedSeconds: nil, mode: recording.mode)
                if globals.useJson {
                    print(Output.json(result))
                } else {
                    print("Recording inactive (stale session: \(recording.sessionId))")
                    print("Video may be at: \(recording.videoPath)")
                }
            }
        } else {
            let result = StatusResult(active: false, sessionId: nil, videoPath: nil,
                                     startTime: nil, elapsedSeconds: nil, mode: nil)
            if globals.useJson {
                print(Output.json(result))
            } else {
                print("No active recording")
            }
        }
    }
}

// MARK: - Batch frame extraction

struct RecordFramesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "frames",
        abstract: "Extract multiple frames from a video",
        discussion: """
            Batch frame extraction with optional dedup, resize, and OCR.
            Use --every for regular intervals, --at for specific timestamps,
            or --keyframes for automatic scene-change detection.
            """
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Path to video file (required)")
    var video: String

    @Option(name: .long, help: "Extract one frame every N seconds")
    var every: Double?

    @Option(name: .long, help: "Specific timestamps (comma-separated, e.g. 1.0,5.0,10.0)")
    var at: String?

    @Flag(name: .long, help: "Auto-detect scene changes (mutually exclusive with --every/--at)")
    var keyframes: Bool = false

    @Option(name: .long, help: "Max width in pixels — downscale to fit (no upscale)")
    var maxWidth: Int?

    @Option(name: .long, help: "Skip if similarity to previous frame >= threshold (0.0-1.0)")
    var dedupThreshold: Double?

    @Option(name: .long, help: "Output directory (default: session dir)")
    var outputDir: String?

    @Flag(name: .long, help: "Convert to grayscale (reduces file size ~3x)")
    var grayscale: Bool = false

    @Option(name: .long, help: "Output format: png (default) or jpeg")
    var format: String?

    @Option(name: .long, help: "JPEG quality 1-100 (default: 80, only with --format jpeg)")
    var quality: Int?

    @Flag(name: .long, help: "Extract text via Vision OCR for each frame")
    var ocr: Bool = false

    struct BatchFrameEntry: Codable {
        let path: String
        let timestamp: Double
        let skipped: Bool
        let width: Int?
        let height: Int?
        let similarity: Double?
        let texts: [RecordFrameCommand.OcrTextBlock]?
    }

    struct BatchResult: Codable {
        let video: String
        let frames: [BatchFrameEntry]
        let extracted: Int
        let skipped: Int
        let total: Int
        let totalScanned: Int?
    }

    func run() throws {
        guard FileManager.default.fileExists(atPath: video) else {
            Output.printError(code: "VIDEO_NOT_FOUND", message: "Video file does not exist: \(video)",
                            hint: "Check the path", useJson: globals.useJson)
            throw ExitCode(2)
        }

        guard RecordFrameCommand.isFfmpegAvailable() else {
            Output.printError(code: "FFMPEG_NOT_FOUND", message: "ffmpeg is not installed",
                            hint: "Install with: brew install ffmpeg", useJson: globals.useJson)
            throw ExitCode(2)
        }

        if let fmt = format {
            guard fmt == "png" || fmt == "jpeg" else {
                Output.printError(code: "INVALID_ARGS", message: "format must be 'png' or 'jpeg'",
                                hint: "Example: --format jpeg --quality 60", useJson: globals.useJson)
                throw ExitCode(2)
            }
        }

        if let q = quality {
            guard q >= 1 && q <= 100 else {
                Output.printError(code: "INVALID_ARGS", message: "quality must be between 1 and 100",
                                hint: "Example: --quality 80", useJson: globals.useJson)
                throw ExitCode(2)
            }
            guard format == "jpeg" else {
                Output.printError(code: "INVALID_ARGS", message: "--quality requires --format jpeg",
                                hint: "Example: --format jpeg --quality 60", useJson: globals.useJson)
                throw ExitCode(2)
            }
        }

        // Get video duration
        guard let duration = RecordStopCommand.getVideoDuration(path: video) else {
            Output.printError(code: "VIDEO_READ_FAILED", message: "Could not read video duration",
                            hint: "Check if the video file is valid", useJson: globals.useJson)
            throw ExitCode(2)
        }

        // Keyframes mode vs timestamp mode
        if keyframes {
            guard every == nil && at == nil else {
                Output.printError(code: "INVALID_ARGS", message: "--keyframes is mutually exclusive with --every and --at",
                                hint: "Use --keyframes alone, or --every/--at without --keyframes", useJson: globals.useJson)
                throw ExitCode(2)
            }
            try runKeyframeExtraction(duration: duration)
            return
        }

        // Build timestamp list
        var timestamps: [Double] = []
        if let everyN = every {
            guard everyN > 0 else {
                Output.printError(code: "INVALID_ARGS", message: "--every must be > 0",
                                hint: "Example: --every 2.0", useJson: globals.useJson)
                throw ExitCode(2)
            }
            var t = 0.0
            while t < duration {
                timestamps.append(t)
                t += everyN
            }
        } else if let atStr = at {
            timestamps = atStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard !timestamps.isEmpty else {
                Output.printError(code: "INVALID_ARGS", message: "No valid timestamps in --at",
                                hint: "Example: --at 1.0,5.0,10.0", useJson: globals.useJson)
                throw ExitCode(2)
            }
        } else {
            Output.printError(code: "INVALID_ARGS", message: "Specify --every, --at, or --keyframes",
                            hint: "Example: --every 2.0 or --at 1.0,5.0,10.0 or --keyframes", useJson: globals.useJson)
            throw ExitCode(2)
        }

        // Determine output directory
        let outDir = outputDir ?? RecordFrameCommand.resolveSessionDir()
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        var results: [BatchFrameEntry] = []
        var lastExtractedPath: String? = nil
        var extractedCount = 0
        var skippedCount = 0

        for ts in timestamps {
            let outputPath = "\(outDir)/frame-\(String(format: "%.1f", ts))s.png"

            do {
                try RecordFrameCommand.extractFrame(from: video, at: ts, to: outputPath, useJson: globals.useJson)
            } catch {
                continue
            }

            // Apply crop (if crop were supported on batch — currently not, reserved for single frame)

            // Apply grayscale
            if grayscale {
                RecordFrameCommand.applyGrayscale(to: outputPath)
            }

            // Apply resize
            if let maxW = maxWidth {
                RecordFrameCommand.applyResize(to: outputPath, maxWidth: maxW)
            }

            // Apply format conversion
            var finalPath = outputPath
            if format == "jpeg" {
                finalPath = RecordFrameCommand.convertToJpeg(path: outputPath, quality: quality ?? 80)
            }

            // Dedup check
            if let threshold = dedupThreshold, let lastPath = lastExtractedPath,
               FileManager.default.fileExists(atPath: lastPath) {
                let similarity = RecordFrameCommand.computeSimilarity(file1: lastPath, file2: finalPath)
                if similarity >= threshold {
                    try? FileManager.default.removeItem(atPath: finalPath)
                    results.append(BatchFrameEntry(path: finalPath, timestamp: ts, skipped: true,
                                                   width: nil, height: nil, similarity: similarity, texts: nil))
                    skippedCount += 1
                    continue
                }
            }

            // OCR
            let ocrTexts: [RecordFrameCommand.OcrTextBlock]? = ocr ? RecordFrameCommand.performOCR(imagePath: finalPath) : nil

            let dims = RecordFrameCommand.getImageDimensions(path: finalPath)
            results.append(BatchFrameEntry(path: finalPath, timestamp: ts, skipped: false,
                                           width: dims?.0, height: dims?.1, similarity: nil, texts: ocrTexts))
            lastExtractedPath = finalPath
            extractedCount += 1
        }

        let batchResult = BatchResult(video: video, frames: results, extracted: extractedCount,
                                      skipped: skippedCount, total: results.count, totalScanned: nil)
        if globals.useJson {
            print(Output.json(batchResult))
        } else {
            print("Extracted \(extractedCount) frames, skipped \(skippedCount) (total \(results.count))")
            for f in results where !f.skipped {
                var line = "  \(String(format: "%.1f", f.timestamp))s → \(f.path)"
                if let w = f.width, let h = f.height { line += " (\(w)×\(h))" }
                if let texts = f.texts { line += " [\(texts.count) texts]" }
                print(line)
            }
        }
    }

    private func runKeyframeExtraction(duration: Double) throws {
        let scanInterval = 0.5  // Scan every 0.5 seconds
        let threshold = dedupThreshold ?? 0.92  // Default keyframe threshold

        let outDir = outputDir ?? RecordFrameCommand.resolveSessionDir()
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        var results: [BatchFrameEntry] = []
        var lastExtractedPath: String? = nil
        var extractedCount = 0
        var skippedCount = 0
        var totalScanned = 0

        var t = 0.0
        while t < duration {
            totalScanned += 1
            let tmpPath = "\(outDir)/keyframe-scan-\(String(format: "%.1f", t))s.png"

            do {
                try RecordFrameCommand.extractFrame(from: video, at: t, to: tmpPath, useJson: globals.useJson)
            } catch {
                t += scanInterval
                continue
            }

            var shouldExtract = false

            if lastExtractedPath == nil {
                // Always extract first frame
                shouldExtract = true
            } else if let lastPath = lastExtractedPath, FileManager.default.fileExists(atPath: lastPath) {
                let similarity = RecordFrameCommand.computeSimilarity(file1: lastPath, file2: tmpPath)
                if similarity < threshold {
                    shouldExtract = true
                }
            }

            if shouldExtract {
                let finalName = "keyframe-\(String(format: "%.1f", t))s.png"
                let outputPath = "\(outDir)/\(finalName)"
                if tmpPath != outputPath {
                    try? FileManager.default.removeItem(atPath: outputPath)
                    try FileManager.default.moveItem(atPath: tmpPath, toPath: outputPath)
                }

                // Apply processing
                if grayscale {
                    RecordFrameCommand.applyGrayscale(to: outputPath)
                }
                if let maxW = maxWidth {
                    RecordFrameCommand.applyResize(to: outputPath, maxWidth: maxW)
                }
                var finalPath = outputPath
                if format == "jpeg" {
                    finalPath = RecordFrameCommand.convertToJpeg(path: outputPath, quality: quality ?? 80)
                }

                let ocrTexts: [RecordFrameCommand.OcrTextBlock]? = ocr ? RecordFrameCommand.performOCR(imagePath: finalPath) : nil
                let dims = RecordFrameCommand.getImageDimensions(path: finalPath)
                results.append(BatchFrameEntry(path: finalPath, timestamp: t, skipped: false,
                                               width: dims?.0, height: dims?.1, similarity: nil, texts: ocrTexts))
                lastExtractedPath = finalPath
                extractedCount += 1
            } else {
                try? FileManager.default.removeItem(atPath: tmpPath)
                skippedCount += 1
            }

            t += scanInterval
        }

        // Always extract last frame if not already extracted
        let lastTs = max(0, duration - 0.1)
        if let lastResult = results.last, lastResult.timestamp < lastTs - scanInterval {
            let tmpPath = "\(outDir)/keyframe-scan-last.png"
            do {
                try RecordFrameCommand.extractFrame(from: video, at: lastTs, to: tmpPath, useJson: globals.useJson)
                let outputPath = "\(outDir)/keyframe-\(String(format: "%.1f", lastTs))s.png"
                try? FileManager.default.removeItem(atPath: outputPath)
                try FileManager.default.moveItem(atPath: tmpPath, toPath: outputPath)

                if grayscale { RecordFrameCommand.applyGrayscale(to: outputPath) }
                if let maxW = maxWidth { RecordFrameCommand.applyResize(to: outputPath, maxWidth: maxW) }
                var finalPath = outputPath
                if format == "jpeg" {
                    finalPath = RecordFrameCommand.convertToJpeg(path: outputPath, quality: quality ?? 80)
                }

                let ocrTexts: [RecordFrameCommand.OcrTextBlock]? = ocr ? RecordFrameCommand.performOCR(imagePath: finalPath) : nil
                let dims = RecordFrameCommand.getImageDimensions(path: finalPath)
                results.append(BatchFrameEntry(path: finalPath, timestamp: lastTs, skipped: false,
                                               width: dims?.0, height: dims?.1, similarity: nil, texts: ocrTexts))
                extractedCount += 1
                totalScanned += 1
            } catch {
                // Last frame extraction failed — not critical
            }
        }

        let batchResult = BatchResult(video: video, frames: results, extracted: extractedCount,
                                      skipped: skippedCount, total: results.count, totalScanned: totalScanned)
        if globals.useJson {
            print(Output.json(batchResult))
        } else {
            print("Keyframes: extracted \(extractedCount), skipped \(skippedCount) (scanned \(totalScanned) at \(scanInterval)s intervals)")
            for f in results {
                var line = "  \(String(format: "%.1f", f.timestamp))s → \(f.path)"
                if let w = f.width, let h = f.height { line += " (\(w)×\(h))" }
                if let texts = f.texts { line += " [\(texts.count) texts]" }
                print(line)
            }
        }
    }
}

// MARK: - Schema

// CommandSchema is defined in AgentSwiftLib/Output/CommandSchema.swift

func allSchemas() -> [CommandSchema] { return [
    CommandSchema(name: "doctor", description: "Check prerequisites and diagnose issues",
        args: [], flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "connect", description: "Connect to a macOS app, iOS Simulator, or iPhone Mirroring",
        args: [], flags: [
            .init(name: "--pid", type: "int", defaultValue: nil),
            .init(name: "--bundle-id", type: "string", defaultValue: nil),
            .init(name: "--simulator", type: "string", defaultValue: nil),
            .init(name: "--udid", type: "string", defaultValue: nil),
            .init(name: "--sim", type: "bool", defaultValue: "false"),
            .init(name: "--mirror", type: "bool", defaultValue: "false"),
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
            .init(name: "--all", type: "bool", defaultValue: "false"),
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
    CommandSchema(name: "find", description: "Find element by locator (supports compound: find role button text Open press)",
        args: [.init(name: "remaining", type: "string...", required: true)],
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
    CommandSchema(name: "type", description: "Type text into focused field",
        args: [.init(name: "text", type: "string", required: true)],
        flags: [.init(name: "--json", type: "bool", defaultValue: "false")],
        exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "swipe", description: "Swipe gesture by coordinates",
        args: [.init(name: "fromX", type: "number", required: true),
               .init(name: "fromY", type: "number", required: true),
               .init(name: "toX", type: "number", required: true),
               .init(name: "toY", type: "number", required: true)],
        flags: [
            .init(name: "--duration", type: "number", defaultValue: "0.3"),
            .init(name: "--json", type: "bool", defaultValue: "false")
        ], exitCodes: ["0": "success", "2": "error"]),
    CommandSchema(name: "record", description: "Screen video recording (start/stop/frame/frames/status). Workflow: record stop → get videoPath → record frame --video <path> --at <seconds>. Use record frames for batch extraction with --every, --at, or --keyframes. Token optimization: --ocr for text extraction, --grayscale/--format jpeg for smaller files, --keyframes for scene-change detection.",
        args: [],
        flags: [
            .init(name: "--at", type: "number", defaultValue: nil),
            .init(name: "--video", type: "string", defaultValue: nil),
            .init(name: "--output", type: "string", defaultValue: nil),
            .init(name: "--max-width", type: "int", defaultValue: nil),
            .init(name: "--crop", type: "string", defaultValue: nil),
            .init(name: "--dedup-threshold", type: "number", defaultValue: nil),
            .init(name: "--grayscale", type: "bool", defaultValue: "false"),
            .init(name: "--format", type: "string", defaultValue: "png"),
            .init(name: "--quality", type: "int", defaultValue: "80"),
            .init(name: "--ocr", type: "bool", defaultValue: "false"),
            .init(name: "--keyframes", type: "bool", defaultValue: "false"),
            .init(name: "--every", type: "number", defaultValue: nil),
            .init(name: "--output-dir", type: "string", defaultValue: nil),
            .init(name: "--json", type: "bool", defaultValue: "false")
        ], exitCodes: ["0": "success", "2": "error"]),
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
