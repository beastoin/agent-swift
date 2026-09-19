import Foundation

public struct SnapshotElement: Codable {
    public let ref: String
    public let type: String
    public let label: String?
    public let role: String
    public let identifier: String?
    public let enabled: Bool
    public let focused: Bool
    let bounds: SessionData.RefEntry.Bounds?
}

public struct SnapshotResult: Codable {
    public let elements: [SnapshotElement]
    public let method: String?
}

public enum SnapshotFormatter {
    public static func formatHuman(elements: [(ref: String, node: AXNode)]) -> String {
        var lines: [String] = []
        for (ref, node) in elements {
            var line = "@\(ref) [\(node.displayType)]"
            if let label = node.displayLabel {
                line += " \"\(label)\""
            }
            if let id = node.identifier, !id.isEmpty {
                line += "  identifier=\(id)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    public static func formatJson(elements: [(ref: String, node: AXNode)], method: String? = nil) -> String {
        let entries = elements.map { (ref, node) in
            SnapshotElement(
                ref: ref,
                type: node.displayType,
                label: node.displayLabel,
                role: node.role,
                identifier: node.identifier,
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
}
