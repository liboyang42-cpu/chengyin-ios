import Foundation

/// Exact native account-role vocabulary, not UI entry intent or an arbitrary server string.
/// A recognized role binds local recovery; it never confers a network capability.
enum PlayRecoveryAccountRole: String { case player, club, merchant }

/// Construction performs no storage I/O, confers no network grant and has no fallback.
@MainActor enum PlayRecoveryComposition {
    static func make(session: PlayExperienceSession, scope: PlaySessionScope,
                     regionalConfiguration: RegionalConfiguration, storageScope: RegionalSessionStorageScope) throws -> PlayDurableRecovery {
        try validate(session: session, scope: scope, regionalConfiguration: regionalConfiguration, storageScope: storageScope)
        return try PlayRecoverySystemFactory.make(session: session, scope: scope,
            regionalConfiguration: regionalConfiguration, storageScope: storageScope)
    }
    fileprivate static func validate(session: PlayExperienceSession, scope: PlaySessionScope,
                                     regionalConfiguration: RegionalConfiguration, storageScope: RegionalSessionStorageScope) throws {
        guard PlayRecoveryAccountRole(rawValue: session.role) != nil, scope.isValid,
              storageScope.matches(configuration: regionalConfiguration),
              session.namespace.utf8.elementsEqual(storageScope.service.utf8) else { throw PlayExperienceError.persistenceUnavailable }
    }
}

/// The normal root chooses fixed OS storage. DEBUG tests explicitly supply synthetic
/// primitives, never a replacement transport or a forged system-provenance seal.
@MainActor enum PlayRecoveryConstruction {
    case system
    #if DEBUG
    case synthetic(anchors: any ContentDraftAnchorStore, ciphertexts: any ContentDraftCiphertextStore)
    case unavailable
    #endif

    func make(session: PlayExperienceSession, scope: PlaySessionScope,
              regionalConfiguration: RegionalConfiguration, storageScope: RegionalSessionStorageScope) throws -> PlayDurableRecovery {
        try PlayRecoveryComposition.validate(session: session, scope: scope,
            regionalConfiguration: regionalConfiguration, storageScope: storageScope)
        switch self {
        case .system:
            return try PlayRecoveryComposition.make(session: session, scope: scope,
                regionalConfiguration: regionalConfiguration, storageScope: storageScope)
        #if DEBUG
        case .synthetic(let anchors, let ciphertexts):
            return try PlayDurableRecovery(owner: .init(session: session),
                key: PlayRunStorageKey.make(session: session, scope: scope), anchors: anchors, ciphertexts: ciphertexts)
        case .unavailable:
            throw PlayExperienceError.persistenceUnavailable
        #endif
        }
    }
}
