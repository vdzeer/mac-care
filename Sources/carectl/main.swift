import CareCore
import Foundation

// A developer tool: runs the core against this Mac from a terminal, without the apps.
// Everything here only reads, except commands that say otherwise and ask for --yes.

// Line by line, so progress shows at once even when the output goes to a file.
setvbuf(stdout, nil, _IOLBF, 0)

let arguments = Array(CommandLine.arguments.dropFirst())
let home = FileManager.default.homeDirectoryForCurrentUser
let runner = SystemCommandRunner()

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{00A0}", with: " ")
}

func column(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func junk(_ rest: [String]) async {
    let scan = await JunkScanner(home: home, runner: runner).scan()
    let selection = JunkSelection.initial(for: scan)
    switch rest.first {
    case "scan", nil:
        for group in scan.groups {
            let mark = group.rule.cleanupClass == .regenerates ? "+" : "?"
            print(
                "\(mark) \(column(group.id.rawValue, 16)) \(column(plain(ByteFormat.string(group.bytes)), 10)) \(group.bytes) B, items: \(group.items.count)"
            )
            if rest.contains("--items") {
                for item in group.items.prefix(8) {
                    print("    \(column(plain(ByteFormat.string(item.bytes)), 10)) \(item.name)")
                }
            }
        }
        let plan = JunkMath.plan(scan, selection)
        print(
            "selected in advance: \(plain(ByteFormat.string(plan.bytes))) (\(plan.bytes) B) in \(plan.items.count) items"
        )
    case "dry-run":
        let plan = JunkMath.plan(scan, selection)
        let remover = Remover(pathGuard: JunkRules.pathGuard(home: home), runner: runner)
        let report = await remover.remove(plan.items.map(\.removalRequest), dryRun: true)
        print("would remove: \(report.planned.count) items, \(plain(ByteFormat.string(report.plannedBytes)))")
        print("refused or failed: \(report.problems.count)")
        for problem in report.problems.prefix(20) {
            print("  \(problem.request.name): \(problem.result)")
        }
    default:
        fail(usage)
    }
}

func signer(_ signature: SignatureInfo?) -> String {
    switch signature?.kind {
    case .apple: "Apple"
    case .developer(let team, let name): "\(name) (\(team))"
    case .adHoc: "ad hoc"
    case .unsigned: "UNSIGNED"
    case .broken: "BROKEN"
    case nil: "-"
    }
}

func autostart() async {
    let items = await AutostartInventory(home: home, runner: runner).items()
    for item in items {
        let state = item.isEnabled ? "on " : "off"
        var who = signer(item.signature)
        if item.isTargetMissing { who = "MISSING" }
        if let launcher = item.launcher { who += " via \(launcher)" }
        print("\(state) \(column(item.kind.rawValue, 11)) \(column(item.name, 30)) \(column(who, 46)) \(item.label)")
    }
    print("items: \(items.count)")
}

func reason(_ finding: Finding) -> String {
    switch finding.reason {
    case .knownMalware(let signature): "MALWARE \(signature)"
    case .unsignedAutostart: "autostart without a developer certificate"
    case .hiddenAutostart: "autostart from a hidden or temporary folder"
    case .scriptAutostart: "autostart that runs an inline script"
    case .brokenSignature: "signature no longer matches the file"
    case .unsignedApp: "app without a developer certificate"
    }
}

func shield(_ rest: [String]) async {
    let daemon = ClamDaemon()
    switch rest.first {
    case "update":
        do {
            try await daemon.updateDatabase()
            print("database: \(daemon.paths.databaseDate().map(String.init(describing:)) ?? "none")")
        } catch { fail("update failed: \(error)") }
    case "scan":
        let targets = rest.dropFirst().filter { $0.hasPrefix("--") == false }.map { URL(fileURLWithPath: $0) }
        guard targets.isEmpty == false else { fail(usage) }
        do {
            let started = Date()
            try await daemon.start()
            print(
                "engine ready in \(Int(Date().timeIntervalSince(started))) s, \(await daemon.client.version() ?? "?")")
            let scanner = MalwareScanner(engine: daemon.client, autostart: { [] }, apps: { [] })
            let result = try await scanner.scan(.make(.custom(targets), home: home))
            print("files: \(result.filesChecked), unreadable: \(result.unreadable), findings: \(result.findings.count)")
            for finding in result.findings { print("  \(reason(finding)): \(finding.url.path)") }
        } catch { print("scan failed: \(error)") }
        if rest.contains("--keep-running") == false { await daemon.stop() }
    case "checks":
        let items = await AutostartInventory(home: home, runner: runner).items()
        let apps = MalwareScanner.apps(in: [
            URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"),
        ])
        let findings =
            Heuristics.findings(for: items) + Heuristics.findings(forApps: apps) { CodeSignature.inspect($0) }
        for finding in findings { print("\(column(finding.name, 34)) \(reason(finding))") }
        print("apps checked: \(apps.count), autostart items: \(items.count), findings: \(findings.count)")
    case "stop":
        await daemon.stop()
    default:
        fail(usage)
    }
}

func mac() async {
    let checks = SecurityChecks.evaluate(await SecurityChecks.collect(runner: runner))
    for check in checks {
        print("\(column(String(describing: check.state), 10)) \(column(check.id.rawValue, 18)) \(check.detail ?? "")")
    }
    print("ok: \(checks.filter { $0.state == .ok }.count) of \(checks.count)")
}

func network() async {
    let before = await NetworkActivity.sample(runner: runner)
    try? await Task.sleep(for: .seconds(1))
    let now = await NetworkActivity.sample(runner: runner)
    let active = NetworkActivity.active(now, previous: before, interval: 1) { pid in
        let path = NetworkActivity.path(ofProcess: pid)
        return (path, path.map { CodeSignature.inspect(URL(fileURLWithPath: $0)) })
    }
    for process in active.prefix(15) {
        print(
            "\(column(process.name, 26)) conn \(column(String(process.connections), 4)) listen \(column(String(process.listeningPorts.count), 3)) \(column(plain(ByteFormat.rate(process.rate)), 10)) \(signer(process.signature))"
        )
    }
    print(
        "programs on the network: \(active.count), waiting for connections: \(active.filter { $0.listeningPorts.isEmpty == false }.count)"
    )
}

/// Creates a harmless LaunchAgent of its own, switches it off and on through the core, and removes it again.
func toggleTest() async {
    let agents = home.appendingPathComponent("Library/LaunchAgents")
    let label = "com.vdzeer.mac-care.toggle-test"
    let plist = agents.appendingPathComponent("\(label).plist")
    let job: [String: Any] = ["Label": label, "ProgramArguments": [Tool.noop], "RunAtLoad": false]
    let remover = Remover(pathGuard: PathGuard(allowedRoots: [agents]), runner: runner)
    do {
        try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).write(to: plist)
        defer { try? remover.discard(plist) }
        let inventory = AutostartInventory(home: home, runner: runner)
        let control = AutostartControl(runner: runner)
        func state() async -> Bool? { await inventory.items().first { $0.label == label }?.isEnabled }

        guard let item = await inventory.items().first(where: { $0.label == label }) else {
            fail("test job not listed")
        }
        print("listed, enabled: \(item.isEnabled)")
        try await control.setEnabled(false, item)
        print("after switching off, enabled: \(String(describing: await state()))")
        try await control.setEnabled(true, item)
        print("after switching on, enabled: \(String(describing: await state()))")
    } catch { print("toggle test failed: \(error)") }
    print("test job file removed: \(FileManager.default.fileExists(atPath: plist.path) == false)")
}

