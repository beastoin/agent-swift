import ApplicationServices
import AppKit
import Foundation

public enum AXError: Error, CustomStringConvertible {
    case notTrusted
    case appNotFound(String)
    case appNotRunning(pid: Int)
    case elementNotFound(String)
    case actionNotSupported(String)
    case axFailure(String)

    public var code: String {
        switch self {
        case .notTrusted: return "AX_NOT_TRUSTED"
        case .appNotFound: return "APP_NOT_FOUND"
        case .appNotRunning: return "APP_NOT_RUNNING"
        case .elementNotFound: return "ELEMENT_NOT_FOUND"
        case .actionNotSupported: return "ACTION_NOT_SUPPORTED"
        case .axFailure: return "AX_FAILURE"
        }
    }

    public var hint: String? {
        switch self {
        case .notTrusted:
            return "Grant Accessibility access in System Settings > Privacy & Security > Accessibility"
        case .appNotFound(let id):
            return "Launch an app with bundle ID \(id), or use --pid"
        case .appNotRunning(let pid):
            return "No process with PID \(pid). Check with: ps -p \(pid)"
        case .elementNotFound:
            return "Re-run: agent-swift snapshot -i"
        case .actionNotSupported:
            return "Pick a different target from snapshot"
        case .axFailure:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .notTrusted: return "Accessibility permission not granted"
        case .appNotFound(let id): return "No running app with bundle ID: \(id)"
        case .appNotRunning(let pid): return "No running process with PID: \(pid)"
        case .elementNotFound(let ref): return "Element not found: \(ref)"
        case .actionNotSupported(let action): return "Action not supported: \(action)"
        case .axFailure(let msg): return "Accessibility API failure: \(msg)"
        }
    }
}

public struct AXNode {
    public let role: String
    public let subrole: String?
    public let title: String?
    public let axDescription: String?
    public let value: String?
    public let identifier: String?
    public let childStaticText: String?
    public let enabled: Bool
    public let focused: Bool
    public let position: CGPoint?
    public let size: CGSize?
    public let actions: [String]
    public let children: [AXNode]

    public init(role: String, subrole: String?, title: String?, axDescription: String?, value: String?,
                identifier: String?, childStaticText: String?, enabled: Bool, focused: Bool,
                position: CGPoint?, size: CGSize?, actions: [String], children: [AXNode]) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.axDescription = axDescription
        self.value = value
        self.identifier = identifier
        self.childStaticText = childStaticText
        self.enabled = enabled
        self.focused = focused
        self.position = position
        self.size = size
        self.actions = actions
        self.children = children
    }

    public var isInteractive: Bool {
        let interactiveRoles: Set<String> = [
            "AXButton", "AXTextField", "AXTextArea", "AXCheckBox",
            "AXRadioButton", "AXPopUpButton", "AXComboBox", "AXSlider",
            "AXSwitch", "AXToggle", "AXMenuItem", "AXMenuButton",
            "AXLink", "AXTab", "AXTabGroup", "AXDisclosureTriangle",
            "AXIncrementor", "AXColorWell", "AXSegmentedControl"
        ]
        return interactiveRoles.contains(role) || actions.contains("AXPress") || actions.contains("AXConfirm")
    }

    public var displayType: String {
        switch role {
        case "AXButton": return "button"
        case "AXTextField", "AXTextArea": return "textfield"
        case "AXStaticText": return "statictext"
        case "AXCheckBox": return "checkbox"
        case "AXRadioButton": return "radio"
        case "AXPopUpButton", "AXComboBox": return "dropdown"
        case "AXSlider": return "slider"
        case "AXSwitch", "AXToggle": return "switch"
        case "AXMenuItem": return "menuitem"
        case "AXLink": return "link"
        case "AXImage": return "image"
        case "AXTab": return "tab"
        case "AXTable": return "table"
        case "AXList": return "list"
        case "AXGroup": return "group"
        case "AXWindow": return "window"
        case "AXToolbar": return "toolbar"
        case "AXScrollArea": return "scrollarea"
        case "AXMenu": return "menu"
        case "AXMenuBar": return "menubar"
        default: return role.replacingOccurrences(of: "AX", with: "").lowercased()
        }
    }

    public var displayLabel: String? {
        // SwiftUI buttons expose text via AXDescription or child AXStaticText, not AXTitle
        return title ?? axDescription ?? childStaticText ?? value
    }

    public var bounds: SessionData.RefEntry.Bounds? {
        guard let pos = position, let sz = size else { return nil }
        return SessionData.RefEntry.Bounds(x: pos.x, y: pos.y, width: sz.width, height: sz.height)
    }

    public func toRefEntry() -> SessionData.RefEntry {
        return SessionData.RefEntry(
            role: role,
            label: displayLabel,
            identifier: identifier,
            enabled: enabled,
            focused: focused,
            bounds: bounds,
            actions: actions
        )
    }
}

