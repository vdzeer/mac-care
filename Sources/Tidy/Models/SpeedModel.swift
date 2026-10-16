import AppKit
import CareCore
import Foundation
import Observation

/// Live numbers about the Mac, shared by the Speed screen and the menu bar panel.
@Observable final class MetricsModel {
    private(set) var snapshot = SystemSnapshot()
    private(set) var heavy: [HeavyProcess] = []
    private(set) var volume: VolumeInfo?

    private let runner: any CommandRunning
    private let meter = SystemMeter()
    private var watchers = 0
    private var task: Task<Void, Never>?
    private var isPreview = false

    init(runner: any CommandRunning) {
        self.runner = runner
    }

    func setPreview(snapshot: SystemSnapshot, heavy: [HeavyProcess], volume: VolumeInfo) {
        self.snapshot = snapshot
        self.heavy = heavy
        self.volume = volume
        isPreview = true
    }

    /// Sampling runs only while something on screen shows the numbers.
    func start() {
        watchers += 1
        guard task == nil, isPreview == false else { return }
        let (meter, runner) = (meter, runner)
        task = Task { [weak self] in
            while Task.isCancelled == false {
                let reading = await Task.detached { meter.read() }.value
                let processes = await HeavyProcesses.sample(runner: runner, limit: 5)
                self?.snapshot = reading
                self?.heavy = processes
                self?.volume = VolumeInfo.startup()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        watchers = max(watchers - 1, 0)
        guard watchers == 0 else { return }
        task?.cancel()
        task = nil
    }
}

/// What the Speed screen knows about things that start by themselves.
@Observable final class SpeedModel {
    enum Phase: Equatable { case idle, loading, ready }

    private(set) var phase: Phase = .idle
    private(set) var items: [AutostartItem] = []
    private(set) var problemID: String?
    private(set) var busyID: String?

    private let home: URL
    private let runner: any CommandRunning
    private var icons: [String: NSImage] = [:]
    private var isPreview = false

    init(home: URL, runner: any CommandRunning) {
        self.home = home
        self.runner = runner
    }

    func setPreview(items: [AutostartItem]) {
        self.items = items
        phase = .ready
        isPreview = true
    }

    var enabledCount: Int { items.filter(\.isEnabled).count }

    func load() async {
        guard phase != .loading, isPreview == false else { return }
        if items.isEmpty { phase = .loading }
        items = await AutostartInventory(home: home, runner: runner).items()
        phase = .ready
    }

    func toggle(_ item: AutostartItem) async {
        guard busyID == nil, isPreview == false else { return }
        problemID = nil
        busyID = item.id
        do {
            try await AutostartControl(runner: runner).setEnabled(item.isEnabled == false, item)
        } catch AdminAction.Failure.cancelled {
            busyID = nil
            return
        } catch {
            problemID = item.id
        }
        // The rows keep their places; only their state is read again.
        let fresh = await AutostartInventory(home: home, runner: runner).items()
        let byID = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        items = items.compactMap { byID[$0.id] }
        busyID = nil
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func icon(for item: AutostartItem) -> NSImage? {
        guard let app = AutostartInventory.enclosingApp((item.target ?? "") + "/") else { return nil }
        if let cached = icons[app] { return cached }
        guard FileManager.default.fileExists(atPath: app) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: app)
        icons[app] = image
        return image
    }
}
