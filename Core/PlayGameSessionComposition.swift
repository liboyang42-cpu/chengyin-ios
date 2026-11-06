import Foundation

@MainActor enum PlayGameSessionCompositionError: Error, Equatable {
    case unsupportedScope
    case missingService
    case missingSessionContext
    case unsupportedRole
    case sessionScopeMismatch
    case journalUnavailable
}

@MainActor enum PlayGameSessionJournalFactory {
    static let allowedRoles: Set<String> = ["player", "club", "merchant"]

    static func validateActivityScope(
        _ scope: PlaySessionScope,
        session: PlayExperienceSession?,
        regionalConfiguration: RegionalConfiguration?,
        storageScope: RegionalSessionStorageScope?
    ) throws -> (
        activityID: Int,
        session: PlayExperienceSession,
        regionalConfiguration: RegionalConfiguration,
        storageScope: RegionalSessionStorageScope
    ) {
        guard case .activity(let activityID) = scope, activityID > 0 else {
            throw PlayGameSessionCompositionError.unsupportedScope
        }
        guard let session, let regionalConfiguration, let storageScope else {
            throw PlayGameSessionCompositionError.missingSessionContext
        }
        let trimmedNamespace = session.namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = session.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard session.accountID > 0,
              !trimmedNamespace.isEmpty,
              !trimmedToken.isEmpty,
              session.epoch > 0
        else {
            throw PlayGameSessionCompositionError.missingSessionContext
        }
        guard allowedRoles.contains(session.role) else {
            throw PlayGameSessionCompositionError.unsupportedRole
        }
        guard regionalConfiguration.apiConfiguration != nil,
              storageScope.matches(configuration: regionalConfiguration),
              session.namespace.utf8.elementsEqual(storageScope.service.utf8)
        else {
            throw PlayGameSessionCompositionError.sessionScopeMismatch
        }
        return (
            activityID: activityID,
            session: session,
            regionalConfiguration: regionalConfiguration,
            storageScope: storageScope
        )
    }

    static func makeJournal(
        session: PlayExperienceSession?,
        scope: PlaySessionScope,
        regionalConfiguration: RegionalConfiguration?,
        storageScope: RegionalSessionStorageScope?,
        makeRecovery: (
            PlayExperienceSession,
            PlaySessionScope,
            RegionalConfiguration,
            RegionalSessionStorageScope
        ) throws -> any PlayGameCommandJournal
    ) throws -> any PlayGameCommandJournal {
        let validated = try validateActivityScope(
            scope,
            session: session,
            regionalConfiguration: regionalConfiguration,
            storageScope: storageScope
        )
        return try makeRecovery(
            validated.session,
            .activity(validated.activityID),
            validated.regionalConfiguration,
            validated.storageScope
        )
    }

    static func makeJournal(
        session: PlayExperienceSession?,
        scope: PlaySessionScope,
        regionalConfiguration: RegionalConfiguration?,
        storageScope: RegionalSessionStorageScope?,
        anchors: any ContentDraftAnchorStore,
        ciphertexts: any ContentDraftCiphertextStore
    ) throws -> PlayDurableRecovery {
        let validated = try validateActivityScope(
            scope,
            session: session,
            regionalConfiguration: regionalConfiguration,
            storageScope: storageScope
        )
        let activeScope = PlaySessionScope.activity(validated.activityID)
        return try PlayDurableRecovery(
            owner: .init(session: validated.session),
            key: PlayRunStorageKey.make(session: validated.session, scope: activeScope),
            anchors: anchors,
            ciphertexts: ciphertexts
        )
    }

