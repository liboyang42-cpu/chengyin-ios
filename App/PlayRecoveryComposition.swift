import Foundation

/// Construction performs no I/O, confers no network grant and has no memory fallback.
@MainActor enum PlayRecoveryComposition {
    static func make(session: PlayExperienceSession, scope: PlaySessionScope,
                     regionalConfiguration: RegionalConfiguration, storageScope: RegionalSessionStorageScope) throws -> PlayDurableRecovery {
        try PlayRecoverySystemFactory.make(session: session, scope: scope,
            regionalConfiguration: regionalConfiguration, storageScope: storageScope)
    }
}
