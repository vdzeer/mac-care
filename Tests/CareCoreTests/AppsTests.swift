import Foundation
import Testing

@testable import CareCore

@Suite struct AppsTests {
    let home: TempHome
    let finder: LeftoverFinder

    init() throws {
        let home = try TempHome()
        self.home = home
        finder = LeftoverFinder(home: home.url, applicationFolders: [home.path("Applications")])
        func app(_ relative: String, id: String) throws {
            let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": "2.1"]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            let url = home.path("\(relative)/Contents/Info.plist")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            try home.file("\(relative)/Contents/MacOS/main", bytes: 50_000)
        }
        try app("Applications/Postman.app", id: "com.postmanlabs.mac")
        try app("Applications/Utilities/Notes Pro.app", id: "com.vendor.notespro")
        try app("Applications/Pad.app", id: "com.apple.pad")
        try home.file("Applications/readme.txt")

        // Postman's own traces.
        try home.file("Library/Application Support/Postman/data.db", bytes: 90_000)
        try home.file("Library/Caches/com.postmanlabs.mac/blob", bytes: 30_000)
        try home.file("Library/Caches/com.postmanlabs.mac.ShipIt/update.zip", bytes: 20_000)
        try home.file("Library/Preferences/com.postmanlabs.mac.plist", bytes: 400)
        try home.file("Library/Saved Application State/com.postmanlabs.mac.savedState/windows.plist", bytes: 800)
        try home.file("Library/Logs/Postman/main.log", bytes: 3_000)
        try home.file("Library/LaunchAgents/com.postmanlabs.mac.helper.plist", bytes: 300)

        // Things that only look similar, and must stay.
        try home.file("Library/Application Support/Postman Agent/data.db", bytes: 1_000)
        try home.file("Library/Caches/com.postmanlabs.macintosh/blob", bytes: 1_000)
        try home.file("Library/Preferences/com.postmanlabs.plist", bytes: 100)
        try home.file("Library/Preferences/com.apple.pad.plist", bytes: 100)
        try home.file("Documents/Postman/collection.json", bytes: 1_000)

        // Traces of apps that are gone, and of a tool that never was an app.
        try home.file("Library/Application Support/com.gone.editor/state", bytes: 40_000)
        try home.file("Library/Preferences/com.gone.editor.plist", bytes: 200)
        try home.file("Library/Caches/org.swift.swiftpm/cache", bytes: 5_000)
        try home.file("Library/Caches/com.apple.Safari/blob", bytes: 5_000)
        try home.file("Library/Caches/SomeFolder/blob", bytes: 5_000)

    }

    func relative(_ url: URL) -> String {
        url.path.replacingOccurrences(of: home.url.path + "/", with: "")
    }

    @Test func listsAppsIncludingOneFolderDeep() {
        let apps = AppInventory.apps(in: [home.path("Applications"), home.path("Missing")])
        #expect(apps.map(\.name) == ["Notes Pro", "Pad", "Postman"])
        #expect(apps.map(\.bundleID) == ["com.vendor.notespro", "com.apple.pad", "com.postmanlabs.mac"])
        #expect(apps[2].version == "2.1")
        #expect(apps[1].isApple)
    }

