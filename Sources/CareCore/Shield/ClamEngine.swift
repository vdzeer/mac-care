import Darwin
import Foundation

/// Where Ward keeps the engine's files: its settings, the signature database, the socket.
public struct ClamPaths: Sendable, Equatable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public static func standard() -> ClamPaths {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ClamPaths(folder: support.appendingPathComponent("Ward/clamav"))
    }

    public var database: URL { folder.appendingPathComponent("db") }
    public var daemonConfig: URL { folder.appendingPathComponent("clamd.conf") }
    public var updaterConfig: URL { folder.appendingPathComponent("freshclam.conf") }
    public var log: URL { folder.appendingPathComponent("clamd.log") }
    public var pidFile: URL { folder.appendingPathComponent("clamd.pid") }

    /// A unix socket path may be at most 103 bytes; a long home folder falls back to this user's own temporary
    /// folder. Never the shared /tmp, where another account could take the name first and answer in the engine's place.
    public var socket: String {
        let preferred = folder.appendingPathComponent("clamd.sock").path
        return preferred.utf8.count < 100 ? preferred : Self.userTemporaryFolder() + "ward-clamd.sock"
    }

    /// The temporary folder only this user can enter, `/var/folders/…/T/`, with a slash at the end.
    static func userTemporaryFolder() -> String {
        let size = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        var folder = NSTemporaryDirectory()
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, size) > 0 {
                folder = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        return folder.hasSuffix("/") ? folder : folder + "/"
    }

    /// The database is refreshed when it is a day old, and after a failed try not again within the hour.
    public static func isUpdateDue(lastCheck: Date?, lastAttempt: Date?, now: Date = Date()) -> Bool {
        let isStale = lastCheck.map { now.timeIntervalSince($0) > 86_400 } ?? true
        let triedLately = lastAttempt.map { now.timeIntervalSince($0) < 3_600 } ?? false
        return isStale && triedLately == false
    }

    /// When the signature database was last refreshed, or nil when there is none yet.
    public func databaseDate() -> Date? {
        let files = (try? FileManager.default.contentsOfDirectory(at: database, includingPropertiesForKeys: nil)) ?? []
        let dates = files.filter { ["cvd", "cld"].contains($0.pathExtension) }.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        return dates.max()
    }

    /// When the updater last ran to the end, whether or not it found anything newer.
    public func lastCheckDate() -> Date? {
        let marker = database.appendingPathComponent("freshclam.dat")
        let checked = try? marker.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return [checked, databaseDate()].compactMap { $0 }.max()
    }

    public func daemonConfigText(excluding excluded: [URL]) -> String {
        var lines = [
            "LocalSocket \(socket)", "LocalSocketMode 600", "FixStaleSocket yes", "DatabaseDirectory \(database.path)",
            "LogFile \(log.path)", "LogFileMaxSize 2M", "PidFile \(pidFile.path)", "Foreground yes", "MaxThreads 8",
            "MaxDirectoryRecursion 40", "FollowDirectorySymlinks no", "FollowFileSymlinks no", "CrossFilesystems no",
            "MaxFileSize 400M", "MaxScanSize 800M", "DetectPUA no", "CommandReadTimeout 30",
        ]
        for url in excluded {
            lines.append("ExcludePath ^\(Self.pattern(for: url.path))/")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A path as a regular expression for the engine's settings file. A space becomes "any character",
    /// because the settings file would cut the line at a space.
    static func pattern(for path: String) -> String {
        var pattern = ""
        for character in path {
            if character == " " {
                pattern += "."
            } else if ".[]{}()*+?^$|\\".contains(character) {
                pattern += "\\\(character)"
            } else {
                pattern.append(character)
            }
        }
        return pattern
    }

    public func updaterConfigText() -> String {
        [
            "DatabaseDirectory \(database.path)", "DatabaseMirror database.clamav.net", "Foreground yes",
            "UpdateLogFile \(folder.appendingPathComponent("freshclam.log").path)",
        ].joined(separator: "\n") + "\n"
    }

    public func writeConfigs(excluding excluded: [URL]) throws {
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
        try daemonConfigText(excluding: excluded).write(to: daemonConfig, atomically: true, encoding: .utf8)
        try updaterConfigText().write(to: updaterConfig, atomically: true, encoding: .utf8)
    }
}

/// What the engine said about one path.
public struct ClamReply: Sendable, Equatable {
    public struct Hit: Sendable, Equatable {
        public let path: String
        public let signature: String
    }

    public var hits: [Hit] = []
    /// Lines the engine could not scan (no access, vanished files).
    public var errors: [String] = []

    /// Reads the engine's answer: lines ending in "FOUND", "ERROR" or "OK". The "z" form of a command ends each
    /// line with NUL and nothing else, because a file name may itself hold a newline. A hit is kept only when its
    /// path is absolute and lies inside one of the `scanned` paths (any absolute path when none are given).
    public static func parse(_ text: String, scanned: [String] = []) -> ClamReply {
        var reply = ClamReply()
        for raw in text.split(separator: "\0") {
            let line = String(raw)
            if line.hasSuffix(" FOUND"), let colon = line.range(of: ": ", options: .backwards) {
                let path = String(line[..<colon.lowerBound])
                let signature = line[colon.upperBound...].dropLast(" FOUND".count)
                guard isPlausible(path, inside: scanned) else { continue }
                reply.hits.append(Hit(path: path, signature: String(signature)))
            } else if line.hasSuffix("ERROR") {
                reply.errors.append(line)
            }
        }
        return reply
    }

    /// An absolute path with no "." or ".." on the way, equal to or below one of the scanned paths.
    static func isPlausible(_ path: String, inside scanned: [String]) -> Bool {
        guard path.hasPrefix("/") else { return false }
        if path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) { return false }
        if scanned.isEmpty { return true }
        return scanned.contains { root in
            path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
    }

    /// How many places the engine could not read. Online-only cloud files are left out: the engine is kept from
    /// downloading them, so they fail on purpose. `isOnlineOnly` is asked about every way to cut the path off a line.
    public func unreadableCount(isOnlineOnly: (String) -> Bool = CloudFiles.isOnlineOnly) -> Int {
        errors.filter { line in
            var rest = line.startIndex..<line.endIndex
            while let colon = line.range(of: ": ", range: rest) {
                if isOnlineOnly(String(line[..<colon.lowerBound])) { return false }
                rest = colon.upperBound..<line.endIndex
            }
            return true
        }
        .count
    }
}

/// Files in iCloud Drive and other cloud folders that are listed on disk but whose content stays online until
/// something reads them.
public enum CloudFiles {
    /// True for a file whose content is not on this Mac. Asking does not download it.
    public static func isOnlineOnly(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_DATALESS) != 0
    }

    /// Runs `body` while this process cannot download online-only files. A program started inside inherits that,
    /// so a scanner started here gets an error for such a file instead of fetching it from the cloud.
    public static func withoutDownloads<T>(_ body: () throws -> T) rethrows -> T {
        let type = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
        let previous = getiopolicy_np(type, IOPOL_SCOPE_PROCESS)
        setiopolicy_np(type, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        defer {
            if previous >= 0 { setiopolicy_np(type, IOPOL_SCOPE_PROCESS, previous) }
        }
        return try body()
    }

    /// Whether this process may download online-only files right now.
    static var downloadsAllowed: Bool {
        getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS)
            != IOPOL_MATERIALIZE_DATALESS_FILES_OFF
    }
}

