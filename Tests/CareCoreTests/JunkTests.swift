import Foundation
import Testing

@testable import CareCore

@Suite struct JunkTests {
    let home: TempHome
    let scanner: JunkScanner
    let remover: Remover

    init() throws {
        home = try TempHome()
        try home.file("Library/Developer/Xcode/DerivedData/ProjA-abc/Build/big.o", bytes: 400_000)
        try home.file("Library/Developer/Xcode/DerivedData/ProjB-def/index.db", bytes: 100_000)
        try home.file("Library/Caches/com.example.editor/blob", bytes: 50_000)
        try home.file("Library/Caches/com.example.running/blob", bytes: 50_000)
        try home.file("Library/Caches/com.apple.Safari/blob", bytes: 50_000)
        try home.file("Library/Caches/CocoaPods/Pods/lib.zip", bytes: 70_000)
        try home.file("Library/Logs/app.log", bytes: 9_000)
        try home.file(".npm/_cacache/content-v2/x", bytes: 30_000)
        try home.file(".npm/package.json", bytes: 100)
        try home.file(".android/avd/Pixel.avd/userdata.img", bytes: 200_000)
        try home.file("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist", bytes: 2_000)
        try home.file("Documents/thesis.txt", bytes: 5_000)
        try home.file("Library/Keychains/login.keychain-db", bytes: 5_000)

        scanner = JunkScanner(home: home.url, runner: FakeRunner(), runningBundleIDs: ["com.example.running"])
        remover = Remover(pathGuard: JunkRules.pathGuard(home: home.url), runner: FakeRunner())
    }

    @Test func findsWhatTheRulesDescribeAndNothingElse() async {
        let scan = await scanner.scan()
        let names = Dictionary(uniqueKeysWithValues: scan.groups.map { ($0.id, $0.items.map(\.name)) })
        #expect(names[.derivedData] == ["ProjA-abc", "ProjB-def"])
        #expect(names[.appCaches] == ["com.example.editor"])
        #expect(names[.cocoaPods] == ["Pods"])
        #expect(names[.logs] == ["app.log"])
        #expect(names[.npm] == ["content-v2"])
        #expect(names[.androidDevices] == ["Pixel.avd"])
        #expect(names[.xcodeArchives] == ["2026-01-01"])
        #expect(scan.groups.first { $0.id == .appCaches }?.skipped == ["com.example.running"])
        #expect(scan.items.allSatisfy { $0.bytes > 0 })
    }

    @Test func aBuildFolderIsLeftAloneWhileItsToolIsOpen() async throws {
        let busy = JunkScanner(home: home.url, runner: FakeRunner(), runningBundleIDs: ["com.apple.dt.Xcode"])
        let scan = await busy.scan()
        let derived = try #require(scan.groups.first { $0.id == .derivedData })
        #expect(derived.items.isEmpty)
        #expect(derived.skipped == ["com.apple.dt.Xcode"])
        #expect(scan.groups.first { $0.id == .npm }?.items.isEmpty == false)
    }

    @Test func ticksOnlyWhatRegenerates() async {
        let scan = await scanner.scan()
        let selection = JunkSelection.initial(for: scan)
        let plan = JunkMath.plan(scan, selection)
        #expect(Set(plan.items.map(\.rule)) == [.derivedData, .appCaches, .cocoaPods, .logs, .npm])
        #expect(plan.bytes == plan.items.reduce(0) { $0 + $1.bytes })

        let segments = JunkMath.segments(scan, selection)
        #expect(segments.map(\.category) == [.xcode, .build, .apps])
        #expect(segments.reduce(0) { $0 + $1.bytes } == plan.bytes)
    }

    @Test func togglingAGroupFillsThenClearsIt() async throws {
        let scan = await scanner.scan()
        let derived = try #require(scan.groups.first { $0.id == .derivedData })
        var selection = JunkSelection()
        #expect(selection.state(of: derived) == .none)
        selection.toggle(derived.items[0])
        #expect(selection.state(of: derived) == .some)
        selection.toggle(derived)
        #expect(selection.state(of: derived) == .all)
        selection.toggle(derived)
        #expect(selection.state(of: derived) == .none)
    }

