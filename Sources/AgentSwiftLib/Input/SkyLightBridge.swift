import Foundation
#if canImport(AppKit)
import AppKit
import ApplicationServices

/// Loads Apple's private SkyLight framework at runtime via dlsym.
/// Provides PID-targeted event delivery without moving the visible cursor or stealing focus.
/// Fails gracefully: if symbols can't be loaded, `isAvailable` returns false.
public final class SkyLightBridge {
    public static let shared = SkyLightBridge()

    // MARK: - Function types

    // void SLEventPostToPid(pid_t pid, CGEventRef event)
    private typealias SLEventPostToPidFn = @convention(c) (Int32, CGEvent) -> Void

    // void SLEventSetAuthenticationMessage(CGEventRef event)
    private typealias SLEventSetAuthenticationMessageFn = @convention(c) (CGEvent) -> Void

    // void CGEventSetWindowLocation(CGEventRef event, CGPoint point)
    // Note: This is a private CoreGraphics function, not SkyLight, but loaded same way
    private typealias CGEventSetWindowLocationFn = @convention(c) (CGEvent, CGPoint) -> Void

    // void SLEventSetIntegerValueField(CGEventRef event, uint32_t field, int64_t value)
    private typealias SLEventSetIntegerValueFieldFn = @convention(c) (CGEvent, UInt32, Int64) -> Void

    // int CGSMainConnectionID(void)
    private typealias CGSMainConnectionIDFn = @convention(c) () -> Int32

    // CGError SLSGetWindowOwner(int cid, CGWindowID windowID, int *ownerCid)
    private typealias SLSGetWindowOwnerFn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Int32>) -> Int32

    // MARK: - Resolved symbols

    private let _postToPid: SLEventPostToPidFn?
    private let _setAuthMessage: SLEventSetAuthenticationMessageFn?
    private let _setWindowLocation: CGEventSetWindowLocationFn?
    private let _setIntField: SLEventSetIntegerValueFieldFn?
    private let _mainConnectionID: CGSMainConnectionIDFn?
    private let _getWindowOwner: SLSGetWindowOwnerFn?

    /// True when all required symbols for background input delivery are available.
    public let isAvailable: Bool

    /// True when at least posting to PID works (minimum viable background delivery).
    public let canPostToPid: Bool

    /// Diagnostic string describing which symbols loaded.
    public let diagnostic: String

    private init() {
        // Load SkyLight framework
        let skyHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        // CoreGraphics for CGEventSetWindowLocation (private symbol)
        let cgHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

        var loaded: [String] = []
        var missing: [String] = []

        // Resolve each symbol
        func resolve<T>(_ name: String, from handle: UnsafeMutableRawPointer?) -> T? {
            guard let handle = handle, let sym = dlsym(handle, name) else {
                missing.append(name)
                return nil
            }
            loaded.append(name)
            return unsafeBitCast(sym, to: T.self)
        }

        _postToPid = resolve("SLEventPostToPid", from: skyHandle)
        _setAuthMessage = resolve("SLEventSetAuthenticationMessage", from: skyHandle)
        _setWindowLocation = resolve("CGEventSetWindowLocation", from: cgHandle)
        _setIntField = resolve("SLEventSetIntegerValueField", from: skyHandle)
        _mainConnectionID = resolve("CGSMainConnectionID", from: skyHandle)
        _getWindowOwner = resolve("SLSGetWindowOwner", from: skyHandle)

        canPostToPid = _postToPid != nil
        isAvailable = _postToPid != nil && _setWindowLocation != nil && _setIntField != nil
        diagnostic = "loaded: [\(loaded.joined(separator: ", "))], missing: [\(missing.joined(separator: ", "))]"
    }

    // MARK: - Public API

    /// Post a CGEvent to a specific PID without moving the visible cursor.
    public func postToPid(_ pid: Int32, event: CGEvent) {
        _postToPid?(pid, event)
    }

    /// Attach authentication credentials to a keyboard event.
    /// Required for Chromium/Electron on macOS 14+ to trust synthetic keyboard input.
    public func setAuthenticationMessage(_ event: CGEvent) {
        _setAuthMessage?(event)
    }

    /// Stamp window-local coordinates on a CGEvent for hit-testing in backgrounded windows.
    public func setWindowLocation(_ event: CGEvent, point: CGPoint) {
        _setWindowLocation?(event, point)
    }

    /// Set a raw integer field on a CGEvent (SkyLight routing fields).
    public func setIntegerValueField(_ event: CGEvent, field: UInt32, value: Int64) {
        _setIntField?(event, field, value)
    }

    /// Get the WindowServer connection ID for the current process.
    public func mainConnectionID() -> Int32 {
        _mainConnectionID?() ?? 0
    }

    /// Check if a window is owned by the expected PID.
    /// Uses CGWindowListCopyWindowInfo to validate PID ownership.
    public func validateWindowOwner(windowID: CGWindowID, expectedPID: Int) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windowList.contains {
            ($0[kCGWindowNumber as String] as? Int) == Int(windowID) &&
            ($0[kCGWindowOwnerPID as String] as? Int) == expectedPID
        }
    }
}

#else
// Non-macOS stub
public final class SkyLightBridge {
    public static let shared = SkyLightBridge()
    public let isAvailable = false
    public let canPostToPid = false
    public let diagnostic = "SkyLight not available on this platform"

    public func postToPid(_ pid: Int32, event: Any) {}
    public func setAuthenticationMessage(_ event: Any) {}
    public func setWindowLocation(_ event: Any, point: CGPoint) {}
    public func setIntegerValueField(_ event: Any, field: UInt32, value: Int64) {}
    public func mainConnectionID() -> Int32 { 0 }
    public func validateWindowOwner(windowID: UInt32, expectedPID: Int) -> Bool { false }
}
#endif
