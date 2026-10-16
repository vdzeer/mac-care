import CareCore
import Foundation
import Observation

enum TidySection: Hashable, CaseIterable {
    case overview, junk, apps, space, speed
}

@Observable final class AppModel {
    var section: TidySection = .overview
    /// The app's own window that asks for Full Disk Access.
    var showsPermissions = false
    let junk: JunkModel
    let apps: AppsModel
    let space: SpaceModel
    let speed: SpeedModel
    let metrics: MetricsModel
    private(set) var volume: VolumeInfo?
    private(set) var appCount = 0
    private(set) var autostartCount = 0

    init(junk: JunkModel, apps: AppsModel, space: SpaceModel, speed: SpeedModel, metrics: MetricsModel) {
        self.junk = junk
        self.apps = apps
        self.space = space
        self.speed = speed
        self.metrics = metrics
        // A cleanup, Empty Trash or an uninstall changes what the overview and the sidebar say about the disk.
        let refresh: () -> Void = { [weak self] in self?.refreshFacts() }
        junk.onDiskChange = refresh
        apps.onDiskChange = refresh
        space.onDiskChange = refresh
    }

    static func live() -> AppModel {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let junk = JunkModel(home: home, runner: SystemCommandRunner(), journal: .standard(appFolder: "Tidy"))
        let runner = SystemCommandRunner()
        let finder = LeftoverFinder(
            home: home,
            applicationFolders: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")])
        let apps = AppsModel(finder: finder, journal: .standard(appFolder: "Tidy"), runner: runner)
        return AppModel(
            junk: junk, apps: apps,
            space: SpaceModel(home: home, journal: .standard(appFolder: "Tidy"), runner: runner),
            speed: SpeedModel(home: home, runner: runner), metrics: MetricsModel(runner: runner))
    }

    /// Shown once, the first time the window opens without Full Disk Access.
    func askForPermissionsIfNeeded() {
        guard Bundle.main.bundleIdentifier != nil, UserDefaults.standard.bool(forKey: "permissionsAsked") == false,
            FullDiskAccess.isGranted() == false
        else { return }
        showsPermissions = true
    }

    func closePermissions() {
        UserDefaults.standard.set(true, forKey: "permissionsAsked")
        showsPermissions = false
        // What can be removed depends on what Tidy can see.
        Task { await junk.measure() }
    }

    /// Facts that cost nothing to read; shown on the overview at once.
    func refreshFacts() {
        volume = VolumeInfo.startup()
        let home = FileManager.default.homeDirectoryForCurrentUser
        appCount = Self.count(in: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")])
        {
            $0.pathExtension == "app"
        }
        autostartCount = Self.count(
            in: [
                home.appendingPathComponent("Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchAgents"),
                URL(fileURLWithPath: "/Library/LaunchDaemons"),
            ]
        ) { $0.pathExtension == "plist" }
    }

    func setFacts(volume: VolumeInfo, appCount: Int, autostartCount: Int) {
        self.volume = volume
        self.appCount = appCount
        self.autostartCount = autostartCount
    }

    private static func count(in folders: [URL], where matches: (URL) -> Bool) -> Int {
        folders.reduce(0) { total, folder in
            let children =
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return total + children.filter(matches).count
        }
    }
}
