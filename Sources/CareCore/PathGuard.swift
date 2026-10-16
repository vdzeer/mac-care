import Foundation

/// Decides whether a path may be removed. Every removal in both apps asks it first.
///
/// A path passes only when it lies strictly inside one of the allowed roots, outside every denied
/// root, and its parent folder does not lead somewhere else through a symbolic link.
///
/// A nested allowance is narrower than a root: under its folder, one level down, only the named
/// subfolders pass. It lets a rule clean `<App>/Cache` for every app without ever reaching `<App>` itself.
public struct PathGuard: Sendable {
    public struct Nested: Sendable, Equatable {
        public let root: URL
        /// Paths relative to each child of `root`, such as "Cache" or "Service Worker/CacheStorage".
        public let names: Set<String>

        public init(root: URL, names: Set<String>) {
            self.root = root
            self.names = names
        }
    }

    public enum Refusal: Error, Equatable {
        case notAbsolute
        case outsideAllowedRoots
        case isAllowedRoot
        case denied
    }

    private let allowedRoots: [String]
    private let nested: [(root: String, names: Set<String>)]
    private let deniedRoots: [String]
    private let deniedComponents: Set<String>

    public init(
        allowedRoots: [URL], nested: [Nested] = [], deniedRoots: [URL] = [], deniedComponents: Set<String> = []
    ) {
        self.allowedRoots = allowedRoots.map { Self.resolve($0) }
        self.nested = nested.map { (Self.resolve($0.root), $0.names) }
        self.deniedRoots = deniedRoots.map { Self.resolve($0) }
        self.deniedComponents = deniedComponents
    }

    public func check(_ url: URL) -> Result<URL, Refusal> {
        guard url.isFileURL, url.path.hasPrefix("/") else { return .failure(.notAbsolute) }
        let path = Self.resolveParent(of: url)

        if allowedRoots.contains(path) { return .failure(.isAllowedRoot) }
        let isNested = nested.contains { allowance in
            guard Self.isInside(path, root: allowance.root) else { return false }
            // What remains after the root must be exactly "<one folder>/<an allowed name>".
            let rest = path.dropFirst(allowance.root.count + 1).split(separator: "/", maxSplits: 1)
            return rest.count == 2 && allowance.names.contains(String(rest[1]))
        }
        guard isNested || allowedRoots.contains(where: { Self.isInside(path, root: $0) }) else {
            return .failure(.outsideAllowedRoots)
        }
        if deniedRoots.contains(where: { path == $0 || Self.isInside(path, root: $0) }) {
            return .failure(.denied)
        }
        let components = Set(path.split(separator: "/").map(String.init))
        if components.isDisjoint(with: deniedComponents) == false {
            return .failure(.denied)
        }
        return .success(URL(fileURLWithPath: path))
    }

    public func allows(_ url: URL) -> Bool {
        if case .success = check(url) { return true }
        return false
    }

    private static func isInside(_ path: String, root: String) -> Bool {
        path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private static func resolve(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Resolves links in the folder that holds the item, but not the item itself:
    /// removing a symbolic link removes the link, not what it points to.
    private static func resolveParent(of url: URL) -> String {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath().path
        let name = standardized.lastPathComponent
        return parent == "/" ? "/" + name : parent + "/" + name
    }
}

extension PathGuard {
    /// Places no cleaning rule may reach, whatever its roots say.
    public static func protectedRoots(home: URL) -> [URL] {
        [
            "Documents", "Desktop", "Pictures", "Music", "Movies",
            "Library/Mobile Documents", "Library/CloudStorage", "Library/Mail", "Library/Messages",
            "Library/Keychains", "Library/Photos", "Library/Containers/com.docker.docker",
            "Library/Group Containers/group.com.docker", ".ssh", ".gnupg",
        ].map { home.appendingPathComponent($0) }
    }

    public static let protectedComponents: Set<String> = [".ssh", ".gnupg", "Keychains"]
}
