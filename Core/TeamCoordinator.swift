import Foundation

/// Only operation identity is persisted. Invite codes, tokens, names and roster data never are.
public struct TeamPendingRecord: Codable, Equatable {
    public let operationID: UUID
    public let ownerKey: String
    public let targetKey: String
    public var dispatchStarted: Bool? = nil
    public init(operationID: UUID, ownerKey: String, targetKey: String) { self.operationID = operationID; self.ownerKey = ownerKey; self.targetKey = targetKey }
}
@MainActor public protocol TeamPendingJournal: AnyObject {
    func pending(ownerKey: String, targetKey: String) throws -> TeamPendingRecord?
    func write(_ record: TeamPendingRecord) throws
    func clear(_ record: TeamPendingRecord) throws
}
@MainActor public final class TeamDefaultsJournal: TeamPendingJournal {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }
    private func key(_ owner: String, _ target: String) -> String { "questify.team.pending.v1.\(owner).\(target)" }
    public func pending(ownerKey: String, targetKey: String) throws -> TeamPendingRecord? {
        let name = key(ownerKey, targetKey)
        guard let raw = defaults.object(forKey: name) else { return nil }
        guard let data = raw as? Data else { throw TeamFailure.persistence }
        guard let result = try? JSONDecoder().decode(TeamPendingRecord.self, from: data), result.ownerKey == ownerKey, result.targetKey == targetKey else { throw TeamFailure.persistence }
        return result
    }
    public func write(_ record: TeamPendingRecord) throws {
        let data = try JSONEncoder().encode(record); let name = key(record.ownerKey, record.targetKey)
        defaults.set(data, forKey: name)
        guard defaults.data(forKey: name) == data else { throw TeamFailure.persistence }
    }
    public func clear(_ record: TeamPendingRecord) throws {
        guard try pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record else { throw TeamFailure.persistence }
        let name = key(record.ownerKey, record.targetKey); defaults.removeObject(forKey: name)
        guard defaults.object(forKey: name) == nil else { throw TeamFailure.persistence }
    }
}
public struct TeamReview: Identifiable, Equatable {
    public let id: UUID
    public let action: TeamAction
    public let detail: TeamDetail?
    fileprivate let session: TeamSession
}
/// Host retains this per workflow and redraws the entire private subtree on session change.
/// A persisted unresolved intent blocks replay across navigation, reauthentication and restart.
@MainActor public final class TeamCoordinator {
    public enum WriteState: Equatable { case idle, checking, submitting, simulated, acknowledged, rejected, notSent, unknown, blocked }
    private let service: any TeamServing
    private let journal: any TeamPendingJournal
    private let currentSession: () -> TeamSession?
    private let onUnauthorized: (TeamSession) -> Void
    private var capturedSession: TeamSession?
    private var generation: UInt64 = 0
    private var activeLookup: TeamLookup?
    private var completedJoinID: Int?
    private var readOnlyDetail = false
    // Workflow-local invalidation, not a server membership fact or a durable ban.
    // Keep the owner namespace across session epochs so reauthentication cannot revive
    // this workflow's acknowledged departure. A new workflow must obtain fresh authority.
    private var retiredMembershipsByOwner: [String: Set<Int>] = [:]
    // The journal has no action kind. Reconstructed coordinators must not guess it;
    // this association only supports correlated receipt checks within this workflow.
    private var retirementOperations: [UUID: (ownerKey: String, teamID: Int)] = [:]
    public private(set) var retiredMembershipTeamID: Int?
    public private(set) var scope = UUID()
    public private(set) var teams: [OwnedTeam] = []
    public private(set) var detail: TeamDetail?
    public private(set) var creation: TeamCreationContext?
    public private(set) var review: TeamReview?
    public private(set) var pending: TeamPendingRecord?
    public private(set) var messageKey: String?
    public private(set) var loading = false
    public private(set) var writeState: WriteState = .idle
    public private(set) var completedTeamID: Int?
    /// Navigation evidence only; never an authorization to write or proof of current membership.
    public var postJoinDetailID: Int? {
        guard currentSession() == capturedSession, capturedSession != nil, !busy,
              pending == nil, writeState == .acknowledged || writeState == .simulated,
              case .invitation = activeLookup, let id = completedJoinID,
              completedTeamID == id, detail?.team.id == id else { return nil }
        return id
    }
    public var authenticated: Bool { currentSession() != nil }
    public var configured: Bool { service.authority != .unconfigured }
    public var busy: Bool { loading || writeState == .checking || writeState == .submitting }
    public var canSubmit: Bool { canSimulate || service.authority == .approved }
    public var canSimulate: Bool {
        #if DEBUG
        return service.authority == .synthetic
        #else
        return false
        #endif
    }
    public init(service: any TeamServing, journal: any TeamPendingJournal, currentSession: @escaping () -> TeamSession?, onUnauthorized: @escaping (TeamSession) -> Void = { _ in }) {
        self.service = service; self.journal = journal; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        capturedSession = currentSession()
    }
    public func synchronizeSession() {
        guard currentSession() != capturedSession else { return }
        generation &+= 1; scope = UUID(); capturedSession = currentSession()
        teams = []; detail = nil; creation = nil; review = nil; pending = nil; activeLookup = nil; messageKey = nil; completedTeamID = nil; completedJoinID = nil
        loading = false; writeState = .idle; retiredMembershipTeamID = nil
    }
    private func active(_ session: TeamSession, _ stamp: UInt64) -> Bool {
        currentSession() == session && capturedSession == session && generation == stamp && !Task.isCancelled
    }
    private func readError(_ error: Error, session: TeamSession) {
        if error as? TeamFailure == .unauthorized {
            teams = []; detail = nil; creation = nil; review = nil; messageKey = "team.signIn"; onUnauthorized(session)
        } else if error as? TeamFailure == .notConfigured { messageKey = "team.unconfigured" }
        else { messageKey = detail == nil ? "team.loadFailed" : "team.refreshFailed" }
    }
    public func loadTeams() async {
        synchronizeSession(); guard !busy else { return }
        guard let session = capturedSession else { messageKey = "team.signIn"; return }
        guard configured else { messageKey = "team.unconfigured"; return }
        generation &+= 1; let stamp = generation; loading = true; review = nil; messageKey = nil
        defer { if generation == stamp { loading = false } }
        do {
            let rows = try await service.myTeams(session: session)
            guard active(session, stamp) else { return }
            teams = rows.filter { !membershipRetired(teamID: $0.id, session: session) }
        }
        catch { guard active(session, stamp) else { return }; readError(error, session: session) }
    }
    public func loadDetail(_ lookup: TeamLookup, requireMembership: Bool = false) async {
        synchronizeSession(); guard !busy else { return }
        guard let lookup = lookup.normalized else { detail = nil; messageKey = "team.invalidLink"; return }
        guard let session = capturedSession else { messageKey = "team.signIn"; return }
        generation &+= 1; let stamp = generation; loading = true; review = nil; messageKey = nil
        // The host uses a separate coordinator for each detail route. Never retain another target.
        if activeLookup != lookup { detail = nil; pending = nil; writeState = .idle; completedJoinID = nil; retiredMembershipTeamID = nil }; activeLookup = lookup
        defer { if generation == stamp { loading = false } }
        if case .id(let id) = lookup, membershipRetired(teamID: id, session: session) {
            detail = nil; retiredMembershipTeamID = id; messageKey = "team.changed"; return
        }
        if requireMembership {
            detail = nil
            guard case .id = lookup else { messageKey = "team.invalidLink"; return }
        }
        do {
            let result = try await service.detail(lookup, session: session)
            guard active(session, stamp) else { return }
            if case .id(let id) = lookup, result.team.id != id { throw TeamFailure.invalidContract }
            // Invitation reads resolve the team only after the response. Never let an old
            // joined projection reopen a team already retired by this workflow.
            guard !membershipRetired(teamID: result.team.id, session: session) else {
                detail = nil; retiredMembershipTeamID = result.team.id; messageKey = "team.changed"; return
            }
            // A joined-invitation continuation must earn membership again on the exact ID read.
            // Never retain its previous roster when membership is revoked or omitted.
            if requireMembership, result.joined != true { detail = nil; throw TeamFailure.invalidContract }
            detail = result; try restorePending(targetKey: "team-\(result.team.id)", session: session)
        } catch { guard active(session, stamp) else { return }; readError(error, session: session) }
    }
    /// A continuation is permanently read-only for this isolated coordinator's lifetime.
    public func loadPostJoinDetail(teamID: Int) async {
        readOnlyDetail = true; review = nil
        await loadDetail(.id(teamID), requireMembership: true)
    }
    public func loadCreation(ownerID: Int) async {
        synchronizeSession(); guard !busy else { return }
        guard let session = capturedSession else { messageKey = "team.signIn"; return }
        generation &+= 1; let stamp = generation; loading = true; creation = nil; review = nil; messageKey = nil
        defer { if generation == stamp { loading = false } }
        do {
            let result = try await service.creationContext(ownerID: ownerID, session: session)
            guard active(session, stamp) else { return }
            guard result.ownerID == ownerID, result.eligible else { throw TeamFailure.invalidContract }
            creation = result; try restorePending(targetKey: "activity-\(ownerID)", session: session)
        } catch { guard active(session, stamp) else { return }; readError(error, session: session) }
    }
    private func restorePending(targetKey: String, session: TeamSession) throws {
        do { pending = try journal.pending(ownerKey: session.ownerKey, targetKey: targetKey) }
        catch { writeState = .blocked; messageKey = "team.storageFailed"; throw TeamFailure.persistence }
        if pending != nil { writeState = .unknown; messageKey = "team.unknown" }
    }
    public func prepare(_ proposedAction: TeamAction) {
        synchronizeSession(); review = nil
        guard !readOnlyDetail, !busy, writeState != .blocked, let session = capturedSession else { return }
        if let teamID = proposedAction.teamID, membershipRetired(teamID: teamID, session: session) {
            messageKey = "team.changed"; return
        }
        var action = proposedAction
        if case .join(let teamID, let code) = action {
            guard let lookup = TeamLookup.invitation(code).normalized,
                  case .invitation(let normalizedCode) = lookup else { messageKey = "team.changed"; return }
            action = .join(teamID: teamID, inviteCode: normalizedCode)
        }
        do { try restorePending(targetKey: action.targetKey, session: session) }
        catch { return }
        guard pending == nil else { return }
        guard action.isAllowed(detail: detail) else { messageKey = "team.changed"; return }
        if case .join = action, action.lookup != activeLookup { messageKey = "team.changed"; return }
        if case .create(let context, _, _) = action, context != creation { messageKey = "team.changed"; return }
        do { _ = try TeamWriteContract(action) } catch { messageKey = "team.changed"; return }
        review = .init(id: UUID(), action: action, detail: detail, session: session)
        messageKey = canSimulate ? "team.fixtureNotice" : "team.writesDisabled"
    }
    public func cancelReview() { review = nil }
    public func leaveScreen() {
        generation &+= 1; loading = false; review = nil
        if pending != nil { writeState = .unknown; messageKey = "team.unknown" }
        else if writeState == .checking { writeState = .idle }
    }
    private func membershipRetired(teamID: Int, session: TeamSession) -> Bool {
        retiredMembershipsByOwner[session.ownerKey]?.contains(teamID) == true
    }
    private func rememberRetirement(_ action: TeamAction, record: TeamPendingRecord) {
        switch action {
        case .leave(let teamID), .disband(let teamID):
            retirementOperations[record.operationID] = (record.ownerKey, teamID)
        case .create, .join, .remove: break
        }
    }
    /// Called only after a correlated success and successful pending-journal clear.
    /// Dropping cached authority does not synthesize a new roster or server status.
    private func retireMembership(record: TeamPendingRecord, teamID: Int) {
        guard let operation = retirementOperations[record.operationID],
              operation.ownerKey == record.ownerKey, operation.teamID == teamID else { return }
        retirementOperations[record.operationID] = nil
        retiredMembershipsByOwner[record.ownerKey, default: []].insert(teamID)
        generation &+= 1
        teams.removeAll { $0.id == teamID }
        if detail?.team.id == teamID { detail = nil }
        review = nil; completedJoinID = nil; loading = false
        retiredMembershipTeamID = teamID
    }
    public func confirm(_ value: TeamReview) async {
        synchronizeSession()
        guard !readOnlyDetail, !busy, pending == nil, review == value, currentSession() == value.session else { return }
        if let teamID = value.action.teamID, membershipRetired(teamID: teamID, session: value.session) { return }
        review = nil
        guard canSubmit else { writeState = .notSent; messageKey = "team.writesDisabled"; return }
        completedJoinID = nil
        let session = value.session; generation &+= 1; let stamp = generation; writeState = .checking
        do {
            if case .create(let expected, _, _) = value.action {
                let fresh = try await service.creationContext(ownerID: expected.ownerID, session: session)
                guard active(session, stamp) else { return }
                guard fresh == expected, fresh.eligible else { writeState = .blocked; messageKey = "team.changed"; return }
            } else if let lookup = value.action.lookup {
                let fresh = try await service.detail(lookup, session: session)
                guard active(session, stamp) else { return }
                guard fresh == value.detail, value.action.isAllowed(detail: fresh) else { writeState = .blocked; messageKey = "team.changed"; return }
            }
            guard active(session, stamp) else { return }
            try restorePending(targetKey: value.action.targetKey, session: session)
            guard pending == nil else { return }
            let record = TeamPendingRecord(operationID: value.id, ownerKey: session.ownerKey, targetKey: value.action.targetKey)
            // This must succeed before any submission. Do not clear it on cancellation or sign-out.
            try journal.write(record); pending = record; writeState = .submitting
            rememberRetirement(value.action, record: record)
            let result = await service.submit(value.action, operationID: value.id, session: session)
            guard active(session, stamp) else { return }
            let persisted = try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey)
            guard let persisted, persisted.operationID == record.operationID else { throw TeamFailure.persistence }
            pending = persisted
            apply(result, record: persisted, expectedTeamID: value.action.teamID)
            if case .join(let teamID, _) = value.action,
               pending == nil, completedTeamID == teamID,
               writeState == .acknowledged || writeState == .simulated {
                completedJoinID = teamID
            }
        } catch {
            guard active(session, stamp) else { return }
            writeState = pending == nil ? .blocked : .unknown
            messageKey = pending == nil ? "team.preflightFailed" : "team.unknown"
        }
    }
    private func apply(_ result: TeamWriteOutcome, record: TeamPendingRecord, expectedTeamID: Int?) {
        switch result {
        case .unknown: writeState = .unknown; messageKey = "team.unknown"
        case .simulated(let id, let teamID):
            guard id == record.operationID, teamID > 0, expectedTeamID == nil || expectedTeamID == teamID else { writeState = .unknown; messageKey = "team.unknown"; return }
            do {
                try journal.clear(record); pending = nil; completedTeamID = teamID
                retireMembership(record: record, teamID: teamID)
                writeState = .simulated; messageKey = "team.simulated"
            }
            catch { writeState = .unknown; messageKey = "team.unknown" }
        case .acknowledged(let id, let teamID):
            guard id == record.operationID, teamID > 0, expectedTeamID == nil || expectedTeamID == teamID else { writeState = .unknown; messageKey = "team.unknown"; return }
            do {
                try journal.clear(record); pending = nil; completedTeamID = teamID
                retireMembership(record: record, teamID: teamID)
                writeState = .acknowledged; messageKey = "team.acknowledged"
            }
            catch { writeState = .unknown; messageKey = "team.unknown" }
        case .rejected, .notSent:
            do {
                try journal.clear(record); pending = nil; retirementOperations[record.operationID] = nil
                writeState = result == .rejected ? .rejected : .notSent; messageKey = result == .rejected ? "team.rejected" : "team.notSent"
            }
            catch { writeState = .unknown; messageKey = "team.unknown" }
        }
    }
    /// Synthetic correlated receipts only. A list refresh is not proof of an earlier outcome.
    public func checkOutcome() async {
        synchronizeSession(); guard !readOnlyDetail, !busy, canSimulate, let session = capturedSession, let record = pending else { return }
        generation &+= 1; let stamp = generation; writeState = .checking
        let expected = record.targetKey.hasPrefix("team-") ? Int(record.targetKey.dropFirst(5)) : nil
        do {
            let result = try await service.receipt(operationID: record.operationID, session: session)
            guard active(session, stamp) else { return }
            apply(result ?? .unknown, record: record, expectedTeamID: expected)
        } catch { guard active(session, stamp) else { return }; writeState = .unknown; messageKey = "team.unknown" }
    }
}
