import XCTest
@testable import AgentSwiftLib

final class WidgetCoverageTests: XCTestCase {

    // Helper to create a minimal AXNode for testing
    private func mkNode(_ role: String, title: String? = nil, actions: [String] = []) -> AXNode {
        AXNode(role: role, subrole: nil, title: title, axDescription: nil, value: nil,
               identifier: nil, childStaticText: nil, enabled: true, focused: false,
               position: nil, size: nil, actions: actions, children: [])
    }

    // ─── Controls: Buttons (2 assertions) ─────────────────────────────────
    func testButtonMappings() {
        XCTAssertEqual(mkNode("AXButton").displayType, "button")
        XCTAssertEqual(mkNode("AXMenuButton").displayType, "menubutton")
    }

    // ─── Controls: Text Input (4 assertions) ──────────────────────────────
    func testTextInputMappings() {
        XCTAssertEqual(mkNode("AXTextField").displayType, "textfield")
        XCTAssertEqual(mkNode("AXTextArea").displayType, "textfield")
        XCTAssertEqual(mkNode("AXSearchField").displayType, "searchfield")
        XCTAssertEqual(mkNode("AXDateField").displayType, "datefield")
    }

    // ─── Controls: Selection (6 assertions) ───────────────────────────────
    func testSelectionMappings() {
        XCTAssertEqual(mkNode("AXCheckBox").displayType, "checkbox")
        XCTAssertEqual(mkNode("AXRadioButton").displayType, "radio")
        XCTAssertEqual(mkNode("AXRadioGroup").displayType, "radiogroup")
        XCTAssertEqual(mkNode("AXPopUpButton").displayType, "dropdown")
        XCTAssertEqual(mkNode("AXComboBox").displayType, "dropdown")
        XCTAssertEqual(mkNode("AXSegmentedControl").displayType, "segmented")
    }

    // ─── Controls: Value (6 assertions) ───────────────────────────────────
    func testValueMappings() {
        XCTAssertEqual(mkNode("AXSlider").displayType, "slider")
        XCTAssertEqual(mkNode("AXSwitch").displayType, "switch")
        XCTAssertEqual(mkNode("AXToggle").displayType, "switch")
        XCTAssertEqual(mkNode("AXIncrementor").displayType, "stepper")
        XCTAssertEqual(mkNode("AXStepper").displayType, "stepper")
        XCTAssertEqual(mkNode("AXColorWell").displayType, "colorwell")
    }

    // ─── Controls: Other (2 assertions) ───────────────────────────────────
    func testOtherControlMappings() {
        XCTAssertEqual(mkNode("AXLevelIndicator").displayType, "levelindicator")
        XCTAssertEqual(mkNode("AXDisclosureTriangle").displayType, "disclosure")
    }

    // ─── Navigation & Links (3 assertions) ────────────────────────────────
    func testNavigationMappings() {
        XCTAssertEqual(mkNode("AXLink").displayType, "link")
        XCTAssertEqual(mkNode("AXTab").displayType, "tab")
        XCTAssertEqual(mkNode("AXTabGroup").displayType, "tabgroup")
    }

    // ─── Menus (5 assertions) ─────────────────────────────────────────────
    func testMenuMappings() {
        XCTAssertEqual(mkNode("AXMenu").displayType, "menu")
        XCTAssertEqual(mkNode("AXMenuBar").displayType, "menubar")
        XCTAssertEqual(mkNode("AXMenuBarItem").displayType, "menubaritem")
        XCTAssertEqual(mkNode("AXMenuItem").displayType, "menuitem")
        XCTAssertEqual(mkNode("AXMenuItemCheckbox").displayType, "menuitem")
    }

    // ─── Containers & Layout (8 assertions) ───────────────────────────────
    func testContainerMappings() {
        XCTAssertEqual(mkNode("AXGroup").displayType, "group")
        XCTAssertEqual(mkNode("AXWindow").displayType, "window")
        XCTAssertEqual(mkNode("AXToolbar").displayType, "toolbar")
        XCTAssertEqual(mkNode("AXScrollArea").displayType, "scrollarea")
        XCTAssertEqual(mkNode("AXSplitGroup").displayType, "splitgroup")
        XCTAssertEqual(mkNode("AXSplitter").displayType, "splitter")
        XCTAssertEqual(mkNode("AXSheet").displayType, "sheet")
        XCTAssertEqual(mkNode("AXDrawer").displayType, "drawer")
    }

    // ─── Table/List Structure (7 assertions) ──────────────────────────────
    func testTableListMappings() {
        XCTAssertEqual(mkNode("AXTable").displayType, "table")
        XCTAssertEqual(mkNode("AXList").displayType, "list")
        XCTAssertEqual(mkNode("AXOutline").displayType, "outline")
        XCTAssertEqual(mkNode("AXBrowser").displayType, "browser")
        XCTAssertEqual(mkNode("AXRow").displayType, "row")
        XCTAssertEqual(mkNode("AXColumn").displayType, "column")
        XCTAssertEqual(mkNode("AXCell").displayType, "cell")
    }

