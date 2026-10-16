import Foundation
import Testing

@testable import CareCore

@Suite struct LiveGuardTests {
    let home: TempHome

    init() throws {
        home = try TempHome()
        try home.file("Downloads/eicar.com", bytes: 68)
        try home.file("Downloads/report.pdf", bytes: 500)
        try home.file("Downloads/movie.mkv.crdownload", bytes: 500)
        try home.file("Downloads/.DS_Store", bytes: 10)
        try home.file("Downloads/Tool.app/Contents/MacOS/tool", bytes: 500)
        try home.file("Downloads/Tool.app/Contents/Info.plist", bytes: 50)
        try home.file("Library/LaunchAgents/com.bad.plist", bytes: 200)
        try home.file("Documents/outside.txt", bytes: 10)
    }

    func inspector() -> LiveInspector {
        let plist = home.path("Library/LaunchAgents/com.bad.plist")
        return LiveInspector(
            home: home.url, engine: FakeEngine(infectedNames: ["eicar.com": "Eicar-Test-Signature"]),
            autostart: {
                [
                    AutostartItem(
                        id: "userAgent:com.bad", kind: .userAgent, label: "com.bad", name: "com.bad", plist: plist,
                        program: "/opt/bad", target: "/opt/bad", launcher: nil, isTargetMissing: false, isEnabled: true,
                        runsAtLoad: true, interval: nil, developer: nil, signature: SignatureInfo(kind: .unsigned))
                ]
            },
            inspect: { _ in SignatureInfo(kind: .adHoc) })
    }

    @Test func aBurstOfChangesBecomesAShortListOfThingsToCheck() {
        let units = LiveInspector.units(from: [
            home.path("Downloads/report.pdf"), home.path("Downloads/report.pdf"),
            home.path("Downloads/movie.mkv.crdownload"), home.path("Downloads/.DS_Store"),
            home.path("Downloads/Tool.app/Contents/MacOS/tool"), home.path("Downloads/Tool.app/Contents/Info.plist"),
            home.path("Downloads/already-gone.zip"),
        ])
        #expect(units.map(\.lastPathComponent) == ["report.pdf", "Tool.app"])
    }

    @Test func judgesEachNewFile() async {
        let events = await inspector().inspect(
            [
                home.path("Downloads/eicar.com"), home.path("Downloads/report.pdf"),
                home.path("Downloads/Tool.app/Contents/MacOS/tool"), home.path("Library/LaunchAgents/com.bad.plist"),
                home.path("Documents/outside.txt"),
            ], places: [.downloads, .autostart])
        #expect(events.map(\.url.lastPathComponent) == ["eicar.com", "report.pdf", "Tool.app", "com.bad.plist"])
        #expect(events.map(\.place) == [.downloads, .downloads, .downloads, .autostart])

        guard case .flagged(let malware) = events[0].verdict else { Issue.record("expected a finding"); return }
        #expect(malware.severity == .malicious)
        #expect(events[1].verdict == .clean)
        guard case .flagged(let app) = events[2].verdict else { Issue.record("expected a finding"); return }
        #expect(app.reason == .unsignedApp)
        guard case .flagged(let job) = events[3].verdict else { Issue.record("expected a finding"); return }
        #expect(job.reason == .unsignedAutostart)
    }

    @Test func aFileTheEngineCouldNotCheckIsNotCalledClean() async {
        let down = LiveInspector(home: home.url, engine: DownEngine(), autostart: { [] }) { _ in
            SignatureInfo(kind: .developer(team: "T", name: "Example Ltd"), notarized: false)
        }
        let events = await down.inspect(
            [home.path("Downloads/report.pdf"), home.path("Downloads/Tool.app/Contents/MacOS/tool")],
            places: [.downloads])
        #expect(events.map(\.verdict) == [.notChecked, .notChecked])
        // What Ward checks itself is still reported.
        #expect(events[1].signer == "Example Ltd")
        #expect(events[1].notarized == false)

        // The engine answered, but could not read the file itself.
        let unreadable = LiveInspector(
            home: home.url, engine: FakeEngine(unreadableNames: ["report.pdf"]), autostart: { [] })
        let more = await unreadable.inspect([home.path("Downloads/report.pdf")], places: [.downloads])
        #expect(more.map(\.verdict) == [.notChecked])
    }

    @Test func aPlaceThatIsSwitchedOffIsNotChecked() async {
        let events = await inspector().inspect([home.path("Downloads/eicar.com")], places: [.autostart])
        #expect(events.isEmpty)
    }

    @Test func theWatcherReportsANewFile() async throws {
        let folder = try home.folder("Watched")
        let (stream, continuation) = AsyncStream.makeStream(of: [URL].self)
        let watcher = FileWatcher(folders: [folder], latency: 0.2) { continuation.yield($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        try home.file("Watched/new-file.bin", bytes: 100)

        let seen = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await batch in stream where batch.contains(where: { $0.lastPathComponent == "new-file.bin" }) {
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(seen)
    }
}

@Suite struct SettleQueueTests {
    let start = Date(timeIntervalSince1970: 1_000_000)
    func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test func aThingIsHandedOutOnceItHasBeenQuiet() {
        var queue = SettleQueue(quiet: 4, longest: 60)
        let app = URL(fileURLWithPath: "/Applications/Big.app")
        let file = URL(fileURLWithPath: "/Users/me/Downloads/a.zip")
        #expect(queue.nextDue() == nil)

        // A copy in progress keeps changing: it waits.
        queue.note([app], at: at(0))
        queue.note([file], at: at(1))
        for second in stride(from: 2.0, through: 10, by: 2) {
            queue.note([app], at: at(second))
        }
        #expect(queue.nextDue() == at(5))
        #expect(queue.take(at: at(4)).isEmpty)
        #expect(queue.take(at: at(5)) == [file])
        #expect(queue.nextDue() == at(14))
        #expect(queue.take(at: at(14)) == [app])
        #expect(queue.nextDue() == nil)
        #expect(queue.isEmpty == false)

        // A change while it is being checked waits until that check is over, then for another quiet moment.
        queue.note([app], at: at(15))
        #expect(queue.nextDue() == nil)
        #expect(queue.take(at: at(30)).isEmpty)
        queue.finish([app])
        #expect(queue.take(at: at(30)) == [app])
        queue.finish([app, file])
        #expect(queue.isEmpty)
    }

    @Test func somethingThatNeverStopsChangingIsStillChecked() {
        var queue = SettleQueue(quiet: 4, longest: 60)
        let log = URL(fileURLWithPath: "/Users/me/Downloads/growing.log")
        for second in stride(from: 0.0, through: 70, by: 2) {
            queue.note([log], at: at(second))
            if second == 58 { #expect(queue.take(at: at(second)).isEmpty) }
        }
        #expect(queue.nextDue() == at(60))
        #expect(queue.take(at: at(70)) == [log])
    }
}

@Suite struct DailyCountTests {
    @Test func startsAgainAtMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Kyiv"))
        func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        var count = DailyCount()
        #expect(count.value(at: time(16, 9), calendar: calendar) == 0)
        count.add(5, at: time(16, 10), calendar: calendar)
        count.add(2, at: time(16, 23, 59), calendar: calendar)
        #expect(count.value(at: time(16, 23, 59), calendar: calendar) == 7)
        // Nothing new came in after midnight, and still the number is gone.
        #expect(count.value(at: time(17, 0, 1), calendar: calendar) == 0)
        count.add(1, at: time(17, 8), calendar: calendar)
        #expect(count.value(at: time(17, 9), calendar: calendar) == 1)
    }
}
