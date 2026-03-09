import XCTest
@testable import AgentSwiftLib

final class InteractionTests: XCTestCase {

    // MARK: - SessionData.interactiveSnapshot

    func testInteractiveSnapshotFieldExists() {
        var session = SessionData.empty
        XCTAssertNil(session.interactiveSnapshot)

        session.interactiveSnapshot = true
        XCTAssertEqual(session.interactiveSnapshot, true)

        session.interactiveSnapshot = false
        XCTAssertEqual(session.interactiveSnapshot, false)
    }

    func testInteractiveSnapshotPersistence() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-swift-test-\(UUID().uuidString)")
        let sessionPath = tmpDir.appendingPathComponent("session.json")
        let store = SessionStore(path: sessionPath)

        var session = SessionData.empty
        session.pid = 12345
        session.interactiveSnapshot = true
        try store.save(session)

        let loaded = store.load()
        XCTAssertEqual(loaded.interactiveSnapshot, true)

        // Clean up
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testInteractiveSnapshotDefaultNil() {
        let session = SessionData.empty
        XCTAssertNil(session.interactiveSnapshot)
    }

    func testInteractiveSnapshotBackwardCompatibility() throws {
        // Old session.json without interactiveSnapshot should still load
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-swift-test-\(UUID().uuidString)")
        let sessionPath = tmpDir.appendingPathComponent("session.json")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let oldJson = """
        {
            "pid": 12345,
            "refs": {},
            "lastSnapshotAt": null
        }
        """
        try oldJson.data(using: .utf8)!.write(to: sessionPath)

        let store = SessionStore(path: sessionPath)
        let loaded = store.load()
        XCTAssertEqual(loaded.pid, 12345)
        XCTAssertNil(loaded.interactiveSnapshot)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - performFill

    func testPerformFillMethodExists() {
        // Verify the method signature compiles and is accessible
        let _: (AXUIElement, String) -> Bool = AXClient.performFill
        XCTAssertTrue(true) // Compilation is the test
    }

    // MARK: - captureScreenshot

    func testCaptureScreenshotMethodExists() {
        // Verify the method signature compiles and is accessible
        let _: (Int, String) -> Bool = AXClient.captureScreenshot
        XCTAssertTrue(true) // Compilation is the test
    }

    // MARK: - AXNode property access (used by get command)

    func testNodeDisplayLabel() {
        // title takes priority
        let node1 = AXNode(role: "AXButton", subrole: nil, title: "Save", axDescription: "Save button",
                          value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                          position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(node1.displayLabel, "Save")

        // falls back to axDescription
        let node2 = AXNode(role: "AXButton", subrole: nil, title: nil, axDescription: "Close",
                          value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                          position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(node2.displayLabel, "Close")

        // falls back to childStaticText
        let node3 = AXNode(role: "AXButton", subrole: nil, title: nil, axDescription: nil,
                          value: nil, identifier: nil, childStaticText: "Click me", enabled: true, focused: false,
                          position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(node3.displayLabel, "Click me")

        // falls back to value
        let node4 = AXNode(role: "AXTextField", subrole: nil, title: nil, axDescription: nil,
                          value: "hello", identifier: nil, childStaticText: nil, enabled: true, focused: false,
                          position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(node4.displayLabel, "hello")

        // nil when nothing available
        let node5 = AXNode(role: "AXGroup", subrole: nil, title: nil, axDescription: nil,
                          value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                          position: nil, size: nil, actions: [], children: [])
        XCTAssertNil(node5.displayLabel)
    }

    func testNodeDisplayType() {
        let button = AXNode(role: "AXButton", subrole: nil, title: nil, axDescription: nil,
                           value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                           position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(button.displayType, "button")

        let textField = AXNode(role: "AXTextField", subrole: nil, title: nil, axDescription: nil,
                              value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                              position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(textField.displayType, "textfield")

        let textArea = AXNode(role: "AXTextArea", subrole: nil, title: nil, axDescription: nil,
                             value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                             position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(textArea.displayType, "textfield")

        let searchField = AXNode(role: "AXSearchField", subrole: nil, title: nil, axDescription: nil,
                                value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                                position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(searchField.displayType, "searchfield")
    }

    func testNodeIdentifier() {
        let node = AXNode(role: "AXButton", subrole: nil, title: "Save", axDescription: nil,
                         value: nil, identifier: "saveButton", childStaticText: nil, enabled: true, focused: false,
                         position: nil, size: nil, actions: ["AXPress"], children: [])
        XCTAssertEqual(node.identifier, "saveButton")
        XCTAssertEqual(node.role, "AXButton")
        XCTAssertTrue(node.isInteractive)
    }

    func testNodeBounds() {
        let node = AXNode(role: "AXButton", subrole: nil, title: nil, axDescription: nil,
                         value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                         position: CGPoint(x: 100, y: 200), size: CGSize(width: 80, height: 30),
                         actions: [], children: [])
        XCTAssertNotNil(node.bounds)
        XCTAssertEqual(node.bounds?.x, 100)
        XCTAssertEqual(node.bounds?.y, 200)
        XCTAssertEqual(node.bounds?.width, 80)
        XCTAssertEqual(node.bounds?.height, 30)

        let noBounds = AXNode(role: "AXButton", subrole: nil, title: nil, axDescription: nil,
                             value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                             position: nil, size: nil, actions: [], children: [])
        XCTAssertNil(noBounds.bounds)
    }
}
