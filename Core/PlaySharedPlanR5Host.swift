import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Persisted original PLAN start scope, not an authority grant or a guessed R5 identity.
public struct PlaySharedPlanStartBinding: Codable, Equatable {
    let activityID, topicID, nodeID, sourceNodeID, gameSessionID, teamID, memberID: Int
    let authorityEpoch, bindingVersion, round, operationReceiptID: Int
    let endingKey, proposalKey: String
    init(ticket: PlaySharedPlanOperationTicket, topicID: Int) {
        activityID = ticket.activityID; self.topicID = topicID; nodeID = ticket.nodeID; sourceNodeID = ticket.sourceNodeID
        gameSessionID = ticket.sessionID; teamID = ticket.teamID; memberID = ticket.memberID
        authorityEpoch = ticket.authorityEpoch; bindingVersion = ticket.bindingVersion; round = ticket.round
        operationReceiptID = ticket.receiptID; endingKey = ticket.endingKey; proposalKey = ticket.proposalKey
    }
    func validate(owner: PlayRecoveryOwner, scope: PlayAdvancedRecoveryScope) throws {
        guard owner.role == "player", owner.accountID == memberID,
              scope.activityID == activityID, scope.topicID == topicID, scope.nodeID == nodeID,
              [activityID, topicID, nodeID, sourceNodeID, gameSessionID, teamID, memberID, authorityEpoch,
               bindingVersion, round, operationReceiptID].allSatisfy({ $0 > 0 }),
              PlaySharedPlanAmount.validKey(endingKey), PlaySharedPlanAmount.validKey(proposalKey) else { throw PlayExperienceError.persistenceUnavailable }
    }
    func matches(_ identity: PlaySharedPlanR5Identity) -> Bool {
        activityID == identity.activityID && topicID == identity.topicID && nodeID == identity.nodeID
            && gameSessionID == identity.gameSessionID && teamID == identity.teamID && authorityEpoch == identity.authorityEpoch
            && bindingVersion == identity.bindingVersion && round == identity.round && operationReceiptID == identity.operationReceiptID
    }
}

