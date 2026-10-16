import AppKit
import CareCore
import Foundation
import Observation

/// What the Autostart & Network screen knows.
@Observable final class AutostartModel {
    enum Filter: Hashable { case all, new, unsigned }
    enum Phase: Equatable { case idle, loading, ready }

    var filter: Filter = .all
    private(set) var phase: Phase = .idle
    private(set) var items: [AutostartItem] = []
    private(set) var newIDs: Set<String> = []
    private(set) var network: [NetworkProcess] = []
    private(set) var problemID: String?

    private let home: URL
    private let runner: any CommandRunning
    private let baseline: BaselineStore
    private var networkTask: Task<Void, Never>?
    private var isPreview = false

    init(home: URL, runner: any CommandRunning, baseline: BaselineStore) {
        self.home = home
        self.runner = runner
        self.baseline = baseline
    }

    func setPreview(items: [AutostartItem], newIDs: Set<String>, network: [NetworkProcess]) {
        self.items = items
        self.newIDs = newIDs
        self.network = network
        phase = .ready
        isPreview = true
    }

    static func lacksSignature(_ item: AutostartItem) -> Bool {
        item.signature.map { $0.isTrusted == false } ?? false
    }

    var unsignedCount: Int { items.filter(Self.lacksSignature).count }
    var listeningCount: Int { network.filter { $0.listeningPorts.isEmpty == false }.count }

    var visible: [AutostartItem] {
        switch filter {
        case .all: items
        case .new: items.filter { newIDs.contains($0.id) }
        case .unsigned: items.filter(Self.lacksSignature)
        }
    }

    func load() async {
        guard phase != .loading, isPreview == false else { return }
        if items.isEmpty { phase = .loading }
        let found = await AutostartInventory(home: home, runner: runner).items()
        // What is new or unsigned goes to the top once, at load; the rows then stay where they are.
        let fresh = baseline.newItems(among: found)
        items = found.filter { fresh.contains($0.id) } + found.filter { fresh.contains($0.id) == false }
        newIDs = fresh
        phase = .ready
    }

    func markSeen() {
        baseline.acknowledge(items)
        newIDs = []
        if filter == .new { filter = .all }
    }

    func setEnabled(_ enabled: Bool, _ item: AutostartItem) async {
        problemID = nil
        do {
            try await AutostartControl(runner: runner).setEnabled(enabled, item)
        } catch AdminAction.Failure.cancelled {
            return
        } catch {
            problemID = item.id
        }
        let found = await AutostartInventory(home: home, runner: runner).items()
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        items = items.compactMap { byID[$0.id] }
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Samples the network every few seconds while the screen is open.
    func startNetwork() {
        guard networkTask == nil, isPreview == false else { return }
        let runner = runner
        networkTask = Task { [weak self] in
            var previous: [NetworkProcess] = []
            var known: [String: SignatureInfo] = [:]
            var stamp = Date()
            while Task.isCancelled == false {
                let sample = await NetworkActivity.sample(runner: runner)
                let now = Date()
                let (earlier, interval, cache) = (previous, now.timeIntervalSince(stamp), known)
                let (active, updated) = await Task.detached { () -> ([NetworkProcess], [String: SignatureInfo]) in
                    var cache = cache
                    let active = NetworkActivity.active(sample, previous: earlier, interval: interval) { pid in
                        guard let path = NetworkActivity.path(ofProcess: pid) else { return (nil, nil) }
                        if cache[path] == nil { cache[path] = CodeSignature.inspect(URL(fileURLWithPath: path)) }
                        return (path, cache[path])
                    }
                    return (active, cache)
                }.value
                (previous, stamp, known) = (sample, now, updated)
                self?.network = active
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopNetwork() {
        networkTask?.cancel()
        networkTask = nil
    }
}
