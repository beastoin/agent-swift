import XCTest
@testable import AgentSwiftLib

final class QADiagnosticsTests: XCTestCase {

    // MARK: - Doctor Check model

    func testDoctorCheckCodable() throws {
        struct Check: Codable {
            let name: String
            let status: String
            let message: String
            var fix: String?
        }

        let check = Check(name: "accessibility", status: "pass", message: "Accessibility access granted", fix: nil)
        let data = try JSONEncoder().encode(check)
        let decoded = try JSONDecoder().decode(Check.self, from: data)

        XCTAssertEqual(decoded.name, "accessibility")
        XCTAssertEqual(decoded.status, "pass")
        XCTAssertEqual(decoded.message, "Accessibility access granted")
        XCTAssertNil(decoded.fix)
    }

    func testDoctorCheckWithFix() throws {
        struct Check: Codable {
            let name: String
            let status: String
            let message: String
            var fix: String?
        }

        let check = Check(name: "target_ax_tree", status: "warn", message: "AX tree empty",
                          fix: "Grant target app Accessibility access")
        let data = try JSONEncoder().encode(check)
        let decoded = try JSONDecoder().decode(Check.self, from: data)

        XCTAssertEqual(decoded.status, "warn")
        XCTAssertNotNil(decoded.fix)
        XCTAssertTrue(decoded.fix!.contains("Accessibility"))
    }

    // MARK: - TargetInfo model

