import Foundation

@testable import CareCore

/// A throwaway folder that stands in for a home directory. Tests never touch the real one.
final class TempHome {
    let url: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        url = base.appendingPathComponent("care-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ relative: String) -> URL {
        url.appendingPathComponent(relative)
    }

    @discardableResult
    func file(_ relative: String, bytes: Int = 4096) throws -> URL {
        let target = path(relative)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: target)
        return target
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let target = path(relative)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: path(relative).path)
    }
}

/// Answers commands from a table instead of starting them.
struct FakeRunner: CommandRunning {
    var answers: [String: CommandResult] = [:]

    func run(_ tool: String, _ arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        let key = ([tool] + arguments).joined(separator: " ")
        guard let answer = answers[key] else { throw CommandError.notExecutable(key) }
        return answer
    }
}
