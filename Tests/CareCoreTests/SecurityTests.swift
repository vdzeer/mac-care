import Foundation
import Testing

@testable import CareCore

@Suite struct SecurityChecksTests {
    /// A Mac with everything as it should be.
    static var safe: SecurityFacts {
        var facts = SecurityFacts()
        facts.firewall = "Firewall is enabled. (State = 1)\n"
        facts.fileVault = "FileVault is On.\n"
        facts.gatekeeper = "assessments enabled\n"
        facts.systemIntegrity = "System Integrity Protection status: enabled.\n"
        facts.screenLock = "2026-10-13 15:28:39.950 sysadminctl[59277:1] screenLock delay is immediate\n"
        facts.systemServices = "\t\"com.apple.smbd\" => disabled\n\t\"com.example\" => enabled\n"
        facts.softwareUpdate = [
            "CriticalUpdateInstall": 1, "ConfigDataInstall": 1, "AutomaticallyInstallMacOSUpdates": 1,
        ]
        facts.guestEnabled = false
        facts.xprotectVersion = "5347"
        return facts
    }

    func state(_ id: SecurityCheck.ID, _ change: (inout SecurityFacts) -> Void) -> SecurityCheck.State? {
        var facts = Self.safe
        change(&facts)
        return SecurityChecks.evaluate(facts).first { $0.id == id }?.state
    }

    @Test func aSafeMacPassesEveryCheck() {
        let checks = SecurityChecks.evaluate(Self.safe)
        #expect(checks.count == SecurityCheck.ID.allCases.count)
        #expect(checks.allSatisfy { $0.state == .ok })
        #expect(checks.first { $0.id == .xprotect }?.detail == "5347")
    }

    @Test func eachSettingIsJudgedInBothDirections() {
        #expect(state(.firewall) { $0.firewall = "Firewall is disabled. (State = 0)" } == .attention)
        #expect(state(.firewall) { $0.firewall = "Firewall is enabled. (State = 2)" } == .ok)
        #expect(state(.fileVault) { $0.fileVault = "FileVault is Off." } == .attention)
        #expect(state(.gatekeeper) { $0.gatekeeper = "assessments disabled" } == .attention)
        #expect(
            state(.systemIntegrity) { $0.systemIntegrity = "System Integrity Protection status: disabled." }
                == .attention)
        #expect(state(.xprotect) { $0.xprotectVersion = nil } == .attention)
        #expect(state(.screenLock) { $0.screenLock = "screenLock is off" } == .attention)
        #expect(state(.screenLock) { $0.screenLock = "screenLock delay is 300 seconds" } == .ok)
        #expect(state(.screenLock) { $0.screenLock = "screenLock delay is 3600 seconds" } == .attention)
        #expect(state(.autoLogin) { $0.autoLoginUser = "someone" } == .attention)
        #expect(state(.guestAccount) { $0.guestEnabled = true } == .attention)
        #expect(state(.remoteLogin) { $0.systemServices = "\"com.openssh.sshd\" => enabled" } == .attention)
        #expect(state(.screenSharing) { $0.systemServices = "\"com.apple.screensharing\" => enabled" } == .attention)
        #expect(state(.fileSharing) { $0.systemServices = "\"com.apple.smbd\" => enabled" } == .attention)
        #expect(state(.securityUpdates) { $0.softwareUpdate?["ConfigDataInstall"] = 0 } == .attention)
        #expect(state(.systemUpdates) { $0.softwareUpdate?["AutomaticallyInstallMacOSUpdates"] = 0 } == .attention)
    }

    @Test func aSilentMacIsUnknownNotSafe() {
        #expect(state(.firewall) { $0.firewall = nil } == .unknown)
        #expect(state(.firewall) { $0.firewall = "something unexpected" } == .unknown)
        #expect(state(.remoteLogin) { $0.systemServices = nil } == .unknown)
        #expect(state(.systemUpdates) { $0.softwareUpdate = nil } == .unknown)
        #expect(state(.systemUpdates) { $0.softwareUpdate = ["CriticalUpdateInstall": 1] } == .unknown)
        #expect(state(.screenLock) { $0.screenLock = "garbled" } == .unknown)
        #expect(state(.guestAccount) { $0.guestEnabled = nil } == .unknown)
    }

    @Test func whatNeedsAttentionComesFirst() {
        var facts = Self.safe
        facts.fileVault = "FileVault is Off."
        facts.guestEnabled = true
        let checks = SecurityChecks.evaluate(facts)
        #expect(checks.prefix(2).map(\.id) == [.fileVault, .guestAccount])
        #expect(checks.dropFirst(2).first?.id == .firewall)
    }

    @Test func everyFixableCheckLeadsToSystemSettings() {
        for check in SecurityChecks.evaluate(Self.safe) where check.id != .systemIntegrity && check.id != .xprotect {
            #expect(check.settingsURL?.scheme == "x-apple.systempreferences", "\(check.id)")
        }
    }
}

