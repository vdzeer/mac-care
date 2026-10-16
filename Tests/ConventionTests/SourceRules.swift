import Foundation
import Testing

/// Rules of the project, checked against the source text itself.
@Suite struct SourceRules {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    struct SourceFile {
        let path: String
        let name: String
        /// The text with `//` comments cut off, line by line.
        let code: [String]
    }

    static func sources(under folder: String) -> [SourceFile] {
        let base = root.appendingPathComponent(folder)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var files: [SourceFile] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let code = text.components(separatedBy: "\n").map { line -> String in
                guard let comment = line.range(of: "//") else { return line }
                return String(line[..<comment.lowerBound])
            }
            files.append(
                SourceFile(
                    path: url.path.replacingOccurrences(of: root.path + "/", with: ""), name: url.lastPathComponent,
                    code: code))
        }
        return files
    }

    static func offences(in files: [SourceFile], matching pattern: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        var found: [String] = []
        for file in files {
            for (index, line) in file.code.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    found.append("\(file.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        return found
    }

    static let cyrillic = "[\\u0400-\\u04FF]"

    @Test func sourcesAreFound() {
        #expect(Self.sources(under: "Sources").count >= 20)
        #expect(Self.sources(under: "Sources").contains { $0.name == "Strings.swift" })
    }

    @Test func screensTakeColoursAndFontsOnlyFromTheTheme() {
        let apps = Self.sources(under: "Sources/Tidy") + Self.sources(under: "Sources/Ward")
        let raw =
            #"Color\(|NSColor\(|#colorLiteral|\.font\(|Font\.|\.fontWeight\(|\.foregroundColor\(|0x[0-9A-Fa-f]{6}"#
        let offences = Self.offences(in: apps, matching: raw)
        #expect(offences.isEmpty, "\(offences.joined(separator: "\n"))")
    }

    @Test func theAppsAreInEnglishOnly() {
        // Comments too: the whole repository is in English.
        var offences: [String] = []
        for folder in ["Sources", "Tests", "scripts"] {
            let base = Self.root.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let url as URL in walker where ["swift", "sh"].contains(url.pathExtension) {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if text.range(of: Self.cyrillic, options: .regularExpression) != nil { offences.append(url.path) }
            }
        }
        #expect(offences.isEmpty, "\(offences.joined(separator: "\n"))")
    }

    @Test func wordsLiveOnlyInStringsFiles() {
        // A string literal that starts with a capitalised word followed by more words is UI copy.
        let files =
            (Self.sources(under: "Sources/Tidy") + Self.sources(under: "Sources/Ward")
            + Self.sources(under: "Sources/CareUI"))
            .filter { $0.name != "Strings.swift" && $0.name != "Snapshots.swift" }
        let offences = Self.offences(in: files, matching: #""[A-Z][a-z]+ [a-z]+ [^"]*""#)
        #expect(offences.isEmpty, "\(offences.joined(separator: "\n"))")
    }

    @Test func wordsFollowTheCopyRules() {
        let files = Self.sources(under: "Sources").filter { $0.name == "Strings.swift" }
        #expect(files.count == 3)
        // No exclamation marks, no straight apostrophe inside a word (’ is the apostrophe), no emoji.
        let inLiteral = #""[^"]*(!|[A-Za-z]'[A-Za-z]|[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}])[^"]*""#
        let offences = Self.offences(in: files, matching: inLiteral)
        #expect(offences.isEmpty, "\(offences.joined(separator: "\n"))")
    }

    @Test func onlyTheRemoverRemovesFiles() {
        let files = Self.sources(under: "Sources").filter { $0.name != "Remover.swift" }
        let offences = Self.offences(in: files, matching: #"removeItem\(|trashItem\(|\bunlink\(|\brmdir\("#)
        #expect(offences.isEmpty, "\(offences.joined(separator: "\n"))")
    }

    @Test func systemDialogsNameTheApp() {
        // osascript would put its own name in the password dialog; sfltool asks for a password by itself.
        let offences = Self.offences(in: Self.sources(under: "Sources"), matching: #"/usr/bin/osascript|sfltool"#)
            .filter { !$0.contains("macOS 27") }
        #expect(offences.isEmpty, "\(offences.joined(separator: "\n"))")
    }

    @Test func systemToolsAreNamedInOnePlace() {
        let files = Self.sources(under: "Sources").filter { $0.name != "CommandRunner.swift" }
        let offences = Self.offences(in: files, matching: #""/(usr/bin|usr/sbin|usr/libexec|bin|sbin)/"#)
        #expect(offences.isEmpty, "\(offences.joined(separator: "\n"))")
    }
}
