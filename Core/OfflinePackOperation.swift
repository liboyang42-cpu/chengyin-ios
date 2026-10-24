import Foundation
import CryptoKit

/// Exclusive offline-pack operation. Inventory first: T41 is an unproven full loop.
/// Missing qmod / volume-12 final ops contract is WAITING_SOURCE, not a rewrite.
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
        guard !packID.isEmpty, packID.count <= 64, !operationID.isEmpty, operationID.count <= 64,
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
    public private(set) var failure: OfflinePackFailure?
    public init() {}
    public var snapshot: OfflinePackSnapshot? {
        guard let operationID else { return nil }
        return OfflinePackSnapshot(operationID: operationID, phase: phase,
                                   manifest: manifest, retainedPriorVersion: retainedPrior?.version)
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
}
