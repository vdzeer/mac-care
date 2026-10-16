import Foundation

/// A locked drawer for files a check found. Nothing in it can run, and everything in it can go back.
public struct QuarantineStore: Sendable {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let originalPath: String
        public let reason: String
        public let date: Date
        public let bytes: Int64
        public let permissions: Int
    }

    public enum Failure: Error, Equatable {
        case notFound
        case placeTaken
        case cannotMove(String)
    }

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public static func standard() -> QuarantineStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return QuarantineStore(folder: support.appendingPathComponent("Ward/Quarantine"))
    }

    public func entries() -> [Entry] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return folders.compactMap { item -> Entry? in
            guard let data = try? Data(contentsOf: item.appendingPathComponent("entry.json")) else { return nil }
            return try? decoder.decode(Entry.self, from: data)
        }
        .sorted { $0.date > $1.date }
    }

    /// Moves the file in, takes away every permission, and writes down where it came from.
    @discardableResult
    public func add(_ url: URL, reason: String, at date: Date = Date()) throws -> Entry {
        let manager = FileManager.default
        let attributes = try manager.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? Int) ?? 0o644
        let usage = DirectorySizer.usage(of: url)
        // Whole seconds, so the date reads back from disk exactly as it was written.
        let date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        let entry = Entry(
            id: UUID().uuidString, name: url.lastPathComponent, originalPath: url.path, reason: reason, date: date,
            bytes: usage.bytes, permissions: permissions)

        let slot = folder.appendingPathComponent(entry.id)
        try manager.createDirectory(at: slot, withIntermediateDirectories: true)
        do {
            try manager.moveItem(at: url, to: payload(entry))
        } catch {
            try? Remover(pathGuard: PathGuard(allowedRoots: [folder]), runner: SystemCommandRunner()).discard(slot)
            throw Failure.cannotMove(error.localizedDescription)
        }
        try? manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: payload(entry).path)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(entry).write(to: slot.appendingPathComponent("entry.json"), options: .atomic)
        return entry
    }

    /// Puts the file back exactly where and how it was. Refuses if something else now sits there.
    public func restore(_ entry: Entry) throws {
        let manager = FileManager.default
        let stored = payload(entry)
        guard manager.fileExists(atPath: stored.path) else { throw Failure.notFound }
        guard manager.fileExists(atPath: entry.originalPath) == false else { throw Failure.placeTaken }
        try? manager.setAttributes([.posixPermissions: entry.permissions], ofItemAtPath: stored.path)
        let destination = URL(fileURLWithPath: entry.originalPath)
        do {
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.moveItem(at: stored, to: destination)
        } catch {
            try? manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: stored.path)
            throw Failure.cannotMove(error.localizedDescription)
        }
        try Remover(pathGuard: PathGuard(allowedRoots: [folder]), runner: SystemCommandRunner())
            .discard(folder.appendingPathComponent(entry.id))
    }

    /// Deletes the quarantined file for good.
    public func delete(_ entry: Entry) throws {
        let slot = folder.appendingPathComponent(entry.id)
        guard FileManager.default.fileExists(atPath: slot.path) else { throw Failure.notFound }
        // A folder with no permissions cannot be emptied; give them back first.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: payload(entry).path)
        try Remover(pathGuard: PathGuard(allowedRoots: [folder]), runner: SystemCommandRunner()).discard(slot)
    }

    private func payload(_ entry: Entry) -> URL {
        folder.appendingPathComponent(entry.id).appendingPathComponent("payload")
    }
}
