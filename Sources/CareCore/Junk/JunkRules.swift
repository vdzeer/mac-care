import Foundation

/// How safe it is to remove something.
public enum CleanupClass: String, Sendable, Codable {
    /// The owning tool recreates it when needed. Selected in advance.
    case regenerates
    /// The owner decides. Never selected in advance.
    case review
}

/// The three parts of the bar on the overview screen.
public enum JunkCategory: String, Sendable, CaseIterable {
    case xcode
    case build
    case apps
}

public enum Removal: Sendable, Equatable {
    /// Gone at once. Only for things that come back by themselves.
    case delete
    /// Moved to the Trash, from where the owner can put it back.
    case trash
    /// A simulator device, removed by `simctl` so Xcode's device list stays consistent.
    case simulator(udid: String)
    /// A whole simulator system (several gigabytes), removed by `simctl`. Xcode can download it again.
    case simulatorRuntime(identifier: String)
}

public struct JunkRule: Sendable, Identifiable, Equatable {
    public enum ID: String, Sendable, CaseIterable, Codable {
        case derivedData, gradle, appCaches, npm, deviceSupport, appDataCaches, nuget, cocoaPods, yarn, homebrew
        case xcodeCaches, logs, jetBrainsCaches
        case simulatorRuntimes, simulators, androidDevices, wallpaperVideos, androidNDK, androidImages, cliCaches
        case xcodeArchives, trash, testBrowsers
    }

    public enum Source: Sendable, Equatable {
        /// Every direct child of the root folders is one item.
        case children
        /// Devices listed by `simctl`.
        case simulators
        /// Simulator systems listed by `simctl runtime`.
        case simulatorRuntimes
        /// One level down: in every child of the root, the subfolders named in `nestedNames`.
        case nested
    }

    public let id: ID
    public let cleanupClass: CleanupClass
    public let category: JunkCategory?
    public let roots: [URL]
    public let source: Source
    public let removal: Removal
    public var excludedNames: Set<String> = []
    public var excludedPrefixes: [String] = []
    /// When set, a child named after a running app's bundle id is left alone.
    public var skipsRunningApps = false
    /// Bundle ids of apps that work in these folders. While one of them is open the rule offers nothing:
    /// taking a build folder away from under a running build breaks the build.
    public var blockedBy: Set<String> = []
    /// For a `nested` rule: the cache folders to look for inside each child of the root.
    public var nestedNames: [String] = []
    /// For a `nested` rule: a child is considered only if it holds one of these, spelled exactly so.
    public var nestedMarkers: [String] = []
}

extension JunkRule {
    /// The open apps that keep this rule from offering anything at all.
    public func blockers(runningBundleIDs: Set<String>) -> Set<String> {
        blockedBy.intersection(runningBundleIDs)
    }

    /// Whether `name`, a child of a root (or an app folder of a `nested` rule), belongs to an app that is open.
    /// `runningAppNames` are lower-cased.
    public func belongsToOpenApp(_ name: String, runningBundleIDs: Set<String>, runningAppNames: Set<String>) -> Bool {
        guard skipsRunningApps else { return false }
        if runningBundleIDs.contains(name) { return true }
        return source == .nested && runningAppNames.contains(name.lowercased())
    }
}

