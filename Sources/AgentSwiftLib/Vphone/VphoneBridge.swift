import Foundation

public enum VphoneError: Error, CustomStringConvertible {
    case socketNotFound(String)
    case connectionFailed(String)
    case commandFailed(String)
    case invalidResponse(String)

    public var code: String {
        switch self {
        case .socketNotFound: return "VPHONE_SOCKET_NOT_FOUND"
        case .connectionFailed: return "VPHONE_CONNECTION_FAILED"
        case .commandFailed: return "VPHONE_COMMAND_FAILED"
        case .invalidResponse: return "VPHONE_INVALID_RESPONSE"
        }
    }

    public var hint: String? {
        switch self {
        case .socketNotFound:
            return "Check VM is running: ls ~/.vphone/VMs/*/vphone.sock"
        case .connectionFailed:
            return "Is the VM running? Boot with: vphone-cli vm launch <name>"
        case .commandFailed(let msg):
            return msg
        case .invalidResponse:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .socketNotFound(let path): return "vphone socket not found: \(path)"
        case .connectionFailed(let msg): return "vphone connection failed: \(msg)"
        case .commandFailed(let msg): return "vphone command failed: \(msg)"
        case .invalidResponse(let msg): return "Invalid vphone response: \(msg)"
        }
    }
}

public struct VphoneBridge {
    public let socketPath: String
    public let vmName: String
    /// VM IP address for VNC taps (socket tap is broken in iOS 26)
    public var vmIP: String?

    /// Screen dimensions in pixels (3x retina)
    public static let screenWidthPx: Double = 1290
    public static let screenHeightPx: Double = 2796
    /// Retina scale factor
    public static let scale: Double = 3.0
    /// Logical point dimensions (what agents use)
    public static let screenWidth: Double = 430
    public static let screenHeight: Double = 932
    /// VNC port on jailbroken vphone VMs (TrollVNC)
    public static let vncPort: Int = 5901
    /// VNC password
    public static let vncPassword: String = "alpine"
    /// SSH port for uiopen commands
    public static let sshPort: Int = 22222
    /// SSH password
    public static let sshPassword: String = "alpine"

    public init(vmName: String, socketPath: String? = nil, vmIP: String? = nil) {
        self.vmName = vmName
        self.socketPath = socketPath ?? Self.defaultSocketPath(for: vmName)
        self.vmIP = vmIP
    }

    public static func defaultSocketPath(for vmName: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.vphone/VMs/\(vmName)/vphone.sock"
    }

    /// Auto-detect first VM with a live socket
    public static func autoDetect() throws -> VphoneBridge {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let vmsDir = "\(home)/.vphone/VMs"
        let fm = FileManager.default

        guard fm.fileExists(atPath: vmsDir) else {
            throw VphoneError.socketNotFound(vmsDir)
        }

        guard let contents = try? fm.contentsOfDirectory(atPath: vmsDir) else {
            throw VphoneError.socketNotFound(vmsDir)
        }

        for vmDir in contents.sorted() {
            let sockPath = "\(vmsDir)/\(vmDir)/vphone.sock"
            if fm.fileExists(atPath: sockPath) {
                return VphoneBridge(vmName: vmDir, socketPath: sockPath)
            }
        }

        throw VphoneError.socketNotFound("No vphone.sock found in \(vmsDir)")
    }

