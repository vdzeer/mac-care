import CoreServices
import Foundation

public struct InstalledApp: Sendable, Identifiable, Equatable {
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let version: String?
    public let lastUsed: Date?

    public var id: String { url.path }

    public init(url: URL, name: String, bundleID: String?, version: String? = nil, lastUsed: Date? = nil) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.lastUsed = lastUsed
    }

    /// Apple's own apps keep their data in shared system places; their leftovers are never offered.
    public var isApple: Bool { bundleID?.hasPrefix("com.apple.") ?? false }
}

public enum AppInventory {
    /// Apps directly in the given folders and one folder deeper (such as `Utilities`).
    public static func apps(in folders: [URL]) -> [InstalledApp] {
        var found: [URL] = []
        for folder in folders {
            for child in children(of: folder) {
                if child.pathExtension == "app" {
                    found.append(child)
                } else if isDirectory(child) {
                    found += children(of: child).filter { $0.pathExtension == "app" }
                }
            }
        }
        return found.compactMap(app(at:)).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public static func app(at url: URL) -> InstalledApp? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        let info =
            (try? Data(contentsOf: plist)).flatMap {
                try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
            } ?? [:]
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return InstalledApp(
            url: url, name: url.deletingPathExtension().lastPathComponent,
            bundleID: info["CFBundleIdentifier"] as? String, version: info["CFBundleShortVersionString"] as? String,
            lastUsed: lastUsed(url))
    }

    /// When the owner last opened the app, as Spotlight remembers it.
    private static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    private static func children(of folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(".") == false }.sorted().map { folder.appendingPathComponent($0) }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}

/// The kinds of places an app leaves things in.
public enum LeftoverKind: String, Sendable, CaseIterable {
    case app, data, caches, logs, preferences, savedState, container, webData, scripts, launchAgent
}

public struct AppPart: Sendable, Identifiable, Equatable {
    public let kind: LeftoverKind
    public let url: URL
    public let bytes: Int64

    public var id: String { url.path }

    public init(kind: LeftoverKind, url: URL, bytes: Int64) {
        self.kind = kind
        self.url = url
        self.bytes = bytes
    }
}

/// An app together with everything it left around the Library.
public struct AppFootprint: Sendable, Equatable {
    public let app: InstalledApp
    public let parts: [AppPart]

    public var bytes: Int64 { parts.reduce(0) { $0 + $1.bytes } }

    public init(app: InstalledApp, parts: [AppPart]) {
        self.app = app
        self.parts = parts
    }

    /// The owner chose this app to remove it, so every part starts ticked.
    public var initiallyUnticked: Set<String> { [] }
}

/// Leftovers whose app is no longer installed, gathered under the identifier they carry.
public struct OrphanGroup: Sendable, Identifiable, Equatable {
    public let bundleID: String
    public let parts: [AppPart]

    public var id: String { bundleID }
    public var bytes: Int64 { parts.reduce(0) { $0 + $1.bytes } }

    public init(bundleID: String, parts: [AppPart]) {
        self.bundleID = bundleID
        self.parts = parts
    }

    /// Leftovers are a guess, so every part starts unticked and the owner ticks what goes.
    public var initiallyUnticked: Set<String> { Set(parts.map(\.id)) }
}

public struct LeftoverFinder: Sendable {
    struct Place {
        let folder: String
        let kind: LeftoverKind
        /// Whether a folder named exactly like the app counts, not only one named after its identifier.
        let matchesName: Bool
    }

    static let places: [Place] = [
        Place(folder: "Library/Application Support", kind: .data, matchesName: true),
        Place(folder: "Library/Caches", kind: .caches, matchesName: true),
        Place(folder: "Library/Logs", kind: .logs, matchesName: true),
        Place(folder: "Library/Preferences", kind: .preferences, matchesName: false),
        Place(folder: "Library/Preferences/ByHost", kind: .preferences, matchesName: false),
        Place(folder: "Library/Saved Application State", kind: .savedState, matchesName: false),
        Place(folder: "Library/Containers", kind: .container, matchesName: false),
        Place(folder: "Library/Application Scripts", kind: .scripts, matchesName: false),
        Place(folder: "Library/HTTPStorages", kind: .webData, matchesName: false),
        Place(folder: "Library/WebKit", kind: .webData, matchesName: false),
        Place(folder: "Library/Cookies", kind: .webData, matchesName: false),
        Place(folder: "Library/LaunchAgents", kind: .launchAgent, matchesName: false),
    ]

    static let strippedSuffixes = [".plist", ".savedState", ".binarycookies"]

    public let home: URL
    public let applicationFolders: [URL]

    public init(home: URL, applicationFolders: [URL]) {
        self.home = home
        self.applicationFolders = applicationFolders
    }

    /// Removal for this module may touch the app folders and the Library places above, and nothing else.
    public var pathGuard: PathGuard {
        PathGuard(
            allowedRoots: applicationFolders + Self.places.map { home.appendingPathComponent($0.folder) },
            deniedRoots: PathGuard.protectedRoots(home: home), deniedComponents: PathGuard.protectedComponents)
    }

