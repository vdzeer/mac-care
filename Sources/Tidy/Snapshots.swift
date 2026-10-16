import AppKit
import CareCore
import CareUI
import SwiftUI

/// Draws every screen with fixed sample data into PNG files: `Tidy --snapshot <folder>`.
/// No window is shown and the disk is not scanned.
enum Snapshots {
    static func write(to folder: URL) {
        _ = NSApplication.shared
        let model = sampleModel()
        let window = CGSize(width: Metric.windowWidth, height: Metric.windowHeight)

        func shot(_ name: String, _ section: TidySection) {
            model.section = section
            save(RootView(model: model), size: window, name: name, folder: folder)
        }
        shot("tidy-overview", .overview)
        shot("tidy-junk", .junk)
        model.junk.expanded = [.derivedData]
        shot("tidy-junk-open", .junk)
        save(CleanSheet(model: model.junk), size: CGSize(width: 460, height: 420), name: "tidy-confirm", folder: folder)
        let done = JunkModel(preview: JunkScan(groups: []), home: URL(fileURLWithPath: "/Users/you"))
        done.previewFinished(
            RemovalReport(outcomes: [
                RemovalOutcome(
                    request: RemovalRequest(
                        id: "dd", kind: "derivedData", name: "DerivedData", urls: [], bytes: 12_400_000_000,
                        removal: .delete), result: .removed),
                RemovalOutcome(
                    request: RemovalRequest(
                        id: "ar", kind: "xcodeArchives", name: "Archive", urls: [], bytes: 1_900_000_000,
                        removal: .trash), result: .removed),
            ]))
        save(CleanSheet(model: done), size: CGSize(width: 460, height: 260), name: "tidy-done", folder: folder)
        model.apps.select("/Applications/Postman.app")
        shot("tidy-apps", .apps)
        model.apps.mode = .orphans
        model.apps.select("com.gone.editor")
        shot("tidy-apps-orphans", .apps)
        shot("tidy-space", .space)
        model.space.tab = .large
        shot("tidy-space-large", .space)
        model.space.tab = .duplicates
        shot("tidy-space-duplicates", .space)
        model.space.tab = .system
        shot("tidy-space-system", .space)
        shot("tidy-speed", .speed)
        save(MenuBarPanel(model: model), size: CGSize(width: 290, height: 420), name: "tidy-menubar", folder: folder)
        let access = PermissionStep(
            id: "fullDiskAccess", title: TidyStrings.Permissions.fullDiskAccess,
            note: TidyStrings.Permissions.fullDiskAccessNote, actionTitle: TidyStrings.Permissions.openSettings,
            isAllowed: { false }, action: {})
        save(
            PermissionsSheet(
                title: TidyStrings.Permissions.title, message: TidyStrings.Permissions.message,
                allowedLabel: TidyStrings.Permissions.allowed, laterTitle: TidyStrings.Permissions.later,
                doneTitle: TidyStrings.Permissions.done, steps: [access], onClose: {}),
            size: CGSize(width: 540, height: 300), name: "tidy-permissions", folder: folder)
    }

    /// Every screen is drawn twice: in the light and in the dark appearance (`-dark`).
    private static func save(_ view: some View, size: CGSize, name: String, folder: URL) {
        for dark in [false, true] {
            do {
                let url = folder.appendingPathComponent(name + (dark ? "-dark" : "") + ".png")
                try SnapshotRenderer.write(view, size: size, accent: .tidy, dark: dark, to: url)
                print(url.path)
            } catch {
                FileHandle.standardError.write(Data("\(name): \(error)\n".utf8))
            }
        }
    }

