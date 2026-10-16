import CoreServices
import Foundation

/// The places a running Ward keeps an eye on.
public enum WatchedPlace: String, Sendable, CaseIterable, Codable {
    case downloads, applications, autostart, volumes, desktop

    public func folders(home: URL) -> [URL] {
        switch self {
        case .downloads: [home.appendingPathComponent("Downloads")]
        case .desktop: [home.appendingPathComponent("Desktop")]
        case .applications: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        case .volumes: [URL(fileURLWithPath: "/Volumes")]
        case .autostart:
            [
                home.appendingPathComponent("Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchAgents"),
                URL(fileURLWithPath: "/Library/LaunchDaemons"),
            ]
        }
    }

    /// The place a changed path belongs to, if any of the given ones.
    public static func owner(of url: URL, among places: [WatchedPlace], home: URL) -> WatchedPlace? {
        places.first { place in
            place.folders(home: home).contains { url.path.hasPrefix($0.path + "/") }
        }
    }
}

/// What happened to one new file.
public struct LiveEvent: Sendable, Identifiable, Equatable {
    public enum Verdict: Sendable, Equatable {
        case clean
        case flagged(Finding)
        /// The engine did not answer or could not read the file, so nothing is known about it.
        case notChecked
    }

    public let id: UUID
    public let date: Date
    public let url: URL
    public let place: WatchedPlace
    public let verdict: Verdict
    /// The developer who signed it, when it is signed.
    public let signer: String?
    /// Whether Apple notarized it, for an app signed by a developer; nil when that was not asked.
    public let notarized: Bool?

    public init(
        id: UUID = UUID(), date: Date, url: URL, place: WatchedPlace, verdict: Verdict, signer: String? = nil,
        notarized: Bool? = nil
    ) {
        self.id = id
        self.date = date
        self.url = url
        self.place = place
        self.verdict = verdict
        self.signer = signer
        self.notarized = notarized
    }
}

/// Holds changed things until they have been quiet for a moment, so a copy in progress is checked once, at the
/// end, instead of after every burst of changes. A thing being checked is not handed out again until it is done;
/// if it changed meanwhile, it waits for another quiet moment.
public struct SettleQueue: Sendable {
    struct Entry: Sendable {
        let url: URL
        let first: Date
        var last: Date
    }

    /// How long a thing must stay unchanged before it is checked.
    public let quiet: TimeInterval
    /// A thing that never stops changing is still checked this long after it first changed.
    public let longest: TimeInterval
    private var pending: [String: Entry] = [:]
    private var inFlight: Set<String> = []

    public init(quiet: TimeInterval = 4, longest: TimeInterval = 60) {
        self.quiet = quiet
        self.longest = longest
    }

    public mutating func note(_ units: [URL], at date: Date) {
        for unit in units {
            if var entry = pending[unit.path] {
                entry.last = max(entry.last, date)
                pending[unit.path] = entry
            } else {
                pending[unit.path] = Entry(url: unit, first: date, last: date)
            }
        }
    }

    /// When the next waiting thing can be handed out, or nil when nothing waits.
    public func nextDue() -> Date? {
        pending.filter { inFlight.contains($0.key) == false }.values.map(due).min()
    }

    /// Hands out what has been quiet long enough, oldest first, and marks it as being checked.
    public mutating func take(at now: Date) -> [URL] {
        let ready = pending.values.filter { inFlight.contains($0.url.path) == false && due($0) <= now }
            .sorted { $0.first < $1.first }
        for entry in ready {
            pending[entry.url.path] = nil
            inFlight.insert(entry.url.path)
        }
        return ready.map(\.url)
    }

    /// The check of these things is over.
    public mutating func finish(_ units: [URL]) {
        for unit in units { inFlight.remove(unit.path) }
    }

    public var isEmpty: Bool { pending.isEmpty && inFlight.isEmpty }

    private func due(_ entry: Entry) -> Date {
        min(entry.last.addingTimeInterval(quiet), entry.first.addingTimeInterval(longest))
    }
}

/// A number that starts again from zero every day.
public struct DailyCount: Sendable, Equatable {
    private var day: Date?
    private var count = 0

    public init() {}

    public mutating func add(_ amount: Int, at date: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: date)
        if day != today {
            day = today
            count = 0
        }
        count += amount
    }

    public func value(at date: Date, calendar: Calendar = .current) -> Int {
        day == calendar.startOfDay(for: date) ? count : 0
    }
}

/// Decides what to check when files change, and checks it.
public struct LiveInspector: Sendable {
    public let home: URL
    public let engine: any ScanEngine
    public let autostart: @Sendable () async -> [AutostartItem]
    public let inspect: @Sendable (URL) -> SignatureInfo

