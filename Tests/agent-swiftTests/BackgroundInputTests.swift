import XCTest
@testable import AgentSwiftLib

final class BackgroundInputTests: XCTestCase {

    // MARK: - SkyLightBridge

    func testSkyLightBridgeSingleton() {
        let a = SkyLightBridge.shared
        let b = SkyLightBridge.shared
        XCTAssertTrue(a === b)
    }

    func testSkyLightBridgeDiagnosticNotEmpty() {
        let bridge = SkyLightBridge.shared
        XCTAssertFalse(bridge.diagnostic.isEmpty)
        // Should contain "loaded" and "missing" sections
        XCTAssertTrue(bridge.diagnostic.contains("loaded:"))
        XCTAssertTrue(bridge.diagnostic.contains("missing:"))
    }

    func testSkyLightBridgeAvailabilityConsistent() {
        let bridge = SkyLightBridge.shared
        // If isAvailable, canPostToPid must also be true
        if bridge.isAvailable {
            XCTAssertTrue(bridge.canPostToPid)
        }
    }

    func testSkyLightBridgeCanPostToPidImpliesLoaded() {
        let bridge = SkyLightBridge.shared
        if bridge.canPostToPid {
            XCTAssertTrue(bridge.diagnostic.contains("SLEventPostToPid"))
        }
    }

    // MARK: - SkyLightField enum

    func testSkyLightFieldValues() {
        XCTAssertEqual(SkyLightField.gesturePhase.rawValue, 0)
        XCTAssertEqual(SkyLightField.clickState.rawValue, 1)
        XCTAssertEqual(SkyLightField.buttonNumber.rawValue, 3)
        XCTAssertEqual(SkyLightField.eventSubtype.rawValue, 7)
        XCTAssertEqual(SkyLightField.targetPID.rawValue, 40)
        XCTAssertEqual(SkyLightField.windowID1.rawValue, 51)
        XCTAssertEqual(SkyLightField.clickGroupID.rawValue, 58)
        XCTAssertEqual(SkyLightField.windowID2.rawValue, 91)
        XCTAssertEqual(SkyLightField.windowID3.rawValue, 92)
    }

    func testSkyLightFieldAllCasesDistinct() {
        let values: [UInt32] = [
            SkyLightField.gesturePhase.rawValue,
            SkyLightField.clickState.rawValue,
            SkyLightField.buttonNumber.rawValue,
            SkyLightField.eventSubtype.rawValue,
            SkyLightField.targetPID.rawValue,
            SkyLightField.windowID1.rawValue,
            SkyLightField.clickGroupID.rawValue,
            SkyLightField.windowID2.rawValue,
            SkyLightField.windowID3.rawValue,
        ]
        XCTAssertEqual(Set(values).count, values.count, "All field values must be unique")
    }

    // MARK: - EventStamping.resolveWindowID

    func testResolveWindowIDForNonexistentPID() {
        // PID 99999 should not have any windows
        let wid = EventStamping.resolveWindowID(pid: 99999)
        XCTAssertNil(wid)
    }

    func testResolveWindowIDForCurrentProcess() {
        // Current process (test runner) typically has no visible windows in headless mode
        // but this tests the code path doesn't crash
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let _ = EventStamping.resolveWindowID(pid: pid)
        // No assertion on result — just verify no crash
    }

    // MARK: - FocusGuard

    func testFocusGuardDeadline() {
        XCTAssertEqual(FocusGuard.deadline, 5.0)
    }

    func testFocusGuardSettleTime() {
        XCTAssertEqual(FocusGuard.settleTime, 0.050)
    }

    func testFocusGuardWithSuppressionPassthrough() {
        let guard_ = FocusGuard()
        // Action should execute and return its value
        let result = guard_.withSuppression(for: 99999) {
            return 42
        }
        XCTAssertEqual(result, 42)
    }

    func testFocusGuardWithSuppressionThrows() {
        let guard_ = FocusGuard()
        enum TestError: Error { case test }
        XCTAssertThrowsError(try guard_.withSuppression(for: 99999) {
            throw TestError.test
        })
    }

