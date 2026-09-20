import Foundation
#if canImport(AppKit)
import AppKit
import ApplicationServices

/// CGEvent field constants used by SkyLight for PID/Window routing.
/// These undocumented fields control how the WindowServer delivers events
/// to backgrounded applications.
public enum SkyLightField: UInt32 {
    /// Gesture phase: 1=down, 2=move, 3=target
    case gesturePhase = 0       // f0
    /// Click state: 1→N for multi-click coalescing
    case clickState = 1         // f1
    /// Button number: 0=left, 1=right, 2=middle
    case buttonNumber = 3       // f3
    /// Event subtype: 3 = NSEventSubtypeTouch
    case eventSubtype = 7       // f7
    /// Target PID filter — the process that should receive this event
    case targetPID = 40         // f40
    /// Window routing — CGWindowID for backgrounded delivery
    case windowID1 = 51         // f51
    /// Click-group ID for gesture coalescing
    case clickGroupID = 58      // f58
    /// Window routing — secondary CGWindowID field
    case windowID2 = 91         // f91
    /// Window routing — tertiary CGWindowID field
    case windowID3 = 92         // f92
}

/// Helpers for stamping CGEvents with SkyLight routing fields
/// and delivering them to backgrounded applications.
public enum EventStamping {

    /// Stamp a CGEvent with the target PID for SkyLight routing.
    public static func stampPID(_ event: CGEvent, pid: Int) {
        let bridge = SkyLightBridge.shared
        bridge.setIntegerValueField(event, field: SkyLightField.targetPID.rawValue, value: Int64(pid))
    }

    /// Stamp a CGEvent with the target CGWindowID for window-specific routing.
    /// Sets all three window routing fields (f51, f91, f92).
    public static func stampWindow(_ event: CGEvent, windowID: CGWindowID) {
        let bridge = SkyLightBridge.shared
        let wid = Int64(windowID)
        bridge.setIntegerValueField(event, field: SkyLightField.windowID1.rawValue, value: wid)
        bridge.setIntegerValueField(event, field: SkyLightField.windowID2.rawValue, value: wid)
        bridge.setIntegerValueField(event, field: SkyLightField.windowID3.rawValue, value: wid)
    }

    /// Stamp window-local coordinates on a CGEvent.
    public static func setWindowLocation(_ event: CGEvent, point: CGPoint) {
        SkyLightBridge.shared.setWindowLocation(event, point: point)
    }