    @Test func aCleanupLeavesWhatAnAppOpenedSinceTheMeasurementUses() async throws {
        try home.file("Library/Application Support/Editor/Code Cache/js/x", bytes: 9_000)
        try home.file("Library/Application Support/Editor/Local Storage/leveldb/000.ldb", bytes: 100)
        let scan = await scanner.scan()
        let plan = JunkMath.plan(scan, .initial(for: scan))
        let rules = JunkRules.all(home: home.url)

        let quiet = JunkMath.recheck(plan.items, rules: rules, runningBundleIDs: [], runningAppNames: [])
        #expect(quiet.safe == plan.items)
        #expect(quiet.blocked.isEmpty)

        // Hours later Xcode, the editor and an app with its own cache are open.
        let busy = JunkMath.recheck(
            plan.items, rules: rules, runningBundleIDs: ["com.apple.dt.Xcode", "com.example.editor"],
            runningAppNames: ["editor"])
        #expect(Set(busy.blocked.map(\.name)) == ["ProjA-abc", "ProjB-def", "com.example.editor", "Editor"])
        #expect(busy.safe.count + busy.blocked.count == plan.items.count)
        #expect(busy.safe.contains { $0.rule == .derivedData || $0.name == "Editor" } == false)
        #expect(busy.safe.contains { $0.rule == .npm })
    }

    @Test func aNewMeasurementKeepsTheOwnersTicks() async throws {
        let first = await scanner.scan()
        var selection = JunkSelection.initial(for: first)
        let projA = try #require(first.items.first { $0.name == "ProjA-abc" })
        let emulator = try #require(first.items.first { $0.name == "Pixel.avd" })
        selection.toggle(projA)
        selection.toggle(emulator)

        try FileManager.default.removeItem(at: home.path("Library/Developer/Xcode/DerivedData/ProjB-def"))
        try home.file("Library/Developer/Xcode/DerivedData/ProjC-ghi/index.db", bytes: 20_000)
        try home.file("Library/Developer/Xcode/Archives/2026-02-02/App.xcarchive/Info.plist", bytes: 2_000)
        try home.file("Library/Developer/Xcode/DerivedData/ProjA-abc/Build/more.o", bytes: 10_000)
        let second = await scanner.scan()
        let carried = JunkSelection.carried(selection, from: first, to: second)
        let ticked = Set(JunkMath.plan(second, carried).items.map(\.name))

        #expect(ticked.contains("ProjA-abc") == false, "unticked by the owner, and it stays so")
        #expect(ticked.contains("Pixel.avd"), "ticked by the owner, and it stays so")
        #expect(ticked.contains("ProjC-ghi"), "new, and regenerates")
        #expect(ticked.contains("2026-02-02") == false, "new, and the owner decides")
        #expect(ticked.contains("com.example.editor"))
        #expect(carried.itemIDs.isSubset(of: Set(second.items.map(\.id))))
        // The first measurement starts from the default.
        #expect(JunkSelection.carried(JunkSelection(), from: JunkScan(groups: []), to: second) == .initial(for: second))
    }

    @Test func dryRunRemovesNothing() async {
        let scan = await scanner.scan()
        let plan = JunkMath.plan(scan, .initial(for: scan))
        let report = await remover.remove(plan.items.map(\.removalRequest), dryRun: true)
        #expect(report.planned.count == plan.items.count)
        #expect(report.plannedBytes == plan.bytes)
        #expect(report.freedBytes == 0)
        #expect(home.exists("Library/Developer/Xcode/DerivedData/ProjA-abc/Build/big.o"))
    }

