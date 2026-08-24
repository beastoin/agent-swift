import XCTest
@testable import AgentSwiftLib

final class MirrorTests: XCTestCase {

    // MARK: - MirrorWindowInfo

    func testMirrorWindowInfoScale() {
        let info = MirrorWindowInfo(
            windowOrigin: CGPoint(x: 100, y: 50),
            contentOrigin: CGPoint(x: 100, y: 78),
            contentSize: CGSize(width: 393, height: 852),
            iosScreenSize: CGSize(width: 393, height: 852)
        )
        XCTAssertEqual(info.scale, 1.0)
    }

    func testMirrorWindowInfoScaleHalf() {
        let info = MirrorWindowInfo(
            windowOrigin: CGPoint(x: 0, y: 0),
            contentOrigin: CGPoint(x: 0, y: 28),
            contentSize: CGSize(width: 196.5, height: 426),
            iosScreenSize: CGSize(width: 393, height: 852)
        )
        XCTAssertEqual(info.scale, 0.5, accuracy: 0.001)
    }

    func testMirrorWindowInfoScaleDouble() {
        let info = MirrorWindowInfo(
            windowOrigin: CGPoint(x: 0, y: 0),
            contentOrigin: CGPoint(x: 0, y: 28),
            contentSize: CGSize(width: 786, height: 1704),
            iosScreenSize: CGSize(width: 393, height: 852)
        )
        XCTAssertEqual(info.scale, 2.0, accuracy: 0.001)
    }

    func testMirrorWindowInfoZeroWidth() {
        let info = MirrorWindowInfo(
            windowOrigin: .zero,
            contentOrigin: .zero,
            contentSize: CGSize(width: 0, height: 0),
            iosScreenSize: CGSize(width: 0, height: 0)
        )
        XCTAssertEqual(info.scale, 1.0)
    }

    // MARK: - Coordinate mapping

    func testIosPointToScreenAtOrigin() {
        let info = MirrorWindowInfo(
            windowOrigin: CGPoint(x: 200, y: 100),
            contentOrigin: CGPoint(x: 200, y: 128),
            contentSize: CGSize(width: 393, height: 852),
            iosScreenSize: CGSize(width: 393, height: 852)
        )
        let result = MirrorBridge.iosPointToScreen(CGPoint(x: 0, y: 0), windowInfo: info)
        XCTAssertEqual(result.x, 200, accuracy: 0.001)
        XCTAssertEqual(result.y, 128, accuracy: 0.001)
    }

    func testIosPointToScreenCenter() {
        let info = MirrorWindowInfo(
            windowOrigin: CGPoint(x: 100, y: 50),
            contentOrigin: CGPoint(x: 100, y: 78),
            contentSize: CGSize(width: 393, height: 852),
            iosScreenSize: CGSize(width: 393, height: 852)
        )
        let result = MirrorBridge.iosPointToScreen(CGPoint(x: 196.5, y: 426), windowInfo: info)
        XCTAssertEqual(result.x, 296.5, accuracy: 0.001)
        XCTAssertEqual(result.y, 504, accuracy: 0.001)
    }

    func testIosPointToScreenWithScale() {
        let info = MirrorWindowInfo(
            windowOrigin: CGPoint(x: 50, y: 30),
            contentOrigin: CGPoint(x: 50, y: 58),
            contentSize: CGSize(width: 196.5, height: 426),
            iosScreenSize: CGSize(width: 393, height: 852)
        )
        let result = MirrorBridge.iosPointToScreen(CGPoint(x: 100, y: 200), windowInfo: info)
        XCTAssertEqual(result.x, 50 + 100 * 0.5, accuracy: 0.001)
        XCTAssertEqual(result.y, 58 + 200 * 0.5, accuracy: 0.001)
    }

