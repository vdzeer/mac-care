import AppKit
import CareCore
import Foundation
import Observation

/// What the Space screen knows: the map of a folder, big files, and exact copies.
@Observable final class SpaceModel {
    enum Tab: Hashable { case map, large, duplicates, system }

    var tab: Tab = .map {
        didSet {
            guard isPreview == false else { return }
            if tab == .large, largeFiles == nil { scanLarge() }
            if tab == .duplicates, duplicates == nil { scanDuplicates() }
            if tab == .system, systemPlaces == nil { scanSystem() }
        }
    }
    private(set) var folder: URL
    private(set) var trail: [URL] = []
    private(set) var nodes: [SpaceNode] = []
    private(set) var isLoadingMap = false
    private(set) var largeFiles: [LargeFile]?
    private(set) var duplicates: [DuplicateGroup]?
    /// The places macOS counts as "System Data"; nil until they are measured.
    private(set) var systemPlaces: [SystemDataPlace]?
    private(set) var hasFullDiskAccess = true
    private(set) var isWorking = false
    private(set) var lastReport: RemovalReport?
    /// Paths of the files the owner has ticked for the Trash.
    var ticked: Set<String> = []
    /// Called after files went to the Trash, so the disk figures can be read again.
    @ObservationIgnored var onDiskChange: () -> Void = {}

    let home: URL
    private let journal: CleanupJournal
    private let runner: any CommandRunning
    private var cache: [String: [SpaceNode]] = [:]
    private var isPreview = false

    init(home: URL, journal: CleanupJournal, runner: any CommandRunning) {
        self.home = home
        self.folder = home
        self.journal = journal
        self.runner = runner
    }

    func setPreview(
        nodes: [SpaceNode], large: [LargeFile], duplicates: [DuplicateGroup], system: [SystemDataPlace]
    ) {
        self.nodes = nodes
        largeFiles = large
        self.duplicates = duplicates
        systemPlaces = system
        isPreview = true
    }

    var folderBytes: Int64 { nodes.reduce(0) { $0 + $1.bytes } }
    var isAtHome: Bool { folder.path == home.path }

    var tickedBytes: Int64 {
        let large = (largeFiles ?? []).filter { ticked.contains($0.id) }.reduce(Int64(0)) { $0 + $1.bytes }
        let copies = (duplicates ?? []).reduce(Int64(0)) { total, group in
            total + group.bytes * Int64(group.files.filter { ticked.contains($0.path) }.count)
        }
        return tab == .large ? large : copies
    }

    func loadMap() async {
        guard isPreview == false else { return }
        hasFullDiskAccess = FullDiskAccess.isGranted(home: home)
        if let cached = cache[folder.path] {
            nodes = cached
            return
        }
        isLoadingMap = true
        let target = folder
        let found = await SpaceScanner.children(of: target)
        cache[target.path] = found
        if folder.path == target.path { nodes = found }
        isLoadingMap = false
    }

    func open(_ node: SpaceNode) async {
        guard node.isFolder else {
            reveal(node.url)
            return
        }
        trail.append(folder)
        folder = node.url
        nodes = []
        await loadMap()
    }

    func back() async {
        guard let previous = trail.popLast() else { return }
        folder = previous
        await loadMap()
    }

    func pickFolder() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        trail = []
        folder = url
        nodes = []
        await loadMap()
    }

    private func scanLarge() {
        let home = home
        Task {
            largeFiles = await Task.detached { SpaceScanner.largeFiles(in: [home]) }.value
        }
    }

    private func scanDuplicates() {
        let home = home
        Task {
            duplicates = await Task.detached { SpaceScanner.duplicates(in: [home]) }.value
        }
    }

    func scanSystem() {
        guard isPreview == false else { return }
        let home = home
        systemPlaces = nil
        hasFullDiskAccess = FullDiskAccess.isGranted(home: home)
        Task {
            systemPlaces = await SystemDataScanner(home: home).places()
        }
    }

    func toggle(_ path: String) {
        if ticked.remove(path) == nil { ticked.insert(path) }
    }

    /// Ticks every copy of a group except the first, so exactly one stays.
    func keepOne(of group: DuplicateGroup) {
        ticked.subtract(group.files.map(\.path))
        ticked.formUnion(group.files.dropFirst().map(\.path))
    }

    func trashTicked() async {
        guard isWorking == false else { return }
        isWorking = true
        defer { isWorking = false }
        var requests: [RemovalRequest] = []
        var changed: [RemovalRequest] = []
        if tab == .large {
            requests = (largeFiles ?? []).filter { ticked.contains($0.id) }.map {
                RemovalRequest(
                    id: $0.id, kind: "largeFile", name: $0.url.lastPathComponent, urls: [$0.url], bytes: $0.bytes,
                    removal: .trash)
            }
        } else if tab == .duplicates {
            let picks = (duplicates ?? []).map { group in
                // At least one copy of every group always stays, whatever is ticked.
                let chosen = group.files.filter { ticked.contains($0.path) }
                return (group, chosen.count == group.files.count ? Array(chosen.dropFirst()) : chosen)
            }
            // Compared again right before they go: a file may have changed since the comparison.
            let confirmed = await Task.detached {
                picks.map { group, removable in Set(SpaceScanner.confirmedCopies(removable, of: group).map(\.path)) }
            }.value
            for ((group, removable), passed) in zip(picks, confirmed) {
                for url in removable {
                    let request = RemovalRequest(
                        id: url.path, kind: "duplicate", name: url.lastPathComponent, urls: [url], bytes: group.bytes,
                        removal: .trash)
                    if passed.contains(url.path) { requests.append(request) } else { changed.append(request) }
                }
            }
        }
        guard requests.isEmpty == false || changed.isEmpty == false else { return }
        let remover = Remover(pathGuard: SpaceScanner.pathGuard(home: home), runner: runner)
        let report = await remover.remove(requests, dryRun: false)
            .adding(skipped: changed, because: SpaceScanner.changedReason)
        try? journal.record(report)
        if report.changedTheDisk { onDiskChange() }
        let gone = Set(report.removed.map(\.id))
        largeFiles = largeFiles?.filter { gone.contains($0.id) == false }
        duplicates = duplicates?.compactMap { group in
            let left = group.files.filter { gone.contains($0.path) == false }
            return left.count > 1 ? DuplicateGroup(bytes: group.bytes, files: left) : nil
        }
        // A copy that changed is no longer known to be a copy: it is unticked, and the result says it stayed.
        ticked.subtract(gone.union(changed.map(\.id)))
        cache = [:]
        lastReport = report
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
