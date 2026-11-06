import Foundation

/// The existing host supplies its original private transport and independent Text grants.
/// This is a response-adapter bundle, not another network client or permission source.
@MainActor struct NativeChannelMessageOriginalAdapters {
    let wire: NativeChannelMessageOriginalWireBridge
    let historyTransport: any HTTPTransport
    let textTransport: NativeChannelTextTransport?
}

@MainActor final class NativeChannelMessageHostFlow {
    final class Lifetime { var active = true }
    let history: NativeChannelHistoryModel
    let reader: MessagingSessionReader
    let wire: NativeChannelMessageOriginalWireBridge
    let coordinator: NativeChannelMessageCoordinator
    private let mutationJournal: NativeChannelMessageMutationJournal
    private(set) var mentionTargets: NativeChannelMentionTargets?
    func attachMentionTargets(_ source: NativeChannelMentionTargets) {
        guard mentionTargets == nil,source.binding == coordinator.client.binding,source.isCurrent else { return };mentionTargets=source
    }
    var canOpenMentionTargets: Bool { isCurrent && mentionTargets?.isCurrent == true && makeTextCoordinator(history:history)?.isCurrent == true }
    var canPrepareMentions: Bool { isCurrent && mentionTargets?.isCurrent == true && makeTextCoordinator(history:history).map { $0.canSendNew && $0.client.canSendMentions } == true }
    var originalDraftReference: NativeChannelMessageTextReference? { retainedText?.coordinator.draftTextReference }
    private var retainedText: (coordinator: NativeChannelTextCoordinator, journal: NativeChannelTextJournal)?
    private let context: RuntimeDependencyContext
    private let storage: any ProjectEditDataStorage
    private let text: NativeChannelTextTransport?
    private let lifetime: Lifetime
    private let current: () -> Bool
    private let unauthorized: () -> Void
    private let originalHistory: NativeChannelMessageOriginalHistoryBinding
    var isCurrent: Bool { lifetime.active && current() }
    fileprivate init(context: RuntimeDependencyContext, storage: any ProjectEditDataStorage,
                     adapters: NativeChannelMessageOriginalAdapters, history: NativeChannelHistoryModel, reader: MessagingSessionReader,
                     coordinator: NativeChannelMessageCoordinator, mutationJournal: NativeChannelMessageMutationJournal,
                     originalHistory: NativeChannelMessageOriginalHistoryBinding,
                     lifetime: Lifetime, current: @escaping () -> Bool, unauthorized: @escaping () -> Void) {
        self.context = context; self.storage = storage; text = adapters.textTransport; wire = adapters.wire
        self.history = history; self.reader = reader; self.coordinator = coordinator; self.originalHistory = originalHistory
        self.mutationJournal = mutationJournal
        self.lifetime = lifetime; self.current = current; self.unauthorized = unauthorized
    }
    func makeTextCoordinator(history selected: NativeChannelHistoryModel) -> NativeChannelTextCoordinator? {
        guard selected === history, isCurrent, history.isCurrent, history.loaded, !history.isLoading,
              history.issue == nil, let text else { return nil }
        if let retainedText { return retainedText.coordinator }
        guard let client = try? NativeChannelTextClient(context: context, conversationID: history.conversation.id,
            transport: text, onUnauthorized: { [weak self] _ in guard self?.isCurrent == true else { return }; self?.unauthorized() }) else { return nil }
        let journal = NativeChannelTextJournal(storage: storage, scope: client.scope)
        guard let coordinator = try? NativeChannelTextCoordinator(history: history, client: client, journal: journal,
            referenceIsCurrent: { [weak self] in self?.isCurrentQuote($0) == true }) else { return nil }
        retainedText = (coordinator, journal)
        return coordinator
    }
    private func isCurrentQuote(_ reference: NativeChannelMessageTextReference) -> Bool {
        guard isCurrent, history.isCurrent, history.loaded, history.issue == nil,
              reference.binding.sameTarget(as:coordinator.client.binding) else { return false }
        if let id=reference.replyToID {
            guard let raw=Int(id.rawValue),let row=history.detailMessage(raw),let snapshot=wire.snapshot(for:row),
                  snapshot.conversationID == reference.binding.conversationID,snapshot.status == 0,
                  snapshot.senderID != nil,let senderType=snapshot.senderType,senderType != 3,
                  coordinator.canDisplay(snapshot) else { return false }
        }
        if !reference.memberIDs.isEmpty || !reference.roleIDs.isEmpty || reference.mentionEveryone {
            guard mentionTargets?.validates(reference) == true else { return false }
        }
        return true // Original server final visibility, system, role, mention permission and audience checks remain.
    }
    @discardableResult func prepareOriginalQuote(_ id: NativeChannelMessageID) -> Bool {
        let prior=originalDraftReference
        guard let reference = try? NativeChannelMessageTextReference(binding: coordinator.client.binding, replyToID: id,
            memberIDs:prior?.memberIDs ?? [],roleIDs:prior?.roleIDs ?? [],mentionEveryone:prior?.mentionEveryone ?? false),
              isCurrentQuote(reference), let owner = makeTextCoordinator(history: history) else { return false }
        return owner.selectQuote(reference)
    }
    @discardableResult func prepareOriginalMentions(_ members: [NativeChannelMessageID],_ roles: [NativeChannelMessageID],_ everyone: Bool) -> Bool {
        guard canPrepareMentions,let owner=makeTextCoordinator(history:history) else { return false }
        let reply=owner.draftTextReference?.replyToID
        if reply == nil && members.isEmpty && roles.isEmpty && !everyone { owner.cancelQuoteDraft();return true }
        guard let reference=try? NativeChannelMessageTextReference(binding:coordinator.client.binding,replyToID:reply,
            memberIDs:members,roleIDs:roles,mentionEveryone:everyone),isCurrentQuote(reference) else { return false }
        return owner.selectReference(reference)
    }
    /// Shares only references created by this host; it does not construct a writer or journal.
    func pageActions(history selected: NativeChannelHistoryModel,
                     textCoordinator selectedText: NativeChannelTextCoordinator) -> ChannelPageActions? {
        guard selected === history, isCurrent, let retainedText,
              retainedText.coordinator === selectedText else { return nil }
        return .init(textCoordinator: retainedText.coordinator, messageCoordinator: coordinator,
                     textJournal: retainedText.journal, mutationJournal: mutationJournal)
    }
    func retire() {
        lifetime.active = false
        // Covered history presentation can retain a callback back to this host.
        // Remove it before stop() publishes, so retirement cannot preserve that cycle.
        history.onChange = nil
        let text = retainedText
        retainedText = nil
        // The host can retire before SwiftUI sends onDisappear. Release the
        // original text lease now; keep its protected journal, never resend.
        text?.coordinator.onChange = nil
        text?.coordinator.stop()
        mentionTargets?.retire(); coordinator.retire(); history.stop(); wire.retire()
    }
}