    /// Send a primer mouseMoved to a backgrounded window.
    /// Primes AppKit's cursor tracking state so that a subsequent click
    /// lands on the correct control. Without this, backgrounded windows
    /// have stale tracking state and clicks may miss their target.
    public static func primerMove(to point: CGPoint, pid: Int, windowID: CGWindowID) {
        guard SkyLightBridge.shared.canPostToPid else { return }
        guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                 mouseCursorPosition: point, mouseButton: .left) else { return }
        stampPID(move, pid: pid)
        stampWindow(move, windowID: windowID)
        setWindowLocation(move, point: point)
        SkyLightBridge.shared.postToPid(Int32(pid), event: move)
    }

    /// Create and deliver a background click to a specific PID+Window.
    /// Returns true if events were posted (delivery confirmed at API level, not app level).
    @discardableResult
    public static func backgroundClick(
        at point: CGPoint,
        pid: Int,
        windowID: CGWindowID,
        button: CGMouseButton = .left,
        clickCount: Int = 1
    ) -> Bool {
        let bridge = SkyLightBridge.shared
        guard bridge.canPostToPid else { return false }

        let pid32 = Int32(pid)
        let downType: CGEventType = button == .left ? .leftMouseDown : (button == .right ? .rightMouseDown : .otherMouseDown)
        let upType: CGEventType = button == .left ? .leftMouseUp : (button == .right ? .rightMouseUp : .otherMouseUp)

        // 1. Primer mouseMoved
        primerMove(to: point, pid: pid, windowID: windowID)
        Thread.sleep(forTimeInterval: 0.01)

        // 2. mouseDown
        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: downType,
                                       mouseCursorPosition: point, mouseButton: button) else { return false }
        stampPID(mouseDown, pid: pid)
        stampWindow(mouseDown, windowID: windowID)
        setWindowLocation(mouseDown, point: point)
        if clickCount > 1 {
            bridge.setIntegerValueField(mouseDown, field: SkyLightField.clickState.rawValue, value: Int64(clickCount))
        }
        bridge.postToPid(pid32, event: mouseDown)

        // 3. Wait minimum hold (28ms for AppKit modal tracking)
        Thread.sleep(forTimeInterval: 0.028)

        // 4. mouseUp
        guard let mouseUp = CGEvent(mouseEventSource: nil, mouseType: upType,
                                     mouseCursorPosition: point, mouseButton: button) else { return false }
        stampPID(mouseUp, pid: pid)
        stampWindow(mouseUp, windowID: windowID)
        setWindowLocation(mouseUp, point: point)
        if clickCount > 1 {
            bridge.setIntegerValueField(mouseUp, field: SkyLightField.clickState.rawValue, value: Int64(clickCount))
        }
        bridge.postToPid(pid32, event: mouseUp)

        // 5. Settle time
        Thread.sleep(forTimeInterval: 0.040)

        return true
    }

    /// Create and deliver a background scroll event.
    @discardableResult
    public static func backgroundScroll(
        at point: CGPoint,
        pid: Int,
        windowID: CGWindowID,
        deltaY: Int32,
        deltaX: Int32 = 0
    ) -> Bool {
        let bridge = SkyLightBridge.shared
        guard bridge.canPostToPid else { return false }

        guard let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                    wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0) else { return false }
        stampPID(scroll, pid: pid)
        stampWindow(scroll, windowID: windowID)
        setWindowLocation(scroll, point: point)
        bridge.postToPid(Int32(pid), event: scroll)

        Thread.sleep(forTimeInterval: 0.040)
        return true
    }

    /// Deliver text to a backgrounded app, following CUA's routing ladder:
    /// 1. AX semantic (Rank 1): focus element + AXValue write — works even when minimized
    /// 2. SkyLight keyboard (Rank 4): per-char keystroke delivery for apps where AX fails
    ///
    /// Returns (success, method) where method is "ax", "skylight", or "none".
    public static func backgroundType(text: String, pid: Int, focusElement: AXUIElement? = nil, replace: Bool = false) -> (Bool, String) {
        // If no focus element provided, try to find one from the app
        var element = focusElement
        if element == nil {
            let appEl = AXUIElementCreateApplication(pid_t(pid))
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success {
                element = (focusedRef as! AXUIElement)
            }
        }

        // Route 1: AX semantic — focus + value write (same as performFill but without activation)
        if let element = element {
            // Focus element first (required for NSTextView to accept value writes)
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
            Thread.sleep(forTimeInterval: 0.050)

            // Read existing value, append or replace
            var existingRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &existingRef)
            let existing = existingRef as? String ?? ""
            let newValue = replace ? text : existing + text

            if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef) == .success {
                // Verify the write actually took effect
                var verifyRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &verifyRef)
                if let verified = verifyRef as? String, verified.contains(text) {
                    return (true, "ax")
                }
            }
        }

        // Route 2: SkyLight keyboard delivery (fallback)
        let bridge = SkyLightBridge.shared
        guard bridge.canPostToPid else { return (false, "none") }

        // If we have an element, ensure it's focused for keyboard input
        if let element = focusElement {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
            Thread.sleep(forTimeInterval: 0.050)
        }

        let pid32 = Int32(pid)

        for char in text {
            let str = String(char)
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { continue }

            let nsStr = str as NSString
            var unichar = nsStr.character(at: 0)
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)

            stampPID(keyDown, pid: pid)
            stampPID(keyUp, pid: pid)
            keyDown.flags = []
            keyUp.flags = []
            bridge.setAuthenticationMessage(keyDown)
            bridge.setAuthenticationMessage(keyUp)

            bridge.postToPid(pid32, event: keyDown)
            Thread.sleep(forTimeInterval: 0.008)
            bridge.postToPid(pid32, event: keyUp)
            Thread.sleep(forTimeInterval: 0.008)
        }

        return (true, "skylight")
    }

    /// Resolve the main CGWindowID for a given PID.
    /// Returns the largest visible window owned by the process.
    public static func resolveWindowID(pid: Int) -> CGWindowID? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let appWindows = windowList.filter {
            ($0[kCGWindowOwnerPID as String] as? Int) == pid &&
            ($0[kCGWindowLayer as String] as? Int) == 0  // Normal layer only
        }
        // Pick the largest window by area
        let best = appWindows.max { a, b in
            windowArea(a) < windowArea(b)
        }
        return best?[kCGWindowNumber as String] as? CGWindowID
    }

    private static func windowArea(_ window: [String: Any]) -> Double {
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let w = bounds["Width"] as? Double,
              let h = bounds["Height"] as? Double else { return 0 }
        return w * h
    }
}

#else
// Non-macOS stub
public enum SkyLightField: UInt32 {
    case gesturePhase = 0, clickState = 1, buttonNumber = 3, eventSubtype = 7
    case targetPID = 40, windowID1 = 51, clickGroupID = 58, windowID2 = 91, windowID3 = 92
}

public enum EventStamping {
    public static func stampPID(_ event: Any, pid: Int) {}
    public static func stampWindow(_ event: Any, windowID: UInt32) {}
    public static func setWindowLocation(_ event: Any, point: CGPoint) {}
    public static func primerMove(to point: CGPoint, pid: Int, windowID: UInt32) {}
    public static func backgroundClick(at point: CGPoint, pid: Int, windowID: UInt32, button: Int = 0, clickCount: Int = 1) -> Bool { false }
    public static func backgroundScroll(at point: CGPoint, pid: Int, windowID: UInt32, deltaY: Int32, deltaX: Int32 = 0) -> Bool { false }
    public static func backgroundType(text: String, pid: Int) -> Bool { false }
    public static func resolveWindowID(pid: Int) -> UInt32? { nil }
}
#endif