/// Watches a folder with the real engine for a while and prints what the live protection would report.
func watch(_ folder: URL, seconds: Int) async {
    let daemon = ClamDaemon()
    do {
        try await daemon.start()
        let inspector = LiveInspector(home: home, engine: daemon.client, autostart: { [] })
        let (stream, continuation) = AsyncStream.makeStream(of: [URL].self)
        let watcher = FileWatcher(folders: [folder], latency: 1) { continuation.yield($0) }
        watcher.start()
        print("watching \(folder.path) for \(seconds) s")
        let started = Date()
        let reader = Task {
            for await changed in stream {
                for unit in LiveInspector.units(from: changed) {
                    let reply = try? await daemon.client.scan(unit)
                    let verdict = reply?.hits.first.map { "MALWARE \($0.signature)" } ?? "clean"
                    let after = String(format: "%.1f", Date().timeIntervalSince(started))
                    print("  +\(after)s \(unit.lastPathComponent): \(verdict)")
                }
            }
        }
        _ = inspector
        try? await Task.sleep(for: .seconds(seconds))
        watcher.stop()
        continuation.finish()
        await reader.value
    } catch { print("watch failed: \(error)") }
    await daemon.stop()
}

func systemData() async {
    let places = await SystemDataScanner(home: home).places()
    let scan = await JunkScanner(home: home, runner: runner).scan()
    for place in places.prefix(40) {
        let cleanable = SystemDataScanner.cleanable(in: place, scan)
        let path = place.url.path.replacingOccurrences(of: home.path, with: "~")
        print(
            "\(column(plain(ByteFormat.string(place.bytes)), 10)) \(column(place.group.rawValue, 10)) \(column(place.known.rawValue, 16)) \(column(cleanable > 0 ? plain(ByteFormat.string(cleanable)) : "-", 10)) \(path)"
        )
    }
    print("places: \(places.count), total: \(plain(ByteFormat.string(places.reduce(0) { $0 + $1.bytes })))")
}

let usage =
    "usage: carectl junk [scan [--items] | dry-run] | autostart [toggle-test] | mac | network | system | shield [update | scan <path>... | watch <folder> [seconds] | checks | stop]"
switch arguments.first {
case "junk": await junk(Array(arguments.dropFirst()))
case "autostart": if arguments.dropFirst().first == "toggle-test" { await toggleTest() } else { await autostart() }
case "mac": await mac()
case "network": await network()
case "system": await systemData()
case "shield":
    let rest = Array(arguments.dropFirst())
    if rest.first == "watch", rest.count >= 2 {
        await watch(URL(fileURLWithPath: rest[1]), seconds: rest.count > 2 ? Int(rest[2]) ?? 20 : 20)
    } else {
        await shield(rest)
    }
default: fail(usage)
}
