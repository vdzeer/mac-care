import Foundation

/// A plain record of what was removed: one JSON object per line, newest last.
public struct CleanupJournal: Sendable {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public var id: String { "\(date.timeIntervalSince1970):\(path)" }
        public let date: Date
        public let kind: String
        public let name: String
        public let path: String
        public let bytes: Int64
        public let method: String
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The journal of an app, in its Application Support folder.
    public static func standard(appFolder: String) -> CleanupJournal {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return CleanupJournal(
            fileURL: support.appendingPathComponent(appFolder).appendingPathComponent("journal.jsonl"))
    }

    public func record(_ report: RemovalReport, at date: Date = Date()) throws {
        let entries = report.removed.map { request in
            Entry(
                date: date, kind: request.kind, name: request.name, path: request.urls.first?.path ?? "",
                bytes: request.bytes, method: Self.methodName(request.removal))
        }
        guard entries.isEmpty == false else { return }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var text = ""
        for entry in entries {
            text += String(decoding: try encoder.encode(entry), as: UTF8.self) + "\n"
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        } else {
            try Data(text.utf8).write(to: fileURL)
        }
    }

    public func entries() -> [Entry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
    }

    private static func methodName(_ removal: Removal) -> String {
        switch removal {
        case .delete: "delete"
        case .trash: "trash"
        case .simulator: "simulator"
        case .simulatorRuntime: "simulatorRuntime"
        }
    }
}