    /// The app and what it left around. `installed` is every app on the Mac: an entry that another of them answers
    /// to as well, such as Chrome Beta's next to Chrome's, is not this app's to take.
    public func footprint(of app: InstalledApp, among installed: [InstalledApp] = []) -> AppFootprint {
        var parts = [AppPart(kind: .app, url: app.url, bytes: DirectorySizer.usage(of: app.url).bytes)]
        if app.isApple == false {
            for place in Self.places {
                for entry in entries(in: place)
                where Self.belongs(entry.base, to: app, byName: place.matchesName)
                    && Self.isClaimed(entry.base, byAnotherThan: app, among: installed) == false
                {
                    parts.append(
                        AppPart(kind: place.kind, url: entry.url, bytes: DirectorySizer.usage(of: entry.url).bytes))
                }
            }
        }
        return AppFootprint(app: app, parts: parts)
    }

    /// Entries named like an app identifier that no installed app answers to.
    /// A guess by nature: command-line tools leave such folders too, so nothing here is ever ticked in advance.
    public func orphans(installed: [InstalledApp]) -> [OrphanGroup] {
        let known = installed.compactMap { $0.bundleID?.lowercased() }
        let names = Set(installed.map { $0.name.lowercased() })
        var groups: [String: [AppPart]] = [:]
        for place in Self.places where place.kind != .launchAgent {
            for entry in entries(in: place) {
                let base = entry.base.lowercased()
                guard Self.looksLikeBundleID(base), base.hasPrefix("com.apple.") == false, names.contains(base) == false
                else { continue }
                let owned = known.contains { base == $0 || base.hasPrefix($0 + ".") || $0.hasPrefix(base + ".") }
                if owned { continue }
                let part = AppPart(kind: place.kind, url: entry.url, bytes: DirectorySizer.usage(of: entry.url).bytes)
                groups[entry.base, default: []].append(part)
            }
        }
        return groups.map { OrphanGroup(bundleID: $0.key, parts: $0.value) }
            .sorted { ($0.bytes, $1.bundleID) > ($1.bytes, $0.bundleID) }
    }

    private func entries(in place: Place) -> [(url: URL, base: String)] {
        let folder = home.appendingPathComponent(place.folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().map { name in
            var base = name
            for suffix in Self.strippedSuffixes where base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
            }
            return (folder.appendingPathComponent(name), base)
        }
    }

    /// Strict on purpose: the identifier itself, something under it, or (where allowed) the exact app name.
    /// "Under it" needs a full identifier such as "com.vendor.app": an app that calls itself "com.vendor" must not
    /// take every entry of the vendor.
    static func belongs(_ base: String, to app: InstalledApp, byName: Bool) -> Bool {
        let base = base.lowercased()
        if let id = app.bundleID?.lowercased(), id.isEmpty == false {
            if base == id || (looksLikeBundleID(id) && base.hasPrefix(id + ".")) { return true }
        }
        return byName && app.name.count >= 3 && base == app.name.lowercased()
    }

    /// Whether another installed app answers to the entry with an identifier at least as long: "com.google.Chrome.beta"
    /// is Chrome Beta's, not Chrome's, and a second copy of the same app still needs its data.
    static func isClaimed(_ base: String, byAnotherThan app: InstalledApp, among installed: [InstalledApp]) -> Bool {
        guard let id = app.bundleID?.lowercased(), id.isEmpty == false else { return false }
        let base = base.lowercased()
        return installed.contains { other in
            guard other.url != app.url, let otherID = other.bundleID?.lowercased(), otherID.count >= id.count
            else { return false }
            return base == otherID || base.hasPrefix(otherID + ".")
        }
    }

    /// Reverse-DNS with at least three parts, such as "com.vendor.app".
    static func looksLikeBundleID(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        return parts.allSatisfy { part in
            part.isEmpty == false && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }
        }
    }
}

extension AppPart {
    /// Everything an uninstall takes goes to the Trash, so it can be put back.
    public func removalRequest(owner: String) -> RemovalRequest {
        RemovalRequest(
            id: id, kind: "uninstall:\(owner)", name: url.lastPathComponent, urls: [url], bytes: bytes, removal: .trash)
    }
}

extension Remover {
    /// Why the rest of an uninstall was left alone, as the report records it.
    public static let appStayed = "the app could not be moved"

    /// An uninstall: the app goes to the Trash first, and what it left around only after it. When the app cannot
    /// go (an App Store or installer app belongs to the system), nothing else is touched: the data of an app that
    /// stays installed stays with it, and the report lists the rest as skipped.
    public func uninstall(_ parts: [AppPart], owner: String, dryRun: Bool) async -> RemovalReport {
        let bundles = parts.filter { $0.kind == .app }.map { $0.removalRequest(owner: owner) }
        let rest = parts.filter { $0.kind != .app }.map { $0.removalRequest(owner: owner) }
        let first = await remove(bundles, dryRun: dryRun)
        let isGone =
            first.outcomes.count == bundles.count
            && first.outcomes.allSatisfy { $0.result == .removed || $0.result == .planned }
        guard isGone else { return first.adding(skipped: rest, because: Self.appStayed) }
        let second = await remove(rest, dryRun: dryRun)
        return RemovalReport(outcomes: first.outcomes + second.outcomes)
    }
}

extension RemovalReport {
    /// The app itself could not go to the Trash, so the leftovers chosen with it stayed too.
    public var appStayed: Bool { outcomes.contains { $0.result == .skipped(Remover.appStayed) } }
}
