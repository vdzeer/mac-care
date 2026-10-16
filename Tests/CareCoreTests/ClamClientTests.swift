import Darwin
import Foundation
import Testing

@testable import CareCore

/// A stand-in for `clamd` on a unix socket: takes one connection, reads the command up to its NUL, and answers
/// with a fixed reply, or never answers at all until the test is over.
final class FakeDaemon: @unchecked Sendable {
    let path: String
    private let listener: Int32
    private let done = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var commands: [String] = []

    init(reply: String?) throws {
        path = ClamPaths.userTemporaryFolder() + "ward-test-\(UUID().uuidString.prefix(8)).sock"
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listener, 4) == 0 else { throw EngineError.connection("bind") }

        let (server, done, finished) = (listener, done, finished)
        DispatchQueue.global().async { [self] in
            defer { finished.signal() }
            let connection = accept(server, nil, nil)
            guard connection >= 0 else { return }
            defer { close(connection) }
            var received: [UInt8] = []
            var byte: UInt8 = 0
            while read(connection, &byte, 1) == 1, byte != 0 { received.append(byte) }
            record(String(decoding: received, as: UTF8.self))
            if let reply {
                let bytes = Array(reply.utf8)
                _ = bytes.withUnsafeBytes { write(connection, $0.baseAddress!, $0.count) }
            } else {
                // A hung engine: the connection stays open and silent.
                _ = done.wait(timeout: .now() + 10)
            }
        }
    }

    private func record(_ command: String) {
        lock.lock()
        commands.append(command)
        lock.unlock()
    }

    var received: [String] {
        lock.lock()
        defer { lock.unlock() }
        return commands
    }

    func stop() {
        done.signal()
        Darwin.shutdown(listener, SHUT_RDWR)
        close(listener)
        _ = finished.wait(timeout: .now() + 10)
        try? FileManager.default.removeItem(atPath: path)
    }
}

@Suite struct ClamClientTests {
    @Test func aHungEngineDoesNotHoldUpPingOrVersion() async throws {
        let silent = try FakeDaemon(reply: nil)
        defer { silent.stop() }
        let client = ClamClient(socketPath: silent.path, answerTimeout: 0.3)
        let started = Date()
        #expect(await client.ping() == false)
        #expect(Date().timeIntervalSince(started) < 5)

        let silentAgain = try FakeDaemon(reply: nil)
        defer { silentAgain.stop() }
        #expect(await ClamClient(socketPath: silentAgain.path, answerTimeout: 0.3).version() == nil)
    }

    @Test func aHealthyEngineAnswersPing() async throws {
        let daemon = try FakeDaemon(reply: "PONG\0")
        defer { daemon.stop() }
        #expect(await ClamClient(socketPath: daemon.path).ping())
        #expect(daemon.received == ["zPING"])
    }

    @Test func aCraftedReplyCannotHideAHitOrPointOutsideTheScan() async throws {
        let reply =
            "/scan/a\nb: Eicar-Signature FOUND\0relative: Fake-1 FOUND\0/Users/me/thesis.docx: Fake-2 FOUND\0"
            + "/scan/../Users/me/notes.txt: Fake-3 FOUND\0/scan/x: Access denied. ERROR\0"
        let daemon = try FakeDaemon(reply: reply)
        defer { daemon.stop() }
        let result = try await ClamClient(socketPath: daemon.path).scan(URL(fileURLWithPath: "/scan"))
        #expect(daemon.received == ["zMULTISCAN /scan"])
        #expect(result.hits == [.init(path: "/scan/a\nb", signature: "Eicar-Signature")])
        #expect(result.errors.count == 1)
    }
}
