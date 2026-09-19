import Foundation
#if canImport(AppKit)
import AppKit
import ApplicationServices
#endif

/// Provides AXUIElement-based fallback for iOS Simulator accessibility.
/// When idb ui describe-all fails (e.g., iOS 26+ compatibility), this bridge
/// walks the Simulator.app's AX tree to get element information.
public struct SimAXBridge {
    public let udid: String

    public init(udid: String) {
        self.udid = udid
    }

    #if canImport(AppKit)
    /// Walk the Simulator.app AX tree and return flattened AXNodes.
    /// The Simulator app exposes the iOS accessibility tree through macOS AX APIs.
    public func describeAll(interactive: Bool = false) throws -> [AXNode] {
        guard AXClient.isTrusted(prompt: false) else {
            throw SimulatorError.simctlFailed("Accessibility not trusted — grant in System Settings > Privacy > Accessibility")
        }

        let simPID = try simulatorPID()
        let simApp = AXClient.appElement(pid: simPID)

        // Find the window matching our device
        let window = try findSimulatorWindow(app: simApp)

        // Walk the AX tree starting from the simulator window
        let tree = AXClient.walkTree(element: window, maxDepth: 25)
        var allNodes = AXClient.flattenTree(tree)

        // Filter out the Simulator chrome (toolbar, title bar) by looking for
        // elements inside the content area. The iOS content is typically a
        // few levels deep: Window > ... > WebArea/Group containing the app UI.
        // We skip elements with no size or position, and very small elements
        // that are likely chrome.
        allNodes = allNodes.filter { node in
            // Must have position and size
            guard let _ = node.position, let sz = node.size else { return false }
            // Skip zero-size elements
            guard sz.width > 0 && sz.height > 0 else { return false }
            // Skip the window and top-level groups (Simulator chrome)
            if node.role == "AXWindow" || node.role == "AXApplication" { return false }
            return true
        }

        if interactive {
            allNodes = allNodes.filter { $0.isInteractive }
        }

        return allNodes
    }

    /// Type text via CGEvent keyboard through the Simulator window.
    public func typeViaCGEvent(text: String) throws {
        activateSimulator()
        Thread.sleep(forTimeInterval: 0.1)

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
    }

    /// Check if AX-based simulator access is available.
    /// Returns (available, diagnostic) tuple.
    public func probeAXAccess() -> (Bool, String) {
        guard AXClient.isTrusted(prompt: false) else {
            return (false, "Accessibility not trusted")
        }

        guard let pid = try? simulatorPID() else {
            return (false, "Simulator.app not running")
        }

        let simApp = AXClient.appElement(pid: pid)
        do {
            let _ = try findSimulatorWindow(app: simApp)
            // Try to walk a small portion of the tree
            let tree = AXClient.walkTree(element: simApp, maxDepth: 3)
            let nodes = AXClient.flattenTree(tree)
            if nodes.count > 1 {
                return (true, "AX tree accessible (\(nodes.count) nodes at depth 3)")
            }
            return (false, "AX tree empty")
        } catch {
            return (false, "Window not found: \(error)")
        }
    }

    /// Check if idb describe-all works for the current simulator.
    /// Returns (success, diagnostic) tuple.
    public func probeIdb() -> (Bool, String) {
        let idb = IdbBridge(udid: udid)
        do {
            let elements = try idb.describeAll()
            return (true, "idb OK (\(elements.count) elements)")
        } catch let error as IdbError {
            return (false, error.description)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Private

    private func simulatorPID() throws -> Int {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator")
        guard let simApp = apps.first else {
            throw SimulatorError.simulatorAppNotRunning
        }
        return Int(simApp.processIdentifier)
    }

    private func findSimulatorWindow(app: AXUIElement) throws -> AXUIElement {
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            throw SimulatorError.windowNotFound
        }

        // Try to find the window matching our device name
        let bridge = SimulatorBridge(udid: udid)
        let info = try? bridge.deviceInfo()

        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            if let title = titleRef as? String, let deviceName = info?.name, title.contains(deviceName) {
                return window
            }
        }

        // If no match by device name, return the first window
        return windows[0]
    }

    private func activateSimulator() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator").first {
            app.activate()
        }
    }
    #else
    public func describeAll(interactive: Bool = false) throws -> [AXNode] {
        throw SimulatorError.simctlFailed("AX fallback not available on this platform")
    }

    public func typeViaCGEvent(text: String) throws {
        throw SimulatorError.simctlFailed("CGEvent not available on this platform")
    }

    public func probeAXAccess() -> (Bool, String) {
        return (false, "Not available on this platform")
    }

    public func probeIdb() -> (Bool, String) {
        let idb = IdbBridge(udid: udid)
        do {
            let elements = try idb.describeAll()
            return (true, "idb OK (\(elements.count) elements)")
        } catch let error as IdbError {
            return (false, error.description)
        } catch {
            return (false, error.localizedDescription)
        }
    }
    #endif
}