/// One original history, one original Text journal, and the already-existing mutation
/// journal. Mapping is supplied only after a real ChannelContext and IM row were read.
@MainActor enum NativeChannelMessageHostBinding {
    static func make(context: RuntimeDependencyContext, conversation: MessagingConversation,
        authority: NativeChannelMessageHostAuthority, storage: any ProjectEditDataStorage,
        current: @escaping () -> Bool, onUnauthorized: @escaping () -> Void,
        makeOriginal: (_ current: @escaping () -> Bool, _ received401: @escaping () -> Void) throws -> NativeChannelMessageOriginalAdapters,
        makeMutations: (_ journal: NativeChannelMessageMutationJournal, _ current: @escaping () -> Bool,
                        _ unauthorized: @escaping (MessagingReadIdentity) -> Void) throws -> any NativeChannelMessageDispatching) throws -> NativeChannelMessageHostFlow {
        let binding = authority.binding
        guard current(), authority.identity == MessagingReadIdentity(accountID: context.session.accountID, epoch: context.session.epoch),
              binding.conversationID.rawValue == String(conversation.id),
              let space = NativeChannelSpace.project([conversation]).first, space.kind == .club else { throw APIError.notConfigured }
        let anchor = (try? authority.credentials(for: .receipt, binding: binding))
            ?? (try? authority.credentials(for: .mutations, binding: binding))
        guard let anchor else { throw APIError.notConfigured }
        let lifetime = NativeChannelMessageHostFlow.Lifetime()
        let available = { lifetime.active && current() && authority.identity == anchor.identity }
        let received401 = {
            if !Task.isCancelled, available() { onUnauthorized() }
            authority.retireReceivedUnauthorized(anchor)
        }
        let adapters = try makeOriginal(available, received401)
        let reader = MessagingSessionReader(service: MessagingService(configuration: try .init(baseURL: context.baseURL), transport: adapters.historyTransport), currentSession: {
            guard available() else { return nil }
            return try? .init(accountID: context.session.accountID, epoch: context.session.epoch, token: context.session.token)
        }, isAvailable: available, onUnauthorized: { _ in if available() { onUnauthorized() } })
        let historyClient = NativeChannelSessionClient(history: reader, currentSession: {
            guard available() else { return nil }
            return try? .init(accountID: context.session.accountID, epoch: context.session.epoch, token: context.session.token)
        }, isAvailable: available, onUnauthorized: { _ in if available() { onUnauthorized() } })
        let history = NativeChannelHistoryModel(conversation: conversation, client: historyClient)
        let originalHistory = NativeChannelMessageOriginalHistoryBinding(model: history, wire: adapters.wire,
            invalidate: { adapters.wire.invalidate($0) })
        let journal = NativeChannelMessageMutationJournal(scope: .init(credentials: anchor), storage: storage)
        let dispatcher = try makeMutations(journal, available, { expected in
            if expected == anchor.identity, available() { onUnauthorized() }
        })
        let client = NativeChannelMessageService(credentials: anchor, authority: authority, transport: dispatcher,
            onUnauthorized: { expected in if expected == anchor.identity, available() { onUnauthorized() } })
        let coordinator = try NativeChannelMessageCoordinator(client: client, journal: journal,
            invalidateOriginalMessage: { originalHistory.invalidateOriginal($0) },
            refreshOriginalHistory: { try await originalHistory.refresh() })
        originalHistory.coordinator = coordinator
        return NativeChannelMessageHostFlow(context: context, storage: storage, adapters: adapters,
            history: history, reader: reader, coordinator: coordinator, mutationJournal: journal, originalHistory: originalHistory,
            lifetime: lifetime, current: current, unauthorized: onUnauthorized)
    }
}