    @Test func removesExactlyThePlan() async {
        let scan = await scanner.scan()
        let plan = JunkMath.plan(scan, .initial(for: scan))
        let report = await remover.remove(plan.items.map(\.removalRequest), dryRun: false)
        #expect(report.problems.isEmpty)
        #expect(report.freedBytes == plan.bytes)

        for gone in [
            "Library/Developer/Xcode/DerivedData/ProjA-abc", "Library/Developer/Xcode/DerivedData/ProjB-def",
            "Library/Caches/com.example.editor", "Library/Caches/CocoaPods/Pods", "Library/Logs/app.log",
            ".npm/_cacache/content-v2",
        ] {
            #expect(home.exists(gone) == false, "\(gone) should be gone")
        }
        for kept in [
            "Library/Developer/Xcode/DerivedData", "Library/Caches/com.example.running/blob",
            "Library/Caches/com.apple.Safari/blob", ".npm/package.json", ".android/avd/Pixel.avd/userdata.img",
            "Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist", "Documents/thesis.txt",
            "Library/Keychains/login.keychain-db",
        ] {
            #expect(home.exists(kept), "\(kept) should still be there")
        }
    }

    @Test func refusesARequestThatPointsOutsideTheRules() async {
        let rogue = RemovalRequest(
            id: "rogue", kind: "test", name: "thesis", urls: [home.path("Documents/thesis.txt")], bytes: 5_000,
            removal: .delete)
        let mixed = RemovalRequest(
            id: "mixed", kind: "test", name: "mixed",
            urls: [home.path("Library/Logs/app.log"), home.path("Library/Keychains/login.keychain-db")], bytes: 1,
            removal: .delete)
        let report = await remover.remove([rogue, mixed], dryRun: false)
        #expect(report.outcomes.map(\.result) == [.refused(.outsideAllowedRoots), .refused(.outsideAllowedRoots)])
        #expect(home.exists("Documents/thesis.txt"))
        // One bad path stops the whole request: the good path next to it stays too.
        #expect(home.exists("Library/Logs/app.log"))
    }

    @Test func theJunkGuardNeverReachesProtectedFolders() {
        let pathGuard = JunkRules.pathGuard(home: home.url)
        for protected in ["Documents/thesis.txt", "Library/Keychains/login.keychain-db", "Library/Caches", ".npm"] {
            #expect(pathGuard.allows(home.path(protected)) == false, "\(protected) must be refused")
        }
    }

    @Test func recordsWhatWasRemoved() async throws {
        let scan = await scanner.scan()
        let plan = JunkMath.plan(scan, .initial(for: scan))
        let report = await remover.remove(plan.items.map(\.removalRequest), dryRun: false)
        let journal = CleanupJournal(fileURL: home.path("journal/journal.jsonl"))
        try journal.record(report)
        try journal.record(report)
        let entries = journal.entries()
        #expect(entries.count == plan.items.count * 2)
        #expect(entries.prefix(plan.items.count).reduce(0) { $0 + $1.bytes } == plan.bytes)
        #expect(entries.allSatisfy { $0.method == "delete" })
    }
}

@Suite struct SimulatorTests {
    static let listing = """
        {"devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
            {"udid": "AAAA", "name": "iPhone 16", "isAvailable": true, "state": "Shutdown"}
          ],
          "com.apple.CoreSimulator.SimRuntime.iOS-16-4": [
            {"udid": "BBBB", "name": "iPhone 14", "isAvailable": false, "availabilityError": "runtime profile not found"}
          ]
        }}
        """

