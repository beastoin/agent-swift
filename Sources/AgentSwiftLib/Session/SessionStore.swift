import Foundation

public struct RecordingSession: Codable {
    public var sessionId: String
    public var pid: Int32
    public var videoPath: String
    public var startTime: String
    public var mode: String  // "simulator", "desktop", "mirror"

    public init(sessionId: String, pid: Int32, videoPath: String, startTime: String, mode: String) {
        self.sessionId = sessionId
        self.pid = pid
        self.videoPath = videoPath
        self.startTime = startTime
        self.mode = mode
    }
}

public struct SessionData: Codable {
    public var pid: Int?
    public var bundleId: String?
    public var connectedAt: String?
    public var refs: [String: RefEntry]
    public var lastSnapshotAt: String?
    public var interactiveSnapshot: Bool?
    public var simulatorUDID: String?
    public var simulatorDeviceType: String?
    public var mirrorMode: Bool?
    public var recording: RecordingSession?
    public var lastVideoPath: String?
    public var lastFramePath: String?

    public struct RefEntry: Codable {
        public let role: String
        public let label: String?
        public let identifier: String?
        public let enabled: Bool
        public let focused: Bool
        public let bounds: Bounds?
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
        return pid != nil || simulatorUDID != nil || mirrorMode == true
    }

    public var isSimulatorMode: Bool {
        return simulatorUDID != nil
    }

    public var isMirrorMode: Bool {
        return mirrorMode == true
    }

    public static var empty: SessionData {
        return SessionData(pid: nil, bundleId: nil, connectedAt: nil, refs: [:], lastSnapshotAt: nil, interactiveSnapshot: nil, simulatorUDID: nil, simulatorDeviceType: nil, mirrorMode: nil, recording: nil, lastVideoPath: nil, lastFramePath: nil)
    }
}

public struct SessionStore {
    static let defaultPath: URL = {
        if let home = ProcessInfo.processInfo.environment["AGENT_SWIFT_HOME"] {
            return URL(fileURLWithPath: home).appendingPathComponent("session.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-swift")
            .appendingPathComponent("session.json")
    }()

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
