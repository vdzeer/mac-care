import CryptoKit
import Darwin
import Foundation

/// A file or folder with the space it takes.
public struct SpaceNode: Sendable, Identifiable, Equatable {
    public let url: URL
    public let bytes: Int64
    public let isFolder: Bool

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }

    public init(url: URL, bytes: Int64, isFolder: Bool) {
        self.url = url
        self.bytes = bytes
        self.isFolder = isFolder
    }
}

/// A big file, with when it was last read.
public struct LargeFile: Sendable, Identifiable, Equatable {
    public let url: URL
    public let bytes: Int64
    public let lastOpened: Date

    public var id: String { url.path }

    public init(url: URL, bytes: Int64, lastOpened: Date) {
        self.url = url
        self.bytes = bytes
        self.lastOpened = lastOpened
    }
}

/// Files with exactly the same contents.
public struct DuplicateGroup: Sendable, Identifiable, Equatable {
    public let bytes: Int64
    public let files: [URL]

    public var id: String { files.first?.path ?? "" }
    /// The space that would come back if only one copy stayed.
    public var wasted: Int64 { bytes * Int64(max(files.count - 1, 0)) }

    public init(bytes: Int64, files: [URL]) {
        self.bytes = bytes
        self.files = files
    }
}

public enum SpaceScanner {
    /// The direct children of a folder with their sizes, largest first.
    public static func children(of folder: URL) async -> [SpaceNode] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var nodes: [SpaceNode] = []
        await withTaskGroup(of: SpaceNode.self) { tasks in
            var pending = names.makeIterator()
            func addNext() {
                guard let name = pending.next() else { return }
                let url = folder.appendingPathComponent(name)
                tasks.addTask {
                    let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    let usage = DirectorySizer.usage(of: url, isCancelled: { Task.isCancelled })
                    return SpaceNode(url: url, bytes: usage.bytes, isFolder: isFolder)
                }
            }
            for _ in 0..<8 { addNext() }
            for await node in tasks {
                nodes.append(node)
                addNext()
            }
        }
        return nodes.filter { $0.bytes > 0 }.sorted { ($0.bytes, $1.name) > ($1.bytes, $0.name) }
    }

    /// Folder names that are really one thing to the owner; their insides are not listed file by file.
    static let packages: Set<String> = [
        "app", "photoslibrary", "bundle", "framework", "xcarchive", "musiclibrary", "tvlibrary", "imovielibrary",
        "fcpbundle", "logicx", "band", "pages", "numbers", "key",
    ]

    /// Walks the owner's own files: hidden folders, `Library`, and the insides of packages are left out.
    static func walk(_ roots: [URL], isCancelled: () -> Bool, visit: (URL, stat) -> Void) {
        for root in roots {
            guard let path = strdup(root.path) else { continue }
            defer { free(path) }
            var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
            guard let tree = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { continue }
            defer { fts_close(tree) }
            var count = 0
            while let entry = fts_read(tree) {
                count += 1
                if count % 2048 == 0, isCancelled() { return }
                let kind = Int32(entry.pointee.fts_info)
                let name = withUnsafePointer(to: &entry.pointee.fts_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.fts_namelen) + 1) {
                        String(cString: $0)
                    }
                }
                if kind == FTS_D, entry.pointee.fts_level > 0 {
                    let isLibrary = entry.pointee.fts_level == 1 && name == "Library"
                    let suffix = name.split(separator: ".").last.map { String($0).lowercased() } ?? ""
                    if name.hasPrefix(".") || isLibrary || (name.contains(".") && packages.contains(suffix)) {
                        fts_set(tree, entry, FTS_SKIP)
                    }
                    continue
                }
                guard kind == FTS_F, name.hasPrefix(".") == false, let info = entry.pointee.fts_statp?.pointee
                else { continue }
                visit(URL(fileURLWithPath: String(cString: entry.pointee.fts_path)), info)
            }
        }
    }

    /// The biggest files under the given folders, largest first.
    public static func largeFiles(
        in roots: [URL], atLeast minimum: Int64 = 200_000_000, limit: Int = 100,
        isCancelled: () -> Bool = { false }
    ) -> [LargeFile] {
        var found: [LargeFile] = []
        walk(roots, isCancelled: isCancelled) { url, info in
            let bytes = Int64(info.st_blocks) * 512
            guard bytes >= minimum else { return }
            let opened = Date(timeIntervalSince1970: TimeInterval(info.st_atimespec.tv_sec))
            found.append(LargeFile(url: url, bytes: bytes, lastOpened: opened))
        }
        return Array(found.sorted { ($0.bytes, $1.url.path) > ($1.bytes, $0.url.path) }.prefix(limit))
    }

    /// Files with identical contents. Compared by size first, then by a hash of the start, then of the whole file.
    public static func duplicates(
        in roots: [URL], atLeast minimum: Int64 = 1_000_000, isCancelled: () -> Bool = { false }
    ) -> [DuplicateGroup] {
        var bySize: [Int64: [URL]] = [:]
        var devices: [URL: dev_t] = [:]
        var seen = Set<FileIdentity>()
        walk(roots, isCancelled: isCancelled) { url, info in
            // An iCloud file kept only online would be downloaded just to be compared.
            guard info.st_size >= minimum, isDataless(info) == false else { return }
            // Two names for one file (a hard link) are not two copies.
            guard seen.insert(FileIdentity(device: info.st_dev, inode: info.st_ino)).inserted else { return }
            bySize[Int64(info.st_size), default: []].append(url)
            devices[url] = info.st_dev
        }

        var groups: [DuplicateGroup] = []
        for (size, sameSize) in bySize where sameSize.count > 1 {
            if isCancelled() { break }
            for sameStart in Dictionary(grouping: sameSize, by: { hash($0, limit: 65_536) }).values
            where sameStart.count > 1 {
                for (digest, same) in Dictionary(grouping: sameStart, by: { hash($0, limit: nil) })
                where same.count > 1 && digest != nil {
                    let copies = separateCopies(same.sorted { $0.path < $1.path }, devices: devices)
                    if copies.count > 1 { groups.append(DuplicateGroup(bytes: size, files: copies)) }
                }
            }
        }
        return groups.sorted { ($0.wasted, $1.id) > ($1.wasted, $0.id) }
    }

    /// One file of every set of APFS clones: a clone shares its blocks with the original, so the two take the
    /// space of one copy and removing either frees nothing.
    static func separateCopies(_ files: [URL], devices: [URL: dev_t]) -> [URL] {
        struct Content: Hashable {
            let device: dev_t
            let identifier: Int64
        }
        var seen = Set<Content>()
        return files.filter { url in
            guard let device = devices[url],
                let identifier = try? url.resourceValues(forKeys: [.fileContentIdentifierKey]).fileContentIdentifier
            else { return true }
            return seen.insert(Content(device: device, identifier: identifier)).inserted
        }
    }

    /// An iCloud file kept only online: its contents are not on the disk, and reading it downloads them.
    static func isDataless(_ info: stat) -> Bool {
        info.st_flags & UInt32(SF_DATALESS) != 0
    }

    /// Why a chosen copy was left alone, as the report records it.
    public static let changedReason = "changed since the comparison"

    /// The copies of a group that may still go, checked right before they do: since the comparison a file may
    /// have been edited, replaced, removed or left only in iCloud. A copy passes when a file that stays still
    /// has the group's size and the same start, and so does the copy.
    public static func confirmedCopies(_ chosen: [URL], of group: DuplicateGroup) -> [URL] {
        let chosenPaths = Set(chosen.map(\.path))
        let staying = group.files.filter { chosenPaths.contains($0.path) == false }
        guard let reference = staying.lazy.compactMap({ quickPrint($0, size: group.bytes) }).first else { return [] }
        return chosen.filter { quickPrint($0, size: group.bytes) == reference }
    }

    /// A hash of the start of a plain file that is on the disk with the expected size; nil otherwise.
    static func quickPrint(_ url: URL, size: Int64) -> String? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, Int64(info.st_size) == size,
            isDataless(info) == false
        else { return nil }
        return hash(url, limit: 65_536)
    }

    /// SHA-256 of the first `limit` bytes, or of everything. Nil when the file cannot be read.
    static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            guard let chunk = try? handle.read(upToCount: min(remaining, 1_048_576)), chunk.isEmpty == false
            else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The owner picks these files one by one, so the guard is wide: anything in the home folder
    /// except `Library` and the places that hold keys. Removal is always a move to the Trash.
    public static func pathGuard(home: URL) -> PathGuard {
        PathGuard(
            allowedRoots: [home],
            deniedRoots: [
                home.appendingPathComponent("Library"), home.appendingPathComponent(".ssh"),
                home.appendingPathComponent(".gnupg"),
            ],
            deniedComponents: PathGuard.protectedComponents)
    }
}
