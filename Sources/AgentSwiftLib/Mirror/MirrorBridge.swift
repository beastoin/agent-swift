import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum MirrorError: Error, CustomStringConvertible {
    case notRunning
    case windowNotFound
    case clickFailed(String)
    case screenshotFailed(String)
    case swipeFailed(String)

    public var code: String {
        switch self {
        case .notRunning: return "MIRROR_NOT_RUNNING"
        case .windowNotFound: return "MIRROR_WINDOW_NOT_FOUND"
        case .clickFailed: return "MIRROR_CLICK_FAILED"
        case .screenshotFailed: return "MIRROR_SCREENSHOT_FAILED"
        case .swipeFailed: return "MIRROR_SWIPE_FAILED"
        }
    }

    public var hint: String? {
        switch self {
        case .notRunning:
            return "Open iPhone Mirroring: open -a 'iPhone Mirroring'"
        case .windowNotFound:
            return "Ensure iPhone Mirroring window is visible and your iPhone is connected"
        case .clickFailed(let msg):
            return "Click failed: \(msg). Ensure Accessibility permission is granted"
        case .screenshotFailed:
            return "Ensure iPhone Mirroring window is visible on screen"
        case .swipeFailed(let msg):
            return "Swipe failed: \(msg). Ensure Accessibility permission is granted"
        }
    }

    public var description: String {
        switch self {
        case .notRunning: return "iPhone Mirroring is not running"
        case .windowNotFound: return "Could not find iPhone Mirroring window"
        case .clickFailed(let msg): return "Click failed: \(msg)"
        case .screenshotFailed(let msg): return "Screenshot failed: \(msg)"
        case .swipeFailed(let msg): return "Swipe failed: \(msg)"
        }
    }
}

public struct MirrorWindowInfo {
    public let windowOrigin: CGPoint
    public let contentOrigin: CGPoint
    public let contentSize: CGSize
    public let iosScreenSize: CGSize
    public let scale: CGFloat

    public init(windowOrigin: CGPoint, contentOrigin: CGPoint, contentSize: CGSize, iosScreenSize: CGSize) {
        self.windowOrigin = windowOrigin
        self.contentOrigin = contentOrigin
        self.contentSize = contentSize
        self.iosScreenSize = iosScreenSize
        self.scale = iosScreenSize.width > 0 ? contentSize.width / iosScreenSize.width : 1.0
    }
}

public struct MirrorBridge {
    public static let bundleId = "com.apple.ScreenContinuity"
    public static let defaultIosSize = CGSize(width: 393, height: 852)

    public init() {}

    public static func isRunning() -> Bool {
        #if canImport(AppKit)
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
        #else
        return false
        #endif
    }