    private static func sampleModel() -> AppModel {
        let home = URL(fileURLWithPath: "/Users/sample")
        let sizes: [(JunkRule.ID, [(String, Double)])] = [
            (.derivedData, [("Moonbeam-fkzqwerty", 21.4), ("Everhue-bzzxcvbn", 9.2), ("Vigil-hgfdsa", 4.5)]),
            (.gradle, [("modules-2", 22.0), ("transforms-4", 6.5)]),
            (.appCaches, [("com.google.Chrome", 9.9), ("com.spotify.client", 8.0), ("com.figma.Desktop", 6.3)]),
            (.npm, [("content-v2", 21.0), ("index-v5", 1.2)]),
            (.deviceSupport, [("iPhone17,1 18.2 (22C152)", 10.1), ("iPhone16,2 17.5 (21F79)", 9.6)]),
            (.cocoaPods, [("Pods", 2.0)]),
            (.yarn, [("v6", 1.9)]),
            (.homebrew, [("downloads", 1.0)]),
            (.logs, [("DiagnosticReports", 0.1)]),
            (.simulatorRuntimes, [("iOS 26.1", 8.3), ("iOS 26.2", 8.4), ("iOS 27.0", 8.1)]),
            (.simulators, [("iPhone 14", 3.1), ("iPhone 16 Pro", 25.7)]),
            (.wallpaperVideos, [("097CA871.mov", 14.5)]),
            (.trash, [("old-report.pdf", 2.6)]),
            (.androidDevices, [("Pixel_8_API_35.avd", 19.7)]),
            (.xcodeArchives, [("2026-09-30", 0.9)]),
        ]
        let rules = Dictionary(uniqueKeysWithValues: JunkRules.all(home: home).map { ($0.id, $0) })
        let groups = sizes.compactMap { id, entries -> JunkGroup? in
            guard let rule = rules[id] else { return nil }
            let items = entries.enumerated().map { index, entry in
                JunkItem(
                    id: "\(id.rawValue):\(entry.0)", rule: id, name: entry.0,
                    runtime: id == .simulators
                        ? (index == 0 ? "iOS 16.4" : "iOS 18.2") : id == .simulatorRuntimes ? "23B80" : nil,
                    isUnavailable: id == .simulators && index == 0,
                    lastUsed: id == .simulatorRuntimes
                        ? Calendar.current.date(byAdding: .month, value: -(11 - index * 4), to: Date()) : nil,
                    urls: sampleURLs(id, entry.0, home: home), bytes: Int64(entry.1 * 1_000_000_000),
                    removal: rule.removal)
            }
            return JunkGroup(rule: rule, items: items, skipped: id == .appCaches ? ["com.apple.dt.Xcode"] : [])
        }
        let runner = SystemCommandRunner()
        let model = AppModel(
            junk: JunkModel(preview: JunkScan(groups: groups), home: home), apps: sampleApps(home: home),
            space: sampleSpace(home: home), speed: sampleSpeed(home: home), metrics: MetricsModel(runner: runner))
        var snapshot = SystemSnapshot()
        snapshot.cpu = 0.18
        snapshot.memoryUsed = 41_000_000_000
        snapshot.memoryTotal = 64_000_000_000
        snapshot.networkIn = 2_400_000
        model.metrics.setPreview(
            snapshot: snapshot,
            heavy: [
                HeavyProcess(pid: 1, name: "Xcode", cpu: 64, memory: 5_200_000_000),
                HeavyProcess(pid: 2, name: "Google Chrome", cpu: 22, memory: 7_800_000_000),
                HeavyProcess(pid: 3, name: "Simulator", cpu: 14, memory: 3_100_000_000),
                HeavyProcess(pid: 4, name: "Docker", cpu: 6, memory: 4_000_000_000),
            ], volume: VolumeInfo(name: "Macintosh HD", total: 994_660_000_000, free: 249_100_000_000))
        model.setFacts(
            volume: VolumeInfo(name: "Macintosh HD", total: 994_660_000_000, free: 249_100_000_000), appCount: 38,
            autostartCount: 21)
        return model
    }

    /// Where a sample junk item would lie, so the system-data tab can tell what belongs to which place.
    private static func sampleURLs(_ rule: JunkRule.ID, _ name: String, home: URL) -> [URL] {
        let folder: String? =
            switch rule {
            case .derivedData: "Library/Developer/Xcode/DerivedData"
            case .deviceSupport: "Library/Developer/Xcode/iOS DeviceSupport"
            case .simulators: "Library/Developer/CoreSimulator/Devices"
            case .gradle: ".gradle/caches"
            case .npm: ".npm/_cacache"
            case .appCaches: "Library/Caches"
            case .androidDevices: ".android/avd"
            case .wallpaperVideos: "Library/Application Support/com.apple.wallpaper/aerials/videos"
            case .trash: ".Trash"
            default: nil
            }
        return folder.map { [home.appendingPathComponent($0).appendingPathComponent(name)] } ?? []
    }

