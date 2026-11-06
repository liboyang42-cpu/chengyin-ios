import Foundation
import Observation

/// Normal entry backed by original state/invite readers. Never creates a write grant from writeApproved/counts.
/// approve must only arrange an independently verified EXACT command grant in the recovery owner; default nil.
@MainActor @Observable public final class CityParticipationFormModel {
    public private(set) var state: CityParticipationState?
    public private(set) var invitation: CityParticipationInvitation?
    public private(set) var prepared: CityParticipationCommand?
    public private(set) var busy = false
    public private(set) var unavailable = false
    public let recovery: CityParticipationCommandRecovery
    private let regionID: String
    private let currentScope: () -> CityParticipationCommandScope?
    private let stateReader: CityParticipationStateReader?
    private let invitationReader: CityParticipationInvitationReader?
    private let approve: (@MainActor (CityParticipationCommand) async -> Bool)?
    private var original: CityParticipationCommandScope?
    private var invitationCode: String?
    private var visit: UInt64 = 0
    private var inviteGeneration: UInt64 = 0
    public init(regionID: String, recovery: CityParticipationCommandRecovery,
                currentScope: @escaping () -> CityParticipationCommandScope?, stateReader: CityParticipationStateReader? = nil,
                invitationReader: CityParticipationInvitationReader? = nil,
                approve: (@MainActor (CityParticipationCommand) async -> Bool)? = nil) {
        self.regionID = regionID; self.recovery = recovery; self.currentScope = currentScope
        self.stateReader = stateReader; self.invitationReader = invitationReader; self.approve = approve
    }
    public var hasApprovalHost: Bool { approve != nil }
    public var availableKinds: [CityParticipationCommand.Kind] {
        guard let s = state, let original, currentScope() == original, original.session.market == .china,
              s.writeApproved, !busy else { return [] }
        switch recovery.display { case .unknown, .storageBlocked, .hidden, .unavailable: return []; default: break }
        guard let t = s.team else { return s.status == "NOT_JOINED" ? [.create, .join] : [] }
        var actions: [CityParticipationCommand.Kind] = []
        if t.state == "FORMING", t.captain, t.presentCount == t.memberCount,
           t.memberCount >= s.binding.rules.minMembers, t.memberCount <= s.binding.rules.maxMembers { actions.append(.lock) }
        if t.state == "LOCKED", t.present, !t.confirmed { actions.append(.confirm) }
        actions.append(t.present ? .exit : .resume)
        return actions
    }
    private func valid(_ v: UInt64, _ scope: CityParticipationCommandScope) -> Bool {
        visit == v && original == scope && currentScope() == scope
    }
    public func close() {
        visit &+= 1; original = nil; state = nil; invitation = nil; invitationCode = nil; prepared = nil
        busy = false; unavailable = false; recovery.close()
    }
    public func open() async {
        close()
        guard let scope = currentScope(), CityParticipationCommand.id(regionID), let stateReader else { unavailable = true; return }
        original = scope; recovery.open(); busy = true
        let v = visit
        do {
            let readScope = try CityParticipationReadScope(market: scope.session.market, baseURL: scope.session.baseURL,
                namespace: scope.session.namespace, accountID: scope.session.accountID, epoch: scope.session.epoch,
                token: scope.token, regionID: regionID)
            let loaded = try await stateReader.read(readScope)
            guard valid(v, scope) else { if visit == v { close() }; return }
            state = loaded; busy = false
        } catch { if valid(v, scope) { busy = false; unavailable = true } else if visit == v { close() } }
    }
    public func invitationInputChanged() {
        inviteGeneration &+= 1; invitation = nil; invitationCode = nil
        if prepared?.kind == .join { prepared = nil }
    }
    public func inspectInvite(_ code: String) async {
        guard !busy, let scope = original, availableKinds.contains(.join), let invitationReader else { return }
        prepared = nil; invitation = nil; invitationCode = nil; busy = true; unavailable = false
        let v = visit, inputGeneration = inviteGeneration
        do {
            let found = try await invitationReader.read(scope: scope, regionID: regionID, code: code)
            guard valid(v, scope) else { if visit == v { close() }; return }
            guard inputGeneration == inviteGeneration else { busy = false; return }
            // The original invite producer checks current release. Never substitute a stale/current map for this binding.
            guard found.binding == state?.binding else { busy = false; unavailable = true; return }
            invitation = found; invitationCode = code; busy = false
        } catch { if valid(v, scope) { busy = false; unavailable = true } else if visit == v { close() } }
    }
    public func prepare(_ kind: CityParticipationCommand.Kind) {
        guard availableKinds.contains(kind), let s = state else { return }
        let binding = s.binding
        do {
            if kind == .join {
                guard let invitation, invitation.binding == binding, let invitationCode else { return }
                prepared = try .init(kind: kind, requestID: UUID().uuidString, regionID: binding.regionId,
                    releaseID: binding.releaseId, contentHash: binding.contentHash, expectedVersion: invitation.version,
                    teamID: invitation.teamId, inviteCode: invitationCode)
            } else {
                prepared = try .init(kind: kind, requestID: UUID().uuidString, regionID: binding.regionId,
                    releaseID: binding.releaseId, contentHash: binding.contentHash, expectedVersion: s.team?.version ?? 0,
                    teamID: s.team?.teamId)
            }
        } catch { prepared = nil; unavailable = true }
    }
    public func cancelReview() { if !busy { prepared = nil } }
    public func submitPrepared() async {
        guard !busy, let command = prepared, availableKinds.contains(command.kind), let scope = original, let approve else { return }
        busy = true; let v = visit
        let approved = await approve(command)
        guard valid(v, scope), prepared == command else { if visit == v { close() }; return }
        guard approved else { busy = false; return }
        await recovery.submit(command)
        guard valid(v, scope) else { if visit == v { close() }; return }
        busy = false; prepared = nil; state = nil; invitation = nil; invitationCode = nil
        // Any next action requires a new original state read. UNKNOWN retains recovery's saved lock.
    }
}
