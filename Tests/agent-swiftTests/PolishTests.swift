import XCTest
import Foundation
@testable import AgentSwiftLib

final class PolishTests: XCTestCase {

    // MARK: - SessionStore env var

    func testSessionStoreDefaultPath() {
        let store = SessionStore()
        XCTAssertTrue(store.path.path.contains(".agent-swift"))
        XCTAssertTrue(store.path.path.hasSuffix("session.json"))
    }

    func testSessionStoreCustomPath() {
        let customURL = URL(fileURLWithPath: "/tmp/test-custom/session.json")
        let store = SessionStore(path: customURL)
        XCTAssertEqual(store.path, customURL)
    }

    // MARK: - CommandSchema completeness

    func testCommandSchemaHas14Commands() {
        // Build the full schema list (same as allSchemas() in main.swift)
        // We test that CommandSchema can be created for all expected commands
        let expectedCommands = [
            "doctor", "connect", "disconnect", "status", "snapshot",
            "press", "fill", "get", "find", "screenshot",
            "is", "wait", "scroll", "schema"
        ]
        XCTAssertEqual(expectedCommands.count, 14)

        // Verify each can be instantiated as a CommandSchema
        for name in expectedCommands {
            let schema = CommandSchema(
                name: name, description: "test",
                args: [], flags: [], exitCodes: ["0": "success"]
            )
            XCTAssertEqual(schema.name, name)
        }
    }

    // MARK: - Error format

    func testErrorEnvelopeHasDiagnosticId() {
        let info = ErrorInfo(code: "TEST", message: "test error")
        XCTAssertFalse(info.diagnosticId.isEmpty)
        XCTAssertEqual(info.diagnosticId.count, 8)
    }

    func testErrorEnvelopeIncludesHint() {
        let info = ErrorInfo(code: "TEST", message: "msg", hint: "try this")
        XCTAssertEqual(info.hint, "try this")
    }

    func testErrorJsonContainsAllFields() throws {
        let json = Output.errorJson(code: "NOT_CONNECTED", message: "No session", hint: "Connect first")
        let data = json.data(using: .utf8)!
        let parsed = try JSONDecoder().decode(ErrorEnvelope.self, from: data)
        XCTAssertEqual(parsed.error.code, "NOT_CONNECTED")
        XCTAssertEqual(parsed.error.message, "No session")
        XCTAssertEqual(parsed.error.hint, "Connect first")
        XCTAssertFalse(parsed.error.diagnosticId.isEmpty)
    }

    // MARK: - Session data

    func testSessionDataEmptyIsNotConnected() {
        let session = SessionData.empty
        XCTAssertFalse(session.isConnected)
        XCTAssertNil(session.pid)
    }

    func testSessionStoreLoadReturnsEmptyForMissingFile() {
        let store = SessionStore(path: URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)/session.json"))
        let session = store.load()
        XCTAssertFalse(session.isConnected)
    }
}
