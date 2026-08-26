import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum SimulatorError: Error, CustomStringConvertible {
    case noBootedDevice
    case deviceNotFound(String)
    case deviceNotBooted(String)
    case simctlFailed(String)
    case simulatorAppNotRunning
    case windowNotFound
    case screenshotFailed(String)

    public var code: String {
        switch self {
        case .noBootedDevice: return "SIM_NO_BOOTED"
        case .deviceNotFound: return "SIM_NOT_FOUND"
        case .deviceNotBooted: return "SIM_NOT_BOOTED"
        case .simctlFailed: return "SIM_SIMCTL_FAILED"
        case .simulatorAppNotRunning: return "SIM_APP_NOT_RUNNING"
        case .windowNotFound: return "SIM_WINDOW_NOT_FOUND"
        case .screenshotFailed: return "SIM_SCREENSHOT_FAILED"
        }
    }

    public var hint: String? {
        switch self {
        case .noBootedDevice:
            return "Boot a simulator: xcrun simctl boot <udid>"
        case .deviceNotFound(let udid):
            return "Check available devices: xcrun simctl list devices. UDID: \(udid)"
        case .deviceNotBooted(let udid):
            return "Boot this device: xcrun simctl boot \(udid)"
        case .simctlFailed:
            return "Ensure Xcode is installed: xcode-select -p"
        case .simulatorAppNotRunning:
            return "Open Simulator: open -a Simulator"
        case .windowNotFound:
            return "Ensure the Simulator window is visible"
        case .screenshotFailed:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .noBootedDevice: return "No booted iOS Simulator found"
        case .deviceNotFound(let udid): return "Simulator device not found: \(udid)"
        case .deviceNotBooted(let udid): return "Simulator device is not booted: \(udid)"
        case .simctlFailed(let msg): return "simctl command failed: \(msg)"
        case .simulatorAppNotRunning: return "Simulator.app is not running"
        case .windowNotFound: return "Could not find Simulator window"
        case .screenshotFailed(let msg): return "Screenshot failed: \(msg)"
        }
    }
}

public struct SimDeviceInfo {
    public let udid: String
    public let name: String
    public let deviceTypeIdentifier: String
    public let state: String

    public var isBooted: Bool { state == "Booted" }

    public var shortName: String {
        if let range = deviceTypeIdentifier.range(of: ".", options: .backwards) {
            return String(deviceTypeIdentifier[range.upperBound...]).replacingOccurrences(of: "-", with: " ")
        }
        return name
    }
}

public struct SimWindowInfo {
    public let windowOrigin: CGPoint
    public let contentSize: CGSize
    public let deviceSize: CGSize
    public let scale: CGFloat

    public init(windowOrigin: CGPoint, contentSize: CGSize, deviceSize: CGSize) {
        self.windowOrigin = windowOrigin
        self.contentSize = contentSize
        self.deviceSize = deviceSize
        self.scale = deviceSize.width > 0 ? contentSize.width / deviceSize.width : 1.0
    }
}

public struct SimulatorBridge {
    public let udid: String

    public init(udid: String) {
        self.udid = udid
    }

    public static func bootedDevice() throws -> SimulatorBridge {
        let devices = try listDevices()
        guard let booted = devices.first(where: { $0.isBooted }) else {
            throw SimulatorError.noBootedDevice
        }
        return SimulatorBridge(udid: booted.udid)
    }

    public static func device(udid: String) throws -> SimulatorBridge {
        let devices = try listDevices()
        guard let device = devices.first(where: { $0.udid == udid }) else {
            throw SimulatorError.deviceNotFound(udid)
        }
        guard device.isBooted else {
            throw SimulatorError.deviceNotBooted(udid)
        }
        return SimulatorBridge(udid: device.udid)
    }

    public static func listDevices() throws -> [SimDeviceInfo] {
        let (output, exitCode) = runSimctl(["list", "devices", "-j"])
        guard exitCode == 0, let data = output.data(using: .utf8) else {
            throw SimulatorError.simctlFailed("list devices failed")
        }
        return try parseDeviceList(data)
    }

    public func deviceInfo() throws -> SimDeviceInfo {
        let devices = try Self.listDevices()
        guard let device = devices.first(where: { $0.udid == udid }) else {
            throw SimulatorError.deviceNotFound(udid)
        }
        return device
    }

