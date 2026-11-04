import Foundation
import Observation

public enum NativeChannelTextState: Equatable {
    case idle, sending, checkingReceipt, outcomeUnknown, receiptUnavailable, persistenceFailed, accessClosed
    /// Verified original server ID only. Payload is always re-projected from current history.
    case acknowledged(messageID: Int)
}

/// Complete one intent before accepting another. All recovery reads use its original
/// key and payload; a missing receipt never triggers an automatic send.
@MainActor @Observable public final class NativeChannelTextCoordinator {
    public let history: NativeChannelHistoryModel
    public let client: any NativeChannelTextAccess
    private let journal: NativeChannelTextJournal
    private let capturedIdentity: MessagingReadIdentity?
    private var intent: MessageTextIntent?
    private var draftReference: NativeChannelMessageTextReference?
    private let referenceIsCurrent: (NativeChannelMessageTextReference) -> Bool
    public var quotedMessageID: String? { isCurrent && conversationReady ? draftReference?.replyToID?.rawValue : nil }
    public var pendingQuotedMessageID: String? { pendingClientMessageID != nil ? intent?.channelReference?.replyToID?.rawValue : nil }
    public var draftTextReference: NativeChannelMessageTextReference? { isCurrent && conversationReady ? draftReference : nil }
    public var mentionSummary: String? { referenceSummary(draftTextReference) }
    public var pendingMentionSummary: String? { pendingClientMessageID != nil ? referenceSummary(intent?.channelReference) : nil }
    private func referenceSummary(_ reference: NativeChannelMessageTextReference?) -> String? {
        guard let reference,!reference.memberIDs.isEmpty || !reference.roleIDs.isEmpty || reference.mentionEveryone else { return nil }
        return "成员："+reference.memberIDs.map(\.rawValue).joined(separator:", ")+"；角色："+reference.roleIDs.map(\.rawValue).joined(separator:", ")+(reference.mentionEveryone ? "；本频道所有当前可见成员（原服务最终过滤）" : "；不提及所有人")
    }
    private func canUse(_ reference: NativeChannelMessageTextReference) -> Bool {
        let mentions = !reference.memberIDs.isEmpty || !reference.roleIDs.isEmpty || reference.mentionEveryone
        return (reference.replyToID == nil || client.canSendQuoted) && (!mentions || client.canSendMentions) && referenceIsCurrent(reference)
    }
    public var quoteDraftIsCurrent: Bool { draftReference.map(canUse) ?? true }
    @discardableResult public func selectReference(_ reference: NativeChannelMessageTextReference) -> Bool {
        guard canSendNew,canUse(reference) else { return false };draftReference=reference;onChange?();return true
    }
    @discardableResult public func selectQuote(_ reference: NativeChannelMessageTextReference) -> Bool {
        guard canSendNew, canUse(reference) else { return false }
        draftReference = reference; onChange?(); return true
    }
    public func cancelQuoteDraft() { guard intent == nil else { return }; draftReference = nil; onChange?() }
    private func mayDispatch(_ value: MessageTextIntent) -> Bool {
        value.channelReference.map(canUse) ?? true
    }
    private var state: NativeChannelTextState = .idle
    private var restored = false
    private var verifiedReceiptClientMessageID: String?
    private var active = false
    private var generation: UInt64 = 0
    private var busy = false
    private var retryPermitted = false
    private var terminalAccessFailure = false
    // Metadata-only safety veto from a newer authoritative receipt. Never restore
    // old normal text from an older history page after recall/moderation evidence.
    private var withheldMessageIDs: Set<Int> = []
    @ObservationIgnored public var onChange: (() -> Void)?
    public var isCurrent: Bool {
        active && capturedIdentity != nil && client.identity == capturedIdentity && history.isCurrent
            && history.client.identity == capturedIdentity
    }
    public var conversationReady: Bool {
        isCurrent && history.loaded && !history.isLoading && history.issue == nil && !terminalAccessFailure
    }
    public var visibleState: NativeChannelTextState { isCurrent && client.canReadReceipt ? state : .accessClosed }
    public var authoritativeMessage: MessagingMessage? {
        guard conversationReady, client.canReadReceipt, case .acknowledged(let id) = state, !isMessageWithheld(id) else { return nil }
        return history.detailMessage(id)
    }
    public func isMessageWithheld(_ id: Int) -> Bool {
        // Pushed details outlive active history, but not its captured owner/conversation.
        capturedIdentity != nil && history.client.identity == capturedIdentity
            && history.conversation.id == client.scope.conversationID && withheldMessageIDs.contains(id)
    }
    public var receiptPayloadWithheld: Bool {
        guard isCurrent, case .acknowledged(let id) = state else { return false }
        return isMessageWithheld(id)
    }
    public var pendingText: String? {
        if case .acknowledged = state { return nil }
        if let intent, intent.clientMessageID == verifiedReceiptClientMessageID { return nil }
        return isCurrent && conversationReady && client.canReadReceipt ? intent?.content : nil
    }
    public var pendingClientMessageID: String? { isCurrent && conversationReady && client.canReadReceipt ? intent?.clientMessageID : nil }
    public var canSendNew: Bool {
        conversationReady && restored && !busy && intent == nil && client.canSend && client.canReadReceipt
            && (try? journal.permitsNewOriginalSend()) == true
            && state != .persistenceFailed
    }
    public var canCheckReceipt: Bool { conversationReady && !busy && intent != nil && client.canReadReceipt }
    public var canRetryOriginal: Bool {
        canCheckReceipt && client.canSend && retryPermitted && intent.map(mayDispatch) == true
    }
    public init(history: NativeChannelHistoryModel, client: any NativeChannelTextAccess,
                journal: NativeChannelTextJournal,
                referenceIsCurrent: @escaping (NativeChannelMessageTextReference) -> Bool = { _ in false }) throws {
        guard client.scope == journal.scope, history.conversation.id == client.scope.conversationID,
              let space = NativeChannelSpace.project([history.conversation]).first,
              space.kind == .club || space.kind == .team else { throw APIError.invalidRequest }
        self.referenceIsCurrent = referenceIsCurrent
        self.history = history; self.client = client; self.journal = journal
        capturedIdentity = client.identity
    }
    /// Call after successful existing history load. Cold start restores but never POSTs.
    public func activate() {
        active = true
        guard isCurrent, client.canReadReceipt else { onChange?(); return }
        if !restored && !busy {
            do {
                intent = try journal.restore(); restored = true
                state = intent == nil ? .idle : .outcomeUnknown
            } catch { state = .persistenceFailed }
        }
        onChange?()
    }
    /// Cancel/return/background cannot prove rollback. Retain only the protected original.
    public func stop() {
        draftReference = nil
        active = false; generation &+= 1; client.retireOperations(); retryPermitted = false
        if intent != nil { state = .outcomeUnknown }
        onChange?()
    }
    /// A departed/closed conversation requires a new history lifetime and fresh authority.
    public func accessInvalidated() { terminalAccessFailure = true; stop() }
    @discardableResult public func sendNew(_ text: String) async -> Bool {
        guard canSendNew, quoteDraftIsCurrent, !Task.isCancelled,
              let value = try? MessageTextIntent(conversationID: client.scope.conversationID, content: text, channelReference: draftReference),
              let lock = journal.beginOperation() else { return false }
        busy = true; generation &+= 1; let operation = generation
        defer { finish(lock) }
        do {
            try journal.saveBeforeDispatch(value)
            intent = value; draftReference = nil; verifiedReceiptClientMessageID = nil
        } catch {
            // A failed read-back can follow a successful write. Never overwrite that key.
            restored = false; state = .persistenceFailed; onChange?(); return false
        }
        guard valid(operation), conversationReady, client.canSend, client.canReadReceipt else {
            state = .outcomeUnknown; onChange?(); return false
        }
        return await dispatch(value, operation: operation)
    }
    @discardableResult public func checkReceipt() async -> Bool {
        guard canCheckReceipt, !Task.isCancelled, let value = intent,
              let lock = journal.beginOperation() else { return false }
        busy = true; generation &+= 1; let operation = generation
        defer { finish(lock) }
        return await probe(value, operation: operation)
    }
    /// Only a distinct, explicit user action after a successful missing-receipt read.
    /// It re-reads first; if now found, no write occurs. It never rotates the key/content.
    @discardableResult public func retryOriginal() async -> Bool {
        guard canRetryOriginal, !Task.isCancelled, let value = intent,
              let lock = journal.beginOperation() else { return false }
        busy = true; retryPermitted = false; generation &+= 1; let operation = generation
        defer { finish(lock) }
        if await probe(value, operation: operation) { return true }
        guard valid(operation), conversationReady, retryPermitted, client.canSend, client.canReadReceipt,
              NativeChannelTextJournal.same(intent, value) else { return false }
        retryPermitted = false
        return await dispatch(value, operation: operation)
    }
    private func finish(_ lock: UUID) {
        journal.endOperation(lock); busy = false
        if state == .sending || state == .checkingReceipt { state = .outcomeUnknown }
        onChange?()
    }
    private func valid(_ operation: UInt64) -> Bool {
        generation == operation && isCurrent && !Task.isCancelled
    }
    private func dispatch(_ value: MessageTextIntent, operation: UInt64) async -> Bool {
        guard valid(operation), conversationReady, client.canSend, client.canReadReceipt, mayDispatch(value) else { return false }
        // Final persistence check at the actual dispatch boundary, not only at draft creation.
        do { guard try NativeChannelTextJournal.same(journal.restore(), value) else { throw NativeChannelTextJournalError.pendingIntent } }
        catch { state = .persistenceFailed; onChange?(); return false }
        state = .sending; retryPermitted = false; onChange?()
        do {
            let message = try await client.send(value)
            guard valid(operation), conversationReady, client.canSend else { return false }
            return acknowledge(message, value: value)
        } catch {
            guard valid(operation) else { return false }
            if closesAccess(error) { closeAccess(); return false }
            state = .outcomeUnknown; onChange?()
            // Timeout/network/malformed/409 is never a resend instruction. Query only.
            if conversationReady && client.canReadReceipt { return await probe(value, operation: operation) }
            return false
        }
    }
    private func probe(_ value: MessageTextIntent, operation: UInt64) async -> Bool {
        guard valid(operation), conversationReady, client.canReadReceipt else { return false }
        retryPermitted = false; state = .checkingReceipt; onChange?()
        do {
            let read = try await client.confirmOriginal(value)
            guard valid(operation), conversationReady, client.canReadReceipt,
                  NativeChannelTextJournal.same(intent, value) else { return false }
            if case .applied(let id) = read.kind {
                return acknowledge(id, withheld: read.displayWithheld, value: value)
            }
            state = .outcomeUnknown
            retryPermitted = read.kind == .notFound
            onChange?(); return false
        } catch {
            guard valid(operation) else { return false }
            if closesAccess(error) { closeAccess() }
            else { state = .receiptUnavailable; onChange?() }
            return false
        }
    }
    private func acknowledge(_ message: MessagingMessage, value: MessageTextIntent) -> Bool {
        acknowledge(message.id, withheld: !message.isPayloadVisible, value: value)
    }
    /// Receipt recovery settles only from the original send proof id. The display body is not the proof.
    private func acknowledge(_ id: Int, withheld: Bool, value: MessageTextIntent) -> Bool {
        verifiedReceiptClientMessageID = value.clientMessageID
        if withheld { withheldMessageIDs.insert(id) }
        state = .acknowledged(messageID: id); retryPermitted = false
        do { try journal.settle(value); intent = nil }
        catch { /* keep original, block new sends; re-read can retry protected cleanup */ }
        onChange?(); return true
    }
    private func closesAccess(_ error: Error) -> Bool {
        guard let failure = error as? MessagingReadFailure else { return error as? APIError == .unauthorized }
        return failure.isUnauthorized || failure.isForbidden || failure.isClosed || failure.code == 404
            || failure.errorCode == "IM_CONVERSATION_CLOSED"
    }
    private func closeAccess() {
        terminalAccessFailure = true; retryPermitted = false; state = .accessClosed; onChange?()
    }
}
