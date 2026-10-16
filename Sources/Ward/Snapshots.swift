import AppKit
import CareCore
import CareUI
import SwiftUI

/// Draws every screen with fixed sample data into PNG files: `Ward --snapshot <folder>`.
/// No window is shown, nothing is scanned, and the engine is not started.
enum Snapshots {
    static func write(to folder: URL) {
        _ = NSApplication.shared
        let model = sampleModel()
        let window = CGSize(width: Metric.windowWidth, height: Metric.windowHeight)

        // Every screen is drawn twice: in the light and in the dark appearance (`-dark`).
        func shot(_ name: String, _ section: WardSection) {
            model.section = section
            for dark in [false, true] {
                do {
                    let url = folder.appendingPathComponent(name + (dark ? "-dark" : "") + ".png")
                    try SnapshotRenderer.write(RootView(model: model), size: window, accent: .ward, dark: dark, to: url)
                    print(url.path)
                } catch {
                    FileHandle.standardError.write(Data("\(name): \(error)\n".utf8))
                }
            }
        }
        shot("ward-overview", .overview)
        shot("ward-scan", .scan)
        shot("ward-live", .live)
        shot("ward-mac", .mac)
        shot("ward-autostart", .autostart)
        model.shield.setPreview(result: nil, entries: [], lastScan: nil, phase: .scanning)
        shot("ward-scan-progress", .scan)
        let home = URL(fileURLWithPath: "/Users/sample")
        model.live.setPreview(
            isOn: true,
            events: [
                LiveEvent(
                    date: Date().addingTimeInterval(-60), url: home.appendingPathComponent("Downloads/setup.pkg"),
                    place: .downloads, verdict: .notChecked),
                LiveEvent(
                    date: Date().addingTimeInterval(-9 * 60), url: home.appendingPathComponent("Downloads/Tool.app"),
                    place: .downloads, verdict: .clean, signer: "Example Ltd", notarized: false),
            ], checkedToday: 4, hasProblem: true)
        shot("ward-live-problem", .live)
        let steps = [
            PermissionStep(
                id: "fullDiskAccess", title: WardStrings.Permissions.fullDiskAccess,
                note: WardStrings.Permissions.fullDiskAccessNote, actionTitle: WardStrings.Permissions.openSettings,
                isAllowed: { false }, action: {}),
            PermissionStep(
                id: "notifications", title: WardStrings.Permissions.notifications,
                note: WardStrings.Permissions.notificationsNote,
                actionTitle: WardStrings.Permissions.allowNotifications,
                isAllowed: { true }, action: {}),
            PermissionStep(
                id: "engine", title: WardStrings.Permissions.engine, note: WardStrings.Permissions.engineNote,
                actionTitle: WardStrings.Permissions.copyCommand, doneLabel: WardStrings.Permissions.installed,
                isAllowed: { true }, action: {}),
        ]
        let sheet = PermissionsSheet(
            title: WardStrings.Permissions.title, message: WardStrings.Permissions.message,
            allowedLabel: WardStrings.Permissions.allowed, laterTitle: WardStrings.Permissions.later,
            doneTitle: WardStrings.Permissions.done, steps: steps, onClose: {})
        for dark in [false, true] {
            let url = folder.appendingPathComponent("ward-permissions" + (dark ? "-dark" : "") + ".png")
            try? SnapshotRenderer.write(
                sheet, size: CGSize(width: 540, height: 420), accent: .ward, dark: dark, to: url)
            print(url.path)
        }
    }

    private static func item(
        _ name: String, _ label: String, _ kind: AutostartItem.Kind, _ target: String, _ signature: SignatureInfo.Kind?,
        enabled: Bool = true
    ) -> AutostartItem {
        AutostartItem(
            id: "\(kind.rawValue):\(label)", kind: kind, label: label, name: name,
            plist: URL(fileURLWithPath: "/Library/LaunchAgents/\(label).plist"), program: target, target: target,
            launcher: nil, isTargetMissing: false, isEnabled: enabled, runsAtLoad: true, interval: nil, developer: nil,
            signature: signature.map { SignatureInfo(kind: $0) })
    }

