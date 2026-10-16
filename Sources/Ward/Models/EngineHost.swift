import CareCore
import Foundation
import Observation

/// Shares one running engine between a check and the live protection, and stops it when nobody needs it.
@Observable final class EngineHost {
    enum Stage: Equatable { case updating, starting }

    private(set) var isInstalled = false
    private(set) var lastCheck: Date?
    /// Folders the engine stays out of: its own files and the quarantine.
    let keepOut: [URL]
    private let daemon: ClamDaemon
    private var holders = 0
    /// One database update and one engine start at a time; whoever asks meanwhile waits for the same one.
    @ObservationIgnored private var updating: Task<Void, any Error>?
    @ObservationIgnored private var starting: Task<Void, any Error>?
    @ObservationIgnored private var lastAttempt: Date?

    init(daemon: ClamDaemon = ClamDaemon(), keepOut: [URL]) {
        self.daemon = daemon
        self.keepOut = keepOut + [daemon.paths.folder]
        refresh()
    }

    func refresh() {
        isInstalled = daemon.isInstalled
        lastCheck = daemon.paths.lastCheckDate()
    }

    func setPreview(installed: Bool, lastCheck: Date?) {
        isInstalled = installed
        self.lastCheck = lastCheck
    }

    /// Hands out a working engine. The database is refreshed first when it is missing or a day old.
    func acquire(onStage: (Stage) -> Void) async throws -> ClamClient {
        refresh()
        guard isInstalled else { throw EngineError.notInstalled }
        let hasDatabase = daemon.paths.databaseDate() != nil
        if hasDatabase == false || ClamPaths.isUpdateDue(lastCheck: lastCheck, lastAttempt: lastAttempt) {
            onStage(.updating)
            do {
                try await updateDatabase()
            } catch {
                // Offline is fine as long as an older database is there to work with.
                if daemon.paths.databaseDate() == nil { throw error }
            }
        }
        onStage(.starting)
        try await startEngine()
        holders += 1
        return daemon.client
    }

    /// While someone holds the engine, refreshes the database once it is a day old. The running engine is told to
    /// reload it, so live protection keeps up with new signatures without a restart.
    func updateIfDue() async {
        refresh()
        guard isInstalled, holders > 0, ClamPaths.isUpdateDue(lastCheck: lastCheck, lastAttempt: lastAttempt)
        else { return }
        try? await updateDatabase()
    }

    /// Whether the engine answers right now. A hung engine counts as not answering after a few seconds.
    func isAnswering() async -> Bool {
        await daemon.client.ping()
    }

    /// Starts the engine again for those who hold it, after it stopped answering.
    func revive() async throws {
        guard holders > 0 else { return }
        try await startEngine()
    }

    func release() async {
        holders = max(holders - 1, 0)
        if holders == 0 { await daemon.stop() }
    }

    func shutdown() async {
        holders = 0
        await daemon.stop()
    }

    private func updateDatabase() async throws {
        if let updating { return try await updating.value }
        let (daemon, keepOut) = (daemon, keepOut)
        let task = Task { try await daemon.updateDatabase(excluding: keepOut) }
        updating = task
        lastAttempt = Date()
        defer {
            updating = nil
            refresh()
        }
        try await task.value
    }

    private func startEngine() async throws {
        if let starting { return try await starting.value }
        let (daemon, keepOut) = (daemon, keepOut)
        let task = Task { try await daemon.start(excluding: keepOut) }
        starting = task
        defer { starting = nil }
        try await task.value
    }
}