    /// `inspect` defaults to the full check: a new app is looked at once, so every file of it is verified.
    public init(
        home: URL, engine: any ScanEngine, autostart: @escaping @Sendable () async -> [AutostartItem],
        inspect: @escaping @Sendable (URL) -> SignatureInfo = { CodeSignature.inspect($0, thorough: true) }
    ) {
        self.home = home
        self.engine = engine
        self.autostart = autostart
        self.inspect = inspect
    }

    /// Half-written downloads and Finder's own bookkeeping are not worth a look.
    static let ignoredSuffixes = [".crdownload", ".download", ".part", ".partial", ".tmp", ".DS_Store", ".localized"]

    /// Turns a burst of changed paths into the things to check: a change inside an app means the whole app,
    /// and each thing is checked once.
    public static func units(from changed: [URL]) -> [URL] {
        var seen = Set<String>()
        var units: [URL] = []
        for url in changed {
            let name = url.lastPathComponent
            if name.hasPrefix(".") || ignoredSuffixes.contains(where: name.hasSuffix) { continue }
            if url.pathComponents.contains(where: { component in ignoredSuffixes.contains { component.hasSuffix($0) } })
            {
                continue
            }
            var unit = url
            if let range = url.path.range(of: ".app/") {
                unit = URL(fileURLWithPath: String(url.path[..<range.lowerBound]) + ".app")
            }
            if FileManager.default.fileExists(atPath: unit.path), seen.insert(unit.path).inserted { units.append(unit) }
        }
        return units
    }

    public func inspect(_ changed: [URL], places: [WatchedPlace], at date: Date = Date()) async -> [LiveEvent] {
        var events: [LiveEvent] = []
        var items: [AutostartItem]?
        for unit in Self.units(from: changed) {
            guard let place = WatchedPlace.owner(of: unit, among: places, home: home) else { continue }
            var finding: Finding?
            var signer: String?
            var notarized: Bool?
            var isChecked = true

            do {
                let reply = try await engine.scan(unit)
                if let hit = reply.hits.first {
                    finding = Finding(
                        severity: .malicious, reason: .knownMalware(signature: hit.signature),
                        url: URL(fileURLWithPath: hit.path))
                } else if reply.errors.contains(where: { $0.hasPrefix(unit.path + ": ") }) {
                    // The engine answered, but could not read the thing itself.
                    isChecked = false
                }
            } catch {
                isChecked = false
            }
            if finding == nil, place == .autostart, unit.pathExtension == "plist" {
                if items == nil { items = await autostart() }
                finding = Heuristics.findings(for: (items ?? []).filter { $0.plist?.path == unit.path }).first
            }
            if finding == nil, ["app", "pkg", "dmg"].contains(unit.pathExtension) {
                let signature = inspect(unit)
                if case .developer(_, let name) = signature.kind {
                    signer = name
                    notarized = signature.notarized
                }
                if signature.kind == .apple { signer = "Apple" }
                if unit.pathExtension == "app" {
                    finding = Heuristics.findings(forApps: [unit]) { _ in signature }.first
                }
            }
            let verdict: LiveEvent.Verdict = finding.map { .flagged($0) } ?? (isChecked ? .clean : .notChecked)
            events.append(
                LiveEvent(date: date, url: unit, place: place, verdict: verdict, signer: signer, notarized: notarized))
        }
        return events
    }
}

/// Reports files that appear or change under the given folders.
public final class FileWatcher: @unchecked Sendable {
    private let folders: [URL]
    private let latency: TimeInterval
    private let onChange: @Sendable ([URL]) -> Void
    private let queue = DispatchQueue(label: "com.vdzeer.ward.watcher")
    private var stream: FSEventStreamRef?

    public init(folders: [URL], latency: TimeInterval = 2, onChange: @escaping @Sendable ([URL]) -> Void) {
        self.folders = folders
        self.latency = latency
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    public func start() {
        guard stream == nil else { return }
        let existing = folders.filter { FileManager.default.fileExists(atPath: $0.path) }.map(\.path)
        guard existing.isEmpty == false else { return }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info, let list = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let wanted = UInt32(
                kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed
                    | kFSEventStreamEventFlagItemModified)
            var changed: [URL] = []
            for index in 0..<count where flags[index] & wanted != 0 {
                changed.append(URL(fileURLWithPath: list[index]))
            }
            if changed.isEmpty == false { watcher.onChange(changed) }
        }
        let options = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard
            let created = FSEventStreamCreate(
                nil, callback, &context, existing as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency, options)
        else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
