import Foundation

public enum IdbError: Error, CustomStringConvertible {
    case notFound
    case commandFailed(String)
    case parseFailed(String)
    case accessibilityDisabled

    public var code: String {
        switch self {
        case .notFound: return "IDB_NOT_FOUND"
        case .commandFailed: return "IDB_COMMAND_FAILED"
        case .parseFailed: return "IDB_PARSE_FAILED"
        case .accessibilityDisabled: return "IDB_ACCESSIBILITY_DISABLED"
        }
    }

    public var hint: String? {
        switch self {
        case .notFound:
            return "Install idb: brew install facebook/fb/idb-companion facebook/fb/idb-cli"
        case .commandFailed(let msg):
            return "idb command failed: \(msg)"
        case .parseFailed:
            return "Failed to parse idb output"
        case .accessibilityDisabled:
            return "Enable accessibility: xcrun simctl spawn <UDID> defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool true"
        }
    }

    public var description: String {
        switch self {
        case .notFound: return "idb CLI not found"
        case .commandFailed(let msg): return "idb command failed: \(msg)"
        case .parseFailed(let msg): return "Failed to parse idb output: \(msg)"
        case .accessibilityDisabled: return "Simulator accessibility is not enabled"
        }
    }
}

public struct IdbElement {
    public let type: String
    public let role: String
    public let label: String?
    public let value: String?
    public let frame: CGRect
    public let uniqueId: String?
    public let enabled: Bool
    public let children: [IdbElement]

    public var centerPoint: CGPoint {
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    public var isInteractive: Bool {
        let interactiveTypes = ["Button", "TextField", "SecureTextField", "TextArea",
                                "CheckBox", "RadioButton", "Slider", "Switch",
                                "Link", "MenuItem", "Tab", "Cell"]
        return interactiveTypes.contains(type)
            || type.contains("Button")
            || type.contains("Field")
            || type.contains("Cell")
    }

    public var displayType: String {
        return type.lowercased()
    }

    public var displayLabel: String? {
        return label ?? value
    }

    public func toAXNode() -> AXNode {
        let pos = CGPoint(x: frame.origin.x, y: frame.origin.y)
        let sz = CGSize(width: frame.width, height: frame.height)
        return AXNode(
            role: role,
            subrole: nil,
            title: label,
            axDescription: nil,
            value: value,
            identifier: uniqueId,
            childStaticText: nil,
            enabled: enabled,
            focused: false,
            position: pos,
            size: sz,
            actions: isInteractive ? ["AXPress"] : [],
            children: []
        )
    }
}

public struct IdbBridge {
    public let udid: String

    public init(udid: String) {
        self.udid = udid
    }