public enum EngineError: Error, Equatable {
    case notInstalled
    case noDatabase
    case didNotStart(String)
    case connection(String)
}

/// Anything that can check a file or folder against known malware. Tests pass a fake.
public protocol ScanEngine: Sendable {
    func scan(_ url: URL) async throws -> ClamReply
}

/// Talks to a running `clamd` over its unix socket.
public struct ClamClient: ScanEngine, Sendable {
    public let socketPath: String
    /// How long a short command (PING, VERSION, RELOAD, SHUTDOWN) may wait for an answer. A hung engine must not
    /// hold up a check or the live protection for good.
    public let answerTimeout: TimeInterval

    public init(socketPath: String, answerTimeout: TimeInterval = 5) {
        self.socketPath = socketPath
        self.answerTimeout = answerTimeout
    }

    public func ping() async -> Bool {
        (try? await send("PING", timeout: answerTimeout)) == "PONG"
    }

    public func version() async -> String? {
        try? await send("VERSION", timeout: answerTimeout)
    }

    public func reload() async {
        _ = try? await send("RELOAD", timeout: answerTimeout)
    }

    public func shutdown() async {
        _ = try? await send("SHUTDOWN", timeout: answerTimeout)
    }

    /// Scans a file or a whole folder on several threads and reports everything it finds inside it.
    public func scan(_ url: URL) async throws -> ClamReply {
        let scanned = Array(Set([url.path, url.resolvingSymlinksInPath().path]))
        return ClamReply.parse(try await send("MULTISCAN \(url.path)", timeout: nil), scanned: scanned)
    }

