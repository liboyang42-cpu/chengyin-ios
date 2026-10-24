import Foundation

/// Exclusive workshop module import / validate / preview / review gate.
/// Inventory first: 30 existing Core/Workshop* files cover consent, owned metadata,
/// purchased library, and W18 private-draft paid install. They are not this machine.
/// Missing qmod original texts / binaries are WAITING_SOURCE, not a rewrite.
public enum WorkshopModuleImportFailure: Error, Equatable {
    case waitingSource(capability: String)
    case invalidManifest
    case answersOrHiddenCoordinatesForbidden
    case unknownModuleFormat
    case jsExecutionForbidden
    case runtimeWriteForbidden
    case notImported
    case notValidated
    case notPreviewed
    case requestMismatch
    public var isWaitingSource: Bool {
        if case .waitingSource = self { return true }
        return false
    }
}

/// Signed inventory of sources this exclusive line has actually read. Absence is typed.
public enum WorkshopModuleSourceInventory {
    public static let qmodOriginal = "qmod.original"
    public static let h5SdkOriginal = "h5.sdk.original"
    public static let h5ContainerOriginal = "h5.container.original"
    public static let modulePackOriginal = "module.pack.original"
    public static let qmodCandidateBinaries = "qmod.workshop.candidate.binaries"
    public static let unpushedIOS = "ios.e2d86c4.unpushed"
    public static let implPack232 = "implPack.232.hashes"
    public static let v12Docx = "questify.v12.docx"
    public static var qmodOriginalPresent: Bool { false }
    public static var h5SdkOriginalPresent: Bool { false }
    public static var h5ContainerOriginalPresent: Bool { false }
    public static var modulePackOriginalPresent: Bool { false }
    public static var qmodCandidateBinariesPresent: Bool { false }
    public static var unpushedIOSPresent: Bool { false }
    public static var implPack232Present: Bool { false }
    public static var v12DocxPresent: Bool { false }
}

public enum WorkshopModuleFormat: String, Equatable, Sendable {
    case metadataManifestV1 = "metadata-manifest-v1"
    case unknownQmod = "qmod"
    case unknownBinary = "binary"
}

public enum WorkshopModuleImportPhase: String, Equatable, Sendable {
    case idle, imported, validated, previewed, reviewPending, waitingSource
}

/// Public catalog facts only. Answers and hidden coordinates must not be shipped.
public struct WorkshopModuleManifest: Equatable, Sendable {
    public let id: String
    public let version: String
    public let contentHash: String
    public let schemaVersion: Int
    public init?(id: String, version: String, contentHash: String, schemaVersion: Int) {
        guard WorkshopModuleImportGate.idOK(id), WorkshopModuleImportGate.versionOK(version),
              WorkshopModuleImportGate.sha256Hex(contentHash), schemaVersion == 1 else { return nil }
        self.id = id; self.version = version; self.contentHash = contentHash; self.schemaVersion = schemaVersion
    }
}

public struct WorkshopModulePreview: Equatable, Sendable {
    public let id: String
    public let version: String
    public let contentHash: String
    public let schemaVersion: Int
    public let metadataOnly: Bool
}

