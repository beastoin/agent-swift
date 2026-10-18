import Foundation

public struct SnapshotElement: Codable {
    public let ref: String
    public let type: String
    public let label: String?
    public let role: String
    public let identifier: String?
    public let help: String?
    public let enabled: Bool
    public let focused: Bool
    let bounds: SessionData.RefEntry.Bounds?
}

public struct SnapshotResult: Codable {
    public let elements: [SnapshotElement]
    public let method: String?
}

public enum SnapshotFormatter {

    // MARK: - Response Sanitization

    /// Whether sanitization is disabled via AGENT_SWIFT_RAW=1
    public static var rawMode: Bool {
        ProcessInfo.processInfo.environment["AGENT_SWIFT_RAW"] == "1"
    }

    /// Sanitize an AX-sourced string: strip control chars, truncate to 500 chars
    public static func sanitize(_ s: String?) -> String? {
        guard let s = s else { return nil }
        if rawMode { return s }
        var cleaned = s.unicodeScalars.filter { scalar in
            // Keep printable chars, \n (0x0A), \t (0x09)
            if scalar.value == 0x0A || scalar.value == 0x09 { return true }
            if scalar.value < 0x20 { return false }  // strip 0x00-0x1F except \n \t
            if scalar.value == 0x7F { return false }  // strip DEL
            return true
        }
        let result = String(cleaned)
        if result.count > 500 {
            return String(result.prefix(500)) + "…"
        }
        return result
    }

    // MARK: - Human Output

    public static func formatHuman(elements: [(ref: String, node: AXNode)], fields: Set<String>? = nil) -> String {
        var lines: [String] = []
        for (ref, node) in elements {
            var line = "@\(ref)"
            let fs = fields

            if fs == nil || fs!.contains("type") {
                line += " [\(node.displayType)]"
            }
            if fs == nil || fs!.contains("label") {
                if let label = sanitize(node.displayLabel) {
                    line += " \"\(label)\""
                }
            }
            if fs == nil || fs!.contains("identifier") {
                if let id = sanitize(node.identifier), !id.isEmpty {
                    line += "  identifier=\(id)"
                }
            }
            if fs == nil || fs!.contains("help") {
                if let hint = sanitize(node.help), !hint.isEmpty {
                    line += "  help=\"\(hint)\""
                }
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Output

    public static func formatJson(elements: [(ref: String, node: AXNode)], method: String? = nil, fields: Set<String>? = nil) -> String {
        if let fs = fields {
            return formatJsonFiltered(elements: elements, method: method, fields: fs)
        }
        let entries = elements.map { (ref, node) in
            SnapshotElement(
                ref: ref,
                type: node.displayType,
                label: sanitize(node.displayLabel),
                role: node.role,
                identifier: sanitize(node.identifier),
                help: sanitize(node.help),
                enabled: node.enabled,
                focused: node.focused,
                bounds: node.bounds
            )
        }
        if let method = method {
            return Output.json(SnapshotResult(elements: entries, method: method))
        }
        return Output.json(entries)
    }

    // MARK: - Filtered JSON (field masking)

    private static func formatJsonFiltered(elements: [(ref: String, node: AXNode)], method: String?, fields: Set<String>) -> String {
        var result: [[String: Any]] = []
        for (ref, node) in elements {
            var dict: [String: Any] = ["ref": ref]
            if fields.contains("type") { dict["type"] = node.displayType }
            if fields.contains("label") { dict["label"] = sanitize(node.displayLabel) as Any }
            if fields.contains("role") { dict["role"] = node.role }
            if fields.contains("identifier") { dict["identifier"] = sanitize(node.identifier) as Any }
            if fields.contains("help") { dict["help"] = sanitize(node.help) as Any }
            if fields.contains("enabled") { dict["enabled"] = node.enabled }
            if fields.contains("focused") { dict["focused"] = node.focused }
            if fields.contains("bounds"), let b = node.bounds {
                dict["bounds"] = ["x": b.x, "y": b.y, "width": b.width, "height": b.height]
            }
            result.append(dict)
        }

        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - NDJSON Output

    public static func formatNdjson(elements: [(ref: String, node: AXNode)], fields: Set<String>? = nil) -> String {
        var lines: [String] = []
        for (ref, node) in elements {
            var dict: [String: Any] = ["ref": ref]
            let fs = fields

            if fs == nil || fs!.contains("type") { dict["type"] = node.displayType }
            if fs == nil || fs!.contains("label") { dict["label"] = sanitize(node.displayLabel) as Any }
            if fs == nil || fs!.contains("role") { dict["role"] = node.role }
            if fs == nil || fs!.contains("identifier") { dict["identifier"] = sanitize(node.identifier) as Any }
            if fs == nil || fs!.contains("help") { dict["help"] = sanitize(node.help) as Any }
            if fs == nil || fs!.contains("enabled") { dict["enabled"] = node.enabled }
            if fs == nil || fs!.contains("focused") { dict["focused"] = node.focused }
            if fs == nil || fs!.contains("bounds"), let b = node.bounds {
                dict["bounds"] = ["x": b.x, "y": b.y, "width": b.width, "height": b.height]
            }

            let data = try! JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
            lines.append(String(data: data, encoding: .utf8)!)
        }
        return lines.joined(separator: "\n")
    }
}
