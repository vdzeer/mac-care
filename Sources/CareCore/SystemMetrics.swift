import Darwin
import Foundation

/// One reading of how busy the Mac is.
public struct SystemSnapshot: Sendable, Equatable {
    /// Share of all processor cores in use since the previous reading, from 0 to 1.
    public var cpu: Double = 0
    public var memoryUsed: Int64 = 0
    public var memoryTotal: Int64 = 0
    public var pressure: MemoryPressure = .normal
    /// Bytes per second across all network interfaces since the previous reading.
    public var networkIn: Double = 0
    public var networkOut: Double = 0

    public init() {}

    public var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
}

/// How hard macOS has to work to find free memory. This, not "free megabytes", says whether memory is short.
public enum MemoryPressure: Int, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4
}

public struct HeavyProcess: Sendable, Identifiable, Equatable {
    public let pid: Int
    public let name: String
    /// Percent of one core; can exceed 100 on several cores.
    public let cpu: Double
    public let memory: Int64

    public var id: Int { pid }

    public init(pid: Int, name: String, cpu: Double, memory: Int64) {
        self.pid = pid
        self.name = name
        self.cpu = cpu
        self.memory = memory
    }
}

/// Reads the counters and turns the difference between two readings into rates.
public final class SystemMeter: @unchecked Sendable {
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastNetwork: (received: UInt64, sent: UInt64, at: Date)?
    private let lock = NSLock()

    public init() {}

    public func read(at now: Date = Date()) -> SystemSnapshot {
        lock.lock()
        defer { lock.unlock() }
        var snapshot = SystemSnapshot()

        if let ticks = Self.cpuTicks() {
            if let last = lastTicks, ticks.total > last.total {
                snapshot.cpu = Double(ticks.busy - last.busy) / Double(ticks.total - last.total)
            }
            lastTicks = ticks
        }

        (snapshot.memoryUsed, snapshot.memoryTotal) = Self.memory()
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            snapshot.pressure = MemoryPressure(rawValue: Int(level)) ?? .normal
        }

        let counters = Self.networkCounters()
        if let last = lastNetwork {
            let seconds = now.timeIntervalSince(last.at)
            if seconds > 0, counters.received >= last.received, counters.sent >= last.sent {
                snapshot.networkIn = Double(counters.received - last.received) / seconds
                snapshot.networkOut = Double(counters.sent - last.sent) / seconds
            }
        }
        lastNetwork = (counters.received, counters.sent, now)
        return snapshot
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + nice + idle)
    }

    /// Used memory the way Activity Monitor counts it: app memory, wired memory and compressed memory.
    private static func memory() -> (used: Int64, total: Int64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = Int64(sysconf(_SC_PAGESIZE))
        let app = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
        let used = (app + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        return (min(max(used, 0), total), total)
    }

    private static func networkCounters() -> (received: UInt64, sent: UInt64) {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return (0, 0) }
        defer { freeifaddrs(first) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                let data = entry.pointee.ifa_data
            else { continue }
            // The loopback interface only carries the Mac talking to itself.
            if String(cString: entry.pointee.ifa_name).hasPrefix("lo") { continue }
            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(counters.ifi_ibytes)
            sent += UInt64(counters.ifi_obytes)
        }
        return (received, sent)
    }
}

public enum HeavyProcesses {
    /// Reads `ps -Aceo pid=,pcpu=,rss=,comm=`: one line per process.
    public static func parse(_ text: String, limit: Int = 5) -> [HeavyProcess] {
        let processes = text.split(separator: "\n").compactMap { line -> HeavyProcess? in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int(fields[0]),
                let cpu = Double(fields[1].replacingOccurrences(of: ",", with: ".")), let kilobytes = Int64(fields[2])
            else { return nil }
            return HeavyProcess(pid: pid, name: String(fields[3]), cpu: cpu, memory: kilobytes * 1024)
        }
        // Heavy means either: busy on the processor now, or holding a lot of memory.
        let byCPU = processes.sorted { $0.cpu > $1.cpu }.prefix(limit)
        let byMemory = processes.sorted { $0.memory > $1.memory }.prefix(limit)
        var seen = Set<Int>()
        return (Array(byCPU) + Array(byMemory)).filter { seen.insert($0.pid).inserted }
            .sorted { ($0.cpu, $0.memory) > ($1.cpu, $1.memory) }
            .prefix(limit).map { $0 }
    }

    public static func sample(runner: any CommandRunning, limit: Int = 5) async -> [HeavyProcess] {
        guard let result = try? await runner.run(Tool.ps, ["-Aceo", "pid=,pcpu=,rss=,comm="], timeout: 10) else {
            return []
        }
        return parse(result.stdout, limit: limit)
    }
}
