import Foundation

public enum GroupPollPhase: Equatable {
    case idle, loading, reviewing(GroupPollMutation), submitting, acknowledged, unknown, rejected, failed, blocked
}
/// Retained by account/epoch/conversation/poll. Durable replay locks reuse the existing
/// operation journal and contain identifiers only, never question/choices/token/member names.
@MainActor public final class GroupPollCoordinator {
    public let scope: IMScope
    public let client: any GroupPollServing
    private let reader: any MessagingReading
    private let journal: any OperationPendingJournal
    private let ownerKey: String
    private let creationOwner: Bool
    /// Opt-in protected payload recovery. Nil preserves the original generic poll contract.
    private let creationRecovery: GroupPollCreateRecoveryJournal?
    public private(set) var recoveredCreationWithoutDraft = false
    public private(set) var reference: GroupPollReference?
    private var phase: GroupPollPhase = .idle
    private var poll: GroupPoll?
    private var activeMembership = false
    private var pendingMutation: GroupPollMutation?
    private var generation: UInt64 = 0
    public var onChange: (() -> Void)?
    public var isCurrent: Bool { client.identity == scope.identity && reader.identity == scope.identity }
    public var visiblePhase: GroupPollPhase { isCurrent ? phase : .blocked }
    public var visiblePoll: GroupPoll? { isCurrent ? poll : nil }
    public var isMember: Bool { isCurrent && activeMembership }
    public var canRead: Bool { isCurrent && client.permits("api/im/poll/result") }
    public var canCreate: Bool { isCurrent && reference == nil && reader.isConfigured && canRead && client.permits("api/im/poll/create") && !isBusy && !isLocked(createTarget) && (creationRecovery == nil || !hasCreationRecoveryPending) }
    public var canVote: Bool {
        guard canInteract, let poll else { return false }
        return poll.isOpen() && poll.myOptionId == nil && client.permits("api/im/poll/vote") && !isLocked(voteTarget(poll.id))
    }
    public var canClose: Bool {
        guard canInteract, let poll else { return false }
        return poll.isOpen() && poll.creatorMemberId == scope.identity.accountID && client.permits("api/im/poll/close") && !isLocked(closeTarget(poll.id))
    }
    private var canInteract: Bool { isMember && canRead && poll?.hasResults == true && !isBusy && phase != .unknown && phase != .blocked }
    private var isBusy: Bool { if case .reviewing = phase { return true }; return phase == .loading || phase == .submitting }
    private var createTarget: String { "im.poll.conversation.\(scope.conversationID).create" }
    private func voteTarget(_ id: Int) -> String { "im.poll.\(id).vote" }
    private func closeTarget(_ id: Int) -> String { "im.poll.\(id).close" }
    private func target(_ mutation: GroupPollMutation) -> String {
        switch mutation { case .create: return createTarget; case .vote(let id, _): return voteTarget(id); case .close(let id, _): return closeTarget(id) }
    }
    public init(scope: IMScope, reference: GroupPollReference? = nil, client: any GroupPollServing,
                reader: any MessagingReading, journal: any OperationPendingJournal, namespace: String, realm: URL,
                creationRecovery: GroupPollCreateRecoveryJournal? = nil) throws {
        guard !namespace.isEmpty, reference == nil || reference?.conversationID == scope.conversationID else { throw APIError.invalidRequest }
        _ = try APIConfiguration(baseURL: realm)
        self.creationOwner = reference == nil
        self.creationRecovery = creationRecovery
        self.scope = scope; self.reference = reference; self.client = client; self.reader = reader; self.journal = journal
        ownerKey = [namespace, realm.absoluteString, String(scope.identity.accountID)].map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        if reference == nil, creationRecovery != nil {
            let original = try creationState()
            if original.key != nil { phase = .unknown }
            if let draft = original.draft { pendingMutation = .create(draft) }
        } else if reference == nil, isLocked(createTarget) { phase = .unknown }
    }
    private func isLocked(_ target: String) -> Bool {
        do { return try journal.pending(ownerKey: ownerKey, targetKey: target) != nil } catch { return true }
    }
    private func creationState() throws -> (record: OperationPendingRecord?, draft: GroupPollDraft?, key: String?) {
        let record=try journal.pending(ownerKey:ownerKey,targetKey:createTarget)
        let draft=try creationRecovery?.restore()
        if let record,let draft { guard record.operationID.uuidString.lowercased() == draft.clientPollKey else { throw APIError.malformedResponse } }
        return (record,draft,record?.operationID.uuidString.lowercased() ?? draft?.clientPollKey)
    }
    private var hasCreationRecoveryPending: Bool { do { return try creationState().key != nil } catch { return true } }
    /// Read-only original confirmation for relaunch recovery; never rebuild a missing draft.
    public var originalCreationDraft: GroupPollDraft? {
        guard creationRecovery != nil, creationOwner, isCurrent, reference == nil, case .create(let draft)? = pendingMutation,
              (try? creationState().draft) == draft else { return nil }
        return draft
    }
    public var canRecoverCreationReceipt: Bool {
        creationRecovery != nil && creationOwner && reference == nil && isCurrent && !isBusy && client.permits("api/im/poll/create-receipt") && hasCreationRecoveryPending
    }
    /// Original same-key lookup only. NOT_FOUND is uncertainty, never a retry grant.
    public func recoverCreationReceipt(sourceIsCurrent: () -> Bool = { true }) async {
        guard sourceIsCurrent(), canRecoverCreationReceipt, !Task.isCancelled else { return }
        generation &+= 1;let request=generation;phase = .loading;changed()
        do {
            guard current(request), sourceIsCurrent() else { finishInterruptedCreationRead(request); return }
            let original=try creationState();guard let key=original.key else { throw APIError.invalidRequest }
            if let draft=original.draft { pendingMutation = .create(draft) }
            guard current(request), sourceIsCurrent(), client.permits("api/im/poll/create-receipt") else { finishInterruptedCreationRead(request); return }
            let receipt=try await client.creationReceipt(scope:scope,clientPollKey:key)
            guard current(request), sourceIsCurrent(), client.permits("api/im/poll/create-receipt") else { finishInterruptedCreationRead(request); return }
            let latest=try creationState()
            guard latest.key == key,latest.draft == original.draft,latest.record == original.record else { throw APIError.malformedResponse }
            guard receipt.state == .applied,let value=receipt.poll else { phase = .unknown;changed();return }
            try value.validate(conversationID: scope.conversationID, results: true)
            guard value.creatorMemberId == scope.identity.accountID, value.clientPollKey == key else { throw APIError.malformedResponse }
            if let draft=original.draft {
                guard receipt.requestHash == GroupPollCreateRecoveryJournal.originalRequestHash(draft) else { throw APIError.malformedResponse }
                try value.validateReceipt(.create(draft),scope:scope)
            }
            // Local storage can synchronously retire its owner too. Only this exact
            // still-current receipt may settle the already matched original UUID.
            guard current(request), sourceIsCurrent(), client.permits("api/im/poll/create-receipt") else { finishInterruptedCreationRead(request); return }
            if let record=original.record { try journal.clear(record) }
            guard current(request), sourceIsCurrent(), client.permits("api/im/poll/create-receipt") else { finishInterruptedCreationRead(request); return }
            if let draft=original.draft { try creationRecovery?.clear(draft) }
            guard current(request), sourceIsCurrent() else { finishInterruptedCreationRead(request); return }
            // Legacy key-only locks cannot reconstruct or retry a missing draft.
            recoveredCreationWithoutDraft=original.draft == nil
            pendingMutation=nil;poll=value;reference=GroupPollReference(poll:value);activeMembership=false;phase = .acknowledged
        } catch {
            guard current(request), sourceIsCurrent() else { finishInterruptedCreationRead(request); return }
            phase = .unknown
        }
        changed()
    }
    /// A cancelled read cannot settle its original intent or strand this owner loading.
    /// A newer presentation owns its own phase; never replace it on late completion.
    private func finishInterruptedCreationRead(_ request: UInt64) {
        guard generation == request, phase == .loading else { return }
        activeMembership = false
        phase = hasCreationRecoveryPending ? .unknown : .idle
        changed()
    }
    private func changed() { onChange?() }
    private func current(_ generation: UInt64) -> Bool { isCurrent && self.generation == generation && !Task.isCancelled }
    /// Reads are explicit at detail entry / refresh. Results remain accessible to historical
    /// audience after leaving; failed membership refresh never erases that server permission.
    public func refresh(sourceIsCurrent: () -> Bool = { true }) async {
        guard sourceIsCurrent(), !Task.isCancelled, canRead, !isBusy, let reference else { return }
        generation &+= 1; let request = generation
        phase = .loading; activeMembership = false; changed()
        do {
            guard current(request), sourceIsCurrent(), canRead else { finishInterruptedRead(request); return }
            let value = try await client.result(reference, expectedIdentity: scope.identity)
            guard current(request), sourceIsCurrent() else { finishInterruptedRead(request); return }
            try value.validate(reference: reference, conversationID: scope.conversationID, results: true)
            poll = value
            try resolveProvenLocks(value)
            guard current(request), sourceIsCurrent(), canRead else { finishInterruptedRead(request); return }
            let member = (try? await membership()) == true
            guard current(request), sourceIsCurrent() else { finishInterruptedRead(request); return }
            activeMembership = member
            phase = unresolved(value) ? .unknown : .idle
        } catch {
            guard current(request), sourceIsCurrent() else { finishInterruptedRead(request); return }
            poll = nil; activeMembership = false
            phase = (error as? MessagingReadFailure)?.code == 403 || (error as? MessagingReadFailure)?.code == 404 ? .blocked : .failed
        }
        changed()
    }
    /// A source-fenced detail read may stop without a view callback (for example a
    /// cancelled preflight). Do not leave the retained original owner stuck loading.
    private func finishInterruptedRead(_ request: UInt64) {
        guard generation == request, phase == .loading else { return }
        poll = nil; activeMembership = false; phase = .idle; changed()
    }
    private func membership() async throws -> Bool {
        guard isCurrent, reader.isConfigured else { return false }
        let rows = try await reader.messagingConversations()
        guard isCurrent, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
        return rows.contains { $0.id == scope.conversationID && $0.supportsGroupPolls }
    }
    public func reviewCreate(question: String, options: [String], deadline: Date?, sourceIsCurrent: () -> Bool = { true }) async {
        guard sourceIsCurrent(), !Task.isCancelled, canCreate, let draft = try? GroupPollDraft(conversationID: scope.conversationID, question: question, options: options, deadline: deadline) else { return }
        generation &+= 1; let request = generation; phase = .loading; changed()
        do {
            guard current(request), sourceIsCurrent() else { finishInterruptedRead(request); return }
            let member = try await membership()
            guard current(request), sourceIsCurrent() else { finishInterruptedRead(request); return }
            activeMembership = member
            guard member, !isLocked(createTarget) else { phase = .blocked; changed(); return }
            phase = .reviewing(.create(draft))
        } catch {
            guard current(request), sourceIsCurrent() else { finishInterruptedRead(request); return }
            phase = .failed
        }
        changed()
    }
    public func reviewVote(optionID: Int, sourceIsCurrent: () -> Bool = { true }) {
        guard sourceIsCurrent(), canVote, let poll, poll.options.contains(where: { $0.id == optionID }) else { return }
        phase = .reviewing(.vote(pollID: poll.id, optionID: optionID)); changed()
    }
    public func reviewClose(sourceIsCurrent: () -> Bool = { true }) {
        guard sourceIsCurrent(), canClose, let poll else { return }
        phase = .reviewing(.close(pollID: poll.id, expectedVersion: poll.version)); changed()
    }
    public func resume() {
        if creationOwner, isCurrent, reference == nil, phase == .unknown, !isLocked(createTarget),
           creationRecovery == nil || !hasCreationRecoveryPending {
            pendingMutation = nil; phase = .idle; changed()
        }
    }
    public var canStartAnother: Bool { creationOwner && isCurrent && reference != nil && !isBusy && phase != .unknown && !isLocked(createTarget) && (creationRecovery == nil || !hasCreationRecoveryPending) }
    public func startAnother() {
        guard canStartAnother else { return }
        poll = nil; reference = nil; pendingMutation = nil; recoveredCreationWithoutDraft = false; activeMembership = false; phase = .idle; changed()
    }
    public func cancelReview() {
        if case .reviewing = phase { phase = .idle; changed() }
    }
    /// Dismissal drops drafts/reviews and invalidates reads/preflight. A dispatched request
    /// keeps its journal lock; returning never resubmits it automatically.
    public func suspend() {
        generation &+= 1; activeMembership = false
        switch phase {
        case .reviewing: phase = .idle
        case .loading: phase = creationRecovery != nil && creationOwner && hasCreationRecoveryPending ? .unknown : .idle
        case .submitting: phase = pendingMutation == nil ? .idle : .unknown
        default: break
        }
        changed()
    }
    public func confirm(sourceIsCurrent: () -> Bool = { true }) async {
        guard sourceIsCurrent(), isCurrent, case .reviewing(let mutation) = phase else { return }
        await dispatch(mutation, retryCreate: false, sourceIsCurrent: sourceIsCurrent)
    }
    /// Only creation has a source idempotency key. Vote/close unknown outcomes offer
    /// result refresh only; an OPEN/no-vote read does not prove an in-flight write failed.
    public var canRetryCreation: Bool {
        guard isCurrent, phase == .unknown, let pendingMutation, case .create = pendingMutation else { return false }
        if let source = creationRecovery {
            guard creationOwner, reference == nil, reader.isConfigured,
                  case .create(let draft) = pendingMutation,
                  (try? source.restore()) == draft, draft.deadline.map({ $0 > Date() }) ?? true,
                  let record = try? journal.pending(ownerKey: ownerKey, targetKey: createTarget),
                  record.operationID.uuidString.lowercased() == draft.clientPollKey else { return false }
        }
        return client.permits("api/im/poll/create") && canRead
    }
    public func retryCreationUnchanged(sourceIsCurrent: () -> Bool = { true }) async {
        guard sourceIsCurrent(), canRetryCreation, let mutation = pendingMutation else { return }
        await dispatch(mutation, retryCreate: true, sourceIsCurrent: sourceIsCurrent)
    }
    private func dispatch(_ mutation: GroupPollMutation, retryCreate: Bool, sourceIsCurrent: () -> Bool = { true }) async {
        guard sourceIsCurrent(), isCurrent, client.permits(mutation.path), canRead, !Task.isCancelled else { return }
        generation &+= 1; let request = generation
        phase = .submitting; changed()
        var record: OperationPendingRecord?
        do {
            // Fresh server results and fresh membership precede every mutation. Reviewed
            // version/choice remains immutable; a changed poll returns to explicit review.
            if let reference {
                guard current(request), sourceIsCurrent(), canRead else { finishInterruptedDispatch(request, record: record); return }
                let latest = try await client.result(reference, expectedIdentity: scope.identity)
                guard current(request), sourceIsCurrent() else { finishInterruptedDispatch(request, record: record); return }
                try latest.validate(reference: reference, conversationID: scope.conversationID, results: true)
                poll = latest
                switch mutation {
                case .vote(let id, let option):
                    guard latest.id == id, latest.isOpen(), latest.myOptionId == nil, latest.options.contains(where: { $0.id == option }) else { throw APIError.invalidRequest }
                case .close(let id, let version):
                    guard latest.id == id, latest.isOpen(), latest.version == version, latest.creatorMemberId == scope.identity.accountID else { throw APIError.invalidRequest }
                case .create: throw APIError.invalidRequest
                }
            }
            guard current(request), sourceIsCurrent(), client.permits(mutation.path), canRead else { finishInterruptedDispatch(request, record: record); return }
            let member = try await membership()
            guard current(request), sourceIsCurrent() else { finishInterruptedDispatch(request, record: record); return }
            activeMembership = member
            guard member, client.permits(mutation.path), canRead else { throw MessagingReadFailure(code: 403) }
            let target = target(mutation)
            if retryCreate {
                guard case .create(let draft) = mutation, let existing = try journal.pending(ownerKey: ownerKey, targetKey: target), existing.operationID.uuidString.lowercased() == draft.clientPollKey else { throw APIError.invalidRequest }
                record = existing
            } else {
                guard try journal.pending(ownerKey: ownerKey, targetKey: target) == nil else { throw APIError.invalidRequest }
                let operationID: UUID
                if case .create(let draft) = mutation { guard let id = UUID(uuidString: draft.clientPollKey) else { throw APIError.invalidRequest }; operationID = id }
                else { operationID = UUID() }
                let fresh = OperationPendingRecord(operationID: operationID, ownerKey: ownerKey, targetKey: target)
                // The opt-in owner already knows this exact intent before synchronous
                // storage callbacks can suspend it. A retired pre-dispatch lock stays UNKNOWN.
                if creationRecovery != nil, case .create = mutation { pendingMutation = mutation }
                try journal.write(fresh)
                guard try journal.pending(ownerKey: ownerKey, targetKey: target) == fresh else { throw APIError.malformedResponse }
                record = fresh
            }
            if let creationRecovery, case .create(let draft) = mutation {
                guard current(request), sourceIsCurrent() else { finishInterruptedDispatch(request, record: record); return }
                try creationRecovery.save(draft)
            }
            pendingMutation = mutation
            // A durable journal implementation may synchronously invalidate its owner.
            // Keep the written lock but never dispatch after that ownership boundary.
            guard current(request), sourceIsCurrent(), phase == .submitting,
                  client.permits(mutation.path), canRead else {
                // Preserve the generic synchronous-retirement UNKNOWN contract. The
                // opted-in creation already chose UNKNOWN in suspend(), above.
                if creationRecovery == nil { phase = .unknown; changed() }
                else { finishInterruptedDispatch(request, record: record) }
                return
            }
            let receipt = try await client.perform(mutation, scope: scope, reference: reference)
            guard current(request), sourceIsCurrent() else { finishInterruptedDispatch(request, record: record); return }
            try receipt.validate(reference: reference, conversationID: scope.conversationID, results: mutation.path != "api/im/poll/create")
            try receipt.validateReceipt(mutation, scope: scope)
            if let record { try journal.clear(record) }
            if let creationRecovery, case .create(let draft) = mutation {
                guard current(request), sourceIsCurrent() else { finishInterruptedDispatch(request, record: record); return }
                try creationRecovery.clear(draft)
                guard current(request), sourceIsCurrent() else { finishInterruptedDispatch(request, record: record); return }
            }
            pendingMutation = nil; poll = receipt; reference = GroupPollReference(poll: receipt); phase = .acknowledged
            // Create response's option zeros are NOT result counts. The view explicitly
            // refreshes via /result before offering a vote or rendering a total.
        } catch {
            guard current(request), sourceIsCurrent() else { finishInterruptedDispatch(request, record: record); return }
            if record == nil { phase = .rejected }
            else if (creationRecovery == nil || !retryCreate), let failure = error as? MessagingReadFailure, failure.httpStatus == nil, let code = failure.code, [400, 401, 403, 404].contains(code) {
                do {
                    if let record { try journal.clear(record) }
                    if let creationRecovery, case .create(let draft) = mutation, try creationRecovery.restore() == draft {
                        guard current(request), sourceIsCurrent() else { finishInterruptedDispatch(request, record: record); return }
                        try creationRecovery.clear(draft)
                        guard current(request), sourceIsCurrent() else { finishInterruptedDispatch(request, record: record); return }
                    }
                    pendingMutation = nil; phase = .rejected
                } catch { phase = .unknown }
            } else { phase = .unknown }
            if (error as? MessagingReadFailure)?.code == 403 { activeMembership = false }
        }
        changed()
    }
    /// Suspension already chose the retired request's recovery state. A newer
    /// read may have resolved its lock or entered another review while it awaited
    /// the server, so a late completion must not replace that newer presentation.
    /// Same-lifetime cancellation still ends loading/submission without clearing
    /// a durable intent or treating an unobserved write as a confirmed failure.
    private func finishInterruptedDispatch(_ request: UInt64, record: OperationPendingRecord?) {
        guard generation == request else { return }
        // An exact-create retry can be interrupted before it has reloaded its
        // existing record. Its original pending intent must still stay unknown.
        let hasPendingIntent = pendingMutation.map { isLocked(target($0)) } == true
        phase = record != nil || hasPendingIntent ? .unknown : .idle
        changed()
    }
    private func unresolved(_ poll: GroupPoll) -> Bool { isLocked(voteTarget(poll.id)) || isLocked(closeTarget(poll.id)) }
    private func resolveProvenLocks(_ poll: GroupPoll) throws {
        if poll.myOptionId != nil || poll.status == "CLOSED", let record = try journal.pending(ownerKey: ownerKey, targetKey: voteTarget(poll.id)) { try journal.clear(record) }
        if poll.status == "CLOSED", let record = try journal.pending(ownerKey: ownerKey, targetKey: closeTarget(poll.id)) { try journal.clear(record) }
        // Reopening the real message can reconcile an uncertain create after relaunch.
        if (try creationRecovery?.restore()) == nil, poll.creatorMemberId == scope.identity.accountID,
           let record = try journal.pending(ownerKey: ownerKey, targetKey: createTarget),
           poll.clientPollKey == record.operationID.uuidString.lowercased() { try journal.clear(record) }
        if !unresolved(poll) { pendingMutation = nil }
    }
}
