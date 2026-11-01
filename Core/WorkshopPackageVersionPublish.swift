import Foundation

/// Exclusive version freeze. Does not own the public author-publish registry.
/// Republish of the same originalRequestID is idempotent. Mutating a frozen
/// hash without a new version fails.
public enum WorkshopPackagePublishFailure: Error, Equatable {
    case waitingSource(capability: String)
    case frozenHashMutation
    case notReviewed
    case invalidFreeze
    case publicRegistryReserved
    case requestMismatch
    public var isWaitingSource: Bool {
        if case .waitingSource = self { return true }
        return false
    }
}

public enum WorkshopPackagePublishPhase: String, Equatable, Sendable {
    case idle, frozen, waitingSource
}

public struct WorkshopFrozenVersion: Equatable, Sendable {
    public let contentHash: String
    public let termsHash: String
    public let versionLabel: String
    public let originalRequestID: String
}

/// Exact contentHash + termsHash + versionLabel freeze. Unwired from the shared session host.
public struct WorkshopPackageVersionPublish: Equatable {
    public private(set) var phase: WorkshopPackagePublishPhase = .idle
    public private(set) var frozen: WorkshopFrozenVersion?
    public private(set) var publishCount: Int = 0
    public private(set) var failure: WorkshopPackagePublishFailure?
    public init() {}
    public mutating func freeze(contentHash: String, termsHash: String, versionLabel: String,
                                originalRequestID: String, reviewed: Bool) throws {
        guard reviewed else { throw fail(.notReviewed) }
        guard WorkshopModuleImportGate.sha256Hex(contentHash),
              WorkshopModuleImportGate.sha256Hex(termsHash),
              WorkshopModuleImportGate.versionOK(versionLabel),
              WorkshopModuleImportGate.requestIDOK(originalRequestID) else {
            throw fail(.invalidFreeze)
        }
        let next = WorkshopFrozenVersion(contentHash: contentHash, termsHash: termsHash,
                                         versionLabel: versionLabel, originalRequestID: originalRequestID)
        if let frozen {
            try republishMatching(next, existing: frozen)
            return
        }
        self.frozen = next
        publishCount = 1
        phase = .frozen
        failure = nil
    }
    /// Republish same originalRequestID is idempotent.
    public mutating func republish(originalRequestID: String) throws {
        guard let frozen else { throw fail(.invalidFreeze) }
        guard frozen.originalRequestID == originalRequestID else { throw fail(.requestMismatch) }
        publishCount += 0
        phase = .frozen
        failure = nil
    }
    /// Mutating frozen hash without a new version fails. A new version is a new machine.
    public mutating func mutateFrozenHash(_ contentHash: String, termsHash: String,
                                          versionLabel: String, originalRequestID: String) throws {
        guard let frozen else { throw fail(.invalidFreeze) }
        if frozen.originalRequestID == originalRequestID,
           frozen.contentHash == contentHash,
           frozen.termsHash == termsHash,
           frozen.versionLabel == versionLabel {
            try republish(originalRequestID: originalRequestID)
            return
        }
        throw fail(.frozenHashMutation)
    }
    /// Public author-publish / install registry stays with dot.
    public mutating func registerPublicAuthorPublish() throws -> Never {
        throw fail(.publicRegistryReserved)
    }
    public mutating func consumeModulePackOriginal() throws -> Never {
        throw fail(.waitingSource(capability: WorkshopModuleSourceInventory.modulePackOriginal))
    }
    private mutating func republishMatching(_ next: WorkshopFrozenVersion,
                                            existing: WorkshopFrozenVersion) throws {
        guard next.originalRequestID == existing.originalRequestID,
              next.contentHash == existing.contentHash,
              next.termsHash == existing.termsHash,
              next.versionLabel == existing.versionLabel else {
            throw fail(.frozenHashMutation)
        }
        phase = .frozen
        failure = nil
    }
    @discardableResult
    private mutating func fail(_ error: WorkshopPackagePublishFailure) -> WorkshopPackagePublishFailure {
        failure = error
        if error.isWaitingSource { phase = .waitingSource }
        return error
    }
}
