import XCTest
@testable import AgentSwiftLib

final class SimulatorTests: XCTestCase {

    // MARK: - Device list parsing

    func testParseDeviceListWithBootedDevice() throws {
        let json = """
        {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
                    {
                        "udid": "AAAA-BBBB-CCCC",
                        "name": "iPhone 17 Pro",
                        "state": "Booted",
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
                    },
                    {
                        "udid": "DDDD-EEEE-FFFF",
                        "name": "iPhone 16",
                        "state": "Shutdown",
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
                    }
                ],
                "com.apple.CoreSimulator.SimRuntime.watchOS-11-0": [
                    {
                        "udid": "WATCH-1111",
                        "name": "Apple Watch Series 10",
                        "state": "Shutdown",
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10"
                    }
                ]
            }
        }
        """
        let devices = try SimulatorBridge.parseDeviceList(json.data(using: .utf8)!)
        XCTAssertEqual(devices.count, 2)
        let booted = devices.filter { $0.isBooted }
        XCTAssertEqual(booted.count, 1)
        XCTAssertEqual(booted.first?.udid, "AAAA-BBBB-CCCC")
        XCTAssertEqual(booted.first?.name, "iPhone 17 Pro")
    }

    func testParseDeviceListEmpty() throws {
        let json = """
        {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-0": []
            }
        }
        """
        let devices = try SimulatorBridge.parseDeviceList(json.data(using: .utf8)!)
        XCTAssertEqual(devices.count, 0)
    }

    func testParseDeviceListNoBootedDevices() throws {
        let json = """
        {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
                    {
                        "udid": "1111-2222-3333",
                        "name": "iPhone 16 Pro Max",
                        "state": "Shutdown",
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
                    }
                ]
            }
        }
        """
        let devices = try SimulatorBridge.parseDeviceList(json.data(using: .utf8)!)
        XCTAssertEqual(devices.count, 1)
        XCTAssertFalse(devices[0].isBooted)
    }

    // MARK: - Coordinate mapping

    func testIosPointToScreenOrigin() {
        let winInfo = SimWindowInfo(
            windowOrigin: CGPoint(x: 100, y: 200),
            contentSize: CGSize(width: 196.5, height: 426),
            deviceSize: CGSize(width: 393, height: 852)
        )
        let screenPoint = SimulatorBridge.iosPointToScreen(CGPoint(x: 0, y: 0), windowInfo: winInfo)
        XCTAssertEqual(screenPoint.x, 100.0, accuracy: 0.01)
        XCTAssertEqual(screenPoint.y, 200.0, accuracy: 0.01)
    }

    func testIosPointToScreenBottomRight() {
        let winInfo = SimWindowInfo(
            windowOrigin: CGPoint(x: 100, y: 200),
            contentSize: CGSize(width: 196.5, height: 426),
            deviceSize: CGSize(width: 393, height: 852)
        )
        let screenPoint = SimulatorBridge.iosPointToScreen(CGPoint(x: 393, y: 852), windowInfo: winInfo)
        XCTAssertEqual(screenPoint.x, 296.5, accuracy: 0.01)
        XCTAssertEqual(screenPoint.y, 626.0, accuracy: 0.01)
    }

    func testIosPointToScreenWithSmallScale() {
        let winInfo = SimWindowInfo(
            windowOrigin: CGPoint(x: 50, y: 100),
            contentSize: CGSize(width: 131, height: 284),
            deviceSize: CGSize(width: 393, height: 852)
        )
        XCTAssertEqual(winInfo.scale, 131.0 / 393.0, accuracy: 0.0001)

        let screenPoint = SimulatorBridge.iosPointToScreen(CGPoint(x: 196.5, y: 426), windowInfo: winInfo)
        let expectedX = 50.0 + 196.5 * (131.0 / 393.0)
        let expectedY = 100.0 + 426.0 * (131.0 / 393.0)
        XCTAssertEqual(screenPoint.x, expectedX, accuracy: 0.01)
        XCTAssertEqual(screenPoint.y, expectedY, accuracy: 0.01)
    }

    // MARK: - SimWindowInfo scale

    func testSimWindowInfoScale() {
        let winInfo = SimWindowInfo(
            windowOrigin: CGPoint(x: 0, y: 0),
            contentSize: CGSize(width: 393, height: 852),
            deviceSize: CGSize(width: 393, height: 852)
        )
        XCTAssertEqual(winInfo.scale, 1.0, accuracy: 0.0001)
    }

