import Foundation

/// Exclusive install / upgrade / rollback machine.
/// Existing WorkshopPaidInstall* stays the W18_PRIVATE_COMPONENT_ONLY private-draft
/// grant (executable=false). This machine is exclusive and unwired. Digital-goods
/// IAP remains OpenDecision, not launched. Do not invent pricing.
public enum WorkshopInstallFailure: Error, Equatable {
    case waitingSource(capability: String)
    case digitalGoodsOpenDecision
    case invalidGrant
    case notHeld
    case notInstalled
    case notUpgrading
    case noRetainedPrior
    case requestMismatch
    public var isWaitingSource: Bool {
        if case .waitingSource = self { return true }
        return false
    }
}

public enum WorkshopInstallPhase: String, Equatable, Sendable {
    case idle, held, installed, upgrading, rolledBack, waitingSource
}

public struct WorkshopInstallSnapshot: Equatable, Sendable {
    public let originalRequestID: String
    public let phase: WorkshopInstallPhase
    public let installedVersion: String?
    public let retainedPriorVersion: String?
    public let installCount: Int
}

/// Phases idle → held (authorized, not IAP) → installed(version) → upgrading →
/// rolledBack to retained prior version. Same originalRequestID cannot double-install.
public struct WorkshopInstallUpgradeRollback: Equatable {
    public private(set) var phase: WorkshopInstallPhase = .idle
    public private(set) var originalRequestID: String?
    public private(set) var installedVersion: String?
    public private(set) var retainedPriorVersion: String?
    public private(set) var upgradingTo: String?
    public private(set) var installCount: Int = 0
    public private(set) var failure: WorkshopInstallFailure?
    public init() {}
    public var snapshot: WorkshopInstallSnapshot? {
        guard let originalRequestID else { return nil }
        return WorkshopInstallSnapshot(originalRequestID: originalRequestID, phase: phase,
                                       installedVersion: installedVersion,
                                       retainedPriorVersion: retainedPriorVersion,
                                       installCount: installCount)
    }
    /// Authorized hold is the implemented grant. Not an IAP purchase.
    public mutating func authorizedHold(originalRequestID: String, versionLabel: String) throws {
        guard phase == .idle, WorkshopModuleImportGate.requestIDOK(originalRequestID),
              WorkshopModuleImportGate.versionOK(versionLabel) else { throw fail(.invalidGrant) }
        self.originalRequestID = originalRequestID
        installedVersion = versionLabel
        retainedPriorVersion = nil
        upgradingTo = nil
        phase = .held
        failure = nil
    }
    public mutating func install(originalRequestID: String) throws {
        guard WorkshopModuleImportGate.requestIDOK(originalRequestID) else { throw fail(.invalidGrant) }
        if let existing = self.originalRequestID, existing == originalRequestID, installCount >= 1 {
            return
        }
        guard phase == .held, self.originalRequestID == originalRequestID else { throw fail(.notHeld) }
        installCount = 1
        phase = .installed
        failure = nil
    }
    public mutating func beginUpgrade(to nextVersion: String) throws {
        guard phase == .installed, let current = installedVersion,
              WorkshopModuleImportGate.versionOK(nextVersion), nextVersion != current else {
            throw fail(.notInstalled)
        }
        retainedPriorVersion = current
        upgradingTo = nextVersion
        phase = .upgrading
        failure = nil
    }
    public mutating func finishUpgrade() throws {
        guard phase == .upgrading, let next = upgradingTo else { throw fail(.notUpgrading) }
        installedVersion = next
        upgradingTo = nil
        phase = .installed
        failure = nil
    }
    /// Rollback without a retained prior fails. Do not invent a prior version.
    public mutating func rollback() throws {
        guard let prior = retainedPriorVersion else { throw fail(.noRetainedPrior) }
        guard phase == .upgrading || phase == .installed else { throw fail(.notInstalled) }
        installedVersion = prior
        upgradingTo = nil
        phase = .rolledBack
        failure = nil
    }
    /// W18 marketplace / Apple IAP / WeChat virtual-goods pay is not revived.
    public mutating func purchaseViaIAP() throws -> Never {
        throw fail(.digitalGoodsOpenDecision)
    }
    public mutating func consumeQmodRuntime() throws -> Never {
        throw fail(.waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
    }
    @discardableResult
    private mutating func fail(_ error: WorkshopInstallFailure) -> WorkshopInstallFailure {
        failure = error
        if error.isWaitingSource { phase = .waitingSource }
        return error
    }
}
