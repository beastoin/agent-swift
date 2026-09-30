import XCTest
@testable import AgentSwiftLib

final class MenuBarTests: XCTestCase {

    // MARK: - MenuBarItem model tests

    func testMenuBarItemCodable() throws {
        struct MenuBarItem: Codable {
            let ref: String
            let title: String?
            let role: String
            let enabled: Bool
            let subrole: String?
        }

        let item = MenuBarItem(ref: "@e1", title: "File", role: "AXMenuBarItem", enabled: true, subrole: nil)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(MenuBarItem.self, from: data)

        XCTAssertEqual(decoded.ref, "@e1")
        XCTAssertEqual(decoded.title, "File")
        XCTAssertEqual(decoded.role, "AXMenuBarItem")
        XCTAssertTrue(decoded.enabled)
        XCTAssertNil(decoded.subrole)
    }

    func testMenuBarItemWithSubrole() throws {
        struct MenuBarItem: Codable {
            let ref: String
            let title: String?
            let role: String
            let enabled: Bool
            let subrole: String?
        }

        let item = MenuBarItem(ref: "@e2", title: "Edit", role: "AXMenuBarItem", enabled: false, subrole: "AXMenuBarItemSubmenu")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(MenuBarItem.self, from: data)

        XCTAssertEqual(decoded.ref, "@e2")
        XCTAssertEqual(decoded.title, "Edit")
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.subrole, "AXMenuBarItemSubmenu")
    }

    // MARK: - Menu bar role mapping

    func testMenuBarRolesInRoleMap() {
        // Verify that menubar-related AX roles are in the ROLE_MAP
        let menuBarNode = AXNode(role: "AXMenuBar", subrole: nil, title: nil, axDescription: nil, value: nil,
                                 identifier: nil, childStaticText: nil, enabled: true, focused: false,
                                 position: nil, size: nil, actions: [], children: [])
        XCTAssertEqual(menuBarNode.displayType, "menubar")

        let menuBarItemNode = AXNode(role: "AXMenuBarItem", subrole: nil, title: "File", axDescription: nil, value: nil,
                                     identifier: nil, childStaticText: nil, enabled: true, focused: false,
                                     position: nil, size: nil, actions: ["AXPress"], children: [])
        XCTAssertEqual(menuBarItemNode.displayType, "menubaritem")
        XCTAssertTrue(menuBarItemNode.isInteractive)
    }

    func testMenuItemIsInteractive() {
        let menuItem = AXNode(role: "AXMenuItem", subrole: nil, title: "Quit", axDescription: nil, value: nil,
                              identifier: nil, childStaticText: nil, enabled: true, focused: false,
                              position: nil, size: nil, actions: ["AXPress"], children: [])
        XCTAssertTrue(menuItem.isInteractive)
    }

    // MARK: - Menu bar node filtering

    func testFilterMenuBarItems() {
        let nodes = [
            AXNode(role: "AXApplication", subrole: nil, title: "TestApp", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: [], children: []),
            AXNode(role: "AXMenuBar", subrole: nil, title: nil, axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: [], children: []),
            AXNode(role: "AXMenuBarItem", subrole: nil, title: "File", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: ["AXPress"], children: []),
            AXNode(role: "AXMenuBarItem", subrole: nil, title: "Edit", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: ["AXPress"], children: []),
            AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: ["AXPress"], children: []),
        ]

        let menuRoles = Set(["AXMenuBar", "AXMenuBarItem", "AXMenuItem", "AXMenu"])
        let menuNodes = nodes.filter { node in
            menuRoles.contains(node.role)
        }

        XCTAssertEqual(menuNodes.count, 3) // MenuBar + 2 MenuBarItems
        XCTAssertEqual(menuNodes[0].role, "AXMenuBar")
        XCTAssertEqual(menuNodes[1].title, "File")
        XCTAssertEqual(menuNodes[2].title, "Edit")
    }

    // MARK: - MenuBarOpenResult model

    func testMenuBarOpenResultCodable() throws {
        struct MenuBarItem: Codable {
            let ref: String
            let title: String?
            let role: String
            let enabled: Bool
            let subrole: String?
        }

        struct MenuBarOpenResult: Codable {
            let opened: String
            let menuItems: [MenuBarItem]
        }

        let result = MenuBarOpenResult(
            opened: "File",
            menuItems: [
                MenuBarItem(ref: "@e10", title: "New", role: "AXMenuItem", enabled: true, subrole: nil),
                MenuBarItem(ref: "@e11", title: "Open…", role: "AXMenuItem", enabled: true, subrole: nil),
                MenuBarItem(ref: "@e12", title: "Save", role: "AXMenuItem", enabled: false, subrole: nil),
            ]
        )

        let data = try JSONEncoder().encode(result)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["opened"] as? String, "File")
        let items = json["menuItems"] as! [[String: Any]]
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0]["ref"] as? String, "@e10")
        XCTAssertEqual(items[0]["title"] as? String, "New")
        XCTAssertEqual(items[2]["enabled"] as? Bool, false)
    }

    // MARK: - Title matching logic

    func testTitleMatchCaseInsensitive() {
        let nodes = [
            AXNode(role: "AXMenuBarItem", subrole: nil, title: "File", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: ["AXPress"], children: []),
            AXNode(role: "AXMenuBarItem", subrole: nil, title: "Edit", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: ["AXPress"], children: []),
        ]

        let target = "file"
        let match = nodes.first { node in
            node.displayLabel?.lowercased() == target.lowercased() ||
            node.title?.lowercased() == target.lowercased()
        }

        XCTAssertNotNil(match)
        XCTAssertEqual(match?.title, "File")
    }

    func testTitleMatchNotFound() {
        let nodes = [
            AXNode(role: "AXMenuBarItem", subrole: nil, title: "File", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: ["AXPress"], children: []),
        ]

        let target = "nonexistent"
        let match = nodes.first { node in
            node.displayLabel?.lowercased() == target.lowercased()
        }

        XCTAssertNil(match)
    }

    // MARK: - MenuBarListResult model

    func testMenuBarListResultCodable() throws {
        struct MenuBarItem: Codable {
            let ref: String
            let title: String?
            let role: String
            let enabled: Bool
            let subrole: String?
        }

        struct MenuBarListResult: Codable {
            let items: [MenuBarItem]
            let source: String
        }

        let result = MenuBarListResult(
            items: [
                MenuBarItem(ref: "@e1", title: "Apple", role: "AXMenuBarItem", enabled: true, subrole: nil),
            ],
            source: "app+extras"
        )

        let data = try JSONEncoder().encode(result)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["source"] as? String, "app+extras")
        let items = json["items"] as! [[String: Any]]
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["title"] as? String, "Apple")
    }

    // MARK: - Ref format validation

    func testRefFormatParsing() {
        let ref = "@e5"
        XCTAssertTrue(ref.hasPrefix("@e"))
        let numStr = ref.dropFirst(2)
        let idx = Int(numStr)
        XCTAssertNotNil(idx)
        XCTAssertEqual(idx, 5)
    }

    func testRefFormatInvalid() {
        let ref = "File"
        XCTAssertFalse(ref.hasPrefix("@e"))
    }

    // MARK: - Display label from AXDescription (MenuBarExtra items)

    func testMenuBarExtraDisplayLabel() {
        // MenuBarExtra items often use AXDescription instead of title
        let node = AXNode(role: "AXMenuBarItem", subrole: nil, title: nil, axDescription: "tmv status",
                          value: nil, identifier: nil, childStaticText: nil, enabled: true, focused: false,
                          position: nil, size: nil, actions: ["AXPress"], children: [])

        XCTAssertEqual(node.displayLabel, "tmv status")
        XCTAssertNil(node.title)
        XCTAssertTrue(node.isInteractive)
    }
}