    func testSimWindowInfoHalfScale() {
        let winInfo = SimWindowInfo(
            windowOrigin: CGPoint(x: 0, y: 0),
            contentSize: CGSize(width: 196.5, height: 426),
            deviceSize: CGSize(width: 393, height: 852)
        )
        XCTAssertEqual(winInfo.scale, 0.5, accuracy: 0.0001)
    }

    // MARK: - Session backwards compat

    func testSessionWithSimulatorFields() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(path: tempDir.appendingPathComponent("session.json"))

        var session = SessionData.empty
        session.simulatorUDID = "AAAA-BBBB-CCCC"
        session.simulatorDeviceType = "iPhone 17 Pro"
        session.connectedAt = "2026-08-24T00:00:00Z"

        try store.save(session)
        let loaded = store.load()

        XCTAssertTrue(loaded.isConnected)
        XCTAssertTrue(loaded.isSimulatorMode)
        XCTAssertEqual(loaded.simulatorUDID, "AAAA-BBBB-CCCC")
        XCTAssertEqual(loaded.simulatorDeviceType, "iPhone 17 Pro")
    }

    func testSessionWithoutSimulatorFields() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(path: tempDir.appendingPathComponent("session.json"))

        // Old-style session without simulator fields
        let json = """
        {
            "pid": 12345,
            "bundleId": "com.test.app",
            "connectedAt": "2026-01-01T00:00:00Z",
            "refs": {}
        }
        """
        try json.data(using: .utf8)!.write(to: tempDir.appendingPathComponent("session.json"))
        let loaded = store.load()

        XCTAssertTrue(loaded.isConnected)
        XCTAssertFalse(loaded.isSimulatorMode)
        XCTAssertNil(loaded.simulatorUDID)
        XCTAssertEqual(loaded.pid, 12345)
    }

    // MARK: - SimDeviceInfo

    func testSimDeviceInfoShortName() {
        let device = SimDeviceInfo(
            udid: "AAAA",
            name: "iPhone 17 Pro",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
            state: "Booted"
        )
        XCTAssertEqual(device.shortName, "iPhone 17 Pro")
        XCTAssertTrue(device.isBooted)
    }

    func testSimDeviceInfoShutdown() {
        let device = SimDeviceInfo(
            udid: "BBBB",
            name: "iPhone 16",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-16",
            state: "Shutdown"
        )
        XCTAssertFalse(device.isBooted)
    }

    // MARK: - Screen size parsing

    func testParseScreenSizeFromEnumerateOutput() {
        let bridge = SimulatorBridge(udid: "test")
        let output = """
        Port 0 (UUID: abc-123):
          Type: display
          Display Class: main
          Width: 1179, Height: 2556
        """
        let size = bridge.parseScreenSize(from: output)
        XCTAssertNotNil(size)
        XCTAssertEqual(size!.width, 393, accuracy: 0.1)
        XCTAssertEqual(size!.height, 852, accuracy: 0.1)
    }

    func testDefaultDeviceSize() {
        let bridge = SimulatorBridge(udid: "test")
        let size = bridge.defaultDeviceSize()
        XCTAssertEqual(size.width, 393)
        XCTAssertEqual(size.height, 852)
    }

    // MARK: - CGEvent coordinate mapping (direction to swipe)

    func testDirectionToSwipeCoordsUp() {
        let coords = SimulatorBridge.directionToSwipeCoords(direction: "up")
        XCTAssertEqual(coords.fromX, coords.toX, accuracy: 0.01)
        XCTAssertGreaterThan(coords.fromY, coords.toY)
    }

    func testDirectionToSwipeCoordsDown() {
        let coords = SimulatorBridge.directionToSwipeCoords(direction: "down")
        XCTAssertEqual(coords.fromX, coords.toX, accuracy: 0.01)
        XCTAssertLessThan(coords.fromY, coords.toY)
    }

    func testDirectionToSwipeCoordsLeft() {
        let coords = SimulatorBridge.directionToSwipeCoords(direction: "left")
        XCTAssertEqual(coords.fromY, coords.toY, accuracy: 0.01)
        XCTAssertGreaterThan(coords.fromX, coords.toX)
    }

    func testDirectionToSwipeCoordsRight() {
        let coords = SimulatorBridge.directionToSwipeCoords(direction: "right")
        XCTAssertEqual(coords.fromY, coords.toY, accuracy: 0.01)
        XCTAssertLessThan(coords.fromX, coords.toX)
    }

    func testDirectionToSwipeCoordsCustomSize() {
        let coords = SimulatorBridge.directionToSwipeCoords(direction: "up", screenWidth: 430, screenHeight: 932)
        XCTAssertEqual(coords.fromX, 215, accuracy: 0.01)
        XCTAssertEqual(coords.toX, 215, accuracy: 0.01)
        let swipeDistance = 932 * 0.4
        XCTAssertEqual(coords.fromY - coords.toY, swipeDistance, accuracy: 0.01)
    }

    func testDirectionToSwipeCoordsDefaultDirection() {
        let coords = SimulatorBridge.directionToSwipeCoords(direction: "unknown")
        let upCoords = SimulatorBridge.directionToSwipeCoords(direction: "up")
        XCTAssertEqual(coords.fromX, upCoords.fromX, accuracy: 0.01)
        XCTAssertEqual(coords.fromY, upCoords.fromY, accuracy: 0.01)
    }

    // MARK: - CGEvent coordinate mapping for tap

    func testIosPointToScreenCenter() {
        let winInfo = SimWindowInfo(
            windowOrigin: CGPoint(x: 100, y: 200),
            contentSize: CGSize(width: 393, height: 852),
            deviceSize: CGSize(width: 393, height: 852)
        )
        let screenPoint = SimulatorBridge.iosPointToScreen(CGPoint(x: 196.5, y: 426), windowInfo: winInfo)
        XCTAssertEqual(screenPoint.x, 296.5, accuracy: 0.01)
        XCTAssertEqual(screenPoint.y, 626.0, accuracy: 0.01)
    }

    func testIosPointToScreenWithDoubleScale() {
        let winInfo = SimWindowInfo(
            windowOrigin: CGPoint(x: 0, y: 0),
            contentSize: CGSize(width: 786, height: 1704),
            deviceSize: CGSize(width: 393, height: 852)
        )
        XCTAssertEqual(winInfo.scale, 2.0, accuracy: 0.0001)
        let screenPoint = SimulatorBridge.iosPointToScreen(CGPoint(x: 100, y: 200), windowInfo: winInfo)
        XCTAssertEqual(screenPoint.x, 200.0, accuracy: 0.01)
        XCTAssertEqual(screenPoint.y, 400.0, accuracy: 0.01)
    }

    func testSimWindowInfoZeroWidthScale() {
        let winInfo = SimWindowInfo(
            windowOrigin: CGPoint(x: 0, y: 0),
            contentSize: CGSize(width: 393, height: 852),
            deviceSize: CGSize(width: 0, height: 852)
        )
        XCTAssertEqual(winInfo.scale, 1.0, accuracy: 0.0001)
    }

    // MARK: - Error codes

    func testSimulatorErrorCodes() {
        XCTAssertEqual(SimulatorError.noBootedDevice.code, "SIM_NO_BOOTED")
        XCTAssertEqual(SimulatorError.deviceNotFound("x").code, "SIM_NOT_FOUND")
        XCTAssertEqual(SimulatorError.deviceNotBooted("x").code, "SIM_NOT_BOOTED")
        XCTAssertEqual(SimulatorError.simctlFailed("x").code, "SIM_SIMCTL_FAILED")
        XCTAssertEqual(SimulatorError.simulatorAppNotRunning.code, "SIM_APP_NOT_RUNNING")
        XCTAssertEqual(SimulatorError.windowNotFound.code, "SIM_WINDOW_NOT_FOUND")
        XCTAssertEqual(SimulatorError.screenshotFailed("x").code, "SIM_SCREENSHOT_FAILED")
    }

    func testSimulatorErrorHints() {
        XCTAssertNotNil(SimulatorError.noBootedDevice.hint)
        XCTAssertNotNil(SimulatorError.deviceNotFound("test-udid").hint)
        XCTAssertNotNil(SimulatorError.deviceNotBooted("test-udid").hint)
        XCTAssertNotNil(SimulatorError.simctlFailed("msg").hint)
        XCTAssertNotNil(SimulatorError.simulatorAppNotRunning.hint)
        XCTAssertNotNil(SimulatorError.windowNotFound.hint)
    }
}
