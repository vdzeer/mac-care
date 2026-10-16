import Foundation

/// The parts of a launchd job description the apps care about.
public struct LaunchdJob: Sendable, Equatable {
    public let label: String
    public let program: String?
    public let arguments: [String]
    public let runsAtLoad: Bool
    public let keepsAlive: Bool
    public let interval: Int?

    public static func parse(_ data: Data) -> LaunchdJob? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let label = plist["Label"] as? String
        else { return nil }
        let arguments = (plist["ProgramArguments"] as? [String]) ?? []
        let program = (plist["Program"] as? String) ?? arguments.first
        let keepAlive = (plist["KeepAlive"] as? Bool) ?? (plist["KeepAlive"] is [String: Any])
        return LaunchdJob(
            label: label, program: program, arguments: arguments, runsAtLoad: (plist["RunAtLoad"] as? Bool) ?? false,
            keepsAlive: keepAlive, interval: plist["StartInterval"] as? Int)
    }
}

public enum DisabledServices {
    /// Reads `launchctl print-disabled <domain>`: for every label listed, whether it is switched on.
    public static func states(_ text: String) -> [String: Bool] {
        var states: [String: Bool] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\" \t"))
            let state = parts[1].trimmingCharacters(in: .whitespaces)
            // The old spelling says whether the label is disabled, the new one says what it is.
            states[label] = (state == "enabled" || state == "false")
        }
        return states
    }

    /// The labels the owner has switched off.
    public static func parse(_ text: String) -> Set<String> {
        Set(states(text).filter { $0.value == false }.keys)
    }
}