    func testTargetInfoCodable() throws {
        struct TargetInfo: Codable {
            let bundleId: String?
            let pid: Int?
            let signed: Bool
            let identity: String?
        }

        let info = TargetInfo(bundleId: "com.apple.TextEdit", pid: 1234, signed: true, identity: "Apple Development")
        let data = try JSONEncoder().encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["bundleId"] as? String, "com.apple.TextEdit")
        XCTAssertEqual(json["pid"] as? Int, 1234)
        XCTAssertEqual(json["signed"] as? Bool, true)
        XCTAssertEqual(json["identity"] as? String, "Apple Development")
    }

    func testTargetInfoNoProcess() throws {
        struct TargetInfo: Codable {
            let bundleId: String?
            let pid: Int?
            let signed: Bool
            let identity: String?
        }

        let info = TargetInfo(bundleId: "com.example.notrunning", pid: nil, signed: false, identity: nil)
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(TargetInfo.self, from: data)

        XCTAssertEqual(decoded.bundleId, "com.example.notrunning")
        XCTAssertNil(decoded.pid)
        XCTAssertFalse(decoded.signed)
        XCTAssertNil(decoded.identity)
    }

    // MARK: - DoctorResult model

    func testDoctorResultAllPass() throws {
        struct Check: Codable {
            let name: String
            let status: String
            let message: String
            var fix: String?
        }

        struct TargetInfo: Codable {
            let bundleId: String?
            let pid: Int?
            let signed: Bool
            let identity: String?
        }

        struct DoctorResult: Codable {
            let checks: [Check]
            let allPass: Bool
            var target: TargetInfo?
        }

        let checks = [
            Check(name: "accessibility", status: "pass", message: "OK"),
            Check(name: "target_ax_tree", status: "pass", message: "OK"),
        ]
        let result = DoctorResult(checks: checks, allPass: true,
                                  target: TargetInfo(bundleId: "com.apple.TextEdit", pid: 100, signed: true, identity: "Apple"))
        let data = try JSONEncoder().encode(result)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["allPass"] as? Bool, true)
        let targetJson = json["target"] as! [String: Any]
        XCTAssertEqual(targetJson["bundleId"] as? String, "com.apple.TextEdit")
    }

    func testDoctorResultWithFailure() throws {
        struct Check: Codable {
            let name: String
            let status: String
            let message: String
            var fix: String?
        }

        struct DoctorResult: Codable {
            let checks: [Check]
            let allPass: Bool
        }

        let checks = [
            Check(name: "accessibility", status: "pass", message: "OK"),
            Check(name: "target_signing", status: "warn", message: "Ad-hoc signed",
                  fix: "Sign with stable identity"),
        ]
        let allPass = checks.allSatisfy { $0.status == "pass" }
        let result = DoctorResult(checks: checks, allPass: allPass)

        XCTAssertFalse(result.allPass)
        XCTAssertEqual(result.checks.count, 2)
    }

    // MARK: - Codesign output parsing

    func testCodesignAdHocDetection() {
        let output = """
        Executable=/Applications/tmv.app/Contents/MacOS/tmv
        Identifier=com.example.tmv
        Format=app bundle with Mach-O thin (arm64)
        Signature=adhoc
        """
        let isAdHoc = output.contains("Signature=adhoc")
        XCTAssertTrue(isAdHoc)
    }

    func testCodesignAuthorityParsing() {
        let output = """
        Authority=Apple Development: developer@example.com (ABCD1234)
        Authority=Apple Worldwide Developer Relations Certification Authority
        Identifier=com.example.app
        """
        var identity: String? = nil
        if let range = output.range(of: "Authority=") {
            identity = String(output[range.upperBound...].prefix(while: { $0 != "\n" }))
        }
        XCTAssertEqual(identity, "Apple Development: developer@example.com (ABCD1234)")
    }

    // MARK: - ArtifactManifest model

    func testArtifactManifestCodable() throws {
        struct ArtifactFile: Codable {
            let name: String
            let path: String
            let size: Int
            var error: String?
        }

        struct ArtifactManifest: Codable {
            let timestamp: String
            let version: String
            let bundleId: String?
            let pid: Int?
            let directory: String
            let files: [ArtifactFile]
        }

        let manifest = ArtifactManifest(
            timestamp: "2026-09-30T12:00:00Z",
            version: "0.12.0",
            bundleId: "com.apple.TextEdit",
            pid: 1234,
            directory: "/tmp/test-artifacts",
            files: [
                ArtifactFile(name: "doctor.json", path: "/tmp/test-artifacts/doctor.json", size: 512),
                ArtifactFile(name: "status.json", path: "/tmp/test-artifacts/status.json", size: 256),
                ArtifactFile(name: "snapshot.json", path: "/tmp/test-artifacts/snapshot.json", size: 4096),
                ArtifactFile(name: "screenshot.png", path: "/tmp/test-artifacts/screenshot.png", size: 0,
                             error: "Screenshot capture failed"),
            ]
        )

        let data = try JSONEncoder().encode(manifest)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["version"] as? String, "0.12.0")
        XCTAssertEqual(json["bundleId"] as? String, "com.apple.TextEdit")
        let files = json["files"] as! [[String: Any]]
        XCTAssertEqual(files.count, 4)
        XCTAssertEqual(files[0]["name"] as? String, "doctor.json")
        XCTAssertEqual(files[3]["error"] as? String, "Screenshot capture failed")
    }

    // MARK: - Snapshot filter logic

    func testVisibleOnlyFilter() {
        let nodes = [
            AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: CGPoint(x: 10, y: 20), size: CGSize(width: 80, height: 30),
                   actions: ["AXPress"], children: []),
            AXNode(role: "AXButton", subrole: nil, title: "Hidden", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil,
                   actions: ["AXPress"], children: []),
            AXNode(role: "AXButton", subrole: nil, title: "Offscreen", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: CGPoint(x: -100, y: -50), size: CGSize(width: 80, height: 30),
                   actions: ["AXPress"], children: []),
        ]

        let visible = nodes.filter { node in
            guard let pos = node.position, let sz = node.size else { return false }
            return sz.width > 0 && sz.height > 0 && pos.x >= 0 && pos.y >= 0
        }

        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible[0].title, "OK")
    }

    func testNonzeroBoundsFilter() {
        let nodes = [
            AXNode(role: "AXButton", subrole: nil, title: "Normal", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: CGPoint(x: 0, y: 0), size: CGSize(width: 100, height: 40),
                   actions: ["AXPress"], children: []),
            AXNode(role: "AXGroup", subrole: nil, title: "ZeroWidth", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: CGPoint(x: 0, y: 0), size: CGSize(width: 0, height: 40),
                   actions: [], children: []),
            AXNode(role: "AXGroup", subrole: nil, title: "NilSize", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: CGPoint(x: 0, y: 0), size: nil,
                   actions: [], children: []),
        ]

        let nonzero = nodes.filter { node in
            guard let sz = node.size else { return false }
            return sz.width > 0 && sz.height > 0
        }

        XCTAssertEqual(nonzero.count, 1)
        XCTAssertEqual(nonzero[0].title, "Normal")
    }

    func testRoleFilter() {
        let nodes = [
            AXNode(role: "AXButton", subrole: nil, title: "Save", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: ["AXPress"], children: []),
            AXNode(role: "AXTextField", subrole: nil, title: nil, axDescription: nil, value: "hello",
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: [], children: []),
            AXNode(role: "AXButton", subrole: nil, title: "Cancel", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: ["AXPress"], children: []),
        ]

        // Filter by AX role name
        let byRole = nodes.filter { $0.role.lowercased() == "axbutton" }
        XCTAssertEqual(byRole.count, 2)

        // Filter by display type
        let byDisplayType = nodes.filter { $0.displayType.lowercased() == "button" }
        XCTAssertEqual(byDisplayType.count, 2)
    }

    func testWindowOnlyFilter() {
        let nodes = [
            AXNode(role: "AXMenuBar", subrole: nil, title: nil, axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: [], children: []),
            AXNode(role: "AXMenuBarItem", subrole: nil, title: "File", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: ["AXPress"], children: []),
            AXNode(role: "AXButton", subrole: nil, title: "OK", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: ["AXPress"], children: []),
            AXNode(role: "AXApplication", subrole: nil, title: "App", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: nil, size: nil, actions: [], children: []),
        ]

        let excludeRoles = Set(["AXMenuBar", "AXMenuBarItem", "AXApplication"])
        let windowOnly = nodes.filter { node in
            if excludeRoles.contains(node.role) { return false }
            return true
        }

        XCTAssertEqual(windowOnly.count, 1)
        XCTAssertEqual(windowOnly[0].title, "OK")
    }

    func testFilterCombination() {
        let nodes = [
            AXNode(role: "AXButton", subrole: nil, title: "Visible", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: CGPoint(x: 10, y: 20), size: CGSize(width: 80, height: 30),
                   actions: ["AXPress"], children: []),
            AXNode(role: "AXButton", subrole: nil, title: "ZeroBounds", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: CGPoint(x: 10, y: 20), size: CGSize(width: 0, height: 0),
                   actions: ["AXPress"], children: []),
            AXNode(role: "AXTextField", subrole: nil, title: "Field", axDescription: nil, value: nil,
                   identifier: nil, childStaticText: nil, enabled: true, focused: false,
                   position: CGPoint(x: 10, y: 20), size: CGSize(width: 200, height: 25),
                   actions: [], children: []),
        ]

        // Combined: nonzero-bounds + role=button
        let filtered = nodes
            .filter { node in
                guard let sz = node.size else { return false }
                return sz.width > 0 && sz.height > 0
            }
            .filter { $0.role.lowercased() == "axbutton" }

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].title, "Visible")
    }

    // MARK: - Artifact file error handling

    func testArtifactFileWithError() throws {
        struct ArtifactFile: Codable {
            let name: String
            let path: String
            let size: Int
            var error: String?
        }

        let file = ArtifactFile(name: "screenshot.png", path: "/tmp/test/screenshot.png", size: 0,
                                error: "Screenshot capture failed")
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(ArtifactFile.self, from: data)

        XCTAssertEqual(decoded.name, "screenshot.png")
        XCTAssertEqual(decoded.size, 0)
        XCTAssertNotNil(decoded.error)
        XCTAssertTrue(decoded.error!.contains("capture failed"))
    }
}
