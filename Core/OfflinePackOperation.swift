import Foundation
import CryptoKit

/// Exclusive offline-pack operation. Inventory first: T41 is an unproven full loop.
/// Missing qmod / volume-12 final ops contract is WAITING_SOURCE, not a rewrite.
/// Qmod install and in-memory keep-old are not this download. A missing published
/// artifact blocks the bytes only.
public enum OfflinePackFailure: Error, Equatable {
    case waitingSource(capability: String)
    case answersOrHiddenCoordinatesForbidden
    case corrupt
    case fullDisk
    case expired
    case operationMismatch
    case notPaused
    case notDownloading
    case notReady
    case alreadyDeleted
    case invalidManifest
    case pauseOpsReserved
    public var isWaitingSource: Bool {
        if case .waitingSource = self { return true }
        return false
    }
}

/// Signed inventory of sources this exclusive line has actually read. Absence is typed.
public enum OfflinePackSourceInventory {
    public static let qmodFinalOpsContract = "qmod.finalOpsContract"
    public static let vol12ResumeWriter = "vol12.offlinePackResumeWriter"
    public static let t41ScoringWriter = "t41.scoringWriter"
    public static let t41FullLoop = "t41.fullLoopUnproven"
    /// Original play pause/resume writer. Twenty pause ops stay with PlayExperienceCoordinator.
    public static let originalPauseOpsOwner = "PlayExperienceCoordinator.paused"
    public static let payloadConsumer = "offlinePack.payloadConsumer"
    public static var qmodFinalOpsContractPresent: Bool { false }
    public static var vol12ResumeWriterPresent: Bool { false }
    public static var t41ScoringWriterPresent: Bool { false }
    public static var t41FullLoopProven: Bool { false }
}

public enum OfflinePackPhase: String, Equatable, Sendable {
    case idle, downloading, paused, ready, updating, corrupt, fullDisk, expired, deleted, waitingSource
}

/// Public catalog facts only. Answers and hidden coordinates must not be shipped.
public struct OfflinePackManifest: Equatable, Sendable {
    public let packID: String
    public let operationID: String
    public let version: String
    public let byteSize: Int
    public let checksum: String
    public let publicPlaceIDs: [Int]
    public let expiresAt: Date
    public init?(packID: String, operationID: String, version: String, byteSize: Int,
                 checksum: String, publicPlaceIDs: [Int], expiresAt: Date) {
        guard !OfflinePackOperation.isBlank(packID), packID.count <= 64,
              !OfflinePackOperation.isBlank(operationID), operationID.count <= 64,
              OfflinePackOperation.versionOK(version), byteSize > 0, byteSize <= 500_000_000,
              checksum.count == 64, checksum.allSatisfy(\.isHexDigit),
              publicPlaceIDs.count <= 256, publicPlaceIDs.allSatisfy({ $0 > 0 }),
              Set(publicPlaceIDs).count == publicPlaceIDs.count,
              expiresAt.timeIntervalSince1970.isFinite else { return nil }
        self.packID = packID; self.operationID = operationID; self.version = version
        self.byteSize = byteSize; self.checksum = checksum
        self.publicPlaceIDs = publicPlaceIDs; self.expiresAt = expiresAt
    }
}

public struct OfflinePackSnapshot: Equatable, Sendable {
    public let operationID: String
    public let phase: OfflinePackPhase
    public let manifest: OfflinePackManifest?
    public let retainedPriorVersion: String?
}

