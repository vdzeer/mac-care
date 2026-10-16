import AppKit
import CareCore
import Observation

/// What the Apps screen knows: installed apps with their footprints, and leftovers of removed ones.
@Observable final class AppsModel {
    enum Mode: Hashable { case installed, orphans }
    enum Phase: Equatable { case idle, loading, ready }

    var mode: Mode = .installed {
        didSet { if mode == .orphans, orphans == nil, isPreview == false { Task { await findOrphans() } } }
    }
    var search = ""
    private(set) var phase: Phase = .idle
    private(set) var footprints: [AppFootprint] = []
    private(set) var orphans: [OrphanGroup]?
    private(set) var isWorking = false
    private(set) var lastReport: RemovalReport?
    var selectedID: String?
    /// Parts the owner unticked for the selected app or leftover group.
    var unticked: Set<String> = []
    /// Called after an uninstall moved something, so the disk figures can be read again.
    @ObservationIgnored var onDiskChange: () -> Void = {}

    private let finder: LeftoverFinder
    private let journal: CleanupJournal
    private let runner: any CommandRunning
    private var icons: [String: NSImage] = [:]
    /// A preview holds fixed sample data and never reads the disk.
    private var isPreview = false

    init(finder: LeftoverFinder, journal: CleanupJournal, runner: any CommandRunning) {
        self.finder = finder
        self.journal = journal
        self.runner = runner
    }

    convenience init(preview footprints: [AppFootprint], orphans: [OrphanGroup], finder: LeftoverFinder) {
        self.init(finder: finder, journal: CleanupJournal(fileURL: finder.home), runner: SystemCommandRunner())
        self.footprints = footprints
        self.orphans = orphans
        self.phase = .ready
        self.isPreview = true
    }

    var visibleFootprints: [AppFootprint] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard query.isEmpty == false else { return footprints }
        return footprints.filter { $0.app.name.localizedCaseInsensitiveContains(query) }
    }

    var selectedFootprint: AppFootprint? { footprints.first { $0.app.id == selectedID } }
    var selectedOrphan: OrphanGroup? { orphans?.first { $0.id == selectedID } }

    func isRunning(_ app: InstalledApp) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty == false
    }

    func icon(for app: InstalledApp) -> NSImage? {
        if let cached = icons[app.id] { return cached }
        guard FileManager.default.fileExists(atPath: app.url.path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        icons[app.id] = image
        return image
    }

    func select(_ id: String) {
        selectedID = id
        if mode == .orphans {
            unticked = orphans?.first { $0.id == id }?.initiallyUnticked ?? []
        } else {
            unticked = footprints.first { $0.app.id == id }?.initiallyUnticked ?? []
        }
        lastReport = nil
    }

    func load() async {
        guard phase != .loading, isPreview == false else { return }
        phase = .loading
        let finder = finder
        let measured = await Task.detached { () -> [AppFootprint] in
            let apps = AppInventory.apps(in: finder.applicationFolders)
            return await withTaskGroup(of: AppFootprint.self) { group in
                for app in apps { group.addTask { finder.footprint(of: app, among: apps) } }
                var all: [AppFootprint] = []
                for await footprint in group { all.append(footprint) }
                return all
            }
        }.value
        // Sorted once, here; the list then keeps its order while the owner works with it.
        footprints = measured.sorted { ($0.bytes, $1.app.name) > ($1.bytes, $0.app.name) }
        orphans = nil
        if mode == .orphans { await findOrphans() }
        phase = .ready
    }

    private func findOrphans() async {
        let finder = finder
        let installed = footprints.map(\.app)
        orphans = await Task.detached { finder.orphans(installed: installed) }.value
    }

    /// Moves the ticked parts of the selection to the Trash, the app itself first.
    func removeSelection() async {
        let parts: [AppPart]
        let owner: String
        if mode == .installed, let footprint = selectedFootprint {
            guard isRunning(footprint.app) == false else { return }
            (parts, owner) = (footprint.parts, footprint.app.name)
        } else if mode == .orphans, let group = selectedOrphan {
            (parts, owner) = (group.parts, group.bundleID)
        } else {
            return
        }
        let chosen = parts.filter { unticked.contains($0.id) == false }
        guard chosen.isEmpty == false else { return }

        isWorking = true
        let remover = Remover(pathGuard: finder.pathGuard, runner: runner)
        let report = await remover.uninstall(chosen, owner: owner, dryRun: false)
        try? journal.record(report)
        if report.changedTheDisk { onDiskChange() }
        isWorking = false
        selectedID = nil
        unticked = []
        await load()
        lastReport = report
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
