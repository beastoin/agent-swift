import XCTest
@testable import AgentSwiftLib

final class IdbTests: XCTestCase {

    // MARK: - Parse describe-all JSON

    func testParseDescribeAllBasic() throws {
        let json = """
        [{"type":"Application","role":"AXApplication","AXLabel":null,"AXValue":null,
          "frame":{"x":0,"y":0,"width":0,"height":0},"AXUniqueId":null,
          "enabled":true,"children":[]}]
        """.data(using: .utf8)!
        let elements = try IdbBridge.parseDescribeAll(json)
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].type, "Application")
        XCTAssertEqual(elements[0].role, "AXApplication")
        XCTAssertTrue(elements[0].enabled)
    }

    func testParseDescribeAllNested() throws {
        let json = """
        [{"type":"Application","role":"AXApplication","AXLabel":null,"AXValue":null,
          "frame":{"x":0,"y":0,"width":402,"height":874},"AXUniqueId":null,
          "enabled":true,"children":[
            {"type":"Button","role":"AXButton","AXLabel":"Settings","AXValue":null,
             "frame":{"x":16,"y":168,"width":370,"height":90},"AXUniqueId":"com.apple.settings",
             "enabled":true,"children":[]},
            {"type":"Heading","role":"AXHeading","AXLabel":"General","AXValue":null,
             "frame":{"x":16,"y":119,"width":133,"height":40},"AXUniqueId":null,
             "enabled":true,"children":[]}
          ]}]
        """.data(using: .utf8)!
        let elements = try IdbBridge.parseDescribeAll(json)
        // Should flatten: Application + Button + Heading = 3
        XCTAssertEqual(elements.count, 3)
        XCTAssertEqual(elements[0].type, "Application")
        XCTAssertEqual(elements[1].type, "Button")
        XCTAssertEqual(elements[1].label, "Settings")
        XCTAssertEqual(elements[1].uniqueId, "com.apple.settings")
        XCTAssertEqual(elements[2].type, "Heading")
        XCTAssertEqual(elements[2].label, "General")
    }

    func testParseDescribeAllEmpty() throws {
        let json = "[]".data(using: .utf8)!
        let elements = try IdbBridge.parseDescribeAll(json)
        XCTAssertEqual(elements.count, 0)
    }

    func testParseDescribeAllSingleElement() throws {
        let json = """
        [{"type":"Button","role":"AXButton","AXLabel":"Tap me","AXValue":"on",
          "frame":{"x":100,"y":200,"width":50,"height":30},"AXUniqueId":"btn1",
          "enabled":false,"children":[]}]
        """.data(using: .utf8)!
        let elements = try IdbBridge.parseDescribeAll(json)
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].label, "Tap me")
        XCTAssertEqual(elements[0].value, "on")
        XCTAssertEqual(elements[0].uniqueId, "btn1")
        XCTAssertFalse(elements[0].enabled)
    }

    // MARK: - IdbElement frame and center point

    func testIdbElementCenterPoint() {
        let element = IdbElement(type: "Button", role: "AXButton", label: "OK",
                                 value: nil, frame: CGRect(x: 100, y: 200, width: 50, height: 30),
                                 uniqueId: nil, enabled: true, children: [])
        let center = element.centerPoint
        XCTAssertEqual(center.x, 125.0)
        XCTAssertEqual(center.y, 215.0)
    }

    func testIdbElementCenterPointAtOrigin() {
        let element = IdbElement(type: "Button", role: "AXButton", label: nil,
                                 value: nil, frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                 uniqueId: nil, enabled: true, children: [])
        XCTAssertEqual(element.centerPoint.x, 50.0)
        XCTAssertEqual(element.centerPoint.y, 50.0)
    }

    // MARK: - IdbElement isInteractive

    func testIdbElementIsInteractive() {
        let button = IdbElement(type: "Button", role: "AXButton", label: "OK",
                                value: nil, frame: .zero, uniqueId: nil, enabled: true, children: [])
        XCTAssertTrue(button.isInteractive)

        let heading = IdbElement(type: "Heading", role: "AXHeading", label: "Title",
                                 value: nil, frame: .zero, uniqueId: nil, enabled: true, children: [])
        XCTAssertFalse(heading.isInteractive)

        let textField = IdbElement(type: "TextField", role: "AXTextField", label: "Name",
                                    value: nil, frame: .zero, uniqueId: nil, enabled: true, children: [])
        XCTAssertTrue(textField.isInteractive)
    }

    // MARK: - Direction to swipe coordinates

    func testDirectionToSwipeCoordsUp() {
        let coords = IdbBridge.directionToSwipeCoords(direction: "up", screenWidth: 402, screenHeight: 874)
        XCTAssertEqual(coords.fromX, 201.0)
        XCTAssertTrue(coords.fromY > coords.toY, "up swipe should go from lower to higher y")
        XCTAssertEqual(coords.toX, 201.0, "x stays centered")
    }

    func testDirectionToSwipeCoordsDown() {
        let coords = IdbBridge.directionToSwipeCoords(direction: "down", screenWidth: 402, screenHeight: 874)
        XCTAssertEqual(coords.fromX, 201.0)
        XCTAssertTrue(coords.fromY < coords.toY, "down swipe should go from higher to lower y")
    }

    func testDirectionToSwipeCoordsLeft() {
        let coords = IdbBridge.directionToSwipeCoords(direction: "left", screenWidth: 402, screenHeight: 874)
        XCTAssertTrue(coords.fromX > coords.toX, "left swipe should go from right to left")
        XCTAssertEqual(coords.fromY, coords.toY, "y stays centered for horizontal swipe")
    }

    func testDirectionToSwipeCoordsRight() {
        let coords = IdbBridge.directionToSwipeCoords(direction: "right", screenWidth: 402, screenHeight: 874)
        XCTAssertTrue(coords.fromX < coords.toX, "right swipe should go from left to right")
    }

    // MARK: - IdbElement toAXNode conversion

    func testIdbElementToAXNode() {
        let element = IdbElement(type: "Button", role: "AXButton", label: "Save",
                                 value: nil, frame: CGRect(x: 10, y: 20, width: 100, height: 44),
                                 uniqueId: "save-btn", enabled: true, children: [])
        let node = element.toAXNode()
        XCTAssertEqual(node.role, "AXButton")
        XCTAssertEqual(node.title, "Save")
        XCTAssertEqual(node.identifier, "save-btn")
        XCTAssertTrue(node.enabled)
        XCTAssertEqual(node.position?.x, 10)
        XCTAssertEqual(node.position?.y, 20)
        XCTAssertEqual(node.size?.width, 100)
        XCTAssertEqual(node.size?.height, 44)
        XCTAssertTrue(node.actions.contains("AXPress"))
    }

    func testIdbElementToAXNodeNonInteractive() {
        let element = IdbElement(type: "StaticText", role: "AXStaticText", label: "Hello",
                                 value: nil, frame: CGRect(x: 0, y: 0, width: 200, height: 20),
                                 uniqueId: nil, enabled: true, children: [])
        let node = element.toAXNode()
        XCTAssertEqual(node.role, "AXStaticText")
        XCTAssertTrue(node.actions.isEmpty)
    }

    // MARK: - IdbElement displayLabel

    func testIdbElementDisplayLabel() {
        let withLabel = IdbElement(type: "Button", role: "AXButton", label: "OK",
                                   value: "1", frame: .zero, uniqueId: nil, enabled: true, children: [])
        XCTAssertEqual(withLabel.displayLabel, "OK")

        let withValue = IdbElement(type: "Switch", role: "AXSwitch", label: nil,
                                   value: "on", frame: .zero, uniqueId: nil, enabled: true, children: [])
        XCTAssertEqual(withValue.displayLabel, "on")

        let noLabel = IdbElement(type: "Group", role: "AXGroup", label: nil,
                                 value: nil, frame: .zero, uniqueId: nil, enabled: true, children: [])
        XCTAssertNil(noLabel.displayLabel)
    }

    // MARK: - IdbError codes

    func testIdbErrorCodes() {
        XCTAssertEqual(IdbError.notFound.code, "IDB_NOT_FOUND")
        XCTAssertEqual(IdbError.commandFailed("test").code, "IDB_COMMAND_FAILED")
        XCTAssertEqual(IdbError.parseFailed("test").code, "IDB_PARSE_FAILED")
        XCTAssertEqual(IdbError.accessibilityDisabled.code, "IDB_ACCESSIBILITY_DISABLED")
    }

    // MARK: - Parse with null AXValue

    func testParseElementWithNullValue() throws {
        let json = """
        [{"type":"Cell","role":"AXCell","AXLabel":"WiFi","AXValue":null,
          "frame":{"x":0,"y":100,"width":402,"height":52},"AXUniqueId":null,
          "enabled":true,"children":[]}]
        """.data(using: .utf8)!
        let elements = try IdbBridge.parseDescribeAll(json)
        XCTAssertEqual(elements.count, 1)
        XCTAssertNil(elements[0].value)
        XCTAssertEqual(elements[0].label, "WiFi")
    }

    // MARK: - Deep nesting flattens correctly

    func testDeepNestingFlattenCorrectly() throws {
        let json = """
        [{"type":"Group","role":"AXGroup","AXLabel":null,"AXValue":null,
          "frame":{"x":0,"y":0,"width":402,"height":874},"AXUniqueId":null,
          "enabled":true,"children":[
            {"type":"Cell","role":"AXCell","AXLabel":"Row 1","AXValue":null,
             "frame":{"x":0,"y":0,"width":402,"height":52},"AXUniqueId":null,
             "enabled":true,"children":[
               {"type":"StaticText","role":"AXStaticText","AXLabel":"Inner","AXValue":null,
                "frame":{"x":16,"y":10,"width":100,"height":20},"AXUniqueId":null,
                "enabled":true,"children":[]}
             ]}
          ]}]
        """.data(using: .utf8)!
        let elements = try IdbBridge.parseDescribeAll(json)
        // Group + Cell + StaticText = 3
        XCTAssertEqual(elements.count, 3)
        XCTAssertEqual(elements[0].type, "Group")
        XCTAssertEqual(elements[1].type, "Cell")
        XCTAssertEqual(elements[1].label, "Row 1")
        XCTAssertEqual(elements[2].type, "StaticText")
        XCTAssertEqual(elements[2].label, "Inner")
    }
}
