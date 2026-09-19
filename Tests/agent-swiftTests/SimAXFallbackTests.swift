import XCTest
@testable import AgentSwiftLib

final class SimAXFallbackTests: XCTestCase {

    // MARK: - SimAXBridge initialization

    func testSimAXBridgeInit() {
        let bridge = SimAXBridge(udid: "test-udid-123")
        XCTAssertNotNil(bridge)
    }

    func testSimAXBridgeUDIDStored() {
        let bridge = SimAXBridge(udid: "58A27B2A-60C3-47E4-B3C2-0FF06DF0C08F")
        XCTAssertEqual(bridge.udid, "58A27B2A-60C3-47E4-B3C2-0FF06DF0C08F")
    }

    // MARK: - Probe methods

    func testProbeIdbReturnsResult() {
        // probeIdb returns a (Bool, String) tuple regardless of idb availability
        let bridge = SimAXBridge(udid: "fake-udid")
        let (_, diag) = bridge.probeIdb()
        // Should return something — either success or failure diagnostic
        XCTAssertFalse(diag.isEmpty, "probe diagnostic should not be empty")
    }

    func testProbeAXAccessReturnsResult() {
        let bridge = SimAXBridge(udid: "fake-udid")
        let (_, diag) = bridge.probeAXAccess()
        XCTAssertFalse(diag.isEmpty, "AX probe diagnostic should not be empty")
    }

    func testProbeIdbWithInvalidUDID() {
        let bridge = SimAXBridge(udid: "nonexistent-device-udid")
        let (ok, diag) = bridge.probeIdb()
        // Should fail with a diagnostic
        XCTAssertFalse(ok, "probeIdb should fail for nonexistent UDID")
        XCTAssertFalse(diag.isEmpty)
    }

    // MARK: - SnapshotResult with method

    func testSnapshotResultEncodesMethod() throws {
        let result = SnapshotResult(elements: [], method: "ax")
        let data = try JSONEncoder().encode(result)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["method"] as? String, "ax")
    }

    func testSnapshotResultWithIdbMethod() throws {
        let result = SnapshotResult(elements: [], method: "idb")
        let data = try JSONEncoder().encode(result)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["method"] as? String, "idb")
    }

    func testSnapshotResultNilMethod() throws {
        let result = SnapshotResult(elements: [], method: nil)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SnapshotResult.self, from: data)
        XCTAssertNil(decoded.method)
    }

    func testSnapshotResultWithElements() throws {
        let elem = SnapshotElement(
            ref: "e1", type: "button", label: "OK", role: "AXButton",
            identifier: nil, enabled: true, focused: false, bounds: nil
        )
        let result = SnapshotResult(elements: [elem], method: "ax")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SnapshotResult.self, from: data)
        XCTAssertEqual(decoded.elements.count, 1)
        XCTAssertEqual(decoded.elements[0].ref, "e1")
        XCTAssertEqual(decoded.method, "ax")
    }

    // MARK: - SnapshotFormatter method parameter

    func testFormatJsonWithoutMethod() {
        let output = SnapshotFormatter.formatJson(elements: [])
        // Without method, should be a plain array
        let data = output.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(parsed is [Any], "Without method, output should be an array")
    }

    func testFormatJsonWithMethod() {
        let output = SnapshotFormatter.formatJson(elements: [], method: "ax")
        let data = output.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed, "With method, output should be an object")
        XCTAssertEqual(parsed?["method"] as? String, "ax")
    }

    func testFormatJsonIdbMethodPreservesElements() {
        let node = AXNode(
            role: "AXButton", subrole: nil, title: "Save", axDescription: nil,
            value: nil, identifier: "save-btn", childStaticText: nil,
            enabled: true, focused: false, position: CGPoint(x: 10, y: 20),
            size: CGSize(width: 100, height: 44), actions: ["AXPress"], children: []
        )
        let output = SnapshotFormatter.formatJson(elements: [("e1", node)], method: "idb")
        let data = output.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed)
        let elements = parsed?["elements"] as? [[String: Any]]
        XCTAssertEqual(elements?.count, 1)
        XCTAssertEqual(elements?[0]["ref"] as? String, "e1")
        XCTAssertEqual(elements?[0]["type"] as? String, "button")
        XCTAssertEqual(elements?[0]["label"] as? String, "Save")
    }

    // MARK: - SessionData snapshotMethod

    func testSessionDataSnapshotMethodField() {
        var session = SessionData.empty
        XCTAssertNil(session.snapshotMethod)
        session.snapshotMethod = "ax"
        XCTAssertEqual(session.snapshotMethod, "ax")
    }

    func testSessionDataSnapshotMethodPersists() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("simaxtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = SessionStore(path: tmpDir.appendingPathComponent("session.json"))
        var session = SessionData.empty
        session.simulatorUDID = "test-udid"
        session.snapshotMethod = "ax"
        try store.save(session)

        let loaded = store.load()
        XCTAssertEqual(loaded.snapshotMethod, "ax")
        XCTAssertEqual(loaded.simulatorUDID, "test-udid")
    }

    func testSessionDataSnapshotMethodBackwardCompat() throws {
        // Old session JSON without snapshotMethod should decode cleanly
        let json = """
        {"refs":{},"simulatorUDID":"test"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)
        XCTAssertNil(decoded.snapshotMethod)
        XCTAssertEqual(decoded.simulatorUDID, "test")
    }

    // MARK: - SnapshotResult round-trip

    func testSnapshotResultRoundTrip() throws {
        let elem = SnapshotElement(
            ref: "e2", type: "textfield", label: "Name", role: "AXTextField",
            identifier: "name-field", enabled: true, focused: true, bounds: nil
        )
        let result = SnapshotResult(elements: [elem], method: "ax")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SnapshotResult.self, from: data)
        XCTAssertEqual(decoded.method, "ax")
        XCTAssertEqual(decoded.elements.count, 1)
        XCTAssertEqual(decoded.elements[0].label, "Name")
        XCTAssertTrue(decoded.elements[0].focused)
    }

    func testSnapshotResultIdbRoundTrip() throws {
        let result = SnapshotResult(elements: [], method: "idb")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SnapshotResult.self, from: data)
        XCTAssertEqual(decoded.method, "idb")
        XCTAssertTrue(decoded.elements.isEmpty)
    }

    // MARK: - IdbElement toAXNode preserves data

    func testIdbElementToAXNodePreservesFields() {
        let idbEl = IdbElement(
            type: "Button", role: "AXButton", label: "OK", value: nil,
            frame: CGRect(x: 10, y: 20, width: 100, height: 44),
            uniqueId: "btn1", enabled: true, children: []
        )
        let node = idbEl.toAXNode()
        XCTAssertEqual(node.role, "AXButton")
        XCTAssertEqual(node.title, "OK")
        XCTAssertEqual(node.enabled, true)
        XCTAssertEqual(node.position, CGPoint(x: 10, y: 20))
        XCTAssertEqual(node.size, CGSize(width: 100, height: 44))
    }
}
