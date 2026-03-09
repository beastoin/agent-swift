import XCTest
@testable import AgentSwiftLib

final class SnapshotFormatterTests: XCTestCase {
    func testFormatHumanBasic() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "Save", axDescription: nil, value: nil,
                                    identifier: "saveBtn", childStaticText: nil, enabled: true, focused: false,
                                    position: nil, size: nil, actions: ["AXPress"], children: [])),
            (ref: "e2", node: AXNode(role: "AXTextField", subrole: nil, title: nil, axDescription: nil, value: "hello",
                                    identifier: nil, childStaticText: nil, enabled: true, focused: false,
                                    position: nil, size: nil, actions: [], children: [])),
            (ref: "e3", node: AXNode(role: "AXStaticText", subrole: nil, title: nil, axDescription: nil, value: "Ready",
                                    identifier: nil, childStaticText: nil, enabled: true, focused: false,
                                    position: nil, size: nil, actions: [], children: []))
        ]

        let output = SnapshotFormatter.formatHuman(elements: nodes)
        let lines = output.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("@e1 [button] \"Save\""))
        XCTAssertTrue(lines[0].contains("identifier=saveBtn"))
        XCTAssertTrue(lines[1].hasPrefix("@e2 [textfield] \"hello\""))
        XCTAssertTrue(lines[2].hasPrefix("@e3 [label] \"Ready\""))
    }

    func testFormatHumanNoLabel() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXGroup", subrole: nil, title: nil, axDescription: nil, value: nil,
                                    identifier: nil, childStaticText: nil, enabled: true, focused: false,
                                    position: nil, size: nil, actions: [], children: []))
        ]

        let output = SnapshotFormatter.formatHuman(elements: nodes)
        XCTAssertEqual(output, "@e1 [group]")
    }

    func testFormatJsonValid() {
        let nodes = [
            (ref: "e1", node: AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil, value: nil,
                                    identifier: nil, childStaticText: nil, enabled: true, focused: false,
                                    position: CGPoint(x: 10, y: 20), size: CGSize(width: 80, height: 30),
                                    actions: ["AXPress"], children: []))
        ]

        let jsonStr = SnapshotFormatter.formatJson(elements: nodes)
        let data = jsonStr.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0]["ref"] as? String, "e1")
        XCTAssertEqual(parsed[0]["type"] as? String, "button")
        XCTAssertEqual(parsed[0]["label"] as? String, "OK")
        XCTAssertEqual(parsed[0]["role"] as? String, "AXButton")
        XCTAssertEqual(parsed[0]["enabled"] as? Bool, true)
    }
}
