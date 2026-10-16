import Foundation

public struct VolumeInfo: Sendable, Equatable {
    public let name: String
    public let total: Int64
    public let free: Int64

    public init(name: String, total: Int64, free: Int64) {
        self.name = name
        self.total = total
        self.free = free
    }

    public var used: Int64 { max(total - free, 0) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// The startup volume, with free space counted the way Finder counts it.
    public static func startup() -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
            let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return VolumeInfo(name: values.volumeName ?? "/", total: Int64(total), free: free)
    }
}
