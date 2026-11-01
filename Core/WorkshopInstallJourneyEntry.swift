import Foundation

/// One install request. The same id installs once. Rollback uses only a version
/// this request already retained. IAP and the missing qmod runtime stay closed.
public struct WorkshopInstallJourneyEntry: Equatable {
    public private(set) var machine = WorkshopInstallUpgradeRollback()
    public init() {}

    public mutating func hold(originalRequestID: String, versionLabel: String) throws {
        try machine.authorizedHold(originalRequestID: originalRequestID, versionLabel: versionLabel)
    }

    public mutating func install(originalRequestID: String) throws {
        try machine.install(originalRequestID: originalRequestID)
    }

    public mutating func upgrade(to nextVersion: String) throws {
        try machine.beginUpgrade(to: nextVersion)
        try machine.finishUpgrade()
    }

    public mutating func rollback() throws {
        try machine.rollback()
    }

    public mutating func purchase() -> WorkshopInstallFailure {
        closed { try machine.purchaseViaIAP() }
    }

    public mutating func consumeRuntime() -> WorkshopInstallFailure {
        closed { try machine.consumeQmodRuntime() }
    }

    private mutating func closed(_ body: () throws -> Never) -> WorkshopInstallFailure {
        do {
            try body()
        } catch let error as WorkshopInstallFailure {
            return error
        } catch {
            return .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal)
        }
    }
}
