import Foundation

/// The root supplies the real independent authority and final-forward dispatcher.
/// This adapter does not issue grants, register devices or alter shared sessions.
@MainActor enum NativeChannelNotificationBinding {
    /// Reuses the original final-forward owner; this reader never writes/restores/settles the journal.
    static func makeDeliveryLog(context: RuntimeDependencyContext, storage: any ProjectEditDataStorage,
        makeDispatcher: (NativeChannelNotificationJournal) throws -> NativeChannelNotificationFinalForward) throws -> NativeNotificationDeliveryLogCoordinator {
        let journal = NativeChannelNotificationJournal(storage: NativeChannelNotificationProtectedStorage(existing: storage),
            owner: .init(context: context))
        let dispatcher = try makeDispatcher(journal)
        guard ContentDraftContextFence.matches(dispatcher.authority.context, context),
              dispatcher.authority.allows(.deliveryLog, scope: nil) else { throw NativeChannelNotificationError.accessClosed }
        return NativeNotificationDeliveryLogCoordinator(client: NativeChannelNotificationService(authority: dispatcher.authority, transport: dispatcher))
    }
    /// Creates one original journal shared by coordinator and final-forward verification.
    /// The dispatcher supplies the same captured authority used by the service.
    static func make(context: RuntimeDependencyContext, storage: any ProjectEditDataStorage,
        scope: NativeChannelNotificationScope?, sharedClubDefault: Bool = false,
        makeDispatcher: (NativeChannelNotificationJournal) throws -> NativeChannelNotificationFinalForward) throws -> NativeChannelNotificationCoordinator {
        let journal = NativeChannelNotificationJournal(storage: NativeChannelNotificationProtectedStorage(existing: storage),
            owner: .init(context: context))
        let dispatcher = try makeDispatcher(journal)
        let authority = dispatcher.authority
        guard ContentDraftContextFence.matches(authority.context, context) else {
            throw NativeChannelNotificationError.accessClosed
        }
        guard !sharedClubDefault || scope?.type == 2 else { throw NativeChannelNotificationError.accessClosed }
        if !authority.allows(sharedClubDefault ? .clubDefaultRead : (scope == nil ? .directory : .preference), scope: scope) {
            // Revoked current-setting access must not strand an independently authorized
            // original receipt. ACK is its own channel grant and does not enable save or mute.
            let ackAllowed = scope?.type == 1 && authority.allows(.ack, scope: scope)
            let unreadAllowed = scope == nil && authority.allows(.unread, scope: nil)
            if !ackAllowed && !unreadAllowed {
                guard let original = try journal.restore(), authority.allows(.receipt, scope: original.scope) else {
                    throw NativeChannelNotificationError.accessClosed
                }
            }
        }
        return try .init(client: NativeChannelNotificationService(authority: authority, transport: dispatcher),
                         journal: journal, scope: scope, sharedClubDefault: sharedClubDefault)
    }
    static func make(context: RuntimeDependencyContext, source: any NativeChannelNotificationAuthorizing,
        dispatcher: any NativeChannelNotificationDispatching, storage: any ProjectEditDataStorage,
        scope: NativeChannelNotificationScope?, sharedClubDefault: Bool = false) throws -> NativeChannelNotificationCoordinator {
        let authority = try NativeChannelNotificationAuthority(context: context, source: source)
        guard !sharedClubDefault || scope?.type == 2 else { throw NativeChannelNotificationError.accessClosed }
        let readAllowed = authority.allows(sharedClubDefault ? .clubDefaultRead : (scope == nil ? .directory : .preference), scope: scope)
        let ackAllowed = scope?.type == 1 && authority.allows(.ack, scope: scope)
        let unreadAllowed = scope == nil && authority.allows(.unread, scope: nil)
        guard readAllowed || ackAllowed || unreadAllowed else {
            throw NativeChannelNotificationError.accessClosed
        }
        let service = NativeChannelNotificationService(authority: authority, transport: dispatcher)
        let journal = NativeChannelNotificationJournal(storage: NativeChannelNotificationProtectedStorage(existing: storage),
            owner: .init(context: context))
        return try .init(client: service, journal: journal, scope: scope, sharedClubDefault: sharedClubDefault)
    }
}
