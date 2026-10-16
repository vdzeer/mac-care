import AppKit
import CareCore
import Foundation
import Observation

/// What the Scan screen knows: the running check, its findings, and the quarantine.
@Observable final class ShieldModel {
    enum Phase: Equatable { case idle, preparing(EngineHost.Stage), scanning, failed(String) }
    enum Tab: Hashable { case result, quarantine }
    /// Why an action on a finding or a quarantined file did not work.
    enum Problem: Equatable { case move, turnOff, taken, restore, delete }

    var tab: Tab = .result
    private(set) var phase: Phase = .idle
    private(set) var progress: ScanProgress?
    private(set) var result: ScanResult?
    private(set) var scope: ScanScope = .quick
    private(set) var findings: [Finding] = []
    private(set) var entries: [QuarantineStore.Entry] = []
    /// Why an action on a finding or a quarantined file did not work, by its id.
    private(set) var problems: [String: Problem] = [:]
    /// Findings and quarantined files with an action under way, by id.
    private(set) var working: Set<String> = []
    private(set) var hasFullDiskAccess = true
    private(set) var lastScanDate: Date?
    private(set) var lastScanFound = 0

    let engine: EngineHost
    private let quarantine: QuarantineStore
    private let trust: TrustStore
    private let home: URL
    private let runner: any CommandRunning
    private let defaults: UserDefaults?
    private var task: Task<Void, Never>?

    init(
        engine: EngineHost, quarantine: QuarantineStore, trust: TrustStore, home: URL, runner: any CommandRunning,
        defaults: UserDefaults? = .standard
    ) {
        self.engine = engine
        self.quarantine = quarantine
        self.trust = trust
        self.home = home
        self.runner = runner
        self.defaults = defaults
        if let date = defaults?.object(forKey: "lastScanDate") as? Date {
            lastScanDate = date
            lastScanFound = defaults?.integer(forKey: "lastScanFound") ?? 0
        }
    }

    func setPreview(result: ScanResult?, entries: [QuarantineStore.Entry], lastScan: Date?, phase: Phase = .idle) {
        self.result = result
        findings = result?.findings ?? []
        self.entries = entries
        lastScanDate = lastScan
        lastScanFound = findings.count
        self.phase = phase
        if phase == .scanning {
            progress = ScanProgress(unitsDone: 3, unitsTotal: 7, filesChecked: 18_204, current: "Downloads")
        }
    }

    var isBusy: Bool { phase != .idle && !isFailed }
    var isFailed: Bool { if case .failed = phase { true } else { false } }

    func refreshFacts() {
        hasFullDiskAccess = FullDiskAccess.isGranted(home: home)
        entries = quarantine.entries()
        engine.refresh()
    }

    func start(_ scope: ScanScope) {
        guard task == nil else { return }
        self.scope = scope
        tab = .result
        problems = [:]
        progress = nil
        task = Task {
            await run(scope)
            task = nil
        }
    }

    func stop() {
        task?.cancel()
    }

    private func run(_ scope: ScanScope) async {
        let client: ClamClient
        do {
            client = try await engine.acquire { phase = .preparing($0) }
        } catch {
            phase = .failed((error as? EngineError) == .notInstalled ? "notInstalled" : String(describing: error))
            return
        }
        phase = .scanning
        let plan = ScanPlan.make(scope, home: home, keepOut: engine.keepOut)
        let (home, runner, trust) = (home, runner, trust)
        let scanner = MalwareScanner(
            engine: client,
            autostart: { await AutostartInventory(home: home, runner: runner).items() },
            apps: {
                MalwareScanner.apps(in: [
                    URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"),
                ])
            },
            trusted: { trust.trustedIDs() })
        do {
            let result = try await scanner.scan(plan) { [weak self] progress in
                Task { @MainActor in self?.progress = progress }
            }
            self.result = result
            findings = result.findings
            lastScanDate = result.date
            lastScanFound = result.findings.count
            defaults?.set(result.date, forKey: "lastScanDate")
            defaults?.set(result.findings.count, forKey: "lastScanFound")
            phase = .idle
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = Task.isCancelled ? .idle : .failed(String(describing: error))
        }
        await engine.release()
        refreshFacts()
    }

    /// Something the live protection caught joins the list, newest first.
    func add(_ finding: Finding) {
        guard findings.contains(where: { $0.id == finding.id }) == false else { return }
        findings.insert(finding, at: 0)
    }

    /// What "Quarantine All" takes: proven malware only, and never Ward itself or Tidy.
    var bulkFindings: [Finding] {
        BulkQuarantine.findings(findings, sparing: [Bundle.main.bundleURL])
    }

    /// Moving a big file from another disk takes a while, so it happens off the main thread.
    func moveToQuarantine(_ finding: Finding) async {
        guard working.insert(finding.id).inserted else { return }
        defer { working.remove(finding.id) }
        let (store, url, reason) = (quarantine, finding.url, finding.reason.title)
        do {
            _ = try await Task.detached(priority: .userInitiated) { try store.add(url, reason: reason) }.value
            resolve(finding)
        } catch {
            problems[finding.id] = .move
        }
        await reloadEntries()
    }

    func moveAllToQuarantine() async {
        for finding in bulkFindings {
            await moveToQuarantine(finding)
        }
    }

    /// The owner has looked and wants it left alone; it will not be shown again.
    func keep(_ finding: Finding) {
        try? trust.trust(finding)
        resolve(finding)
    }

    func disable(_ finding: Finding) async {
        guard let item = finding.autostart, working.insert(finding.id).inserted else { return }
        defer { working.remove(finding.id) }
        do {
            try await AutostartControl(runner: runner).setEnabled(false, item)
            resolve(finding)
        } catch AdminAction.Failure.cancelled {
            return
        } catch {
            problems[finding.id] = .turnOff
        }
    }

    func restore(_ entry: QuarantineStore.Entry) async {
        guard working.insert(entry.id).inserted else { return }
        defer { working.remove(entry.id) }
        let store = quarantine
        do {
            try await Task.detached(priority: .userInitiated) { try store.restore(entry) }.value
            problems[entry.id] = nil
        } catch QuarantineStore.Failure.placeTaken {
            problems[entry.id] = .taken
        } catch {
            problems[entry.id] = .restore
        }
        await reloadEntries()
    }

    func delete(_ entry: QuarantineStore.Entry) async {
        guard working.insert(entry.id).inserted else { return }
        defer { working.remove(entry.id) }
        let store = quarantine
        do {
            try await Task.detached(priority: .userInitiated) { try store.delete(entry) }.value
            problems[entry.id] = nil
        } catch {
            problems[entry.id] = .delete
        }
        await reloadEntries()
    }

    private func reloadEntries() async {
        let store = quarantine
        entries = await Task.detached(priority: .userInitiated) { store.entries() }.value
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func resolve(_ finding: Finding) {
        findings.removeAll { $0.id == finding.id }
        problems[finding.id] = nil
    }
}

extension Finding.Reason {
    /// A short name stored with a quarantined file.
    var title: String {
        switch self {
        case .knownMalware(let signature): signature
        case .unsignedAutostart: "unsignedAutostart"
        case .hiddenAutostart: "hiddenAutostart"
        case .scriptAutostart: "scriptAutostart"
        case .brokenSignature: "brokenSignature"
        case .unsignedApp: "unsignedApp"
        }
    }
}
