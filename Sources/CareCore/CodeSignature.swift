import Foundation
import Security

/// Who signed a program, as far as macOS can tell.
public struct SignatureInfo: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Part of macOS or made by Apple.
        case apple
        /// Signed with a certificate Apple issued to a developer.
        case developer(team: String, name: String)
        /// Signed without a certificate: anyone can do this.
        case adHoc
        case unsigned
        /// Signed, but the file no longer matches its signature.
        case broken
    }

    public let kind: Kind
    public let identifier: String?
    /// Whether Apple notarized it (or the Mac App Store signed it). Asked only by the full check, and only about
    /// developer-signed code; else nil.
    public let notarized: Bool?

    public init(kind: Kind, identifier: String? = nil, notarized: Bool? = nil) {
        self.kind = kind
        self.identifier = identifier
        self.notarized = notarized
    }

    /// True when a real, intact certificate stands behind the program.
    public var isTrusted: Bool {
        switch kind {
        case .apple, .developer: true
        case .adHoc, .unsigned, .broken: false
        }
    }
}

public enum CodeSignature {
    /// Inspects a program or an app bundle.
    ///
    /// The quick check (for long lists) reads the signature but does not hash the files. The `thorough` one is what
    /// `codesign --verify --deep --strict` does: every architecture, the executable, every resource and every
    /// nested program, so a patched file shows as broken. It also asks whether Apple notarized developer-signed
    /// code, as `codesign -R="notarized"` does. Thorough results for a single file are kept until it changes.
    public static func inspect(_ url: URL, thorough: Bool = false) -> SignatureInfo {
        guard thorough else { return examine(url, thorough: false) }
        let stamp = FileStamp(url)
        if let stamp, let known = cache.value(for: url.path, stamp: stamp) { return known }
        let info = examine(url, thorough: true)
        if let stamp { cache.store(info, for: url.path, stamp: stamp) }
        return info
    }

    /// The flags of the full check: `codesign --verify --deep --strict`.
    static let fullCheck = SecCSFlags(
        rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
    /// The flags of the quick check: the signature itself, without hashing the files.
    static let quickCheck = SecCSFlags(rawValue: kSecCSDoNotValidateExecutable | kSecCSDoNotValidateResources)

    private static func examine(_ url: URL, thorough: Bool) -> SignatureInfo {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return SignatureInfo(kind: .unsigned)
        }

        var raw: CFDictionary?
        let wanted = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, wanted, &raw) == errSecSuccess,
            let info = raw as? [String: Any], info[kSecCodeInfoIdentifier as String] != nil
        else { return SignatureInfo(kind: .unsigned) }
        let identifier = info[kSecCodeInfoIdentifier as String] as? String

        guard SecStaticCodeCheckValidity(code, thorough ? fullCheck : quickCheck, nil) == errSecSuccess else {
            return SignatureInfo(kind: .broken, identifier: identifier)
        }

        let flags = (info[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        if flags & 0x2 != 0 { return SignatureInfo(kind: .adHoc, identifier: identifier) }

        if satisfies(code, "anchor apple") { return SignatureInfo(kind: .apple, identifier: identifier) }

        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
        guard satisfies(code, "anchor apple generic"), let leaf = certificates?.first else {
            return SignatureInfo(kind: .adHoc, identifier: identifier)
        }
        let summary = (SecCertificateCopySubjectSummary(leaf) as String?) ?? ""
        return SignatureInfo(
            kind: .developer(team: team ?? "", name: developerName(summary)), identifier: identifier,
            notarized: thorough ? satisfies(code, notarizedOrAppStore) : nil)
    }

    /// Notarized by Apple, or signed by the Mac App Store, whose apps Apple reviews instead of notarizing.
    static let notarizedOrAppStore =
        "notarized or (anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9] exists)"

    /// "Developer ID Application: Docker Inc (9BNSXJN65R)" becomes "Docker Inc".
    static func developerName(_ summary: String) -> String {
        var name = summary
        if let colon = name.range(of: ": ") { name = String(name[colon.upperBound...]) }
        if name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) {
            name = String(name[..<open.lowerBound])
        }
        return name
    }

    /// Checks a requirement against a signature already validated above, without hashing the files again.
    private static func satisfies(_ code: SecStaticCode, _ text: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, quickCheck, requirement) == errSecSuccess
    }

    private static let cache = SignatureCache()
}

/// What tells a file apart from its earlier self: where it lives on disk, its size and when it last changed.
/// Only for a single file: a bundle folder does not change when a file deep inside it does.
struct FileStamp: Hashable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let changed: Int
    let changedNanos: Int

    init?(_ url: URL) {
        var info = stat()
        guard stat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        device = info.st_dev
        inode = info.st_ino
        size = info.st_size
        changed = info.st_ctimespec.tv_sec
        changedNanos = info.st_ctimespec.tv_nsec
    }
}

/// Thorough results by path, valid while the file's stamp stays the same.
private final class SignatureCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: (stamp: FileStamp, info: SignatureInfo)] = [:]

    func value(for path: String, stamp: FileStamp) -> SignatureInfo? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path], entry.stamp == stamp else { return nil }
        return entry.info
    }

    func store(_ info: SignatureInfo, for path: String, stamp: FileStamp) {
        lock.lock()
        defer { lock.unlock() }
        if entries.count > 2_000 { entries.removeAll() }
        entries[path] = (stamp, info)
    }
}
