import Foundation

public struct CommandSchema: Codable {
    public let name: String
    public let description: String
    public let args: [ArgSchema]
    public let flags: [FlagSchema]
    public let exitCodes: [String: String]

    public init(name: String, description: String, args: [ArgSchema], flags: [FlagSchema], exitCodes: [String: String]) {
        self.name = name
        self.description = description
        self.args = args
        self.flags = flags
        self.exitCodes = exitCodes
    }

    public struct ArgSchema: Codable {
        public let name: String
        public let type: String
        public let required: Bool

        public init(name: String, type: String, required: Bool) {
            self.name = name
            self.type = type
            self.required = required
        }
    }

    public struct FlagSchema: Codable {
        public let name: String
        public let type: String
        public let defaultValue: String?

        public init(name: String, type: String, defaultValue: String?) {
            self.name = name
            self.type = type
            self.defaultValue = defaultValue
        }

        enum CodingKeys: String, CodingKey {
            case name, type
            case defaultValue = "default"
        }
    }
}