    static func makeCoordinator(
        scope: PlaySessionScope,
        service: PlayExperienceService?,
        session: PlayExperienceSession? = nil,
        regionalConfiguration: RegionalConfiguration?,
        storageScope: RegionalSessionStorageScope?,
        currentSession: @escaping () -> PlayExperienceSession?,
        makeRecovery: (
            PlayExperienceSession,
            PlaySessionScope,
            RegionalConfiguration,
            RegionalSessionStorageScope
        ) throws -> any PlayGameCommandJournal
    ) -> PlayPlayerGameCoordinator? {
        guard let service else {
            return nil
        }
        let activeSession = currentSession()
        let candidateSession = session ?? activeSession
        guard let candidateSession, activeSession == candidateSession else {
            return nil
        }
        guard case .activity(let activityID) = scope, activityID > 0 else {
            return nil
        }
        guard let journal = try? makeJournal(
            session: candidateSession,
            scope: .activity(activityID),
            regionalConfiguration: regionalConfiguration,
            storageScope: storageScope,
            makeRecovery: makeRecovery
        ) else {
            return nil
        }
        return PlayPlayerGameCoordinator(
            activityID: activityID,
            service: service,
            currentSession: currentSession,
            journal: journal
        )
    }

    static func makeCoordinator(
        scope: PlaySessionScope,
        service: PlayExperienceService?,
        session: PlayExperienceSession? = nil,
        regionalConfiguration: RegionalConfiguration?,
        storageScope: RegionalSessionStorageScope?,
        currentSession: @escaping () -> PlayExperienceSession?,
        anchors: any ContentDraftAnchorStore,
        ciphertexts: any ContentDraftCiphertextStore
    ) -> PlayPlayerGameCoordinator? {
        makeCoordinator(
            scope: scope,
            service: service,
            session: session,
            regionalConfiguration: regionalConfiguration,
            storageScope: storageScope,
            currentSession: currentSession,
            makeRecovery: { validatedSession, validatedScope, _, _ in
                try PlayDurableRecovery(
                    owner: .init(session: validatedSession),
                    key: PlayRunStorageKey.make(session: validatedSession, scope: validatedScope),
                    anchors: anchors,
                    ciphertexts: ciphertexts
                )
            }
        )
    }

    static func makeCoordinator(
        scope: PlaySessionScope,
        service: PlayExperienceService?,
        session: PlayExperienceSession? = nil,
        regionalConfiguration: RegionalConfiguration?,
        storageScope: RegionalSessionStorageScope?,
        currentSession: @escaping () -> PlayExperienceSession?,
        journal: (any PlayGameCommandJournal)?
    ) -> PlayPlayerGameCoordinator? {
        guard let journal else {
            return nil
        }
        return makeCoordinator(
            scope: scope,
            service: service,
            session: session,
            regionalConfiguration: regionalConfiguration,
            storageScope: storageScope,
            currentSession: currentSession,
            makeRecovery: { _, _, _, _ in journal }
        )
    }

    #if canImport(Security) && canImport(Darwin)
    static func makeSystemJournal(
        session: PlayExperienceSession?,
        scope: PlaySessionScope,
        regionalConfiguration: RegionalConfiguration?,
        storageScope: RegionalSessionStorageScope?
    ) throws -> PlayDurableRecovery {
        let validated = try validateActivityScope(
            scope,
            session: session,
            regionalConfiguration: regionalConfiguration,
            storageScope: storageScope
        )
        return try PlayRecoverySystemFactory.make(
            session: validated.session,
            scope: .activity(validated.activityID),
            regionalConfiguration: validated.regionalConfiguration,
            storageScope: validated.storageScope
        )
    }

    static func makeSystemCoordinator(
        scope: PlaySessionScope,
        service: PlayExperienceService?,
        session: PlayExperienceSession? = nil,
        regionalConfiguration: RegionalConfiguration?,
        storageScope: RegionalSessionStorageScope?,
        currentSession: @escaping () -> PlayExperienceSession?
    ) -> PlayPlayerGameCoordinator? {
        makeCoordinator(
            scope: scope,
            service: service,
            session: session,
            regionalConfiguration: regionalConfiguration,
            storageScope: storageScope,
            currentSession: currentSession,
            makeRecovery: { validatedSession, validatedScope, validatedRegional, validatedStorageScope in
                try PlayRecoverySystemFactory.make(
                    session: validatedSession,
                    scope: validatedScope,
                    regionalConfiguration: validatedRegional,
                    storageScope: validatedStorageScope
                )
            }
        )
    }
    #endif
}
