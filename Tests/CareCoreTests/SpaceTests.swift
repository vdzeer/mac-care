import CoreGraphics
import Darwin
import Foundation
import Testing

@testable import CareCore

@Suite struct TreemapTests {
    @Test func boxesFillTheAreaInProportionWithoutOverlap() {
        let weights: [Double] = [212, 148, 96, 74, 41, 38, 28, 22, 13]
        let bounds = CGRect(x: 10, y: 20, width: 536, height: 420)
        let rects = Treemap.layout(weights, in: bounds)
        #expect(rects.count == weights.count)

        let total = weights.reduce(0, +)
        let area = Double(bounds.width * bounds.height)
        for (weight, rect) in zip(weights, rects) {
            #expect(abs(Double(rect.width * rect.height) - area * weight / total) < 1)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
        }
        for first in rects.indices {
            for second in rects.indices where second > first {
                let overlap = rects[first].intersection(rects[second])
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
        // The biggest boxes should not come out as thin slivers.
        #expect(max(rects[0].width / rects[0].height, rects[0].height / rects[0].width) < 3)
    }

    @Test func oddInputsDoNotCrash() {
        #expect(Treemap.layout([], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        #expect(Treemap.layout([0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)) == [.zero, .zero])
        #expect(Treemap.layout([5], in: .zero) == [.zero])
        let single = Treemap.layout([5], in: CGRect(x: 0, y: 0, width: 10, height: 4))
        #expect(single == [CGRect(x: 0, y: 0, width: 10, height: 4)])
    }
}

@Suite struct SpaceScannerTests {
    let home: TempHome

    init() throws {
        home = try TempHome()
        try home.file("Movies/screen.mov", bytes: 900_000)
        try home.file("Movies/clip.mov", bytes: 300_000)
        try home.file("Downloads/backup.zip", bytes: 600_000)
        try home.file("Documents/note.txt", bytes: 2_000)
        try home.file("Library/Caches/huge.bin", bytes: 950_000)
        try home.file(".hidden/huge.bin", bytes: 950_000)
        try home.file("Apps/Editor.app/Contents/Resources/big.dat", bytes: 950_000)

        // Duplicates: three copies of one file, two files of equal size but different contents,
        // and a hard link, which is one file under two names.
        let payload = Data((0..<400_000).map { UInt8($0 % 251) })
        for path in ["Documents/report.pdf", "Downloads/report (1).pdf", "Desktop/report copy.pdf"] {
            let url = home.path(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payload.write(to: url)
        }
        try Data(repeating: 0x11, count: 250_000).write(to: home.path("Documents/a.bin"))
        try Data(repeating: 0x22, count: 250_000).write(to: home.path("Documents/b.bin"))
        try FileManager.default.linkItem(at: home.path("Movies/clip.mov"), to: home.path("Movies/clip-link.mov"))
    }

    @Test func sizesTheChildrenOfAFolder() async {
        let nodes = await SpaceScanner.children(of: home.url)
        #expect(nodes.first?.bytes ?? 0 >= nodes.last?.bytes ?? 0)
        #expect(Set(nodes.map(\.name)).isSuperset(of: ["Movies", "Downloads", "Documents", "Library", "Apps"]))
        #expect(nodes.allSatisfy { $0.isFolder && $0.bytes > 0 })
        let movies = nodes.first { $0.name == "Movies" }
        #expect(movies?.bytes == DirectorySizer.usage(of: home.path("Movies")).bytes)
    }

    @Test func listsBigFilesOfTheOwnerOnly() {
        let files = SpaceScanner.largeFiles(in: [home.url], atLeast: 500_000)
        #expect(files.map(\.url.lastPathComponent) == ["screen.mov", "backup.zip"])
        #expect(files.allSatisfy { $0.lastOpened.timeIntervalSinceNow > -3600 })
        #expect(SpaceScanner.largeFiles(in: [home.url], atLeast: 500_000, limit: 1).count == 1)
    }

    @Test func findsOnlyTrueCopies() {
        let groups = SpaceScanner.duplicates(in: [home.url], atLeast: 100_000)
        #expect(groups.count == 1)
        #expect(
            groups.first?.files.map(\.lastPathComponent) == ["report copy.pdf", "report.pdf", "report (1).pdf"])
        #expect(groups.first?.bytes == 400_000)
        #expect(groups.first?.wasted == 800_000)
    }

    @Test func aCloneIsNotASecondCopy() throws {
        // An APFS clone shares its blocks with the original: together they take the space of one copy.
        let original = home.path("Documents/report.pdf")
        #expect(clonefile(original.path, home.path("Documents/report clone.pdf").path, 0) == 0)
        let groups = SpaceScanner.duplicates(in: [home.url], atLeast: 100_000)
        #expect(groups.count == 1)
        // One name of the pair stays in the list, the other is left out.
        #expect(
            groups.first?.files.map(\.lastPathComponent) == ["report copy.pdf", "report clone.pdf", "report (1).pdf"])
        #expect(groups.first?.wasted == 800_000)
    }

    @Test func checksTheCopiesAgainRightBeforeTheyGo() throws {
        let group = try #require(SpaceScanner.duplicates(in: [home.url], atLeast: 100_000).first)
        let keep = group.files[0]
        let copy = group.files[1]
        #expect(SpaceScanner.confirmedCopies([copy], of: group) == [copy])
        // Every file of the group chosen: nothing would stay to compare with, so nothing goes.
        #expect(SpaceScanner.confirmedCopies(group.files, of: group).isEmpty)

        // Edited since the comparison, with the size unchanged.
        let original = try Data(contentsOf: copy)
        var edited = original
        edited[0] = edited[0] &+ 1
        try edited.write(to: copy)
        #expect(SpaceScanner.confirmedCopies([copy], of: group).isEmpty)
        try original.write(to: copy)
        #expect(SpaceScanner.confirmedCopies([copy], of: group) == [copy])

        // Grown since the comparison.
        try (original + Data([1])).write(to: copy)
        #expect(SpaceScanner.confirmedCopies([copy], of: group).isEmpty)
        try original.write(to: copy)

        // The copy that was to stay is gone: the last ones never go.
        try FileManager.default.removeItem(at: keep)
        #expect(SpaceScanner.confirmedCopies([copy], of: group) == [copy], "a third copy still stays")
        #expect(SpaceScanner.confirmedCopies([copy, group.files[2]], of: group).isEmpty)
    }

    @Test func neverReadsAFileThatIsOnlyInICloud() {
        var info = stat()
        #expect(SpaceScanner.isDataless(info) == false)
        info.st_flags = UInt32(SF_DATALESS)
        #expect(SpaceScanner.isDataless(info))
        info.st_flags = UInt32(UF_HIDDEN)
        #expect(SpaceScanner.isDataless(info) == false)
    }

    @Test func hashesTheStartOrTheWholeFile() throws {
        let first = home.path("Documents/a.bin")
        #expect(SpaceScanner.hash(first, limit: 16) == SpaceScanner.hash(first, limit: 16))
        #expect(SpaceScanner.hash(first, limit: nil) != SpaceScanner.hash(home.path("Documents/b.bin"), limit: nil))
        #expect(SpaceScanner.hash(home.path("missing"), limit: nil) == nil)
    }

    @Test func theGuardForOwnFilesStaysOutOfLibraryAndKeys() {
        let pathGuard = SpaceScanner.pathGuard(home: home.url)
        #expect(pathGuard.allows(home.path("Movies/screen.mov")))
        #expect(pathGuard.allows(home.path("Library/Caches/huge.bin")) == false)
        #expect(pathGuard.allows(home.path(".ssh/id_ed25519")) == false)
        #expect(pathGuard.allows(URL(fileURLWithPath: "/etc/hosts")) == false)
    }
}

@Suite struct SystemMetricsTests {
    @Test func readsPlausibleNumbers() throws {
        let meter = SystemMeter()
        let first = meter.read(at: Date())
        #expect(first.cpu == 0)
        #expect(first.memoryTotal == Int64(ProcessInfo.processInfo.physicalMemory))
        #expect(first.memoryUsed > 0 && first.memoryUsed <= first.memoryTotal)
        Thread.sleep(forTimeInterval: 0.3)
        let second = meter.read(at: Date())
        #expect(second.cpu >= 0 && second.cpu <= 1)
        #expect(second.networkIn >= 0 && second.networkOut >= 0)
        #expect(second.memoryFraction > 0 && second.memoryFraction <= 1)
    }

