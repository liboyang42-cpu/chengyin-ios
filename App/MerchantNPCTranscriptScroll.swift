import SwiftUI

/// Presentation metadata only. No question, answer, error text or audio is retained.
@MainActor struct MerchantNPCTranscriptScrollEvent: Equatable {
    enum ReplyState: Equatable { case none, processing, succeeded, rejected, failed, other }
    enum FailureState: Equatable { case none, disabled, staleScope, invalid, reviewRequired, unknownOutcome, malformed, rejected }
    struct Status: Equatable {
        let sending: Bool
        let stopping: Bool
        let reply: ReplyState
        let retryable: Bool
        let retryDeadline: Date?
        let failure: FailureState
    }
    let owner: ObjectIdentifier
    let scope: MerchantNPCScope
    let requestID: UUID?
    let replyID: UUID?
    let lastTurnID: UUID?
    let status: Status

    static func capture(_ coordinator: MerchantNPCChatCoordinator) -> Self? {
        guard coordinator.isCurrent, coordinator.scope.accountID > 0, !coordinator.scope.namespace.isEmpty else { return nil }
        let lastTurnID = coordinator.conversationHistory.turns.last?.id
        let reply: ReplyState
        switch coordinator.reply?.outcomeStatus {
        case nil: reply = .none
        case .some("PROCESSING"): reply = .processing
        case .some("SUCCEEDED"): reply = .succeeded
        case .some("REJECTED"): reply = .rejected
        case .some("FAILED"): reply = .failed
        default: reply = .other
        }
        let failure: FailureState
        switch coordinator.failure {
        case nil: failure = .none
        case .some(.disabled): failure = .disabled
        case .some(.staleScope): failure = .staleScope
        case .some(.invalid): failure = .invalid
        case .some(.reviewRequired): failure = .reviewRequired
        case .some(.unknownOutcome): failure = .unknownOutcome
        case .some(.malformed): failure = .malformed
        case .some(.rejected(_, _)): failure = .rejected
        }
        return .init(owner: ObjectIdentifier(coordinator), scope: coordinator.scope,
            requestID: coordinator.requestID, replyID: coordinator.reply?.requestID, lastTurnID: lastTurnID,
            status: .init(sending: coordinator.sending, stopping: coordinator.isStoppingLocalWait,
                reply: reply, retryable: coordinator.reply?.canRetry == true,
                retryDeadline: coordinator.requestID == nil ? nil : coordinator.retryAt, failure: failure))
    }
}

/// Consume visible events once. Merely rendering, changing a countdown or returning
/// to the foreground must not replay an old scroll intent.
@MainActor struct MerchantNPCTranscriptScrollPolicy {
    private var previous: MerchantNPCTranscriptScrollEvent?
    private var active = false
    mutating func synchronize(_ event: MerchantNPCTranscriptScrollEvent?, isActive: Bool) {
        previous = event; active = isActive
    }
    mutating func consume(_ event: MerchantNPCTranscriptScrollEvent?, isActive: Bool, voiceOverEnabled: Bool) -> Bool {
        let old = previous, wasActive = active
        previous = event; active = isActive
        guard wasActive, isActive, !voiceOverEnabled, let old, let event,
              old.owner == event.owner, old.scope == event.scope, old != event else { return false }
        if let last = event.lastTurnID, last != old.lastTurnID { return true }
        // Includes a new send, a new safe/service reply and meaningful pending
        // status changes. No message count, revision counter or current clock value.
        if event.requestID != nil || event.replyID != nil { return true }
        // An HTTP rejection can end a pending request without producing a reply ID.
        return old.requestID != nil && event.status.failure != .none && event.status.failure != old.status.failure
    }
}

@MainActor struct MerchantNPCTranscriptScroll<Content: View>: View {
    let coordinator: MerchantNPCChatCoordinator
    let event: MerchantNPCTranscriptScrollEvent?
    private let content: Content
    @State private var policy = MerchantNPCTranscriptScrollPolicy()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    private static var bottomID: String { "merchantNPC.transcript.bottom" }

    init(coordinator: MerchantNPCChatCoordinator, event: MerchantNPCTranscriptScrollEvent?, @ViewBuilder content: () -> Content) {
        self.coordinator = coordinator; self.event = event; self.content = content()
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                Color.clear.frame(height: 1).id(Self.bottomID).accessibilityHidden(true)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { policy.synchronize(event, isActive: scenePhase == .active) }
            .onChange(of: event) { _, next in
                guard policy.consume(next, isActive: scenePhase == .active, voiceOverEnabled: voiceOverEnabled) else { return }
                let current = MerchantNPCTranscriptScrollEvent.capture(coordinator)
                guard let next, current == next else {
                    policy.synchronize(current, isActive: scenePhase == .active); return
                }
                // Never move VoiceOver focus, and never animate, including when an
                // enclosing update has an animation or Reduce Motion is enabled.
                var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
                withTransaction(transaction) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: scenePhase) { _, phase in policy.synchronize(event, isActive: phase == .active) }
            .onChange(of: voiceOverEnabled) { _, _ in policy.synchronize(event, isActive: scenePhase == .active) }
            .onDisappear { policy.synchronize(nil, isActive: false) }
        }
    }
}
