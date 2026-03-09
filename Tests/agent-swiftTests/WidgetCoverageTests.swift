import XCTest
@testable import AgentSwiftLib

final class WidgetCoverageTests: XCTestCase {

    private func mkNode(_ role: String, title: String? = nil, actions: [String] = []) -> AXNode {
        AXNode(role: role, subrole: nil, title: title, axDescription: nil, value: nil,
               identifier: nil, childStaticText: nil, enabled: true, focused: false,
               position: nil, size: nil, actions: actions, children: [])
    }

    // ─── Group 1: Existing control mappings (10 assertions) ───────────────
    func testExistingControlMappings() {
        XCTAssertEqual(mkNode("AXButton").displayType, "button")
        XCTAssertEqual(mkNode("AXTextField").displayType, "textfield")
        XCTAssertEqual(mkNode("AXTextArea").displayType, "textfield")
        XCTAssertEqual(mkNode("AXCheckBox").displayType, "checkbox")
        XCTAssertEqual(mkNode("AXRadioButton").displayType, "radio")
        XCTAssertEqual(mkNode("AXPopUpButton").displayType, "dropdown")
        XCTAssertEqual(mkNode("AXComboBox").displayType, "dropdown")
        XCTAssertEqual(mkNode("AXSlider").displayType, "slider")
        XCTAssertEqual(mkNode("AXSwitch").displayType, "switch")
        XCTAssertEqual(mkNode("AXToggle").displayType, "switch")
    }

    func testExistingControlMappings2() {
        XCTAssertEqual(mkNode("AXMenuItem").displayType, "menuitem")
        XCTAssertEqual(mkNode("AXMenuButton").displayType, "menubutton")
        XCTAssertEqual(mkNode("AXLink").displayType, "link")
        XCTAssertEqual(mkNode("AXTab").displayType, "tab")
        XCTAssertEqual(mkNode("AXTabGroup").displayType, "tabgroup")
        XCTAssertEqual(mkNode("AXDisclosureTriangle").displayType, "disclosure")
        XCTAssertEqual(mkNode("AXIncrementor").displayType, "stepper")
        XCTAssertEqual(mkNode("AXColorWell").displayType, "colorwell")
        XCTAssertEqual(mkNode("AXSegmentedControl").displayType, "segmented")
    }

    // ─── Group 1: Existing content/container mappings (8 assertions) ──────
    func testExistingContentContainerMappings() {
        XCTAssertEqual(mkNode("AXStaticText").displayType, "label")
        XCTAssertEqual(mkNode("AXImage").displayType, "image")
        XCTAssertEqual(mkNode("AXGroup").displayType, "group")
        XCTAssertEqual(mkNode("AXWindow").displayType, "window")
        XCTAssertEqual(mkNode("AXToolbar").displayType, "toolbar")
        XCTAssertEqual(mkNode("AXScrollArea").displayType, "scrollarea")
        XCTAssertEqual(mkNode("AXMenu").displayType, "menu")
        XCTAssertEqual(mkNode("AXMenuBar").displayType, "menubar")
    }

    // ─── Group 2: New control roles (5 assertions) ────────────────────────
    func testNewControlMappings() {
        XCTAssertEqual(mkNode("AXSearchField").displayType, "searchfield")
        XCTAssertEqual(mkNode("AXDateField").displayType, "datefield")
        XCTAssertEqual(mkNode("AXLevelIndicator").displayType, "levelindicator")
        XCTAssertEqual(mkNode("AXRadioGroup").displayType, "radiogroup")
        XCTAssertEqual(mkNode("AXStepper").displayType, "stepper")
    }

    // ─── Group 2: New controls are interactive (5 assertions) ─────────────
    func testNewControlsAreInteractive() {
        XCTAssertTrue(mkNode("AXSearchField").isInteractive)
        XCTAssertTrue(mkNode("AXDateField").isInteractive)
        XCTAssertTrue(mkNode("AXLevelIndicator").isInteractive)
        XCTAssertTrue(mkNode("AXRadioGroup").isInteractive)
        XCTAssertTrue(mkNode("AXStepper").isInteractive)
    }

    // ─── Group 3: Container & layout roles (8 assertions) ──────────────────
    func testContainerMappings() {
        XCTAssertEqual(mkNode("AXSplitGroup").displayType, "splitgroup")
        XCTAssertEqual(mkNode("AXSplitter").displayType, "splitter")
        XCTAssertEqual(mkNode("AXSheet").displayType, "sheet")
        XCTAssertEqual(mkNode("AXDrawer").displayType, "drawer")
        XCTAssertEqual(mkNode("AXLayoutArea").displayType, "layoutarea")
        XCTAssertEqual(mkNode("AXLayoutItem").displayType, "layoutitem")
        XCTAssertEqual(mkNode("AXOutline").displayType, "outline")
        XCTAssertEqual(mkNode("AXBrowser").displayType, "browser")
    }