    public static func launch() throws {
        #if canImport(AppKit)
        let config = NSWorkspace.OpenConfiguration()
        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                launchError = error
                semaphore.signal()
            }
            semaphore.wait()
            if launchError != nil {
                throw MirrorError.notRunning
            }
            Thread.sleep(forTimeInterval: 1.0)
        } else {
            throw MirrorError.notRunning
        }
        #else
        throw MirrorError.notRunning
        #endif
    }

    #if canImport(AppKit)
    public func windowInfo() throws -> MirrorWindowInfo {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleId)
        guard let mirrorApp = apps.first else {
            throw MirrorError.notRunning
        }

        let pid = mirrorApp.processIdentifier
        let appAX = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            throw MirrorError.windowNotFound
        }

        let targetWindow = windows[0]

        var pos = CGPoint.zero
        var size = CGSize.zero
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(targetWindow, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(targetWindow, kAXSizeAttribute as CFString, &sizeRef)
        if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }

        let titleBarHeight: CGFloat = 28
        let contentOrigin = CGPoint(x: pos.x, y: pos.y + titleBarHeight)
        let contentSize = CGSize(width: size.width, height: size.height - titleBarHeight)

        return MirrorWindowInfo(
            windowOrigin: pos,
            contentOrigin: contentOrigin,
            contentSize: contentSize,
            iosScreenSize: Self.defaultIosSize
        )
    }
    #endif

    public func screenshot(to path: String) throws {
        #if canImport(AppKit)
        guard Self.isRunning() else { throw MirrorError.notRunning }

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            throw MirrorError.screenshotFailed("cannot list windows")
        }

        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleId)
        guard let mirrorApp = apps.first else {
            throw MirrorError.notRunning
        }
        let pid = Int(mirrorApp.processIdentifier)

        let mirrorWindows = windowList.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid }
        guard let mainWindow = mirrorWindows.max(by: { a, b in
            Self.windowArea(a) < Self.windowArea(b)
        }), let windowID = mainWindow[kCGWindowNumber as String] as? CGWindowID else {
            throw MirrorError.windowNotFound
        }

        let bounds: CGRect
        if let boundsDict = mainWindow[kCGWindowBounds as String] as? [String: Any],
           let boundsRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
            bounds = boundsRect
        } else {
            bounds = .null
        }

        guard let image = CGWindowListCreateImage(bounds, .optionIncludingWindow, windowID, [.boundsIgnoreFraming]) else {
            throw MirrorError.screenshotFailed("CGWindowListCreateImage returned nil")
        }

        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw MirrorError.screenshotFailed("cannot create image destination")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw MirrorError.screenshotFailed("cannot finalize image")
        }
        #else
        throw MirrorError.screenshotFailed("not available on this platform")
        #endif
    }

    public func tap(x: Double, y: Double) throws {
        #if canImport(AppKit)
        let info = try windowInfo()
        let screenPoint = Self.iosPointToScreen(CGPoint(x: x, y: y), windowInfo: info)

        Self.activateMirrorApp()

        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                       mouseCursorPosition: screenPoint, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                     mouseCursorPosition: screenPoint, mouseButton: .left) else {
            throw MirrorError.clickFailed("cannot create CGEvent")
        }
        mouseDown.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        mouseUp.post(tap: .cgSessionEventTap)
        #else
        throw MirrorError.clickFailed("not available on this platform")
        #endif
    }

    public func swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, duration: Double? = nil) throws {
        #if canImport(AppKit)
        let info = try windowInfo()
        let startPoint = Self.iosPointToScreen(CGPoint(x: fromX, y: fromY), windowInfo: info)
        let endPoint = Self.iosPointToScreen(CGPoint(x: toX, y: toY), windowInfo: info)

        Self.activateMirrorApp()

        let swipeDuration = duration ?? 0.3
        let steps = max(Int(swipeDuration * 60), 10)
        let dx = (endPoint.x - startPoint.x) / Double(steps)
        let dy = (endPoint.y - startPoint.y) / Double(steps)
        let stepDelay = swipeDuration / Double(steps)

        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                       mouseCursorPosition: startPoint, mouseButton: .left) else {
            throw MirrorError.swipeFailed("cannot create mouseDown event")
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
            throw MirrorError.swipeFailed("cannot create mouseUp event")
        }
        mouseUp.post(tap: .cgSessionEventTap)
        #else
        throw MirrorError.swipeFailed("not available on this platform")
        #endif
    }

    public static func iosPointToScreen(_ point: CGPoint, windowInfo: MirrorWindowInfo) -> CGPoint {
        return CGPoint(
            x: windowInfo.contentOrigin.x + point.x * windowInfo.scale,
            y: windowInfo.contentOrigin.y + point.y * windowInfo.scale
        )
    }

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

    #if canImport(AppKit)
    private static func activateMirrorApp() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate()
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    #endif

    private static func windowArea(_ window: [String: Any]) -> Double {
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let w = bounds["Width"] as? Double,
              let h = bounds["Height"] as? Double else { return 0 }
        return w * h
    }
}