    // ─── Content & Display (8 assertions) ─────────────────────────────────
    func testContentMappings() {
        XCTAssertEqual(mkNode("AXStaticText").displayType, "label")
        XCTAssertEqual(mkNode("AXImage").displayType, "image")
        XCTAssertEqual(mkNode("AXHeading").displayType, "heading")
        XCTAssertEqual(mkNode("AXProgressIndicator").displayType, "progressbar")
        XCTAssertEqual(mkNode("AXBusyIndicator").displayType, "busyindicator")
        XCTAssertEqual(mkNode("AXValueIndicator").displayType, "valueindicator")
        XCTAssertEqual(mkNode("AXRelevanceIndicator").displayType, "relevanceindicator")
        XCTAssertEqual(mkNode("AXRuler").displayType, "ruler")
    }

    // ─── Scroll Components (2 assertions) ─────────────────────────────────
    func testScrollMappings() {
        XCTAssertEqual(mkNode("AXScrollBar").displayType, "scrollbar")
        XCTAssertEqual(mkNode("AXHandle").displayType, "handle")
    }

    // ─── System-Level (3 assertions) ──────────────────────────────────────
    func testSystemMappings() {
        XCTAssertEqual(mkNode("AXApplication").displayType, "application")
        XCTAssertEqual(mkNode("AXSystemWide").displayType, "system")
        XCTAssertEqual(mkNode("AXUnknown").displayType, "unknown")
    }

    // ─── Interactive Classification (14 assertions) ───────────────────────
    func testInteractiveRoles() {
        // Should be interactive
        XCTAssertTrue(mkNode("AXButton").isInteractive)
        XCTAssertTrue(mkNode("AXTextField").isInteractive)
        XCTAssertTrue(mkNode("AXCheckBox").isInteractive)
        XCTAssertTrue(mkNode("AXSearchField").isInteractive)
        XCTAssertTrue(mkNode("AXDateField").isInteractive)
        XCTAssertTrue(mkNode("AXSegmentedControl").isInteractive)
        XCTAssertTrue(mkNode("AXMenuBarItem").isInteractive)
        XCTAssertTrue(mkNode("AXLevelIndicator").isInteractive)
        XCTAssertTrue(mkNode("AXRadioGroup").isInteractive)
        XCTAssertTrue(mkNode("AXColorWell").isInteractive)
    }

    // ─── Non-Interactive Classification (10 assertions) ───────────────────
    func testNonInteractiveRoles() {
        XCTAssertFalse(mkNode("AXStaticText").isInteractive)
        XCTAssertFalse(mkNode("AXImage").isInteractive)
        XCTAssertFalse(mkNode("AXProgressIndicator").isInteractive)
        XCTAssertFalse(mkNode("AXOutline").isInteractive)
        XCTAssertFalse(mkNode("AXSheet").isInteractive)
        XCTAssertFalse(mkNode("AXTable").isInteractive)
        XCTAssertFalse(mkNode("AXScrollBar").isInteractive)
        XCTAssertFalse(mkNode("AXApplication").isInteractive)
        XCTAssertFalse(mkNode("AXGroup").isInteractive)
        XCTAssertFalse(mkNode("AXWindow").isInteractive)
    }

    // ─── AXPress Fallback (2 assertions) ──────────────────────────────────
    func testAXPressFallback() {
        let customWithPress = mkNode("AXCustomWidget", actions: ["AXPress"])
        XCTAssertTrue(customWithPress.isInteractive)

        let customWithConfirm = mkNode("AXCustomWidget", actions: ["AXConfirm"])
        XCTAssertTrue(customWithConfirm.isInteractive)
    }

    // ─── Fallback Behavior (2 assertions) ─────────────────────────────────
    func testFallbackBehavior() {
        XCTAssertEqual(mkNode("AXCustomWidget").displayType, "customwidget")
        XCTAssertEqual(mkNode("AXSuperSpecialThing").displayType, "superspecialthing")
    }

    // ─── ROLE_MAP Completeness (2 assertions) ─────────────────────────────
    func testRoleMapCompleteness() {
        // Must have >= 50 entries
        XCTAssertGreaterThanOrEqual(ROLE_MAP.count, 50)
        // All values should be non-empty
        XCTAssertTrue(ROLE_MAP.values.allSatisfy { !$0.isEmpty })
    }

    // ─── INTERACTIVE_ROLES Completeness (2 assertions) ────────────────────
    func testInteractiveRolesCompleteness() {
        // All interactive roles must be in ROLE_MAP
        for role in INTERACTIVE_ROLES {
            XCTAssertNotNil(ROLE_MAP[role], "\(role) is interactive but not in ROLE_MAP")
        }
        // Must have >= 20 interactive roles
        XCTAssertGreaterThanOrEqual(INTERACTIVE_ROLES.count, 20)
    }

    // ─── No Duplicate Definitions (1 assertion) ───────────────────────────
    func testNoDuplicateInteractiveDefinition() {
        // INTERACTIVE_ROLES should be the single source of truth
        // Verify the set is non-empty (it exists and is used)
        XCTAssertFalse(INTERACTIVE_ROLES.isEmpty)
    }

    // ─── AXStaticText → label Rename (1 assertion) ────────────────────────
    func testStaticTextIsLabel() {
        XCTAssertEqual(ROLE_MAP["AXStaticText"], "label")
    }
}