    /// Discover VM IP by scanning bridge network (192.168.64.x) via SSH probe
    public static func discoverVMIP() -> String? {
        // Try common bridge IPs — vphone NAT VMs typically get IPs in 192.168.64.x range
        let candidates = (2...30).map { "192.168.64.\($0)" }
        for ip in candidates {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["sshpass", "-p", sshPassword,
                                "ssh", "-o", "StrictHostKeyChecking=no",
                                "-o", "ConnectTimeout=2",
                                "-p", "\(sshPort)", "root@\(ip)",
                                "echo", "ok"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return ip
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Check if socket file exists
    public func isAvailable() -> Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    // MARK: - Commands

    public func screenshot(to path: String) throws {
        let resp = try send(["t": "screenshot", "path": path])
        guard resp["ok"] as? Bool == true else {
            let err = resp["error"] as? String ?? "screenshot failed"
            throw VphoneError.commandFailed(err)
        }
    }

    /// Tap at logical coordinates via VNC (vncdo).
    /// Socket tap is broken in iOS 26 (returns ok:true but has zero effect).
    /// VNC tap through TrollVNC port 5901 delivers real iOS touch events.
    public func tap(x: Double, y: Double) throws {
        guard let ip = vmIP else {
            throw VphoneError.commandFailed(
                "No VM IP configured — cannot send VNC tap. " +
                "Reconnect with: agent-swift connect --vphone \(vmName)")
        }
        let px = Int(x * Self.scale)
        let py = Int(y * Self.scale)
        try runVncTap(ip: ip, x: px, y: py)
    }

    /// Swipe is NOT supported — VNC drag does not translate to iOS swipe,
    /// and socket swipe is broken (iOS 26 HID issue).
    public func swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, durationMs: Int = 300) throws {
        throw VphoneError.commandFailed(
            "Swipe not available in vphone mode (iOS 26 HID limitation). " +
            "Use SSH uiopen for navigation: sshpass -p alpine ssh -p 22222 root@\(vmIP ?? "VM_IP") uiopen <url>")
    }

    public func key(_ name: String) throws {
        let resp = try send(["t": "key", "name": name])
        guard resp["ok"] as? Bool == true else {
            let err = resp["error"] as? String ?? "key \(name) failed"
            throw VphoneError.commandFailed(err)
        }
    }

    /// Open an app or URL via SSH uiopen (bypasses lock screen, no touch needed)
    public func uiopen(_ target: String) throws {
        guard let ip = vmIP else {
            throw VphoneError.commandFailed("No VM IP — cannot SSH to VM")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sshpass", "-p", Self.sshPassword,
                            "ssh", "-o", "StrictHostKeyChecking=no",
                            "-p", "\(Self.sshPort)", "root@\(ip)",
                            "uiopen", target]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw VphoneError.commandFailed("uiopen failed: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    // MARK: - VNC tap (workaround for broken socket touch)

    /// Send a tap via vncdotool to TrollVNC on port 5901.
    /// Must pause 8s on first connect to let the notification banner clear.
    private func runVncTap(ip: String, x: Int, y: Int) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // vncdo -s <ip>::5901 -p alpine -t 15 pause 8 move X Y pause 0.2 click 1
        process.arguments = ["vncdo",
                            "-s", "\(ip)::\(Self.vncPort)",
                            "-p", Self.vncPassword,
                            "-t", "15",
                            "pause", "8",
                            "move", "\(x)", "\(y)",
                            "pause", "0.2",
                            "click", "1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw VphoneError.commandFailed("vncdo not found — install: pip install vncdotool")
        }
        guard process.terminationStatus == 0 else {
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw VphoneError.commandFailed("VNC tap failed: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    // MARK: - Socket communication

    /// Send a JSON command over unix socket and return parsed response.
    /// Protocol: newline-delimited JSON. One connection per command.
    public func send(_ command: [String: Any]) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw VphoneError.socketNotFound(socketPath)
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw VphoneError.connectionFailed("Cannot create socket")
        }
        defer { Darwin.close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw VphoneError.connectionFailed("Socket path too long")
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            sunPathPtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { ptr in
                for (i, byte) in pathBytes.enumerated() {
                    ptr[i] = byte
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            throw VphoneError.connectionFailed("connect() failed: \(String(cString: strerror(errno)))")
        }

        // Serialize and send
        let jsonData = try JSONSerialization.data(withJSONObject: command)
        var payload = jsonData
        payload.append(contentsOf: [0x0A]) // newline

        let written = payload.withUnsafeBytes { ptr in
            Darwin.write(fd, ptr.baseAddress!, ptr.count)
        }
        guard written == payload.count else {
            throw VphoneError.connectionFailed("Failed to write command")
        }

        // Read response until newline or EOF
        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let bytesRead = Darwin.read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            responseData.append(contentsOf: buffer[0..<bytesRead])
            if buffer[0..<bytesRead].contains(0x0A) { break }
        }

        let trimmed = responseData.prefix(while: { $0 != 0x0A })
        guard !trimmed.isEmpty else {
            throw VphoneError.invalidResponse("Empty response")
        }

        guard let json = try? JSONSerialization.jsonObject(with: Data(trimmed)) as? [String: Any] else {
            throw VphoneError.invalidResponse("Not valid JSON")
        }

        return json
    }

    // MARK: - Coordinate helpers

    /// Convert logical points to pixel coordinates
    public static func logicalToPixel(x: Double, y: Double) -> (px: Int, py: Int) {
        return (Int(x * scale), Int(y * scale))
    }

    /// Convert pixel coordinates to logical points
    public static func pixelToLogical(px: Int, py: Int) -> (x: Double, y: Double) {
        return (Double(px) / scale, Double(py) / scale)
    }
}