@Suite struct NetworkActivityTests {
    static let first = """
        ,bytes_in,bytes_out,
        launchd.1,0,0,
        tcp4 127.0.0.1:8021<->*:*,,,
        tcp6 *.445<->*.*,,,
        apsd.589,4000,700,
        tcp4 192.168.1.20:59694<->17.57.144.10:5223,4000,700,
        mDNSResponder.669,100,100,
        udp4 *:5353<->*:*,100,100,
        Google Chrome H.812,9000,1000,
        tcp4 192.168.1.20:50001<->142.250.74.14:443,5000,600,
        tcp6 fe80::1.50002<->2a00:1450:4001::200e.443,4000,400,
        tcp4 192.168.1.20:50003<->142.250.74.14:443,0,0,
        idle.900,0,0,
        """

    @Test func readsProgramsAndTheirSockets() {
        let processes = NetworkActivity.parse(Self.first)
        #expect(processes.map(\.name) == ["launchd", "apsd", "mDNSResponder", "Google Chrome H", "idle"])
        #expect(processes.map(\.pid) == [1, 589, 669, 812, 900])
        #expect(processes[0].listeningPorts == [445, 8021])
        #expect(processes[0].connections == 0)
        #expect(processes[1].connections == 1)
        #expect(processes[1].remotes == ["17.57.144.10"])
        #expect(processes[2].listeningPorts.isEmpty)
        #expect(processes[3].connections == 3)
        #expect(processes[3].remotes == ["142.250.74.14", "2a00:1450:4001::200e"])
        #expect(processes[3].bytesIn == 9000)
    }

    @Test func keepsOnlyProgramsOnTheNetworkAndWorksOutRates() {
        let earlier = NetworkActivity.parse(Self.first)
        let later = NetworkActivity.parse(
            Self.first.replacingOccurrences(
                of: "Google Chrome H.812,9000,1000,", with: "Google Chrome H.812,12000,2000,"))
        let active = NetworkActivity.active(later, previous: earlier, interval: 2) { pid in
            pid == 812
                ? ("/Applications/Chrome.app", SignatureInfo(kind: .developer(team: "T", name: "Google LLC")))
                : (nil, nil)
        }
        #expect(active.map(\.name) == ["Google Chrome H", "apsd", "launchd"])
        #expect(active[0].rate == 2000)
        #expect(active[0].signature?.isTrusted == true)
        #expect(active[1].rate == 0)
    }

    @Test func splitsEndpoints() {
        #expect(NetworkActivity.port(of: "192.168.1.5:443") == 443)
        #expect(NetworkActivity.port(of: "fe80::1.8080") == 8080)
        #expect(NetworkActivity.port(of: "*:*") == nil)
        #expect(NetworkActivity.address(of: "10.0.0.1:53") == "10.0.0.1")
    }

    @Test func findsTheProgramOfARunningProcess() {
        let own = NetworkActivity.path(ofProcess: Int(ProcessInfo.processInfo.processIdentifier))
        #expect(own?.hasPrefix("/") == true)
        #expect(NetworkActivity.path(ofProcess: 999_999_999) == nil)
    }
}

@Suite struct BaselineTests {
    @Test func theFirstLookRecordsEverythingAndLaterOnesReportWhatIsNew() throws {
        let home = try TempHome()
        let store = BaselineStore(fileURL: home.path("state/baseline.json"))
        let first = [
            autostartItem("a", target: "/opt/a", signature: .apple),
            autostartItem("b", target: "/opt/b", signature: .apple),
        ]
        #expect(store.known() == nil)
        #expect(store.newItems(among: first).isEmpty)
        #expect(store.known()?.count == 2)

        let second = first + [autostartItem("c", target: "/opt/c", signature: .unsigned)]
        #expect(store.newItems(among: second) == ["userAgent:c"])
        // Still new until the owner says they have seen it.
        #expect(store.newItems(among: second) == ["userAgent:c"])
        store.acknowledge(second)
        #expect(store.newItems(among: second).isEmpty)
        // Something that disappears and comes back is new again only after the owner looked in between.
        store.acknowledge(first)
        #expect(store.newItems(among: second) == ["userAgent:c"])
    }
}