    @Test func picksTheHeaviestProcesses() {
        let text = """
              101  64,0 5242880 Xcode
              202  22.5 7864320 Google Chrome
              303   0.0   10240 idle thing
              404  14.0 3145728 Simulator
            garbage line
              505   1.0 4194304 Docker
            """
        let heavy = HeavyProcesses.parse(text, limit: 3)
        #expect(heavy.map(\.name) == ["Xcode", "Google Chrome", "Simulator"])
        #expect(heavy[0].cpu == 64)
        #expect(heavy[1].memory == 7_864_320 * 1024)
        #expect(HeavyProcesses.parse("", limit: 3).isEmpty)
    }

    @Test func readsTheRealProcessList() async {
        let heavy = await HeavyProcesses.sample(runner: SystemCommandRunner(), limit: 4)
        #expect(heavy.count == 4)
        #expect(heavy.allSatisfy { $0.name.isEmpty == false && $0.memory > 0 })
    }
}

@Suite struct SystemDataTests {
    let home: TempHome

    init() throws {
        home = try TempHome()
        try home.file("User/.gradle/caches/modules/big.jar", bytes: 400_000)
        try home.file("User/.gradle/jdks/jdk/bin", bytes: 100_000)
        try home.file("User/.codex/sessions/session.jsonl", bytes: 150_000)
        try home.file("User/.mystery/blob", bytes: 120_000)
        try home.file("User/.tiny/blob", bytes: 10)
        try home.file("User/.zshrc", bytes: 100)
        try home.file("User/.Trash/old.zip", bytes: 130_000)
        try home.file("User/Library/Caches/com.example/blob", bytes: 200_000)
        try home.file("User/Library/Application Support/Editor/data.db", bytes: 300_000)
        try home.file("User/Library/Application Support/com.apple.wallpaper/aerials/videos/a.mov", bytes: 250_000)
        try home.file("User/Library/Application Support/com.apple.TCC/TCC.db", bytes: 110_000)
        try home.file("User/Library/Containers/com.docker.docker/Data/vm.raw", bytes: 500_000)
        try home.file("User/Library/Containers/com.vendor.app/Data/file", bytes: 140_000)
        try home.file("User/Documents/thesis.txt", bytes: 900_000)
        try home.file("private/var/vm/swapfile0", bytes: 600_000)
        try home.file("opt/homebrew/Cellar/tool/1.0/bin/tool", bytes: 180_000)
    }

