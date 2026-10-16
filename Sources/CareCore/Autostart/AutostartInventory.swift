import Foundation

/// Something that starts by itself: a launchd job from a LaunchAgents or LaunchDaemons folder, or a login item.
public struct AutostartItem: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable {
        /// `~/Library/LaunchAgents`: runs for this user, can be switched without a password.
        case userAgent
        /// `/Library/LaunchAgents`: installed for every user, runs in this user's session.
        case globalAgent
        /// `/Library/LaunchDaemons`: runs as the system; switching needs an administrator.
        case daemon
        /// An app or helper that opens at login; only System Settings can switch it.
        case loginItem
        /// A background job registered from inside an app; only System Settings can switch it.
        case appService
    }

    public let id: String
    public let kind: Kind
    public let label: String
    public let name: String
    public let plist: URL?
    /// What launchd starts.
    public let program: String?
    /// What really runs when the program is only a launcher such as `open` or `sh`.
    public let target: String?
    /// The launcher's name when the job goes through one.
    public let launcher: String?
    public let isTargetMissing: Bool
    public let isEnabled: Bool
    public let runsAtLoad: Bool
    public let interval: Int?
    public let developer: String?
    /// The signature of `target`; nil when nothing on disk could be inspected.
    public let signature: SignatureInfo?

    public init(
        id: String, kind: Kind, label: String, name: String, plist: URL?, program: String?, target: String?,
        launcher: String?, isTargetMissing: Bool, isEnabled: Bool, runsAtLoad: Bool, interval: Int?, developer: String?,
        signature: SignatureInfo?
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.name = name
        self.plist = plist
        self.program = program
        self.target = target
        self.launcher = launcher
        self.isTargetMissing = isTargetMissing
        self.isEnabled = isEnabled
        self.runsAtLoad = runsAtLoad
        self.interval = interval
        self.developer = developer
        self.signature = signature
    }

    public var needsAdministrator: Bool { kind == .daemon }
    public var canBeSwitchedHere: Bool { kind == .userAgent || kind == .globalAgent || kind == .daemon }
}

public struct AutostartInventory: Sendable {
    public let home: URL
    /// The folder that holds `LaunchAgents` and `LaunchDaemons` for the whole Mac: `/Library`.
    public let systemLibrary: URL
    public let userID: Int
    public let runner: any CommandRunning
    public let inspect: @Sendable (URL) -> SignatureInfo

    public init(
        home: URL, systemLibrary: URL = URL(fileURLWithPath: "/Library"), userID: Int = Int(getuid()),
        runner: any CommandRunning, inspect: @escaping @Sendable (URL) -> SignatureInfo = Self.inspectProgram
    ) {
        self.home = home
        self.systemLibrary = systemLibrary
        self.userID = userID
        self.runner = runner
        self.inspect = inspect
    }

