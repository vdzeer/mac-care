import Darwin
import Foundation

public struct DiskUsage: Sendable, Equatable {
    public var bytes: Int64
    public var files: Int

    public init(bytes: Int64 = 0, files: Int = 0) {
        self.bytes = bytes
        self.files = files
    }

    public static func + (lhs: DiskUsage, rhs: DiskUsage) -> DiskUsage {
        DiskUsage(bytes: lhs.bytes + rhs.bytes, files: lhs.files + rhs.files)
    }
}

/// Measures space on disk the way `du` does: allocated blocks, hard links counted once,
/// symbolic links not followed, other volumes not entered.
public enum DirectorySizer {
    public static func usage(of url: URL, isCancelled: () -> Bool = { false }) -> DiskUsage {
        guard let path = strdup(url.path) else { return DiskUsage() }
        defer { free(path) }
        var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
        guard let tree = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return DiskUsage() }
        defer { fts_close(tree) }

        var usage = DiskUsage()
        var seenLinks = Set<FileIdentity>()
        var visited = 0
        while let entry = fts_read(tree) {
            visited += 1
            if visited % 4096 == 0, isCancelled() { break }
            let kind = Int32(entry.pointee.fts_info)
            guard kind == FTS_F || kind == FTS_D || kind == FTS_SL || kind == FTS_SLNONE || kind == FTS_DEFAULT,
                let stat = entry.pointee.fts_statp?.pointee
            else { continue }
            if kind != FTS_D, stat.st_nlink > 1 {
                let identity = FileIdentity(device: stat.st_dev, inode: stat.st_ino)
                if seenLinks.insert(identity).inserted == false { continue }
            }
            usage.bytes += Int64(stat.st_blocks) * 512
            if kind == FTS_F { usage.files += 1 }
        }
        return usage
    }
}

struct FileIdentity: Hashable {
    let device: dev_t
    let inode: ino_t
}
