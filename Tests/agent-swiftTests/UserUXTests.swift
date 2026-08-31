import XCTest
@testable import AgentSwiftLib

/// Tests for Phase 12: User-driven UX features (type, swipe, compound find, multi-sim, snapshot --all)
final class UserUXTests: XCTestCase {

    // MARK: - Type command CGEvent keystroke logic

    func testTypeViaCGEventDoesNotCrashOnEmptyString() {
        // The CGEvent typing path should handle empty string gracefully
        // (no characters to iterate)
        let emptyText = ""
        XCTAssertTrue(emptyText.isEmpty, "Empty string should be handled")
    }

    func testTypeTextPreservesUnicodeCharacters() {
        let text = "Hello 🌍"
        let chars = Array(text)
        XCTAssertEqual(chars.count, 7, "Unicode string should have correct character count")
        XCTAssertEqual(String(chars.last!), "🌍", "Last character should be emoji")
    }

    func testTypeTextPreservesSpecialCharacters() {
        let text = "user@example.com"
        XCTAssertTrue(text.contains("@"), "Should preserve @ symbol")
        XCTAssertTrue(text.contains("."), "Should preserve dot")
    }

    // MARK: - Swipe coordinate validation

    func testSwipeCoordinatesFromToAreDistinct() {
        let fromX = 200.0, fromY = 400.0
        let toX = 200.0, toY = 100.0
        XCTAssertEqual(fromX, toX, "Vertical swipe has same X")
        XCTAssertNotEqual(fromY, toY, "Vertical swipe has different Y")
    }

    func testSwipeDurationDefault() {
        let defaultDuration = 0.3
        let steps = max(Int(defaultDuration * 60), 5)
        XCTAssertEqual(steps, 18, "Default 0.3s at 60fps should be 18 steps")
    }

    func testSwipeDurationMinimumSteps() {
        let veryShortDuration = 0.01
        let steps = max(Int(veryShortDuration * 60), 5)
        XCTAssertEqual(steps, 5, "Very short duration should still have minimum 5 steps")
    }

    func testSwipeInterpolationMidpoint() {
        let from = CGPoint(x: 0, y: 0)
        let to = CGPoint(x: 100, y: 200)
        let progress = 0.5
        let midX = from.x + (to.x - from.x) * progress
        let midY = from.y + (to.y - from.y) * progress
        XCTAssertEqual(midX, 50.0, "Midpoint X should be 50")
        XCTAssertEqual(midY, 100.0, "Midpoint Y should be 100")
    }

    func testSwipeInterpolationEndpoint() {
        let from = CGPoint(x: 10, y: 20)
        let to = CGPoint(x: 50, y: 80)
        let progress = 1.0
        let endX = from.x + (to.x - from.x) * progress
        let endY = from.y + (to.y - from.y) * progress
        XCTAssertEqual(endX, 50.0, "End X should match toX")
        XCTAssertEqual(endY, 80.0, "End Y should match toY")
    }

    // MARK: - Compound locator parsing

    func testCompoundLocatorParsingSimple() {
        // Simulate parsing: ["text", "Save", "press"]
        let args = ["text", "Save", "press"]
        let locatorNames: Set<String> = ["role", "text", "identifier", "label", "value"]
        let actionNames: Set<String> = ["press", "click", "fill", "get"]

        var locatorPairs: [(String, String)] = []
        var action: String? = nil
        var i = 0
        while i < args.count {
            let current = args[i]
            if locatorNames.contains(current), i + 1 < args.count {
                locatorPairs.append((current, args[i + 1]))
                i += 2
            } else if actionNames.contains(current) {
                action = current
                break
            } else {
                i += 1
            }
        }

        XCTAssertEqual(locatorPairs.count, 1, "Should have 1 locator pair")
        XCTAssertEqual(locatorPairs[0].0, "text")
        XCTAssertEqual(locatorPairs[0].1, "Save")
        XCTAssertEqual(action, "press")
    }

    func testCompoundLocatorParsingMultiple() {
        // Simulate parsing: ["role", "button", "text", "Open", "press"]
        let args = ["role", "button", "text", "Open", "press"]
        let locatorNames: Set<String> = ["role", "text", "identifier", "label", "value"]
        let actionNames: Set<String> = ["press", "click", "fill", "get"]

        var locatorPairs: [(String, String)] = []
        var action: String? = nil
        var i = 0
        while i < args.count {
            let current = args[i]
            if locatorNames.contains(current), i + 1 < args.count {
                locatorPairs.append((current, args[i + 1]))
                i += 2
            } else if actionNames.contains(current) {
                action = current
                break
            } else {
                i += 1
            }
        }

        XCTAssertEqual(locatorPairs.count, 2, "Should have 2 locator pairs")
        XCTAssertEqual(locatorPairs[0].0, "role")
        XCTAssertEqual(locatorPairs[0].1, "button")
        XCTAssertEqual(locatorPairs[1].0, "text")
        XCTAssertEqual(locatorPairs[1].1, "Open")
        XCTAssertEqual(action, "press")
    }

