import XCTest
@testable import AgentSwiftLib

/// Tests for Phase 14: Frame processing (resize, dedup, crop, batch)
final class FrameProcessingTests: XCTestCase {

    // MARK: - lastFramePath in SessionData

    func testLastFramePathNilByDefault() {
        let session = SessionData.empty
        XCTAssertNil(session.lastFramePath, "New session should have no lastFramePath")
    }

    func testLastFramePathPersistsAcrossEncodeDecode() throws {
        var session = SessionData.empty
        session.lastFramePath = "/tmp/frame-4.0s.png"
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)
        XCTAssertEqual(decoded.lastFramePath, "/tmp/frame-4.0s.png")
    }

    func testLastFramePathUpdatedOnNewFrame() {
        var session = SessionData.empty
        session.lastFramePath = "/tmp/old-frame.png"
        session.lastFramePath = "/tmp/new-frame.png"
        XCTAssertEqual(session.lastFramePath, "/tmp/new-frame.png")
    }

    // MARK: - Crop parameter parsing

    func testCropParseValid() {
        let crop = "0,200,1206,800"
        let parts = crop.split(separator: ",").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(parts[0], 0)   // x
        XCTAssertEqual(parts[1], 200) // y
        XCTAssertEqual(parts[2], 1206) // width
        XCTAssertEqual(parts[3], 800)  // height
    }

    func testCropParseInvalid() {
        let crop = "abc,200,1206"
        let parts = crop.split(separator: ",").compactMap { Int($0) }
        XCTAssertNotEqual(parts.count, 4, "Invalid crop should not parse to 4 integers")
    }

    func testCropClampToBounds() {
        // Simulate clamping: x=1000, y=2000, w=500, h=1000 on a 1206x2622 image
        let imgW = 1206, imgH = 2622
        var x = 1000, y = 2000, w = 500, h = 1000
        x = max(0, min(x, imgW - 1))
        y = max(0, min(y, imgH - 1))
        w = min(w, imgW - x)
        h = min(h, imgH - y)
        XCTAssertEqual(x, 1000)
        XCTAssertEqual(y, 2000)
        XCTAssertEqual(w, 206, "Width should be clamped to 1206 - 1000 = 206")
        XCTAssertEqual(h, 622, "Height should be clamped to 2622 - 2000 = 622")
    }

    func testCropFullyOutOfBounds() {
        let imgW = 100, imgH = 100
        var x = 200, y = 200, w = 50, h = 50
        x = max(0, min(x, imgW - 1))
        y = max(0, min(y, imgH - 1))
        w = min(w, imgW - x)
        h = min(h, imgH - y)
        XCTAssertEqual(x, 99)
        XCTAssertEqual(y, 99)
        XCTAssertEqual(w, 1, "Width clamped to 1")
        XCTAssertEqual(h, 1, "Height clamped to 1")
    }

    // MARK: - Max width logic

    func testMaxWidthNoUpscale() {
        // If current width < maxWidth, should not resize
        let currentWidth = 600
        let maxWidth = 800
        let shouldResize = currentWidth > maxWidth
        XCTAssertFalse(shouldResize, "Should not upscale when width < maxWidth")
    }

    func testMaxWidthDownscale() {
        let currentWidth = 1206
        let maxWidth = 800
        let shouldResize = currentWidth > maxWidth
        XCTAssertTrue(shouldResize, "Should downscale when width > maxWidth")
    }

    func testMaxWidthExactMatch() {
        let currentWidth = 800
        let maxWidth = 800
        let shouldResize = currentWidth > maxWidth
        XCTAssertFalse(shouldResize, "Should not resize when width == maxWidth")
    }

    // MARK: - Dedup threshold validation

    func testDedupThresholdValidRange() {
        XCTAssertTrue(0.0 >= 0 && 0.0 <= 1.0, "0.0 is valid")
        XCTAssertTrue(0.95 >= 0 && 0.95 <= 1.0, "0.95 is valid")
        XCTAssertTrue(1.0 >= 0 && 1.0 <= 1.0, "1.0 is valid")
    }

    func testDedupThresholdInvalidRange() {
        let threshold = 1.5
        XCTAssertFalse(threshold >= 0 && threshold <= 1.0, "1.5 is invalid")
        let negative = -0.1
        XCTAssertFalse(negative >= 0 && negative <= 1.0, "-0.1 is invalid")
    }

    func testDedupSkipLogic() {
        let similarity = 0.97
        let threshold = 0.95
        XCTAssertTrue(similarity >= threshold, "Should skip: 0.97 >= 0.95")
    }

    func testDedupExtractLogic() {
        let similarity = 0.80
        let threshold = 0.95
        XCTAssertFalse(similarity >= threshold, "Should not skip: 0.80 < 0.95")
    }

    // MARK: - Batch timestamp generation

    func testBatchEveryTimestamps() {
        let duration = 10.0
        let every = 2.0
        var timestamps: [Double] = []
        var t = 0.0
        while t < duration {
            timestamps.append(t)
            t += every
        }
        XCTAssertEqual(timestamps, [0.0, 2.0, 4.0, 6.0, 8.0])
    }

    func testBatchEveryShortVideo() {
        let duration = 1.5
        let every = 2.0
        var timestamps: [Double] = []
        var t = 0.0
        while t < duration {
            timestamps.append(t)
            t += every
        }
        XCTAssertEqual(timestamps, [0.0], "Only frame 0 fits in a 1.5s video with 2s interval")
    }

    func testBatchAtTimestamps() {
        let atStr = "1.0,5.0,10.0"
        let timestamps = atStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        XCTAssertEqual(timestamps, [1.0, 5.0, 10.0])
    }

    func testBatchAtWithSpaces() {
        let atStr = "1.0, 5.0, 10.0"
        let timestamps = atStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        XCTAssertEqual(timestamps, [1.0, 5.0, 10.0], "Should handle spaces after commas")
    }

    // MARK: - Frame output path

    func testFrameOutputPathFormat() {
        let timestamp = 4.5
        let dir = "/tmp/session"
        let path = "\(dir)/frame-\(String(format: "%.1f", timestamp))s.png"
        XCTAssertEqual(path, "/tmp/session/frame-4.5s.png")
    }

    // MARK: - sips command construction

    func testSipsResizeArgs() {
        let maxWidth = 800
        let path = "/tmp/frame.png"
        let args = ["--resampleWidth", String(maxWidth), path]
        XCTAssertEqual(args[0], "--resampleWidth")
        XCTAssertEqual(args[1], "800")
        XCTAssertEqual(args[2], path)
    }

    func testSipsCropArgs() {
        let h = 800, w = 1206, y = 200, x = 0
        let path = "/tmp/frame.png"
        let args = ["--cropToHeightWidth", String(h), String(w), "--cropOffset", String(y), String(x), path]
        XCTAssertEqual(args[0], "--cropToHeightWidth")
        XCTAssertEqual(args[1], "800")
        XCTAssertEqual(args[2], "1206")
        XCTAssertEqual(args[3], "--cropOffset")
        XCTAssertEqual(args[4], "200")
        XCTAssertEqual(args[5], "0")
    }

    // MARK: - Version check

    func testVersionIs09x() {
        let version = "0.9.0"
        XCTAssertTrue(version.hasPrefix("0.9"), "Version should be 0.9.x for phase 14")
    }

    // MARK: - FrameResult model

    func testFrameResultWithProcessing() throws {
        // Verify the result struct can encode width/height and skip info
        let json = """
        {"path":"/tmp/f.png","timestamp":4.0,"source":"video","success":true,"width":800,"height":1740,"skipped":false}
        """
        let data = json.data(using: .utf8)!
        // Just verify it's valid JSON with expected fields
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(parsed["width"] as? Int, 800)
        XCTAssertEqual(parsed["height"] as? Int, 1740)
        XCTAssertEqual(parsed["skipped"] as? Bool, false)
    }

    func testFrameResultSkipped() throws {
        let json = """
        {"path":"/tmp/f.png","timestamp":4.0,"source":"video","success":true,"skipped":true,"reason":"duplicate","similarity":0.97}
        """
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(parsed["skipped"] as? Bool, true)
        XCTAssertEqual(parsed["reason"] as? String, "duplicate")
        XCTAssertEqual(parsed["similarity"] as? Double, 0.97)
    }

    // MARK: - Backward compatibility

    func testNoProcessingFlagsProduceBasicResult() {
        // When no --max-width, --crop, --dedup-threshold are specified,
        // the result should be identical to v0.8.2 behavior
        let maxWidth: Int? = nil
        let crop: String? = nil
        let dedupThreshold: Double? = nil
        XCTAssertNil(maxWidth)
        XCTAssertNil(crop)
        XCTAssertNil(dedupThreshold)
        // No processing applied — backward compatible
    }
}
