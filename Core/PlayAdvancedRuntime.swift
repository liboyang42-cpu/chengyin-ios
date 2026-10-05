import Foundation
import Observation

public struct PlayAdvancedState: Equatable {
    public let sessionID: Int; public let activityID: Int; public let topicID: Int; public let nodeID: Int
    public let status: String; public let version: Int; public let score: Int?
    public let ownerType: Int?
    public let readyForBase: Bool; public let deadlineAt: Int64?; public let inline: Bool
    public let config: PlayWireValue; public let draws: [PlayWireValue]; public let branch: PlayWireValue
    public let playKit: PlayWireValue; public let multiplayer: PlayWireValue
    public let storyVariables: [String: PlayWireValue]
    public let objectCard: ObjectCard?
    public var isMultiplayer: Bool { config["multiplayer"]["enabled"].bool == true }
    public var needsUnverifiedSteps: Bool { playKit["steps"].object != nil && playKit["steps"]["reached"].bool != true }
    public init(_ raw: PlayWireValue) throws {
        guard let session = raw["sessionId"].integer, session > 0, let node = raw["nodeId"].integer, node > 0,
              let version = raw["version"].integer, version >= 0,
              let activity = raw["activityId"].integer, activity >= 0,
              let topic = raw["topicId"].integer, topic > 0,
              let status = raw["status"].text, !status.isEmpty else { throw PlayExperienceError.malformed }
        sessionID = session; activityID = activity; topicID = topic; nodeID = node; self.version = version; self.status = status
        ownerType = raw["ownerType"].integer
        score = raw["score"].integer; readyForBase = raw["readyForBase"].bool == true
        deadlineAt = raw["deadlineAt"].integer.flatMap { $0 > 0 ? Int64($0) : nil }
        inline = raw["present"].text == "inline"; config = raw["config"]; draws = raw["draws"].array ?? []
        branch = raw["branch"]; playKit = raw["playKit"]; multiplayer = raw["multiplayer"]
        storyVariables = raw["vars"].object ?? [:]
        objectCard = PlayObjectCardReceiptDecoder.decode(raw["objectCard"])
    }
    public func remainingSeconds(nowMilliseconds: Int64) -> Int? {
        deadlineAt.map { Int(max(0, ceil(Double($0 - nowMilliseconds) / 1000))) }
    }
}
public enum PlayKitActionCatalog {
    /// Source: Flutter playkit_host.dart plus the newer mini-program playkit-view action catalog.
    /// Bingo is server progress without an action. Walk cannot manufacture encrypted step proof.
    public static let actions: [String: Set<String>] = [
        "sort": ["SUBMIT_SORT"], "match": ["SUBMIT_MATCH"], "classify": ["SUBMIT_CLASSIFY"],
        "compare": ["SUBMIT_COMPARE"], // Current backend-only family, absent from historical client hosts.
        "compass": ["SUBMIT_COMPASS"], "shout": ["START_CHALLENGE", "SUBMIT_SHOUT"],
        "qa": ["SUBMIT_QA"], "branch": ["CHOOSE"], "estimate": ["SUBMIT_ESTIMATE"],
        "pricePair": ["SUBMIT_PRICE_PAIR"], "hiddenObject": ["SUBMIT_HIDDEN_OBJECT"],
        "countdown": ["START_CHALLENGE", "SUBMIT_COUNTDOWN"], "stopwatch": ["START_CHALLENGE", "SUBMIT_STOPWATCH"],
        "blindTaste": ["SUBMIT_BLIND_TASTE"], "diyName": ["SUBMIT_DIY_NAME"], "steps": ["SUBMIT_STEPS"],
        "dailySign": ["CLAIM_DAILY_SIGN"], "slowTask": ["START_SLOW_TASK", "CLAIM_SLOW_TASK"], "silentOrder": [],
        "coinFlip": ["FLIP_COIN"], "diceRoll": ["ROLL_DICE"], "predict": ["SUBMIT_PREDICT"],
        "reaction": ["START_CHALLENGE", "SUBMIT_REACTION"], "ballShake": ["START_CHALLENGE", "SUBMIT_BALL_SHAKE"],
        "quietHold": ["START_CHALLENGE", "SUBMIT_QUIET_HOLD"], "random": ["DRAW"], "scan": ["SUBMIT_SCAN"],
        "profile": ["SUBMIT_PROFILE"], "photoCheck": ["SUBMIT_PHOTO_CHECK"], "note": ["SUBMIT_NOTE"],
        "typeIn": ["START_CHALLENGE", "SUBMIT_TYPE_IN"], "timeWindow": [], "musicCorner": [], "walk": [], "gameTimer": [], "stickerBook": [], "bingo": []
    ]
    public static func payload(kind: String, action: String, detail: [String: PlayWireValue]) throws -> [String: PlayWireValue] {
        guard actions[kind]?.contains(action) == true else { throw PlayExperienceError.unsupported }
        switch action {
        case "FLIP_COIN", "ROLL_DICE": return [:] // Never invent a random outcome client-side.
        case "START_CHALLENGE":
            if ["reaction", "ballShake", "quietHold", "typeIn", "countdown", "stopwatch", "shout"].contains(kind) { return ["game": .string(kind)] }
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
        guard let rows = value.array, rows.count <= 100, rows.allSatisfy({ ($0["rank"].integer ?? 0) > 0 && ($0["ownerId"].integer ?? 0) > 0 && $0["score"].integer != nil && ($0["elapsedSeconds"].integer ?? -1) >= 0 && ($0["completedUnits"].integer ?? -1) >= 0 && $0["displayName"].text?.isEmpty == false }) else { throw PlayExperienceError.malformed }
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
    public private(set) var leaderboardPhase = "idle"
    private var leaderboardGeneration: UInt64 = 0
    private var teamSurfaceRevision: UInt64 = 0
    private var teamSurfaceActive = false
    private let defaultTeamSurfaceID = UUID()
    private var teamSurfaceOwner: UUID?
    public var canTeamInteract: Bool {
        canInteract && (state?.deadlineAt.map { $0 > Int64(Date().timeIntervalSince1970 * 1000) } ?? true)
    }
    public var teamProjection: PlayAdvancedTeamProjection? {
        guard isCurrent, !["stale", "disabled"].contains(phase), let state, let owner else { return nil }
        return .init(state: state, actorID: owner.accountID)
    }
    public var leaderboardMetric: PlayAdvancedLeaderboardMetric? {
        guard isCurrent, !["stale", "disabled"].contains(phase), let state, state.config["leaderboard"]["enabled"].bool == true else { return nil }
        return state.config["leaderboard"]["metric"].text.flatMap(PlayAdvancedLeaderboardMetric.init(rawValue:))
    }
    public func beginTeamSurface(id: UUID? = nil) {
        let identity = id ?? defaultTeamSurfaceID
        guard teamSurfaceOwner != identity else { return }
        teamSurfaceOwner = identity; teamSurfaceActive = true; teamSurfaceRevision &+= 1
        clearAdvancedLeaderboard()
    }
    public func endTeamSurface(id: UUID? = nil) {
        guard teamSurfaceOwner == (id ?? defaultTeamSurfaceID) else { return }
        teamSurfaceOwner = nil; teamSurfaceActive = false; teamSurfaceRevision &+= 1
        clearAdvancedLeaderboard()
    }
    private func clearAdvancedLeaderboard() {
        leaderboardGeneration &+= 1; leaderboard = []; leaderboardPhase = "idle"
    }
    public func loadAdvancedLeaderboard(surfaceID: UUID? = nil) async {
        guard teamSurfaceOwner == (surfaceID ?? defaultTeamSurfaceID), teamSurfaceActive, isCurrent, let session = owner, let state, let metric = leaderboardMetric,
              leaderboardPhase != "loading" else { return }
        leaderboardGeneration &+= 1; let request = leaderboardGeneration
        let surface = teamSurfaceRevision; let runtimeGeneration = generation; leaderboardPhase = "loading"; leaderboard = []
        do {
            let rows = try await service.advancedLeaderboard(activityID: activityID, topicID: topicID, nodeID: nodeID, token: session.token)
            guard request == leaderboardGeneration else { return }
            guard teamSurfaceActive, surface == teamSurfaceRevision, currentSession() == session,
                  self.state?.sessionID == state.sessionID, self.state?.version == state.version,
                  leaderboardMetric == metric else { leaderboardPhase = "idle"; return }
            leaderboard = rows; leaderboardPhase = "ready"
        } catch {
            guard request == leaderboardGeneration else { return }
            guard teamSurfaceActive, surface == teamSurfaceRevision, currentSession() == session else { leaderboardPhase = "idle"; return }
            if case PlayExperienceError.unauthorized = error {
                failure(error, session: session, generation: runtimeGeneration)
            } else if case APIError.unauthorized = error {
                failure(error, session: session, generation: runtimeGeneration)
            } else { leaderboard = []; leaderboardPhase = "failed" }
        }
    }
    public func reviewTeamAction(_ action: PlayAdvancedTeamReview.Action, surfaceID: UUID? = nil) throws -> PlayAdvancedTeamReview {
        guard let surfaceOwner = teamSurfaceOwner, surfaceOwner == (surfaceID ?? defaultTeamSurfaceID), teamSurfaceActive, canTeamInteract, let state, let owner, let team = teamProjection else { throw PlayExperienceError.staleSession }
        switch action {
        case .assign(let memberID, let roleID):
            guard team.canAssign(memberID: memberID, roleID: roleID) else { throw PlayExperienceError.invalidAction }
            return .init(action: action, sessionID: state.sessionID, nodeID: state.nodeID, version: state.version,
                         memberName: team.members.first { $0.id == memberID }?.name, roleLabel: team.roleLabel(roleID), owner: owner, surfaceRevision: teamSurfaceRevision, surfaceID: surfaceOwner)
        case .completeUnit:
            guard team.canRequestUnit else { throw PlayExperienceError.invalidAction }
            return .init(action: action, sessionID: state.sessionID, nodeID: state.nodeID, version: state.version,
                         memberName: nil, roleLabel: team.myRole.map(team.roleLabel), owner: owner, surfaceRevision: teamSurfaceRevision, surfaceID: surfaceOwner)
        }
    }
    public func submitTeamReview(_ review: PlayAdvancedTeamReview) async {
        guard teamSurfaceActive, review.surfaceRevision == teamSurfaceRevision,
              review.surfaceID == teamSurfaceOwner, review.owner == currentSession() else { return }
        guard state?.sessionID == review.sessionID, state?.nodeID == review.nodeID, state?.version == review.version,
              (try? reviewTeamAction(review.action, surfaceID: review.surfaceID)) != nil else { issue = .staleSession; return }
        switch review.action {
        case .assign(let memberID, let roleID): await assignRole(memberID: memberID, roleID: roleID)
        case .completeUnit: await completeUnit()
        }
    }
    private var cardReceipts = PlayObjectCardReceiptCache()
    private var cardLifetime: UInt64 = 0
    private var pendingRequestedCard = false
    public var objectCardReceipt: PlayObjectCardReceipt? { isCurrent ? cardReceipts.receipt : nil }
    public func clearObjectCardReceipt() { cardLifetime &+= 1; cardReceipts.clear() }
    let activityID: Int; let topicID: Int; let nodeID: Int
    let service: PlayExperienceService
    let currentSession: () -> PlayExperienceSession?
    private var owner: PlayExperienceSession?
    private var generation: UInt64 = 0
    public private(set) var startOutcomeUnknown = false
    public init(activityID: Int, topicID: Int, nodeID: Int, service: PlayExperienceService, currentSession: @escaping () -> PlayExperienceSession?) {
        self.activityID = activityID; self.topicID = topicID; self.nodeID = nodeID; self.service = service; self.currentSession = { service.hasCurrentReadLifetime ? currentSession() : nil }
    }
    public var readLifetimeID: String? { service.readLifetimeID }
    public var hasCurrentReadLifetime: Bool { service.hasCurrentReadLifetime }
    public var blocksReadRebinding: Bool { startOutcomeUnknown || pending != nil || ["loading", "submitting", "unknown", "retryable"].contains(phase) }
    public func start() async {
        guard !startOutcomeUnknown, state == nil, ["idle", "rejected", "disabled"].contains(phase), let session = currentSession() else { return }
        generation &+= 1; let generation = generation; owner = session; phase = "loading"
        startOutcomeUnknown = true
        do {
            try accept(await service.startAdvanced(activityID: activityID, topicID: topicID, nodeID: nodeID, token: session.token), session: session, generation: generation)
            startOutcomeUnknown = false
        } catch {
            // Only a definite non-dispatch/rejection clears the start lock. A
            // retired lease, lost response or stale401 is not an idempotency proof.
            if case PlayExperienceError.disabled = error { startOutcomeUnknown = false }
            if case PlayExperienceError.rejected = error { startOutcomeUnknown = false }
            failure(error, session: session, generation: generation)
        }
    }
    public var isCurrent: Bool { owner != nil && owner == currentSession() }
    public var canInteract: Bool { isCurrent && phase == "ready" && pending == nil && state?.status == "RUNNING" }
    public func review(kind: String, action: String, detail: [String: PlayWireValue] = [:]) throws -> PlayKitActionReview {
        guard canInteract, let state, let owner else { throw PlayExperienceError.staleSession }
        guard state.playKit[kind].object != nil || state.config[kind]["enabled"].bool == true else { throw PlayExperienceError.unsupported }
        let payload = try PlayKitActionCatalog.payload(kind: kind, action: action, detail: detail)
        // Existing mechanical branch/random projections live outside playKit.
        let segment: PlayWireValue
        if state.playKit[kind].object != nil { segment = state.playKit[kind] }
        else if kind == "branch" { segment = state.branch }
        else if kind == "random" { segment = .object(["drawn": .array(state.draws), "drawCount": state.config["random"]["drawCount"]]) }
        else { segment = state.config[kind] }
        try PlayKitInputContract.validate(kind: kind, action: action, payload: payload, segment: segment)
        return PlayKitActionReview(state: state, owner: owner, kind: kind, action: action, payload: payload)
    }
    @discardableResult public func submit(_ review: PlayKitActionReview) async -> Bool {
        guard canInteract, let state, owner == review.owner, currentSession() == review.owner,
              state.sessionID == review.sessionID, state.version == review.version else {
            issue = .staleSession; return false
        }
        pendingRequestedCard = review.kind == "photoCheck" && state.playKit["photoCheck"]["mode"].text == "CARD"
        pending = PlayAdvancedPending(sessionID: review.sessionID, version: review.version,
            key: review.id.uuidString, action: review.action, payload: review.payload)
        await sendPending()
        return pending == nil && phase == "ready" && self.state?.sessionID == review.sessionID && (self.state?.version ?? -1) > review.version
    }
    public func submit(kind: String, action: String, detail: [String: PlayWireValue] = [:]) async {
        do { _ = await submit(try review(kind: kind, action: action, detail: detail)) }
        catch { issue = error as? PlayExperienceError ?? .invalidAction }
    }
    public func assignRole(memberID: Int, roleID: String) async {
        guard canTeamInteract, let state, let team = teamProjection, team.canAssign(memberID: memberID, roleID: roleID), owner == currentSession(),
              state.multiplayer["members"].array?.contains(where: { $0["memberId"].integer == memberID }) == true,
              state.config["multiplayer"]["roles"].array?.contains(where: { $0["id"].text == roleID }) == true else { return }
        pending = .init(sessionID: state.sessionID, version: state.version, key: UUID().uuidString, action: "ASSIGN_ROLE", payload: ["memberId": .int(memberID), "roleId": .string(roleID)])
        await sendPending()
    }
    public func completeUnit() async {
        guard canTeamInteract, let state, teamProjection?.canRequestUnit == true, owner == currentSession() else { return }
        // Source builds one unit per session/version. This is a local idempotency identity, not outcome proof.
        let unitID = "unit-\(state.sessionID)-v\(state.version)"
        pending = .init(sessionID: state.sessionID, version: state.version, key: UUID().uuidString, action: "COMPLETE_UNIT", payload: ["unitId": .string(unitID)])
        await sendPending()
    }
    private func sendPending() async {
        guard let pending, let session = owner, session == currentSession() else { return }
        let generation = generation; let cardLifetime = cardLifetime; phase = "submitting"
        do {
            let result = try await service.advancedAction(pending, token: session.token)
            try accept(result, session: session, generation: generation)
            if self.cardLifetime == cardLifetime { cardReceipts.accept(result, owner: session, pending: pending, requestedCard: pendingRequestedCard) }
            self.pending = nil; pendingRequestedCard = false
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
            cardReceipts.reconcile(result, owner: session)
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
        try validate(state, session: session, generation: generation)
        if self.state?.version != state.version { clearAdvancedLeaderboard() }
        self.state = state; issue = nil
        cardReceipts.reconcile(state, owner: session)
        // An unresolved steps proof must not disable unrelated server-present kits.
        // Step submission itself is separately unsupported until its proof contract is approved.
        phase = "ready"
    }
    private func failure(_ error: Error, session: PlayExperienceSession, generation: UInt64) {
        guard self.generation == generation else { return }
        guard currentSession() == session else { clearAdvancedLeaderboard(); self.state = nil; clearObjectCardReceipt(); phase = "stale"; return }
        issue = error as? PlayExperienceError ?? .unknownResult
        if case PlayExperienceError.rejected = error { pending = nil; clearObjectCardReceipt(); phase = "rejected"; clearAdvancedLeaderboard() }
        else if case PlayExperienceError.disabled = error { clearAdvancedLeaderboard(); pending = nil; clearObjectCardReceipt(); phase = "disabled" }
        else if case PlayExperienceError.unauthorized = error { clearAdvancedLeaderboard(); clearObjectCardReceipt(); phase = "stale" }
        else if case APIError.unauthorized = error { clearAdvancedLeaderboard(); clearObjectCardReceipt(); phase = "stale" }
        else { phase = "unknown" }
    }
}
