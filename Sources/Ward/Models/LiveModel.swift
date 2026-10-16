import CareCore
import Foundation
import Observation
import ServiceManagement
import UserNotifications

/// What the Live Protection screen knows: the switch, the watched places, what was checked.
@Observable final class LiveModel {
    private(set) var isOn = false
    private(set) var isStarting = false
    private(set) var places: Set<WatchedPlace>
    private(set) var events: [LiveEvent] = []
    /// The engine did not start, or stopped answering: new files are not being checked.
    private(set) var hasProblem = false
    /// The owner wants the protection on, even while it could not start.
    private(set) var wantsOn = false
    private var checked = DailyCount()

    private let engine: EngineHost
    private let shield: ShieldModel
    private let home: URL
    private let runner: any CommandRunning
    private let defaults: UserDefaults?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var inspector: LiveInspector?
    @ObservationIgnored private var isPreview = false
    /// Changed things wait here until they are quiet, so a copy in progress is checked once, at the end.
    @ObservationIgnored private var queue = SettleQueue()
    @ObservationIgnored private var drain: Task<Void, Never>?
    @ObservationIgnored private var upkeep: Task<Void, Never>?
    /// Things that were not checked and have been tried once more already.
    @ObservationIgnored private var retried: Set<String> = []
    /// Things that were not checked while the engine was down; they are tried again once it is back.
    @ObservationIgnored private var unchecked: [String: URL] = [:]
    @ObservationIgnored private var lastRevival: Date?

    init(
        engine: EngineHost, shield: ShieldModel, home: URL, runner: any CommandRunning,
        defaults: UserDefaults? = .standard
    ) {
        self.engine = engine
        self.shield = shield
        self.home = home
        self.runner = runner
        self.defaults = defaults
        let saved = (defaults?.stringArray(forKey: "watchedPlaces") ?? []).compactMap(WatchedPlace.init(rawValue:))
        places = saved.isEmpty ? [.downloads, .applications, .autostart, .volumes] : Set(saved)
        wantsOn = defaults?.bool(forKey: "liveOn") == true
    }

    /// Files checked since midnight.
    var checkedToday: Int { checked.value(at: Date()) }

    /// The protection should be running and its engine is not there. The menu bar icon carries a mark then.
    var engineIsDown: Bool { hasProblem && (isOn || wantsOn) }

    func setPreview(isOn: Bool, events: [LiveEvent], checkedToday: Int, hasProblem: Bool = false) {
        self.isOn = isOn
        self.events = events
        checked = DailyCount()
        checked.add(checkedToday, at: Date())
        self.hasProblem = hasProblem
        isPreview = true
    }

    /// Switches the protection back on after a restart if it was on before.
    func resume() async {
        if wantsOn, isOn == false { await setOn(true) }
    }

    func setOn(_ on: Bool) async {
        guard isPreview == false, isStarting == false, on != isOn else { return }
        hasProblem = false
        if on {
            isStarting = true
            defer { isStarting = false }
            do {
                let client = try await engine.acquire { _ in }
                let (home, runner) = (home, runner)
                inspector = LiveInspector(
                    home: home, engine: client,
                    autostart: { await AutostartInventory(home: home, runner: runner).items() })
                isOn = true
                wantsOn = true
                defaults?.set(true, forKey: "liveOn")
                restartWatcher()
                startUpkeep()
                // The owner agreed that live protection starts together with the Mac.
                try? SMAppService.mainApp.register()
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                hasProblem = true
            }
        } else {
            watcher?.stop()
            watcher = nil
            inspector = nil
            drain?.cancel()
            drain = nil
            upkeep?.cancel()
            upkeep = nil
            queue = SettleQueue()
            retried = []
            unchecked = [:]
            lastRevival = nil
            isOn = false
            wantsOn = false
            defaults?.set(false, forKey: "liveOn")
            try? await SMAppService.mainApp.unregister()
            await engine.release()
        }
    }

    /// The button next to a problem: start the protection, or its engine, again.
    func retry() async {
        guard isPreview == false else { return }
        if isOn {
            lastRevival = nil
            await recover([])
        } else {
            await setOn(true)
        }
    }