    @Test func readsTheDeviceList() {
        let devices = SimulatorList.parse(Self.listing)
        #expect(
            devices == [
                SimulatorDevice(udid: "BBBB", name: "iPhone 14", runtime: "iOS 16.4", isAvailable: false),
                SimulatorDevice(udid: "AAAA", name: "iPhone 16", runtime: "iOS 18.2", isAvailable: true),
            ])
        #expect(SimulatorList.parse("not json").isEmpty)
    }

    @Test func listsUnavailableDevicesFirstAndRemovesThroughSimctl() async throws {
        let home = try TempHome()
        try home.file("Library/Developer/CoreSimulator/Devices/AAAA/data/big", bytes: 900_000)
        try home.file("Library/Developer/CoreSimulator/Devices/BBBB/data/small", bytes: 1_000)
        let runner = FakeRunner(answers: [
            "/usr/bin/xcrun simctl list devices -j": CommandResult(status: 0, stdout: Self.listing),
            "/usr/bin/xcrun simctl delete BBBB": CommandResult(status: 0, stdout: ""),
        ])
        let scan = await JunkScanner(home: home.url, runner: runner).scan()
        let group = try #require(scan.groups.first { $0.id == .simulators })
        #expect(group.items.map(\.name) == ["iPhone 14", "iPhone 16"])
        #expect(group.items[0].isUnavailable)
        #expect(JunkSelection.initial(for: scan).itemIDs.isEmpty)

        let remover = Remover(pathGuard: JunkRules.pathGuard(home: home.url), runner: runner)
        let report = await remover.remove(
            [group.items[0].removalRequest, group.items[1].removalRequest], dryRun: false)
        #expect(report.outcomes[0].result == .removed)
        // No answer was prepared for the second device, so the fake refuses it.
        #expect(report.outcomes[1].result != .removed)
    }
}

@Suite struct SimulatorRuntimeTests {
    static let listing = """
        {
          "44B2552C-B717-45E4-A9B4-543C0C3E131A": {
            "identifier": "44B2552C-B717-45E4-A9B4-543C0C3E131A",
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0", "version": "26.0", "build": "23A343",
            "sizeBytes": 8014773567, "state": "Ready", "deletable": true, "lastUsedAt": "2026-10-03T09:55:19Z"
          },
          "778E3BE3-B1BE-4C57-BEA6-8721CA77C044": {
            "identifier": "778E3BE3-B1BE-4C57-BEA6-8721CA77C044",
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1", "version": "26.1", "build": "23B80",
            "sizeBytes": 8346526729, "state": "Ready", "deletable": true, "lastUsedAt": "2025-11-10T21:50:45Z"
          },
          "AAAAAAAA-0000-0000-0000-000000000000": {
            "identifier": "AAAAAAAA-0000-0000-0000-000000000000",
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.watchOS-11-2", "version": "11.2", "build": "22S99",
            "sizeBytes": 4000000000, "state": "Ready", "deletable": false
          }
        }
        """

    @Test func readsRuntimesLongestUnusedFirst() {
        let runtimes = SimulatorRuntimes.parse(Self.listing)
        #expect(runtimes.map(\.name) == ["watchOS 11.2", "iOS 26.1", "iOS 26.0"])
        #expect(runtimes.map(\.build) == ["22S99", "23B80", "23A343"])
        #expect(runtimes[1].bytes == 8_346_526_729)
        #expect(runtimes[0].lastUsed == nil)
        #expect(runtimes[0].isDeletable == false)
        #expect(SimulatorRuntimes.parse("oops").isEmpty)
    }

    @Test func offersDeletableRuntimesAndRemovesThemThroughSimctl() async throws {
        let home = try TempHome()
        let old = "778E3BE3-B1BE-4C57-BEA6-8721CA77C044"
        let runner = FakeRunner(answers: [
            "/usr/bin/xcrun simctl runtime list -j": CommandResult(status: 0, stdout: Self.listing),
            "/usr/bin/xcrun simctl runtime delete \(old)": CommandResult(status: 0, stdout: ""),
        ])
        let scan = await JunkScanner(home: home.url, runner: runner).scan()
        let group = try #require(scan.groups.first { $0.id == .simulatorRuntimes })
        #expect(group.items.map(\.name) == ["iOS 26.1", "iOS 26.0"])
        #expect(group.bytes == 8_346_526_729 + 8_014_773_567)
        // Never ticked in advance: only the owner knows which systems are still needed.
        #expect(JunkSelection.initial(for: scan).itemIDs.isEmpty)

        let remover = Remover(pathGuard: JunkRules.pathGuard(home: home.url), runner: runner)
        let planned = await remover.remove([group.items[0].removalRequest], dryRun: true)
        #expect(planned.outcomes.map(\.result) == [.planned])
        let done = await remover.remove([group.items[0].removalRequest], dryRun: false)
        #expect(done.outcomes.map(\.result) == [.removed])

        let forged = RemovalRequest(
            id: "x", kind: "test", name: "x", urls: [], bytes: 1,
            removal: .simulatorRuntime(identifier: "all; rm -rf /"))
        let refused = await remover.remove([forged], dryRun: false)
        #expect(refused.outcomes.first?.result == .failed("bad runtime identifier"))
    }
}

