import Foundation
import Testing

@testable import CareCore

/// An engine that "finds" whatever file names it is told to.
struct FakeEngine: ScanEngine {
    var infectedNames: [String: String] = [:]
    var unreadableNames: Set<String> = []

    func scan(_ url: URL) async throws -> ClamReply {
        var reply = ClamReply()
        var candidates = [url]
        if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            candidates += walker.compactMap { $0 as? URL }
        }
        for file in candidates {
            if let signature = infectedNames[file.lastPathComponent] {
                reply.hits.append(.init(path: file.path, signature: signature))
            }
            if unreadableNames.contains(file.lastPathComponent) {
                reply.errors.append("\(file.path): Access denied. ERROR")
            }
        }
        return reply
    }
}

/// An engine that never answers until the check is stopped.
struct StallingEngine: ScanEngine {
    func scan(_ url: URL) async throws -> ClamReply {
        try await Task.sleep(for: .seconds(60))
        return ClamReply()
    }
}

/// An engine that is not running.
struct DownEngine: ScanEngine {
    func scan(_ url: URL) async throws -> ClamReply {
        throw EngineError.connection("Connection refused")
    }
}

func autostartItem(
    _ label: String, kind: AutostartItem.Kind = .userAgent, target: String?, launcher: String? = nil,
    signature: SignatureInfo.Kind?, enabled: Bool = true
) -> AutostartItem {
    AutostartItem(
        id: "\(kind.rawValue):\(label)", kind: kind, label: label, name: label,
        plist: URL(fileURLWithPath: "/Library/LaunchAgents/\(label).plist"), program: target, target: target,
        launcher: launcher, isTargetMissing: false, isEnabled: enabled, runsAtLoad: true, interval: nil,
        developer: nil, signature: signature.map { SignatureInfo(kind: $0) })
}