    func toggle(_ place: WatchedPlace) {
        if places.remove(place) == nil { places.insert(place) }
        defaults?.set(places.map(\.rawValue).sorted(), forKey: "watchedPlaces")
        if isOn, isPreview == false { restartWatcher() }
    }

    private func restartWatcher() {
        watcher?.stop()
        let folders = places.flatMap { $0.folders(home: home) }
        watcher = FileWatcher(folders: folders) { [weak self] changed in
            Task { @MainActor in self?.handle(changed) }
        }
        watcher?.start()
    }

    /// A burst of changes only notes what changed; the check comes once it has been quiet for a moment.
    private func handle(_ changed: [URL]) {
        guard isOn, inspector != nil else { return }
        let units = LiveInspector.units(from: changed)
        guard units.isEmpty == false else { return }
        queue.note(units, at: Date())
        scheduleDrain()
    }

    private func scheduleDrain() {
        guard drain == nil, isOn else { return }
        drain = Task { [weak self] in await self?.runDrain() }
    }

    /// Waits for things to settle and hands each settled group to its own check, off the main thread.
    private func runDrain() async {
        while isOn, Task.isCancelled == false, let due = queue.nextDue() {
            let wait = due.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                continue
            }
            let ready = queue.take(at: Date())
            guard ready.isEmpty == false, let inspector else { break }
            let places = Array(places)
            Task { [weak self] in
                let found = await inspector.inspect(ready, places: places)
                self?.finish(ready, found)
            }
        }
        // A cancelled loop was already replaced when the protection went off.
        if Task.isCancelled == false { drain = nil }
    }

    private func finish(_ units: [URL], _ found: [LiveEvent]) {
        queue.finish(units)
        guard isOn else { return }
        record(found)
        let missed = found.filter { $0.verdict == .notChecked }.map(\.url)
        if missed.isEmpty == false {
            Task { await recover(missed) }
        }
        scheduleDrain()
    }

    private func record(_ found: [LiveEvent]) {
        guard found.isEmpty == false else { return }
        let checkedNow = found.filter { $0.verdict != .notChecked }
        checked.add(checkedNow.count, at: Date())
        for event in checkedNow { retried.remove(event.url.path) }
        // A clean verdict means the engine answered.
        if found.contains(where: { $0.verdict == .clean }) { hasProblem = false }
        events = Array((found.reversed() + events).prefix(200))
        for event in found {
            guard case .flagged(let finding) = event.verdict else { continue }
            shield.add(finding)
            notify(about: finding, place: event.place)
        }
    }

    /// Something was not checked, or it is time to look: if the engine is gone, start it again (at most once a
    /// minute); once it answers, everything that was missed is tried once more.
    private func recover(_ missed: [URL]) async {
        for url in missed where retried.contains(url.path) == false { unchecked[url.path] = url }
        if await engine.isAnswering() == false {
            hasProblem = true
            if let lastRevival, Date().timeIntervalSince(lastRevival) < 60 { return }
            lastRevival = Date()
            do {
                try await engine.revive()
            } catch {
                return
            }
        }
        hasProblem = false
        let again = Array(unchecked.values)
        unchecked = [:]
        for url in again { retried.insert(url.path) }
        guard isOn, again.isEmpty == false else { return }
        queue.note(again, at: Date())
        scheduleDrain()
    }

    /// Every few minutes while the protection is on: is the engine still there, and is the database a day old.
    private func startUpkeep() {
        upkeep?.cancel()
        upkeep = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(300))
                guard Task.isCancelled == false, let self, self.isOn else { return }
                await self.recover([])
                await self.engine.updateIfDue()
            }
        }
    }

    private func notify(about finding: Finding, place: WatchedPlace) {
        let content = UNMutableNotificationContent()
        content.title =
            finding.severity == .malicious ? WardStrings.Notice.maliciousTitle : WardStrings.Notice.suspiciousTitle
        content.body = WardStrings.Notice.body(finding.name, WardStrings.Live.place(place))
        content.sound = .default
        let request = UNNotificationRequest(identifier: finding.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
