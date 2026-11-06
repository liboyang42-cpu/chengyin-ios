import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// CHECK-only continuation of an already-issued PLAN operation. No start/RETRY,
/// branch-choice, album, fabricated dice or fabricated settled outcome route.
@available(macOS 14.0, *)
@MainActor @Observable final class PlaySharedPlanR5Recovery {
    private(set) var projection: PlaySharedPlanR5Projection?
    private(set) var outcome: PlaySharedPlanR5Outcome?
    private(set) var pending: PlayAdvancedPending?
    private(set) var acknowledged = false
    private(set) var busy = false
    private(set) var issue: PlayExperienceError?
    private let owner: PlayExperienceSession
    private let ticket: PlaySharedPlanOperationTicket
    private let topicID: Int
    private let service: PlayExperienceService
    private let outcomeService: PlayExperienceService
    private let onUnauthorized: () -> Void
    private let journal: any PlayAdvancedRecovery
    private let retainSessionCursor: Bool
    private let current, approvedWriteAndOriginalProof: () -> Bool
    private let validateOperation: () async throws -> Void
    private var generation: UInt64 = 0
    init(owner: PlayExperienceSession, ticket: PlaySharedPlanOperationTicket, topicID: Int,
         service: PlayExperienceService, outcomeService: PlayExperienceService, journal: any PlayAdvancedRecovery,
         current: @escaping () -> Bool, retainSessionCursor: Bool = false, approvedWriteAndOriginalProof: @escaping () -> Bool = { false },
         validateOperation: @escaping () async throws -> Void, onUnauthorized: @escaping () -> Void = {}) {
        self.owner = owner; self.ticket = ticket; self.topicID = topicID; self.journal = journal; self.retainSessionCursor = retainSessionCursor
        let operationGuard: () async throws -> Void = {
            guard current(), owner.role == "player", ticket.memberID == owner.accountID else { throw PlayExperienceError.staleSession }
            try service.checkReadLifetime(); try await validateOperation()
            guard current() else { throw PlayExperienceError.staleSession }
            try service.checkReadLifetime()
        }
        self.service = .init(configuration: service.configuration,
            transport: SharedPlanR5ScopedTransport(underlying: service.transport, baseURL: service.configuration.baseURL,
                outcomeOnly: false, current: current, write: approvedWriteAndOriginalProof, validate: operationGuard), enabled: service.enabled)
        self.outcomeService = .init(configuration: outcomeService.configuration,
            transport: SharedPlanR5ScopedTransport(underlying: outcomeService.transport, baseURL: outcomeService.configuration.baseURL,
                outcomeOnly: true, current: current, write: { false }, validate: {
                    guard current(), owner.role == "player" else { throw PlayExperienceError.staleSession }
                    try outcomeService.checkReadLifetime()
                }), enabled: outcomeService.enabled); self.onUnauthorized = onUnauthorized
        self.current = current; self.approvedWriteAndOriginalProof = approvedWriteAndOriginalProof; self.validateOperation = validateOperation
    }
    private var scope: PlayAdvancedRecoveryScope { get throws { try .init(activityID: ticket.activityID, topicID: topicID, nodeID: ticket.nodeID) } }
    private var writable: Bool { current() && owner.role == "player" && approvedWriteAndOriginalProof() && service.enabled.contains(.advanced) }
    private func check(_ issued: UInt64) throws {
        try Task.checkCancellation()
        guard generation == issued, current(), owner.role == "player", ticket.memberID == owner.accountID else { throw PlayExperienceError.staleSession }
        try service.checkReadLifetime()
    }
    private func requestService(_ issued: UInt64, outcome: Bool = false) -> PlayExperienceService {
        let source = outcome ? outcomeService : service
        return .init(configuration: source.configuration,
            transport: SharedPlanR5ScopedTransport(underlying: source.transport, baseURL: source.configuration.baseURL,
                outcomeOnly: outcome, current: { self.generation == issued && self.current() },
                write: { self.writable }, validate: { try self.check(issued) }), enabled: source.enabled)
    }
    func suspend() { generation &+= 1; projection = nil; outcome = nil; pending = nil; acknowledged = false; busy = false }
    private func restore(_ issued: UInt64) async throws -> PlayAdvancedRecoverySnapshot? {
        let saved = try await journal.read(); try check(issued)
        if let saved {
            try saved.value.validate(session: owner, scope: scope)
            if saved.value.phase == .started, let start = saved.value.sharedPlanStart {
                guard start == PlaySharedPlanStartBinding(ticket: ticket, topicID: topicID), saved.value.sessionID != nil else { throw PlayExperienceError.staleSession }
                pending = nil; acknowledged = false; return saved
            }
            guard let binding = saved.value.sharedPlanR5, binding.matches(ticket), let command = saved.value.pending else {
                throw PlayExperienceError.persistenceUnavailable
            }
            pending = command; acknowledged = saved.value.phase == .acknowledged
        } else { pending = nil; acknowledged = false }
        return saved
    }
    private func read(_ sessionID: Int, issued: UInt64) async throws -> PlaySharedPlanR5Projection {
        try check(issued); try await validateOperation(); try check(issued)
        let raw = try await requestService(issued).request("api/play/advanced/state", query: ["sessionId": String(sessionID)], capability: .reads, token: owner.token)
        try check(issued)
        let value = try PlaySharedPlanR5Projection(raw, ticket: ticket, topicID: topicID)
        guard value.identity.advancedSessionID == sessionID else { throw PlayExperienceError.malformed }
        return value
    }
    func load(sessionID: Int) async {
        guard !busy else { return }; let issued = generation; busy = true; issue = nil
        defer { if generation == issued { busy = false } }
        do {
            try check(issued); let saved = try await restore(issued)
            let id = saved?.value.sessionID ?? sessionID
            let fresh = try await read(id, issued: issued)
            if let binding = saved?.value.sharedPlanR5, binding != fresh.identity { throw PlayExperienceError.staleSession }
            projection = fresh
            // Current state, even a higher version/PASS, cannot acknowledge an original action.
            if pending != nil && !acknowledged { issue = .unknownResult }
            await readOutcome(fresh.identity, issued: issued)
        } catch { fail(error, issued: issued) }
    }
    private func readOutcome(_ identity: PlaySharedPlanR5Identity, issued: UInt64) async {
        do {
            try check(issued)
            let raw = try await requestService(issued, outcome: true).request("api/game/session/view", query: ["activityId": String(ticket.activityID), "perspective": "PLAYER"], capability: .reads, token: owner.token)
            try check(issued); outcome = try PlaySharedPlanR5Outcome(raw, identity: identity)
        } catch {
            if generation == issued {
                outcome = nil
                if case PlayExperienceError.unauthorized = error { fail(error, issued: issued) }
            }
        }
    }
    struct Review: Equatable {
        let id: UUID
        let action: String
        let source: PlaySharedPlanR5Projection
    }
    func canReview(_ action: String) -> Bool {
        writable && !busy && (pending == nil || retainSessionCursor && acknowledged) && projection?.allowedActions.contains(action) == true
    }
    var canRetryOriginal: Bool { writable && !busy && pending != nil && !acknowledged }
    func review(_ action: String) throws -> Review {
        guard canReview(action), let projection else { throw PlayExperienceError.disabled }
        return .init(id: UUID(), action: action, source: projection)
    }
    func commit(_ review: Review) async {
        guard writable, !busy else { return }; let issued = generation; busy = true; issue = nil
        defer { if generation == issued { busy = false } }
        do {
            let prior = try await restore(issued)
            guard prior == nil || prior?.value.phase == .started && prior?.value.sharedPlanStart != nil
                || retainSessionCursor && prior?.value.phase == .acknowledged else { throw PlayExperienceError.unknownResult }
            let fresh = try await read(review.source.identity.advancedSessionID, issued: issued)
            guard fresh == review.source, fresh.allowedActions.contains(review.action), writable else { throw PlayExperienceError.staleSession }
            let command = PlayAdvancedPending(sessionID: fresh.identity.advancedSessionID, version: fresh.version,
                key: review.id.uuidString, action: review.action, payload: [:])
            let record = try PlayAdvancedRecoveryRecord(session: owner, scope: scope, pending: command, requestedCard: false, sharedPlanR5: fresh.identity)
            let saved = try await journal.prepare(record); try check(issued)
            guard saved.value == record else { throw PlayExperienceError.persistenceUnavailable }; pending = command
            try await dispatch(saved, issued: issued)
        } catch { fail(error, issued: issued) }
    }
    /// Explicit exact replay only, after review by the eventual host. Never called by load.
    func retryOriginal() async {
        guard writable, !busy else { return }; let issued = generation; busy = true; issue = nil
        defer { if generation == issued { busy = false } }
        do {
            guard let saved = try await restore(issued), saved.value.phase != .acknowledged,
                  let binding = saved.value.sharedPlanR5 else { throw PlayExperienceError.unknownResult }
            let fresh = try await read(binding.advancedSessionID, issued: issued)
            guard fresh.identity == binding, writable else { throw PlayExperienceError.staleSession }
            let replayLease: PlayAdvancedRecoverySnapshot
            if saved.value.phase == .dispatching, saved.value.dispatchProcess == journal.processID {
                // An explicit retry may race the old in-flight response, but it retains
                // the identical server idempotency identity. CAS prevents either old
                // completion from retiring the newer lease. Never make a replacement ID.
                replayLease = try await journal.transition(saved, to: .unknown, startedSessionID: nil)
                try check(issued)
            } else { replayLease = saved }
            try await dispatch(replayLease, issued: issued)
        } catch { fail(error, issued: issued) }
    }
    private func dispatch(_ saved: PlayAdvancedRecoverySnapshot, issued: UInt64) async throws {
        try check(issued); try await validateOperation(); try check(issued)
        guard writable, let binding = saved.value.sharedPlanR5, let command = saved.value.pending else { throw PlayExperienceError.disabled }
        let sent = try await journal.transition(saved, to: .dispatching, startedSessionID: nil)
        do {
            try check(issued); guard writable else { throw PlayExperienceError.disabled }
            let raw = try await requestService(issued).request("api/play/advanced/action", json: ["sessionId": .int(command.sessionID),
                "version": .int(command.version), "idempotencyKey": .string(command.key), "action": .string(command.action),
                "payload": .object(command.payload)], capability: .advanced, token: owner.token)
            try check(issued)
            let value = try PlaySharedPlanR5Projection(raw, ticket: ticket, topicID: topicID)
            guard value.identity == binding, value.proves(raw, pending: command, memberID: owner.accountID) else { throw PlayExperienceError.unknownResult }
            _ = try await journal.transition(sent, to: .acknowledged, startedSessionID: nil); try check(issued)
            acknowledged = true; projection = value
            await readOutcome(binding, issued: issued)
        } catch {
            // Exact CAS only. A newer owner/lease cannot be replaced by this failed dispatch.
            if generation == issued, current() { _ = try? await journal.transition(sent, to: .unknown, startedSessionID: nil) }
            throw error
        }
    }
    /// Acknowledgement was persisted from the matching actor/request proof, not world outcome.
    func retireAcknowledged() async {
        guard writable, !busy else { return }; let issued = generation; busy = true
        defer { if generation == issued { busy = false } }
        do {
            guard let saved = try await restore(issued), saved.value.phase == .acknowledged,
                  let binding = saved.value.sharedPlanR5 else { throw PlayExperienceError.unknownResult }
            let fresh = try await read(binding.advancedSessionID, issued: issued)
            guard fresh.identity == binding, let command = saved.value.pending,
                  fresh.version >= command.version + 1, writable else { throw PlayExperienceError.staleSession }
            if !retainSessionCursor { try await journal.clear(saved); try check(issued) }
            // The normal PLAN host keeps the acknowledged original as its restart
            // cursor. Its next explicit action atomically replaces this exact slot.
            pending = nil; acknowledged = false; projection = fresh
        } catch { fail(error, issued: issued) }
    }
    private func fail(_ error: Error, issued: UInt64) {
        guard generation == issued else { return }
        if !current() { suspend(); return }
        if case PlayExperienceError.unauthorized = error { projection = nil; outcome = nil; onUnauthorized() }
        issue = error as? PlayExperienceError ?? .unknownResult
    }
}