    private static func sampleApps(home: URL) -> AppsModel {
        func megabytes(_ value: Double) -> Int64 { Int64(value * 1_000_000) }
        func app(_ name: String, _ id: String, _ size: Double, monthsAgo: Int) -> AppFootprint {
            let url = URL(fileURLWithPath: "/Applications/\(name).app")
            let used = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: Date())
            let installed = InstalledApp(url: url, name: name, bundleID: id, version: "1.0", lastUsed: used)
            return AppFootprint(app: installed, parts: [AppPart(kind: .app, url: url, bytes: megabytes(size))])
        }
        var footprints = [
            app("Android Studio", "com.google.android.studio", 3900, monthsAgo: 1),
            app("Telegram", "ru.keepcoder.Telegram", 2800, monthsAgo: 0),
            app("Docker", "com.docker.docker", 2200, monthsAgo: 0),
            app("Slack", "com.tinyspeck.slackmacgap", 1400, monthsAgo: 0),
            app("Figma", "com.figma.Desktop", 1100, monthsAgo: 2),
            app("Notion", "notion.id", 780, monthsAgo: 3),
            app("Zoom", "us.zoom.xos", 640, monthsAgo: 5),
        ]
        let postman = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Postman.app"), name: "Postman", bundleID: "com.postmanlabs.mac",
            version: "11.2", lastUsed: Calendar.current.date(byAdding: .month, value: -4, to: Date()))
        let library = home.appendingPathComponent("Library")
        let parts = [
            AppPart(kind: .app, url: postman.url, bytes: megabytes(512)),
            AppPart(
                kind: .data, url: library.appendingPathComponent("Application Support/Postman"), bytes: megabytes(1300)),
            AppPart(
                kind: .caches, url: library.appendingPathComponent("Caches/com.postmanlabs.mac"), bytes: megabytes(240)),
            AppPart(kind: .logs, url: library.appendingPathComponent("Logs/Postman"), bytes: megabytes(3)),
            AppPart(
                kind: .savedState,
                url: library.appendingPathComponent("Saved Application State/com.postmanlabs.mac.savedState"),
                bytes: 12_000),
            AppPart(
                kind: .preferences, url: library.appendingPathComponent("Preferences/com.postmanlabs.mac.plist"),
                bytes: 4_000),
        ]
        footprints.insert(AppFootprint(app: postman, parts: parts), at: 3)
        let orphans = [
            OrphanGroup(
                bundleID: "com.gone.editor",
                parts: [
                    AppPart(
                        kind: .data, url: library.appendingPathComponent("Application Support/com.gone.editor"),
                        bytes: megabytes(820)),
                    AppPart(
                        kind: .preferences, url: library.appendingPathComponent("Preferences/com.gone.editor.plist"),
                        bytes: 6_000),
                ]),
            OrphanGroup(
                bundleID: "org.swift.swiftpm",
                parts: [
                    AppPart(
                        kind: .caches, url: library.appendingPathComponent("Caches/org.swift.swiftpm"),
                        bytes: megabytes(310))
                ]),
        ]
        let finder = LeftoverFinder(home: home, applicationFolders: [URL(fileURLWithPath: "/Applications")])
        return AppsModel(preview: footprints, orphans: orphans, finder: finder)
    }

    private static func sampleSpace(home: URL) -> SpaceModel {
        func gigabytes(_ value: Double) -> Int64 { Int64(value * 1_000_000_000) }
        let model = SpaceModel(home: home, journal: CleanupJournal(fileURL: home), runner: SystemCommandRunner())
        let folders: [(String, Double)] = [
            ("Library", 212), ("Projects", 148), ("Movies", 96), ("Pictures", 74), ("Documents", 41), ("Downloads", 38),
            (".gradle", 28), (".npm", 22), ("Music", 6), ("Desktop", 4), (".android", 2), ("Public", 0.6),
            (".config", 0.4),
        ]
        let nodes = folders.map {
            SpaceNode(url: home.appendingPathComponent($0.0), bytes: gigabytes($0.1), isFolder: true)
        }
        func ago(months: Int) -> Date { Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date() }
        let large = [
            LargeFile(
                url: home.appendingPathComponent("Movies/Screen recording.mov"), bytes: gigabytes(18.4),
                lastOpened: ago(months: 7)),
            LargeFile(
                url: home.appendingPathComponent("Downloads/backup-2025.zip"), bytes: gigabytes(12.1),
                lastOpened: ago(months: 12)),
            LargeFile(
                url: home.appendingPathComponent("Downloads/Xcode_27.xip"), bytes: gigabytes(9.8),
                lastOpened: ago(months: 1)),
            LargeFile(
                url: home.appendingPathComponent("Downloads/ubuntu-24.04.iso"), bytes: gigabytes(5.9),
                lastOpened: ago(months: 24)),
            LargeFile(
                url: home.appendingPathComponent("Documents/archive.tar"), bytes: gigabytes(4.2),
                lastOpened: ago(months: 5)),
        ]
        let duplicates = [
            DuplicateGroup(
                bytes: gigabytes(2.1),
                files: [
                    home.appendingPathComponent("Movies/holiday.mp4"),
                    home.appendingPathComponent("Downloads/holiday (1).mp4"),
                    home.appendingPathComponent("Desktop/holiday copy.mp4"),
                ]),
            DuplicateGroup(
                bytes: 48_000_000,
                files: [
                    home.appendingPathComponent("Documents/report.pdf"),
                    home.appendingPathComponent("Downloads/report.pdf"),
                ]),
        ]
        func place(_ path: String, _ group: SystemDataPlace.Group, _ known: SystemDataPlace.Known, _ size: Double)
            -> SystemDataPlace
        {
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : home.appendingPathComponent(path)
            return SystemDataPlace(url: url, group: group, known: known, bytes: gigabytes(size))
        }
        let system = [
            place("Library/Developer", .developer, .xcode, 90.9), place(".gradle", .developer, .gradle, 37.0),
            place("Library/Android", .developer, .androidSDK, 25.8), place(".npm", .developer, .npm, 23.8),
            place(".android", .developer, .androidHome, 21.2), place(".cache", .developer, .cliCache, 6.5),
            place(".codex", .developer, .assistant, 1.4), place("Library/Caches", .apps, .appCaches, 28.9),
            place("Library/Containers/com.docker.docker", .apps, .docker, 18.1),
            place("Library/Application Support/com.apple.wallpaper", .apps, .wallpapers, 14.5),
            place("Library/Application Support/Slack", .apps, .appData, 12.9),
            place("/private/var/vm", .system, .swap, 5.4), place("/private/var/folders", .system, .temporary, 4.1),
            place(".Trash", .system, .trash, 2.6),
        ]
        model.setPreview(nodes: nodes, large: large, duplicates: duplicates, system: system)
        model.ticked = [large[1].id, duplicates[0].files[1].path, duplicates[0].files[2].path]
        return model
    }

    private static func sampleSpeed(home: URL) -> SpeedModel {
        func item(_ name: String, _ label: String, _ kind: AutostartItem.Kind, _ target: String, enabled: Bool = true)
            -> AutostartItem
        {
            AutostartItem(
                id: "\(kind.rawValue):\(label)", kind: kind, label: label, name: name, plist: nil, program: target,
                target: target, launcher: nil, isTargetMissing: false, isEnabled: enabled, runsAtLoad: true,
                interval: nil,
                developer: nil, signature: nil)
        }
        let model = SpeedModel(home: home, runner: SystemCommandRunner())
        model.setPreview(items: [
            item("Docker", "com.docker.vmnetd", .daemon, "/Applications/Docker.app/Contents/MacOS/vmnetd"),
            item("Figma", "com.figma.agent", .userAgent, "/Applications/Figma.app/Contents/MacOS/agent"),
            item(
                "Google Chrome", "com.google.GoogleUpdater.wake", .userAgent,
                "/Applications/Google Chrome.app/Contents/MacOS/updater", enabled: false),
            item(
                "Microsoft AutoUpdate", "com.microsoft.update.agent", .globalAgent,
                "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/x"),
            item(
                "zoom.us", "us.zoom.ZoomDaemon", .daemon, "/Applications/zoom.us.app/Contents/MacOS/daemon",
                enabled: false),
        ])
        return model
    }
}