    func send(_ command: String, timeout: TimeInterval?) async throws -> String {
        let box = SocketBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(
                        with: Result { try box.exchange(path: socketPath, command: command, timeout: timeout) })
                }
            }
        } onCancel: {
            box.close()
        }
    }
}

/// One connection: send a command, read until the engine closes it.
private final class SocketBox: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var isClosed = false

    func close() {
        lock.lock()
        isClosed = true
        if descriptor >= 0 { Darwin.shutdown(descriptor, SHUT_RDWR) }
        lock.unlock()
    }

    /// `timeout` limits every wait for the engine; nil waits as long as a scan takes.
    func exchange(path: String, command: String, timeout: TimeInterval?) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw EngineError.connection("socket") }
        lock.lock()
        descriptor = fd
        let cancelled = isClosed
        lock.unlock()
        // The number is forgotten before the socket is closed, so a late cancel never touches a reused one.
        defer {
            lock.lock()
            descriptor = -1
            lock.unlock()
            Darwin.close(fd)
        }
        if cancelled { throw CancellationError() }

        if let timeout {
            let seconds = max(timeout, 0.1)
            var limit = timeval(
                tv_sec: Int(seconds), tv_usec: Int32((seconds - seconds.rounded(.down)) * 1_000_000))
            let size = socklen_t(MemoryLayout<timeval>.size)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, size)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, size)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw EngineError.connection("socket path too long") }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw EngineError.connection(String(cString: strerror(errno))) }

        // The "z" form ends the command with NUL, so paths with spaces or newlines arrive intact.
        var request = Array("z\(command)".utf8) + [0]
        var sent = 0
        while sent < request.count {
            let count = request.withUnsafeMutableBytes { write(fd, $0.baseAddress! + sent, $0.count - sent) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw EngineError.connection(errno == EAGAIN ? "timed out" : "write") }
            sent += count
        }

        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count < 0, errno == EINTR { continue }
            if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { throw EngineError.connection("timed out") }
            if count <= 0 { break }
            data.append(chunk, count: count)
        }
        lock.lock()
        let wasCancelled = isClosed
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0\n"))
    }
}

/// Starts and stops the engine process, and keeps its signature database fresh.
public actor ClamDaemon {
    public nonisolated let paths: ClamPaths
    private let runner: any CommandRunning
    private var process: Process?

    public init(paths: ClamPaths = .standard(), runner: any CommandRunning = SystemCommandRunner()) {
        self.paths = paths
        self.runner = runner
    }

    public nonisolated var client: ClamClient { ClamClient(socketPath: paths.socket) }

    public nonisolated var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Tool.clamd)
            && FileManager.default.isExecutableFile(atPath: Tool.freshclam)
    }

    /// Downloads or refreshes the signature database. The first download is a few hundred megabytes.
    public func updateDatabase(excluding excluded: [URL] = []) async throws {
        guard isInstalled else { throw EngineError.notInstalled }
        try paths.writeConfigs(excluding: excluded)
        let result = try await runner.run(Tool.freshclam, ["--config-file=\(paths.updaterConfig.path)"], timeout: 1800)
        guard result.succeeded else {
            throw EngineError.didNotStart(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        if await client.ping() { await client.reload() }
    }

    /// Makes sure the engine is running and answers. Loading the database takes a while the first time.
    public func start(excluding excluded: [URL] = []) async throws {
        guard isInstalled else { throw EngineError.notInstalled }
        if await client.ping() { return }
        guard paths.databaseDate() != nil else { throw EngineError.noDatabase }
        try paths.writeConfigs(excluding: excluded)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Tool.clamd)
        process.arguments = ["--config-file=\(paths.daemonConfig.path)"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // A scan must never download online-only iCloud files; the engine inherits that from here.
        try CloudFiles.withoutDownloads { try process.run() }
        self.process = process

        // Loading the database takes a while the first time; a hung engine gives up after two minutes.
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if await client.ping() { return }
            if process.isRunning == false { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        let tail = (try? String(contentsOf: paths.log, encoding: .utf8))?.suffix(400) ?? ""
        throw EngineError.didNotStart(String(tail))
    }

    public func stop() async {
        if await client.ping() { await client.shutdown() }
        if let process, process.isRunning {
            for _ in 0..<25 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(200))
            }
            if process.isRunning { process.terminate() }
        }
        process = nil
    }
}