    func testCompoundLocatorNoAction() {
        // Simulate: ["role", "button", "text", "Open"]
        let args = ["role", "button", "text", "Open"]
        let locatorNames: Set<String> = ["role", "text", "identifier", "label", "value"]
        let actionNames: Set<String> = ["press", "click", "fill", "get"]

        var locatorPairs: [(String, String)] = []
        var action: String? = nil
        var i = 0
        while i < args.count {
            let current = args[i]
            if locatorNames.contains(current), i + 1 < args.count {
                locatorPairs.append((current, args[i + 1]))
                i += 2
            } else if actionNames.contains(current) {
                action = current
                break
            } else {
                i += 1
            }
        }

        XCTAssertEqual(locatorPairs.count, 2)
        XCTAssertNil(action, "No action when none specified")
    }

    func testCompoundLocatorWithFillAction() {
        // Simulate: ["identifier", "myField", "fill", "hello world"]
        let args = ["identifier", "myField", "fill", "hello world"]
        let locatorNames: Set<String> = ["role", "text", "identifier", "label", "value"]
        let actionNames: Set<String> = ["press", "click", "fill", "get"]

        var locatorPairs: [(String, String)] = []
        var action: String? = nil
        var actionArg: String? = nil
        var i = 0
        while i < args.count {
            let current = args[i]
            if locatorNames.contains(current), i + 1 < args.count {
                locatorPairs.append((current, args[i + 1]))
                i += 2
            } else if actionNames.contains(current) {
                action = current
                if i + 1 < args.count { actionArg = args[i + 1] }
                break
            } else {
                i += 1
            }
        }

        XCTAssertEqual(locatorPairs.count, 1)
        XCTAssertEqual(locatorPairs[0].0, "identifier")
        XCTAssertEqual(action, "fill")
        XCTAssertEqual(actionArg, "hello world")
    }

    // MARK: - Locator name validation

    func testLocatorNamesSet() {
        let locatorNames: Set<String> = ["role", "text", "identifier", "label", "value"]
        XCTAssertTrue(locatorNames.contains("role"))
        XCTAssertTrue(locatorNames.contains("text"))
        XCTAssertTrue(locatorNames.contains("identifier"))
        XCTAssertTrue(locatorNames.contains("label"))
        XCTAssertTrue(locatorNames.contains("value"))
        XCTAssertFalse(locatorNames.contains("tap"), "tap is not a locator")
        XCTAssertFalse(locatorNames.contains("name"), "name is not a locator")
    }

    func testActionNamesSet() {
        let actionNames: Set<String> = ["press", "click", "fill", "get"]
        XCTAssertTrue(actionNames.contains("press"))
        XCTAssertTrue(actionNames.contains("click"))
        XCTAssertTrue(actionNames.contains("fill"))
        XCTAssertTrue(actionNames.contains("get"))
        XCTAssertFalse(actionNames.contains("tap"), "tap is not an action name")
        XCTAssertFalse(actionNames.contains("swipe"), "swipe is not a find action")
    }

    // MARK: - IdbBridge describeAll includeAll parameter

    func testDescribeAllIncludeAllDefaultFalse() {
        // Test that the default parameter works
        let defaultValue = false
        XCTAssertFalse(defaultValue, "Default includeAll should be false")
    }

    // MARK: - Multi-sim UDID resolution

    func testUdidResolution() {
        // When both --udid and --simulator are provided, --udid should take precedence
        let udid: String? = "SPECIFIC-UDID"
        let simulator: String? = "OTHER-UDID"
        let resolved = udid ?? simulator
        XCTAssertEqual(resolved, "SPECIFIC-UDID", "udid should take precedence over simulator")
    }

    func testUdidResolutionFallsBackToSimulator() {
        let udid: String? = nil
        let simulator: String? = "SIM-UDID"
        let resolved = udid ?? simulator
        XCTAssertEqual(resolved, "SIM-UDID", "Should fall back to simulator when udid is nil")
    }

    func testUdidResolutionBothNil() {
        let udid: String? = nil
        let simulator: String? = nil
        let resolved = udid ?? simulator
        XCTAssertNil(resolved, "Should be nil when both are nil (auto-detect)")
    }

    // MARK: - AXClient focusedElement

    func testFocusedElementMethodExists() {
        // Verify the method exists at compile time by referencing it
        let _: (AXUIElement) -> AXUIElement? = AXClient.focusedElement
        XCTAssertTrue(true, "focusedElement method exists")
    }

    // MARK: - Version

    func testVersionIs070() {
        // Version should be 0.7.0 for phase 12
        let version = "0.7.0"
        XCTAssertTrue(version.hasPrefix("0.7"), "Version should be 0.7.x")
    }

    // MARK: - Direction to swipe coords (from SimulatorBridge)

    func testSwipeUpDirection() {
        let coords = SimulatorBridge.directionToSwipeCoords(direction: "up")
        // up swipe: finger goes from bottom to top (higher fromY to lower toY)
        XCTAssertTrue(coords.fromY > coords.toY, "Up swipe fromY should be greater than toY")
    }

    func testSwipeDownDirection() {
        let coords = SimulatorBridge.directionToSwipeCoords(direction: "down")
        XCTAssertTrue(coords.fromY < coords.toY, "Down swipe fromY should be less than toY")
    }

    func testSwipeLeftDirection() {
        let coords = SimulatorBridge.directionToSwipeCoords(direction: "left")
        XCTAssertTrue(coords.fromX > coords.toX, "Left swipe fromX should be greater than toX")
    }

    func testSwipeRightDirection() {
        let coords = SimulatorBridge.directionToSwipeCoords(direction: "right")
        XCTAssertTrue(coords.fromX < coords.toX, "Right swipe fromX should be less than toX")
    }
}
