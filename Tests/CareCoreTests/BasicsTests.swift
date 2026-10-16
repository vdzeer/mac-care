import Foundation
import Testing

@testable import CareCore

@Suite struct ByteFormatTests {
    @Test(arguments: [
        (Int64(-5), "0 B"), (0, "0 B"), (999, "999 B"), (1000, "1 KB"), (512_000_000, "512 MB"),
        (999_400_000, "999 MB"), (999_960_000, "1.0 GB"), (1_300_000_000, "1.3 GB"),
        (134_700_000_000, "134.7 GB"), (2_000_000_000_000, "2.0 TB"),
    ])
    func formatsLikeFinder(bytes: Int64, expected: String) {
        #expect(ByteFormat.string(bytes) == expected.replacingOccurrences(of: " ", with: "\u{00A0}"))
    }

    @Test func groupsThousands() {
        #expect(ByteFormat.grouped(0) == "0")
        #expect(ByteFormat.grouped(999) == "999")
        #expect(ByteFormat.grouped(48213) == "48,213")
        #expect(ByteFormat.grouped(1_234_567) == "1,234,567")
    }

    @Test func rateNamesTheSecond() {
        #expect(ByteFormat.rate(2_400_000) == "2\u{00A0}MB/s")
    }
}

@Suite struct PathGuardTests {
    let home = try! TempHome()

    func makeGuard() -> PathGuard {
        PathGuard(
            allowedRoots: [home.path("Library/Caches")],
            deniedRoots: [home.path("Library/Caches/Protected")],
            deniedComponents: [".ssh"])
    }

    @Test func allowsWhatLiesInsideARoot() throws {
        try home.file("Library/Caches/app/data.bin")
        #expect(makeGuard().allows(home.path("Library/Caches/app")))
        #expect(makeGuard().allows(home.path("Library/Caches/app/data.bin")))
    }

    @Test func refusesTheRootItself() throws {
        try home.folder("Library/Caches")
        #expect(makeGuard().check(home.path("Library/Caches")) == .failure(.isAllowedRoot))
    }

    @Test func refusesWhatLiesOutside() throws {
        try home.file("Documents/keep.txt")
        #expect(makeGuard().check(home.path("Documents/keep.txt")) == .failure(.outsideAllowedRoots))
        #expect(makeGuard().check(home.path("Library")) == .failure(.outsideAllowedRoots))
        #expect(makeGuard().check(home.path("Library/Caches-other/x")) == .failure(.outsideAllowedRoots))
    }

    @Test func refusesClimbingOutWithDots() throws {
        try home.file("Documents/keep.txt")
        let sneaky = home.path("Library/Caches/app/../../../Documents/keep.txt")
        #expect(makeGuard().check(sneaky) == .failure(.outsideAllowedRoots))
    }

    @Test func refusesDeniedRootsAndNames() throws {
        try home.file("Library/Caches/Protected/secret")
        try home.file("Library/Caches/tool/.ssh/id_key")
        #expect(makeGuard().check(home.path("Library/Caches/Protected")) == .failure(.denied))
        #expect(makeGuard().check(home.path("Library/Caches/Protected/secret")) == .failure(.denied))
        #expect(makeGuard().check(home.path("Library/Caches/tool/.ssh/id_key")) == .failure(.denied))
    }

    @Test func refusesAFolderThatLeadsOutThroughALink() throws {
        try home.file("Documents/keep.txt")
        try home.folder("Library/Caches")
        try FileManager.default.createSymbolicLink(
            at: home.path("Library/Caches/escape"), withDestinationURL: home.path("Documents"))
        // The link itself may go: removing it does not touch Documents.
        #expect(makeGuard().allows(home.path("Library/Caches/escape")))
        // Anything reached through it may not.
        #expect(makeGuard().check(home.path("Library/Caches/escape/keep.txt")) == .failure(.outsideAllowedRoots))
    }

    @Test func refusesRelativePaths() {
        #expect(makeGuard().check(URL(string: "https://example.com/Library/Caches/x")!) == .failure(.notAbsolute))
    }
}

@Suite struct DirectorySizerTests {
    @Test func matchesDu() async throws {
        let home = try TempHome()
        try home.file("tree/a.bin", bytes: 10_000)
        try home.file("tree/deep/b.bin", bytes: 300_000)
        try home.file("tree/deep/deeper/c.bin", bytes: 1)
        try home.folder("tree/empty")

        let usage = DirectorySizer.usage(of: home.path("tree"))
        let du = try await SystemCommandRunner().run("/usr/bin/du", ["-sk", home.path("tree").path])
        let duBytes = Int64(du.stdout.split(separator: "\t")[0])! * 1024
        #expect(abs(usage.bytes - duBytes) < 1024)
        #expect(usage.files == 3)
    }

    @Test func countsAHardLinkOnce() throws {
        let home = try TempHome()
        let original = try home.file("tree/a.bin", bytes: 200_000)
        let single = DirectorySizer.usage(of: home.path("tree")).bytes
        try FileManager.default.linkItem(at: original, to: home.path("tree/b.bin"))
        #expect(DirectorySizer.usage(of: home.path("tree")).bytes == single)
    }

    @Test func doesNotFollowLinksOut() throws {
        let home = try TempHome()
        try home.file("outside/big.bin", bytes: 500_000)
        try home.file("tree/a.bin", bytes: 1000)
        try FileManager.default.createSymbolicLink(
            at: home.path("tree/link"), withDestinationURL: home.path("outside"))
        #expect(DirectorySizer.usage(of: home.path("tree")).bytes < 100_000)
    }
}

@Suite struct CommandRunnerTests {
    @Test func capturesOutputAndStatus() async throws {
        let result = try await SystemCommandRunner().run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        #expect(result.stdout == "out\n")
        #expect(result.stderr == "err\n")
        #expect(result.status == 3)
    }

    @Test func stopsAToolThatRunsTooLong() async {
        await #expect(throws: CommandError.timedOut("/bin/sleep")) {
            try await SystemCommandRunner().run("/bin/sleep", ["5"], timeout: 0.3)
        }
    }

    @Test func refusesAMissingTool() async {
        await #expect(throws: CommandError.notExecutable("/nonexistent/tool")) {
            try await SystemCommandRunner().run("/nonexistent/tool", [])
        }
    }
}
