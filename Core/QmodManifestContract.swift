import Foundation

/// Local JSON syntax/ambiguity check only. This does not compile a ServerPlan,
/// validate node capabilities, or replace server-side validation of original bytes.
enum QmodJSONInspection {
    enum Failure: String, Error { case malformed, duplicateKey, depthExceeded }

    static func validate(_ data: Data) throws {
        var parser = Parser(bytes: Array(data))
        try parser.value(depth: 0)
        parser.whitespace()
        guard parser.offset == parser.bytes.count else { throw Failure.malformed }
    }

    private struct Parser {
        let bytes: [UInt8]
        var offset = 0

        mutating func whitespace() {
            while offset < bytes.count && [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 }
        }

        mutating func take(_ byte: UInt8) -> Bool {
            guard offset < bytes.count, bytes[offset] == byte else { return false }
            offset += 1
            return true
        }

        mutating func value(depth: Int) throws {
            // Technical recursion stop, not a business limit or schema version.
            guard depth <= 64 else { throw Failure.depthExceeded }
            whitespace()
            guard offset < bytes.count else { throw Failure.malformed }
            switch bytes[offset] {
            case 123: // object
                offset += 1
                whitespace()
                if take(125) { return }
                var keys = Set<String>()
                while true {
                    whitespace()
                    let key = try string()
                    guard keys.insert(key).inserted else { throw Failure.duplicateKey }
                    whitespace()
                    guard take(58) else { throw Failure.malformed }
                    try value(depth: depth + 1)
                    whitespace()
                    if take(125) { return }
                    guard take(44) else { throw Failure.malformed }
                }
            case 91: // array
                offset += 1
                whitespace()
                if take(93) { return }
                while true {
                    try value(depth: depth + 1)
                    whitespace()
                    if take(93) { return }
                    guard take(44) else { throw Failure.malformed }
                }
            case 34: _ = try string()
            case 116: try literal([116, 114, 117, 101])
            case 102: try literal([102, 97, 108, 115, 101])
            case 110: try literal([110, 117, 108, 108])
            case 45, 48...57: try number()
            default: throw Failure.malformed
            }
        }

        mutating func literal(_ expected: [UInt8]) throws {
            for byte in expected {
                guard take(byte) else { throw Failure.malformed }
            }
        }

        mutating func string() throws -> String {
            let start = offset
            guard take(34) else { throw Failure.malformed }
            while offset < bytes.count {
                let byte = bytes[offset]
                offset += 1
                if byte == 34 {
                    // Decode escapes before comparing keys, including surrogate
                    // pairs. Invalid UTF-8/escapes/control characters fail here.
                    guard let decoded = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<offset])) else {
                        throw Failure.malformed
                    }
                    return decoded
                }
                if byte < 32 { throw Failure.malformed }
                if byte == 92 {
                    guard offset < bytes.count else { throw Failure.malformed }
                    offset += 1
                }
            }
            throw Failure.malformed
        }

        mutating func number() throws {
            _ = take(45)
            guard offset < bytes.count else { throw Failure.malformed }
            if !take(48) {
                guard offset < bytes.count, (49...57).contains(bytes[offset]) else { throw Failure.malformed }
                digits()
            }
            if take(46) {
                let start = offset
                digits()
                guard offset > start else { throw Failure.malformed }
            }
            if take(101) || take(69) {
                if !take(43) { _ = take(45) }
                let start = offset
                digits()
                guard offset > start else { throw Failure.malformed }
            }
        }

        mutating func digits() {
            while offset < bytes.count, (48...57).contains(bytes[offset]) { offset += 1 }
        }
    }
}

/// Reform plan v9 part C §3 / U08: the single standard-module (qmod) line. This
/// validates an author-side manifest before any submission exists, reusing the
/// existing publishing, license and runtime systems. H5 packages remain design-only
/// in this round: a `questify.h5` kind is rejected here and there is no H5 container.
///
/// Limits come from a versioned `QmodLimitProfile`. Part C lists suggested values
/// (25 MiB archive, 100 MiB expanded, 20 MiB per file, 2,000 files, 200-char paths,
/// depth 8) as pre-load-test proposals; `reviewProposalV1` carries them only for
/// local authoring hints and tests, labelled as a proposal, never as server truth.
public enum QmodManifestIssue: Error, Equatable {
    case malformed, unsupportedFormat, h5DesignOnly, invalidPackage, invalidVersion, invalidEntrypoint
    case invalidLocale, invalidDependency, unsafePath(String), duplicatePath(String), fileTooLarge(String, actual: Int64, limit: Int64)
    case tooManyFiles(actual: Int, limit: Int), expandedTooLarge(actual: Int64, limit: Int64)
    case authorityField(String), missingFile(String), digestMismatch(String)
}