    public func items() async -> [AutostartItem] {
        // Apps that open at login are left out: since macOS 27 the only list of them,
        // `sfltool dumpbtm`, asks for an administrator password. System Settings shows them.
        async let userOff = disabled(domain: "gui/\(userID)")
        async let systemOff = disabled(domain: "system")
        let (offForUser, offForSystem) = await (userOff, systemOff)

        let folders: [(URL, AutostartItem.Kind)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (systemLibrary.appendingPathComponent("LaunchAgents"), .globalAgent),
            (systemLibrary.appendingPathComponent("LaunchDaemons"), .daemon),
        ]
        var items: [AutostartItem] = []
        for (folder, kind) in folders {
            let files =
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where file.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: file), let job = LaunchdJob.parse(data) else { continue }
                let off = kind == .daemon ? offForSystem : offForUser
                let resolved = Self.resolve(program: job.program, arguments: job.arguments)
                let exists = resolved.target.map { FileManager.default.fileExists(atPath: $0) } ?? false
                // Some helpers can be run but not read by an ordinary user; those cannot be judged.
                let readable = resolved.target.map { FileManager.default.isReadableFile(atPath: $0) } ?? false
                let signature = readable ? resolved.target.map { inspect(URL(fileURLWithPath: $0)) } : nil
                items.append(
                    AutostartItem(
                        id: "\(kind.rawValue):\(job.label)", kind: kind, label: job.label,
                        name: Self.displayName(target: resolved.target, fallback: job.label),
                        plist: file, program: job.program, target: resolved.target, launcher: resolved.launcher,
                        isTargetMissing: resolved.target != nil && exists == false,
                        isEnabled: off.contains(job.label) == false, runsAtLoad: job.runsAtLoad || job.keepsAlive,
                        interval: job.interval, developer: Self.developer(signature),
                        signature: signature))
            }
        }

        return items
    }

    /// A program on its own gets the full check, every file of it hashed and its notarization asked, as
    /// `codesign --verify --deep --strict` does. A program inside an app keeps the quick check: the full one would
    /// hash the whole app every time the list loads.
    public static func inspectProgram(_ url: URL) -> SignatureInfo {
        CodeSignature.inspect(url, thorough: enclosingApp(url.path) == nil)
    }

    private func disabled(domain: String) async -> Set<String> {
        guard let result = try? await runner.run(Tool.launchctl, ["print-disabled", domain]) else { return [] }
        return DisabledServices.parse(result.stdout)
    }

    /// Programs that only start something else: shells, script interpreters and wrappers. Judging their
    /// signature would say "Apple" about anything they are told to run.
    static let launchers: Set<String> = [
        "open", "sh", "bash", "zsh", "ksh", "dash", "csh", "tcsh", "env", "arch", "python", "python3", "osascript",
        "nohup", "caffeinate", "ruby", "perl", "node",
    ]

    /// Launchers that take a line of code after a flag instead of a file to run.
    static let inlineCodeFlags: [String: Set<String>] = [
        "sh": ["-c"], "bash": ["-c"], "zsh": ["-c"], "ksh": ["-c"], "dash": ["-c"], "csh": ["-c"], "tcsh": ["-c"],
        "python": ["-c"], "python3": ["-c"], "ruby": ["-e"], "perl": ["-e", "-E"], "node": ["-e", "-p", "--eval"],
        "osascript": ["-e"],
    ]

    /// Anything a shell would read as more than one plain path.
    private static let codeCharacters = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: ";|&$`'\"<>()*?[]{}~!#\\="))

    /// Looks through a launcher to the file it is told to start, and through a launcher that starts another
    /// launcher (`env sh -c …`, `arch -arm64 /bin/zsh -c …`). The launcher named is the one that runs the target.
    /// A line of code (`sh -c "…"`) has no single file to judge, so it counts as a script, unless it is
    /// nothing but the path of a program.
    static func resolve(program: String?, arguments: [String]) -> (target: String?, launcher: String?) {
        guard let program else { return (nil, nil) }
        var name = URL(fileURLWithPath: program).lastPathComponent
        guard launchers.contains(name) else { return (program, nil) }
        var rest = arguments.first == program ? Array(arguments.dropFirst()) : arguments
        // A few rounds are enough for any honest job; more only hides what runs.
        for _ in 0..<4 {
            let codeFlags = inlineCodeFlags[name] ?? []
            guard
                let index = rest.firstIndex(where: {
                    codeFlags.contains($0) || $0.hasPrefix("/") || launchers.contains($0)
                })
            else {
                return (nil, name)
            }
            if codeFlags.contains(rest[index]) {
                let code = index + 1 < rest.count ? rest[index + 1] : ""
                let barePath =
                    code.hasPrefix("/") && code.rangeOfCharacter(from: codeCharacters) == nil
                    && !launchers.contains(URL(fileURLWithPath: code).lastPathComponent)
                return (barePath ? code : nil, name)
            }
            let next = URL(fileURLWithPath: rest[index]).lastPathComponent
            guard launchers.contains(next) else { return (rest[index], name) }
            name = next
            rest = Array(rest[(index + 1)...])
        }
        return (nil, name)
    }

    public static func enclosingApp(_ path: String?) -> String? {
        guard let path, let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    /// The name people know: the app the program lives in, else the given fallback.
    static func displayName(target: String?, fallback: String) -> String {
        if let app = target?.components(separatedBy: "/").first(where: { $0.hasSuffix(".app") }) {
            return String(app.dropLast(4))
        }
        return fallback
    }

    private static func developer(_ signature: SignatureInfo?) -> String? {
        if case .developer(_, let name) = signature?.kind { return name }
        return nil
    }
}

/// Switches launchd jobs on and off. User-level jobs need no password; daemons go through `AdminAction`.
public struct AutostartControl: Sendable {
    public let userID: Int
    public let runner: any CommandRunning
    public let admin: any AdminScripting

    public init(
        userID: Int = Int(getuid()), runner: any CommandRunning, admin: any AdminScripting = InProcessAppleScript()
    ) {
        self.userID = userID
        self.runner = runner
        self.admin = admin
    }

    public enum Failure: Error, Equatable {
        case notSwitchableHere
        case invalidLabel
        case refused(String)
    }

    public func setEnabled(_ enabled: Bool, _ item: AutostartItem) async throws {
        guard item.canBeSwitchedHere else { throw Failure.notSwitchableHere }
        guard AdminAction.isSafeLabel(item.label) else { throw Failure.invalidLabel }

        if item.needsAdministrator {
            guard let plist = item.plist?.path else { throw Failure.notSwitchableHere }
            let action: AdminAction =
                enabled ? .enableDaemon(label: item.label, plist: plist) : .disableDaemon(label: item.label)
            try await action.run(with: admin)
            return
        }

        let domain = "gui/\(userID)"
        let service = "\(domain)/\(item.label)"
        let mark = try await runner.run(Tool.launchctl, [enabled ? "enable" : "disable", service])
        guard mark.succeeded else { throw Failure.refused(mark.stderr) }
        // Starting or stopping it now is a courtesy; the mark above is what survives a restart.
        if enabled, let plist = item.plist?.path {
            _ = try? await runner.run(Tool.launchctl, ["bootstrap", domain, plist])
        } else if enabled == false {
            _ = try? await runner.run(Tool.launchctl, ["bootout", service])
        }
    }
}
