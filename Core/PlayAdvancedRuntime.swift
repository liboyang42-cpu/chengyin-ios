import Foundation
import Observation

public struct PlayAdvancedState: Equatable {
    public let sessionID: Int; public let activityID: Int; public let topicID: Int; public let nodeID: Int
    public let status: String; public let version: Int; public let score: Int?
    public let readyForBase: Bool; public let deadlineAt: Int64?; public let inline: Bool
    public let config: PlayWireValue; public let draws: [PlayWireValue]; public let branch: PlayWireValue
    public let playKit: PlayWireValue; public let multiplayer: PlayWireValue
    public var isMultiplayer: Bool { config["multiplayer"]["enabled"].bool == true }
    public var needsUnverifiedSteps: Bool { playKit["steps"].object != nil && playKit["steps"]["reached"].bool != true }
    public init(_ raw: PlayWireValue) throws {
        guard let session = raw["sessionId"].integer, session > 0, let node = raw["nodeId"].integer, node > 0,
              let version = raw["version"].integer, version >= 0,
              let activity = raw["activityId"].integer, activity >= 0,
              let topic = raw["topicId"].integer, topic > 0,
              let status = raw["status"].text, !status.isEmpty else { throw PlayExperienceError.malformed }
        sessionID = session; activityID = activity; topicID = topic; nodeID = node; self.version = version; self.status = status
        score = raw["score"].integer; readyForBase = raw["readyForBase"].bool == true
        deadlineAt = raw["deadlineAt"].integer.flatMap { $0 > 0 ? Int64($0) : nil }
        inline = raw["present"].text == "inline"; config = raw["config"]; draws = raw["draws"].array ?? []
        branch = raw["branch"]; playKit = raw["playKit"]; multiplayer = raw["multiplayer"]
    }
    public func remainingSeconds(nowMilliseconds: Int64) -> Int? {
        deadlineAt.map { Int(max(0, ceil(Double($0 - nowMilliseconds) / 1000))) }
    }
}
public enum PlayKitActionCatalog {
    /// Source: playkit_host.dart. Local-only kits intentionally have an empty action set.
    public static let actions: [String: Set<String>] = [
        "qa": ["SUBMIT_QA"], "branch": ["CHOOSE"], "estimate": ["SUBMIT_ESTIMATE"],
        "pricePair": ["SUBMIT_PRICE_PAIR"], "hiddenObject": ["SUBMIT_HIDDEN_OBJECT"],
        "countdown": ["START_CHALLENGE", "SUBMIT_COUNTDOWN"], "stopwatch": ["START_CHALLENGE", "SUBMIT_STOPWATCH"],
        "blindTaste": ["SUBMIT_BLIND_TASTE"], "diyName": ["SUBMIT_DIY_NAME"], "steps": ["SUBMIT_STEPS"],
        "dailySign": ["CLAIM_DAILY_SIGN"], "slowTask": ["START_SLOW_TASK", "CLAIM_SLOW_TASK"], "silentOrder": [],
        "coinFlip": ["FLIP_COIN"], "diceRoll": ["ROLL_DICE"], "predict": ["SUBMIT_PREDICT"],
        "reaction": ["START_CHALLENGE", "SUBMIT_REACTION"], "ballShake": ["START_CHALLENGE", "SUBMIT_BALL_SHAKE"],
        "quietHold": ["START_CHALLENGE", "SUBMIT_QUIET_HOLD"], "random": ["DRAW"], "scan": ["SUBMIT_SCAN"],
        "profile": ["SUBMIT_PROFILE"], "photoCheck": ["SUBMIT_PHOTO_CHECK"], "note": ["SUBMIT_NOTE"],
        "typeIn": ["START_CHALLENGE", "SUBMIT_TYPE_IN"], "timeWindow": [], "walk": [], "gameTimer": [], "stickerBook": [], "bingo": []
    ]
    public static func payload(kind: String, action: String, detail: [String: PlayWireValue]) throws -> [String: PlayWireValue] {
        guard actions[kind]?.contains(action) == true else { throw PlayExperienceError.unsupported }
        switch action {
        case "FLIP_COIN", "ROLL_DICE": return [:] // Never invent a random outcome client-side.
        case "START_CHALLENGE":
            if ["reaction", "ballShake", "quietHold", "typeIn"].contains(kind) { return ["game": .string(kind)] }
            return detail
        case "SUBMIT_REACTION":
            guard let times = detail["times"]?.array, !times.isEmpty, times.allSatisfy({ ($0.integer ?? -1) >= 0 }) else { throw PlayExperienceError.invalidAction }
            return ["roundsMs": .array(times)]
        case "SUBMIT_QUIET_HOLD":
            guard let seconds = detail["heldSeconds"]?.double, seconds.isFinite, seconds >= 0, seconds <= 3600 else { throw PlayExperienceError.invalidAction }
            return ["heldMs": .int(Int((seconds * 1000).rounded()))]
        case "SUBMIT_BALL_SHAKE":
            guard let hits = detail["hits"]?.integer, hits >= 0 else { throw PlayExperienceError.invalidAction }
            return ["hits": .int(hits)]
        default: return detail
        }
    }
}
public struct PlayAdvancedPending: Equatable {
    public let sessionID: Int; public let version: Int; public let key: String
    public let action: String; public let payload: [String: PlayWireValue]
}
extension PlayExperienceService {
    public func startAdvanced(activityID: Int, topicID: Int, nodeID: Int, token: String) async throws -> PlayAdvancedState {
        guard activityID >= 0, topicID > 0, nodeID > 0 else { throw APIError.invalidRequest }
        let state = try PlayAdvancedState(await request("api/play/advanced/start", json: ["activityId": .int(activityID), "topicId": .int(topicID), "nodeId": .int(nodeID)], capability: .advanced, token: token))
        guard state.activityID == activityID, state.topicID == topicID, state.nodeID == nodeID else { throw PlayExperienceError.malformed }
        return state
    }
    public func advancedState(sessionID: Int, token: String) async throws -> PlayAdvancedState {
        guard sessionID > 0 else { throw APIError.invalidRequest }
        let state = try PlayAdvancedState(await request("api/play/advanced/state", query: ["sessionId": String(sessionID)], capability: .reads, token: token))
        guard state.sessionID == sessionID else { throw PlayExperienceError.malformed }; return state
    }
    public func advancedAction(_ pending: PlayAdvancedPending, token: String) async throws -> PlayAdvancedState {
        guard pending.sessionID > 0, pending.version >= 0, !pending.key.isEmpty else { throw APIError.invalidRequest }
        let state = try PlayAdvancedState(await request("api/play/advanced/action", json: [
            "sessionId": .int(pending.sessionID), "version": .int(pending.version), "idempotencyKey": .string(pending.key),
            "action": .string(pending.action), "payload": .object(pending.payload)
        ], capability: .advanced, token: token))
        guard state.sessionID == pending.sessionID, state.version > pending.version else { throw PlayExperienceError.malformed }; return state
    }
    public func advancedLeaderboard(activityID: Int, topicID: Int, nodeID: Int, token: String) async throws -> [PlayWireValue] {
        guard activityID >= 0, topicID > 0, nodeID > 0 else { throw APIError.invalidRequest }
        let value = try await request("api/play/advanced/leaderboard", query: ["activityId": String(activityID), "topicId": String(topicID), "nodeId": String(nodeID)], capability: .reads, token: token)
        guard let rows = value.array, rows.allSatisfy({ ($0["rank"].integer ?? 0) > 0 && ($0["ownerId"].integer ?? 0) > 0 && $0["score"].integer != nil && ($0["elapsedSeconds"].integer ?? -1) >= 0 && ($0["completedUnits"].integer ?? -1) >= 0 && $0["displayName"].text?.isEmpty == false }) else { throw PlayExperienceError.malformed }
        return rows
    }
}
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayAdvancedCoordinator {
    public private(set) var state: PlayAdvancedState?
    public private(set) var pending: PlayAdvancedPending?
    public private(set) var phase = "idle"
    public private(set) var issue: PlayExperienceError?
    public private(set) var leaderboard: [PlayWireValue] = []
    let activityID: Int; let topicID: Int; let nodeID: Int
    let service: PlayExperienceService
    let currentSession: () -> PlayExperienceSession?
    private var owner: PlayExperienceSession?
    private var generation: UInt64 = 0
    public init(activityID: Int, topicID: Int, nodeID: Int, service: PlayExperienceService, currentSession: @escaping () -> PlayExperienceSession?) {
        self.activityID = activityID; self.topicID = topicID; self.nodeID = nodeID; self.service = service; self.currentSession = currentSession
    }
    public func start() async {
        guard state == nil, ["idle", "rejected", "disabled"].contains(phase), let session = currentSession() else { return }
        generation &+= 1; let generation = generation; owner = session; phase = "loading"
        do { try accept(await service.startAdvanced(activityID: activityID, topicID: topicID, nodeID: nodeID, token: session.token), session: session, generation: generation) }
        catch { failure(error, session: session, generation: generation) }
    }
    public func submit(kind: String, action: String, detail: [String: PlayWireValue] = [:]) async {
        guard phase == "ready", pending == nil, let state, !state.needsUnverifiedSteps, state.status == "RUNNING", owner == currentSession() else { return }
        do {
            // Dispatch only a server-present kit or an enabled mechanical section.
            guard state.playKit[kind].object != nil || state.config[kind]["enabled"].bool == true else { throw PlayExperienceError.unsupported }
            let payload = try PlayKitActionCatalog.payload(kind: kind, action: action, detail: detail)
            pending = PlayAdvancedPending(sessionID: state.sessionID, version: state.version, key: UUID().uuidString, action: action, payload: payload)
            await sendPending()
        } catch { issue = error as? PlayExperienceError ?? .invalidAction }
    }
    public func assignRole(memberID: Int, roleID: String) async {
        guard phase == "ready", pending == nil, let state, state.isMultiplayer, owner == currentSession(),
              state.multiplayer["members"].array?.contains(where: { $0["memberId"].integer == memberID }) == true,
              state.config["multiplayer"]["roles"].array?.contains(where: { $0["id"].text == roleID }) == true else { return }
        pending = .init(sessionID: state.sessionID, version: state.version, key: UUID().uuidString, action: "ASSIGN_ROLE", payload: ["memberId": .int(memberID), "roleId": .string(roleID)])
        await sendPending()
    }
    public func completeUnit() async {
        guard phase == "ready", pending == nil, let state, state.isMultiplayer, state.status == "RUNNING", owner == currentSession() else { return }
        // Source builds one unit per session/version. This is a local idempotency identity, not outcome proof.
        let unitID = "unit-\(state.sessionID)-v\(state.version)"
        pending = .init(sessionID: state.sessionID, version: state.version, key: UUID().uuidString, action: "COMPLETE_UNIT", payload: ["unitId": .string(unitID)])
        await sendPending()
    }
    private func sendPending() async {
        guard let pending, let session = owner, session == currentSession() else { return }
        let generation = generation; phase = "submitting"
        do {
            let result = try await service.advancedAction(pending, token: session.token)
            try accept(result, session: session, generation: generation); self.pending = nil
        } catch { failure(error, session: session, generation: generation) }
    }
    public func recover() async {
        guard let pending, let session = owner, session == currentSession(), phase == "unknown" else { return }
        let generation = generation; phase = "loading"
        do {
            let result = try await service.advancedState(sessionID: pending.sessionID, token: session.token)
            try validate(result, session: session, generation: generation)
            guard result.version >= pending.version else { throw PlayExperienceError.malformed }
            state = result
            // Version advancement alone is NOT proof, including on a single-user run.
            // Expose only replay of the frozen idempotent request after explicit review.
            phase = "retryable"
        } catch { failure(error, session: session, generation: generation) }
    }
    public func retryExact() async { guard phase == "retryable" else { return }; await sendPending() }
    public func refreshAuthoritative() async {
        if pending != nil { if phase == "unknown" { await recover() }; return }
        guard phase != "submitting", let state, let session = owner, session == currentSession() else { return }
        let generation = generation; phase = "loading"
        do { try accept(await service.advancedState(sessionID: state.sessionID, token: session.token), session: session, generation: generation) }
        catch { failure(error, session: session, generation: generation) }
    }
    private func validate(_ state: PlayAdvancedState, session: PlayExperienceSession, generation: UInt64) throws {
        guard self.generation == generation, currentSession() == session, !Task.isCancelled else { throw PlayExperienceError.staleSession }
        guard state.activityID == activityID, state.topicID == topicID, state.nodeID == nodeID,
              self.state == nil || self.state?.sessionID == state.sessionID else { throw PlayExperienceError.malformed }
    }
    private func accept(_ state: PlayAdvancedState, session: PlayExperienceSession, generation: UInt64) throws {
        try validate(state, session: session, generation: generation); self.state = state; issue = nil
        phase = state.needsUnverifiedSteps ? "unsupported" : "ready"
    }
    private func failure(_ error: Error, session: PlayExperienceSession, generation: UInt64) {
        guard self.generation == generation else { return }
        guard currentSession() == session else { self.state = nil; phase = "stale"; return }
        issue = error as? PlayExperienceError ?? .unknownResult
        if case PlayExperienceError.rejected = error { pending = nil; phase = "rejected" }
        else if case PlayExperienceError.disabled = error { pending = nil; phase = "disabled" }
        else { phase = "unknown" }
    }
}