/// Final transport fence; the state machine's earlier check is not sufficient
/// if authorization changes while awaiting journal storage or an operation read.
@MainActor private final class SharedPlanR5ScopedTransport: HTTPTransport {
    let underlying: any HTTPTransport
    let baseURL: URL
    let outcomeOnly: Bool
    let current, write: () -> Bool
    let validate: () async throws -> Void
    init(underlying: any HTTPTransport, baseURL: URL, outcomeOnly: Bool,
         current: @escaping () -> Bool, write: @escaping () -> Bool, validate: @escaping () async throws -> Void) {
        self.underlying = underlying; self.baseURL = baseURL; self.outcomeOnly = outcomeOnly
        self.current = current; self.write = write; self.validate = validate
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let url = request.url, var route = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
        route.query = nil; route.fragment = nil
        let expected = outcomeOnly ? "api/game/session/view" : request.httpMethod == "POST" ? "api/play/advanced/action" : "api/play/advanced/state"
        guard route.url == baseURL.appendingPathComponent(expected),
              request.httpMethod == (expected.hasSuffix("/action") ? "POST" : "GET") else { throw PlayExperienceError.disabled }
        try await validate()
        guard current(), request.httpMethod != "POST" || write() else { throw PlayExperienceError.disabled }
        let result = try await underlying.send(request)
        guard current() else { throw PlayExperienceError.staleSession }
        return result
    }
}
