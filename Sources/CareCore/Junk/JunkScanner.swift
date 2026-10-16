import Foundation

public struct JunkScanner: Sendable {
    public let home: URL
    public let runner: any CommandRunning
    /// Bundle ids of apps that are open now; their caches are skipped.
    public let runningBundleIDs: Set<String>

    /// Names of apps that are open now, lower-cased; their data folders are skipped.
    public let runningAppNames: Set<String>

    public init(
        home: URL, runner: any CommandRunning, runningBundleIDs: Set<String> = [], runningAppNames: Set<String> = []
    ) {
        self.home = home
        self.runner = runner
        self.runningBundleIDs = runningBundleIDs
        self.runningAppNames = Set(runningAppNames.map { $0.lowercased() })
    }

    /// Measures every rule, or only those in `only`. `onGroup` fires as each rule finishes, so the screen can
    /// fill in gradually.
    public func scan(
        only: Set<JunkRule.ID>? = nil, onGroup: @Sendable @escaping (JunkGroup) -> Void = { _ in }
    ) async -> JunkScan {
        let rules = JunkRules.all(home: home).filter { only?.contains($0.id) ?? true }
        var groups: [JunkRule.ID: JunkGroup] = [:]
        await withTaskGroup(of: JunkGroup.self) { tasks in
            for rule in rules {
                tasks.addTask { await group(for: rule) }
            }
            for await group in tasks {
                groups[group.id] = group
                onGroup(group)
            }
        }
        return JunkScan(groups: rules.compactMap { groups[$0.id] })
    }

    private func group(for rule: JunkRule) async -> JunkGroup {
        switch rule.source {
        case .children: return await childrenGroup(rule)
        case .simulators: return await simulatorGroup(rule)
        case .simulatorRuntimes: return await runtimeGroup(rule)
        case .nested: return await nestedGroup(rule)
        }
    }

    private func childrenGroup(_ rule: JunkRule) async -> JunkGroup {
        let blockers = rule.blockers(runningBundleIDs: runningBundleIDs)
        if blockers.isEmpty == false {
            return JunkGroup(rule: rule, items: [], skipped: blockers.sorted())
        }
        var candidates: [URL] = []
        var skipped: [String] = []
        for root in rule.roots {
            // Built from names, so every path keeps the spelling of the root it was found under.
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            for name in names {
                let child = root.appendingPathComponent(name)
                if rule.excludedNames.contains(name) || rule.excludedPrefixes.contains(where: name.hasPrefix) {
                    continue
                }
                if rule.belongsToOpenApp(name, runningBundleIDs: runningBundleIDs, runningAppNames: runningAppNames) {
                    skipped.append(name)
                    continue
                }
                candidates.append(child)
            }
        }

        var items: [JunkItem] = []
        await withTaskGroup(of: JunkItem.self) { tasks in
            // A handful at a time: more only makes the disk queue longer.
            var pending = candidates.makeIterator()
            func addNext() {
                guard let url = pending.next() else { return }
                tasks.addTask {
                    let usage = DirectorySizer.usage(of: url, isCancelled: { Task.isCancelled })
                    return JunkItem(
                        id: "\(rule.id.rawValue):\(url.path)", rule: rule.id, name: url.lastPathComponent, urls: [url],
                        bytes: usage.bytes, removal: rule.removal)
                }
            }
            for _ in 0..<6 { addNext() }
            for await item in tasks {
                items.append(item)
                addNext()
            }
        }
        // An empty folder frees nothing; listing it would only add a row.
        items.removeAll { $0.bytes == 0 }
        items.sort { ($0.bytes, $1.name) > ($1.bytes, $0.name) }
        return JunkGroup(rule: rule, items: items, skipped: skipped.sorted())
    }

    private func simulatorGroup(_ rule: JunkRule) async -> JunkGroup {
        guard let result = try? await runner.run(Tool.xcrun, ["simctl", "list", "devices", "-j"]), result.succeeded
        else { return JunkGroup(rule: rule, items: [], skipped: []) }
        let devices = SimulatorList.parse(result.stdout)
        var items: [JunkItem] = []
        for device in devices {
            let folder = rule.roots[0].appendingPathComponent(device.udid)
            let usage = DirectorySizer.usage(of: folder, isCancelled: { Task.isCancelled })
            items.append(
                JunkItem(
                    id: "\(rule.id.rawValue):\(device.udid)", rule: rule.id, name: device.name, runtime: device.runtime,
                    isUnavailable: device.isAvailable == false, urls: [folder], bytes: usage.bytes,
                    removal: .simulator(udid: device.udid)))
        }
        // Devices Xcode can no longer run come first: they are the safe ones to drop.
        items.sort { lhs, rhs in
            if lhs.isUnavailable != rhs.isUnavailable { return lhs.isUnavailable }
            return lhs.bytes > rhs.bytes
        }
        return JunkGroup(rule: rule, items: items, skipped: [])
    }
}

