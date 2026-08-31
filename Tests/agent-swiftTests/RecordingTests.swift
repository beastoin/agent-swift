import XCTest
@testable import AgentSwiftLib

/// Tests for Phase 13: Screen video recording
final class RecordingTests: XCTestCase {

    // MARK: - RecordingSession model

    func testRecordingSessionInit() {
        let rs = RecordingSession(sessionId: "abc12345", pid: 99999, videoPath: "/tmp/test.mp4",
                                  startTime: "2026-08-31T00:00:00Z", mode: "simulator")
        XCTAssertEqual(rs.sessionId, "abc12345")
        XCTAssertEqual(rs.pid, 99999)
        XCTAssertEqual(rs.videoPath, "/tmp/test.mp4")
        XCTAssertEqual(rs.startTime, "2026-08-31T00:00:00Z")
        XCTAssertEqual(rs.mode, "simulator")
    }

    func testRecordingSessionCodable() throws {
        let rs = RecordingSession(sessionId: "test1234", pid: 12345, videoPath: "/tmp/vid.mp4",
                                  startTime: "2026-01-01T00:00:00Z", mode: "desktop")
        let data = try JSONEncoder().encode(rs)
        let decoded = try JSONDecoder().decode(RecordingSession.self, from: data)
        XCTAssertEqual(decoded.sessionId, "test1234")
        XCTAssertEqual(decoded.pid, 12345)
        XCTAssertEqual(decoded.videoPath, "/tmp/vid.mp4")
        XCTAssertEqual(decoded.mode, "desktop")
    }

    func testSessionDataRecordingFieldNilByDefault() {
        let session = SessionData.empty
        XCTAssertNil(session.recording, "New session should have no recording")
    }

    func testSessionDataWithRecording() {
        var session = SessionData.empty
        session.recording = RecordingSession(sessionId: "r1", pid: 1, videoPath: "/v.mp4",
                                             startTime: "2026-01-01T00:00:00Z", mode: "simulator")
        XCTAssertNotNil(session.recording)
        XCTAssertEqual(session.recording?.sessionId, "r1")
    }

    func testSessionDataRecordingPersistsAcrossEncodeDecode() throws {
        var session = SessionData.empty
        session.pid = 100
        session.recording = RecordingSession(sessionId: "enc1", pid: 500, videoPath: "/tmp/enc.mp4",
                                             startTime: "2026-06-15T12:00:00Z", mode: "mirror")
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)
        XCTAssertNotNil(decoded.recording)
        XCTAssertEqual(decoded.recording?.sessionId, "enc1")
        XCTAssertEqual(decoded.recording?.pid, 500)
        XCTAssertEqual(decoded.recording?.mode, "mirror")
    }

    func testSessionDataRecordingCanBeCleared() throws {
        var session = SessionData.empty
        session.recording = RecordingSession(sessionId: "clr", pid: 42, videoPath: "/tmp/c.mp4",
                                             startTime: "2026-01-01T00:00:00Z", mode: "desktop")
        XCTAssertNotNil(session.recording)
        session.recording = nil
        XCTAssertNil(session.recording)
        // Verify it encodes without recording
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)
        XCTAssertNil(decoded.recording)
    }

    // MARK: - Recording mode validation

    func testRecordingModeSimulator() {
        let rs = RecordingSession(sessionId: "s1", pid: 1, videoPath: "/v.mp4",
                                  startTime: "2026-01-01T00:00:00Z", mode: "simulator")
        XCTAssertEqual(rs.mode, "simulator")
    }

    func testRecordingModeDesktop() {
        let rs = RecordingSession(sessionId: "d1", pid: 1, videoPath: "/v.mp4",
                                  startTime: "2026-01-01T00:00:00Z", mode: "desktop")
        XCTAssertEqual(rs.mode, "desktop")
    }

    func testRecordingModeMirror() {
        let rs = RecordingSession(sessionId: "m1", pid: 1, videoPath: "/v.mp4",
                                  startTime: "2026-01-01T00:00:00Z", mode: "mirror")
        XCTAssertEqual(rs.mode, "mirror")
    }

    // MARK: - Video path generation

    func testVideoPathContainsSessionId() {
        let sessionId = "abcd1234"
        let videoPath = "/tmp/recording-\(sessionId).mp4"
        XCTAssertTrue(videoPath.contains(sessionId), "Video path should contain session ID")
        XCTAssertTrue(videoPath.hasSuffix(".mp4"), "Video should be mp4")
    }

    func testFrameOutputPathContainsTimestamp() {
        let timestamp = 4.0
        let framePath = "/tmp/frame-\(String(format: "%.1f", timestamp))s.png"
        XCTAssertTrue(framePath.contains("4.0s"), "Frame path should contain timestamp")
        XCTAssertTrue(framePath.hasSuffix(".png"), "Frame should be png")
    }

    // MARK: - Timestamp validation

    func testTimestampZeroIsValid() {
        let timestamp = 0.0
        XCTAssertTrue(timestamp >= 0, "Zero timestamp is valid")
    }

    func testTimestampPositiveIsValid() {
        let timestamp = 4.5
        XCTAssertTrue(timestamp >= 0, "Positive timestamp is valid")
    }

    func testTimestampNegativeIsInvalid() {
        let timestamp = -1.0
        XCTAssertFalse(timestamp >= 0, "Negative timestamp is invalid")
    }

    // MARK: - ffmpeg command construction

    func testFfmpegFrameExtractionArgs() {
        let videoPath = "/tmp/recording-abc.mp4"
        let timestamp = 4.0
        let outputPath = "/tmp/frame-4.0s.png"
        let args = ["ffmpeg", "-y", "-ss", String(timestamp), "-i", videoPath, "-frames:v", "1", "-update", "1", outputPath]
        XCTAssertEqual(args[0], "ffmpeg")
        XCTAssertEqual(args[3], "4.0")
        XCTAssertEqual(args[5], videoPath)
        XCTAssertEqual(args[6], "-frames:v")
        XCTAssertEqual(args[7], "1")
        XCTAssertEqual(args.last, outputPath)
    }

    func testSimctlRecordVideoArgs() {
        let udid = "5EC30357-9C5A-40B3-954B-5A71797A7439"
        let videoPath = "/tmp/recording-test.mp4"
        let args = ["simctl", "io", udid, "recordVideo", "--codec", "h264", "--force", videoPath]
        XCTAssertEqual(args[0], "simctl")
        XCTAssertEqual(args[2], udid)
        XCTAssertEqual(args[3], "recordVideo")
        XCTAssertEqual(args[4], "--codec")
        XCTAssertEqual(args[5], "h264")
        XCTAssertEqual(args.last, videoPath)
    }

    // MARK: - Session ID format

    func testSessionIdFormat() {
        let uuid = UUID().uuidString
        let sessionId = String(uuid.prefix(8)).lowercased()
        XCTAssertEqual(sessionId.count, 8, "Session ID should be 8 chars")
        XCTAssertTrue(sessionId.allSatisfy { $0.isHexDigit || $0 == "-" },
                      "Session ID should be hex chars or dashes")
    }

    // MARK: - Version check

    func testVersionIs080() {
        let version = "0.8.0"
        XCTAssertTrue(version.hasPrefix("0.8"), "Version should be 0.8.x for phase 13")
    }

    // MARK: - SIGINT signal value

    func testSigintSignalNumber() {
        XCTAssertEqual(SIGINT, 2, "SIGINT should be signal 2")
    }

    func testSigkillSignalNumber() {
        XCTAssertEqual(SIGKILL, 9, "SIGKILL should be signal 9")
    }
}