public struct QmodLimitProfile: Equatable, Sendable {
    public let profileVersion: String
    public let isProposal: Bool
    public let maxArchiveBytes, maxExpandedBytes, maxFileBytes: Int64
    public let maxFiles, maxPathLength, maxDepth: Int
    public init(profileVersion: String, isProposal: Bool, maxArchiveBytes: Int64, maxExpandedBytes: Int64, maxFileBytes: Int64, maxFiles: Int, maxPathLength: Int, maxDepth: Int) {
        self.profileVersion = profileVersion; self.isProposal = isProposal; self.maxArchiveBytes = maxArchiveBytes
        self.maxExpandedBytes = maxExpandedBytes; self.maxFileBytes = maxFileBytes; self.maxFiles = maxFiles
        self.maxPathLength = maxPathLength; self.maxDepth = maxDepth
    }
    /// Part C §3.1 suggested values; proposal only, not a reviewed server profile.
    public static let reviewProposalV1 = QmodLimitProfile(profileVersion: "proposal-v1", isProposal: true, maxArchiveBytes: 25 << 20, maxExpandedBytes: 100 << 20, maxFileBytes: 20 << 20, maxFiles: 2_000, maxPathLength: 200, maxDepth: 8)
}

public struct QmodManifest: Equatable, Sendable {
    public struct Dependency: Equatable, Sendable { public let packageId, version, contentHash: String }
    public struct File: Equatable, Sendable { public let path, sha256: String; public let bytes: Int64 }
    public enum Monetization: String, Sendable { case none = "NONE", merchantFunded = "MERCHANT_FUNDED", iaa = "IAA", digitalSale = "DIGITAL_SALE" }
    public let packageId, packageVersion: String
    public let locales: [String]
    public let minimumHostVersion: String
    public let capabilities: [String]
    public let dependencies: [Dependency]
    public let files: [File]
    /// Declaration only; not a payment permission and not verified rights.
    public let monetization: Monetization
    public let rightsDeclared: Bool

    static let allowedKeys: Set<String> = ["formatVersion", "kind", "packageId", "packageVersion", "entrypoint", "locales", "runtime", "dependencies", "files", "rightsDeclaration", "monetizationDeclaration"]
    /// Authority fields the server alone may decide; their presence rejects the manifest.
    static let authorityKeys: Set<String> = ["reviewed", "approved", "ownerRole", "rewardBudget", "reviewStatus", "publishedAt", "licenseId"]

    private struct Wire: Decodable {
        struct Runtime: Decodable { let minHostVersion: String; let capabilities: [String] }
        struct Dep: Decodable { let packageId, version, contentHash: String }
        struct WireFile: Decodable { let path, sha256: String; let bytes: Int64 }
        struct Rights: Decodable { let declared: Bool }
        let formatVersion: String?
        let kind: String?
        let packageId, packageVersion, entrypoint, monetizationDeclaration: String?
        let locales: [String]?
        let runtime: Runtime?
        let dependencies: [Dep]?
        let files: [WireFile]?
        let rightsDeclaration: Rights?
    }

