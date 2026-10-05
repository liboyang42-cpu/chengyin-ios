import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


/// A single request attempt, created only by the coordinator after an exact journal readback.
/// It is not Codable, has no public/internal constructor or reset, and remains consumed on error.
/// Retrying requires the coordinator to advance the same immutable pending mutation again.
@MainActor public final class ContentDraftPreparedDispatch: CustomStringConvertible, CustomDebugStringConvertible {
    public let mutation: ContentDraftMutation
    let route: ContentDraftRoute
    let body: Data
    private let url: URL
    private let lease: ContentDraftSessionLease
    private let journal: any ContentDraftSecureJournal
    private let snapshot: ContentDraftJournalSnapshot
    private let isCurrent: () -> Bool
    private var started = false
    private var retired = false
    fileprivate init(snapshot: ContentDraftJournalSnapshot, journal: any ContentDraftSecureJournal,
                     lease: ContentDraftSessionLease, isCurrent: @escaping () -> Bool) throws {
        try lease.check()
        try snapshot.value.mutation.validate()
        guard snapshot.value.dispatched, snapshot.generation.count == 32,
              journal.scope == ContentDraftJournalScope(context: lease.context, identity: snapshot.value.mutation.identity),
              isCurrent() else { throw ContentDraftIssue.storageUnavailable }
        self.snapshot = snapshot; self.journal = journal; self.lease = lease; self.isCurrent = isCurrent
        mutation = snapshot.value.mutation
        route = mutation.kind == .save ? .save : .delete
        url = lease.context.baseURL.appendingPathComponent(route.path)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        body = try encoder.encode(mutation.command)
    }
    fileprivate func retire() { retired = true }
    /// The real service invokes this once, at the final transport boundary. A mismatch burns
    /// the attempt too. No caller can pair a valid attempt with a new operation, body or path.
    func consume(request: URLRequest, lease: ContentDraftSessionLease, transport: any HTTPTransport) async throws {
        guard !started, !retired else { throw ContentDraftIssue.storageUnavailable }
        started = true
        // Arbitrary protocol conformance is not evidence of persistence. Only the sealed
        // fixed-storage adapter can authorize network-capable transports. The final recorder
        // has no network implementation and cannot be subclassed or wrap another transport.
        guard transport is ContentDraftRecordingTransport ||
              (journal as? ContentDraftDurableJournal)?.isSystemBacked == true else { throw ContentDraftIssue.storageUnavailable }
        guard self.lease === lease else { throw ContentDraftIssue.staleSession }
        try lease.check()
        guard isCurrent() else { throw ContentDraftIssue.staleSession }
        guard request.url?.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) == true,
              request.httpMethod == "POST", request.httpBody == body,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(lease.context.session.token.utf8) == true,
              journal.scope == ContentDraftJournalScope(context: lease.context, identity: mutation.identity),
              try await journal.read() == snapshot else { throw ContentDraftIssue.storageUnavailable }
        try checkDispatchLifetime()
    }
    /// Separate from one-attempt consumption: retirement during a suspended read must win.
    /// Rechecked after the service's final grant-clock callback and immediately before send.
    func checkDispatchLifetime() throws {
        guard started, !retired else { throw ContentDraftIssue.storageUnavailable }
        try lease.check()
        guard isCurrent(), !retired else { throw ContentDraftIssue.staleSession }
    }
    public nonisolated var description: String { "ContentDraftPreparedDispatch[redacted]" }
    public nonisolated var debugDescription: String { description }
}

@available(macOS 14.0, *)
@MainActor @Observable public final class ContentDraftCoordinator<Payload: Codable & Equatable> {
    public enum Phase: String { case idle, loading, ready, review, sending, conflict, unknown, blocked, deleted, invalidated }
    public private(set) var phase: Phase = .idle
    public private(set) var document: ContentDraftDocument<Payload>?
    public private(set) var localPayload: Payload?
    public private(set) var cloudConflict: ContentDraftDocument<Payload>?
    public private(set) var review: ContentDraftMutation?
    public private(set) var issue: ContentDraftIssue?
    private var pending: ContentDraftJournalSnapshot?
    private var journalLoaded = false
    private let identity: ContentDraftIdentity
    private let initialServerID: Int64?
    private let service: any ContentDraftServing
    private let lease: ContentDraftSessionLease
    private let journal: (any ContentDraftSecureJournal)?
    private let journalScope: ContentDraftJournalScope
    private var generation = UUID()

