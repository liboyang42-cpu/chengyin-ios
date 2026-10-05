import Foundation
import Observation

public struct PlayPlayerGameProjection: Equatable {
    public struct Node: Equatable, Identifiable {
        public let id: Int; public let name: String?; public let state: String?; public let stationState: String?
        public let clue: String?; public let task: PlayWireValue; public let hint: PlayWireValue
        public let choices: [PlayWireValue]; public let pause: PlayWireValue; public let fallback: PlayWireValue
        public let completionStatus: String?; public let completionSource: String?
    }
    public let sessionID: Int; public let activityID: Int; public let revision: Int; public let teamID: Int
    public let status: String; public let role: PlayWireValue; public let availableActions: Set<String>
    public let nodes: [Node]; public let story: PlayWireValue; public let submissions: [PlayWireValue]
    public init(_ raw: PlayWireValue) throws {
        guard raw["perspective"].text == "PLAYER", let session = raw["sessionId"].integer, session > 0,
              let activity = raw["activityId"].integer, activity > 0, let revision = raw["revision"].integer, revision >= 0,
              let status = raw["status"].text, ["PREPARING", "READY", "RUNNING", "FINISHED", "CANCELLED"].contains(status),
              let team = raw["player"]["teamId"].integer, team > 0, raw["player"]["role"].object != nil,
              let nodes = raw["player"]["nodes"].array else { throw PlayExperienceError.malformed }
        sessionID = session; activityID = activity; self.revision = revision; teamID = team; self.status = status
        role = raw["player"]["role"]; story = raw["player"]["story"]; submissions = raw["player"]["mySubmissions"].array ?? []
        availableActions = Set((raw["availableActions"].array ?? []).compactMap(\.text)).intersection(PlayPlayerCommand.Action.allCases.map(\.rawValue))
        self.nodes = try nodes.map { row in
            guard let id = row["nodeId"].integer, id > 0 else { throw PlayExperienceError.malformed }
            return Node(id: id, name: row["nodeName"].text, state: row["personalState"].text,
                        stationState: (row["stationStatus"].text ?? row["status"].text), clue: row["clue"].text,
                        task: row["playerTask"], hint: row["hint"], choices: row["allowedChoices"].array ?? [],
                        pause: row["pause"], fallback: row["fallback"], completionStatus: row["completionStatus"].text, completionSource: row["completionSource"].text)
        }
        guard Set(self.nodes.map(\.id)).count == self.nodes.count else { throw PlayExperienceError.malformed }
    }
    public var roleConfirmed: Bool { role["confirmed"].bool == true || role["status"].text == "CONFIRMED" }
    public func allows(_ command: PlayPlayerCommand) -> Bool {
        guard command.activityID == activityID, command.expectedRevision == revision, availableActions.contains(command.action.rawValue) else { return false }
        if command.action == .confirmRole { return !roleConfirmed && role["code"].text?.isEmpty == false && status != "FINISHED" && status != "CANCELLED" }
        guard roleConfirmed, status == "RUNNING", let node = nodes.first(where: { $0.id == command.nodeID }),
              !["PAUSED", "COMPLETED", "FALLBACK_COMPLETED", "HIDDEN", "LOCKED"].contains(node.state ?? "HIDDEN"), node.stationState != "PAUSED" else { return false }
        switch command.action {
        case .choice: return node.choices.contains(where: { $0["id"].text == command.payload["choiceId"]?.text })
        case .submit:
            let prior = submissions.first { $0["nodeId"].integer == node.id }
            guard prior == nil || prior?["status"].text == "REJECTED" else { return false }
            return node.task["taskCode"].text == command.payload["taskCode"]?.text
        case .hint:
            return node.hint["nextLevel"].integer == command.payload["level"]?.integer && node.hint["nextImpactLabel"].text?.isEmpty == false
        case .reveal: return node.hint["revealAvailable"].bool == true && node.hint["revealImpactLabel"].text?.isEmpty == false
        case .confirmRole: return false
        }
    }
}
public struct PlayPlayerCommand: Equatable {
    public enum Action: String, CaseIterable { case confirmRole = "CONFIRM_ROLE", choice = "PLAYER_CHOICE", submit = "PLAYER_SUBMIT", hint = "PLAYER_HINT", reveal = "PLAYER_REVEAL" }
    public let activityID: Int; public let nodeID: Int?; public let requestID: String; public let expectedRevision: Int
    public let action: Action; public let payload: [String: PlayWireValue]
    public init(activityID: Int, nodeID: Int?, requestID: String = UUID().uuidString, expectedRevision: Int, action: Action, payload: [String: PlayWireValue]) throws {
        guard activityID > 0, expectedRevision >= 0, requestID.range(of: "^[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil,
              (action == .confirmRole) == (nodeID == nil), nodeID.map({ $0 > 0 }) ?? true else { throw PlayExperienceError.invalidAction }
        let keys = Set(payload.keys)
        switch action {
        case .confirmRole, .reveal: guard payload.isEmpty else { throw PlayExperienceError.invalidAction }
        case .choice:
            guard keys == ["choiceId"], let text = payload["choiceId"]?.text, !text.isEmpty, text.count <= 64 else { throw PlayExperienceError.invalidAction }
        case .hint: guard keys == ["level"], (1...2).contains(payload["level"]?.integer ?? 0) else { throw PlayExperienceError.invalidAction }
        case .submit:
            guard keys == ["taskCode", "evidenceUrls"], let code = payload["taskCode"]?.text, !code.isEmpty, code.count <= 64,
                  let values = payload["evidenceUrls"]?.array, (1...6).contains(values.count), values.allSatisfy({ Self.validEvidence($0.text) }) else { throw PlayExperienceError.invalidAction }
        }
        self.activityID = activityID; self.nodeID = nodeID; self.requestID = requestID; self.expectedRevision = expectedRevision; self.action = action; self.payload = payload
    }
    public static func textEvidence(_ text: String, scan: Bool = false) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= (scan ? 256 : 300) else { throw PlayExperienceError.invalidAction }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else { throw PlayExperienceError.invalidAction }
        return (scan ? "scan:" : "text:") + encoded
    }
    private static func validEvidence(_ value: String?) -> Bool {
        guard let value, !value.isEmpty, value.count <= 512, !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return false }
        if value.hasPrefix("text:") || value.hasPrefix("scan:") {
            let encoded = String(value.dropFirst(5)); guard let decoded = encoded.removingPercentEncoding else { return false }
            return (try? textEvidence(decoded, scan: value.hasPrefix("scan:"))) == value
        }
        // uploadOSS may return a signed or extensionless HTTPS URL; source accepts it.
        return PlayExperienceService.validHTTPS(value)
    }
    var json: [String: PlayWireValue] { ["activityId": .int(activityID), "nodeId": nodeID.map(PlayWireValue.int) ?? .null,
        "requestId": .string(requestID), "expectedRevision": .int(expectedRevision), "action": .string(action.rawValue), "payload": .object(payload)] }
}
public struct PlayGameReceipt: Equatable {
    public let activityID: Int; public let requestID: String; public let action: String; public let outcome: String
    public let receiptID: Int?; public let revision: Int; public let result: PlayWireValue
    public init(_ raw: PlayWireValue, command: PlayPlayerCommand) throws {
        guard raw["activityId"].integer == command.activityID, raw["requestId"].text == command.requestID,
              raw["action"].text == command.action.rawValue, let outcome = raw["outcome"].text, ["PENDING", "APPLIED", "FAILED"].contains(outcome),
              let revision = raw["revision"].integer, revision >= 0 else { throw PlayExperienceError.malformed }
        let receiptID = raw["receiptId"].integer
        guard (raw["receiptId"] == .null || (receiptID ?? 0) > 0), outcome == "PENDING" || (receiptID ?? 0) > 0 else { throw PlayExperienceError.malformed }
        activityID = command.activityID; requestID = command.requestID; action = command.action.rawValue; self.outcome = outcome
        self.receiptID = receiptID; self.revision = revision; result = raw["result"]
    }
}
extension PlayExperienceService {
    public func playerProjection(activityID: Int, token: String) async throws -> PlayPlayerGameProjection {
        guard activityID > 0 else { throw APIError.invalidRequest }
        let value = try PlayPlayerGameProjection(await request("api/game/session/view", query: ["activityId": String(activityID), "perspective": "PLAYER"], capability: .reads, token: token))
        guard value.activityID == activityID else { throw PlayExperienceError.malformed }; return value
    }
    public func playerCommand(_ command: PlayPlayerCommand, token: String) async throws -> PlayGameReceipt {
        try PlayGameReceipt(await request("api/game/session/command", json: command.json, capability: .playerCommands, token: token), command: command)
    }
    public func playerReceipt(_ command: PlayPlayerCommand, token: String) async throws -> PlayGameReceipt {
        try PlayGameReceipt(await request("api/game/session/receipt", query: ["activityId": String(command.activityID), "requestId": command.requestID], capability: .reads, token: token), command: command)
    }
}
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayPlayerGameCoordinator {
    public let activityID: Int
    public private(set) var projection: PlayPlayerGameProjection?
    public private(set) var pending: PlayPlayerCommand?
    public private(set) var receipt: PlayGameReceipt?
    public private(set) var phase = "idle"
    public private(set) var issue: PlayExperienceError?
    let service: PlayExperienceService
    let currentSession: () -> PlayExperienceSession?
    private var owner: PlayExperienceSession?
    private var generation: UInt64 = 0
    public init(activityID: Int, service: PlayExperienceService, currentSession: @escaping () -> PlayExperienceSession?) {
        self.activityID = activityID; self.service = service; self.currentSession = currentSession
    }
    public var hasCurrentProjection: Bool { owner != nil && owner == currentSession() }
    public func load() async {
        guard phase != "submitting", let session = currentSession() else { return }
        if owner != nil && owner != session { projection = nil; receipt = nil; phase = "stale"; return }
        owner = session; generation &+= 1; let generation = generation; phase = "loading"; issue = nil
        do {
            let value = try await service.playerProjection(activityID: activityID, token: session.token)
            try check(session, generation); projection = value; phase = pending == nil ? "ready" : "unknown"
        } catch { fail(error, session, generation) }
    }
    public func submit(_ command: PlayPlayerCommand) async {
        guard pending == nil, phase == "ready", projection?.allows(command) == true, owner == currentSession() else { return }
        pending = command; await sendExact()
    }
    private func sendExact() async {
        guard let pending, let session = owner, session == currentSession() else { return }
        let generation = generation; phase = "submitting"
        do { try await accept(service.playerCommand(pending, token: session.token), session, generation) }
        catch { fail(error, session, generation) }
    }
    private func accept(_ receipt: PlayGameReceipt, _ session: PlayExperienceSession, _ generation: UInt64) async throws {
        try check(session, generation); self.receipt = receipt
        if receipt.outcome == "PENDING" { phase = "unknown"; return }
        if receipt.outcome == "FAILED" { pending = nil; phase = "rejected"; return }
        // APPLIED receipt alone does not permit subsequent actions against stale revision.
        let value = try await service.playerProjection(activityID: activityID, token: session.token)
        try check(session, generation)
        guard value.revision >= receipt.revision, value.sessionID == projection?.sessionID else { throw PlayExperienceError.malformed }
        projection = value; pending = nil; phase = "ready"
    }
    public func recover() async {
        guard let pending, let session = owner, session == currentSession(), phase == "unknown" else { return }
        let generation = generation; phase = "loading"; issue = nil
        do { try await accept(service.playerReceipt(pending, token: session.token), session, generation) }
        catch { fail(error, session, generation) }
    }
    /// Explicit user retry, with frozen command/requestId. No new payload or ID.
    public func retryExact() async { guard phase == "unknown", pending != nil else { return }; await sendExact() }
    private func check(_ session: PlayExperienceSession, _ generation: UInt64) throws {
        guard self.generation == generation, currentSession() == session, !Task.isCancelled else { throw PlayExperienceError.staleSession }
    }
    private func fail(_ error: Error, _ session: PlayExperienceSession, _ generation: UInt64) {
        guard self.generation == generation else { return }
        guard currentSession() == session else { projection = nil; receipt = nil; phase = "stale"; return }
        issue = error as? PlayExperienceError ?? .unknownResult
        if case PlayExperienceError.rejected = error { pending = nil; phase = "rejected" }
        else if case PlayExperienceError.disabled = error { pending = nil; phase = "disabled" }
        else { phase = pending == nil ? "failed" : "unknown" }
    }
}