@Suite struct MoreJunkRulesTests {
    @Test func coversBuildCachesToolCachesAndTheTrash() async throws {
        let home = try TempHome()
        try home.file(".gradle/wrapper/dists/gradle-8.9-bin/archive.zip", bytes: 60_000)
        try home.file(".gradle/daemon/8.9/daemon.log", bytes: 4_000)
        try home.file(".gradle/gradle.properties", bytes: 100)
        try home.file(".nuget/packages/newtonsoft.json/13.0.3/lib.dll", bytes: 30_000)
        try home.file(".cache/uv/wheels/x.whl", bytes: 20_000)
        try home.file("Library/Developer/CoreSimulator/Caches/dyld/cache.bin", bytes: 50_000)
        try home.file(".Trash/old-report.pdf", bytes: 9_000)
        try home.file(".Trash/.DS_Store", bytes: 10)

        let scan = await JunkScanner(home: home.url, runner: FakeRunner()).scan()
        let names = Dictionary(uniqueKeysWithValues: scan.groups.map { ($0.id, Set($0.items.map(\.name))) })
        #expect(names[.gradle] == ["gradle-8.9-bin", "8.9"])
        #expect(names[.nuget] == ["newtonsoft.json"])
        #expect(names[.xcodeCaches] == ["dyld"])
        #expect(names[.cliCaches] == ["uv"])
        #expect(names[.trash] == ["old-report.pdf"])

        let ticked = JunkMath.plan(scan, .initial(for: scan))
        #expect(Set(ticked.items.map(\.rule)) == [.gradle, .nuget, .xcodeCaches])

        // Emptying the Trash removes for good, and so does clearing command-line caches: tools download again.
        let trash = try #require(scan.groups.first { $0.id == .trash })
        let caches = try #require(scan.groups.first { $0.id == .cliCaches })
        #expect(trash.items[0].removal == .delete)
        #expect(caches.items[0].removal == .delete)
        let remover = Remover(pathGuard: JunkRules.pathGuard(home: home.url), runner: FakeRunner())
        let report = await remover.remove([trash.items[0].removalRequest], dryRun: false)
        #expect(report.problems.isEmpty)
        #expect(home.exists(".Trash/old-report.pdf") == false)
        #expect(home.exists(".gradle/gradle.properties"))
        #expect(JunkRules.pathGuard(home: home.url).allows(home.path(".Trash")) == false)
    }
}

@Suite struct NestedCachesTests {
    let home: TempHome

    init() throws {
        home = try TempHome()
        try home.file("Library/Application Support/Editor/Cache/data_0", bytes: 80_000)
        try home.file("Library/Application Support/Editor/Service Worker/CacheStorage/blob", bytes: 20_000)
        try home.file("Library/Application Support/Editor/User/settings.json", bytes: 500)
        try home.file("Library/Application Support/Editor/Local Storage/leveldb/000.ldb", bytes: 300)
        // Not laid out like a browser profile: their "Cache" and "cache" folders may mean something else.
        try home.file("Library/Application Support/PythonTool/cache/wheels/x.whl", bytes: 30_000)
        try home.file("Library/Application Support/PlainStore/Cache/data", bytes: 30_000)
        try home.file("Library/Application Support/Editor/Service Worker/Database/db", bytes: 500)
        try home.file("Library/Application Support/Messenger/Code Cache/js/x", bytes: 40_000)
        try home.file("Library/Application Support/Messenger/Local Storage/leveldb/000.ldb", bytes: 700)
        try home.file("Library/Application Support/OpenNow/Cache/data_0", bytes: 10_000)
        try home.file("Library/Application Support/OpenNow/GPUCache/index", bytes: 100)
        try home.file("Library/Application Support/com.apple.wallpaper/Cache/x", bytes: 10_000)
        try home.file("Library/Application Support/Plain/notes.db", bytes: 900)
    }