    public func describeAll(includeAll: Bool = false) throws -> [IdbElement] {
        guard Self.isIdbAvailable() else {
            throw IdbError.notFound
        }

        let args = ["ui", "describe-all", "--udid", udid, "--nested", "--json"]
        let (output, exitCode) = Self.runIdb(args)
        guard exitCode == 0 else {
            if output.contains("accessibility server has not started") || output.contains("ApplicationAccessibilityEnabled") {
                throw IdbError.accessibilityDisabled
            }
            throw IdbError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let data = output.data(using: .utf8) else {
            throw IdbError.parseFailed("empty output")
        }

        return try Self.parseDescribeAll(data)
    }

    public func tap(x: Double, y: Double) throws {
        guard Self.isIdbAvailable() else { throw IdbError.notFound }
        let (output, exitCode) = Self.runIdb(["ui", "tap", String(Int(x)), String(Int(y)), "--udid", udid])
        guard exitCode == 0 else {
            throw IdbError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func text(input: String) throws {
        guard Self.isIdbAvailable() else { throw IdbError.notFound }
        let (output, exitCode) = Self.runIdb(["ui", "text", input, "--udid", udid])
        guard exitCode == 0 else {
            throw IdbError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, duration: Double? = nil) throws {
        guard Self.isIdbAvailable() else { throw IdbError.notFound }
        var args = ["ui", "swipe", String(Int(fromX)), String(Int(fromY)),
                    String(Int(toX)), String(Int(toY)), "--udid", udid]
        if let d = duration {
            args += ["--duration", String(d)]
        }
        let (output, exitCode) = Self.runIdb(args)
        guard exitCode == 0 else {
            throw IdbError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func enableAccessibility() throws {
        let (output, exitCode) = SimulatorBridge.runSimctl([
            "spawn", udid, "defaults", "write",
            "com.apple.Accessibility", "ApplicationAccessibilityEnabled", "-bool", "true"
        ])
        guard exitCode == 0 else {
            throw IdbError.commandFailed("Failed to enable accessibility: \(output)")
        }
    }

    public static func isIdbAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["idb"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Parsing

    static func parseDescribeAll(_ data: Data) throws -> [IdbElement] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw IdbError.parseFailed("expected JSON array")
        }

        var result: [IdbElement] = []
        for item in json {
            result.append(contentsOf: flattenElement(item))
        }
        return result
    }

    static func flattenElement(_ dict: [String: Any]) -> [IdbElement] {
        let element = parseElement(dict)
        var result = [element]
        for child in element.children {
            result.append(child)
            result.append(contentsOf: flattenChildren(child))
        }
        return result
    }

    private static func flattenChildren(_ element: IdbElement) -> [IdbElement] {
        var result: [IdbElement] = []
        for child in element.children {
            result.append(child)
            result.append(contentsOf: flattenChildren(child))
        }
        return result
    }

    static func parseElement(_ dict: [String: Any]) -> IdbElement {
        let type = dict["type"] as? String ?? "Unknown"
        let role = dict["role"] as? String ?? "AXUnknown"
        let label = dict["AXLabel"] as? String
        let value: String?
        if let v = dict["AXValue"] {
            if v is NSNull {
                value = nil
            } else {
                value = "\(v)"
            }
        } else {
            value = nil
        }
        let uniqueId = dict["AXUniqueId"] as? String
        let enabled = dict["enabled"] as? Bool ?? false

        var frame = CGRect.zero
        if let frameDict = dict["frame"] as? [String: Any] {
            let x = (frameDict["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (frameDict["y"] as? NSNumber)?.doubleValue ?? 0
            let w = (frameDict["width"] as? NSNumber)?.doubleValue ?? 0
            let h = (frameDict["height"] as? NSNumber)?.doubleValue ?? 0
            frame = CGRect(x: x, y: y, width: w, height: h)
        }

        var children: [IdbElement] = []
        if let childDicts = dict["children"] as? [[String: Any]] {
            children = childDicts.map { parseElement($0) }
        }

        return IdbElement(
            type: type,
            role: role,
            label: label,
            value: value,
            frame: frame,
            uniqueId: uniqueId,
            enabled: enabled,
            children: children
        )
    }

    public static func directionToSwipeCoords(direction: String, screenWidth: Double = 402, screenHeight: Double = 874) -> (fromX: Double, fromY: Double, toX: Double, toY: Double) {
        let cx = screenWidth / 2
        let cy = screenHeight / 2
        let swipeDistance = screenHeight * 0.4

        switch direction {
        case "up":
            return (cx, cy + swipeDistance / 2, cx, cy - swipeDistance / 2)
        case "down":
            return (cx, cy - swipeDistance / 2, cx, cy + swipeDistance / 2)
        case "left":
            return (cx + swipeDistance / 2, cy, cx - swipeDistance / 2, cy)
        case "right":
            return (cx - swipeDistance / 2, cy, cx + swipeDistance / 2, cy)
        default:
            return (cx, cy + swipeDistance / 2, cx, cy - swipeDistance / 2)
        }
    }

    // MARK: - Process

    static func resolveIdbPath() -> String {
        // Check environment override first
        if let envPath = ProcessInfo.processInfo.environment["IDB_PATH"], !envPath.isEmpty {
            return envPath
        }
        // Resolve via which
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["idb"]
        let whichPipe = Pipe()
        whichProcess.standardOutput = whichPipe
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty && whichProcess.terminationStatus == 0 { return path }
        } catch { /* fall through to default */ }
        return "idb"
    }

    static func runIdb(_ args: [String]) -> (String, Int32) {
        let idbPath = resolveIdbPath()
        let process = Process()
        if idbPath == "idb" {
            // Use /usr/bin/env to resolve from PATH
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["idb"] + args
        } else {
            process.executableURL = URL(fileURLWithPath: idbPath)
            process.arguments = args
        }
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("Failed to run idb: \(error)", 1)
        }
        let stdout = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout.isEmpty ? stderr : stdout, process.terminationStatus)
    }
}
