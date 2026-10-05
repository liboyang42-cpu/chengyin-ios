#if DEBUG
import Foundation

public enum ClubOperationsFixtureScenario: String, CaseIterable {
    case owner, admin, ordinary, limit, unknown, denied, delayed, changed, readbackUnavailable, missingSettings, unverified
}
/// A deterministic in-memory synthetic backend. No URL, transport, credential or disk.
@MainActor public final class ClubOperationsFixtureAccess: ClubOperationsAccess {
    public private(set) var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 0)
    public var isConfigured: Bool { true }
    public var writeAvailability: ClubOperationsWriteAvailability { scenario == .unverified ? .unverified : .syntheticOnly }
    public private(set) var writeCount = 0
    public var onWrite: (() -> Void)?
    public var onWriteFinished: (() -> Void)?
    /// UI fixtures can hold a dispatched write until an explicit account switch,
    /// so simulator scheduling cannot turn a race test into a post-completion switch.
    public var delayedWriteGate: (() async -> Void)?
    public private(set) var readCount = 0
    public let scenario: ClubOperationsFixtureScenario
    private var payload: [String: Any]
    private var memberRows: [[String: Any]] = [["memberId": 701, "nickname": "Fixture owner", "role": 1, "isOwner": true], ["memberId": 704, "nickname": "Fixture member", "role": 0, "isOwner": false]]
    private var ownedIDs = [81]
    public init(scenario: ClubOperationsFixtureScenario) {
        self.scenario = scenario
        payload = ["id": 81, "name": "Fixture club", "city": "Fixture city", "clubType": "兴趣社群", "activityPrefs": "轻社交",
            "description": "Synthetic club profile", "keywords": "", "style": "Explore together", "logo": "", "cover": "",
            "isOwner": scenario != .admin && scenario != .ordinary, "viewerIsAdmin": scenario == .admin, "isJoined": true,
            "memberCount": 2, "prioritySignupEnabled": 1, "memberReservedQuota": 4, "joinPolicy": 1, "joinPolicySupported": true]
        if scenario != .missingSettings {
            payload["publicVisible"] = 1; payload["memberPostAllowed"] = 1; payload["merchantUndertakeOpen"] = 0
        }
        if scenario == .limit { ownedIDs = [81, 82] }
    }
    public func switchAccount() {
        identity = .init(accountID: identity?.accountID == 701 ? 702 : 701, epoch: (identity?.epoch ?? 0) + 1)
    }
    public func signOut() { identity = nil }
    public func reloginSameAccount() { identity = .init(accountID: identity?.accountID ?? 701, epoch: (identity?.epoch ?? 0) + 1) }
    public func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot {
        try Task.checkCancellation()
        guard identity != nil else { throw APIError.unauthorized }
        readCount += 1
        if scenario == .readbackUnavailable, writeCount > 0 { throw APIError.malformedResponse }
        switch target {
        case .create: return .init(target: target, accountRole: scenario == .ordinary ? "player" : "club", ownedClubIDs: ownedIDs)
        case .club(let id):
            guard id == 81 else { throw APIError.invalidRequest }
            guard scenario != .ordinary else { throw ClubReadFailure.forbidden(message: nil) }
            var data = payload
            if scenario == .changed, readCount >= 3 { data["viewerIsAdmin"] = false; data["isOwner"] = false }
            let profile = try JSONDecoder().decode(ClubOperationsProfile.self, from: JSONSerialization.data(withJSONObject: data))
            let members = try JSONDecoder().decode([ClubMember].self, from: JSONSerialization.data(withJSONObject: memberRows))
            return .init(target: target, profile: profile, members: profile.club.isOwner ? members : [])
        }
    }
    public func perform(_ command: ClubOperationsCommand, target: ClubOperationsTarget, expectedIdentity: ClubReadIdentity) async throws -> ClubOperationsReceipt {
        guard identity == expectedIdentity else { throw ClubActionWriteError.notSent(.unauthorized) }
        guard writeAvailability == .syntheticOnly else { throw ClubActionWriteError.notSent(.notConfigured) }
        let fresh = try await snapshot(target: target)
        do { try command.validate(snapshot: fresh, identity: expectedIdentity) }
        catch { throw ClubActionWriteError.eligibilityChanged }
        guard !Task.isCancelled else { throw ClubActionWriteError.cancelledBeforeDispatch }
        writeCount += 1; onWrite?()
        defer { onWriteFinished?() }
        if scenario == .denied { throw ClubActionWriteError.rejected(.init(code: 403, message: "Fixture server rejected this change")) }
        if scenario == .delayed {
            if let delayedWriteGate { await delayedWriteGate() }
            else {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                catch { throw ClubActionWriteError.outcomeUnknown(.cancelled) }
            }
        }
        guard identity == expectedIdentity else { throw ClubActionWriteError.outcomeUnknown(.accountChanged) }
        let receipt: ClubOperationsReceipt
        switch command {
        case .create: ownedIDs.append(82); receipt = .init(clubID: 82)
        case .update(let draft, let original):
            let fields = try draft.fields(original: original)
            payload.merge(fields) { _, new in new }; receipt = .init()
        case .openSetting(let setting, let enabled, _):
            payload[setting.rawValue] = enabled ? 1 : 0; receipt = .init(settingValue: enabled)
        case .memberRole(let memberID, let admin, _):
            if let index = memberRows.firstIndex(where: { $0["memberId"] as? Int == memberID }) { memberRows[index]["role"] = admin ? 1 : 0 }
            receipt = .init()
        }
        if scenario == .unknown { throw ClubActionWriteError.outcomeUnknown(.transport) }
        return receipt
    }
}
#endif