    func scanner() -> SystemDataScanner {
        SystemDataScanner(home: home.path("User"), root: home.url, minimum: 50_000)
    }

    @Test func listsTheKnownPlacesBiggestFirstAndSkipsTheOwnersFiles() async {
        let places = await scanner().places()
        let byName = Dictionary(uniqueKeysWithValues: places.map { ($0.name, $0) })
        #expect(places.map(\.bytes) == places.map(\.bytes).sorted(by: >))
        #expect(byName["Documents"] == nil)
        #expect(byName[".tiny"] == nil)
        #expect(byName[".zshrc"] == nil)

        #expect(byName[".gradle"]?.known == .gradle)
        #expect(byName[".gradle"]?.group == .developer)
        #expect(byName[".codex"]?.known == .assistant)
        #expect(byName[".mystery"]?.known == .hiddenFolder)
        #expect(byName[".Trash"]?.group == .system)
        #expect(byName["Caches"]?.known == .appCaches)
        #expect(byName["Editor"]?.known == .appData)
        #expect(byName["com.apple.wallpaper"]?.known == .wallpapers)
        #expect(byName["com.apple.TCC"]?.known == .appleData)
        #expect(byName["com.docker.docker"]?.known == .docker)
        #expect(byName["com.vendor.app"]?.known == .container)
        #expect(byName["vm"]?.known == .swap)
        #expect(byName["homebrew"]?.known == .homebrew)

        #expect(byName["vm"]?.isManaged == true)
        #expect(byName["com.docker.docker"]?.isManaged == true)
        #expect(byName["com.apple.TCC"]?.isManaged == true)
        #expect(byName[".gradle"]?.isManaged == false)
    }

    @Test func saysHowMuchOfAPlaceTheJunkRulesCanRemove() async throws {
        let places = await scanner().places()
        let scan = await JunkScanner(home: home.path("User"), runner: FakeRunner()).scan()
        let gradle = try #require(places.first { $0.name == ".gradle" })
        let cleanable = SystemDataScanner.cleanable(in: gradle, scan)
        // The caches can go; the JDKs next to them are not junk.
        #expect(cleanable > 0 && cleanable < gradle.bytes)
        let wallpapers = try #require(places.first { $0.name == "com.apple.wallpaper" })
        #expect(SystemDataScanner.cleanable(in: wallpapers, scan) > 0)
        let assistant = try #require(places.first { $0.name == ".codex" })
        #expect(SystemDataScanner.cleanable(in: assistant, scan) == 0)
        let trash = try #require(places.first { $0.name == ".Trash" })
        #expect(SystemDataScanner.cleanable(in: trash, scan) > 0)
    }
}