    // ─── Group 3: Table/list structure (3 assertions) ─────────────────────
    func testTableListMappings() {
        XCTAssertEqual(mkNode("AXRow").displayType, "row")
        XCTAssertEqual(mkNode("AXColumn").displayType, "column")
        XCTAssertEqual(mkNode("AXCell").displayType, "cell")
    }

    // ─── Group 3: Menu roles (3 assertions) ───────────────────────────────
    func testMenuMappings() {
        XCTAssertEqual(mkNode("AXMenuBarItem").displayType, "menubaritem")
        XCTAssertEqual(mkNode("AXMenuItemCheckbox").displayType, "menuitem")
        XCTAssertEqual(mkNode("AXMenuItemRadio").displayType, "menuitem")
    }

    // ─── Group 3: Non-interactive containers (5 assertions) ───────────────
    func testContainersNotInteractive() {
        XCTAssertFalse(mkNode("AXSplitGroup").isInteractive)
        XCTAssertFalse(mkNode("AXSheet").isInteractive)
        XCTAssertFalse(mkNode("AXOutline").isInteractive)
        XCTAssertFalse(mkNode("AXTable").isInteractive)
        XCTAssertFalse(mkNode("AXWindow").isInteractive)
    }

    // ─── Group 3: Menu items are interactive (3 assertions) ───────────────
    func testMenuItemsInteractive() {
        XCTAssertTrue(mkNode("AXMenuBarItem").isInteractive)
        XCTAssertTrue(mkNode("AXMenuItemCheckbox").isInteractive)
        XCTAssertTrue(mkNode("AXMenuItemRadio").isInteractive)
    }

    // ─── Group 4: Content & display roles (8 assertions) ────────────────────
    func testContentMappings() {
        XCTAssertEqual(mkNode("AXHeading").displayType, "heading")
        XCTAssertEqual(mkNode("AXProgressIndicator").displayType, "progressbar")
        XCTAssertEqual(mkNode("AXBusyIndicator").displayType, "busyindicator")
        XCTAssertEqual(mkNode("AXValueIndicator").displayType, "valueindicator")
        XCTAssertEqual(mkNode("AXRelevanceIndicator").displayType, "relevanceindicator")
        XCTAssertEqual(mkNode("AXRuler").displayType, "ruler")
        XCTAssertEqual(mkNode("AXScrollBar").displayType, "scrollbar")
        XCTAssertEqual(mkNode("AXHandle").displayType, "handle")
    }

    // ─── Group 4: System & misc roles (5 assertions) ─────────────────────
    func testSystemMappings() {
        XCTAssertEqual(mkNode("AXApplication").displayType, "application")
        XCTAssertEqual(mkNode("AXSystemWide").displayType, "system")
        XCTAssertEqual(mkNode("AXUnknown").displayType, "unknown")
        XCTAssertEqual(mkNode("AXWebArea").displayType, "webarea")
        XCTAssertEqual(mkNode("AXPopover").displayType, "popover")
    }

    // ─── Group 4: Content/system not interactive (5 assertions) ───────────
    func testContentNotInteractive() {
        XCTAssertFalse(mkNode("AXProgressIndicator").isInteractive)
        XCTAssertFalse(mkNode("AXScrollBar").isInteractive)
        XCTAssertFalse(mkNode("AXApplication").isInteractive)
        XCTAssertFalse(mkNode("AXImage").isInteractive)
        XCTAssertFalse(mkNode("AXGroup").isInteractive)
    }

    // ─── ROLE_MAP completeness (2 assertions) ─────────────────────────────
    func testRoleMapCompleteness() {
        XCTAssertGreaterThanOrEqual(ROLE_MAP.count, 50)
        XCTAssertTrue(ROLE_MAP.values.allSatisfy { !$0.isEmpty })
    }

    // ─── INTERACTIVE_ROLES completeness (2 assertions) ────────────────────
    func testInteractiveRolesCompleteness() {
        for role in INTERACTIVE_ROLES {
            XCTAssertNotNil(ROLE_MAP[role], "\(role) is interactive but not in ROLE_MAP")
        }
        XCTAssertGreaterThanOrEqual(INTERACTIVE_ROLES.count, 20)
    }

    // ─── AXStaticText → label rename (1 assertion) ────────────────────────
    func testStaticTextIsLabel() {
        XCTAssertEqual(ROLE_MAP["AXStaticText"], "label")
    }

    // ─── Fallback behavior (2 assertions) ─────────────────────────────────
    func testFallbackBehavior() {
        XCTAssertEqual(mkNode("AXCustomWidget").displayType, "customwidget")
        XCTAssertEqual(mkNode("AXSuperSpecialThing").displayType, "superspecialthing")
    }

    // ─── AXPress fallback (2 assertions) ──────────────────────────────────
    func testAXPressFallback() {
        XCTAssertTrue(mkNode("AXCustomWidget", actions: ["AXPress"]).isInteractive)
        XCTAssertTrue(mkNode("AXCustomWidget", actions: ["AXConfirm"]).isInteractive)
    }
}
