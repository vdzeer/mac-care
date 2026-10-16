import Foundation

public struct JunkItem: Sendable, Identifiable, Equatable {
    public let id: String
    public let rule: JunkRule.ID
    public let name: String
    /// Extra facts for simulators: the system version, and whether Xcode can still run the device.
    public var runtime: String?
    public var isUnavailable = false
    /// When a simulator system was last started, if known.
    public var lastUsed: Date?
    public let urls: [URL]
    public let bytes: Int64
    public let removal: Removal

    public init(
        id: String, rule: JunkRule.ID, name: String, runtime: String? = nil, isUnavailable: Bool = false,
        lastUsed: Date? = nil, urls: [URL], bytes: Int64, removal: Removal
    ) {
        self.id = id
        self.rule = rule
        self.name = name
        self.runtime = runtime
        self.isUnavailable = isUnavailable
        self.lastUsed = lastUsed
        self.urls = urls
        self.bytes = bytes
        self.removal = removal
    }
}

public struct JunkGroup: Sendable, Identifiable, Equatable {
    public let rule: JunkRule
    public let items: [JunkItem]
    /// Names left out because the app they belong to is running.
    public let skipped: [String]

    public init(rule: JunkRule, items: [JunkItem], skipped: [String] = []) {
        self.rule = rule
        self.items = items
        self.skipped = skipped
    }

    public var id: JunkRule.ID { rule.id }
    public var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

public struct JunkScan: Sendable, Equatable {
    public let groups: [JunkGroup]

    public init(groups: [JunkGroup]) {
        self.groups = groups
    }

    public var items: [JunkItem] { groups.flatMap(\.items) }

    public func groups(of cleanupClass: CleanupClass) -> [JunkGroup] {
        groups.filter { $0.rule.cleanupClass == cleanupClass }
    }
}

/// What the owner has ticked. Kept apart from the scan so a rescan does not lose the choice.
public struct JunkSelection: Sendable, Equatable {
    public enum GroupState: Sendable, Equatable { case none, some, all }

    public private(set) var itemIDs: Set<String>

    public init(itemIDs: Set<String> = []) {
        self.itemIDs = itemIDs
    }

    /// Everything that regenerates is ticked; everything else waits for the owner.
    public static func initial(for scan: JunkScan) -> JunkSelection {
        JunkSelection(itemIDs: Set(scan.groups(of: .regenerates).flatMap(\.items).map(\.id)))
    }

    /// The owner's choice carried over to a new measurement: what was there before keeps its tick or its blank,
    /// and only what is new gets the default of `initial`.
    public static func carried(_ previous: JunkSelection, from old: JunkScan, to new: JunkScan) -> JunkSelection {
        let known = Set(old.items.map(\.id))
        let defaults = initial(for: new).itemIDs
        let ticked = new.items.map(\.id).filter {
            known.contains($0) ? previous.itemIDs.contains($0) : defaults.contains($0)
        }
        return JunkSelection(itemIDs: Set(ticked))
    }

    public func contains(_ item: JunkItem) -> Bool { itemIDs.contains(item.id) }

    public func state(of group: JunkGroup) -> GroupState {
        let picked = group.items.filter(contains).count
        if picked == 0 { return .none }
        return picked == group.items.count ? .all : .some
    }

    public mutating func toggle(_ item: JunkItem) {
        if itemIDs.remove(item.id) == nil { itemIDs.insert(item.id) }
    }

    /// A partly ticked group becomes fully ticked; a fully ticked one is cleared.
    public mutating func toggle(_ group: JunkGroup) {
        let ids = group.items.map(\.id)
        if state(of: group) == .all {
            itemIDs.subtract(ids)
        } else {
            itemIDs.formUnion(ids)
        }
    }
}

public struct JunkPlan: Sendable, Equatable {
    public let items: [JunkItem]

    public var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    public var isEmpty: Bool { items.isEmpty }
}

public enum JunkMath {
    public static func plan(_ scan: JunkScan, _ selection: JunkSelection) -> JunkPlan {
        JunkPlan(items: scan.items.filter(selection.contains))
    }

    /// Why an item of the plan was left alone at cleanup time, as the report records it.
    public static let openAppReason = "its app is open"

    /// The plan checked against the apps open right now. A measurement can be hours old, and an app opened since
    /// must not lose its build folder or its cache from under it. `runningAppNames` are lower-cased.
    public static func recheck(
        _ items: [JunkItem], rules: [JunkRule], runningBundleIDs: Set<String>, runningAppNames: Set<String>
    ) -> (safe: [JunkItem], blocked: [JunkItem]) {
        let rules = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        var safe: [JunkItem] = []
        var blocked: [JunkItem] = []
        for item in items {
            guard let rule = rules[item.rule] else {
                blocked.append(item)
                continue
            }
            let isBusy =
                rule.blockers(runningBundleIDs: runningBundleIDs).isEmpty == false
                || rule.belongsToOpenApp(
                    item.name, runningBundleIDs: runningBundleIDs, runningAppNames: runningAppNames)
            if isBusy { blocked.append(item) } else { safe.append(item) }
        }
        return (safe, blocked)
    }

    public static func selectedBytes(in group: JunkGroup, _ selection: JunkSelection) -> Int64 {
        group.items.filter(selection.contains).reduce(0) { $0 + $1.bytes }
    }

    /// Selected bytes for each part of the overview bar, in the fixed order of `JunkCategory`.
    public static func segments(_ scan: JunkScan, _ selection: JunkSelection) -> [(
        category: JunkCategory, bytes: Int64
    )] {
        JunkCategory.allCases.map { category in
            let bytes = scan.groups.filter { $0.rule.category == category }
                .reduce(Int64(0)) { $0 + selectedBytes(in: $1, selection) }
            return (category, bytes)
        }
    }
}