    @Test func findsCacheFoldersInsideAppDataAndNothingElse() async throws {
        let scan = await JunkScanner(home: home.url, runner: FakeRunner(), runningAppNames: ["opennow"]).scan()
        let group = try #require(scan.groups.first { $0.id == .appDataCaches })
        #expect(group.items.map(\.name) == ["Editor", "Messenger"])
        #expect(group.items[0].urls.map(\.lastPathComponent) == ["Cache", "CacheStorage"])
        #expect(group.skipped == ["OpenNow"])
        #expect(JunkSelection.initial(for: scan).itemIDs.count == 2)

        let remover = Remover(pathGuard: JunkRules.pathGuard(home: home.url), runner: FakeRunner())
        let report = await remover.remove(group.items.map(\.removalRequest), dryRun: false)
        #expect(report.problems.isEmpty)
        #expect(home.exists("Library/Application Support/Editor/Cache") == false)
        #expect(home.exists("Library/Application Support/Editor/Service Worker/CacheStorage") == false)
        for kept in [
            "Library/Application Support/Editor/User/settings.json",
            "Library/Application Support/Editor/Service Worker/Database/db",
            "Library/Application Support/Messenger/Local Storage/leveldb/000.ldb",
            "Library/Application Support/OpenNow/Cache/data_0", "Library/Application Support/Plain/notes.db",
            "Library/Application Support/PythonTool/cache/wheels/x.whl",
            "Library/Application Support/PlainStore/Cache/data",
            "Library/Application Support/Editor/Local Storage/leveldb/000.ldb",
            "Library/Application Support/com.apple.wallpaper/Cache/x",
        ] {
            #expect(home.exists(kept), "\(kept) should still be there")
        }
    }

    @Test func theGuardLetsThroughOnlyTheNamedFoldersOneLevelDown() {
        let pathGuard = JunkRules.pathGuard(home: home.url)
        let support = "Library/Application Support"
        #expect(pathGuard.allows(home.path("\(support)/Editor/Cache")))
        #expect(pathGuard.allows(home.path("\(support)/Editor/Service Worker/CacheStorage")))
        // The app's own folder, its other data, and deeper or shallower paths are all refused.
        #expect(pathGuard.allows(home.path("\(support)/Editor")) == false)
        #expect(pathGuard.allows(home.path("\(support)/Editor/User")) == false)
        #expect(pathGuard.allows(home.path("\(support)/Editor/User/Cache")) == false)
        #expect(pathGuard.allows(home.path("\(support)/Editor/Service Worker")) == false)
        #expect(pathGuard.allows(home.path("\(support)/Cache")) == false)
        #expect(pathGuard.allows(home.path("\(support)")) == false)
    }

