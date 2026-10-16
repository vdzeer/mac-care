import Foundation

/// One of the places macOS adds up under "System Data": a folder with its size and what it is.
public struct SystemDataPlace: Sendable, Identifiable, Equatable {
    public enum Group: String, Sendable, CaseIterable {
        /// Tools for building software.
        case developer
        /// Data that apps keep outside the owner's own folders.
        case apps
        /// What macOS manages itself.
        case system
    }

    /// What the place is, when it is one the app knows by name.
    public enum Known: String, Sendable {
        case xcode, androidSDK, gradle, npm, yarn, nuget, androidHome, cliCache, ollama, nodeVersions, cocoaPods
        case editor, assistant, toolData, homebrew, hiddenFolder
        case appCaches, wallpapers, docker, appleData, appData, container
        case trash, swap, temporary, systemLogs, systemDatabases, systemCaches, shared
    }

    public let url: URL
    public let group: Group
    public let known: Known
    public let bytes: Int64

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }

    public init(url: URL, group: Group, known: Known, bytes: Int64) {
        self.url = url
        self.group = group
        self.known = known
        self.bytes = bytes
    }

    /// Whether the place belongs to macOS or to a tool that must clean it itself; such places are only shown.
    public var isManaged: Bool {
        switch known {
        case .swap, .temporary, .systemLogs, .systemDatabases, .systemCaches, .appleData, .docker: true
        default: false
        }
    }
}

public struct SystemDataScanner: Sendable {
    public let home: URL
    /// The root of the disk; tests point it at a temporary folder.
    public let root: URL
    /// A place smaller than this is not worth a row.
    public let minimum: Int64

    public init(home: URL, root: URL = URL(fileURLWithPath: "/"), minimum: Int64 = 100_000_000) {
        self.home = home
        self.root = root
        self.minimum = minimum
    }

    static let hiddenFolders: [String: SystemDataPlace.Known] = [
        ".gradle": .gradle, ".npm": .npm, ".yarn": .yarn, ".nuget": .nuget, ".android": .androidHome,
        ".cache": .cliCache, ".ollama": .ollama, ".nvm": .nodeVersions, ".cocoapods": .cocoaPods,
        ".vscode": .editor, ".cursor": .editor, ".antigravity": .editor, ".antigravity-ide": .editor,
        ".claude": .assistant, ".codex": .assistant, ".gemini": .assistant, ".local": .toolData,
        ".config": .toolData, ".Trash": .trash,
    ]

    /// Measures every place. Sizes of folders the app may not read come out smaller than they are.
    public func places() async -> [SystemDataPlace] {
        var candidates: [(URL, SystemDataPlace.Group, SystemDataPlace.Known)] = []
        func children(_ relative: String) -> [URL] {
            let folder = relative.isEmpty ? home : home.appendingPathComponent(relative)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.sorted().map { folder.appendingPathComponent($0) }
        }
        func isFolder(_ url: URL) -> Bool {
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        }

        for url in children("") where url.lastPathComponent.hasPrefix(".") && isFolder(url) {
            let known = Self.hiddenFolders[url.lastPathComponent] ?? .hiddenFolder
            candidates.append((url, known == .trash ? .system : .developer, known))
        }
        candidates.append((home.appendingPathComponent("Library/Developer"), .developer, .xcode))
        candidates.append((home.appendingPathComponent("Library/Android"), .developer, .androidSDK))
        candidates.append((root.appendingPathComponent("opt/homebrew"), .developer, .homebrew))

        candidates.append((home.appendingPathComponent("Library/Caches"), .apps, .appCaches))
        for url in children("Library/Application Support") where isFolder(url) {
            let name = url.lastPathComponent
            let known: SystemDataPlace.Known =
                name == "com.apple.wallpaper" ? .wallpapers : name.hasPrefix("com.apple.") ? .appleData : .appData
            candidates.append((url, .apps, known))
        }
        for url in children("Library/Containers") + children("Library/Group Containers") where isFolder(url) {
            let name = url.lastPathComponent
            let isApple = name.hasPrefix("com.apple.") || name.hasPrefix("group.com.apple.")
            let isDocker = name.hasPrefix("com.docker.") || name.hasPrefix("group.com.docker")
            candidates.append((url, .apps, isDocker ? .docker : isApple ? .appleData : .container))
        }

        candidates.append((root.appendingPathComponent("private/var/vm"), .system, .swap))
        candidates.append((root.appendingPathComponent("private/var/folders"), .system, .temporary))
        candidates.append((root.appendingPathComponent("private/var/log"), .system, .systemLogs))
        candidates.append((root.appendingPathComponent("private/var/db"), .system, .systemDatabases))
        candidates.append((root.appendingPathComponent("Library/Caches"), .system, .systemCaches))
        candidates.append((root.appendingPathComponent("Users/Shared"), .system, .shared))

        var found: [SystemDataPlace] = []
        await withTaskGroup(of: SystemDataPlace.self) { tasks in
            var pending = candidates.makeIterator()
            func addNext() {
                guard let (url, group, known) = pending.next() else { return }
                tasks.addTask {
                    let usage = DirectorySizer.usage(of: url, isCancelled: { Task.isCancelled })
                    return SystemDataPlace(url: url, group: group, known: known, bytes: usage.bytes)
                }
            }
            for _ in 0..<8 { addNext() }
            for await place in tasks {
                found.append(place)
                addNext()
            }
        }
        return found.filter { $0.bytes >= minimum }.sorted { ($0.bytes, $1.url.path) > ($1.bytes, $0.url.path) }
    }

    /// How much of a place the junk rules can remove: the items of the measurement that lie inside it.
    public static func cleanable(in place: SystemDataPlace, _ scan: JunkScan) -> Int64 {
        let prefix = place.url.path + "/"
        return scan.items.reduce(Int64(0)) { total, item in
            guard let first = item.urls.first, first.path.hasPrefix(prefix) else { return total }
            return total + item.bytes
        }
    }
}
