import Foundation

/// Remembers which autostart items the owner has already seen, so a new one stands out.
public struct BaselineStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Nil on the very first run: nothing has been seen yet, so nothing can be called new.
    public func known() -> Set<String>? {
        guard let data = try? Data(contentsOf: fileURL), let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return Set(ids)
    }

    public func save(_ ids: Set<String>) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ids.sorted()).write(to: fileURL, options: .atomic)
    }

    /// The items that appeared since the owner last looked. The first run records everything and reports nothing.
    public func newItems(among items: [AutostartItem]) -> Set<String> {
        let current = Set(items.map(\.id))
        guard let known = known() else {
            try? save(current)
            return []
        }
        return current.subtracting(known)
    }

    /// The owner has seen what is there now.
    public func acknowledge(_ items: [AutostartItem]) {
        try? save(Set(items.map(\.id)))
    }
}