extension JunkScanner {
    /// Looks one level down: `<root>/<app>/<cache folder>` for every app and every name of the rule.
    fileprivate func nestedGroup(_ rule: JunkRule) async -> JunkGroup {
        var items: [JunkItem] = []
        var skipped: [String] = []
        for root in rule.roots {
            let apps = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            for app in apps.sorted() where rule.excludedPrefixes.contains(where: app.hasPrefix) == false {
                let folder = root.appendingPathComponent(app)
                guard rule.nestedMarkers.isEmpty || rule.nestedMarkers.contains(where: { Self.holds(folder, $0) })
                else { continue }
                let caches = rule.nestedNames.filter { Self.holds(folder, $0) }.map {
                    folder.appendingPathComponent($0)
                }
                guard caches.isEmpty == false else { continue }
                if rule.belongsToOpenApp(app, runningBundleIDs: runningBundleIDs, runningAppNames: runningAppNames) {
                    skipped.append(app)
                    continue
                }
                let bytes = caches.reduce(Int64(0)) { total, url in
                    total + DirectorySizer.usage(of: url, isCancelled: { Task.isCancelled }).bytes
                }
                if bytes > 0 {
                    items.append(
                        JunkItem(
                            id: "\(rule.id.rawValue):\(folder.path)", rule: rule.id, name: app, urls: caches,
                            bytes: bytes, removal: rule.removal))
                }
            }
        }
        items.sort { ($0.bytes, $1.name) > ($1.bytes, $0.name) }
        return JunkGroup(rule: rule, items: items, skipped: skipped)
    }

    /// Whether `folder` holds `relative`, compared letter for letter. The disk itself ignores case,
    /// so asking it directly would let "cache" pass for "Cache".
    fileprivate static func holds(_ folder: URL, _ relative: String) -> Bool {
        var current = folder
        for component in relative.split(separator: "/").map(String.init) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: current.path)) ?? []
            guard names.contains(component) else { return false }
            current = current.appendingPathComponent(component)
        }
        return true
    }

    fileprivate func runtimeGroup(_ rule: JunkRule) async -> JunkGroup {
        guard let result = try? await runner.run(Tool.xcrun, ["simctl", "runtime", "list", "-j"]), result.succeeded
        else { return JunkGroup(rule: rule, items: [], skipped: []) }
        let items = SimulatorRuntimes.parse(result.stdout).filter(\.isDeletable).map { runtime in
            JunkItem(
                id: "\(rule.id.rawValue):\(runtime.identifier)", rule: rule.id, name: runtime.name,
                runtime: runtime.build, lastUsed: runtime.lastUsed, urls: [], bytes: runtime.bytes,
                removal: .simulatorRuntime(identifier: runtime.identifier))
        }
        return JunkGroup(rule: rule, items: items, skipped: [])
    }
}

/// A simulator system image: a whole iOS, watchOS or tvOS that Xcode downloaded.
public struct SimulatorRuntime: Sendable, Equatable {
    public let identifier: String
    public let name: String
    public let build: String
    public let bytes: Int64
    public let lastUsed: Date?
    public let isDeletable: Bool
}

public enum SimulatorRuntimes {
    /// Reads the output of `xcrun simctl runtime list -j`. The ones left unused longest come first.
    public static func parse(_ json: String) -> [SimulatorRuntime] {
        struct Entry: Decodable {
            let identifier: String
            let runtimeIdentifier: String?
            let version: String?
            let build: String?
            let sizeBytes: Int64?
            let deletable: Bool?
            let lastUsedAt: String?
        }
        guard let entries = try? JSONDecoder().decode([String: Entry].self, from: Data(json.utf8)) else { return [] }
        let dates = ISO8601DateFormatter()
        return entries.values.map { entry in
            // "com.apple.CoreSimulator.SimRuntime.iOS-18-6" names the system; the version says which one exactly.
            let system = SimulatorList.runtimeName(entry.runtimeIdentifier ?? "").split(separator: " ").first.map(
                String.init)
            let name = [system, entry.version].compactMap { $0 }.joined(separator: " ")
            return SimulatorRuntime(
                identifier: entry.identifier, name: name.isEmpty ? entry.identifier : name, build: entry.build ?? "",
                bytes: entry.sizeBytes ?? 0, lastUsed: entry.lastUsedAt.flatMap(dates.date(from:)),
                isDeletable: entry.deletable ?? false)
        }
        .sorted {
            ($0.lastUsed ?? .distantPast, $0.identifier) < ($1.lastUsed ?? .distantPast, $1.identifier)
        }
    }
}

public struct SimulatorDevice: Sendable, Equatable {
    public let udid: String
    public let name: String
    public let runtime: String
    public let isAvailable: Bool
}

public enum SimulatorList {
    /// Reads the output of `xcrun simctl list devices -j`.
    public static func parse(_ json: String) -> [SimulatorDevice] {
        struct Listing: Decodable {
            struct Device: Decodable {
                let udid: String
                let name: String
                let isAvailable: Bool?
            }
            let devices: [String: [Device]]
        }
        guard let listing = try? JSONDecoder().decode(Listing.self, from: Data(json.utf8)) else { return [] }
        return listing.devices.sorted { $0.key < $1.key }.flatMap { key, devices in
            devices.map {
                SimulatorDevice(
                    udid: $0.udid, name: $0.name, runtime: runtimeName(key), isAvailable: $0.isAvailable ?? false)
            }
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-18-2" becomes "iOS 18.2".
    static func runtimeName(_ key: String) -> String {
        let last = key.split(separator: ".").last.map(String.init) ?? key
        let parts = last.split(separator: "-")
        guard let system = parts.first, parts.count > 1 else { return last }
        return "\(system) " + parts.dropFirst().joined(separator: ".")
    }
}