    /// Parses manifest.json bytes. Unknown keys, authority keys and non-canonical shapes are rejected.
    /// JSONSerialization checks key sets only; typed values use JSONDecoder so booleans never pass as numbers.
    public init(data: Data, limits: QmodLimitProfile) throws {
        guard data.count <= 262_144 else { throw QmodManifestIssue.malformed }
        // Foundation parsers may select different values for repeated keys. Reject
        // the original bytes before either parser discards that information.
        do { try QmodJSONInspection.validate(data) }
        catch { throw QmodManifestIssue.malformed }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QmodManifestIssue.malformed }
        if let key = root.keys.sorted().first(where: { Self.authorityKeys.contains($0) }) { throw QmodManifestIssue.authorityField(key) }
        guard Set(root.keys).isSubset(of: Self.allowedKeys) else { throw QmodManifestIssue.malformed }
        func keys(_ value: Any?) -> Set<String>? { (value as? [String: Any]).map { Set($0.keys) } }
        func keyList(_ value: Any?) -> [Set<String>]? { (value as? [[String: Any]]).map { $0.map { Set($0.keys) } } }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data), let kind = wire.kind else { throw QmodManifestIssue.malformed }
        if kind == "questify.h5" { throw QmodManifestIssue.h5DesignOnly }
        guard kind == "questify.mod", wire.formatVersion == "1.0" else { throw QmodManifestIssue.unsupportedFormat }
        guard let packageId = wire.packageId, packageId.count <= 64, packageId.range(of: "\\A[a-z0-9]+(?:[.-][a-z0-9]+)*\\z", options: .regularExpression) != nil else { throw QmodManifestIssue.invalidPackage }
        guard let version = wire.packageVersion, Self.strictSemver(version) else { throw QmodManifestIssue.invalidVersion }
        guard wire.entrypoint == "content.json" else { throw QmodManifestIssue.invalidEntrypoint }
        guard let locales = wire.locales, !locales.isEmpty, Set(locales).count == locales.count, Set(locales).isSubset(of: ["zh-Hans", "en"]) else { throw QmodManifestIssue.invalidLocale }
        guard let runtime = wire.runtime, keys(root["runtime"]) == ["minHostVersion", "capabilities"], Self.strictSemver(runtime.minHostVersion),
              runtime.capabilities.count <= 32, Set(runtime.capabilities).count == runtime.capabilities.count,
              runtime.capabilities.allSatisfy({ $0.range(of: "\\A[a-z][a-z0-9_.]{0,63}\\z", options: .regularExpression) != nil }) else { throw QmodManifestIssue.malformed }
        var dependencies: [Dependency] = []
        if root["dependencies"] != nil {
            guard let raw = wire.dependencies, let rawKeys = keyList(root["dependencies"]), rawKeys.allSatisfy({ $0 == ["packageId", "version", "contentHash"] }) else { throw QmodManifestIssue.invalidDependency }
            for dep in raw {
                guard dep.packageId != packageId, dep.packageId.count <= 64, dep.packageId.range(of: "\\A[a-z0-9]+(?:[.-][a-z0-9]+)*\\z", options: .regularExpression) != nil,
                      Self.strictSemver(dep.version), ReformWire.sha256(dep.contentHash),
                      !dependencies.contains(where: { $0.packageId == dep.packageId }) else { throw QmodManifestIssue.invalidDependency }
                dependencies.append(.init(packageId: dep.packageId, version: dep.version, contentHash: dep.contentHash))
            }
        }
        guard let rawFiles = wire.files, !rawFiles.isEmpty, let fileKeys = keyList(root["files"]), fileKeys.allSatisfy({ $0 == ["path", "sha256", "bytes"] }) else { throw QmodManifestIssue.malformed }
        guard rawFiles.count <= limits.maxFiles else { throw QmodManifestIssue.tooManyFiles(actual: rawFiles.count, limit: limits.maxFiles) }
        var files: [File] = [], folded = Set<String>(), total: Int64 = 0
        for file in rawFiles {
            guard ReformWire.sha256(file.sha256), file.bytes >= 0 else { throw QmodManifestIssue.malformed }
            try Self.checkPath(file.path, limits: limits)
            guard folded.insert(file.path.lowercased()).inserted else { throw QmodManifestIssue.duplicatePath(file.path) }
            guard file.bytes <= limits.maxFileBytes else { throw QmodManifestIssue.fileTooLarge(file.path, actual: file.bytes, limit: limits.maxFileBytes) }
            total += file.bytes
            files.append(.init(path: file.path, sha256: file.sha256, bytes: file.bytes))
        }
        guard total <= limits.maxExpandedBytes else { throw QmodManifestIssue.expandedTooLarge(actual: total, limit: limits.maxExpandedBytes) }
        guard files.contains(where: { $0.path == "content.json" }) else { throw QmodManifestIssue.missingFile("content.json") }
        for locale in locales where !files.contains(where: { $0.path == locale + ".json" }) { throw QmodManifestIssue.missingFile(locale + ".json") }
        guard let rights = wire.rightsDeclaration, keys(root["rightsDeclaration"]) == ["declared"],
              let monetizationRaw = wire.monetizationDeclaration, let monetization = Monetization(rawValue: monetizationRaw) else { throw QmodManifestIssue.malformed }
        self.packageId = packageId; packageVersion = version; self.locales = locales; minimumHostVersion = runtime.minHostVersion
        capabilities = runtime.capabilities; self.dependencies = dependencies; self.files = files
        self.monetization = monetization; rightsDeclared = rights.declared
    }

    /// Checks one archive entry against the manifest. Files outside the manifest are rejected by callers.
    public func verify(path: String, sha256: String, bytes: Int64) throws {
        guard let file = files.first(where: { $0.path == path }) else { throw QmodManifestIssue.unsafePath(path) }
        guard file.sha256 == sha256, file.bytes == bytes else { throw QmodManifestIssue.digestMismatch(path) }
    }

    static func strictSemver(_ value: String) -> Bool {
        value.range(of: "\\A(?:0|[1-9][0-9]{0,5})\\.(?:0|[1-9][0-9]{0,5})\\.(?:0|[1-9][0-9]{0,5})\\z", options: .regularExpression) != nil
    }
    /// Relative ASCII only: no absolute paths, `..`, backslashes, empty segments,
    /// hidden files, or executable/markup types rejected in the first version.
    static func checkPath(_ path: String, limits: QmodLimitProfile) throws {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        let lowered = path.lowercased()
        guard !path.isEmpty, path.count <= limits.maxPathLength, path.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 0x20 && $0.value < 0x7F }),
              !path.hasPrefix("/"), !path.contains("\\"), segments.count <= limits.maxDepth,
              segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }),
              !["svg", "html", "htm", "js", "mjs", "lua", "py", "sh", "zip"].contains(where: { lowered.hasSuffix("." + $0) }) else { throw QmodManifestIssue.unsafePath(path) }
    }
}
