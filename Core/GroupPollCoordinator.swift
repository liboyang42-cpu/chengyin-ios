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
    public var canCreate: Bool { isCurrent && reference == nil && reader.isConfigured && canRead && client.permits("api/im/poll/create") && !isBusy && !isLocked(createTarget) }
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
                reader: any MessagingReading, journal: any OperationPendingJournal, namespace: String, realm: URL) throws {
        guard !namespace.isEmpty, reference == nil || reference?.conversationID == scope.conversationID else { throw APIError.invalidRequest }
        _ = try APIConfiguration(baseURL: realm)
        self.creationOwner = reference == nil
        self.scope = scope; self.reference = reference; self.client = client; self.reader = reader; self.journal = journal
        ownerKey = [namespace, realm.absoluteString, String(scope.identity.accountID)].map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        if reference == nil, isLocked(createTarget) { phase = .unknown }
    }
    private func isLocked(_ target: String) -> Bool {
        do { return try journal.pending(ownerKey: ownerKey, targetKey: target) != nil } catch { return true }
    }
    private func changed() { onChange?() }
    private func current(_ generation: UInt64) -> Bool { isCurrent && self.generation == generation && !Task.isCancelled }
    /// Reads are explicit at detail entry / refresh. Results remain accessible to historical
    /// audience after leaving; failed membership refresh never erases that server permission.
    public func refresh() async {
        guard canRead, !isBusy, let reference else { return }
        generation &+= 1; let request = generation
        phase = .loading; activeMembership = false; changed()
        do {
            let value = try await client.result(reference, expectedIdentity: scope.identity)
            guard current(request) else { return }
            try value.validate(reference: reference, conversationID: scope.conversationID, results: true)
            poll = value
            try resolveProvenLocks(value)
            activeMembership = (try? await membership()) == true
            guard current(request) else { return }
            phase = unresolved(value) ? .unknown : .idle
        } catch {
            guard current(request) else { return }
            poll = nil; activeMembership = false
            phase = (error as? MessagingReadFailure)?.code == 403 || (error as? MessagingReadFailure)?.code == 404 ? .blocked : .failed
        }
        changed()
    }
    private func membership() async throws -> Bool {
        guard isCurrent, reader.isConfigured else { return false }
        let rows = try await reader.messagingConversations()
        guard isCurrent, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
        return rows.contains { $0.id == scope.conversationID && $0.supportsGroupPolls }
    }
    public func reviewCreate(question: String, options: [String], deadline: Date?) async {
        guard canCreate, let draft = try? GroupPollDraft(conversationID: scope.conversationID, question: question, options: options, deadline: deadline) else { return }
        generation &+= 1; let request = generation; phase = .loading; changed()
        do {
            let member = try await membership()
            guard current(request) else { return }
            activeMembership = member
            guard member, !isLocked(createTarget) else { phase = .blocked; changed(); return }
            phase = .reviewing(.create(draft))
        } catch { if current(request) { phase = .failed } }
        changed()
    }
    public func reviewVote(optionID: Int) {
        guard canVote, let poll, poll.options.contains(where: { $0.id == optionID }) else { return }
        phase = .reviewing(.vote(pollID: poll.id, optionID: optionID)); changed()
    }
    public func reviewClose() {
        guard canClose, let poll else { return }
        phase = .reviewing(.close(pollID: poll.id, expectedVersion: poll.version)); changed()
    }
    public func resume() {
        if creationOwner, isCurrent, reference == nil, phase == .unknown, !isLocked(createTarget) {
            pendingMutation = nil; phase = .idle; changed()
        }
    }
    public var canStartAnother: Bool { creationOwner && isCurrent && reference != nil && !isBusy && phase != .unknown && !isLocked(createTarget) }
    public func startAnother() {
        guard canStartAnother else { return }
        poll = nil; reference = nil; pendingMutation = nil; activeMembership = false; phase = .idle; changed()
    }
    public func cancelReview() {
        if case .reviewing = phase { phase = .idle; changed() }
    }
    /// Dismissal drops drafts/reviews and invalidates reads/preflight. A dispatched request
    /// keeps its journal lock; returning never resubmits it automatically.
    public func suspend() {
        generation &+= 1; activeMembership = false
        switch phase {
        case .reviewing, .loading: phase = .idle
        case .submitting: phase = pendingMutation == nil ? .idle : .unknown
        default: break
        }
        changed()
    }
    public func confirm() async {
        guard isCurrent, case .reviewing(let mutation) = phase else { return }
        await dispatch(mutation, retryCreate: false)
    }
    /// Only creation has a source idempotency key. Vote/close unknown outcomes offer
    /// result refresh only; an OPEN/no-vote read does not prove an in-flight write failed.
    public var canRetryCreation: Bool {
        guard isCurrent, phase == .unknown, let pendingMutation, case .create = pendingMutation else { return false }
        return client.permits("api/im/poll/create") && canRead
    }
    public func retryCreationUnchanged() async {
        guard canRetryCreation, let mutation = pendingMutation else { return }
        await dispatch(mutation, retryCreate: true)
    }
    private func dispatch(_ mutation: GroupPollMutation, retryCreate: Bool) async {
        guard isCurrent, client.permits(mutation.path), canRead, !Task.isCancelled else { return }
        generation &+= 1; let request = generation
        phase = .submitting; changed()
        var record: OperationPendingRecord?
        do {
            // Fresh server results and fresh membership precede every mutation. Reviewed
            // version/choice remains immutable; a changed poll returns to explicit review.
            if let reference {
                let latest = try await client.result(reference, expectedIdentity: scope.identity)
                guard current(request) else { return }
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
            let member = try await membership()
            guard current(request) else { return }
            activeMembership = member
            guard member else { throw MessagingReadFailure(code: 403) }
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
                try journal.write(fresh)
                guard try journal.pending(ownerKey: ownerKey, targetKey: target) == fresh else { throw APIError.malformedResponse }
                record = fresh
            }
            pendingMutation = mutation
            // A durable journal implementation may synchronously invalidate its owner.
            // Keep the written lock but never dispatch after that ownership boundary.
            guard current(request), phase == .submitting else { phase = .unknown; changed(); return }
            let receipt = try await client.perform(mutation, scope: scope, reference: reference)
            guard current(request) else { phase = .unknown; changed(); return }
            try receipt.validate(reference: reference, conversationID: scope.conversationID, results: mutation.path != "api/im/poll/create")
            try receipt.validateReceipt(mutation, scope: scope)
            if let record { try journal.clear(record) }
            pendingMutation = nil; poll = receipt; reference = GroupPollReference(poll: receipt); phase = .acknowledged
            // Create response's option zeros are NOT result counts. The view explicitly
            // refreshes via /result before offering a vote or rendering a total.
        } catch {
            guard current(request) else { phase = record == nil ? .idle : .unknown; changed(); return }
            if record == nil { phase = .rejected }
            else if let failure = error as? MessagingReadFailure, failure.httpStatus == nil, let code = failure.code, [400, 401, 403, 404].contains(code) {
                do { if let record { try journal.clear(record) }; pendingMutation = nil; phase = .rejected } catch { phase = .unknown }
            } else { phase = .unknown }
            if (error as? MessagingReadFailure)?.code == 403 { activeMembership = false }
        }
        changed()
    }
    private func unresolved(_ poll: GroupPoll) -> Bool { isLocked(voteTarget(poll.id)) || isLocked(closeTarget(poll.id)) }
    private func resolveProvenLocks(_ poll: GroupPoll) throws {
        if poll.myOptionId != nil || poll.status == "CLOSED", let record = try journal.pending(ownerKey: ownerKey, targetKey: voteTarget(poll.id)) { try journal.clear(record) }
        if poll.status == "CLOSED", let record = try journal.pending(ownerKey: ownerKey, targetKey: closeTarget(poll.id)) { try journal.clear(record) }
        // Reopening the real message can reconcile an uncertain create after relaunch.
        if poll.creatorMemberId == scope.identity.accountID,
           let record = try journal.pending(ownerKey: ownerKey, targetKey: createTarget),
           poll.clientPollKey == record.operationID.uuidString.lowercased() { try journal.clear(record) }
        if !unresolved(poll) { pendingMutation = nil }
    }
}