/// Exclusive download / pause / corrupt / full-disk / update / keep-old / expire / delete /
/// resume-same-operation-id machine. Does not own the twenty original play pause ops.
public struct OfflinePackOperation: Equatable {
    public private(set) var phase: OfflinePackPhase = .idle
    public private(set) var operationID: String?
    public private(set) var manifest: OfflinePackManifest?
    public private(set) var retainedPrior: OfflinePackManifest?
    /// True only after a verified payload was kept as the prior file. A version string is not that file.
    private var priorFileAccepted = false
    public private(set) var failure: OfflinePackFailure?
    public init() {}
    public var snapshot: OfflinePackSnapshot? {
        guard let operationID else { return nil }
        return OfflinePackSnapshot(operationID: operationID, phase: phase,
                                   manifest: manifest, retainedPriorVersion: retainedPrior?.version)
    }
    public static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public static func versionOK(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Reject answers / hidden coordinates before any bytes are retained.
    public static func inspect(_ object: [String: String]) throws -> Void {
        let forbidden = ["answer", "answers", "hiddenCoordinate", "hiddenCoordinates",
                         "hiddenLat", "hiddenLng", "hiddenLatitude", "hiddenLongitude", "spoilerAnswer"]
        for key in object.keys where forbidden.contains(key) {
            throw OfflinePackFailure.answersOrHiddenCoordinatesForbidden
        }
        for value in object.values {
            let lower = value.lowercased()
            if lower.contains("hidden-coord") || lower.contains("\"answer\"") {
                throw OfflinePackFailure.answersOrHiddenCoordinatesForbidden
            }
        }
    }
    public static func decodeManifest(_ object: [String: String], publicPlaceIDs: [Int],
                                      expiresAt: Date) throws -> OfflinePackManifest {
        try inspect(object)
        guard let packID = object["packID"], let operationID = object["operationID"],
              let version = object["version"], let checksum = object["checksum"],
              let sizeText = object["byteSize"], let byteSize = Int(sizeText),
              let manifest = OfflinePackManifest(
                packID: packID, operationID: operationID, version: version, byteSize: byteSize,
                checksum: checksum, publicPlaceIDs: publicPlaceIDs, expiresAt: expiresAt)
        else { throw OfflinePackFailure.invalidManifest }
        return manifest
    }
    public mutating func startDownload(_ manifest: OfflinePackManifest, at now: Date = Date()) throws {
        try Self.inspect(["packID": manifest.packID, "operationID": manifest.operationID,
                          "version": manifest.version, "checksum": manifest.checksum,
                          "byteSize": String(manifest.byteSize)])
        guard phase == .idle || phase == .deleted || phase == .expired else {
            throw fail(.invalidManifest)
        }
        guard manifest.expiresAt > now else { throw fail(.expired) }
        operationID = manifest.operationID
        self.manifest = manifest
        retainedPrior = nil
        priorFileAccepted = false
        phase = .downloading
        failure = nil
    }
    public mutating func pause() throws {
        guard phase == .downloading else { throw fail(.notDownloading) }
        phase = .paused
        failure = nil
    }
    /// Resume continues the same operation id. A different id is an operation mismatch.
    public mutating func resume(operationID: String) throws {
        guard phase == .paused else { throw fail(.notPaused) }
        guard self.operationID == operationID, !operationID.isEmpty else { throw fail(.operationMismatch) }
        phase = .downloading
        failure = nil
    }
    public mutating func finishDownload() throws {
        guard phase == .downloading else { throw fail(.notDownloading) }
        throw OfflinePackFailure.waitingSource(capability: OfflinePackSourceInventory.payloadConsumer)
    }
    public mutating func finishDownload(payload: Data) throws {
        guard phase == .downloading else { throw fail(.notDownloading) }
        try verifyPayload(payload)
        phase = .ready
        failure = nil
    }
    public mutating func recordCorrupt() throws {
        guard phase == .downloading || phase == .updating || phase == .ready else { throw fail(.invalidManifest) }
        if let prior = retainedPrior, phase == .updating {
            restorePrior(prior)
            return
        }
        phase = .corrupt
        failure = .corrupt
        throw OfflinePackFailure.corrupt
    }
    public mutating func recordFullDisk() throws {
        guard phase == .downloading || phase == .updating else { throw fail(.notDownloading) }
        if let prior = retainedPrior, phase == .updating {
            restorePrior(prior)
            return
        }
        phase = .fullDisk
        failure = .fullDisk
        throw OfflinePackFailure.fullDisk
    }
    public mutating func applyUpdate(_ next: OfflinePackManifest, keepOld: Bool, at now: Date = Date()) throws {
        guard phase == .ready, let current = manifest else { throw fail(.notReady) }
        guard next.operationID == current.operationID else { throw fail(.operationMismatch) }
        guard next.packID == current.packID else { throw fail(.operationMismatch) }
        guard next.expiresAt > now else { throw fail(.expired) }
        try Self.inspect(["packID": next.packID, "operationID": next.operationID,
                          "version": next.version, "checksum": next.checksum])
        retainedPrior = keepOld ? current : nil
        priorFileAccepted = keepOld
        manifest = next
        phase = .updating
        failure = nil
    }
    public mutating func finishUpdate() throws {
        guard phase == .updating else { throw fail(.notDownloading) }
        throw OfflinePackFailure.waitingSource(capability: OfflinePackSourceInventory.payloadConsumer)
    }
    public mutating func finishUpdate(payload: Data) throws {
        guard phase == .updating else { throw fail(.notDownloading) }
        try verifyPayload(payload)
        phase = .ready
        failure = nil
    }
    public mutating func expire(at now: Date = Date()) throws {
        guard let manifest else { throw fail(.invalidManifest) }
        guard now >= manifest.expiresAt else { throw fail(.invalidManifest) }
        phase = .expired
        failure = .expired
    }
    public mutating func delete() throws {
        guard phase != .deleted else { throw fail(.alreadyDeleted) }
        guard phase != .idle else { throw fail(.invalidManifest) }
        phase = .deleted
        retainedPrior = nil
        priorFileAccepted = false
        failure = nil
    }
    /// Original scoring / resume writer is not in this public tree.
    public mutating func commitOriginalWriter() throws -> Never {
        throw fail(.waitingSource(capability: OfflinePackSourceInventory.qmodFinalOpsContract))
    }
    public mutating func scoreT41() throws -> Never {
        throw fail(.waitingSource(capability: OfflinePackSourceInventory.t41ScoringWriter))
    }
    public mutating func proveT41FullLoop() throws -> Never {
        throw fail(.waitingSource(capability: OfflinePackSourceInventory.t41FullLoop))
    }
    public mutating func resumeViaVol12Writer() throws -> Never {
        throw fail(.waitingSource(capability: OfflinePackSourceInventory.vol12ResumeWriter))
    }
    /// Must not dispatch through the twenty original play pause ops.
    public mutating func hijackOriginalPauseOps() throws -> Never {
        throw fail(.pauseOpsReserved)
    }
    private mutating func verifyPayload(_ payload: Data) throws {
        guard let manifest, payload.count == manifest.byteSize,
              Self.sha256Hex(payload).caseInsensitiveCompare(manifest.checksum) == .orderedSame else {
            if let prior = retainedPrior, phase == .updating {
                restorePrior(prior)
                throw OfflinePackFailure.corrupt
            }
            phase = .corrupt
            failure = .corrupt
            throw OfflinePackFailure.corrupt
        }
    }
    static func sha256Hex(_ payload: Data) -> String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }
    private mutating func restorePrior(_ prior: OfflinePackManifest) {
        manifest = prior
        phase = .ready
        failure = nil
    }
    @discardableResult
    private mutating func fail(_ error: OfflinePackFailure) -> OfflinePackFailure {
        failure = error
        if error.isWaitingSource { phase = .waitingSource }
        return error
    }

