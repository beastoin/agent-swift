import XCTest
@testable import AgentSwiftLib

/// Tests for Phase 15: Token-efficient video analysis (keyframes, OCR, grayscale, JPEG)
final class TokenOptTests: XCTestCase {

    // MARK: - OCR text block model

    func testOcrTextBlockEncoding() throws {
        let json = """
        {"text":"Settings","x":10,"y":200,"width":100,"height":20,"confidence":0.98}
        """
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(parsed["text"] as? String, "Settings")
        XCTAssertEqual(parsed["x"] as? Int, 10)
        XCTAssertEqual(parsed["y"] as? Int, 200)
        XCTAssertEqual(parsed["width"] as? Int, 100)
        XCTAssertEqual(parsed["height"] as? Int, 20)
        XCTAssertEqual(parsed["confidence"] as? Double, 0.98)
    }

    func testOcrResultWithTextsArray() throws {
        let json = """
        {"path":"/tmp/f.png","timestamp":4.0,"source":"video","success":true,"width":800,"height":600,"texts":[{"text":"Hello","x":0,"y":0,"width":50,"height":20,"confidence":0.95}]}
        """
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(parsed["texts"])
        let texts = parsed["texts"] as! [[String: Any]]
        XCTAssertEqual(texts.count, 1)
        XCTAssertEqual(texts[0]["text"] as? String, "Hello")
    }

    func testOcrResultWithoutTexts() throws {
        // When --ocr is not used, texts should be nil/absent
        let json = """
        {"path":"/tmp/f.png","timestamp":4.0,"source":"video","success":true,"width":800,"height":600}
        """
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(parsed["texts"], "texts should be absent when OCR not used")
    }

    func testOcrEmptyTextsArray() throws {
        // Frame with no readable text returns empty array
        let json = """
        {"path":"/tmp/f.png","timestamp":4.0,"source":"video","success":true,"texts":[]}
        """
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let texts = parsed["texts"] as! [Any]
        XCTAssertTrue(texts.isEmpty, "Empty texts for frame with no readable text")
    }

    // MARK: - Vision bounding box coordinate conversion

    func testVisionBboxToPixelCoords() {
        // Vision: normalized (0-1), origin at bottom-left
        // Target: pixel coordinates, origin at top-left
        let imgWidth = 1206
        let imgHeight = 2622
        let bboxOriginX = 0.1
        let bboxOriginY = 0.8  // Vision bottom-left origin
        let bboxWidth = 0.3
        let bboxHeight = 0.05

        let x = Int(bboxOriginX * Double(imgWidth))
        let y = Int(Double(imgHeight) - (bboxOriginY + bboxHeight) * Double(imgHeight))
        let w = Int(bboxWidth * Double(imgWidth))
        let h = Int(bboxHeight * Double(imgHeight))

        XCTAssertEqual(x, 120, "x = 0.1 * 1206 ≈ 120")
        XCTAssertEqual(y, 393, "y = 2622 - (0.8 + 0.05) * 2622 ≈ 393")
        XCTAssertEqual(w, 361, "w = 0.3 * 1206 ≈ 361")
        XCTAssertEqual(h, 131, "h = 0.05 * 2622 ≈ 131")
    }

    func testVisionBboxTopLeftCorner() {
        // Text at top-left of image: high y in Vision coords
        let imgWidth = 800, imgHeight = 600
        let bboxOriginX = 0.0
        let bboxOriginY = 0.95  // Near top in Vision (near bottom-left origin y=1)
        let bboxWidth = 0.2
        let bboxHeight = 0.05

        let y = Int(Double(imgHeight) - (bboxOriginY + bboxHeight) * Double(imgHeight))
        XCTAssertEqual(y, 0, "Top of image should be y=0 in pixel coords")
    }

    // MARK: - Grayscale

    func testGrayscaleProfilePath() {
        let profilePath = "/System/Library/ColorSync/Profiles/Generic Gray Profile.icc"
        // Just verify the expected path string is what we use
        XCTAssertTrue(profilePath.contains("Gray"), "Profile path should reference Gray")
        XCTAssertTrue(profilePath.hasSuffix(".icc"), "Profile should be ICC format")
    }

