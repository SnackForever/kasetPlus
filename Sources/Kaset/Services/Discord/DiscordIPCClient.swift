import Darwin
import Foundation

// MARK: - DiscordIPCError

enum DiscordIPCError: Error, Equatable {
    /// No `discord-ipc-N` socket exists — Discord is not running.
    case discordNotRunning
    case connectionFailed(errno: Int32)
    case writeFailed(errno: Int32)
    case connectionClosed
    /// Discord rejected the handshake. 4000 means the Application ID is wrong.
    case rejected(code: Int, message: String)
}

// MARK: - DiscordIPCClient

/// Minimal client for Discord's local Rich Presence IPC socket.
///
/// The protocol is a Unix domain socket carrying length-prefixed JSON frames:
/// an 8-byte little-endian header (opcode, byte count) followed by the payload.
/// That is the whole wire format, so this needs no third-party library.
///
/// Discord listens on `discord-ipc-0` through `discord-ipc-9` in the user's
/// temporary directory; several sockets exist when more than one Discord build
/// is running, so we take the first that accepts a handshake.
actor DiscordIPCClient {
    enum Opcode: UInt32 {
        case handshake = 0
        case frame = 1
        case close = 2
        case ping = 3
        case pong = 4
    }

    /// Discord closes the socket if a frame claims an implausible length; cap
    /// reads so a corrupt or hostile header cannot make us allocate wildly.
    private static let maximumFrameBytes = 64 * 1024
    private static let socketCandidates = 0 ... 9

    private var descriptor: Int32?
    private let logger = DiagnosticsLogger.player

    var isConnected: Bool { self.descriptor != nil }

    deinit {
        if let descriptor { Darwin.close(descriptor) }
    }

    // MARK: - Connection

    /// Candidate socket paths, in probe order. Discord uses the real user
    /// temporary directory; `NSTemporaryDirectory()` matches it because Kaset
    /// ships unsandboxed (see `Kaset.entitlements`).
    static func socketPaths() -> [String] {
        let base = NSTemporaryDirectory()
        return Self.socketCandidates.map { base + "discord-ipc-\($0)" }
    }

    func connect(applicationID: String) async throws {
        self.disconnect()
        let paths = Self.socketPaths().filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { throw DiscordIPCError.discordNotRunning }

        var lastError: DiscordIPCError = .discordNotRunning
        for path in paths {
            do {
                let descriptor = try Self.openSocket(at: path)
                self.descriptor = descriptor
                try self.send(opcode: .handshake, payload: ["v": 1, "client_id": applicationID])
                let response = try self.readFrame()
                if response.opcode == .close {
                    let code = response.payload["code"] as? Int ?? -1
                    let message = response.payload["message"] as? String ?? "unknown"
                    self.disconnect()
                    // A bad Application ID fails the same way on every socket.
                    throw DiscordIPCError.rejected(code: code, message: message)
                }
                return
            } catch let error as DiscordIPCError {
                self.disconnect()
                if case .rejected = error { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    func disconnect() {
        guard let descriptor else { return }
        Darwin.close(descriptor)
        self.descriptor = nil
    }

    private static func openSocket(at path: String) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw DiscordIPCError.connectionFailed(errno: errno) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            Darwin.close(descriptor)
            throw DiscordIPCError.connectionFailed(errno: ENAMETOOLONG)
        }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: capacity) { buffer in
                    _ = strncpy(buffer, source, capacity - 1)
                }
            }
        }

        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, length) }
        }
        guard result == 0 else {
            let failure = errno
            Darwin.close(descriptor)
            throw DiscordIPCError.connectionFailed(errno: failure)
        }
        return descriptor
    }

    // MARK: - Activity

    func setActivity(_ activity: [String: Any]?, processID: Int32) throws {
        var arguments: [String: Any] = ["pid": Int(processID)]
        // A nil activity clears the presence; Discord expects the key omitted.
        if let activity { arguments["activity"] = activity }
        try self.send(
            opcode: .frame,
            payload: [
                "cmd": "SET_ACTIVITY",
                "args": arguments,
                "nonce": UUID().uuidString,
            ]
        )
    }

    // MARK: - Framing

    /// Encodes one IPC frame: little-endian opcode, little-endian byte count, body.
    static func encodeFrame(opcode: Opcode, body: Data) -> Data {
        var frame = Data(capacity: 8 + body.count)
        withUnsafeBytes(of: opcode.rawValue.littleEndian) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(body.count).littleEndian) { frame.append(contentsOf: $0) }
        frame.append(body)
        return frame
    }

    /// Decodes a frame header, rejecting lengths past `maximumFrameBytes`.
    static func decodeHeader(_ header: Data) -> (opcode: UInt32, length: Int)? {
        guard header.count == 8 else { return nil }
        let opcode = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }.littleEndian
        let length = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }.littleEndian
        guard length <= UInt32(Self.maximumFrameBytes) else { return nil }
        return (opcode, Int(length))
    }

    private func send(opcode: Opcode, payload: [String: Any]) throws {
        guard let descriptor else { throw DiscordIPCError.connectionClosed }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let frame = Self.encodeFrame(opcode: opcode, body: body)
        try frame.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard written > 0 else { throw DiscordIPCError.writeFailed(errno: errno) }
                offset += written
            }
        }
    }

    private func readFrame() throws -> (opcode: Opcode, payload: [String: Any]) {
        let header = try self.readExactly(8)
        guard let decoded = Self.decodeHeader(header) else { throw DiscordIPCError.connectionClosed }
        let body = decoded.length > 0 ? try self.readExactly(decoded.length) : Data()
        let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        return (Opcode(rawValue: decoded.opcode) ?? .frame, payload)
    }

    private func readExactly(_ count: Int) throws -> Data {
        guard let descriptor else { throw DiscordIPCError.connectionClosed }
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let read = buffer.withUnsafeMutableBytes { pointer in
                Darwin.read(descriptor, pointer.baseAddress!.advanced(by: offset), count - offset)
            }
            guard read > 0 else { throw DiscordIPCError.connectionClosed }
            offset += read
        }
        return Data(buffer)
    }
}