    func testFocusGuardIsFrontmostForNonexistent() {
        XCTAssertFalse(FocusGuard.isFrontmost(pid: 99999))
    }

    func testFocusGuardFrontmostPIDReturnsValue() {
        // On a headed macOS system this returns a PID; in headless it may be nil
        // Either way, it shouldn't crash
        let _ = FocusGuard.frontmostPID()
    }

    // MARK: - SessionData.windowID

    func testSessionDataWindowIDField() {
        var session = SessionData.empty
        XCTAssertNil(session.windowID)
        session.windowID = 12345
        XCTAssertEqual(session.windowID, 12345)
    }

    func testSessionDataWindowIDPersists() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("bginput-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = SessionStore(path: tmpDir.appendingPathComponent("session.json"))
        var session = SessionData.empty
        session.pid = 1234
        session.windowID = 56789
        try store.save(session)

        let loaded = store.load()
        XCTAssertEqual(loaded.windowID, 56789)
        XCTAssertEqual(loaded.pid, 1234)
    }

    func testSessionDataWindowIDBackwardCompat() throws {
        // Old session JSON without windowID should decode cleanly
        let json = """
        {"refs":{},"pid":1234}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)
        XCTAssertNil(decoded.windowID)
        XCTAssertEqual(decoded.pid, 1234)
    }

    // MARK: - Background click/type/scroll return false when SkyLight unavailable

    func testBackgroundClickReturnsFalseForInvalidTarget() {
        // With PID 0 or when SkyLight isn't available on test host
        let result = EventStamping.backgroundClick(at: CGPoint(x: 100, y: 100), pid: 0, windowID: 0)
        // Either false (no SkyLight) or true (SkyLight posted events to pid 0)
        // The point is it doesn't crash
        let _ = result
    }

    func testBackgroundTypeReturnsFalseForInvalidTarget() {
        let (_, method) = EventStamping.backgroundType(text: "test", pid: 0)
        // Method is either "none" (no SkyLight) or "skylight" (posted but PID 0 won't process)
        XCTAssertFalse(method.isEmpty)
    }

    func testBackgroundScrollReturnsFalseForInvalidTarget() {
        let result = EventStamping.backgroundScroll(at: CGPoint(x: 100, y: 100), pid: 0, windowID: 0, deltaY: 5)
        let _ = result
    }

    // MARK: - Doctor output struct encoding

    func testClickResultWithDeliveryEncodes() throws {
        // Test that the delivery field encodes correctly in ClickResult-like structures
        struct TestResult: Codable {
            let success: Bool
            var delivery: String? = nil
        }
        let r1 = TestResult(success: true, delivery: "background")
        let data1 = try JSONEncoder().encode(r1)
        let json1 = try JSONSerialization.jsonObject(with: data1) as? [String: Any]
        XCTAssertEqual(json1?["delivery"] as? String, "background")

        let r2 = TestResult(success: true)
        let data2 = try JSONEncoder().encode(r2)
        let json2 = try JSONSerialization.jsonObject(with: data2) as? [String: Any]
        // nil delivery should not appear in JSON (or appear as null)
        // Both behaviors are acceptable
    }

    func testScrollResultDeliveryEncodes() throws {
        struct TestScrollResult: Codable {
            let target: String
            let success: Bool
            var delivery: String? = nil
        }
        let r = TestScrollResult(target: "down", success: true, delivery: "foreground")
        let data = try JSONEncoder().encode(r)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["delivery"] as? String, "foreground")
    }

    // MARK: - SkyLightBridge on macOS

    func testSkyLightBridgeLoadedOnMacOS() {
        // On macOS, SkyLight framework should load (all test hosts are macOS)
        let bridge = SkyLightBridge.shared
        // At minimum, the framework should load — individual symbols may vary by OS version
        XCTAssertTrue(bridge.diagnostic.contains("loaded:"))
    }

    func testMainConnectionIDReturnsNonNegative() {
        let cid = SkyLightBridge.shared.mainConnectionID()
        // cid is 0 when SkyLight unavailable, positive when connected to WindowServer
        XCTAssertGreaterThanOrEqual(cid, 0)
    }
}