    public func operationRecord() -> OfflinePackOperationRecord? {
        guard let operationID, let manifest else { return nil }
        return OfflinePackOperationRecord(operationID: operationID, phase: phase.rawValue,
            packID: manifest.packID, version: manifest.version, byteSize: manifest.byteSize,
            checksum: manifest.checksum, publicPlaceIDs: manifest.publicPlaceIDs,
            expiresAt: manifest.expiresAt.timeIntervalSince1970,
            retainedPackID: retainedPrior?.packID, retainedVersion: retainedPrior?.version,
            retainedByteSize: retainedPrior?.byteSize, retainedChecksum: retainedPrior?.checksum,
            retainedVerifiedChecksum: priorFileAccepted ? retainedPrior?.checksum : nil,
            retainedPlaceIDs: retainedPrior?.publicPlaceIDs,
            retainedExpiresAt: retainedPrior?.expiresAt.timeIntervalSince1970,
            retainedFileAccepted: priorFileAccepted)
    }

    public static func restored(_ record: OfflinePackOperationRecord) -> OfflinePackOperation? {
        guard let phase = OfflinePackPhase(rawValue: record.phase),
              let manifest = OfflinePackManifest(packID: record.packID, operationID: record.operationID,
                version: record.version, byteSize: record.byteSize, checksum: record.checksum,
                publicPlaceIDs: record.publicPlaceIDs, expiresAt: Date(timeIntervalSince1970: record.expiresAt)),
              manifest.operationID == record.operationID else { return nil }
        var operation = OfflinePackOperation()
        operation.operationID = record.operationID
        operation.phase = phase
        operation.manifest = manifest
        if record.retainedFileAccepted {
            guard let priorID = record.retainedPackID, priorID == manifest.packID,
                  let priorVersion = record.retainedVersion,
                  let priorSize = record.retainedByteSize, let priorChecksum = record.retainedChecksum,
                  let verified = record.retainedVerifiedChecksum,
                  priorChecksum.caseInsensitiveCompare(verified) == .orderedSame,
                  let places = record.retainedPlaceIDs, let expires = record.retainedExpiresAt,
                  let prior = OfflinePackManifest(packID: priorID, operationID: record.operationID,
                    version: priorVersion, byteSize: priorSize, checksum: priorChecksum,
                    publicPlaceIDs: places, expiresAt: Date(timeIntervalSince1970: expires)) else { return nil }
            operation.retainedPrior = prior
            operation.priorFileAccepted = true
        }
        return operation
    }

