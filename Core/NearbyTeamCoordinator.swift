import Foundation

public struct NearbyTeamReview: Identifiable, Equatable {
    public let id: UUID
    public let action: NearbyTeamAction
    public let session: NearbyTeamSession
    public let revision: UInt64
    public let team: NearbyTeam?
    public let applicant: NearbyApplicant?
    public let application: NearbyMyApplication?
}
@MainActor public final class NearbyTeamCoordinator {
    public private(set) var teams: [NearbyTeam] = []
    public private(set) var myApplications: [NearbyMyApplication] = []
    public private(set) var applicants: [NearbyApplicant] = []
    public private(set) var applicantsTeamID: NearbyTeamID?
    public private(set) var review: NearbyTeamReview?
    public private(set) var busy = false
    public private(set) var messageKey: String?
    public private(set) var serverMessage = ""
    public private(set) var errorCode = ""
    public private(set) var revision: UInt64 = 0
    public private(set) var context: NearbyQueryContext?
    public private(set) var refreshRequired = false
    public private(set) var session: NearbyTeamSession?
    private let service: NearbyTeamService
    private var generation: UInt64 = 0
    private var active = true
    private let locks: NearbyTeamLockStore
    private var settledActions: Set<NearbyTeamActionKey> = []
    public init(service: NearbyTeamService, session: NearbyTeamSession? = nil, locks: NearbyTeamLockStore? = nil) { self.service = service; self.session = session; self.locks = locks ?? NearbyTeamLockStore(defaults: .standard) }
    public var synthetic: Bool { service.synthetic }
    public var canSubmit: Bool { service.canSubmit }
    public var configured: Bool { service.configured }
    public var authenticated: Bool { session?.valid == true }
    public var uncertain: Bool { session.map { locks.contains(accountKey($0)) } ?? false }
    public var locked: Bool { busy || uncertain || refreshRequired || !active }
    public func bind(_ session: NearbyTeamSession?) {
        guard self.session != session else { return }; generation &+= 1; revision &+= 1; self.session = session
        teams = []; myApplications = []; applicants = []; applicantsTeamID = nil; context = nil; review = nil; busy = false; active = true; refreshRequired = false; messageKey = nil; serverMessage = ""; errorCode = ""; settledActions = []
    }
    public func leave() { generation &+= 1; active = false; review = nil; busy = false }
    public func resume() { active = true }
    public func cancelReview() { review = nil }
    private func accountKey(_ session: NearbyTeamSession) -> String { "\(session.region):\(session.namespace):\(session.accountID)" }
    private func valid(_ captured: NearbyTeamSession, _ generation: UInt64) -> Bool { active && session == captured && self.generation == generation }
    private func begin() -> (NearbyTeamSession, UInt64)? {
        guard !busy, active, let session, session.valid else { messageKey = "nearby.signIn"; return nil }
        busy = true; review = nil; messageKey = nil; serverMessage = ""; errorCode = ""; return (session, generation)
    }
    public func loadNearby(_ context: NearbyQueryContext) async {
        guard context.valid else { messageKey = "nearby.context.invalid"; return }
        guard let (session, generation) = begin() else { return }
        defer { if valid(session, generation) { busy = false } }
        do {
            let rows = try await service.nearby(context, session: session); guard valid(session, generation) else { return }
            guard Set(rows.map(\.id)).count == rows.count else { throw NearbyTeamFailure.contract }
            teams = rows; self.context = context; revision &+= 1
            applicants = []; applicantsTeamID = nil; refreshRequired = false
        } catch { if valid(session, generation) { failure(error) } }
    }
    public func loadMine() async {
        guard let (session, generation) = begin() else { return }
        defer { if valid(session, generation) { busy = false } }
        do {
            let rows = try await service.myApplications(session: session); guard valid(session, generation) else { return }
            var seen: Set<NearbyTeamID> = []
            myApplications = rows.filter { [.pending, .rejected].contains($0.status) && seen.insert($0.id).inserted }; revision &+= 1
        } catch { if valid(session, generation) { failure(error) } }
    }
    public func loadApplicants(teamID: NearbyTeamID) async {
        guard teams.first(where: { $0.id == teamID })?.viewerStatus == .leader else { messageKey = "nearby.role"; return }
        guard let (session, generation) = begin() else { return }
        defer { if valid(session, generation) { busy = false } }
        do {
            let rows = try await service.applications(teamID, session: session); guard valid(session, generation) else { return }
            guard Set(rows.map(\.id)).count == rows.count else { throw NearbyTeamFailure.contract }
            applicants = rows; applicantsTeamID = teamID; revision &+= 1
        } catch { if valid(session, generation) { applicants = []; applicantsTeamID = nil; failure(error) } }
    }
    public func allowed(_ action: NearbyTeamAction, now: Date = Date()) -> Bool {
        guard authenticated, !locked, !settledActions.contains(.init(action)) else { return false }
        let team = teams.first { $0.id == action.teamID }
        switch action {
        case .apply: return team?.viewerStatus == .none && team?.viewerHasTicket == true
        case .withdraw:
            if let team { return team.viewerStatus == .pending }; return myApplications.contains { $0.id == action.teamID && $0.status == .pending }
        case .handle(_, let applicant, _):
            guard team?.viewerStatus == .leader, applicantsTeamID == action.teamID, let row = applicants.first(where: { $0.id == applicant }) else { return false }
            // Expired displayed data cannot authorize a decision. Missing expiry is not invented.
            if let expiry = row.applyExpireTime?.date() { return expiry > now }; return true
        }
    }
    public func prepare(_ action: NearbyTeamAction, now: Date = Date()) {
        guard allowed(action, now: now), let session else { messageKey = "nearby.actionUnavailable"; return }
        let applicant: NearbyApplicant?
        if case .handle(_, let id, _) = action { applicant = applicants.first { $0.id == id } } else { applicant = nil }
        review = .init(id: UUID(), action: action, session: session, revision: revision, team: teams.first { $0.id == action.teamID }, applicant: applicant, application: myApplications.first { $0.id == action.teamID })
    }
    public func confirm(_ snapshot: NearbyTeamReview, now: Date = Date()) async {
        guard review == snapshot, snapshot.session == session, snapshot.revision == revision, allowed(snapshot.action, now: now) else { review = nil; messageKey = "nearby.stale"; return }
        guard canSubmit else { messageKey = "nearby.dormant"; review = nil; return }
        let capturedGeneration = generation; let capturedSession = snapshot.session
        review = nil; busy = true
        // Register before suspension, preserving an account-scoped lock across logout/navigation.
        guard locks.insert(accountKey(capturedSession)) else { busy = false; messageKey = "nearby.unknown"; return }
        let outcome = await service.submit(snapshot.action, session: capturedSession, review: snapshot)
        switch outcome { case .unknown: break; default: locks.remove(accountKey(capturedSession)) }
        guard valid(capturedSession, capturedGeneration) else { return }
        busy = false; revision &+= 1
        switch outcome {
        case .notSent: messageKey = "nearby.dormant"
        case .unknown: messageKey = "nearby.unknown"
        case .rejected(let code, let message):
            errorCode = code; serverMessage = message; messageKey = NearbyErrorEffect.messageKey(operation: snapshot.action.operation, errorCode: code)
            let effect = NearbyErrorEffect.resolve(operation: snapshot.action.operation, errorCode: code)
            if effect.dropTeam { teams.removeAll { $0.id == snapshot.action.teamID } }
            else if let index = teams.firstIndex(where: { $0.id == snapshot.action.teamID }) { teams[index].patch(status: effect.status, ticket: effect.ticket) }
            if effect.dropApplicant, case .handle(_, let id, _) = snapshot.action { applicants.removeAll { $0.id == id } }
            refreshRequired = effect.refresh
        case .simulated(let expiry), .acknowledged(let expiry):
            settledActions.insert(.init(snapshot.action))
            if case .acknowledged = outcome { messageKey = "nearby.acknowledged" } else { messageKey = "nearby.simulated" }
            switch snapshot.action {
            case .apply(let id): if let index = teams.firstIndex(where: { $0.id == id }) { teams[index].patch(status: .pending, expiry: expiry, replaceExpiry: true) }
            case .withdraw(let id):
                if let index = teams.firstIndex(where: { $0.id == id }) { teams[index].patch(status: .none, replaceExpiry: true) }
                myApplications.removeAll { $0.id == id }
            case .handle(_, let id, let approved): applicants.removeAll { $0.id == id }; refreshRequired = approved
            }
        }
        // No speculative count/member increment. Source requires a server refresh after approval/full.
        if refreshRequired, let context {
            let savedKey = messageKey, savedCode = errorCode, savedMessage = serverMessage
            await loadNearby(context)
            if valid(capturedSession, capturedGeneration), !savedCode.isEmpty { messageKey = savedKey; errorCode = savedCode; serverMessage = savedMessage }
        }
    }
    private func failure(_ error: Error) {
        if error as? NearbyTeamFailure == .unauthorized { bind(nil); busy = false; messageKey = "nearby.signIn"; return }
        if case NearbyTeamFailure.rejected(let code, let message) = error { errorCode = code; serverMessage = message }
        messageKey = error as? NearbyTeamFailure == .unconfigured ? "nearby.unconfigured" : "nearby.loadFailed"
    }
}
private struct NearbyTeamActionKey: Hashable {
    let team: NearbyTeamID; let operation: String; let applicant: NearbyApplicantID?
    init(_ action: NearbyTeamAction) { team = action.teamID; operation = action.operation; if case .handle(_, let id, _) = action { applicant = id } else { applicant = nil } }
}

/// Stores only a namespaced unresolved-intent bit, never names, applicant data, tokens or coordinates.
/// The source exposes no idempotency or operation-receipt endpoint: refresh cannot clear ambiguity.
@MainActor public final class NearbyTeamLockStore {
    private let defaults: UserDefaults?
    private var values: Set<String> = []
    public init(defaults: UserDefaults? = nil) { self.defaults = defaults }
    private func key(_ account: String) -> String { "questify.nearby.unresolved.v1." + Data(account.utf8).base64EncodedString() }
    public func contains(_ account: String) -> Bool { values.contains(account) || defaults?.object(forKey: key(account)) != nil }
    func insert(_ account: String) -> Bool {
        values.insert(account)
        guard let defaults else { return true }
        defaults.set(true, forKey: key(account)); return defaults.bool(forKey: key(account))
    }
    func remove(_ account: String) { values.remove(account); defaults?.removeObject(forKey: key(account)) }
}