    func testIosPointToScreenBottomRight() {
        let info = MirrorWindowInfo(
            windowOrigin: CGPoint(x: 0, y: 0),
            contentOrigin: CGPoint(x: 0, y: 28),
            contentSize: CGSize(width: 393, height: 852),
            iosScreenSize: CGSize(width: 393, height: 852)
        )
        let result = MirrorBridge.iosPointToScreen(CGPoint(x: 393, y: 852), windowInfo: info)
        XCTAssertEqual(result.x, 393, accuracy: 0.001)
        XCTAssertEqual(result.y, 880, accuracy: 0.001)
    }

    // MARK: - Direction swipe coords

    func testDirectionToSwipeCoordsUp() {
        let coords = MirrorBridge.directionToSwipeCoords(direction: "up")
        XCTAssertEqual(coords.fromX, coords.toX, accuracy: 0.001)
        XCTAssertGreaterThan(coords.fromY, coords.toY)
    }

    func testDirectionToSwipeCoordsDown() {
        let coords = MirrorBridge.directionToSwipeCoords(direction: "down")
        XCTAssertEqual(coords.fromX, coords.toX, accuracy: 0.001)
        XCTAssertLessThan(coords.fromY, coords.toY)
    }

    func testDirectionToSwipeCoordsLeft() {
        let coords = MirrorBridge.directionToSwipeCoords(direction: "left")
        XCTAssertEqual(coords.fromY, coords.toY, accuracy: 0.001)
        XCTAssertGreaterThan(coords.fromX, coords.toX)
    }

    func testDirectionToSwipeCoordsRight() {
        let coords = MirrorBridge.directionToSwipeCoords(direction: "right")
        XCTAssertEqual(coords.fromY, coords.toY, accuracy: 0.001)
        XCTAssertLessThan(coords.fromX, coords.toX)
    }

    func testDirectionToSwipeCoordsCustomSize() {
        let coords = MirrorBridge.directionToSwipeCoords(direction: "up", screenWidth: 430, screenHeight: 932)
        XCTAssertEqual(coords.fromX, 215, accuracy: 0.001)
        XCTAssertEqual(coords.toX, 215, accuracy: 0.001)
    }

    // MARK: - Error codes

    func testMirrorErrorCodes() {
        XCTAssertEqual(MirrorError.notRunning.code, "MIRROR_NOT_RUNNING")
        XCTAssertEqual(MirrorError.windowNotFound.code, "MIRROR_WINDOW_NOT_FOUND")
        XCTAssertEqual(MirrorError.clickFailed("test").code, "MIRROR_CLICK_FAILED")
        XCTAssertEqual(MirrorError.screenshotFailed("test").code, "MIRROR_SCREENSHOT_FAILED")
        XCTAssertEqual(MirrorError.swipeFailed("test").code, "MIRROR_SWIPE_FAILED")
    }

    func testMirrorErrorHints() {
        XCTAssertNotNil(MirrorError.notRunning.hint)
        XCTAssertNotNil(MirrorError.windowNotFound.hint)
        XCTAssertNotNil(MirrorError.clickFailed("x").hint)
        XCTAssertNotNil(MirrorError.screenshotFailed("x").hint)
        XCTAssertNotNil(MirrorError.swipeFailed("x").hint)
    }

    func testMirrorErrorDescriptions() {
        XCTAssertTrue(MirrorError.notRunning.description.contains("not running"))
        XCTAssertTrue(MirrorError.windowNotFound.description.contains("window"))
        XCTAssertTrue(MirrorError.clickFailed("detail").description.contains("detail"))
        XCTAssertTrue(MirrorError.screenshotFailed("detail").description.contains("detail"))
        XCTAssertTrue(MirrorError.swipeFailed("detail").description.contains("detail"))
    }

    // MARK: - MirrorBridge constants

    func testBundleId() {
        XCTAssertEqual(MirrorBridge.bundleId, "com.apple.ScreenContinuity")
    }

    func testDefaultIosSize() {
        XCTAssertEqual(MirrorBridge.defaultIosSize.width, 393)
        XCTAssertEqual(MirrorBridge.defaultIosSize.height, 852)
    }
}