public class AXClient {
    public static func isTrusted(prompt: Bool = false) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    public static func resolvePID(bundleId: String) -> Int? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard let app = apps.first else { return nil }
        return Int(app.processIdentifier)
    }

    public static func isProcessRunning(pid: Int) -> Bool {
        return NSRunningApplication(processIdentifier: pid_t(pid)) != nil
    }

    public static func appElement(pid: Int) -> AXUIElement {
        return AXUIElementCreateApplication(pid_t(pid))
    }

    public static func walkTree(element: AXUIElement, maxDepth: Int = 20, currentDepth: Int = 0) -> AXNode {
        func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
            var value: AnyObject?
            let result = AXUIElementCopyAttributeValue(el, name as CFString, &value)
            guard result == .success else { return nil }
            return value as? T
        }

        let role: String = attr(element, kAXRoleAttribute) ?? "AXUnknown"
        let subrole: String? = attr(element, kAXSubroleAttribute)
        let title: String? = attr(element, kAXTitleAttribute)
        let axDescription: String? = attr(element, kAXDescriptionAttribute)
        let rawValue: AnyObject? = {
            var v: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &v)
            return v
        }()
        let value: String? = rawValue as? String
        let identifier: String? = attr(element, kAXIdentifierAttribute)
        let enabled: Bool = attr(element, kAXEnabledAttribute) ?? true
        let focused: Bool = attr(element, kAXFocusedAttribute) ?? false

        var position: CGPoint? = nil
        var posValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
           let val = posValue {
            var point = CGPoint.zero
            if AXValueGetValue(val as! AXValue, .cgPoint, &point) {
                position = point
            }
        }

        var size: CGSize? = nil
        var sizeValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let val = sizeValue {
            var sz = CGSize.zero
            if AXValueGetValue(val as! AXValue, .cgSize, &sz) {
                size = sz
            }
        }

        var actionNames: [String] = []
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(element, &actionsRef) == .success, let actions = actionsRef as? [String] {
            actionNames = actions
        }

        var children: [AXNode] = []
        if currentDepth < maxDepth {
            var childrenRef: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let childElements = childrenRef as? [AXUIElement] {
                children = childElements.map { walkTree(element: $0, maxDepth: maxDepth, currentDepth: currentDepth + 1) }
            }
        }

        // Extract label from child AXStaticText elements (SwiftUI button pattern)
        let childStaticText: String? = {
            guard title == nil && axDescription == nil else { return nil }
            let texts = children.compactMap { child -> String? in
                if child.role == "AXStaticText" {
                    return child.title ?? child.value
                }
                return nil
            }
            return texts.isEmpty ? nil : texts.joined(separator: " ")
        }()

        return AXNode(
            role: role,
            subrole: subrole,
            title: title,
            axDescription: axDescription,
            value: value,
            identifier: identifier,
            childStaticText: childStaticText,
            enabled: enabled,
            focused: focused,
            position: position,
            size: size,
            actions: actionNames,
            children: children
        )
    }

    public static func flattenTree(_ node: AXNode) -> [AXNode] {
        var result = [node]
        for child in node.children {
            result.append(contentsOf: flattenTree(child))
        }
        return result
    }

    public static func performPress(element: AXUIElement, actionName: String = "AXPress") -> Bool {
        return AXUIElementPerformAction(element, actionName as CFString) == .success
    }

    public static func collectElements(element: AXUIElement, interactiveOnly: Bool, into result: inout [AXUIElement], maxDepth: Int = 20, depth: Int = 0) {
        let role: String = {
            var v: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &v)
            return v as? String ?? "AXUnknown"
        }()
        let actions: [String] = {
            var a: CFArray?
            AXUIElementCopyActionNames(element, &a)
            return (a as? [String]) ?? []
        }()

        let interactiveRoles: Set<String> = [
            "AXButton", "AXTextField", "AXTextArea", "AXCheckBox",
            "AXRadioButton", "AXPopUpButton", "AXComboBox", "AXSlider",
            "AXSwitch", "AXToggle", "AXMenuItem", "AXMenuButton",
            "AXLink", "AXTab", "AXTabGroup", "AXDisclosureTriangle",
            "AXIncrementor", "AXColorWell", "AXSegmentedControl"
        ]
        let isInteractive = interactiveRoles.contains(role) || actions.contains("AXPress") || actions.contains("AXConfirm")

        if !interactiveOnly || isInteractive {
            result.append(element)
        }

        guard depth < maxDepth else { return }
        var childrenRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                collectElements(element: child, interactiveOnly: interactiveOnly, into: &result, maxDepth: maxDepth, depth: depth + 1)
            }
        }
    }
}
