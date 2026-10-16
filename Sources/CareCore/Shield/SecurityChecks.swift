import Foundation

/// One setting of the Mac that matters for safety, and whether it is as it should be.
public struct SecurityCheck: Sendable, Identifiable, Equatable {
    public enum ID: String, Sendable, CaseIterable {
        case firewall, securityUpdates, systemUpdates, fileVault, gatekeeper, systemIntegrity, xprotect
        case screenLock, autoLogin, guestAccount, remoteLogin, screenSharing, fileSharing
    }

    public enum State: Sendable, Equatable {
        case ok
        case attention
        /// The Mac did not answer; nothing is claimed either way.
        case unknown
    }

    public let id: ID
    public let state: State
    /// A value worth showing next to the check, such as a version number.
    public let detail: String?

    public init(id: ID, state: State, detail: String? = nil) {
        self.id = id
        self.state = state
        self.detail = detail
    }

    /// The page of System Settings where the owner changes it. The apps only read settings, never change them.
    public var settingsURL: URL? {
        let page: String? =
            switch id {
            case .firewall: "com.apple.Network-Settings.extension?Firewall"
            case .securityUpdates, .systemUpdates: "com.apple.Software-Update-Settings.extension"
            case .fileVault: "com.apple.settings.PrivacySecurity.extension?FileVault"
            case .gatekeeper: "com.apple.settings.PrivacySecurity.extension?Security"
            case .screenLock: "com.apple.Lock-Screen-Settings.extension"
            case .autoLogin, .guestAccount: "com.apple.Users-Groups-Settings.extension"
            case .remoteLogin, .screenSharing, .fileSharing: "com.apple.Sharing-Settings.extension"
            case .systemIntegrity, .xprotect: nil
            }
        return page.flatMap { URL(string: "x-apple.systempreferences:\($0)") }
    }
}

/// Raw answers from the Mac, gathered once and then judged by a pure function.
public struct SecurityFacts: Sendable, Equatable {
    public var firewall: String?
    public var fileVault: String?
    public var gatekeeper: String?
    public var systemIntegrity: String?
    public var screenLock: String?
    /// Output of `launchctl print-disabled system`.
    public var systemServices: String?
    /// Whole-number values from the Software Update settings file.
    public var softwareUpdate: [String: Int]?
    public var autoLoginUser: String?
    public var guestEnabled: Bool?
    public var xprotectVersion: String?

    public init() {}
}

public enum SecurityChecks {
    /// Turns the gathered facts into checks: what needs attention first, the rest in a fixed order.
    public static func evaluate(_ facts: SecurityFacts) -> [SecurityCheck] {
        let services = facts.systemServices.map(DisabledServices.states)
        func sharing(_ label: String) -> SecurityCheck.State {
            guard let services else { return .unknown }
            return services[label] == true ? .attention : .ok
        }
        func updates(_ keys: [String]) -> SecurityCheck.State {
            guard let settings = facts.softwareUpdate else { return .unknown }
            let values = keys.map { settings[$0] }
            if values.contains(0) { return .attention }
            return values.contains(nil) ? .unknown : .ok
        }

        let checks = [
            SecurityCheck(
                id: .firewall, state: state(facts.firewall, ok: ["State = 1", "State = 2"], bad: ["State = 0"])),
            SecurityCheck(id: .securityUpdates, state: updates(["CriticalUpdateInstall", "ConfigDataInstall"])),
            SecurityCheck(id: .systemUpdates, state: updates(["AutomaticallyInstallMacOSUpdates"])),
            SecurityCheck(
                id: .fileVault, state: state(facts.fileVault, ok: ["FileVault is On"], bad: ["FileVault is Off"])),
            SecurityCheck(
                id: .gatekeeper,
                state: state(facts.gatekeeper, ok: ["assessments enabled"], bad: ["assessments disabled"])),
            SecurityCheck(
                id: .systemIntegrity,
                state: state(facts.systemIntegrity, ok: ["status: enabled"], bad: ["status: disabled"])),
            SecurityCheck(
                id: .xprotect, state: facts.xprotectVersion == nil ? .attention : .ok, detail: facts.xprotectVersion),
            SecurityCheck(id: .screenLock, state: screenLock(facts.screenLock)),
            SecurityCheck(id: .autoLogin, state: facts.autoLoginUser == nil ? .ok : .attention),
            SecurityCheck(id: .guestAccount, state: facts.guestEnabled.map { $0 ? .attention : .ok } ?? .unknown),
            SecurityCheck(id: .remoteLogin, state: sharing("com.openssh.sshd")),
            SecurityCheck(id: .screenSharing, state: sharing("com.apple.screensharing")),
            SecurityCheck(id: .fileSharing, state: sharing("com.apple.smbd")),
        ]
        return checks.filter { $0.state == .attention } + checks.filter { $0.state != .attention }
    }

