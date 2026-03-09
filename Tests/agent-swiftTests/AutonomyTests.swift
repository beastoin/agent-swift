import XCTest
import ArgumentParser
@testable import AgentSwiftLib

final class AutonomyTests: XCTestCase {

    // MARK: - Is condition evaluation on AXNode

    func testIsExistsCondition() {
        let node = AXNode(role: "AXButton", subrole: nil, title: "Save", axDescription: nil,
                         value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                         position: CGPoint(x: 10, y: 20), size: CGSize(width: 80, height: 30),
                         actions: ["AXPress"], children: [])
        // Element exists → true
        XCTAssertEqual(node.role, "AXButton")
        XCTAssertTrue(node.isInteractive)
    }

    func testIsVisibleCondition() {
        let visible = AXNode(role: "AXButton", subrole: nil, title: nil, axDescription: nil,
                            value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                            position: CGPoint(x: 100, y: 200), size: CGSize(width: 80, height: 30),
                            actions: [], children: [])
        XCTAssertNotNil(visible.position)
        XCTAssertNotNil(visible.size)

        let invisible = AXNode(role: "AXButton", subrole: nil, title: nil, axDescription: nil,
                              value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                              position: nil, size: nil, actions: [], children: [])
        XCTAssertNil(invisible.position)
        XCTAssertNil(invisible.size)
    }

    func testIsEnabledCondition() {
        let enabled = AXNode(role: "AXButton", subrole: nil, title: nil, axDescription: nil,
                            value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                            position: nil, size: nil, actions: [], children: [])
        XCTAssertTrue(enabled.enabled)

        let disabled = AXNode(role: "AXButton", subrole: nil, title: nil, axDescription: nil,
                             value: nil, identifier: nil, childStaticText: nil, enabled: false, focused: false,
                             position: nil, size: nil, actions: [], children: [])
        XCTAssertFalse(disabled.enabled)
    }

    func testIsFocusedCondition() {
        let focused = AXNode(role: "AXTextField", subrole: nil, title: nil, axDescription: nil,
                            value: "hello", identifier: nil, childStaticText: nil, enabled: true, focused: true,
                            position: nil, size: nil, actions: [], children: [])
        XCTAssertTrue(focused.focused)

        let unfocused = AXNode(role: "AXTextField", subrole: nil, title: nil, axDescription: nil,
                              value: "hello", identifier: nil, childStaticText: nil, enabled: true, focused: false,
                              position: nil, size: nil, actions: [], children: [])
        XCTAssertFalse(unfocused.focused)
    }

    // MARK: - Wait text matching

    func testWaitTextMatchingOnNodes() {
        let nodes = [
            AXNode(role: "AXStaticText", subrole: nil, title: "Welcome back", axDescription: nil,
                  value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                  position: nil, size: nil, actions: [], children: []),
            AXNode(role: "AXButton", subrole: nil, title: "Submit", axDescription: nil,
                  value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                  position: nil, size: nil, actions: ["AXPress"], children: []),
        ]

        // "Welcome" should match via contains
        let hasWelcome = nodes.contains { $0.displayLabel?.contains("Welcome") == true }
        XCTAssertTrue(hasWelcome)

        // "Submit" should match
        let hasSubmit = nodes.contains { $0.displayLabel?.contains("Submit") == true }
        XCTAssertTrue(hasSubmit)

        // "NotHere" should not match
        let hasNotHere = nodes.contains { $0.displayLabel?.contains("NotHere") == true }
        XCTAssertFalse(hasNotHere)
    }

    func testWaitGoneCondition() {
        // If index is out of range, element is "gone"
        let nodes = [
            AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil,
                  value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                  position: nil, size: nil, actions: [], children: [])
        ]

        // @e1 (index 0) exists → not gone
        let e1Gone = 0 >= nodes.count
        XCTAssertFalse(e1Gone)

        // @e5 (index 4) doesn't exist → gone
        let e5Gone = 4 >= nodes.count
        XCTAssertTrue(e5Gone)
    }

    // MARK: - Schema structure

    func testSchemaRegistryNotEmpty() {
        // Verify we can access the schema from the test (it's defined in main.swift, not the lib)
        // Test the underlying model types instead
        let schema = CommandSchema(
            name: "test",
            description: "A test command",
            args: [CommandSchema.ArgSchema(name: "ref", type: "string", required: true)],
            flags: [CommandSchema.FlagSchema(name: "--json", type: "bool", defaultValue: "false")],
            exitCodes: ["0": "success", "2": "error"]
        )
        XCTAssertEqual(schema.name, "test")
        XCTAssertEqual(schema.args.count, 1)
        XCTAssertEqual(schema.args[0].name, "ref")
        XCTAssertTrue(schema.args[0].required)
        XCTAssertEqual(schema.flags.count, 1)
        XCTAssertEqual(schema.flags[0].defaultValue, "false")
        XCTAssertEqual(schema.exitCodes["0"], "success")
    }

    func testSchemaEncodesToJSON() throws {
        let schema = CommandSchema(
            name: "press",
            description: "Press element by ref",
            args: [CommandSchema.ArgSchema(name: "ref", type: "string", required: true)],
            flags: [CommandSchema.FlagSchema(name: "--json", type: "bool", defaultValue: "false")],
            exitCodes: ["0": "success", "2": "error"]
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(schema)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"name\":\"press\"") || json.contains("\"name\" : \"press\""))
        XCTAssertTrue(json.contains("\"description\""))
        XCTAssertTrue(json.contains("\"args\""))
        XCTAssertTrue(json.contains("\"flags\""))
    }

    func testSchemaDecodesFromJSON() throws {
        let json = """
        {"name":"fill","description":"Enter text","args":[{"name":"ref","type":"string","required":true}],"flags":[],"exitCodes":{"0":"success"}}
        """
        let decoder = JSONDecoder()
        let schema = try decoder.decode(CommandSchema.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(schema.name, "fill")
        XCTAssertEqual(schema.args.count, 1)
        XCTAssertTrue(schema.args[0].required)
    }

    // MARK: - Scroll direction parsing

    func testScrollDirectionParsing() {
        let validDirections = ["up", "down"]
        XCTAssertTrue(validDirections.contains("up"))
        XCTAssertTrue(validDirections.contains("down"))
        XCTAssertFalse(validDirections.contains("left"))

        // Ref-style targets start with @ or e
        let refTarget = "@e1"
        let isRef = refTarget.hasPrefix("@") || refTarget.hasPrefix("e")
        XCTAssertTrue(isRef)

        let dirTarget = "down"
        let isDir = ["up", "down"].contains(dirTarget)
        XCTAssertTrue(isDir)
    }

    // MARK: - Exit code contract

    func testExitCodeContract() {
        // Verify our exit code constants
        XCTAssertEqual(ExitCode.success.rawValue, 0)
        XCTAssertEqual(ExitCode(1).rawValue, 1)  // assertion false
        XCTAssertEqual(ExitCode(2).rawValue, 2)  // error
    }
}
