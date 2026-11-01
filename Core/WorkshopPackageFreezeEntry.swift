import Foundation

/// Freezes one reviewed package version. The same request id republishes the
/// same hashes. The public author registry and the missing module pack stay closed.
public struct WorkshopPackageFreezeEntry: Equatable {
    public private(set) var publish = WorkshopPackageVersionPublish()
    public init() {}

    public mutating func freeze(contentHash: String, termsHash: String, versionLabel: String,
                                originalRequestID: String, reviewed: Bool) throws {
        try publish.freeze(contentHash: contentHash, termsHash: termsHash, versionLabel: versionLabel,
                           originalRequestID: originalRequestID, reviewed: reviewed)
    }

    public mutating func registerPublic() -> WorkshopPackagePublishFailure {
        do {
            try publish.registerPublicAuthorPublish()
        } catch let error as WorkshopPackagePublishFailure {
            return error
        } catch {
            return .publicRegistryReserved
        }
    }

    public mutating func consumePack() -> WorkshopPackagePublishFailure {
        do {
            try publish.consumeModulePackOriginal()
        } catch let error as WorkshopPackagePublishFailure {
            return error
        } catch {
            return .waitingSource(capability: WorkshopModuleSourceInventory.modulePackOriginal)
        }
    }
}
