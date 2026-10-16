import Darwin
import Foundation

/// A program that is talking to the network right now.
public struct NetworkProcess: Sendable, Identifiable, Equatable {
    public let pid: Int
    public let name: String
    /// Open connections to another machine.
    public let connections: Int
    /// Ports on which the program waits for others to connect.
    public let listeningPorts: [Int]
    /// A few of the addresses it talks to.
    public let remotes: [String]
    public let bytesIn: Int64
    public let bytesOut: Int64
    /// Bytes per second over the last sample, both directions.
    public var rate: Double = 0
    public var path: String?
    public var signature: SignatureInfo?

    public var id: Int { pid }

    public init(
        pid: Int, name: String, connections: Int, listeningPorts: [Int], remotes: [String], bytesIn: Int64,
        bytesOut: Int64, rate: Double = 0, path: String? = nil, signature: SignatureInfo? = nil
    ) {
        self.pid = pid
        self.name = name
        self.connections = connections
        self.listeningPorts = listeningPorts
        self.remotes = remotes
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.rate = rate
        self.path = path
        self.signature = signature
    }
}

public enum NetworkActivity {
    /// Reads `nettop -L 1 -x -n -J bytes_in,bytes_out`: a line per program, then a line per socket it holds.
    public static func parse(_ text: String) -> [NetworkProcess] {
        struct Draft {
            var pid: Int
            var name: String
            var bytesIn: Int64
            var bytesOut: Int64
            var connections = 0
            var listening = Set<Int>()
            var remotes: [String] = []
        }
        var drafts: [Draft] = []
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard let head = fields.first, head.isEmpty == false else { continue }
            let isSocket = ["tcp4 ", "tcp6 ", "udp4 ", "udp6 "].contains { head.hasPrefix($0) }
            if isSocket {
                guard drafts.isEmpty == false, let arrow = head.range(of: "<->") else { continue }
                let local = String(head[head.index(head.startIndex, offsetBy: 5)..<arrow.lowerBound])
                let remote = String(head[arrow.upperBound...])
                if remote.hasPrefix("*") {
                    if head.hasPrefix("tcp"), let port = port(of: local) {
                        drafts[drafts.count - 1].listening.insert(port)
                    }
                } else {
                    drafts[drafts.count - 1].connections += 1
                    let host = address(of: remote)
                    if drafts[drafts.count - 1].remotes.contains(host) == false {
                        drafts[drafts.count - 1].remotes.append(host)
                    }
                }
            } else if let dot = head.lastIndex(of: "."), let pid = Int(head[head.index(after: dot)...]) {
                drafts.append(
                    Draft(
                        pid: pid, name: String(head[..<dot]), bytesIn: Int64(fields.dropFirst().first ?? "") ?? 0,
                        bytesOut: Int64(fields.dropFirst(2).first ?? "") ?? 0))
            }
        }
        return drafts.map {
            NetworkProcess(
                pid: $0.pid, name: $0.name, connections: $0.connections, listeningPorts: $0.listening.sorted(),
                remotes: Array($0.remotes.prefix(3)), bytesIn: $0.bytesIn, bytesOut: $0.bytesOut)
        }
    }

    /// "192.168.1.5:443" and "fe80::1.443" both end in the port.
    static func port(of endpoint: String) -> Int? {
        guard let separator = endpoint.lastIndex(where: { $0 == ":" || $0 == "." }) else { return nil }
        return Int(endpoint[endpoint.index(after: separator)...])
    }

    static func address(of endpoint: String) -> String {
        guard let separator = endpoint.lastIndex(where: { $0 == ":" || $0 == "." }),
            Int(endpoint[endpoint.index(after: separator)...]) != nil
        else { return endpoint }
        return String(endpoint[..<separator])
    }

    /// The programs that hold a connection or wait for one, busiest first.
    /// Rates come from the difference between this reading and `previous`, taken `interval` seconds ago.
    public static func active(
        _ processes: [NetworkProcess], previous: [NetworkProcess] = [], interval: TimeInterval = 1,
        inspect: (Int) -> (path: String?, signature: SignatureInfo?) = { _ in (nil, nil) }
    ) -> [NetworkProcess] {
        let before = Dictionary(
            previous.map { ($0.pid, $0.bytesIn + $0.bytesOut) }, uniquingKeysWith: { first, _ in first })
        return processes.filter { $0.connections > 0 || $0.listeningPorts.isEmpty == false }
            .map { process in
                var process = process
                if let earlier = before[process.pid], interval > 0 {
                    process.rate = max(Double(process.bytesIn + process.bytesOut - earlier), 0) / interval
                }
                let facts = inspect(process.pid)
                process.path = facts.path
                process.signature = facts.signature
                return process
            }
            .sorted { ($0.rate, $0.connections, $1.name) > ($1.rate, $1.connections, $0.name) }
    }

    public static func sample(runner: any CommandRunning) async -> [NetworkProcess] {
        let arguments = ["-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out"]
        guard let result = try? await runner.run(Tool.nettop, arguments, timeout: 15) else { return [] }
        return parse(result.stdout)
    }

    /// Where the program of a running process lives on disk.
    public static func path(ofProcess pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