@Suite struct ClamTests {
    @Test func readsEngineReplies() {
        let text =
            "/Users/me/Downloads/eicar.com: Eicar-Signature FOUND\0/Users/me/a: b/x.bin: Osx.Trojan.Agent-1 FOUND\0"
            + "/Users/me/Library/Mail: Access denied. ERROR\0/Users/me/gone: lstat() failed: No such file. ERROR\0"
            + "/Users/me/Downloads: OK\0"
        let reply = ClamReply.parse(text)
        #expect(
            reply.hits == [
                .init(path: "/Users/me/Downloads/eicar.com", signature: "Eicar-Signature"),
                .init(path: "/Users/me/a: b/x.bin", signature: "Osx.Trojan.Agent-1"),
            ])
        #expect(reply.errors.count == 2)
        #expect(ClamReply.parse("/clean: OK\n").hits.isEmpty)
        #expect(ClamReply.parse("").hits.isEmpty)
    }

    @Test func writesSettingsThatKeepTheEngineOutOfExcludedFolders() throws {
        let home = try TempHome()
        let paths = ClamPaths(folder: home.path("clamav"))
        try paths.writeConfigs(excluding: [URL(fileURLWithPath: "/Users/me/Library/Mobile Documents")])
        let daemon = try String(contentsOf: paths.daemonConfig, encoding: .utf8)
        #expect(daemon.contains("LocalSocket \(paths.socket)"))
        #expect(daemon.contains("DatabaseDirectory \(paths.database.path)"))
        #expect(daemon.contains("ExcludePath ^/Users/me/Library/Mobile.Documents/"))
        #expect(ClamPaths.pattern(for: "/a.b/c (1)+") == "/a\\.b/c.\\(1\\)\\+")
        #expect(daemon.contains("FollowDirectorySymlinks no"))
        let updater = try String(contentsOf: paths.updaterConfig, encoding: .utf8)
        #expect(updater.contains("DatabaseMirror database.clamav.net"))
        #expect(paths.databaseDate() == nil)
        try home.file("clamav/db/daily.cvd")
        #expect(paths.databaseDate() != nil)
        #expect(paths.socket.utf8.count < 104)
    }

    @Test func aReplySplitsOnNulOnlyAndKeepsHitsInsideTheScannedPath() {
        // A file name may hold a newline. Splitting on it too would hide the first hit and invent a relative one.
        let text =
            "/scan/a\nb: Eicar-Signature FOUND\0relative/x: Fake-1 FOUND\0/elsewhere/f: Fake-2 FOUND\0"
            + "/scan/../Users/me/thesis.docx: Fake-3 FOUND\0/scanner/x: Fake-4 FOUND\0/scan/c d: Osx.Agent FOUND\0"
            + "/scan: OK\0"
        let reply = ClamReply.parse(text, scanned: ["/scan"])
        #expect(
            reply.hits == [
                .init(path: "/scan/a\nb", signature: "Eicar-Signature"),
                .init(path: "/scan/c d", signature: "Osx.Agent"),
            ])
        // Without scanned paths, only absolute paths without "." or ".." pass.
        #expect(ClamReply.parse(text).hits.map(\.signature) == ["Eicar-Signature", "Fake-2", "Fake-4", "Osx.Agent"])
        // The scanned file itself is inside.
        #expect(ClamReply.parse("/scan/e.com: Eicar FOUND\0", scanned: ["/scan/e.com"]).hits.count == 1)
        #expect(ClamReply.parse("/: Eicar FOUND\0/x: Y FOUND\0", scanned: ["/"]).hits.count == 2)
    }

    @Test func aLongHomeFolderGetsAShortSocketPathInTheUsersOwnTemporaryFolder() throws {
        let deep = URL(fileURLWithPath: "/Users/" + String(repeating: "x", count: 120))
        let socket = ClamPaths(folder: deep).socket
        let own = ClamPaths.userTemporaryFolder()
        #expect(own.hasPrefix("/tmp/") == false && own.hasPrefix("/private/tmp/") == false)
        #expect(own.hasSuffix("/"))
        #expect(socket == own + "ward-clamd.sock")
        #expect(socket.utf8.count < 104)
        // Only this user may enter the folder, so nobody else can take the name first.
        let mode = try FileManager.default.attributesOfItem(atPath: own)[.posixPermissions] as? Int
        #expect(mode.map { $0 & 0o077 } == 0)
        let owner = try FileManager.default.attributesOfItem(atPath: own)[.ownerAccountID] as? Int
        #expect(owner == Int(getuid()))
    }

    @Test func theDatabaseIsRefreshedDailyAndNotRetriedWithinTheHour() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func hours(_ count: Double) -> Date { now.addingTimeInterval(-count * 3_600) }
        #expect(ClamPaths.isUpdateDue(lastCheck: nil, lastAttempt: nil, now: now))
        #expect(ClamPaths.isUpdateDue(lastCheck: hours(23), lastAttempt: nil, now: now) == false)
        #expect(ClamPaths.isUpdateDue(lastCheck: hours(25), lastAttempt: nil, now: now))
        #expect(ClamPaths.isUpdateDue(lastCheck: hours(25), lastAttempt: hours(0.5), now: now) == false)
        #expect(ClamPaths.isUpdateDue(lastCheck: hours(25), lastAttempt: hours(2), now: now))
    }

    @Test func onlineOnlyCloudFilesDoNotCountAsUnreadable() {
        let reply = ClamReply(
            hits: [],
            errors: [
                "/Users/me/Documents/notes: one.pages: Can't open file or directory ERROR",
                "/Users/me/Library/Mail: Access denied. ERROR",
                "/Users/me/gone: lstat() failed: No such file or directory. ERROR",
            ])
        #expect(reply.unreadableCount { $0 == "/Users/me/Documents/notes: one.pages" } == 2)
        #expect(reply.unreadableCount { _ in false } == 3)
        // An ordinary file on disk is not online-only.
        #expect(CloudFiles.isOnlineOnly("/bin/ls") == false)
        #expect(CloudFiles.isOnlineOnly("/no/such/file") == false)
    }

    @Test func theEngineIsStartedUnableToDownloadCloudFiles() {
        #expect(CloudFiles.downloadsAllowed)
        let inside = CloudFiles.withoutDownloads { CloudFiles.downloadsAllowed }
        #expect(inside == false)
        #expect(CloudFiles.downloadsAllowed)
    }
}

