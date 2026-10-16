import Foundation

public struct RemovalRequest: Sendable, Equatable, Identifiable {
    public let id: String
    /// What the journal files the entry under, such as a rule id.
    public let kind: String
    public let name: String
    public let urls: [URL]
    public let bytes: Int64
    public let removal: Removal

    public init(id: String, kind: String, name: String, urls: [URL], bytes: Int64, removal: Removal) {
        self.id = id
        self.kind = kind
        self.name = name
        self.urls = urls
        self.bytes = bytes
        self.removal = removal
    }
}

public enum RemovalResult: Sendable, Equatable {
    case removed
    /// Dry run: this is what would have been removed.
    case planned
    case refused(PathGuard.Refusal)
    case failed(String)
    /// Left alone on purpose: something changed since the measurement, such as an app that opened or a file that
    /// was edited. The reason is for the developer's tool, not for the screens.
    case skipped(String)
}

public struct RemovalOutcome: Sendable, Equatable {
    public let request: RemovalRequest
    public let result: RemovalResult

    public init(request: RemovalRequest, result: RemovalResult) {
        self.request = request
        self.result = result
    }
}

public struct RemovalReport: Sendable, Equatable {
    public let outcomes: [RemovalOutcome]

    public init(outcomes: [RemovalOutcome]) {
        self.outcomes = outcomes
    }

    public var removed: [RemovalRequest] { outcomes.filter { $0.result == .removed }.map(\.request) }
    public var planned: [RemovalRequest] { outcomes.filter { $0.result == .planned }.map(\.request) }
    public var problems: [RemovalOutcome] {
        outcomes.filter { $0.result != .removed && $0.result != .planned }
    }
    public var freedBytes: Int64 { removed.reduce(0) { $0 + $1.bytes } }
    /// Gone for good: deleted, or removed by `simctl`.
    public var deletedBytes: Int64 { removed.filter { $0.removal != .trash }.reduce(0) { $0 + $1.bytes } }
    /// Moved to the Trash: the space comes back only when the Trash is emptied.
    public var trashedBytes: Int64 { removed.filter { $0.removal == .trash }.reduce(0) { $0 + $1.bytes } }
    public var plannedBytes: Int64 { planned.reduce(0) { $0 + $1.bytes } }
    /// Whether anything left its place, so the free space shown elsewhere is out of date.
    public var changedTheDisk: Bool { removed.isEmpty == false }

    /// The same report with requests that were left alone on purpose added at the end.
    public func adding(skipped requests: [RemovalRequest], because reason: String) -> RemovalReport {
        RemovalReport(outcomes: outcomes + requests.map { RemovalOutcome(request: $0, result: .skipped(reason)) })
    }
}

/// The only code in the project that removes anything from disk.
public struct Remover: Sendable {
    public let pathGuard: PathGuard
    public let runner: any CommandRunning
    /// How a path is moved to the Trash. Tests replace it, so they never fill the real Trash.
    public let moveToTrash: @Sendable (URL) throws -> Void

    public init(
        pathGuard: PathGuard, runner: any CommandRunning,
        moveToTrash: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
    ) {
        self.pathGuard = pathGuard
        self.runner = runner
        self.moveToTrash = moveToTrash
    }

    public func remove(
        _ requests: [RemovalRequest], dryRun: Bool, onOutcome: @Sendable (RemovalOutcome) -> Void = { _ in }
    ) async -> RemovalReport {
        var outcomes: [RemovalOutcome] = []
        for request in requests {
            if Task.isCancelled { break }
            let outcome = RemovalOutcome(request: request, result: await remove(request, dryRun: dryRun))
            outcomes.append(outcome)
            onOutcome(outcome)
        }
        return RemovalReport(outcomes: outcomes)
    }

    private func remove(_ request: RemovalRequest, dryRun: Bool) async -> RemovalResult {
        if case .simulator(let udid) = request.removal {
            if dryRun { return .planned }
            do {
                let result = try await runner.run(Tool.xcrun, ["simctl", "delete", udid], timeout: 120)
                return result.succeeded
                    ? .removed : .failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                return .failed(String(describing: error))
            }
        }

        if case .simulatorRuntime(let identifier) = request.removal {
            // The identifier goes straight to the tool as one argument; still, only a real UUID is let through.
            guard UUID(uuidString: identifier) != nil else { return .failed("bad runtime identifier") }
            if dryRun { return .planned }
            do {
                let result = try await runner.run(
                    Tool.xcrun, ["simctl", "runtime", "delete", identifier], timeout: 600)
                return result.succeeded
                    ? .removed : .failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                return .failed(String(describing: error))
            }
        }

        // Every path of the request is checked before the first one is touched.
        var checked: [URL] = []
        for url in request.urls {
            switch pathGuard.check(url) {
            case .success(let safe): checked.append(safe)
            case .failure(let refusal): return .refused(refusal)
            }
        }
        if dryRun { return .planned }

        do {
            for url in checked where FileManager.default.fileExists(atPath: url.path) || isSymbolicLink(url) {
                if request.removal == .trash {
                    try moveToTrash(url)
                } else {
                    try FileManager.default.removeItem(at: url)
                }
            }
            return .removed
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Removes one path at once, after the same check. For a store that tidies its own folder.
    public func discard(_ url: URL) throws {
        switch pathGuard.check(url) {
        case .success(let safe): try FileManager.default.removeItem(at: safe)
        case .failure(let refusal): throw refusal
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
    }
}

extension JunkItem {
    public var removalRequest: RemovalRequest {
        RemovalRequest(id: id, kind: rule.rawValue, name: name, urls: urls, bytes: bytes, removal: removal)
    }
}