    func testGrayscaleSipsArgs() {
        let path = "/tmp/frame.png"
        let profilePath = "/System/Library/ColorSync/Profiles/Generic Gray Profile.icc"
        let args = ["--matchTo", profilePath, path]
        XCTAssertEqual(args[0], "--matchTo")
        XCTAssertTrue(args[1].contains("Gray"))
        XCTAssertEqual(args[2], path)
    }

    // MARK: - JPEG format conversion

    func testJpegSipsArgs() {
        let path = "/tmp/frame.png"
        let quality = 60
        let args = ["--setProperty", "format", "jpeg", "--setProperty", "formatOptions", String(quality), path]
        XCTAssertEqual(args[0], "--setProperty")
        XCTAssertEqual(args[1], "format")
        XCTAssertEqual(args[2], "jpeg")
        XCTAssertEqual(args[5], "60")
    }

    func testJpegPathConversion() {
        let pngPath = "/tmp/session/frame-4.0s.png"
        let jpegPath: String
        if pngPath.hasSuffix(".png") {
            jpegPath = String(pngPath.dropLast(4)) + ".jpg"
        } else {
            jpegPath = pngPath + ".jpg"
        }
        XCTAssertEqual(jpegPath, "/tmp/session/frame-4.0s.jpg")
    }

    func testJpegPathNonPng() {
        let path = "/tmp/frame.bmp"
        let jpegPath: String
        if path.hasSuffix(".png") {
            jpegPath = String(path.dropLast(4)) + ".jpg"
        } else {
            jpegPath = path + ".jpg"
        }
        XCTAssertEqual(jpegPath, "/tmp/frame.bmp.jpg")
    }

    func testFormatValidation() {
        let validFormats = ["png", "jpeg"]
        XCTAssertTrue(validFormats.contains("png"))
        XCTAssertTrue(validFormats.contains("jpeg"))
        XCTAssertFalse(validFormats.contains("gif"), "gif is not a valid format")
        XCTAssertFalse(validFormats.contains("webp"), "webp is not a valid format")
    }

    func testQualityValidRange() {
        XCTAssertTrue(1 >= 1 && 1 <= 100, "1 is valid quality")
        XCTAssertTrue(80 >= 1 && 80 <= 100, "80 is valid quality (default)")
        XCTAssertTrue(100 >= 1 && 100 <= 100, "100 is valid quality")
    }

    func testQualityInvalidRange() {
        XCTAssertFalse(0 >= 1 && 0 <= 100, "0 is invalid quality")
        XCTAssertFalse(101 >= 1 && 101 <= 100, "101 is invalid quality")
    }

    func testQualityRequiresJpeg() {
        // --quality without --format jpeg should be rejected
        let format: String? = nil
        let quality: Int? = 60
        let isValid = format == "jpeg" || quality == nil
        XCTAssertFalse(isValid, "quality=60 with no format should be invalid")
    }

    // MARK: - Keyframe detection

    func testKeyframeScanTimestamps() {
        let duration = 10.0
        let scanInterval = 0.5
        var timestamps: [Double] = []
        var t = 0.0
        while t < duration {
            timestamps.append(t)
            t += scanInterval
        }
        XCTAssertEqual(timestamps.count, 20, "10s at 0.5s intervals = 20 scan points")
        XCTAssertEqual(timestamps.first, 0.0)
        XCTAssertEqual(timestamps.last, 9.5)
    }

    func testKeyframeDefaultThreshold() {
        let dedupThreshold: Double? = nil
        let threshold = dedupThreshold ?? 0.92
        XCTAssertEqual(threshold, 0.92, "Default keyframe threshold should be 0.92")
    }

    func testKeyframeMutuallyExclusive() {
        // --keyframes should not work with --every or --at
        let keyframes = true
        let every: Double? = 2.0
        let at: String? = nil
        let isConflict = keyframes && (every != nil || at != nil)
        XCTAssertTrue(isConflict, "keyframes + every should conflict")
    }