    public mutating func restoreSameOperation(_ record: OfflinePackOperationRecord) throws {
        if let operationID, let manifest {
            guard operationID == record.operationID, manifest.packID == record.packID,
                  manifest.version == record.version,
                  manifest.checksum.caseInsensitiveCompare(record.checksum) == .orderedSame else {
                throw fail(.operationMismatch)
            }
        }
        guard let restored = Self.restored(record), restored.operationID == record.operationID,
              restored.manifest?.packID == record.packID,
              restored.manifest?.version == record.version else {
            throw fail(.invalidManifest)
        }
        self = restored
    }
}

/// Fields the published artifact source must bind. No locator is invented here.
public struct OfflinePackPublishedContract: Equatable, Sendable {
    public static let requiredFields = ["packID", "version", "checksum", "approvedLocator"]
    public let packID: String
    public let version: String
    public let checksum: String
    public let locator: String
    public init?(packID: String, version: String, checksum: String, locator: String) {
        guard !OfflinePackOperation.isBlank(packID), OfflinePackOperation.versionOK(version),
              checksum.count == 64, checksum.allSatisfy(\.isHexDigit),
              !OfflinePackOperation.isBlank(locator) else { return nil }
        self.packID = packID
        self.version = version
        self.checksum = checksum
        self.locator = locator
    }
}

public protocol OfflinePackArtifactSource {
    func publishedContract(operationID: String) -> OfflinePackPublishedContract?
    func bytes(matching contract: OfflinePackPublishedContract) -> Data?
}

public enum OfflinePackPayloadConsumer {
    public static let missingArtifact = "offlinePack.publishedArtifact"
    public static func accept(_ operation: inout OfflinePackOperation, from source: any OfflinePackArtifactSource) throws {
        guard let operationID = operation.operationID, let manifest = operation.manifest else {
            throw OfflinePackFailure.waitingSource(capability: OfflinePackSourceInventory.payloadConsumer)
        }
        guard operation.phase == .downloading || operation.phase == .updating else {
            throw OfflinePackFailure.notDownloading
        }
        let capturedPhase = operation.phase
        guard let contract = source.publishedContract(operationID: operationID),
              contract.packID == manifest.packID, contract.version == manifest.version,
              contract.checksum.caseInsensitiveCompare(manifest.checksum) == .orderedSame else {
            throw OfflinePackFailure.waitingSource(capability: missingArtifact)
        }
        guard let payload = source.bytes(matching: contract) else {
            throw OfflinePackFailure.waitingSource(capability: OfflinePackSourceInventory.payloadConsumer)
        }
        guard operation.phase == capturedPhase, operation.operationID == operationID,
              operation.manifest?.packID == manifest.packID,
              operation.manifest?.version == manifest.version,
              operation.manifest?.checksum.caseInsensitiveCompare(manifest.checksum) == .orderedSame else {
            throw OfflinePackFailure.operationMismatch
        }
        if capturedPhase == .downloading {
            try operation.finishDownload(payload: payload)
        } else {
            try operation.finishUpdate(payload: payload)
        }
    }
}

public struct OfflinePackOperationRecord: Codable, Equatable, Sendable {
    public let operationID: String
    public let phase: String
    public let packID: String
    public let version: String
    public let byteSize: Int
    public let checksum: String
    public let publicPlaceIDs: [Int]
    public let expiresAt: TimeInterval
    public let retainedPackID: String?
    public let retainedVersion: String?
    public let retainedByteSize: Int?
    public let retainedChecksum: String?
    public let retainedVerifiedChecksum: String?
    public let retainedPlaceIDs: [Int]?
    public let retainedExpiresAt: TimeInterval?
    public let retainedFileAccepted: Bool
}