/// Exclusive import from a normal entry. Does not execute JS. Does not write Runtime.
public struct WorkshopModuleImportGate: Equatable {
    public private(set) var phase: WorkshopModuleImportPhase = .idle
    public private(set) var entry: String?
    public private(set) var originalRequestID: String?
    public private(set) var manifest: WorkshopModuleManifest?
    public private(set) var preview: WorkshopModulePreview?
    public private(set) var failure: WorkshopModuleImportFailure?
    public init() {}
    public static func idOK(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func versionOK(_ value: String) -> Bool { idOK(value) }
    public static func requestIDOK(_ value: String) -> Bool { idOK(value) }
    public static func sha256Hex(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    /// Reject answers / hidden coordinates before any preview is retained.
    public static func inspect(_ object: [String: String]) throws {
        let forbidden = ["answer", "answers", "hiddenCoordinate", "hiddenCoordinates",
                         "hiddenLat", "hiddenLng", "hiddenLatitude", "hiddenLongitude", "spoilerAnswer"]
        for key in object.keys where forbidden.contains(key) {
            throw WorkshopModuleImportFailure.answersOrHiddenCoordinatesForbidden
        }
        for value in object.values {
            let lower = value.lowercased()
            if lower.contains("hidden-coord") || lower.contains("\"answer\"") {
                throw WorkshopModuleImportFailure.answersOrHiddenCoordinatesForbidden
            }
        }
    }
    public static func decodeManifest(_ object: [String: String]) throws -> WorkshopModuleManifest {
        try inspect(object)
        guard let id = object["id"], let version = object["version"],
              let contentHash = object["contentHash"],
              let schemaText = object["schemaVersion"], let schemaVersion = Int(schemaText),
              let manifest = WorkshopModuleManifest(
                id: id, version: version, contentHash: contentHash, schemaVersion: schemaVersion)
        else { throw WorkshopModuleImportFailure.invalidManifest }
        return manifest
    }
    public mutating func importFromNormalEntry(entry: String, format: WorkshopModuleFormat,
                                               originalRequestID: String?) throws {
        guard Self.idOK(entry) else { throw fail(.invalidManifest) }
        let requestID: String?
        if let raw = originalRequestID {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            requestID = Self.requestIDOK(trimmed) ? trimmed : nil
        } else {
            requestID = nil
        }
        guard let requestID else { throw fail(.invalidManifest) }
        if let existing = self.originalRequestID {
            guard existing == requestID, self.entry == entry else { throw fail(.requestMismatch) }
            return
        }
        guard format == .metadataManifestV1 else {
            throw fail(.waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
        }
        self.entry = entry
        self.originalRequestID = requestID
        manifest = nil
        preview = nil
        phase = .imported
        failure = nil
    }
    public mutating func validate(_ object: [String: String]) throws {
        guard phase == .imported else { throw fail(.notImported) }
        let decoded = try Self.decodeManifest(object)
        manifest = decoded
        phase = .validated
        failure = nil
    }
    /// Preview is metadata-only. Payload bodies are not retained.
    public mutating func previewMetadataOnly() throws {
        guard phase == .validated, let manifest else { throw fail(.notValidated) }
        preview = WorkshopModulePreview(id: manifest.id, version: manifest.version,
                                        contentHash: manifest.contentHash,
                                        schemaVersion: manifest.schemaVersion, metadataOnly: true)
        phase = .previewed
        failure = nil
    }
    public mutating func markReviewPending() throws {
        guard phase == .previewed, preview?.metadataOnly == true else { throw fail(.notPreviewed) }
        phase = .reviewPending
        failure = nil
    }
    public mutating func executeJavaScript(_ source: String) throws -> Never {
        _ = source
        throw fail(.jsExecutionForbidden)
    }
    public mutating func writeRuntime() throws -> Never {
        throw fail(.runtimeWriteForbidden)
    }
    /// Unknown module format / missing qmod original. Never a fake success path.
    public mutating func consumeQmodOriginal() throws -> Never {
        throw fail(.waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
    }
    public mutating func consumeUnpushedIOSCandidate() throws -> Never {
        throw fail(.waitingSource(capability: WorkshopModuleSourceInventory.unpushedIOS))
    }
    public mutating func consumeImplPack232() throws -> Never {
        throw fail(.waitingSource(capability: WorkshopModuleSourceInventory.implPack232))
    }
    public mutating func consumeV12Docx() throws -> Never {
        throw fail(.waitingSource(capability: WorkshopModuleSourceInventory.v12Docx))
    }
    public mutating func consumeCandidateBinaries() throws -> Never {
        throw fail(.waitingSource(capability: WorkshopModuleSourceInventory.qmodCandidateBinaries))
    }
    @discardableResult
    private mutating func fail(_ error: WorkshopModuleImportFailure) -> WorkshopModuleImportFailure {
        failure = error
        if error.isWaitingSource { phase = .waitingSource }
        return error
    }
}
