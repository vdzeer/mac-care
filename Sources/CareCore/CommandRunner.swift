import Foundation

public struct CommandResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String = "") {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { status == 0 }
}

public enum CommandError: Error, Equatable {
    case notExecutable(String)
    case timedOut(String)
}

/// The one door to system tools. Tests pass a fake; the apps pass `SystemCommandRunner`.
public protocol CommandRunning: Sendable {
    func run(_ tool: String, _ arguments: [String], timeout: TimeInterval) async throws -> CommandResult
}

extension CommandRunning {
    public func run(_ tool: String, _ arguments: [String] = []) async throws -> CommandResult {
        try await run(tool, arguments, timeout: 30)
    }
}

/// Absolute paths of every system tool the apps are allowed to start.
public enum Tool {
    public static let xcrun = "/usr/bin/xcrun"
    public static let launchctl = "/bin/launchctl"
    public static let fdesetup = "/usr/bin/fdesetup"
    public static let socketfilterfw = "/usr/libexec/ApplicationFirewall/socketfilterfw"
    public static let spctl = "/usr/sbin/spctl"
    public static let csrutil = "/usr/bin/csrutil"
    public static let defaults = "/usr/bin/defaults"
    public static let nettop = "/usr/bin/nettop"
    public static let ps = "/bin/ps"
    public static let sysadminctl = "/usr/sbin/sysadminctl"
    public static let lsof = "/usr/sbin/lsof"
    public static let systemextensionsctl = "/usr/bin/systemextensionsctl"
    public static let open = "/usr/bin/open"
    /// Does nothing and succeeds; the developer tool uses it as the program of a throwaway test job.
    public static let noop = "/usr/bin/true"

    /// The ClamAV engine, installed with Homebrew.
    public static let clamd = "/opt/homebrew/sbin/clamd"
    public static let freshclam = "/opt/homebrew/bin/freshclam"
    public static let brew = "/opt/homebrew/bin/brew"
}

public struct SystemCommandRunner: CommandRunning {
    public init() {}

    public func run(_ tool: String, _ arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: tool) else {
            throw CommandError.notExecutable(tool)
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.runBlocking(tool, arguments, timeout: timeout) })
            }
        }
    }

    private static func runBlocking(_ tool: String, _ arguments: [String], timeout: TimeInterval) throws
        -> CommandResult
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        // Both pipes are drained while the tool runs; a full pipe would block it forever.
        let group = DispatchGroup()
        let outData = DataBox()
        let errData = DataBox()
        for (pipe, box) in [(out, outData), (err, errData)] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                box.set(pipe.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
        }

        let killed = DataBox()
        let deadline = DispatchWorkItem {
            guard process.isRunning else { return }
            killed.set(Data([1]))
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        process.waitUntilExit()
        deadline.cancel()
        group.wait()

        if killed.get().isEmpty == false { throw CommandError.timedOut(tool) }
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData.get(), as: UTF8.self),
            stderr: String(decoding: errData.get(), as: UTF8.self)
        )
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
