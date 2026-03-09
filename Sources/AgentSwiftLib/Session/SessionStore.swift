import Foundation

public struct SessionData: Codable {
    public var pid: Int?
    public var bundleId: String?
    public var connectedAt: String?
    public var refs: [String: RefEntry]
    public var lastSnapshotAt: String?

    public struct RefEntry: Codable {
        public let role: String
        public let label: String?
        public let identifier: String?
        public let enabled: Bool
        public let focused: Bool
        let bounds: Bounds?
        public let actions: [String]

        public init(role: String, label: String?, identifier: String?, enabled: Bool,
                    focused: Bool, bounds: Bounds?, actions: [String]) {
            self.role = role; self.label = label; self.identifier = identifier
            self.enabled = enabled; self.focused = focused; self.bounds = bounds
            self.actions = actions
        }

        public struct Bounds: Codable {
            public let x: Double
            public let y: Double
            public let width: Double
            public let height: Double

            public init(x: Double, y: Double, width: Double, height: Double) {
                self.x = x; self.y = y; self.width = width; self.height = height
            }
        }
    }

    public var isConnected: Bool {
        return pid != nil
    }

    public static var empty: SessionData {
        return SessionData(pid: nil, bundleId: nil, connectedAt: nil, refs: [:], lastSnapshotAt: nil)
    }
}

public struct SessionStore {
    static let defaultPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".agent-swift")
        .appendingPathComponent("session.json")

    public let path: URL

    public init(path: URL? = nil) {
        self.path = path ?? Self.defaultPath
    }

    public func load() -> SessionData {
        guard let data = try? Data(contentsOf: path),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            return .empty
        }
        return session
    }

    public func save(_ session: SessionData) throws {
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: path, options: .atomic)
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
}