@Suite struct HeuristicsTests {
    @Test func flagsOnlyWhatDeservesALook() {
        let items = [
            autostartItem("ok.apple", target: "/usr/libexec/thing", signature: .apple),
            autostartItem(
                "ok.vendor", target: "/Applications/V.app/Contents/MacOS/v", signature: .developer(team: "T", name: "V")
            ),
            autostartItem("no.signature", target: "/opt/tool/agent", signature: .unsigned),
            autostartItem("ad.hoc", kind: .daemon, target: "/Library/PrivilegedHelperTools/x", signature: .adHoc),
            autostartItem("changed", target: "/Applications/C.app/Contents/MacOS/c", signature: .broken),
            autostartItem(
                "hidden.signed", target: "/Users/me/.tool/agent", signature: .developer(team: "T", name: "V")),
            autostartItem("hidden", target: "/Users/me/.cache/.upd/agent", signature: .adHoc),
            autostartItem("temporary", target: "/private/tmp/agent", signature: .unsigned),
            autostartItem("script", target: nil, launcher: "sh", signature: nil),
            autostartItem("unreadable", target: "/Library/PrivilegedHelperTools/locked", signature: nil),
            autostartItem("off", target: "/opt/tool/off", signature: .unsigned, enabled: false),
        ]
        let findings = Heuristics.findings(for: items)
        #expect(
            findings.map { "\($0.autostart?.label ?? ""):\($0.reason.key)" } == [
                "no.signature:unsignedAutostart", "ad.hoc:unsignedAutostart", "changed:brokenSignature",
                "hidden:hiddenAutostart", "temporary:hiddenAutostart", "script:scriptAutostart",
            ])
        #expect(findings.allSatisfy { $0.severity == .suspicious })
    }

    @Test func flagsAppsWithoutADeveloperCertificate() {
        let apps = ["/Applications/Good.app", "/Applications/Cracked.app", "/Applications/Edited.app"].map {
            URL(fileURLWithPath: $0)
        }
        let findings = Heuristics.findings(forApps: apps) { url in
            switch url.lastPathComponent {
            case "Cracked.app": SignatureInfo(kind: .adHoc)
            case "Edited.app": SignatureInfo(kind: .broken)
            default: SignatureInfo(kind: .developer(team: "T", name: "Good"))
            }
        }
        #expect(findings.map(\.name) == ["Cracked.app", "Edited.app"])
        #expect(findings.map(\.reason) == [.unsignedApp, .brokenSignature])
    }

    @Test func quarantineAllTakesOnlyMalwareAndNeverTheseApps() throws {
        let home = try TempHome()
        func app(_ name: String, id: String) throws -> URL {
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": id, "CFBundleExecutable": name], format: .xml, options: 0)
            try home.file("Apps/\(name).app/Contents/MacOS/\(name)", bytes: 10)
            try plist.write(to: home.path("Apps/\(name).app/Contents/Info.plist"))
            return home.path("Apps/\(name).app")
        }
        let tidy = try app("Tidy", id: "com.vdzeer.tidy")
        let other = try app("Other", id: "com.example.other")
        let running = home.path("Running/Ward.app")
        let findings = [
            Finding(severity: .malicious, reason: .knownMalware(signature: "A"), url: home.path("Downloads/a.dmg")),
            Finding(severity: .suspicious, reason: .unsignedApp, url: other),
            Finding(severity: .suspicious, reason: .unsignedApp, url: tidy),
            Finding(
                severity: .malicious, reason: .knownMalware(signature: "B"),
                url: tidy.appendingPathComponent("Contents/MacOS/Tidy")),
            Finding(severity: .malicious, reason: .knownMalware(signature: "C"), url: running),
            Finding(
                severity: .malicious, reason: .knownMalware(signature: "D"),
                url: running.appendingPathComponent("Contents/Resources/x")),
            Finding(
                severity: .malicious, reason: .knownMalware(signature: "E"),
                url: other.appendingPathComponent("Contents/MacOS/Other")),
            Finding(
                severity: .malicious, reason: .knownMalware(signature: "F"), url: home.path("Library/LaunchAgents/x"),
                autostart: autostartItem("x", target: "/opt/x", signature: .unsigned)),
        ]
        let taken = BulkQuarantine.findings(findings, sparing: [running])
        #expect(taken.map(\.reason) == [.knownMalware(signature: "A"), .knownMalware(signature: "E")])
    }
}

