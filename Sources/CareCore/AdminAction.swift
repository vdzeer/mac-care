import Foundation

/// The short, closed list of things the apps may do as an administrator.
///
/// Each one becomes a fixed shell line run through the standard macOS password dialog. The
/// dialog is asked for from inside the app (`InProcessAppleScript`), so macOS names the app in it.
/// Nothing typed by anyone ends up in that line: labels and paths are checked against strict patterns first.
public enum AdminAction: Sendable, Equatable {
    case disableDaemon(label: String)
    case enableDaemon(label: String, plist: String)

    public enum Failure: Error, Equatable {
        case unsafeArgument
        case cancelled
        case failed(String)
    }

    public static func isSafeLabel(_ label: String) -> Bool {
        label.isEmpty == false && label.count < 200
            && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    static func isSafeDaemonPlist(_ path: String) -> Bool {
        let prefix = "/Library/LaunchDaemons/"
        guard path.hasPrefix(prefix), path.hasSuffix(".plist") else { return false }
        return isSafeLabel(String(path.dropFirst(prefix.count).dropLast(".plist".count)))
    }

    /// The shell line, or nil when an argument does not pass the check.
    public var shellLine: String? {
        switch self {
        case .disableDaemon(let label):
            guard Self.isSafeLabel(label) else { return nil }
            return "\(Tool.launchctl) disable system/\(label); \(Tool.launchctl) bootout system/\(label); true"
        case .enableDaemon(let label, let plist):
            guard Self.isSafeLabel(label), Self.isSafeDaemonPlist(plist) else { return nil }
            return "\(Tool.launchctl) enable system/\(label); \(Tool.launchctl) bootstrap system \(plist); true"
        }
    }

    /// The AppleScript that asks for the password and runs the line, or nil when an argument does not pass.
    public var script: String? {
        shellLine.map { "do shell script \"\($0)\" with administrator privileges" }
    }

    public func run(with scripting: any AdminScripting) async throws {
        guard let script else { throw Failure.unsafeArgument }
        guard let error = await scripting.run(script) else { return }
        // -128 is AppleScript's "the user pressed Cancel".
        throw error.code == -128 ? Failure.cancelled : Failure.failed(error.message)
    }
}

/// Runs AppleScript for `AdminAction`. Tests pass a fake; the apps pass `InProcessAppleScript`.
public protocol AdminScripting: Sendable {
    /// Nil when the script succeeded; otherwise AppleScript's error number and message.
    func run(_ source: String) async -> (code: Int, message: String)?
}

/// Runs the script inside the app rather than through `osascript`, so the password dialog says
/// which app asks. AppleScript runs on the main thread; the app waits while the dialog is open.
public struct InProcessAppleScript: AdminScripting {
    public init() {}

    public func run(_ source: String) async -> (code: Int, message: String)? {
        await MainActor.run {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { return (-1, "") }
            script.executeAndReturnError(&error)
            guard let error else { return nil }
            return (
                error[NSAppleScript.errorNumber] as? Int ?? -1, error[NSAppleScript.errorMessage] as? String ?? ""
            )
        }
    }
}

public enum FullDiskAccess {
    /// True when macOS lets this process read places it guards, such as Safari's folder.
    public static func isGranted(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let guarded = home.appendingPathComponent("Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: guarded.path)) != nil
    }

    /// Opens the page of System Settings where the owner can grant it.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
