import Foundation

public struct ErrorInfo: Codable {
    public let code: String
    public let message: String
    public let hint: String?
    public let diagnosticId: String

    public init(code: String, message: String, hint: String? = nil) {
        self.code = code
        self.message = message
        self.hint = hint
        self.diagnosticId = String(UUID().uuidString.prefix(8)).lowercased()
    }
}

public struct ErrorEnvelope: Codable {
    public let error: ErrorInfo
}

public enum Output {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public static func json<T: Encodable>(_ value: T) -> String {
        let data = try! encoder.encode(value)
        return String(data: data, encoding: .utf8)!
    }

    public static func errorJson(code: String, message: String, hint: String? = nil) -> String {
        return json(ErrorEnvelope(error: ErrorInfo(code: code, message: message, hint: hint)))
    }

    public static func printError(code: String, message: String, hint: String? = nil, useJson: Bool) {
        if useJson {
            FileHandle.standardError.write(Data((errorJson(code: code, message: message, hint: hint) + "\n").utf8))
        } else {
            FileHandle.standardError.write(Data("error: \(message)\n".utf8))
            if let hint = hint {
                FileHandle.standardError.write(Data("hint: \(hint)\n".utf8))
            }
        }
    }
}