    public func screenshot(to path: String) throws {
        let (output, exitCode) = Self.runSimctl(["io", udid, "screenshot", "--type=png", path])
        guard exitCode == 0 else {
            throw SimulatorError.screenshotFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func deviceScreenSize() throws -> CGSize {
        let (output, exitCode) = Self.runSimctl(["io", udid, "enumerate"])
        guard exitCode == 0 else {
            throw SimulatorError.simctlFailed("io enumerate failed")
        }
        if let size = parseScreenSize(from: output) {
            return size
        }
        return defaultDeviceSize()
    }

    #if canImport(AppKit)
    public func windowInfo() throws -> SimWindowInfo {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator")
        guard let simApp = apps.first else {
            throw SimulatorError.simulatorAppNotRunning
        }

        let pid = simApp.processIdentifier
        let simAX = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(simAX, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            throw SimulatorError.windowNotFound
        }

        // Find the window matching our device name
        var targetWindow: AXUIElement = windows[0]
        let info = try? deviceInfo()
        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            if let title = titleRef as? String, let deviceName = info?.name, title.contains(deviceName) {
                targetWindow = window
                break
            }
        }

        var pos = CGPoint.zero
        var size = CGSize.zero
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(targetWindow, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(targetWindow, kAXSizeAttribute as CFString, &sizeRef)
        if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }

        let toolbarHeight: CGFloat = 52
        let contentOrigin = CGPoint(x: pos.x, y: pos.y + toolbarHeight)
        let contentSize = CGSize(width: size.width, height: size.height - toolbarHeight)

        let deviceSize = (try? deviceScreenSize()) ?? defaultDeviceSize()

        return SimWindowInfo(windowOrigin: contentOrigin, contentSize: contentSize, deviceSize: deviceSize)
    }
    #endif

    public static func iosPointToScreen(_ point: CGPoint, windowInfo: SimWindowInfo) -> CGPoint {
        return CGPoint(
            x: windowInfo.windowOrigin.x + point.x * windowInfo.scale,
            y: windowInfo.windowOrigin.y + point.y * windowInfo.scale
        )
    }

    public static func isSimulatorRunning() -> Bool {
        #if canImport(AppKit)
        return !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator").isEmpty
        #else
        return false
        #endif
    }

    #if canImport(AppKit)
    public func tap(x: Double, y: Double) throws {
        let info = try windowInfo()
        let screenPoint = Self.iosPointToScreen(CGPoint(x: x, y: y), windowInfo: info)

        Self.activateSimulator()

        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                       mouseCursorPosition: screenPoint, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                     mouseCursorPosition: screenPoint, mouseButton: .left) else {
            throw SimulatorError.simctlFailed("cannot create CGEvent for tap")
        }
        mouseDown.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        mouseUp.post(tap: .cgSessionEventTap)
    }

    public func swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, duration: Double? = nil) throws {
        let info = try windowInfo()
        let startPoint = Self.iosPointToScreen(CGPoint(x: fromX, y: fromY), windowInfo: info)
        let endPoint = Self.iosPointToScreen(CGPoint(x: toX, y: toY), windowInfo: info)

        Self.activateSimulator()

        let swipeDuration = duration ?? 0.3
        let steps = max(Int(swipeDuration * 60), 10)
        let dx = (endPoint.x - startPoint.x) / Double(steps)
        let dy = (endPoint.y - startPoint.y) / Double(steps)
        let stepDelay = swipeDuration / Double(steps)

        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                       mouseCursorPosition: startPoint, mouseButton: .left) else {
            throw SimulatorError.simctlFailed("cannot create mouseDown event")
        }
        mouseDown.post(tap: .cgSessionEventTap)

        for i in 1...steps {
            let current = CGPoint(x: startPoint.x + dx * Double(i), y: startPoint.y + dy * Double(i))
            guard let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                      mouseCursorPosition: current, mouseButton: .left) else {
                continue
            }
            drag.post(tap: .cgSessionEventTap)
            Thread.sleep(forTimeInterval: stepDelay)
        }

        guard let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                     mouseCursorPosition: endPoint, mouseButton: .left) else {
            throw SimulatorError.simctlFailed("cannot create mouseUp event")
        }
        mouseUp.post(tap: .cgSessionEventTap)
    }

    private static func activateSimulator() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator").first {
            app.activate()
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    #endif

    public static func directionToSwipeCoords(direction: String, screenWidth: Double = 393, screenHeight: Double = 852) -> (fromX: Double, fromY: Double, toX: Double, toY: Double) {
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

    // MARK: - Internal

    static func runSimctl(_ args: [String]) -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + args
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("Failed to run xcrun simctl: \(error)", 1)
        }
        let stdout = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout.isEmpty ? stderr : stdout, process.terminationStatus)
    }

    static func parseDeviceList(_ data: Data) throws -> [SimDeviceInfo] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesByRuntime = json["devices"] as? [String: [[String: Any]]] else {
            throw SimulatorError.simctlFailed("Invalid device list JSON")
        }

        var result: [SimDeviceInfo] = []
        for (runtime, devices) in devicesByRuntime {
            guard runtime.contains("iOS") || runtime.contains("iphone") else { continue }
            for device in devices {
                guard let udid = device["udid"] as? String,
                      let name = device["name"] as? String,
                      let state = device["state"] as? String else { continue }
                let deviceType = device["deviceTypeIdentifier"] as? String ?? ""
                result.append(SimDeviceInfo(udid: udid, name: name, deviceTypeIdentifier: deviceType, state: state))
            }
        }
        return result
    }

    func parseScreenSize(from enumerateOutput: String) -> CGSize? {
        // Try "Width: N, Height: N" (simctl io enumerate format)
        let pattern1 = #"Width:\s*(\d+).*?Height:\s*(\d+)"#
        // Fallback: "NxN" or "N x N"
        let pattern2 = #"(\d+)\s*x\s*(\d+)"#

        for pattern in [pattern1, pattern2] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
                  let match = regex.firstMatch(in: enumerateOutput, range: NSRange(enumerateOutput.startIndex..., in: enumerateOutput)),
                  let wRange = Range(match.range(at: 1), in: enumerateOutput),
                  let hRange = Range(match.range(at: 2), in: enumerateOutput),
                  let w = Double(enumerateOutput[wRange]),
                  let h = Double(enumerateOutput[hRange]) else {
                continue
            }
            // Native pixels → logical points (3x Retina for modern iPhones)
            return CGSize(width: w / 3.0, height: h / 3.0)
        }
        return nil
    }

    func defaultDeviceSize() -> CGSize {
        return CGSize(width: 393, height: 852)
    }
}
