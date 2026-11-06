import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// WORLD_SHARED gameplay deliberation only. This is not an IM poll or staff fallback.
public enum PlaySharedPlanAction: String, Codable, CaseIterable, Identifiable {
    case propose = "PLAN_PROPOSE", intent = "PLAN_INTENT", withdraw = "PLAN_WITHDRAW", change = "PLAN_CHANGE"
    case rejectAll = "PLAN_REJECT_ALL", openVote = "VOTE_OPEN", nextVote = "VOTE_NEXT", vote = "VOTE_CAST"
    case accept = "ACCEPT_SET", consensus = "CONSENSUS_CAST", confirm = "PLAN_CONFIRM"
    case start = "OPERATION_START", cancel = "OPERATION_CANCEL", execute = "PLAN_EXECUTE"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .propose: return "提出此方案"; case .intent: return "签署本队投入意向"; case .withdraw: return "撤回本队提案"
        case .change: return "改案并重新签署"; case .rejectAll: return "拒绝全部剩余方案"; case .openVote: return "开启首选表决"
        case .nextVote: return "开启下一轮"; case .vote: return "签署本队首选票"; case .accept: return "签署接受清单"
        case .consensus: return "签署共识票"; case .confirm: return "确认并锁定本队物资"
        case .start: return "开始原操作任务"; case .cancel: return "取消本队原操作"; case .execute: return "执行已选方案"
        }
    }
    public var consequence: String {
        switch self {
        case .intent: return "意向由当前队长签署，但不锁定或消耗物资。"
        case .confirm: return "仅锁定本队原意向中的物资；托管不是执行完成。"
        case .change: return "释放方案锁、本轮投票与签名；不会释放独立交易锁。所有队伍须重新核对。"
        case .withdraw, .rejectAll: return "会影响当前方案、票轮或签名；仅代表本队当前队长。"
        case .execute: return "仅原系统确认各队签名、准确托管、真实操作 PASS 与费用后结算。选定不等于已执行。"
        case .start: return "开始只是原操作实例建立，仍须进入真实题组；不会由界面制造 PASS。"
        case .cancel: return "取消当前本队方案操作及其对应证明；不会执行方案或推断退款。"
        default: return "按当前原票轮、版本和队长签署；结果以本次原回执为准。"
        }
    }
}
public struct PlaySharedPlanIdentity: Codable, Equatable {
    public let teamID, ownerRevision, round: Int
    public let endingKey, proposalKey: String?
    public let proposalVersion, operationNodeID, sourceNodeID, bindingVersion: Int?
    public let operationReceiptID: Int?
}
public struct PlaySharedPlanRow: Equatable, Identifiable {
    public var id: String { endingKey }
    public let endingKey, title, summary: String
    public let proposalKey: String?
    public let version, proposingTeamID, operationNodeID, sourceNodeID, bindingVersion: Int?
    public let cost, ownIntent: [PlaySharedPlanAmount]
    public let confirmed: [String: [PlaySharedPlanAmount]]
    public let signatureCurrent, ownConfirmed, selected, conditionsMet, started: Bool
    public let canFund, canVote, canAccept, canExecute, canStart: Bool
    public let reason: String?
    init(_ plan: PlayWireValue, world: PlayWireValue, player: PlayWireValue) throws {
        guard let ending = plan["endingKey"].text, PlaySharedPlanAmount.validKey(ending),
              let title = plan["title"].text, plan["summary"] == .null || plan["summary"].text != nil,
              let conditions = plan["conditionsMet"].bool, let fund = plan["actions"]["canFund"].bool,
              let vote = plan["actions"]["canVote"].bool, let accept = plan["actions"]["canAccept"].bool,
              let execute = plan["actions"]["canExecute"].bool else { throw PlayExperienceError.malformed }
        endingKey = ending; self.title = title; self.summary = plan["summary"].text ?? ""; conditionsMet = conditions
        let proposalKey = plan["proposalKey"].text, version = plan["version"].integer
        self.proposalKey = proposalKey; self.version = version
        let proposals = world["proposals"].array ?? []
        let proposal = proposals.first { $0["proposalKey"].text == proposalKey && proposalKey != nil } ?? .null
        if let proposalKey {
            guard PlaySharedPlanAmount.validKey(proposalKey), (version ?? 0) > 0,
                  proposal["version"].integer == version, proposal["endingKey"].text == ending,
                  proposal["status"].text == "OPEN", (proposal["teamId"].integer ?? 0) > 0 else { throw PlayExperienceError.malformed }
        } else { guard plan["proposalKey"] == .null, plan["version"] == .null else { throw PlayExperienceError.malformed } }
        proposingTeamID = proposal["teamId"].integer
        cost = try PlaySharedPlanAmount.read(plan["materialCost"])
        let intent = proposal["ownIntent"]
        guard intent == .null || (intent.object != nil && intent["signatureCurrent"].bool != nil),
              proposal["ownConfirmed"] == .null || proposal["ownConfirmed"].bool != nil else { throw PlayExperienceError.malformed }
        if intent == .null { ownIntent = [] } else { ownIntent = try PlaySharedPlanAmount.read(intent["amounts"]) }
        signatureCurrent = intent["signatureCurrent"].bool == true; ownConfirmed = proposal["ownConfirmed"].bool == true
        var confirmed: [String: [PlaySharedPlanAmount]] = [:]
        for (team, amounts) in proposal["confirmed"].object ?? [:] {
            guard (Int(team) ?? 0) > 0 else { throw PlayExperienceError.malformed }
            confirmed[team] = try PlaySharedPlanAmount.read(amounts)
        }
        self.confirmed = confirmed
        selected = proposalKey != nil && world["selected"].text == proposalKey
        sourceNodeID = plan["operationNodeId"].integer
        guard plan["operationNodeId"] == .null || (sourceNodeID ?? 0) > 0 else { throw PlayExperienceError.malformed }
        let tool = (player["interactionTools"].array ?? []).first { $0["kind"].text == "PLAN" && $0["endingKey"].text == ending } ?? .null
        let op = player["activeOperation"]
        let matchingOperation = op["operationKind"].text == "PLAN" && op["operationKey"].text == ending && op["sourceNodeId"].integer == sourceNodeID
        operationNodeID = matchingOperation ? op["nodeId"].integer : tool["nodeId"].integer
        bindingVersion = matchingOperation ? op["bindingVersion"].integer : tool["bindingVersion"].integer
        // Only the current original binding chooses the task node; never use an old author node as a substitute.
        started = selected && matchingOperation && (operationNodeID ?? 0) > 0 && (bindingVersion ?? 0) > 0
            && op["round"].integer == world["round"].integer
            && op["epoch"].integer == player["authorityEpoch"].integer && (op["receiptId"].integer ?? 0) > 0
        canFund = fund; canVote = vote; canAccept = accept; canExecute = execute
        canStart = selected && (operationNodeID ?? 0) > 0 && (bindingVersion ?? 0) > 0 && tool["enabled"].bool == true && tool["operation"].text == "OPERATION_START"
        reason = plan["actions"]["disabledReason"].text ?? tool["disabledReason"].text
    }
}
public struct PlaySharedPlanProjection: Equatable {
    /// Existing authoritative TEAM projection and inventory remain the only stock source.
    public let team: PlaySharedPlanTeamProjection
    public let ownerRevision, round: Int
    public let phase, policy: String
    public let rows: [PlaySharedPlanRow]
    public let ownVote, ownAcceptance, consensus, result: PlayWireValue
    public let ownRejectedAll: Bool
    let player, world: PlayWireValue
    let actions: Set<String>
    public init(_ raw: PlayWireValue, activityID: Int) throws {
        team = try PlaySharedPlanTeamProjection(raw, activityID: activityID)
        let p = raw["player"], w = p["world"]
        guard let revision = p["ownerRevision"].integer, revision >= 0,
              let round = w["round"].integer, (0..<Int(Int32.max)).contains(round),
              let phase = w["votePhase"].text, ["FUNDING", "VOTING", "TIED", "ACCEPTANCE", "CONSENSUS", "SELECTED", "EXECUTED", "FALLBACK"].contains(phase),
              let policy = w["votePolicy"].text, let plans = w["plans"].array, plans.count <= 100,
              let proposals = w["proposals"].array, proposals.count <= 100 else { throw PlayExperienceError.malformed }
        guard Set(proposals.compactMap { $0["proposalKey"].text }).count == proposals.count else { throw PlayExperienceError.malformed }
        ownerRevision = revision; self.round = round; self.phase = phase; self.policy = policy; player = p; world = w
        actions = Set((raw["availableActions"].array ?? []).compactMap(\.text))
        rows = try plans.map { try PlaySharedPlanRow($0, world: w, player: p) }
        guard Set(rows.map(\.id)).count == rows.count else { throw PlayExperienceError.malformed }
        ownVote = w["ownVote"]; ownAcceptance = w["ownAcceptance"]; consensus = w["consensus"]
        ownRejectedAll = w["ownRejectedAll"].bool == true
        result = w["result"] == .null ? w["lastOperationResult"] : w["result"]
        for ballot in [ownVote, ownAcceptance] {
            guard ballot == .null || (ballot.object != nil && ballot["ownSignatureCurrent"].bool != nil) else { throw PlayExperienceError.malformed }
        }
        if ownVote != .null { guard ownVote["planKey"].text != nil else { throw PlayExperienceError.malformed } }
        if ownAcceptance != .null {
            guard let choices = ownAcceptance["planKeys"].array, choices.allSatisfy({ $0.text != nil }) else { throw PlayExperienceError.malformed }
        }
        if result != .null { try PlaySharedPlanCommand.validateResult(result) }
    }
    public func allows(_ action: PlaySharedPlanAction, row: PlaySharedPlanRow? = nil) -> Bool {
        guard team.writable, actions.contains(action.rawValue) else { return false }
        switch action {
        case .propose: return row?.canFund == true && row?.proposalKey == nil
        case .intent: return row?.canFund == true && row?.proposalKey != nil
        case .withdraw: return row?.proposalKey != nil && row?.proposingTeamID == team.teamID
        case .vote: return phase == "VOTING" && (row == nil || row?.canVote == true)
        case .consensus: return phase == "CONSENSUS" && row?.canVote == true
        case .accept: return policy == "MAJORITY_ACCEPTANCE" && ["TIED", "ACCEPTANCE"].contains(phase) && (row == nil || row?.canAccept == true)
        case .confirm: return row?.selected == true && row?.signatureCurrent == true && row?.ownConfirmed == false && row?.ownIntent.isEmpty == false
        case .start: return row?.canStart == true
        case .cancel: return row?.started == true
        case .execute: return row?.selected == true && row?.canExecute == true
        case .change: return true
        case .rejectAll, .openVote: return phase == "FUNDING"
        case .nextVote: return phase == "TIED"
        }
    }
    func identity(_ row: PlaySharedPlanRow?) -> PlaySharedPlanIdentity {
        .init(teamID: team.teamID, ownerRevision: ownerRevision, round: round,
              endingKey: row?.endingKey, proposalKey: row?.proposalKey, proposalVersion: row?.version,
              operationNodeID: row?.operationNodeID, sourceNodeID: row?.sourceNodeID, bindingVersion: row?.bindingVersion, operationReceiptID: row?.started == true ? player["activeOperation"]["receiptId"].integer : nil)
    }
    func sameOwner(_ command: PlaySharedPlanCommand) -> Bool {
        team.activityID == command.activityID && team.sessionID == command.sessionID && team.teamID == command.identity.teamID
    }
}
public struct PlaySharedPlanCommand: Equatable {
    public let activityID, sessionID, memberID, revision, authorityEpoch: Int
    public let identity: PlaySharedPlanIdentity
    public let requestID: String
    public let action: PlaySharedPlanAction
    public let payload: PlayWireValue
    func validate() throws {
        guard [activityID, sessionID, memberID, authorityEpoch, identity.teamID].allSatisfy({ $0 > 0 }),
              (0..<Int(Int32.max)).contains(revision), identity.ownerRevision >= 0, (0..<Int(Int32.max)).contains(identity.round),
              requestID.range(of: "^[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil,
              let p = payload.object else { throw PlayExperienceError.invalidAction }
        func keys(_ expected: Set<String>) throws { guard Set(p.keys) == expected else { throw PlayExperienceError.invalidAction } }
        func proposal() throws {
            guard let key = payload["proposalKey"].text, PlaySharedPlanAmount.validKey(key), key == identity.proposalKey else { throw PlayExperienceError.invalidAction }
        }
        func round() throws { guard payload["round"].integer == identity.round, identity.round > 0 else { throw PlayExperienceError.invalidAction } }
        switch action {
        case .propose:
            try keys(["proposalKey", "endingKey"])
            guard let key = payload["proposalKey"].text, PlaySharedPlanAmount.validKey(key), identity.proposalKey == nil,
                  let ending = payload["endingKey"].text, PlaySharedPlanAmount.validKey(ending), ending == identity.endingKey else { throw PlayExperienceError.invalidAction }
        case .intent, .withdraw:
            try keys(action == .intent ? ["proposalKey", "version", "amounts"] : ["proposalKey", "version"]); try proposal()
            guard let version = payload["version"].integer, version > 0, version == identity.proposalVersion else { throw PlayExperienceError.invalidAction }
            if action == .intent { _ = try PlaySharedPlanAmount.read(payload["amounts"]) }
        case .vote, .consensus, .confirm, .execute:
            try keys(["round", "proposalKey"]); try round()
            if action == .vote && payload["proposalKey"].text == "REJECT" {
                guard identity.proposalKey == nil, identity.endingKey == nil else { throw PlayExperienceError.invalidAction }
            } else { try proposal() }
        case .accept:
            try keys(["round", "proposalKeys"]); try round()
            guard let values = payload["proposalKeys"].array, values.count <= 100,
                  values.allSatisfy({ $0.text.map(PlaySharedPlanAmount.validKey) == true }),
                  Set(values.compactMap(\.text)).count == values.count else { throw PlayExperienceError.invalidAction }
        case .start:
            try keys(["operationKind", "operationKey"])
            guard payload["operationKind"].text == "PLAN", let ending = payload["operationKey"].text,
                  ending == identity.endingKey, PlaySharedPlanAmount.validKey(ending), (identity.operationNodeID ?? 0) > 0, (identity.sourceNodeID ?? 0) > 0, (identity.bindingVersion ?? 0) > 0 else { throw PlayExperienceError.invalidAction }
        case .cancel:
            try keys([]); guard (identity.operationReceiptID ?? 0) > 0, identity.endingKey != nil else { throw PlayExperienceError.invalidAction }
        case .change, .rejectAll, .openVote, .nextVote: try keys([])
        }
    }
    var wire: PlayWireValue { .object(["activityId": .int(activityID), "expectedRevision": .int(revision), "authorityEpoch": .int(authorityEpoch),
        "requestId": .string(requestID), "action": .string(action.rawValue), "payload": payload]) }
    static func validateResult(_ value: PlayWireValue) throws {
        guard let ending = value["endingKey"].text, !ending.isEmpty, ending.utf16.count <= 128, value["title"].text != nil,
              value["summary"] == .null || value["summary"].text != nil, value["terminal"].bool != nil else { throw PlayExperienceError.malformed }
    }
}
extension PlayPendingGameCommand {
    init(plan command: PlaySharedPlanCommand, session: PlayExperienceSession) throws {
        try command.validate(); guard command.memberID == session.accountID else { throw PlayExperienceError.staleSession }
        owner = .init(session: session); originEpoch = session.epoch; activityID = command.activityID; nodeID = nil
        requestID = command.requestID; expectedRevision = command.revision; action = command.action.rawValue; authorityEpoch = command.authorityEpoch
        sharedPlanIdentity = command.identity; sessionID = command.sessionID
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; payload = try encoder.encode(command.payload)
        guard try planCommand() == command else { throw PlayExperienceError.persistenceUnavailable }
    }
    func planCommand() throws -> PlaySharedPlanCommand {
        guard let action = PlaySharedPlanAction(rawValue: action), let identity = sharedPlanIdentity, let epoch = authorityEpoch,
              nodeID == nil,
              owner.role == "player", !owner.namespace.isEmpty, originEpoch > 0, payload.count <= 65536 else { throw PlayExperienceError.persistenceUnavailable }
        let command = PlaySharedPlanCommand(activityID: activityID, sessionID: sessionID, memberID: owner.accountID,
            revision: expectedRevision, authorityEpoch: epoch, identity: identity, requestID: requestID, action: action,
            payload: try JSONDecoder().decode(PlayWireValue.self, from: payload))
        try command.validate(); return command
    }
}
public struct PlaySharedPlanReceipt: Equatable {
    public let requestID, outcome: String
    public let action: PlaySharedPlanAction
    public let receiptID, revision: Int
    public let result: PlayWireValue
    public let reason: String?
    init(_ raw: PlayWireValue, command: PlaySharedPlanCommand) throws {
        guard raw["activityId"].integer == command.activityID, raw["requestId"].text == command.requestID else { throw PlayExperienceError.malformed }
        if raw["outcome"].text == "PENDING" { throw PlayExperienceError.unknownResult }
        guard raw["action"].text == command.action.rawValue, let outcome = raw["outcome"].text, ["APPLIED", "FAILED"].contains(outcome),
              let id = raw["receiptId"].integer, id > 0, let revision = raw["revision"].integer, revision >= 0 else { throw PlayExperienceError.malformed }
        requestID = command.requestID; action = command.action; self.outcome = outcome; receiptID = id; self.revision = revision
        reason = PlayThemeText.clean(raw["message"].text ?? raw["reasonCode"].text); result = raw["result"]
        guard outcome == "APPLIED" else { return }
        guard revision == command.revision + 1, result["receiptOwnerTeamId"].integer == command.identity.teamID else { throw PlayExperienceError.malformed }
        let value = result["result"], world = result["cooperation"], key = command.payload["proposalKey"].text
        let proposal = (world["proposals"].array ?? []).first { $0["proposalKey"].text == key } ?? .null
        switch action {
        case .propose, .intent, .withdraw:
            guard value["proposalKey"].text == key, value["endingKey"].text == command.identity.endingKey,
                  value["version"].integer == (action == .propose ? 1 : command.identity.proposalVersion),
                  value["status"].text == (action == .withdraw ? "WITHDRAWN" : "OPEN") else { throw PlayExperienceError.malformed }
            if action == .propose { guard value["teamId"].integer == command.identity.teamID else { throw PlayExperienceError.malformed } }
            if action == .intent {
                guard proposal["ownIntent"]["signatureCurrent"].bool == true,
                      try PlaySharedPlanAmount.read(proposal["ownIntent"]["amounts"]) == PlaySharedPlanAmount.read(command.payload["amounts"]) else { throw PlayExperienceError.malformed }
            }
        case .change:
            guard value["stage"].text == "DRAFT", value["round"].integer == command.identity.round + 1 else { throw PlayExperienceError.malformed }
        case .openVote, .nextVote:
            guard value["stage"].text == "VOTING", value["round"].integer == command.identity.round + 1 else { throw PlayExperienceError.malformed }
        case .rejectAll:
            guard value["rejectedAll"].bool == true, world["ownRejectedAll"].bool == true else { throw PlayExperienceError.malformed }
        case .vote:
            guard world["round"].integer == command.identity.round, world["ownVote"]["planKey"].text == key,
                  world["ownVote"]["ownSignatureCurrent"].bool == true else { throw PlayExperienceError.malformed }
        case .accept:
            guard world["round"].integer == command.identity.round, world["ownAcceptance"]["ownSignatureCurrent"].bool == true,
                  let choices = world["ownAcceptance"]["planKeys"].array, choices.allSatisfy({ $0.text != nil }),
                  Set(choices.compactMap(\.text)).count == choices.count,
                  Set(choices.compactMap(\.text)) == Set((command.payload["proposalKeys"].array ?? []).compactMap(\.text)) else { throw PlayExperienceError.malformed }
        case .consensus:
            guard world["round"].integer == command.identity.round, world["consensus"][String(command.identity.teamID)].text == key else { throw PlayExperienceError.malformed }
        case .confirm:
            guard world["round"].integer == command.identity.round, world["selected"].text == key,
                  proposal["ownConfirmed"].bool == true else { throw PlayExperienceError.malformed }
        case .execute:
            try PlaySharedPlanCommand.validateResult(value)
            guard value["endingKey"].text == command.identity.endingKey, value["proposalKey"].text == key,
                  value["round"].integer == command.identity.round, value["eventId"].text == "receipt:\(id)",
                  value["contributions"].object != nil else { throw PlayExperienceError.malformed }
        case .start:
            let op = result["operation"]
            guard op["operationKind"].text == "PLAN", op["operationKey"].text == command.identity.endingKey,
                  op["nodeId"].integer == command.identity.operationNodeID, op["sourceNodeId"].integer == command.identity.sourceNodeID,
                  op["bindingVersion"].integer == command.identity.bindingVersion, op["round"].integer == command.identity.round,
                  op["epoch"].integer == command.authorityEpoch, op["receiptId"].integer == id else { throw PlayExperienceError.malformed }
        case .cancel:
            guard result["operation"] == .null || result["operation"] == .object([:]) else { throw PlayExperienceError.malformed }
        }
    }
}
public struct PlaySharedPlanReview: Equatable, Identifiable {
    public let id: UUID
    public let command: PlaySharedPlanCommand
    public let title: String
    let source: PlaySharedPlanProjection
}
public struct PlaySharedPlanOperationTicket: Equatable, Identifiable {
    public let id: UUID
    public let activityID, sessionID, teamID, memberID, nodeID, sourceNodeID, bindingVersion, authorityEpoch, round, receiptID: Int
    public let endingKey, proposalKey: String
}
@available(macOS 14.0, *)
@MainActor @Observable public final class PlaySharedPlanLifecycle {
    public let activityID: Int
    public private(set) var projection: PlaySharedPlanProjection?
    public private(set) var review: PlaySharedPlanReview?
    public private(set) var pending: PlaySharedPlanCommand?
    public private(set) var receipt: PlaySharedPlanReceipt?
    public private(set) var operationTicket: PlaySharedPlanOperationTicket?
    public private(set) var busy = false
    public private(set) var ready = false
    public private(set) var anotherActionPending = false
    public private(set) var message: String?
    private let owner: PlayExperienceSession
    private let service: PlayExperienceService
    private let journal: any PlayGameCommandJournal
    private let current, canWrite: () -> Bool
    private let retireConfirmedJournal: Bool
    private let onUnauthorized: () -> Void
    private var generation: UInt64 = 0
    public init(activityID: Int, session: PlayExperienceSession, service: PlayExperienceService, journal: any PlayGameCommandJournal,
        current: @escaping () -> Bool, canWrite: @escaping () -> Bool = { false }, retireConfirmedJournal: Bool = false, onUnauthorized: @escaping () -> Void) {
        self.retireConfirmedJournal = retireConfirmedJournal
        self.activityID = activityID; owner = session; self.service = service; self.journal = journal
        self.current = current; self.canWrite = canWrite; self.onUnauthorized = onUnauthorized
    }
    public var isCurrent: Bool { owner.role == "player" && current() }
    public var writesEnabled: Bool { isCurrent && canWrite() && service.enabled.contains(.playerCommands) }
    public var canInteract: Bool { current() && ready && !busy && pending == nil && !anotherActionPending && operationTicket == nil }
    private var key: String { PlayRunStorageKey.make(session: owner, scope: .activity(activityID)) }
    public func invalidateReview() { review = nil }
    public func suspend() {
        generation &+= 1; projection = nil; review = nil; receipt = nil; pending = nil; operationTicket = nil; ready = false; busy = false; message = nil
    }
    private func check(_ issued: UInt64) throws {
        try Task.checkCancellation(); guard issued == generation, isCurrent else { throw PlayExperienceError.staleSession }
    }
    private func read(_ issued: UInt64) async throws -> PlaySharedPlanProjection {
        let raw = try await service.sharedPlanRequest(activityID: activityID, token: owner.token, finalCheck: { try self.check(issued) })
        try check(issued); return try PlaySharedPlanProjection(raw, activityID: activityID)
    }
    private func restore(_ issued: UInt64) async throws -> PlayGameCommandJournalSnapshot? {
        let stored = try await journal.readGameCommand(key); try check(issued); pending = nil; anotherActionPending = false
        guard let stored else { return nil }
        guard stored.value.owner.matches(owner), stored.value.activityID == activityID else { throw PlayExperienceError.persistenceUnavailable }
        // Action name alone is insufficient: OPERATION_* has other original consumers.
        if stored.value.sharedPlanIdentity == nil {
            _ = try stored.value.command(); anotherActionPending = true; return nil
        }
        pending = try stored.value.planCommand(); return stored
    }
    public func load() async {
        guard !busy, isCurrent, operationTicket == nil else { return }; busy = true; ready = false; review = nil
        let issued = generation; defer { if generation == issued { busy = false } }
        do {
            let lease = try await restore(issued); let fresh = try await read(issued); projection = fresh
            if let lease {
                let command = try lease.value.planCommand(); guard fresh.sameOwner(command) else { throw PlayExperienceError.staleSession }
                // Changed captain/epoch revokes writes, never changes the original command or its ID.
                let raw = try await service.sharedPlanRequest(activityID: activityID, token: owner.token, command: command, receipt: true,
                    finalCheck: { try self.check(issued) })
                try check(issued); try await accept(PlaySharedPlanReceipt(raw, command: command), lease: lease, issued: issued)
            } else {
                ready = !anotherActionPending; message = anotherActionPending ? "本局另有原操作待确认，请回原入口核对；这里不会替它清锁。" : nil
            }
        } catch { fail(error, issued) }
    }
    public func prepare(_ action: PlaySharedPlanAction, endingKey: String? = nil, quantities: [String: String] = [:], acceptance: Set<String> = []) async {
        guard canInteract, writesEnabled, let shown = projection else { return }
        busy = true; ready = false; review = nil; let issued = generation; defer { if generation == issued { busy = false } }
        do {
            guard try await restore(issued) == nil, !anotherActionPending else { throw PlayExperienceError.unknownResult }
            let fresh = try await read(issued); projection = fresh
            guard sameReview(shown, fresh) else { throw PlayExperienceError.staleSession }
            let row = fresh.rows.first { $0.endingKey == endingKey }
            guard endingKey == nil || row != nil, fresh.allows(action, row: row) else { throw PlayExperienceError.invalidAction }
            var payload: [String: PlayWireValue] = [:]
            switch action {
            case .propose:
                payload = ["proposalKey": .string("plan_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(26))), "endingKey": .string(row!.endingKey)]
            case .intent, .withdraw:
                guard let row, let proposal = row.proposalKey, let version = row.version else { throw PlayExperienceError.invalidAction }
                payload = ["proposalKey": .string(proposal), "version": .int(version)]
                if action == .intent {
                    guard Set(quantities.keys).isSubset(of: Set(row.cost.map(\.itemID))) else { throw PlayExperienceError.invalidAction }
                    let amounts = try row.cost.compactMap { cost -> PlaySharedPlanAmount? in
                        let text = (quantities[cost.itemID] ?? "0").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard text.range(of: "^[0-9]{1,3}$", options: .regularExpression) != nil, let value = Int(text), value <= cost.quantity,
                              let item = fresh.team.items.first(where: { $0.id == cost.itemID }), let available = item.available, value <= available else { throw PlayExperienceError.invalidAction }
                        return value == 0 ? nil : .init(itemID: cost.itemID, quantity: value)
                    }
                    payload["amounts"] = .array(amounts.map(\.wire))
                }
            case .vote, .consensus, .confirm, .execute:
                payload = ["round": .int(fresh.round), "proposalKey": .string(row?.proposalKey ?? "REJECT")]
            case .accept:
                let eligible = Set(fresh.rows.filter { fresh.allows(.accept, row: $0) }.compactMap(\.proposalKey))
                guard acceptance.isSubset(of: eligible) else { throw PlayExperienceError.invalidAction }
                payload = ["round": .int(fresh.round), "proposalKeys": .array(acceptance.sorted().map(PlayWireValue.string))]
            case .start: payload = ["operationKind": .string("PLAN"), "operationKey": .string(row!.endingKey)]
            case .cancel, .change, .rejectAll, .openVote, .nextVote: break
            }
            let command = PlaySharedPlanCommand(activityID: activityID, sessionID: fresh.team.sessionID, memberID: owner.accountID,
                revision: fresh.team.revision, authorityEpoch: fresh.team.authorityEpoch, identity: fresh.identity(row), requestID: UUID().uuidString,
                action: action, payload: .object(payload))
            try command.validate(); review = .init(id: UUID(), command: command, title: row?.title ?? action.title, source: fresh); ready = true
        } catch { fail(error, issued) }
    }
    private func sameReview(_ a: PlaySharedPlanProjection, _ b: PlaySharedPlanProjection) -> Bool {
        // Ignore unrelated observation-time fields such as the manual-sign upper time bound.
        a.team == b.team && a.ownerRevision == b.ownerRevision && a.world == b.world && a.actions == b.actions
            && a.rows == b.rows && a.player["currentNodeId"] == b.player["currentNodeId"]
            && a.player["activeOperation"] == b.player["activeOperation"] && a.player["interactionTools"] == b.player["interactionTools"]
    }
    public func commit(_ offered: PlaySharedPlanReview) async {
        guard canInteract, writesEnabled, review == offered else { return }
        busy = true; ready = false; review = nil; receipt = nil; let issued = generation; defer { if generation == issued { busy = false } }
        do {
            guard try await restore(issued) == nil, !anotherActionPending else { throw PlayExperienceError.unknownResult }
            let fresh = try await read(issued); projection = fresh
            let row = fresh.rows.first { $0.endingKey == offered.command.identity.endingKey }
            guard sameReview(offered.source, fresh), fresh.allows(offered.command.action, row: row), writesEnabled else { throw PlayExperienceError.staleSession }
            let value = try PlayPendingGameCommand(plan: offered.command, session: owner); pending = offered.command
            let lease = try await journal.recordGameCommand(value, key: key); try check(issued)
            guard lease.value == value, try lease.value.planCommand() == offered.command else { throw PlayExperienceError.persistenceUnavailable }
            // One and only POST after durable CAS. Every later attempt is receipt-only.
            let raw = try await service.sharedPlanRequest(activityID: activityID, token: owner.token, command: offered.command,
                finalCheck: { try self.check(issued); guard self.writesEnabled else { throw PlayExperienceError.disabled } })
            try check(issued); try await accept(PlaySharedPlanReceipt(raw, command: offered.command), lease: lease, issued: issued)
        } catch { fail(error, issued) }
    }
    private func accept(_ value: PlaySharedPlanReceipt, lease: PlayGameCommandJournalSnapshot, issued: UInt64) async throws {
        try check(issued); let command = try lease.value.planCommand(); receipt = value
        let fresh = try await read(issued)
        guard fresh.sameOwner(command), fresh.team.revision >= value.revision else { throw PlayExperienceError.malformed }
        if !retireConfirmedJournal {
            projection = fresh; ready = false
            message = "已核对原回执；原请求日志保留，未开放后续写入。"
            return
        }
        // A subsequent change may reset the round. Only the matching durable receipt proves this command.
        try check(issued); try await journal.clearGameCommand(lease, key: key); try check(issued)
        projection = fresh; pending = nil; ready = true
        message = value.outcome == "FAILED" ? "原请求明确失败，未换 ID 重做。" : value.action == .execute
            ? "已取得本次执行原回执并回读当前公共结果；终态以原结果 terminal 为准。" : "本次原请求已回执并回读。提出、意向、投票、选定及托管均不等于已执行。"
    }
    public func prepareOperation(endingKey: String) async {
        guard canInteract, writesEnabled, let shown = projection, shown.team.writable else { return }
        busy = true; review = nil; let issued = generation; defer { if generation == issued { busy = false } }
        do {
            guard try await restore(issued) == nil, !anotherActionPending else { throw PlayExperienceError.unknownResult }
            let fresh = try await read(issued); projection = fresh
            guard sameReview(shown, fresh), fresh.team.writable, let row = fresh.rows.first(where: { $0.endingKey == endingKey }), row.started,
                  let node = row.operationNodeID, let sourceNode = row.sourceNodeID, let binding = row.bindingVersion, let proposal = row.proposalKey, let receipt = fresh.player["activeOperation"]["receiptId"].integer else { throw PlayExperienceError.staleSession }
            operationTicket = .init(id: UUID(), activityID: activityID, sessionID: fresh.team.sessionID, teamID: fresh.team.teamID,
                memberID: owner.accountID, nodeID: node, sourceNodeID: sourceNode, bindingVersion: binding, authorityEpoch: fresh.team.authorityEpoch, round: fresh.round, receiptID: receipt,
                endingKey: row.endingKey, proposalKey: proposal)
        } catch { fail(error, issued) }
    }
    public func operationIsCurrent(_ ticket: PlaySharedPlanOperationTicket) -> Bool {
        writesEnabled && operationTicket == ticket && pending == nil && !anotherActionPending
    }
    public func validateOperation(_ ticket: PlaySharedPlanOperationTicket) async throws {
        guard operationIsCurrent(ticket) else { throw PlayExperienceError.staleSession }; let issued = generation
        do {
            guard try await restore(issued) == nil, !anotherActionPending else { throw PlayExperienceError.unknownResult }
            let fresh = try await read(issued); let op = fresh.player["activeOperation"]
            guard operationIsCurrent(ticket), fresh.team.writable, fresh.team.sessionID == ticket.sessionID, fresh.team.teamID == ticket.teamID,
                  owner.accountID == ticket.memberID, fresh.team.authorityEpoch == ticket.authorityEpoch, fresh.round == ticket.round,
                  fresh.world["selected"].text == ticket.proposalKey, op["operationKind"].text == "PLAN", op["operationKey"].text == ticket.endingKey,
                  op["nodeId"].integer == ticket.nodeID, op["sourceNodeId"].integer == ticket.sourceNodeID,
                  op["bindingVersion"].integer == ticket.bindingVersion, op["receiptId"].integer == ticket.receiptID,
                  op["round"].integer == ticket.round, op["epoch"].integer == ticket.authorityEpoch else { throw PlayExperienceError.staleSession }
            projection = fresh
        } catch { operationTicket = nil; fail(error, issued); throw error }
    }
    public func closeOperation() async { operationTicket = nil; await load() }
    func operationAuthenticationRevoked() { operationTicket = nil; fail(PlayExperienceError.unauthorized, generation) }
    private func fail(_ error: Error, _ issued: UInt64) {
        guard issued == generation else { return }
        if case PlayExperienceError.unauthorized = error { projection = nil; review = nil; receipt = nil; operationTicket = nil; onUnauthorized() }
        guard isCurrent else { suspend(); return }; ready = false; review = nil
        if pending != nil { message = "原请求结果或回读仍待确认；已保留原 ID、完整命令与安全锁，只读原回执，绝不自动重发。" }
        else if anotherActionPending { message = "本局另有原操作待确认，请回原入口恢复；这里不清除其它操作的锁。" }
        else if case PlayExperienceError.persistenceUnavailable = error { message = "原安全日志未能确认，不能提交新方案动作。" }
        else { message = "本队、队长、版本、权限或票轮已变化／尚未确认。请刷新后重新核对；未据此认定操作成功。" }
    }
}