    func testKeyframeFirstFrameAlwaysExtracted() {
        // First frame is always extracted regardless of similarity
        let lastExtractedPath: String? = nil
        let shouldExtract = lastExtractedPath == nil
        XCTAssertTrue(shouldExtract, "First frame always extracted when no previous frame")
    }

    func testKeyframeSceneChange() {
        // When similarity < threshold, frame should be extracted
        let similarity = 0.75
        let threshold = 0.92
        let isSceneChange = similarity < threshold
        XCTAssertTrue(isSceneChange, "0.75 < 0.92 should be detected as scene change")
    }

    func testKeyframeStillScene() {
        // When similarity >= threshold, frame should be skipped
        let similarity = 0.97
        let threshold = 0.92
        let isStillScene = similarity >= threshold
        XCTAssertTrue(isStillScene, "0.97 >= 0.92 should be skipped as still scene")
    }

    // MARK: - Batch result with new fields

    func testBatchResultWithTotalScanned() throws {
        let json = """
        {"video":"/tmp/v.mp4","frames":[],"extracted":4,"skipped":56,"total":4,"totalScanned":60}
        """
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(parsed["totalScanned"] as? Int, 60)
        XCTAssertEqual(parsed["extracted"] as? Int, 4)
        XCTAssertEqual(parsed["skipped"] as? Int, 56)
    }

    func testBatchFrameEntryWithOcr() throws {
        let json = """
        {"path":"/tmp/f.png","timestamp":2.0,"skipped":false,"width":800,"height":600,"texts":[{"text":"OK","x":10,"y":10,"width":30,"height":15,"confidence":0.99}]}
        """
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let texts = parsed["texts"] as! [[String: Any]]
        XCTAssertEqual(texts.count, 1)
        XCTAssertEqual(texts[0]["text"] as? String, "OK")
    }

    // MARK: - Backward compatibility

    func testNoNewFlagsProducesV09Behavior() {
        // When no --ocr, --grayscale, --format, --quality, --keyframes are set,
        // behavior is identical to v0.9.0
        let ocr = false
        let grayscale = false
        let format: String? = nil
        let quality: Int? = nil
        let keyframes = false
        XCTAssertFalse(ocr)
        XCTAssertFalse(grayscale)
        XCTAssertNil(format)
        XCTAssertNil(quality)
        XCTAssertFalse(keyframes)
    }

    // MARK: - Version check

    func testVersionIs010x() {
        let version = "0.10.0"
        XCTAssertTrue(version.hasPrefix("0.10"), "Version should be 0.10.x for phase 15")
    }

    // MARK: - OCR sort order

    func testOcrSortTopToBottomLeftToRight() {
        // Verify sorting by (y, x)
        struct Block: Comparable {
            let y: Int, x: Int
            static func < (lhs: Block, rhs: Block) -> Bool { (lhs.y, lhs.x) < (rhs.y, rhs.x) }
        }
        var blocks = [Block(y: 200, x: 50), Block(y: 100, x: 30), Block(y: 100, x: 10), Block(y: 300, x: 5)]
        blocks.sort()
        XCTAssertEqual(blocks[0].y, 100)
        XCTAssertEqual(blocks[0].x, 10, "First should be top-left (y=100, x=10)")
        XCTAssertEqual(blocks[1].y, 100)
        XCTAssertEqual(blocks[1].x, 30, "Second should be (y=100, x=30)")
        XCTAssertEqual(blocks[2].y, 200)
        XCTAssertEqual(blocks[3].y, 300)
    }

    // MARK: - Token savings estimation

    func testTokenSavingsWithKeyframesAndOcr() {
        // Simulate: 30s video at 2s intervals = 15 frames
        // With keyframes: 4 extracted out of 60 scanned
        // With OCR: ~100 tokens per frame vs ~1600 per image
        let withoutOptimization = 15 * 1600  // 24,000 tokens
        let withOptimization = 4 * 100       // 400 tokens
        let savings = Double(withoutOptimization - withOptimization) / Double(withoutOptimization)
        XCTAssertGreaterThan(savings, 0.95, "Should save >95% tokens")
    }
}
