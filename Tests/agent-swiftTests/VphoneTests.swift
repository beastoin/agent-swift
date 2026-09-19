import XCTest
@testable import AgentSwiftLib

final class VphoneTests: XCTestCase {

    // MARK: - Coordinate conversion

    func testLogicalToPixel() {
        let (px, py) = VphoneBridge.logicalToPixel(x: 215, y: 466)
        XCTAssertEqual(px, 645)
        XCTAssertEqual(py, 1398)
    }

    func testPixelToLogical() {
        let (x, y) = VphoneBridge.pixelToLogical(px: 1290, py: 2796)
        XCTAssertEqual(x, 430.0, accuracy: 0.01)
        XCTAssertEqual(y, 932.0, accuracy: 0.01)
    }

    func testLogicalToPixelOrigin() {
        let (px, py) = VphoneBridge.logicalToPixel(x: 0, y: 0)
        XCTAssertEqual(px, 0)
        XCTAssertEqual(py, 0)
    }

    func testLogicalToPixelMaxCorner() {
        let (px, py) = VphoneBridge.logicalToPixel(x: 430, y: 932)
        XCTAssertEqual(px, 1290)
        XCTAssertEqual(py, 2796)
    }

    func testPixelToLogicalCenter() {
        let (x, y) = VphoneBridge.pixelToLogical(px: 645, py: 1398)
        XCTAssertEqual(x, 215.0, accuracy: 0.01)
        XCTAssertEqual(y, 466.0, accuracy: 0.01)
    }

    // MARK: - Screen dimensions

    func testScreenDimensions() {
        XCTAssertEqual(VphoneBridge.screenWidthPx, 1290)
        XCTAssertEqual(VphoneBridge.screenHeightPx, 2796)
        XCTAssertEqual(VphoneBridge.screenWidth, 430)
        XCTAssertEqual(VphoneBridge.screenHeight, 932)
        XCTAssertEqual(VphoneBridge.scale, 3.0)
    }

    // MARK: - Socket path

    func testDefaultSocketPath() {
        let path = VphoneBridge.defaultSocketPath(for: "voxtest")
        XCTAssertTrue(path.hasSuffix(".vphone/VMs/voxtest/vphone.sock"))
        XCTAssertTrue(path.contains("/.vphone/VMs/"))
    }

    func testInitWithName() {
        let bridge = VphoneBridge(vmName: "myvm")
        XCTAssertEqual(bridge.vmName, "myvm")
        XCTAssertTrue(bridge.socketPath.hasSuffix("myvm/vphone.sock"))
    }

    func testInitWithCustomSocket() {
        let bridge = VphoneBridge(vmName: "test", socketPath: "/tmp/custom.sock")
        XCTAssertEqual(bridge.socketPath, "/tmp/custom.sock")
        XCTAssertEqual(bridge.vmName, "test")
    }

    // MARK: - Session vphone mode

    func testSessionVphoneModeDetection() {
        var session = SessionData.empty
        XCTAssertFalse(session.isVphoneMode)
        XCTAssertFalse(session.isConnected)

        session.vphoneVM = "voxtest"
        XCTAssertTrue(session.isVphoneMode)
        XCTAssertTrue(session.isConnected)
    }

    func testSessionVphoneFields() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(path: tempDir.appendingPathComponent("session.json"))

        var session = SessionData.empty
        session.vphoneVM = "voxtest"
        session.vphoneSocket = "/path/to/vphone.sock"
        session.connectedAt = "2026-09-04T00:00:00Z"

        try store.save(session)
        let loaded = store.load()

        XCTAssertTrue(loaded.isConnected)
        XCTAssertTrue(loaded.isVphoneMode)
        XCTAssertFalse(loaded.isSimulatorMode)
        XCTAssertFalse(loaded.isMirrorMode)
        XCTAssertEqual(loaded.vphoneVM, "voxtest")
        XCTAssertEqual(loaded.vphoneSocket, "/path/to/vphone.sock")
    }

    func testSessionVphoneDoesNotAffectOtherModes() {
        var session = SessionData.empty
        session.simulatorUDID = "AAAA-BBBB"
        XCTAssertTrue(session.isSimulatorMode)
        XCTAssertFalse(session.isVphoneMode)

        session.mirrorMode = true
        XCTAssertTrue(session.isMirrorMode)
        XCTAssertFalse(session.isVphoneMode)
    }

    // MARK: - Error codes

    func testVphoneErrorCodes() {
        XCTAssertEqual(VphoneError.socketNotFound("x").code, "VPHONE_SOCKET_NOT_FOUND")
        XCTAssertEqual(VphoneError.connectionFailed("x").code, "VPHONE_CONNECTION_FAILED")
        XCTAssertEqual(VphoneError.commandFailed("x").code, "VPHONE_COMMAND_FAILED")
        XCTAssertEqual(VphoneError.invalidResponse("x").code, "VPHONE_INVALID_RESPONSE")
    }

    func testVphoneErrorHints() {
        XCTAssertNotNil(VphoneError.socketNotFound("x").hint)
        XCTAssertNotNil(VphoneError.connectionFailed("x").hint)
        XCTAssertNotNil(VphoneError.commandFailed("test").hint)
    }

    func testVphoneErrorDescription() {
        let err = VphoneError.socketNotFound("/tmp/test.sock")
        XCTAssertTrue(err.description.contains("/tmp/test.sock"))
    }

    // MARK: - Availability check

    func testIsAvailableReturnsFalseForMissingSocket() {
        let bridge = VphoneBridge(vmName: "nonexistent", socketPath: "/tmp/definitely-not-here-\(UUID()).sock")
        XCTAssertFalse(bridge.isAvailable())
    }

    // MARK: - Coordinate round-trip

    func testCoordinateRoundTrip() {
        let origX = 215.0
        let origY = 466.0
        let (px, py) = VphoneBridge.logicalToPixel(x: origX, y: origY)
        let (backX, backY) = VphoneBridge.pixelToLogical(px: px, py: py)
        XCTAssertEqual(backX, origX, accuracy: 0.01)
        XCTAssertEqual(backY, origY, accuracy: 0.01)
    }
}
