#if DEBUG
import Foundation

public enum TeamSyntheticFixtures {
    public static let detailJSON = #"{"team":{"id":4101,"title":"Synthetic harbor companions","status":0,"joinedCount":2,"maxMembers":4,"ownerType":2,"ownerId":5101,"expireTime":"2030-05-02 10:00:00","joinMode":2,"inviteCode":"SYNTHETIC-TEAM"},"joined":true,"leader":true,"members":[{"memberId":901,"memberName":"Synthetic captain","role":1},{"memberId":902,"memberName":"Synthetic teammate","role":0}]}"#
    public static func detail() throws -> TeamDetail { try JSONDecoder().decode(TeamDetail.self, from: Data(detailJSON.utf8)) }
    public static var creation: TeamCreationContext { .init(ownerID: 5101, title: "Synthetic harbor activity", registrationStatus: 2, teamMode: 2, maxMembers: 4) }
    public static func session(epoch: UInt64 = 1, accountID: Int = 901, region: String = "CN", role: String = "player") throws -> TeamSession {
        let data = try JSONSerialization.data(withJSONObject: ["id": accountID, "role": role])
        let account = try JSONDecoder().decode(Account.self, from: data)
        return try .init(account: account, epoch: epoch, region: region, storageNamespace: "offline-team-fixture", token: "synthetic-team-token")
    }
}
@MainActor public final class TeamMemoryJournal: TeamPendingJournal {
    public var records: [String: TeamPendingRecord] = [:]
    public var failReads = false
    public var failWrites = false
    public init() {}
    public func pending(ownerKey: String, targetKey: String) throws -> TeamPendingRecord? {
        if failReads { throw TeamFailure.persistence }; return records[ownerKey + ":" + targetKey]
    }
    public func write(_ record: TeamPendingRecord) throws {
        if failWrites { throw TeamFailure.persistence }; records[record.ownerKey + ":" + record.targetKey] = record
    }
    public func clear(_ record: TeamPendingRecord) throws {
        guard !failWrites, records[record.ownerKey + ":" + record.targetKey] == record else { throw TeamFailure.persistence }
        records[record.ownerKey + ":" + record.targetKey] = nil
    }
}
@MainActor public final class TeamSyntheticService: TeamServing {
    public enum Scenario: String { case content, empty, failure, retry, guest, unconfigured, invitation, full, inProgress, ended, disbanded, unknownStatus, missingRole, unknownOutcome, rejected, notSent }
    public var authority: TeamServiceAuthority { scenario == .unconfigured ? .unconfigured : .synthetic }
    public let scenario: Scenario
    public var currentDetail: TeamDetail
    public var context = TeamSyntheticFixtures.creation
    public var beforeRead: (() async -> Void)?
    public var beforeSubmit: (() async -> Void)?
    public private(set) var submissions: [UUID] = []
    public var outcomes: [UUID: TeamWriteOutcome] = [:]
    private var attempts = 0
    public init(scenario: Scenario = .content) throws {
        self.scenario = scenario
        var json = TeamSyntheticFixtures.detailJSON
        switch scenario {
        case .invitation: json = json.replacingOccurrences(of: "\"joined\":true,\"leader\":true", with: "\"joined\":false,\"leader\":false")
        case .full: json = json.replacingOccurrences(of: "\"status\":0", with: "\"status\":1")
        case .inProgress: json = json.replacingOccurrences(of: "\"status\":0", with: "\"status\":2")
        case .ended: json = json.replacingOccurrences(of: "\"status\":0", with: "\"status\":3")
        case .disbanded: json = json.replacingOccurrences(of: "\"status\":0", with: "\"status\":4")
        case .unknownStatus: json = json.replacingOccurrences(of: "\"status\":0", with: "\"status\":98")
        case .missingRole: json = json.replacingOccurrences(of: "\"joined\":true,\"leader\":true,", with: "")
        default: break
        }
        currentDetail = try JSONDecoder().decode(TeamDetail.self, from: Data(json.utf8))
    }
    private func readCheck() async throws {
        if let beforeRead { await beforeRead() }
        if scenario == .unconfigured { throw TeamFailure.notConfigured }
        if scenario == .failure { throw TeamFailure.unavailable }
        if scenario == .retry { attempts += 1; if attempts == 1 { throw TeamFailure.unavailable } }
    }
    public func myTeams(session: TeamSession) async throws -> [OwnedTeam] {
        try await readCheck(); return scenario == .empty || currentDetail.joined != true ? [] : [currentDetail.team]
    }
    public func detail(_ lookup: TeamLookup, session: TeamSession) async throws -> TeamDetail {
        try await readCheck(); guard lookup.isValid else { throw TeamFailure.invalidRequest }
        switch lookup {
        case .id(let id): guard currentDetail.team.id == id else { throw TeamFailure.invalidContract }
        case .invitation(let code): guard code == currentDetail.team.inviteCode else { throw TeamFailure.unavailable }
        }
        return currentDetail
    }
    public func creationContext(ownerID: Int, session: TeamSession) async throws -> TeamCreationContext {
        try await readCheck(); guard ownerID == context.ownerID else { throw TeamFailure.invalidRequest }; return context
    }
    public func submit(_ action: TeamAction, operationID: UUID, session: TeamSession) async -> TeamWriteOutcome {
        if let existing = outcomes[operationID] { return existing }
        submissions.append(operationID)
        if let beforeSubmit { await beforeSubmit() }
        let result: TeamWriteOutcome
        switch scenario {
        case .unknownOutcome: return .unknown
        case .rejected: result = .rejected
        case .notSent: result = .notSent
        default:
            do { try applyLocal(action); result = .simulated(operationID: operationID, teamID: action.teamID ?? 4101) }
            catch { return .unknown }
        }
        outcomes[operationID] = result; return result
    }
    public func receipt(operationID: UUID, session: TeamSession) async throws -> TeamWriteOutcome? { outcomes[operationID] }
    private func applyLocal(_ action: TeamAction) throws {
        // Offline fixture-only state. Never announces real membership changes or notifications.
        guard var object = try JSONSerialization.jsonObject(with: Data(TeamSyntheticFixtures.detailJSON.utf8)) as? [String: Any] else { throw TeamFailure.invalidContract }
        switch action {
        case .join: object["joined"] = true; object["leader"] = false
        case .leave: object["joined"] = false; object["leader"] = false
        case .remove(_, let memberID): object["members"] = (object["members"] as? [[String: Any]])?.filter { $0["memberId"] as? Int != memberID }
        case .disband:
            guard var team = object["team"] as? [String: Any] else { throw TeamFailure.invalidContract }; team["status"] = 4; object["team"] = team; object["joined"] = false; object["leader"] = false
        case .create(_, let size, let inviteOnly):
            guard var team = object["team"] as? [String: Any] else { throw TeamFailure.invalidContract }; team["maxMembers"] = size; team["joinMode"] = inviteOnly ? 1 : 2; object["team"] = team
        }
        currentDetail = try JSONDecoder().decode(TeamDetail.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
#endif