    @Test func findsExactlyWhatBelongsToTheApp() throws {
        let app = try #require(AppInventory.app(at: home.path("Applications/Postman.app")))
        let footprint = finder.footprint(of: app)
        #expect(
            Set(footprint.parts.map { relative($0.url) }) == [
                "Applications/Postman.app", "Library/Application Support/Postman", "Library/Caches/com.postmanlabs.mac",
                "Library/Caches/com.postmanlabs.mac.ShipIt", "Library/Preferences/com.postmanlabs.mac.plist",
                "Library/Saved Application State/com.postmanlabs.mac.savedState", "Library/Logs/Postman",
                "Library/LaunchAgents/com.postmanlabs.mac.helper.plist",
            ])
        #expect(footprint.parts.first?.kind == .app)
        #expect(footprint.bytes == footprint.parts.reduce(0) { $0 + $1.bytes })
        #expect(footprint.parts.allSatisfy { $0.bytes > 0 })
    }

    @Test func offersNothingBeyondTheBundleForAppleApps() throws {
        let app = try #require(AppInventory.app(at: home.path("Applications/Pad.app")))
        #expect(finder.footprint(of: app).parts.map(\.kind) == [.app])
    }

    @Test func uninstallMovesEveryPartToTheTrashAndLeavesNeighbours() async throws {
        let app = try #require(AppInventory.app(at: home.path("Applications/Postman.app")))
        let footprint = finder.footprint(of: app)
        let trash = try home.folder("FakeTrash")
        let remover = Remover(pathGuard: finder.pathGuard, runner: FakeRunner()) { url in
            try FileManager.default.moveItem(
                at: url, to: trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent))
        }
        let report = await remover.remove(footprint.parts.map { $0.removalRequest(owner: app.name) }, dryRun: false)
        #expect(report.problems.isEmpty)
        #expect(report.freedBytes == footprint.bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).count == footprint.parts.count)

        for gone in footprint.parts { #expect(FileManager.default.fileExists(atPath: gone.url.path) == false) }
        for kept in [
            "Library/Application Support/Postman Agent/data.db", "Library/Caches/com.postmanlabs.macintosh/blob",
            "Library/Preferences/com.postmanlabs.plist", "Documents/Postman/collection.json",
            "Applications/Utilities/Notes Pro.app/Contents/MacOS/main", "Library/Preferences/com.apple.pad.plist",
        ] {
            #expect(home.exists(kept), "\(kept) should still be there")
        }
    }

    @Test func theUninstallGuardRefusesDocuments() {
        #expect(finder.pathGuard.allows(home.path("Documents/Postman")) == false)
        #expect(finder.pathGuard.allows(home.path("Library/Application Support")) == false)
        #expect(finder.pathGuard.allows(home.path("Library/Application Support/Postman")))
    }

    @Test func findsLeftoversOfAppsThatAreGone() {
        let installed = AppInventory.apps(in: [home.path("Applications")])
        let orphans = finder.orphans(installed: installed)
        #expect(orphans.map(\.bundleID) == ["com.gone.editor", "org.swift.swiftpm", "com.postmanlabs.macintosh"])
        #expect(orphans[0].parts.count == 2)
        #expect(orphans.allSatisfy { $0.bytes > 0 })
    }

    @Test func leftoversStartUntickedAndAnAppStartsTicked() throws {
        let orphans = finder.orphans(installed: AppInventory.apps(in: [home.path("Applications")]))
        let group = try #require(orphans.first)
        #expect(group.initiallyUnticked == Set(group.parts.map(\.id)))
        let app = try #require(AppInventory.app(at: home.path("Applications/Postman.app")))
        #expect(finder.footprint(of: app).initiallyUnticked.isEmpty)
    }

    @Test func uninstallTakesTheAppFirstAndStopsWhenItCannotGo() async throws {
        let app = try #require(AppInventory.app(at: home.path("Applications/Postman.app")))
        let footprint = finder.footprint(of: app)
        // Like an App Store app owned by root: the bundle refuses to move, everything else would.
        let trash = try home.folder("FakeTrash")
        let stubborn = Remover(pathGuard: finder.pathGuard, runner: FakeRunner()) { url in
            guard url.pathExtension != "app" else { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(
                at: url, to: trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent))
        }
        let shuffled = Array(footprint.parts.reversed())
        let report = await stubborn.uninstall(shuffled, owner: app.name, dryRun: false)
        #expect(report.removed.isEmpty)
        #expect(report.appStayed)
        #expect(report.changedTheDisk == false)
        #expect(report.outcomes.first?.request.urls == [app.url])
        #expect(report.outcomes.dropFirst().allSatisfy { $0.result == .skipped(Remover.appStayed) })
        #expect(report.outcomes.count == footprint.parts.count)
        for part in footprint.parts { #expect(FileManager.default.fileExists(atPath: part.url.path)) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)

        // When the bundle goes, the rest follows it.
        let willing = Remover(pathGuard: finder.pathGuard, runner: FakeRunner()) { url in
            try FileManager.default.moveItem(
                at: url, to: trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent))
        }
        let done = await willing.uninstall(shuffled, owner: app.name, dryRun: false)
        #expect(done.outcomes.first?.request.urls == [app.url])
        #expect(done.removed.count == footprint.parts.count)
        #expect(done.appStayed == false)
        for part in footprint.parts { #expect(FileManager.default.fileExists(atPath: part.url.path) == false) }
    }

    @Test func recognisesIdentifiers() {
        #expect(LeftoverFinder.looksLikeBundleID("com.vendor.app"))
        #expect(LeftoverFinder.looksLikeBundleID("org.swift.swiftpm"))
        #expect(LeftoverFinder.looksLikeBundleID("Postman") == false)
        #expect(LeftoverFinder.looksLikeBundleID("com.vendor") == false)
        #expect(LeftoverFinder.looksLikeBundleID("com..app") == false)
        #expect(LeftoverFinder.looksLikeBundleID("my file.v2.final") == false)
    }
}

