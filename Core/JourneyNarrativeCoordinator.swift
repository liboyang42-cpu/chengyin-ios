import Foundation
import Observation

public struct JourneyAskReview: Identifiable, Equatable {
    public let id = UUID()
    public let scope: JourneyNarrativeScope
    public let question: JourneyQuestion
    public let projection: JourneyQuestionsDocument
    let session: PlayExperienceSession
    fileprivate init(scope: JourneyNarrativeScope, question: JourneyQuestion, projection: JourneyQuestionsDocument, session: PlayExperienceSession) {
        self.scope = scope; self.question = question; self.projection = projection; self.session = session
    }
}
@MainActor @Observable public final class JourneyNarrativeCoordinator {
    public let scope: JourneyNarrativeScope
    public let query: JourneyNarrativeQuery
    private let service: JourneyNarrativeService
    private let currentSession: () -> PlayExperienceSession?
    private let journal: (any JourneyNarrativeJournal)?
    private let unauthorized: (PlayExperienceSession) -> Void
    private var owner: PlayExperienceSession?
    private var generation: UInt64 = 0
    private var storedDocument: JourneyNarrativeDocument?
    private var storedReview: JourneyAskReview?
    private var storedReceipt: JourneyAskReceipt?
    private var storedPending = Set<String>()
    // A caller cannot observe the previous owner's data between an authentication
    // callback and the next SwiftUI task/synchronize pass.
    private var hasCurrentOwner: Bool { owner != nil && owner == currentSession() }
    public var document: JourneyNarrativeDocument? { hasCurrentOwner ? storedDocument : nil }
    public var review: JourneyAskReview? { hasCurrentOwner ? storedReview : nil }
    public var receipt: JourneyAskReceipt? { hasCurrentOwner ? storedReceipt : nil }
    public var pending: Set<String> { hasCurrentOwner ? storedPending : [] }
    public private(set) var busy = false
    public private(set) var issue: String?
    public private(set) var acknowledgedRevision: UInt64 = 0
    public var identity: String? { currentSession().map { "\($0.namespace):\($0.accountID):\($0.epoch)" } }
    public var available: Bool { service.readsEnabled && currentSession() != nil }
    public var canAsk: Bool {
        guard available, service.asksEnabled, journal?.isDurable == true, !busy, owner == currentSession(),
              let document, case .questions(let projection) = document else { return false }
        return projection.allowsAsking
    }
    public init(scope: JourneyNarrativeScope, query: JourneyNarrativeQuery, service: JourneyNarrativeService,
                journal: (any JourneyNarrativeJournal)? = nil, currentSession: @escaping () -> PlayExperienceSession?,
                onUnauthorized: @escaping (PlayExperienceSession) -> Void = { _ in }) {
        self.scope = scope; self.query = query; self.service = service; self.journal = journal
        self.currentSession = currentSession; unauthorized = onUnauthorized
    }
    public func synchronize() {
        if owner != currentSession() { generation &+= 1; owner = currentSession(); storedDocument = nil; storedReview = nil; storedReceipt = nil; storedPending = []; issue = nil; busy = false }
    }
    public func dismiss() { generation &+= 1; storedReview = nil; storedReceipt = nil; storedDocument = nil; busy = false }
    public func cancelReview() { guard !busy else { return }; generation &+= 1; storedReview = nil }
    public func load() async {
        synchronize(); guard !busy else { return }; generation &+= 1; let revision = generation
        storedReview = nil; storedDocument = nil; issue = nil; busy = true
        defer { if revision == generation { busy = false } }
        guard let captured = currentSession(), available else { issue = "journey.record.disabled"; return }
        do {
            let result = try await service.read(query, scope: scope, token: captured.token)
            try check(captured, revision)
            if case .questions(let projection) = result, let journal {
                let saved = try journal.pending(owner: captured, scope: scope, realm: service.realm, runID: projection.runID, nodeID: projection.nodeID)
                try check(captured, revision)
                let unresolved = saved.subtracting(projection.questions.filter(\.asked).map(\.id))
                if saved != unresolved { try journal.save(unresolved, owner: captured, scope: scope, realm: service.realm, runID: projection.runID, nodeID: projection.nodeID) }
                try check(captured, revision)
                storedPending = unresolved
            }
            storedDocument = result
        } catch { fail(error, captured, revision) }
    }
    public func prepare(_ id: String) {
        synchronize()
        guard canAsk, !pending.contains(id), let owner, let document,
              case .questions(let projection) = document,
              let question = projection.questions.first(where: { $0.id == id }), !question.asked else { issue = "journey.record.unavailableAction"; return }
        generation &+= 1; storedReceipt = nil; issue = nil
        storedReview = .init(scope: scope, question: question, projection: projection, session: owner)
    }
    public func confirm(_ approved: JourneyAskReview) async {
        synchronize()
        guard canAsk, review == approved, currentSession() == approved.session, let journal else { return }
        let revision = generation; busy = true; issue = nil
        defer { if revision == generation { busy = false } }
        var dispatched = false
        do {
            let current = try await service.read(.questions(nodeID: approved.projection.nodeID), scope: scope, token: approved.session.token)
            try check(approved.session, revision)
            guard case .questions(let fresh) = current, fresh == approved.projection, review == approved else { throw PlayExperienceError.staleSession }
            var saved = try journal.pending(owner: approved.session, scope: scope, realm: service.realm, runID: fresh.runID, nodeID: fresh.nodeID)
            try check(approved.session, revision)
            guard !saved.contains(approved.question.id) else { throw PlayExperienceError.unknownResult }
            saved.insert(approved.question.id)
            try journal.save(saved, owner: approved.session, scope: scope, realm: service.realm, runID: fresh.runID, nodeID: fresh.nodeID)
            try check(approved.session, revision)
            storedPending = saved; storedReview = nil
            dispatched = true
            let result = try await service.ask(scope: scope, nodeID: fresh.nodeID, questionID: approved.question.id, token: approved.session.token)
            try check(approved.session, revision)
            // A valid matched receipt is authoritative; it does not claim node completion.
            guard result.stateVersion >= fresh.version else { throw PlayExperienceError.malformed }
            saved.remove(approved.question.id)
            try journal.save(saved, owner: approved.session, scope: scope, realm: service.realm, runID: fresh.runID, nodeID: fresh.nodeID)
            try check(approved.session, revision)
            storedPending = saved; storedReceipt = result; acknowledgedRevision &+= 1
            // Readback failure must not erase the acknowledged answer or replay the action.
            do { let refreshed = try await service.read(query, scope: scope, token: approved.session.token); try check(approved.session, revision); storedDocument = refreshed }
            catch { try check(approved.session, revision); storedDocument = nil; issue = "journey.record.readbackFailed"; if error as? PlayExperienceError == .unauthorized { unauthorized(approved.session) } }
        } catch {
            if revision == generation, currentSession() == approved.session {
                storedReview = nil; storedDocument = nil
                issue = dispatched ? "journey.record.unknown" : "journey.record.stale"
                if error as? PlayExperienceError == .unauthorized { unauthorized(approved.session) }
            }
        }
    }
    private func check(_ captured: PlayExperienceSession, _ revision: UInt64) throws {
        guard currentSession() == captured, owner == captured, generation == revision, !Task.isCancelled else { throw PlayExperienceError.staleSession }
    }
    private func fail(_ error: Error, _ captured: PlayExperienceSession, _ revision: UInt64) {
        guard currentSession() == captured, generation == revision else { return }
        issue = error as? PlayExperienceError == .disabled ? "journey.record.disabled" : "journey.record.failed"
        if error as? PlayExperienceError == .unauthorized { unauthorized(captured) }
    }
}
