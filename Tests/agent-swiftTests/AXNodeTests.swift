import XCTest
@testable import AgentSwiftLib

final class AXNodeTests: XCTestCase {
    func testDisplayType() {
        let button = AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil, value: nil,
                           identifier: nil, childStaticText: nil, enabled: true, focused: false,
                           position: nil, size: nil, actions: ["AXPress"], children: [])
        XCTAssertEqual(button.displayType, "button")

        let textfield = AXNode(role: "AXTextField", subrole: nil, title: nil, axDescription: nil, value: "hello",
                              identifier: "nameField", childStaticText: nil, enabled: true, focused: true,
                              position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(textfield.displayType, "textfield")

        let staticText = AXNode(role: "AXStaticText", subrole: nil, title: nil, axDescription: nil, value: "Label",
                               identifier: nil, childStaticText: nil, enabled: true, focused: false,
                               position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(staticText.displayType, "statictext")
    }

    func testIsInteractive() {
        let button = AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil, value: nil,
                           identifier: nil, childStaticText: nil, enabled: true, focused: false,
                           position: nil, size: nil, actions: ["AXPress"], children: [])
        XCTAssertTrue(button.isInteractive)

        let staticText = AXNode(role: "AXStaticText", subrole: nil, title: nil, axDescription: nil, value: "Label",
                               identifier: nil, childStaticText: nil, enabled: true, focused: false,
                               position: nil, size: nil, actions: [], children: [])
        XCTAssertFalse(staticText.isInteractive)

        // Non-standard role but has AXPress action
        let custom = AXNode(role: "AXCustom", subrole: nil, title: "Click", axDescription: nil, value: nil,
                           identifier: nil, childStaticText: nil, enabled: true, focused: false,
                           position: nil, size: nil, actions: ["AXPress"], children: [])
        XCTAssertTrue(custom.isInteractive)
    }

    func testDisplayLabel() {
        let withTitle = AXNode(role: "AXButton", subrole: nil, title: "Save", axDescription: nil, value: nil,
                              identifier: nil, childStaticText: nil, enabled: true, focused: false,
                              position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(withTitle.displayLabel, "Save")

        let withValue = AXNode(role: "AXTextField", subrole: nil, title: nil, axDescription: nil, value: "hello",
                              identifier: nil, childStaticText: nil, enabled: true, focused: false,
                              position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(withValue.displayLabel, "hello")

        let neither = AXNode(role: "AXGroup", subrole: nil, title: nil, axDescription: nil, value: nil,
                            identifier: nil, childStaticText: nil, enabled: true, focused: false,
                            position: nil, size: nil, actions: [], children: [])
        XCTAssertNil(neither.displayLabel)
    }

    func testFlattenTree() {
        let child1 = AXNode(role: "AXButton", subrole: nil, title: "B1", axDescription: nil, value: nil,
                           identifier: nil, childStaticText: nil, enabled: true, focused: false,
                           position: nil, size: nil, actions: [], children: [])
        let child2 = AXNode(role: "AXButton", subrole: nil, title: "B2", axDescription: nil, value: nil,
                           identifier: nil, childStaticText: nil, enabled: true, focused: false,
                           position: nil, size: nil, actions: [], children: [])
        let parent = AXNode(role: "AXGroup", subrole: nil, title: nil, axDescription: nil, value: nil,
                           identifier: nil, childStaticText: nil, enabled: true, focused: false,
                           position: nil, size: nil, actions: [], children: [child1, child2])

        let flat = AXClient.flattenTree(parent)
        XCTAssertEqual(flat.count, 3)
        XCTAssertEqual(flat[0].role, "AXGroup")
        XCTAssertEqual(flat[1].title, "B1")
        XCTAssertEqual(flat[2].title, "B2")
    }

    func testToRefEntry() {
        let node = AXNode(role: "AXButton", subrole: nil, title: "Save", axDescription: nil, value: nil,
                         identifier: "saveBtn", childStaticText: nil, enabled: true, focused: false,
                         position: CGPoint(x: 10, y: 20), size: CGSize(width: 80, height: 30),
                         actions: ["AXPress"], children: [])
        let entry = node.toRefEntry()
        XCTAssertEqual(entry.role, "AXButton")
        XCTAssertEqual(entry.label, "Save")
        XCTAssertEqual(entry.identifier, "saveBtn")
        XCTAssertTrue(entry.enabled)
        XCTAssertFalse(entry.focused)
        XCTAssertEqual(entry.bounds?.x, 10)
        XCTAssertEqual(entry.bounds?.width, 80)
        XCTAssertEqual(entry.actions, ["AXPress"])
    }
}
