import XCTest
@testable import AgentSwiftLib

final class SessionStoreTests: XCTestCase {
    var tempDir: URL!
    var store: SessionStore!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SessionStore(path: tempDir.appendingPathComponent("session.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadEmpty() {
        let session = store.load()
        XCTAssertFalse(session.isConnected)
        XCTAssertNil(session.pid)
        XCTAssertNil(session.bundleId)
        XCTAssertEqual(session.refs.count, 0)
    }

    func testSaveAndLoad() throws {
        var session = SessionData.empty
        session.pid = 12345
        session.bundleId = "com.test.app"
        session.connectedAt = "2026-03-09T00:00:00Z"
        session.refs["e1"] = SessionData.RefEntry(
            role: "AXButton",
            label: "Save",
            identifier: "saveBtn",
            enabled: true,
            focused: false,
            bounds: SessionData.RefEntry.Bounds(x: 10, y: 20, width: 80, height: 30),
            actions: ["AXPress"]
        )

        try store.save(session)
        let loaded = store.load()

        XCTAssertTrue(loaded.isConnected)
        XCTAssertEqual(loaded.pid, 12345)
        XCTAssertEqual(loaded.bundleId, "com.test.app")
        XCTAssertEqual(loaded.connectedAt, "2026-03-09T00:00:00Z")
        XCTAssertEqual(loaded.refs.count, 1)
        XCTAssertEqual(loaded.refs["e1"]?.role, "AXButton")
        XCTAssertEqual(loaded.refs["e1"]?.label, "Save")
    }

    func testClear() throws {
        var session = SessionData.empty
        session.pid = 999
        try store.save(session)
        XCTAssertTrue(store.load().isConnected)

        try store.clear()
        XCTAssertFalse(store.load().isConnected)
    }

    func testClearNonexistent() throws {
        try store.clear()
    }
}
