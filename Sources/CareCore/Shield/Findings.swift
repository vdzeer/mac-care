import Foundation

/// One thing a check turned up.
public struct Finding: Sendable, Identifiable, Equatable {
    public enum Severity: Sendable, Equatable {
        /// The signature database knows this file as malware.
        case malicious
        /// Nothing is proven; the owner should look and decide.
        case suspicious
    }

    public enum Reason: Sendable, Equatable {
        case knownMalware(signature: String)
        /// Starts by itself, and no developer certificate stands behind it.
        case unsignedAutostart
        /// Starts by itself from a hidden or temporary folder, with no developer certificate behind it.
        case hiddenAutostart
        /// Starts by itself and runs a line of shell script with no file to inspect.
        case scriptAutostart
        /// The file was changed after it was signed.
        case brokenSignature
        /// An app with no developer certificate behind it.
        case unsignedApp
        /// An app signed by a developer that Apple did not notarize: nobody checked it for malware.
        case notNotarizedApp

        var key: String {
            switch self {
            case .knownMalware: "malware"
            case .unsignedAutostart: "unsignedAutostart"
            case .hiddenAutostart: "hiddenAutostart"
            case .scriptAutostart: "scriptAutostart"
            case .brokenSignature: "brokenSignature"
            case .unsignedApp: "unsignedApp"
            case .notNotarizedApp: "notNotarizedApp"
            }
        }
    }

    public let severity: Severity
    public let reason: Reason
    /// The file to show, and to quarantine when that is possible.
    public let url: URL
    public let name: String
    /// Set when the finding is about something that starts by itself; such findings are switched off, not moved.
    public let autostart: AutostartItem?

    public var id: String { "\(reason.key):\(url.path)" }

    public init(severity: Severity, reason: Reason, url: URL, name: String? = nil, autostart: AutostartItem? = nil) {
        self.severity = severity
        self.reason = reason
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.autostart = autostart
    }
}

/// Which findings "Quarantine All" takes.
public enum BulkQuarantine {
    /// The two apps of this package. Built from source they are signed ad hoc and look suspicious, so one button
    /// must never take them, whatever copy it is.
    public static let ownBundleIDs: Set<String> = ["com.vdzeer.tidy", "com.vdzeer.ward"]

    /// Proven malware only, never something that starts by itself (that is switched off, not moved), and never
    /// anything inside the `spared` apps or inside an app of this package.
    public static func findings(_ findings: [Finding], sparing spared: [URL]) -> [Finding] {
        let roots = spared.map { $0.standardizedFileURL.path }
        return findings.filter { finding in
            guard finding.severity == .malicious, finding.autostart == nil else { return false }
            let path = finding.url.standardizedFileURL.path
            if roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return false }
            return isOwnApp(path) == false
        }
    }

    /// True when the path is an app of this package or lies inside one.
    static func isOwnApp(_ path: String) -> Bool {
        let app = path.hasSuffix(".app") ? path : AutostartInventory.enclosingApp(path)
        guard let app, let bundle = Bundle(path: app), let id = bundle.bundleIdentifier else { return false }
        return ownBundleIDs.contains(id)
    }
}

/// The checks Ward makes itself, without the signature database.
public enum Heuristics {
    /// Folders nobody installs honest software into.
    static let temporaryPrefixes = ["/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/", "/Users/Shared/"]

    public static func findings(for items: [AutostartItem]) -> [Finding] {
        items.compactMap { item in
            guard item.isEnabled else { return nil }
            let shown = item.plist ?? URL(fileURLWithPath: item.target ?? item.program ?? item.label)
            func finding(_ reason: Finding.Reason) -> Finding {
                Finding(severity: .suspicious, reason: reason, url: shown, name: item.name, autostart: item)
            }
            if item.launcher != nil, item.target == nil { return finding(.scriptAutostart) }
            switch item.signature?.kind {
            case .broken:
                return finding(.brokenSignature)
            case .unsigned, .adHoc:
                // An odd place makes an unsigned program more worrying; a signed one may live where it likes.
                let hidden = item.target.map(isHiddenOrTemporary) ?? false
                return finding(hidden ? .hiddenAutostart : .unsignedAutostart)
            case .apple, .developer, nil:
                return nil
            }
        }
    }

    /// Only the full check asks about notarization (`notarized` is nil otherwise), so only it flags a signed app
    /// that Apple did not notarize.
    public static func findings(forApps apps: [URL], inspect: (URL) -> SignatureInfo) -> [Finding] {
        apps.compactMap { app in
            let signature = inspect(app)
            switch signature.kind {
            case .broken: return Finding(severity: .suspicious, reason: .brokenSignature, url: app)
            case .unsigned, .adHoc: return Finding(severity: .suspicious, reason: .unsignedApp, url: app)
            case .developer where signature.notarized == false:
                return Finding(severity: .suspicious, reason: .notNotarizedApp, url: app)
            case .apple, .developer: return nil
            }
        }
    }

    static func isHiddenOrTemporary(_ path: String) -> Bool {
        if temporaryPrefixes.contains(where: path.hasPrefix) { return true }
        // A dot-folder anywhere on the way, such as ~/.cache/.upd/agent.
        return path.split(separator: "/").dropLast().contains { $0.hasPrefix(".") }
    }
}

/// What the owner has looked at and chosen to keep. Those findings are not shown again.
public struct TrustStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func trustedIDs() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL), let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }

    public func trust(_ finding: Finding) throws {
        var ids = trustedIDs()
        ids.insert(finding.id)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ids.sorted()).write(to: fileURL, options: .atomic)
    }
}