/// Apps whose identifiers share a beginning: each takes only what is its own.
@Suite struct UninstallNeighboursTests {
    let home: TempHome
    let finder: LeftoverFinder
    let installed: [InstalledApp]

    init() throws {
        let home = try TempHome()
        self.home = home
        finder = LeftoverFinder(home: home.url, applicationFolders: [home.path("Applications")])
        func app(_ relative: String, id: String) throws {
            let plist: [String: Any] = ["CFBundleIdentifier": id]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            let url = home.path("\(relative)/Contents/Info.plist")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            try home.file("\(relative)/Contents/MacOS/main", bytes: 10_000)
        }
        try app("Applications/Google Chrome.app", id: "com.google.Chrome")
        try app("Applications/Google Chrome Beta.app", id: "com.google.Chrome.beta")
        try app("Applications/IntelliJ IDEA.app", id: "com.jetbrains.intellij")
        try app("Applications/IntelliJ IDEA CE.app", id: "com.jetbrains.intellij.ce")
        try app("Applications/Sneaky.app", id: "com.google")
        try app("Applications/Notes.app", id: "com.vendor.notes")
        try app("Applications/Old/Notes.app", id: "com.vendor.notes")

        for path in [
            "Library/Caches/com.google.Chrome/blob", "Library/Caches/com.google.Chrome.beta/blob",
            "Library/Application Support/com.google.Chrome.beta.helper/state",
            "Library/Caches/com.google.Keystone/blob", "Library/Caches/com.google.SoftwareUpdate/blob",
            "Library/Caches/com.jetbrains.intellij/index", "Library/Caches/com.jetbrains.intellij.ce/index",
            "Library/Containers/com.vendor.notes/Data/notes.db",
        ] {
            try home.file(path, bytes: 2_000)
        }
        for name in [
            "com.google.Chrome", "com.google.Chrome.beta", "com.google.Keystone.Agent", "com.jetbrains.intellij",
            "com.jetbrains.intellij.ce", "com.vendor.notes",
        ] {
            try home.file("Library/Preferences/\(name).plist", bytes: 100)
        }
        installed = AppInventory.apps(in: [home.path("Applications")])
    }

    func taken(by path: String) throws -> Set<String> {
        let app = try #require(installed.first { $0.url.path == home.path(path).path })
        return Set(
            finder.footprint(of: app, among: installed).parts.dropFirst().map {
                $0.url.path.replacingOccurrences(of: home.url.path + "/Library/", with: "")
            })
    }

    @Test func leavesWhatALongerIdentifierAnswersTo() throws {
        #expect(
            try taken(by: "Applications/Google Chrome.app") == [
                "Caches/com.google.Chrome", "Preferences/com.google.Chrome.plist",
            ])
        #expect(
            try taken(by: "Applications/Google Chrome Beta.app") == [
                "Caches/com.google.Chrome.beta", "Application Support/com.google.Chrome.beta.helper",
                "Preferences/com.google.Chrome.beta.plist",
            ])
        #expect(
            try taken(by: "Applications/IntelliJ IDEA.app") == [
                "Caches/com.jetbrains.intellij", "Preferences/com.jetbrains.intellij.plist",
            ])
        #expect(
            try taken(by: "Applications/IntelliJ IDEA CE.app") == [
                "Caches/com.jetbrains.intellij.ce", "Preferences/com.jetbrains.intellij.ce.plist",
            ])
    }

    @Test func aShortIdentifierTakesNothingOfItsVendor() throws {
        #expect(try taken(by: "Applications/Sneaky.app").isEmpty)
        let sneaky = try #require(installed.first { $0.bundleID == "com.google" })
        #expect(LeftoverFinder.belongs("com.google.Keystone", to: sneaky, byName: false) == false)
        #expect(LeftoverFinder.belongs("com.google", to: sneaky, byName: false))
    }

    @Test func aSecondCopyOfAnAppLeavesTheDataToTheOneThatStays() throws {
        #expect(try taken(by: "Applications/Old/Notes.app").isEmpty)
        #expect(try taken(by: "Applications/Notes.app").isEmpty)
        // Alone, the app takes its data as before.
        let notes = try #require(installed.first { $0.url.path == home.path("Applications/Notes.app").path })
        #expect(finder.footprint(of: notes).parts.count == 3)
    }
}