public enum JunkRules {
    public static func all(home: URL) -> [JunkRule] {
        func at(_ paths: String...) -> [URL] { paths.map { home.appendingPathComponent($0) } }
        let xcode = "Library/Developer/Xcode"
        return [
            JunkRule(
                id: .derivedData, cleanupClass: .regenerates, category: .xcode,
                roots: at("\(xcode)/DerivedData"), source: .children, removal: .delete,
                blockedBy: ["com.apple.dt.Xcode"]),
            JunkRule(
                id: .gradle, cleanupClass: .regenerates, category: .build,
                roots: at(".gradle/caches", ".gradle/wrapper/dists", ".gradle/daemon"), source: .children,
                removal: .delete, blockedBy: ["com.google.android.studio"]),
            JunkRule(
                id: .appCaches, cleanupClass: .regenerates, category: .apps,
                roots: at("Library/Caches"), source: .children, removal: .delete,
                excludedNames: [
                    "CocoaPods", "Homebrew", "Yarn", "CloudKit", "FamilyCircle", "GeoServices", "PassKit", "GameKit",
                    "familycircled", "askpermissiond", "com.vdzeer.tidy", "com.vdzeer.ward",
                    // Their own rules below: test browsers do not come back by themselves, and JetBrains
                    // caches must wait until the IDE is closed.
                    "ms-playwright", "Cypress", "JetBrains",
                ],
                excludedPrefixes: ["com.apple."],
                skipsRunningApps: true),
            // JetBrains IDEs rebuild their caches, but not from under a running IDE.
            JunkRule(
                id: .jetBrainsCaches, cleanupClass: .regenerates, category: .apps,
                roots: at("Library/Caches/JetBrains"), source: .children, removal: .delete,
                blockedBy: JunkRules.jetBrainsIDEs),
            JunkRule(
                id: .npm, cleanupClass: .regenerates, category: .build,
                roots: at(".npm/_cacache", ".npm/_npx", ".npm/_logs"), source: .children, removal: .delete),
            JunkRule(
                id: .deviceSupport, cleanupClass: .regenerates, category: .xcode,
                roots: at(
                    "\(xcode)/iOS DeviceSupport", "\(xcode)/watchOS DeviceSupport", "\(xcode)/tvOS DeviceSupport",
                    "\(xcode)/visionOS DeviceSupport"),
                source: .children, removal: .delete),
            // Desktop apps built on web technology keep their caches next to their data, not in Library/Caches.
            JunkRule(
                id: .appDataCaches, cleanupClass: .regenerates, category: .apps,
                roots: at("Library/Application Support"), source: .nested, removal: .delete,
                excludedPrefixes: ["com.apple."], skipsRunningApps: true,
                nestedNames: [
                    "Cache", "Code Cache", "GPUCache", "CachedData", "CachedExtensionVSIXs", "DawnCache",
                    "DawnGraphiteCache", "DawnWebGPUCache", "Service Worker/CacheStorage", "Service Worker/ScriptCache",
                    "logs", "Crashpad",
                ],
                // Only folders laid out like a Chromium profile: there "Cache" and "logs" mean what they say.
                nestedMarkers: ["Code Cache", "GPUCache", "Local Storage", "Session Storage"]),
            JunkRule(
                id: .nuget, cleanupClass: .regenerates, category: .build,
                roots: at(".nuget/packages"), source: .children, removal: .delete),
            JunkRule(
                id: .cocoaPods, cleanupClass: .regenerates, category: .build,
                roots: at("Library/Caches/CocoaPods"), source: .children, removal: .delete),
            JunkRule(
                id: .yarn, cleanupClass: .regenerates, category: .build,
                roots: at(".yarn/berry/cache", ".yarn/cache", "Library/Caches/Yarn"), source: .children,
                removal: .delete),
            JunkRule(
                id: .homebrew, cleanupClass: .regenerates, category: .build,
                roots: at("Library/Caches/Homebrew"), source: .children, removal: .delete),
            JunkRule(
                id: .xcodeCaches, cleanupClass: .regenerates, category: .xcode,
                roots: at("Library/Developer/CoreSimulator/Caches", "Library/Developer/XCTestDevices"),
                source: .children, removal: .delete),
            JunkRule(
                id: .logs, cleanupClass: .regenerates, category: .apps,
                roots: at("Library/Logs"), source: .children, removal: .delete),
            JunkRule(
                id: .simulatorRuntimes, cleanupClass: .review, category: nil, roots: [], source: .simulatorRuntimes,
                removal: .delete),
            JunkRule(
                id: .simulators, cleanupClass: .review, category: nil,
                roots: at("Library/Developer/CoreSimulator/Devices"), source: .simulators, removal: .delete),
            JunkRule(
                id: .androidDevices, cleanupClass: .review, category: nil,
                roots: at(".android/avd"), source: .children, removal: .trash),
            // "Your call" decides what is offered, not how it goes: what can be downloaded again is removed for
            // good, because moving it to the Trash frees nothing. Only what cannot come back goes to the Trash.
            // Aerial videos for wallpapers and screen savers; macOS downloads the chosen one again.
            JunkRule(
                id: .wallpaperVideos, cleanupClass: .review, category: nil,
                roots: at("Library/Application Support/com.apple.wallpaper/aerials/videos"), source: .children,
                removal: .delete),
            JunkRule(
                id: .androidNDK, cleanupClass: .review, category: nil,
                roots: at("Library/Android/sdk/ndk"), source: .children, removal: .delete),
            JunkRule(
                id: .androidImages, cleanupClass: .review, category: nil,
                roots: at("Library/Android/sdk/system-images"), source: .children, removal: .delete),
            // The generic cache folder of command-line tools. Some keep downloaded models there, so the owner decides.
            JunkRule(
                id: .cliCaches, cleanupClass: .review, category: nil,
                roots: at(".cache"), source: .children, removal: .delete),
            // Browsers that test runners download. They do not come back by themselves, so the owner decides;
            // `npx playwright install` or the next Cypress run fetches them again.
            JunkRule(
                id: .testBrowsers, cleanupClass: .review, category: nil,
                roots: at("Library/Caches/ms-playwright", "Library/Caches/Cypress"), source: .children,
                removal: .delete),
            JunkRule(
                id: .xcodeArchives, cleanupClass: .review, category: nil,
                roots: at("\(xcode)/Archives"), source: .children, removal: .trash),
            // Emptying the Trash is the one removal here that cannot be undone.
            JunkRule(
                id: .trash, cleanupClass: .review, category: nil,
                roots: at(".Trash"), source: .children, removal: .delete, excludedNames: [".DS_Store"]),
        ]
    }

    /// Bundle ids of the JetBrains IDEs; while one runs, their caches are left alone.
    public static let jetBrainsIDEs: Set<String> = [
        "com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.pycharm", "com.jetbrains.pycharm.ce",
        "com.jetbrains.WebStorm", "com.jetbrains.goland", "com.jetbrains.CLion", "com.jetbrains.rider",
        "com.jetbrains.PhpStorm", "com.jetbrains.rubymine", "com.jetbrains.datagrip", "com.jetbrains.dataspell",
        "com.jetbrains.rustrover", "com.jetbrains.fleet", "com.jetbrains.aqua", "com.jetbrains.writerside",
    ]

    /// The guard for junk removal is built from the same roots the rules scan, so the two cannot drift apart.
    public static func pathGuard(home: URL) -> PathGuard {
        let rules = all(home: home)
        let roots = rules.filter { $0.source == .children }.flatMap(\.roots)
        let nested = rules.filter { $0.source == .nested }.flatMap { rule in
            rule.roots.map { PathGuard.Nested(root: $0, names: Set(rule.nestedNames)) }
        }
        return PathGuard(
            allowedRoots: roots, nested: nested,
            deniedRoots: PathGuard.protectedRoots(home: home),
            deniedComponents: PathGuard.protectedComponents)
    }
}