    private static func state(_ output: String?, ok: [String], bad: [String]) -> SecurityCheck.State {
        guard let output else { return .unknown }
        if bad.contains(where: output.contains) { return .attention }
        return ok.contains(where: output.contains) ? .ok : .unknown
    }

    /// A password must be asked at once, or at most five minutes after the screen locks.
    private static func screenLock(_ output: String?) -> SecurityCheck.State {
        guard let output else { return .unknown }
        if output.contains("screenLock is off") { return .attention }
        if output.contains("delay is immediate") { return .ok }
        guard let range = output.range(of: "delay is "),
            let seconds = Int(output[range.upperBound...].prefix { $0.isNumber })
        else { return .unknown }
        return seconds <= 300 ? .ok : .attention
    }

    /// Asks the Mac. Every question is read-only and needs no password.
    public static func collect(runner: any CommandRunning) async -> SecurityFacts {
        func ask(_ tool: String, _ arguments: [String]) async -> String? {
            guard let result = try? await runner.run(tool, arguments, timeout: 15) else { return nil }
            let text = result.stdout + result.stderr
            return text.isEmpty ? nil : text
        }
        var facts = SecurityFacts()
        async let firewall = ask(Tool.socketfilterfw, ["--getglobalstate"])
        async let fileVault = ask(Tool.fdesetup, ["status"])
        async let gatekeeper = ask(Tool.spctl, ["--status"])
        async let integrity = ask(Tool.csrutil, ["status"])
        async let screenLock = ask(Tool.sysadminctl, ["-screenLock", "status"])
        async let services = ask(Tool.launchctl, ["print-disabled", "system"])
        facts.firewall = await firewall
        facts.fileVault = await fileVault
        facts.gatekeeper = await gatekeeper
        facts.systemIntegrity = await integrity
        facts.screenLock = await screenLock
        facts.systemServices = await services

        if let update = plist("/Library/Preferences/com.apple.SoftwareUpdate.plist") {
            facts.softwareUpdate = update.compactMapValues { value in
                (value as? Int) ?? (value as? Bool).map { $0 ? 1 : 0 }
            }
        }
        if let login = plist("/Library/Preferences/com.apple.loginwindow.plist") {
            facts.autoLoginUser = login["autoLoginUser"] as? String
            facts.guestEnabled =
                (login["GuestEnabled"] as? Bool) ?? ((login["GuestEnabled"] as? Int).map { $0 != 0 }) ?? false
        }
        let bundles = [
            "/var/protected/xprotect/XProtect.bundle", "/Library/Apple/System/Library/CoreServices/XProtect.bundle",
        ]
        let versions = bundles.compactMap {
            plist($0 + "/Contents/Info.plist")?["CFBundleShortVersionString"] as? String
        }
        facts.xprotectVersion = versions.max { (Int($0) ?? 0) < (Int($1) ?? 0) }
        return facts
    }

    private static func plist(_ path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }
}