@Suite struct QuarantineTests {
    @Test func aFileGoesInComesBackUnchangedAndCanBeDeleted() throws {
        let home = try TempHome()
        let store = QuarantineStore(folder: home.path("Quarantine"))
        let file = try home.file("Downloads/tool.bin", bytes: 12_345)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let original = try Data(contentsOf: file)

        let entry = try store.add(file, reason: "Eicar-Signature")
        #expect(home.exists("Downloads/tool.bin") == false)
        #expect(store.entries() == [entry])
        #expect(entry.originalPath == file.path)
        // While it sits in quarantine nobody can read or run it.
        let stored = home.path("Quarantine/\(entry.id)/payload")
        let mode = try FileManager.default.attributesOfItem(atPath: stored.path)[.posixPermissions] as? Int
        #expect(mode == 0)

        try store.restore(entry)
        #expect(try Data(contentsOf: file) == original)
        let restored = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(restored == 0o755)
        #expect(store.entries().isEmpty)

        let again = try store.add(file, reason: "Eicar-Signature")
        try store.delete(again)
        #expect(store.entries().isEmpty)
        #expect(home.exists("Downloads/tool.bin") == false)
        #expect(home.exists("Quarantine/\(again.id)") == false)
    }

    @Test func restoreNeverOverwritesWhatNowSitsThere() throws {
        let home = try TempHome()
        let store = QuarantineStore(folder: home.path("Quarantine"))
        let file = try home.file("Downloads/tool.bin", bytes: 100)
        let entry = try store.add(file, reason: "test")
        try home.file("Downloads/tool.bin", bytes: 7)
        #expect(throws: QuarantineStore.Failure.placeTaken) { try store.restore(entry) }
        #expect(store.entries().count == 1)
        #expect(try Data(contentsOf: file).count == 7)
    }

    @Test func aWholeAppFolderCanBeQuarantined() throws {
        let home = try TempHome()
        let store = QuarantineStore(folder: home.path("Quarantine"))
        try home.file("Apps/Bad.app/Contents/MacOS/bad", bytes: 5_000)
        let entry = try store.add(home.path("Apps/Bad.app"), reason: "unsignedApp")
        #expect(home.exists("Apps/Bad.app") == false)
        try store.restore(entry)
        #expect(home.exists("Apps/Bad.app/Contents/MacOS/bad"))
    }
}

@Suite struct MalwareScannerTests {
    let home: TempHome

    init() throws {
        home = try TempHome()
        try home.file("Downloads/eicar.com", bytes: 68)
        try home.file("Downloads/report.pdf", bytes: 9_000)
        try home.file("Desktop/notes.txt", bytes: 100)
        try home.file("Documents/work/draft.txt", bytes: 100)
        try home.file("Library/LaunchAgents/com.example.plist", bytes: 300)
        try home.file("Library/Mobile Documents/cloud-only.doc", bytes: 100)
        try home.file("Library/Preferences/x.plist", bytes: 100)
        try home.file("Apps/Good.app/Contents/Info.plist", bytes: 100)
    }

    func scanner(trusted: Set<String> = []) -> MalwareScanner {
        MalwareScanner(
            engine: FakeEngine(infectedNames: ["eicar.com": "Eicar-Signature"], unreadableNames: ["notes.txt"]),
            autostart: { [autostartItem("no.signature", target: "/opt/tool/agent", signature: .unsigned)] },
            apps: { [URL(fileURLWithPath: "/Applications/Cracked.app")] },
            inspect: { _ in SignatureInfo(kind: .adHoc) },
            trusted: { trusted })
    }

