import AppKit
import CareCore
import Foundation
import Observation
import UserNotifications

enum WardSection: Hashable, CaseIterable {
    case overview, scan, live, mac, autostart
}

@Observable final class AppModel {
    var section: WardSection = .overview
    /// The app's own window for Full Disk Access, notifications and the engine.
    var showsPermissions = false
    let engine: EngineHost
    let shield: ShieldModel
    let mac: MacModel
    let autostart: AutostartModel
    let live: LiveModel

    init(engine: EngineHost, shield: ShieldModel, mac: MacModel, autostart: AutostartModel, live: LiveModel) {
        self.engine = engine
        self.shield = shield
        self.mac = mac
        self.autostart = autostart
        self.live = live
    }

    static func make(home: URL, runner: any CommandRunning, support: URL, defaults: UserDefaults?) -> AppModel {
        let quarantine = QuarantineStore(folder: support.appendingPathComponent("Quarantine"))
        let engine = EngineHost(keepOut: [quarantine.folder])
        let shield = ShieldModel(
            engine: engine, quarantine: quarantine,
            trust: TrustStore(fileURL: support.appendingPathComponent("trusted.json")),
            home: home, runner: runner, defaults: defaults)
        return AppModel(
            engine: engine, shield: shield, mac: MacModel(runner: runner),
            autostart: AutostartModel(
                home: home, runner: runner,
                baseline: BaselineStore(fileURL: support.appendingPathComponent("baseline.json"))),
            live: LiveModel(engine: engine, shield: shield, home: home, runner: runner, defaults: defaults))
    }

    static func live() -> AppModel {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return make(
            home: FileManager.default.homeDirectoryForCurrentUser, runner: SystemCommandRunner(),
            support: support.appendingPathComponent("Ward"), defaults: .standard)
    }

    /// How many things on the overview ask for the owner's attention.
    var attentionCount: Int {
        mac.attention.count + (shield.findings.isEmpty ? 0 : 1) + (autostart.newIDs.isEmpty ? 0 : 1)
    }

    /// Everything the overview needs, read once when the window opens.
    func refresh() async {
        shield.refreshFacts()
        async let checks: Void = mac.refresh()
        async let items: Void = autostart.load()
        _ = await (checks, items)
        await live.resume()
    }

    /// Shown once, the first time the window opens while something is missing.
    func askForPermissionsIfNeeded() async {
        guard Bundle.main.bundleIdentifier != nil, UserDefaults.standard.bool(forKey: "permissionsAsked") == false
        else { return }
        engine.refresh()
        let notifications = await Self.notificationsAllowed()
        if FullDiskAccess.isGranted() == false || notifications == false || engine.isInstalled == false {
            showsPermissions = true
        }
    }

    func closePermissions() {
        UserDefaults.standard.set(true, forKey: "permissionsAsked")
        showsPermissions = false
        shield.refreshFacts()
    }

    static func notificationsAllowed() async -> Bool {
        // The notification centre exists only for a real app bundle, not for a bare build or a snapshot run.
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// macOS asks only once; after a "Don't Allow" the switch lives in System Settings.
    func askForNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .denied {
                let id = Bundle.main.bundleIdentifier ?? ""
                if let url = URL(
                    string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")
                {
                    NSWorkspace.shared.open(url)
                }
            } else {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
        }
    }

    func startQuickCheck() {
        section = .scan
        shield.start(.quick)
    }
}