    @Test func offersWallpaperVideosAndAndroidToolsForTheOwnerToDecide() async throws {
        try home.file("Library/Application Support/com.apple.wallpaper/aerials/videos/A1.mov", bytes: 90_000)
        try home.file("Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json", bytes: 100)
        try home.file("Library/Android/sdk/ndk/21.4.7075529/toolchain.bin", bytes: 70_000)
        try home.file("Library/Android/sdk/system-images/android-35/google/arm64/system.img", bytes: 60_000)
        try home.file("Library/Android/sdk/platform-tools/adb", bytes: 1_000)

        let scan = await JunkScanner(home: home.url, runner: FakeRunner()).scan()
        let names = Dictionary(uniqueKeysWithValues: scan.groups.map { ($0.id, $0.items.map(\.name)) })
        #expect(names[.wallpaperVideos] == ["A1.mov"])
        #expect(names[.androidNDK] == ["21.4.7075529"])
        #expect(names[.androidImages] == ["android-35"])
        let ticked = Set(JunkMath.plan(scan, .initial(for: scan)).items.map(\.rule))
        #expect(ticked.isDisjoint(with: [.wallpaperVideos, .androidNDK, .androidImages]))
        // They download again, so they are removed for good: moving them to the Trash would free nothing.
        #expect(
            scan.items.filter { [.wallpaperVideos, .androidNDK, .androidImages].contains($0.rule) }.allSatisfy {
                $0.removal == .delete
            })
    }

    @Test func testBrowsersWaitForTheOwnerAndJetBrainsCachesWaitForTheIDE() async throws {
        try home.file("Library/Caches/ms-playwright/chromium-1140/chrome", bytes: 50_000)
        try home.file("Library/Caches/Cypress/13.6.0/Cypress.app", bytes: 40_000)
        try home.file("Library/Caches/JetBrains/IntelliJIdea2025.2/index", bytes: 30_000)
        try home.file("Library/Caches/com.example.app/cache.db", bytes: 20_000)

        let scan = await JunkScanner(home: home.url, runner: FakeRunner()).scan()
        let names = Dictionary(uniqueKeysWithValues: scan.groups.map { ($0.id, Set($0.items.map(\.name))) })
        #expect(names[.appCaches] == ["com.example.app"])
        #expect(names[.testBrowsers] == ["chromium-1140", "13.6.0"])
        #expect(names[.jetBrainsCaches] == ["IntelliJIdea2025.2"])
        let ticked = Set(JunkMath.plan(scan, .initial(for: scan)).items.map(\.rule))
        #expect(ticked.contains(.jetBrainsCaches) && !ticked.contains(.testBrowsers))

        let withIDE = await JunkScanner(
            home: home.url, runner: FakeRunner(), runningBundleIDs: ["com.jetbrains.intellij"]
        ).scan(only: [.jetBrainsCaches])
        #expect(withIDE.items.isEmpty)
        let pathGuard = JunkRules.pathGuard(home: home.url)
        #expect(pathGuard.allows(home.path("Library/Caches/ms-playwright/chromium-1140")))
        #expect(pathGuard.allows(home.path("Library/Caches/JetBrains/IntelliJIdea2025.2")))
    }

    @Test func onlyWhatCannotComeBackGoesToTheTrash() {
        let trashed = Set(JunkRules.all(home: home.url).filter { $0.removal == .trash }.map(\.id))
        #expect(trashed == [.androidDevices, .xcodeArchives])
    }

    @Test func measuresOnlyTheRulesAskedFor() async throws {
        try home.file(".Trash/old-report.pdf", bytes: 9_000)
        try home.file(".gradle/caches/modules-2/x.jar", bytes: 9_000)

        let scan = await JunkScanner(home: home.url, runner: FakeRunner()).scan(only: [.trash])
        #expect(scan.groups.map(\.id) == [.trash])
        #expect(scan.items.map(\.name) == ["old-report.pdf"])
    }

    @Test func tellsWhatWasDeletedFromWhatWentToTheTrash() {
        func request(_ id: String, _ bytes: Int64, _ removal: Removal) -> RemovalOutcome {
            RemovalOutcome(
                request: RemovalRequest(id: id, kind: "k", name: id, urls: [], bytes: bytes, removal: removal),
                result: .removed)
        }
        let report = RemovalReport(outcomes: [
            request("cache", 100, .delete), request("archive", 40, .trash),
            request("device", 7, .simulator(udid: "u")),
        ])
        #expect(report.deletedBytes == 107)
        #expect(report.trashedBytes == 40)
        #expect(report.freedBytes == 147)
        #expect(report.changedTheDisk)
    }

    @Test func saysWhetherTheDiskChanged() {
        let request = RemovalRequest(id: "x", kind: "k", name: "x", urls: [], bytes: 5, removal: .delete)
        let refused = RemovalReport(outcomes: [RemovalOutcome(request: request, result: .refused(.denied))])
        #expect(refused.changedTheDisk == false)
        let skipped = RemovalReport(outcomes: []).adding(skipped: [request], because: "open")
        #expect(skipped.changedTheDisk == false)
        #expect(skipped.problems.map(\.result) == [.skipped("open")])
        #expect(RemovalReport(outcomes: [RemovalOutcome(request: request, result: .removed)]).changedTheDisk)
    }
}