    @Test func aQuickPlanCoversTheUsualPlaces() {
        let plan = ScanPlan.make(.quick, home: home.url, systemLibrary: home.path("System"), shared: [])
        let names = plan.units.map(\.lastPathComponent)
        #expect(names.contains("Downloads"))
        #expect(names.contains("Desktop"))
        #expect(names.contains("LaunchAgents"))
        #expect(names.contains("Documents") == false)
        #expect(plan.includesOwnChecks)
    }

    @Test func aFullPlanStaysOutOfCloudFolders() {
        let plan = ScanPlan.make(
            .full, home: home.url, systemLibrary: home.path("System"), applications: home.path("Apps"), shared: [])
        let paths = plan.units.map { $0.path.replacingOccurrences(of: home.url.path + "/", with: "") }
        #expect(paths.contains("Documents"))
        #expect(paths.contains("Library/LaunchAgents"))
        #expect(paths.contains("Library/Preferences"))
        #expect(paths.contains("Apps/Good.app"))
        #expect(paths.contains("Library") == false)
        #expect(paths.contains("Library/Mobile Documents") == false)
        #expect(plan.excluded.map(\.lastPathComponent).contains("Mobile Documents"))
    }

    @Test func mergesEngineHitsWithOwnChecksAndPutsMalwareFirst() async throws {
        let plan = ScanPlan.make(.quick, home: home.url, systemLibrary: home.path("System"), shared: [])
        let result = try await scanner().scan(plan)
        #expect(result.findings.map(\.reason.key) == ["malware", "unsignedAutostart", "unsignedApp"])
        #expect(result.findings[0].url.lastPathComponent == "eicar.com")
        #expect(result.findings[0].severity == .malicious)
        #expect(result.filesChecked == 4)
        #expect(result.unreadable == 1)
    }

    @Test func aCustomCheckLooksOnlyWhereItIsTold() async throws {
        let plan = ScanPlan.make(.custom([home.path("Documents"), home.path("missing")]), home: home.url)
        #expect(plan.units.map(\.lastPathComponent) == ["Documents"])
        let result = try await scanner().scan(plan)
        #expect(result.findings.isEmpty)
        #expect(result.filesChecked == 1)
    }

    @Test func stoppingAScanStopsItAtOnce() async throws {
        let plan = ScanPlan.make(.custom([home.path("Downloads"), home.path("Desktop")]), home: home.url)
        let scanner = MalwareScanner(engine: StallingEngine(), autostart: { [] }, apps: { [] })
        let started = Date()
        let task = Task { try await scanner.scan(plan) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func theFileCountGivesUpWhenTheScanIsStopped() async throws {
        let many = try home.folder("Many")
        for index in 0..<5_000 {
            FileManager.default.createFile(atPath: many.appendingPathComponent("f\(index)").path, contents: nil)
        }
        #expect(await MalwareScanner.countFiles(in: many) == 5_000)
        let task = Task {
            try? await Task.sleep(for: .seconds(30))
            return await MalwareScanner.countFiles(in: many)
        }
        task.cancel()
        #expect(await task.value < 5_000)
    }

    @Test func whatTheOwnerChoseToKeepIsNotShownAgain() async throws {
        let home2 = try TempHome()
        let store = TrustStore(fileURL: home2.path("state/trusted.json"))
        let plan = ScanPlan.make(.quick, home: home.url, systemLibrary: home.path("System"), shared: [])
        let first = try await scanner().scan(plan)
        try store.trust(first.findings[2])
        try store.trust(first.findings[2])
        #expect(store.trustedIDs().count == 1)
        let second = try await scanner(trusted: store.trustedIDs()).scan(plan)
        #expect(second.findings.map(\.reason.key) == ["malware", "unsignedAutostart"])
    }
}