    private static func sampleModel() -> AppModel {
        let home = URL(fileURLWithPath: "/Users/sample")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ward-snapshot")
        let model = AppModel.make(home: home, runner: SystemCommandRunner(), support: scratch, defaults: nil)
        model.engine.setPreview(installed: true, lastCheck: Date().addingTimeInterval(-3 * 3600))

        var facts = SecurityFacts()
        facts.firewall = "State = 0"
        facts.fileVault = "FileVault is On."
        facts.gatekeeper = "assessments enabled"
        facts.systemIntegrity = "status: enabled"
        facts.screenLock = "delay is immediate"
        facts.systemServices = "\"com.example\" => enabled"
        facts.softwareUpdate = [
            "CriticalUpdateInstall": 1, "ConfigDataInstall": 1, "AutomaticallyInstallMacOSUpdates": 0,
        ]
        facts.guestEnabled = false
        facts.xprotectVersion = "5347"
        model.mac.setPreview(SecurityChecks.evaluate(facts))

        let suspect = item(
            "com.sys.updater", "com.sys.updater", .userAgent, "/Users/sample/.cache/.upd/agent", .unsigned)
        let items = [
            suspect,
            item(
                "Docker", "com.docker.vmnetd", .daemon, "/Library/PrivilegedHelperTools/com.docker.vmnetd",
                .developer(team: "9BNSXJN65R", name: "Docker Inc")),
            item(
                "GoogleUpdater", "com.google.GoogleUpdater.wake", .userAgent,
                "/Applications/Google Chrome.app/Contents/MacOS/GoogleUpdater",
                .developer(team: "EQHXZ8M8AV", name: "Google LLC")),
            item(
                "Microsoft AutoUpdate", "com.microsoft.update.agent", .globalAgent,
                "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/Assistant",
                .developer(team: "UBF8T346G9", name: "Microsoft Corporation"), enabled: false),
            item(
                "FigmaAgent", "com.figma.agent", .userAgent, "/Applications/Figma.app/Contents/MacOS/agent",
                .developer(team: "T8RA8NE3B7", name: "Figma, Inc.")),
            item(
                "Backup Helper", "com.example.backup-helper", .userAgent,
                "/Users/Shared/Backup Helper.app/Contents/MacOS/helper",
                .adHoc),
            item(
                "zoom.us", "us.zoom.ZoomDaemon", .daemon, "/Library/PrivilegedHelperTools/us.zoom.ZoomDaemon",
                .developer(team: "BJ4HAAB9B3", name: "Zoom Video Communications, Inc.")),
        ]
        func process(
            _ name: String, _ pid: Int, _ connections: Int, _ rate: Double, _ kind: SignatureInfo.Kind,
            listen: [Int] = []
        ) -> NetworkProcess {
            NetworkProcess(
                pid: pid, name: name, connections: connections, listeningPorts: listen, remotes: ["45.9.148.21"],
                bytesIn: 0,
                bytesOut: 0, rate: rate, path: nil, signature: SignatureInfo(kind: kind))
        }
        model.autostart.setPreview(
            items: items, newIDs: [suspect.id],
            network: [
                process("agent", 4111, 1, 38_000, .unsigned),
                process("Google Chrome", 812, 14, 1_800_000, .developer(team: "T", name: "Google LLC")),
                process("Slack", 900, 3, 12_000, .developer(team: "T", name: "Slack Technologies")),
                process("Docker", 950, 2, 4_000, .developer(team: "T", name: "Docker Inc"), listen: [2375]),
                process("mDNSResponder", 669, 2, 1_000, .apple, listen: [5353]),
                process("ControlCenter", 700, 0, 0, .apple, listen: [5000, 7000]),
            ])

        let malware = Finding(
            severity: .malicious, reason: .knownMalware(signature: "Osx.Trojan.Agent"),
            url: home.appendingPathComponent("Downloads/FlashPlayer_update.dmg"))
        let odd = Finding(
            severity: .suspicious, reason: .hiddenAutostart,
            url: home.appendingPathComponent("Library/LaunchAgents/com.sys.updater.plist"), name: "com.sys.updater",
            autostart: suspect)
        let yesterday = Date().addingTimeInterval(-26 * 3600)
        model.shield.setPreview(
            result: ScanResult(findings: [malware, odd], filesChecked: 48_213, unreadable: 0, date: Date()),
            entries: [],
            lastScan: yesterday)

        func event(
            _ minutesAgo: Double, _ name: String, _ place: WatchedPlace, _ verdict: LiveEvent.Verdict,
            _ signer: String? = nil
        ) -> LiveEvent {
            LiveEvent(
                date: Date().addingTimeInterval(-minutesAgo * 60),
                url: home.appendingPathComponent("Downloads/\(name)"),
                place: place, verdict: verdict, signer: signer)
        }
        model.live.setPreview(
            isOn: true,
            events: [
                event(12, "Slack-4.41.dmg", .downloads, .clean, "Slack Technologies"),
                event(27, "node-v24.9.0.pkg", .downloads, .clean, "OpenJS Foundation"),
                event(174, "com.sys.updater.plist", .autostart, .flagged(odd)),
                event(283, "invoice-october.pdf", .downloads, .clean),
                event(302, "Figma.app", .applications, .clean, "Figma, Inc."),
            ], checkedToday: 37)
        return model
    }
}
