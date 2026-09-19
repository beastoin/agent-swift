import Foundation
#if canImport(AppKit)
import AppKit

/// Prevents target apps from stealing focus during AX or background input operations.
/// Subscribes to NSWorkspace.didActivateApplicationNotification and immediately
/// re-activates the prior frontmost app when the guarded PID activates.
///
/// Usage:
///     let guard = FocusGuard()
///     try guard.withSuppression(for: targetPID) {
///         // AX actions or background input here
///         // If the target app steals focus, it's reverted
///     }
public final class FocusGuard {
    /// Maximum suppression duration before auto-expiring (prevents leaked guards)
    public static let deadline: TimeInterval = 5.0

    /// Settle time after re-activating the original frontmost app
    public static let settleTime: TimeInterval = 0.050

    private var observer: NSObjectProtocol?
    private let queue = OperationQueue()

    public init() {
        queue.name = "com.agent-swift.focus-guard"
        queue.maxConcurrentOperationCount = 1
    }

    deinit {
        if let obs = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    /// Execute an action while suppressing focus steal from the given PID.
    /// If the target app activates during the action, the prior frontmost app
    /// is immediately re-activated.
    @discardableResult
    public func withSuppression<T>(for targetPID: Int, action: () throws -> T) rethrows -> T {
        let priorApp = NSWorkspace.shared.frontmostApplication
        let guardedPID = pid_t(targetPID)
        var suppressed = false

        // Install observer on background queue (essential for daemon/CLI without main run loop)
        let obs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: queue
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == guardedPID else { return }
            // Target app stole focus — revert
            if let prior = priorApp {
                prior.activate()
                suppressed = true
            }
        }

        // Deadline: auto-remove observer after max duration
        let deadlineItem = DispatchWorkItem { [weak self] in
            if let obs = self?.observer {
                NSWorkspace.shared.notificationCenter.removeObserver(obs)
                self?.observer = nil
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.deadline, execute: deadlineItem)

        defer {
            // Clean up observer
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            deadlineItem.cancel()

            // If focus was suppressed, give a settle time
            if suppressed {
                Thread.sleep(forTimeInterval: Self.settleTime)
            }
        }

        self.observer = obs
        return try action()
    }

    /// Check if a PID is currently the frontmost application.
    public static func isFrontmost(pid: Int) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid_t(pid)
    }

    /// Get the PID of the current frontmost application.
    public static func frontmostPID() -> Int? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return Int(app.processIdentifier)
    }
}

#else
// Non-macOS stub
public final class FocusGuard {
    public static let deadline: TimeInterval = 5.0
    public static let settleTime: TimeInterval = 0.050

    public init() {}

    @discardableResult
    public func withSuppression<T>(for targetPID: Int, action: () throws -> T) rethrows -> T {
        return try action()
    }

    public static func isFrontmost(pid: Int) -> Bool { false }
    public static func frontmostPID() -> Int? { nil }
}
#endif