@available(macOS 14.0, *)
@MainActor @Observable final class PlaySharedPlanR5Host {
    private(set) var phase = "idle"
    private(set) var issue: PlayExperienceError?
    private(set) var busy = false
    private(set) var sessionID: Int?
    private(set) var recovery: PlaySharedPlanR5Recovery?
    private let owner: PlayExperienceSession
    private let ticket: PlaySharedPlanOperationTicket
    private let topicID: Int
    private let service, outcomeService: PlayExperienceService
    private let journal: any PlayAdvancedRecovery
    private let current, approvedWriteAndOriginalProof: () -> Bool
    private let validateOperation: () async throws -> Void
    private let onUnauthorized: () -> Void
    private var generation: UInt64 = 0
    var canStart: Bool { phase == "readyToStart" && !busy && current() && approvedWriteAndOriginalProof() && service.enabled.contains(.advanced) }
    var approvalMissing: Bool { !approvedWriteAndOriginalProof() }
    init(owner: PlayExperienceSession, ticket: PlaySharedPlanOperationTicket, topicID: Int,
         service: PlayExperienceService, outcomeService: PlayExperienceService, journal: any PlayAdvancedRecovery,
         current: @escaping () -> Bool, approvedWriteAndOriginalProof: @escaping () -> Bool = { false },
         validateOperation: @escaping () async throws -> Void, onUnauthorized: @escaping () -> Void = {}) {
        self.owner = owner; self.ticket = ticket; self.topicID = topicID; self.service = service
        self.outcomeService = outcomeService; self.journal = journal; self.current = current
        self.approvedWriteAndOriginalProof = approvedWriteAndOriginalProof; self.validateOperation = validateOperation; self.onUnauthorized = onUnauthorized
    }
    private var binding: PlaySharedPlanStartBinding { .init(ticket: ticket, topicID: topicID) }
    private var scope: PlayAdvancedRecoveryScope { get throws { try .init(activityID: ticket.activityID, topicID: topicID, nodeID: ticket.nodeID) } }
    private func check(_ issued: UInt64) throws {
        try Task.checkCancellation()
        guard generation == issued, current(), owner.role == "player", ticket.memberID == owner.accountID else { throw PlayExperienceError.staleSession }
        try service.checkReadLifetime(); try binding.validate(owner: .init(session: owner), scope: scope)
    }
    func suspend() { generation &+= 1; recovery?.suspend(); recovery = nil; busy = false; phase = "stale" }
    func load() async {
        guard !busy else { return }; let issued = generation; busy = true; issue = nil
        defer { if generation == issued { busy = false } }
        do {
            try check(issued); let saved = try await journal.read(); try check(issued)
            guard let saved else { phase = "readyToStart"; return }
            try saved.value.validate(session: owner, scope: scope)
            if let start = saved.value.sharedPlanStart {
                guard start == binding else { throw PlayExperienceError.staleSession }
                if saved.value.phase == .starting { phase = "unknownStart"; issue = .unknownResult; return }
                guard saved.value.phase == .started, let id = saved.value.sessionID else { throw PlayExperienceError.persistenceUnavailable }
                try await openExisting(id, issued: issued)
            } else if let identity = saved.value.sharedPlanR5 {
                if !binding.matches(identity) {
                    guard saved.value.phase == .acknowledged else { throw PlayExperienceError.staleSession }
                    phase = "readyToStart"; return
                }
                try await openExisting(identity.advancedSessionID, issued: issued)
            } else { phase = "otherOriginalPending"; issue = .persistenceUnavailable }
        } catch { fail(error, issued: issued) }
    }
    /// User confirmation is the only start action. Opening/reopening a page cannot call it.
    func startConfirmed() async {
        guard canStart else { return }; let issued = generation; busy = true; issue = nil
        defer { if generation == issued { busy = false } }
        do {
            try check(issued); try await validateOperation(); try check(issued)
            guard approvedWriteAndOriginalProof() else { throw PlayExperienceError.disabled }
            let marker = try PlayAdvancedRecoveryRecord(session: owner, scope: scope, process: journal.processID, sharedPlanStart: binding)
            let stored = try await journal.prepare(marker); try check(issued)
            guard stored.value == marker else { throw PlayExperienceError.persistenceUnavailable }
            phase = "unknownStart" // Once persisted, no new start is allowed even if the request is interrupted.
            let transport = SharedPlanR5StartTransport(underlying: service.transport, baseURL: service.configuration.baseURL,
                current: { self.generation == issued && self.current() && self.approvedWriteAndOriginalProof() },
                validate: { try self.check(issued); try await self.validateOperation(); try self.check(issued) })
            let bound = PlayExperienceService(configuration: service.configuration, transport: transport, enabled: service.enabled)
            let raw = try await bound.request("api/play/advanced/start", json: ["activityId": .int(ticket.activityID),
                "topicId": .int(topicID), "nodeId": .int(ticket.nodeID)], capability: .advanced, token: owner.token)
            try check(issued)
            // Identity must come from the actual returned session, never a calculated ID.
            guard raw["activityId"].integer == ticket.activityID, raw["topicId"].integer == topicID,
                  raw["nodeId"].integer == ticket.nodeID, raw["ownerType"].integer == 2,
                  raw["ownerId"].integer == ticket.teamID, let id = raw["sessionId"].integer, id > 0 else { throw PlayExperienceError.malformed }
            let started = try await journal.transition(stored, to: .started, startedSessionID: id); try check(issued)
            guard started.value.phase == .started, started.value.sessionID == id, started.value.sharedPlanStart == binding else { throw PlayExperienceError.persistenceUnavailable }
            // Keep .started in the SAME encrypted slot until the first verified R5 command
            // atomically promotes it. Page exit/process restart must not erase this cursor.
            try await openExisting(id, issued: issued)
        } catch { fail(error, issued: issued) }
    }
    private func openExisting(_ id: Int, issued: UInt64) async throws {
        try check(issued); sessionID = id
        let value = PlaySharedPlanR5Recovery(owner: owner, ticket: ticket, topicID: topicID, service: service,
            outcomeService: outcomeService, journal: journal, current: { self.generation == issued && self.current() }, retainSessionCursor: true,
            approvedWriteAndOriginalProof: approvedWriteAndOriginalProof, validateOperation: validateOperation, onUnauthorized: onUnauthorized)
        recovery = value; await value.load(sessionID: id); try check(issued)
        phase = value.projection == nil ? "awaitingOriginalContract" : "ready"
    }
    private func fail(_ error: Error, issued: UInt64) {
        guard generation == issued else { return }
        if !current() { suspend(); return }
        issue = error as? PlayExperienceError ?? .unknownResult
        if case PlayExperienceError.unauthorized = error { onUnauthorized() }
        if phase != "unknownStart" { phase = "blocked" }
    }
}

@MainActor private final class SharedPlanR5StartTransport: HTTPTransport {
    let underlying: any HTTPTransport
    let baseURL: URL
    let current: () -> Bool
    let validate: () async throws -> Void
    init(underlying: any HTTPTransport, baseURL: URL, current: @escaping () -> Bool, validate: @escaping () async throws -> Void) {
        self.underlying = underlying; self.baseURL = baseURL; self.current = current; self.validate = validate
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard request.url == baseURL.appendingPathComponent("api/play/advanced/start"), request.httpMethod == "POST" else { throw PlayExperienceError.disabled }
        try await validate(); guard current() else { throw PlayExperienceError.disabled }
        let result = try await underlying.send(request)
        guard current() else { throw PlayExperienceError.staleSession }; return result
    }
}
