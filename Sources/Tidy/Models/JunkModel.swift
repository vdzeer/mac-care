import AppKit
import CareCore
import CareUI
import Observation

/// What the Junk screen and the overview know about junk: the measurement, the ticks, the cleanup.
@Observable final class JunkModel {
    enum Phase: Equatable { case idle, measuring, ready, cleaning, finished }

    private(set) var phase: Phase = .idle
    private(set) var measuredAt: Date?
    private(set) var report: RemovalReport?
    /// What emptying the Trash after the cleanup removed; nil until the owner asks for it.
    private(set) var trashReport: RemovalReport?
    /// The Trash was empty or out of sight when the owner asked to empty it: without Full Disk Access Tidy
    /// cannot look inside.
    private(set) var trashOutOfSight = false
    private(set) var stepsDone = 0
    private(set) var stepsTotal = 0
    var selection = JunkSelection()
    var expanded: Set<JunkRule.ID> = []
    var isSheetShown = false
    var isJournalShown = false
    /// Called after a cleanup or Empty Trash removed something, so the disk figures can be read again.
    @ObservationIgnored var onDiskChange: () -> Void = {}

    private var arrived: [JunkRule.ID: JunkGroup] = [:]
    private let rules: [JunkRule]
    private let home: URL
    private let runner: any CommandRunning
    let journal: CleanupJournal

    init(home: URL, runner: any CommandRunning, journal: CleanupJournal) {
        self.home = home
        self.runner = runner
        self.journal = journal
        self.rules = JunkRules.all(home: home)
    }

    /// A model that already holds a finished measurement. For snapshots.
    convenience init(preview scan: JunkScan, home: URL) {
        self.init(home: home, runner: SystemCommandRunner(), journal: CleanupJournal(fileURL: home))
        arrived = Dictionary(uniqueKeysWithValues: scan.groups.map { ($0.id, $0) })
        selection = .initial(for: scan)
        phase = .ready
        measuredAt = Date()
    }

    /// Shows a finished cleanup without running one. For snapshots.
    func previewFinished(_ report: RemovalReport) {
        self.report = report
        phase = .finished
    }

    /// Groups in the fixed order of the rules, so rows never move while the owner works with them.
    var scan: JunkScan { JunkScan(groups: rules.compactMap { arrived[$0.id] }) }
    var plan: JunkPlan { JunkMath.plan(scan, selection) }
    var isMeasuring: Bool { phase == .measuring }

    /// While measuring, the sum of what has arrived so far; afterwards, what is ticked.
    var headlineBytes: Int64 {
        isMeasuring ? scan.groups(of: .regenerates).reduce(0) { $0 + $1.bytes } : plan.bytes
    }

    func checkState(of group: JunkGroup) -> CheckState {
        switch selection.state(of: group) {
        case .none: .off
        case .some: .mixed
        case .all: .on
        }
    }

    /// The apps open right now: bundle ids, and names in lower case.
    private static func openApps() -> (bundleIDs: Set<String>, names: Set<String>) {
        let apps = NSWorkspace.shared.runningApplications
        let names = apps.flatMap { [$0.localizedName, $0.executableURL?.lastPathComponent].compactMap { $0 } }
        return (Set(apps.compactMap(\.bundleIdentifier)), Set(names.map { $0.lowercased() }))
    }

    func measure() async {
        guard phase != .measuring, phase != .cleaning else { return }
        let before = scan
        phase = .measuring
        arrived = [:]
        let open = Self.openApps()
        let scanner = JunkScanner(
            home: home, runner: runner, runningBundleIDs: open.bundleIDs, runningAppNames: open.names)
        let result = await scanner.scan { [weak self] group in
            Task { @MainActor in
                guard let self, self.phase == .measuring else { return }
                self.arrived[group.id] = group
            }
        }
        arrived = Dictionary(uniqueKeysWithValues: result.groups.map { ($0.id, $0) })
        // What the owner ticked or unticked before stays so; only new items get the default.
        selection = .carried(selection, from: before, to: result)
        measuredAt = Date()
        phase = .ready
    }

    func clean() async {
        guard phase == .ready, plan.isEmpty == false else { return }
        // The measurement can be hours old: what an app opened since is using stays where it is.
        let open = Self.openApps()
        let checked = JunkMath.recheck(
            plan.items, rules: rules, runningBundleIDs: open.bundleIDs, runningAppNames: open.names)
        let requests = checked.safe.map(\.removalRequest)
        stepsDone = 0
        stepsTotal = requests.count
        phase = .cleaning
        let remover = Remover(pathGuard: JunkRules.pathGuard(home: home), runner: runner)
        let report = await remover.remove(requests, dryRun: false) { [weak self] _ in
            Task { @MainActor in self?.stepsDone += 1 }
        }
        .adding(skipped: checked.blocked.map(\.removalRequest), because: JunkMath.openAppReason)
        try? journal.record(report)
        if report.changedTheDisk { onDiskChange() }
        self.report = report
        trashReport = nil
        trashOutOfSight = false
        stepsDone = stepsTotal
        phase = .finished
    }

    /// After a cleanup that moved things to the Trash: measures the Trash as it is now and empties it, so the
    /// space really comes back. Everything in the Trash goes, not only what Tidy put there; the sheet says so.
    func emptyTrash() async {
        guard phase == .finished, trashReport == nil else { return }
        phase = .cleaning
        let scan = await JunkScanner(home: home, runner: runner).scan(only: [.trash])
        let requests = scan.items.map(\.removalRequest)
        stepsDone = 0
        stepsTotal = requests.count
        let remover = Remover(pathGuard: JunkRules.pathGuard(home: home), runner: runner)
        let emptied = await remover.remove(requests, dryRun: false) { [weak self] _ in
            Task { @MainActor in self?.stepsDone += 1 }
        }
        try? journal.record(emptied)
        if emptied.changedTheDisk { onDiskChange() }
        trashReport = emptied
        trashOutOfSight = requests.isEmpty
        stepsDone = stepsTotal
        phase = .finished
    }

    /// Closes the result and measures again, so the numbers match the disk.
    func acknowledge() async {
        isSheetShown = false
        phase = .idle
        report = nil
        trashReport = nil
        trashOutOfSight = false
        await measure()
    }
}