    public init(identity: ContentDraftIdentity, serverDraftID: Int64? = nil, initialPayload: Payload? = nil,
                service: any ContentDraftServing, lease: ContentDraftSessionLease,
                journal: (any ContentDraftSecureJournal)? = nil) {
        self.identity = identity; initialServerID = serverDraftID; localPayload = initialPayload
        self.service = service; self.lease = lease; self.journal = journal
        journalScope = .init(context: lease.context, identity: identity)
    }
    public var canPrepare: Bool { lease.isCurrent && phase == .ready && pending == nil && journalLoaded && journal != nil }
    public var canRetryExact: Bool { lease.isCurrent && phase == .unknown && pending != nil && journal != nil }
    public var hasUncertainMutation: Bool { pending?.value.dispatched == true }
    private var busy: Bool { phase == .loading || phase == .sending }
    private func gate(_ ticket: UUID? = nil) -> Bool {
        guard ticket == nil || ticket == generation else { return false }
        guard lease.isCurrent else { invalidate(); return false }
        return phase != .invalidated
    }
    /// Host must call this for session lifetime changes; pending durable records are deliberately retained.
    public func invalidate() {
        lease.revoke(); generation = UUID(); document = nil; localPayload = nil; cloudConflict = nil
        review = nil; pending = nil; journalLoaded = false; issue = .staleSession; phase = .invalidated
    }
    private func checkedJournal() throws -> any ContentDraftSecureJournal {
        guard let journal, journal.scope == journalScope else { throw ContentDraftIssue.storageUnavailable }
        return journal
    }
    public func initialize() async {
        guard gate(), phase == .idle || phase == .blocked else { return }
        let ticket = generation; phase = .loading
        do {
            try identity.validate()
            if let journal {
                guard journal.scope == journalScope else { throw ContentDraftIssue.storageUnavailable }
                let stored = try await journal.read()
                guard gate(ticket) else { return }
                if let stored {
                    try stored.value.mutation.validate()
                    guard stored.value.mutation.identity == identity,
                          initialServerID == nil || initialServerID == stored.value.mutation.command.id else { throw ContentDraftIssue.storageUnavailable }
                }
                pending = stored; journalLoaded = true
            }
            if pending != nil {
                // Restored in-flight intent is never silently replaced with the editor's startup values.
                localPayload = nil; phase = .unknown; issue = .unknownOutcome; return
            }
            if let id = initialServerID {
                let value = try await service.restore(id: id, identity: identity)
                guard value.id == id, value.status == .draft else { throw ContentDraftIssue.malformed }
                let typed = try ContentDraftDocument<Payload>(record: value, identity: identity)
                guard gate(ticket) else { return }
                document = typed; localPayload = typed.payload
            }
            guard gate(ticket) else { return }
            phase = .ready; issue = nil
        } catch {
            guard gate(ticket) else { return }
            issue = (error as? ContentDraftIssue) ?? .storageUnavailable; phase = .blocked
        }
    }
    public func prepareSave(_ payload: Payload, subjectID: Int64?, deviceID: String) {
        guard canPrepare else { return }
        do {
            let mutation = try ContentDraftMutation.save(payload: payload, identity: identity,
                subjectID: subjectID, deviceID: deviceID, baseline: document?.record)
            localPayload = payload; review = mutation; issue = nil; phase = .review
        } catch { issue = .invalid }
    }
    public func prepareDelete() {
        guard canPrepare, let document else { return }
        do { review = try .delete(identity: identity, baseline: document.record); issue = nil; phase = .review }
        catch { issue = .invalid }
    }
    public func cancelReview() { guard gate(), phase == .review else { return }; review = nil; phase = .ready }
    public func confirm() async {
        guard gate(), phase == .review, let review else { return }
        let ticket = generation; phase = .sending
        do {
            let journal = try checkedJournal(), stored = ContentDraftPending(mutation: review)
            let snapshot = try await journal.insert(stored)
            guard gate(ticket) else { return }
            guard snapshot.value == stored else { throw ContentDraftIssue.storageUnavailable }
            guard try await journal.read() == snapshot else { throw ContentDraftIssue.storageUnavailable }
            guard gate(ticket) else { return }
            pending = snapshot; self.review = nil; phase = .review
        } catch { guard gate(ticket) else { return }; issue = .storageUnavailable; phase = .blocked; return }
        await dispatchPending()
    }
    public func retryExact() async { guard canRetryExact else { return }; await dispatchPending() }
    private func dispatchPending() async {
        guard gate(), !busy, let original = pending else { return }
        let ticket = generation; phase = .sending
        let journal: any ContentDraftSecureJournal
        let dispatchedValue = ContentDraftPending(mutation: original.value.mutation, dispatched: true)
        let dispatched: ContentDraftJournalSnapshot
        do {
            journal = try checkedJournal()
            guard try await journal.read() == original else { throw ContentDraftIssue.storageUnavailable }
            guard gate(ticket) else { return }
            try original.value.mutation.validate()
            dispatched = try await journal.replace(original, with: dispatchedValue)
            guard gate(ticket) else { return }
            guard dispatched.value == dispatchedValue else { throw ContentDraftIssue.storageUnavailable }
            guard try await journal.read() == dispatched else { throw ContentDraftIssue.storageUnavailable }
            guard gate(ticket) else { return }
            pending = dispatched
        } catch { guard gate(ticket) else { return }; issue = .storageUnavailable; phase = .unknown; return }
        // Persist before HTTP. After process death this flag means "possibly sent", never permission for a new key.
        phase = .sending
        do {
            let attempt = try ContentDraftPreparedDispatch(snapshot: dispatched, journal: journal, lease: lease,
                isCurrent: { [weak self] in self?.gate(ticket) == true })
            defer { attempt.retire() }
            let receipt = try await service.mutate(attempt)
            try dispatched.value.mutation.validate(receipt: receipt)
            let typed = try ContentDraftDocument<Payload>(record: receipt, identity: identity)
            guard gate(ticket) else { return }
            try await journal.clear(matching: dispatched)
            guard gate(ticket) else { return }
            guard try await journal.read() == nil else { throw ContentDraftIssue.storageUnavailable }
            guard gate(ticket) else { return }
            pending = nil; review = nil; cloudConflict = nil; issue = nil
            if receipt.status == .deleted { document = nil; localPayload = nil; phase = .deleted }
            else { document = typed; localPayload = typed.payload; phase = .ready }
        } catch {
            guard gate(ticket) else { return }
            let problem = (error as? ContentDraftIssue) ?? .unknownOutcome
            // A definitive rejection of the FIRST attempt is safe to release. After any uncertain
            // attempt/crash, a later 409/404/403 cannot prove that the earlier write did not commit.
            let rejection = [ContentDraftIssue.conflict, .rejected, .forbidden, .notFound, .unauthorized].contains(problem)
            if !original.value.dispatched && rejection {
                do {
                    try await journal.clear(matching: dispatched)
                    guard gate(ticket) else { return }
                    guard try await journal.read() == nil else { throw ContentDraftIssue.storageUnavailable }
                    guard gate(ticket) else { return }
                    pending = nil; issue = problem; phase = problem == .conflict ? .conflict : .blocked
                } catch { guard gate(ticket) else { return }; issue = .storageUnavailable; phase = .unknown }
            } else { issue = problem; phase = .unknown }
        }
    }
    /// Readback for inspection/recovery only. Never claims to resolve an uncertain mutation.
    public func fetchLatestForConflict() async {
        guard gate(), !busy, phase == .conflict || phase == .unknown else { return }
        let id = document?.record.id ?? pending?.value.mutation.command.id ?? initialServerID
        let ticket = generation, previous = phase
        phase = .loading
        do {
            let record: ContentDraftRecord
            if let id {
                record = try await service.restore(id: id, identity: identity)
                guard record.id == id else { throw ContentDraftIssue.malformed }
            } else {
                // A duplicate create key has no assigned local ID. Discover its existing active record
                // through the real list route; finding it still cannot settle an unknown mutation.
                let values = try await service.list(type: identity.businessType)
                let matches = values.filter { $0.ownerMemberId == identity.ownerMemberID &&
                    $0.businessType == identity.businessType && $0.clientDraftKey.utf8.elementsEqual(identity.clientDraftKey.utf8) }
                guard matches.count == 1, let found = matches.first else { throw ContentDraftIssue.notFound }
                record = found
            }
            guard record.status == .draft else { throw ContentDraftIssue.malformed }
            let latest = try ContentDraftDocument<Payload>(record: record, identity: identity)
            guard gate(ticket) else { return }
            cloudConflict = latest; phase = previous
        } catch {
            guard gate(ticket) else { return }
            issue = (error as? ContentDraftIssue) ?? .unavailable; phase = previous
        }
    }
    /// Explicit user choice after a known conflict. This does not submit or publish anything.
    public func resolveConflict(useCloudPayload: Bool) {
        guard gate(), phase == .conflict, pending == nil, let latest = cloudConflict else { return }
        document = latest
        if useCloudPayload { localPayload = latest.payload }
        cloudConflict = nil; review = nil; issue = nil; phase = .ready
        // Keeping local edits rebases only the version. A NEW prepare/review/confirm is required.
    }
}
