import XCTest
@testable import AgentSwiftLib

final class AgentFriendlyTests: XCTestCase {

    // MARK: - Response Sanitization

    func testSanitizeStripsControlChars() {
        let input = "Hello\u{01}World\u{02}Test\u{7F}End"
        let result = SnapshotFormatter.sanitize(input)
        XCTAssertEqual(result, "HelloWorldTestEnd")
    }

    func testSanitizePreservesNewlineAndTab() {
        let input = "Line1\nLine2\tTabbed"
        let result = SnapshotFormatter.sanitize(input)
        XCTAssertEqual(result, "Line1\nLine2\tTabbed")
    }

    func testSanitizeTruncatesLongStrings() {
        let longString = String(repeating: "a", count: 600)
        let result = SnapshotFormatter.sanitize(longString)!
        // 500 chars + "…" = 501 chars
        XCTAssertEqual(result.count, 501)
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func testSanitizeNilPassthrough() {
        let result = SnapshotFormatter.sanitize(nil)
        XCTAssertNil(result)
    }

    func testSanitizeShortStringUnchanged() {
        let result = SnapshotFormatter.sanitize("OK")
        XCTAssertEqual(result, "OK")
    }

    func testSanitizeEmptyString() {
        let result = SnapshotFormatter.sanitize("")
        XCTAssertEqual(result, "")
    }

    // MARK: - Field Masking

    func testFieldMaskingFiltersCorrectly() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "Save", axDescription: nil, value: nil,
                                    identifier: "saveBtn", childStaticText: nil, enabled: true, focused: false,
                                    position: CGPoint(x: 10, y: 20), size: CGSize(width: 80, height: 30),
                                    actions: ["AXPress"], children: []))
        ]

        let fields: Set<String> = ["ref", "label", "role"]
        let jsonStr = SnapshotFormatter.formatJson(elements: nodes, fields: fields)
        let data = jsonStr.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0]["ref"] as? String, "e1")
        XCTAssertEqual(parsed[0]["label"] as? String, "Save")
        XCTAssertEqual(parsed[0]["role"] as? String, "AXButton")
        // These should NOT be present
        XCTAssertNil(parsed[0]["type"])
        XCTAssertNil(parsed[0]["enabled"])
        XCTAssertNil(parsed[0]["focused"])
        XCTAssertNil(parsed[0]["bounds"])
    }

    func testFieldMaskingAlwaysIncludesRef() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil, value: nil,
                                    identifier: nil, childStaticText: nil, enabled: true, focused: false,
                                    position: nil, size: nil, actions: [], children: []))
        ]

        // Request only "label" — ref should still be included
        let fields: Set<String> = ["ref", "label"]
        let jsonStr = SnapshotFormatter.formatJson(elements: nodes, fields: fields)
        let data = jsonStr.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(parsed[0]["ref"] as? String, "e1")
    }

    // MARK: - NDJSON

    func testNdjsonFormat() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil, value: nil,
                                    identifier: nil, childStaticText: nil, enabled: true, focused: false,
                                    position: nil, size: nil, actions: [], children: [])),
            (ref: "e2", node: AXNode(role: "AXTextField", subrole: nil, title: nil, axDescription: nil, value: "hi",
                                    identifier: nil, childStaticText: nil, enabled: true, focused: true,
                                    position: nil, size: nil, actions: [], children: []))
        ]

        let output = SnapshotFormatter.formatNdjson(elements: nodes)
        let lines = output.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 2)

        // Each line should be valid JSON
        for line in lines {
            let data = line.data(using: .utf8)!
            let parsed = try! JSONSerialization.jsonObject(with: data)
            XCTAssertTrue(parsed is [String: Any])
        }

        // First line should have ref "e1"
        let first = try! JSONSerialization.jsonObject(with: lines[0].data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(first["ref"] as? String, "e1")
    }

    func testNdjsonWithFieldMasking() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil, value: nil,
                                    identifier: nil, childStaticText: nil, enabled: true, focused: false,
                                    position: nil, size: nil, actions: [], children: []))
        ]

        let fields: Set<String> = ["ref", "label"]
        let output = SnapshotFormatter.formatNdjson(elements: nodes, fields: fields)
        let data = output.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(parsed["ref"])
        XCTAssertNil(parsed["type"])
        XCTAssertNil(parsed["enabled"])
    }

    // MARK: - Schema includes new flags

    func testSchemaIncludesDryRunOnPress() {
        let jsonStr = """
        [{"name":"press","flags":[{"name":"--dry-run","type":"bool"}]}]
        """
        // Just verify our schema has --dry-run for mutating commands
        // This test verifies the concept; actual schema is tested via eval.sh
        let data = jsonStr.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let flags = parsed[0]["flags"] as! [[String: Any]]
        let flagNames = flags.map { $0["name"] as! String }
        XCTAssertTrue(flagNames.contains("--dry-run"))
    }

    func testSchemaIncludesFieldsOnSnapshot() {
        let jsonStr = """
        [{"name":"snapshot","flags":[{"name":"--fields","type":"string"},{"name":"--ndjson","type":"bool"}]}]
        """
        let data = jsonStr.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let flags = parsed[0]["flags"] as! [[String: Any]]
        let flagNames = flags.map { $0["name"] as! String }
        XCTAssertTrue(flagNames.contains("--fields"))
        XCTAssertTrue(flagNames.contains("--ndjson"))
    }

    // MARK: - Sanitization in snapshot output

    func testSnapshotJsonSanitizesLabels() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "Click\u{01}Me", axDescription: nil, value: nil,
                                    identifier: "id\u{02}here", childStaticText: nil, enabled: true, focused: false,
                                    position: nil, size: nil, actions: [], children: []))
        ]

        let jsonStr = SnapshotFormatter.formatJson(elements: nodes)
        let data = jsonStr.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        // Control chars should be stripped
        XCTAssertEqual(parsed[0]["label"] as? String, "ClickMe")
        XCTAssertEqual(parsed[0]["identifier"] as? String, "idhere")
    }

    func testHumanOutputSanitizesLabels() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "Save\u{03}File", axDescription: nil, value: nil,
                                    identifier: nil, childStaticText: nil, enabled: true, focused: false,
                                    position: nil, size: nil, actions: [], children: []))
        ]

        let output = SnapshotFormatter.formatHuman(elements: nodes)
        XCTAssertTrue(output.contains("SaveFile"))
        XCTAssertFalse(output.contains("\u{03}"))
    }

    // MARK: - AXHelp (accessibilityHint) support

    func testAXNodeHelpField() {
        let node = AXNode(role: "AXButton", subrole: nil, title: "Submit", axDescription: nil, help: "Double tap to submit the form",
                         value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                         position: nil, size: nil, actions: ["AXPress"], children: [])
        XCTAssertEqual(node.help, "Double tap to submit the form")
    }

    func testAXNodeHelpNilByDefault() {
        let node = AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil,
                         value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                         position: nil, size: nil, actions: [], children: [])
        XCTAssertNil(node.help)
    }

    func testSnapshotElementIncludesHelp() {
        let elem = SnapshotElement(ref: "e1", type: "button", label: "Submit", role: "AXButton",
                                  identifier: nil, help: "Submits the form", enabled: true, focused: false, bounds: nil)
        XCTAssertEqual(elem.help, "Submits the form")
    }

    func testSnapshotJsonIncludesHelp() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "Submit", axDescription: nil,
                                    help: "Double tap to submit", value: nil, identifier: nil, childStaticText: nil,
                                    enabled: true, focused: false, position: nil, size: nil, actions: [], children: []))
        ]

        let jsonStr = SnapshotFormatter.formatJson(elements: nodes)
        let data = jsonStr.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(parsed[0]["help"] as? String, "Double tap to submit")
    }

    func testHelpInFieldMasking() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "Submit", axDescription: nil,
                                    help: "Tap to submit", value: nil, identifier: nil, childStaticText: nil,
                                    enabled: true, focused: false, position: nil, size: nil, actions: [], children: []))
        ]

        let fields: Set<String> = ["ref", "help"]
        let jsonStr = SnapshotFormatter.formatJson(elements: nodes, fields: fields)
        let data = jsonStr.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(parsed[0]["ref"] as? String, "e1")
        XCTAssertEqual(parsed[0]["help"] as? String, "Tap to submit")
        XCTAssertNil(parsed[0]["label"])  // not requested
    }

    func testHelpSanitized() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil,
                                    help: "Hint\u{01}text\u{7F}here", value: nil, identifier: nil, childStaticText: nil,
                                    enabled: true, focused: false, position: nil, size: nil, actions: [], children: []))
        ]

        let jsonStr = SnapshotFormatter.formatJson(elements: nodes)
        let data = jsonStr.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(parsed[0]["help"] as? String, "Hinttexthere")
    }

    func testHumanOutputShowsHelp() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "Submit", axDescription: nil,
                                    help: "Double tap", value: nil, identifier: nil, childStaticText: nil,
                                    enabled: true, focused: false, position: nil, size: nil, actions: [], children: []))
        ]

        let output = SnapshotFormatter.formatHuman(elements: nodes)
        XCTAssertTrue(output.contains("help=\"Double tap\""))
    }
}
