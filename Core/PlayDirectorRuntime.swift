import Foundation
import Observation

public struct PlayDirectorProjection: Equatable {
    public let activityID: Int; public let sessionID: Int?; public let revision: Int; public let status: String
    public let availableActions: Set<String>; public let club: PlayWireValue; public let currentChapterID: Int?
    public init(_ raw: PlayWireValue, activityID: Int) throws {
        guard activityID > 0, raw["activityId"].integer == activityID, raw["perspective"].text == "CLUB",
              let revision = raw["revision"].integer, revision >= 0, let status = raw["status"].text else { throw PlayExperienceError.malformed }
        availableActions = Set(raw["availableActions"].array?.compactMap(\.text) ?? []).intersection(PlayDirectorAction.allCases.map(\.rawValue))
        let notPrepared = status == "NOT_PREPARED" && revision == 0 && availableActions.contains("PREPARE") && raw["sessionId"] == .null
        guard notPrepared || ((raw["sessionId"].integer ?? 0) > 0 && raw["club"].object != nil) else { throw PlayExperienceError.malformed }
        self.activityID = activityID; sessionID = raw["sessionId"].integer; self.revision = revision; self.status = status
        club = raw["club"]; currentChapterID = raw["currentChapterId"].integer
    }
    public var stations: [PlayWireValue] { club["stations"].array ?? [] }
    public var teams: [PlayWireValue] { club["teams"].array ?? [] }
    public var roles: [PlayWireValue] { club["roles"].array ?? [] }
    public var roleOptions: [PlayWireValue] { club["roleOptions"].array ?? [] }
    public var submissions: [PlayWireValue] { club["submissions"].array ?? [] }
    public var chapterOptions: [PlayWireValue] { (club["chapterOptions"].array ?? []).filter { ($0["chapterId"].integer ?? 0) > 0 && $0["chapterId"].integer != currentChapterID && $0["unlocked"].bool != true && $0["unlockable"].bool != false } }
    public var leaderboardVisible: Bool? { club["leaderboardVisible"].bool ?? club["leaderboard"]["visible"].bool }
    public var canStart: Bool {
        let required = club["readiness"]["requiredStations"].integer
        return status == "READY" && (required ?? 0) > 0 && club["readiness"]["readyStations"].integer == required && club["readiness"]["teamsReady"].bool == true && availableActions.contains("START")
    }
    public func allows(_ command: PlayDirectorCommand) -> Bool {
        guard command.activityID == activityID, command.expectedRevision == revision, availableActions.contains(command.action.rawValue) else { return false }
        let p = command.payload
        switch command.action {
        case .start: return canStart
        case .prepare: return status == "NOT_PREPARED" || status == "DRAFT"
        case .finish: return sessionID != nil
        case .visibility: return leaderboardVisible != nil
        case .unlock: return chapterOptions.contains { $0["chapterId"].integer == p["chapterId"]?.integer }
        case .pause, .resume:
            guard let station = stations.first(where: { $0["nodeId"].integer == command.nodeID }) else { return false }
            if command.action == .resume { return station["status"].text == "PAUSED" }
            if let plan = p["fallbackPlanCode"]?.text {
                guard station["fallbackPlanOptions"].array?.contains(where: { $0["planCode"].text == plan && $0["version"].integer == p["fallbackPlanVersion"]?.integer }) == true else { return false }
            }
            return station["status"].text != "PAUSED" && station["status"].text != "CLOSED"
        case .reject: return submissions.contains { $0["submissionId"].integer == p["submissionId"]?.integer && $0["status"].text == "PENDING" }
        case .broadcast:
            if p["targetType"]?.text == "TEAM" { return teams.contains { $0["teamId"].integer == p["targetId"]?.integer } }
            if p["targetType"]?.text == "ROLE" { return roleOptions.contains { Self.roleCode($0) == p["roleCode"]?.text } }
            return p["targetType"]?.text == "ALL"
        case .assign:
            guard teams.contains(where: { $0["teamId"].integer == p["teamId"]?.integer }), let assignments = p["assignments"]?.array else { return false }
            return assignments.allSatisfy { assignment in
                roles.contains { $0["teamId"].integer == p["teamId"]?.integer && $0["memberId"].integer == assignment["memberId"].integer } &&
                roleOptions.contains { Self.roleCode($0) == assignment["roleCode"].text }
            }
        case .takeover:
            let team = p["teamId"]?.integer, source = p["sourceMemberId"]?.integer, target = p["targetMemberId"]?.integer
            return roles.contains { $0["teamId"].integer == team && $0["memberId"].integer == source && ($0["confirmationStatus"].text ?? $0["status"].text) == "CONFIRMED" && Self.roleCode($0)?.isEmpty == false } &&
                roles.contains { $0["teamId"].integer == team && $0["memberId"].integer == target && (Self.roleCode($0) ?? "").isEmpty }
        }
    }
    public static func roleCode(_ raw: PlayWireValue) -> String? { raw["roleCode"].text ?? raw["code"].text ?? raw["key"].text }
}
public enum PlayDirectorAction: String, CaseIterable, Identifiable {
    case prepare = "PREPARE", start = "START", finish = "FINISH", assign = "ASSIGN_ROLES", takeover = "TAKEOVER_ROLE"
    case broadcast = "BROADCAST", unlock = "UNLOCK_CHAPTER", visibility = "SET_LEADERBOARD_VISIBILITY"
    case pause = "CLUB_STATION_PAUSE", resume = "CLUB_STATION_RESUME", reject = "CLUB_REJECT_SUBMISSION"
    public var id: String { rawValue }
}
public struct PlayDirectorCommand: Equatable {
    public let activityID: Int; public let nodeID: Int?; public let expectedRevision: Int; public let requestID: String
    public let action: PlayDirectorAction; public let payload: [String: PlayWireValue]
    public init(activityID: Int, nodeID: Int?, expectedRevision: Int, requestID: String = UUID().uuidString, action: PlayDirectorAction, payload: [String: PlayWireValue]) throws {
        guard activityID > 0, expectedRevision >= 0, requestID.range(of: "^[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil,
              ([PlayDirectorAction.pause, .resume].contains(action)) == (nodeID != nil), nodeID.map({ $0 > 0 }) ?? true else { throw PlayExperienceError.invalidAction }
        func text(_ key: String, _ max: Int) -> Bool { guard let value = payload[key]?.text else { return false }; return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= max }
        func positive(_ key: String) -> Bool { (payload[key]?.integer ?? 0) > 0 }
        let keys = Set(payload.keys)
        let valid: Bool
        switch action {
        case .prepare, .start, .finish, .resume: valid = payload.isEmpty
        case .assign:
            valid = keys == ["teamId", "assignments"] && positive("teamId") && payload["assignments"]?.array?.isEmpty == false && payload["assignments"]?.array?.allSatisfy {
                ($0["memberId"].integer ?? 0) > 0 && $0["roleCode"].text?.isEmpty == false && ($0["roleCode"].text?.count ?? 65) <= 64 && Set($0.object?.keys.map { $0 } ?? []) == ["memberId", "roleCode"]
            } == true
        case .takeover: valid = keys == ["teamId", "sourceMemberId", "targetMemberId", "reason"] && positive("teamId") && positive("sourceMemberId") && positive("targetMemberId") && payload["sourceMemberId"] != payload["targetMemberId"] && text("reason", 200)
        case .broadcast:
            let target = payload["targetType"]?.text
            valid = ["ALL", "TEAM", "ROLE"].contains(target ?? "") && text("content", 200) &&
                (target == "ALL" ? keys == ["targetType", "content"] : target == "TEAM" ? keys == ["targetType", "targetId", "content"] && positive("targetId") : keys == ["targetType", "roleCode", "content"] && text("roleCode", 64))
        case .unlock: valid = keys == ["chapterId", "reason"] && positive("chapterId") && text("reason", 200)
        case .visibility: valid = keys == ["visible"] && payload["visible"]?.bool != nil
        case .pause:
            let base: Set<String> = ["reasonCode", "reason", "resumeEta"]
            valid = (keys == base || keys == base.union(["fallbackPlanCode", "fallbackPlanVersion"])) && text("reasonCode", 64) && text("reason", 200) && (payload["reason"]?.text?.count ?? 0) >= 2 && text("resumeEta", 64) && (payload["fallbackPlanCode"] == nil || (text("fallbackPlanCode", 64) && positive("fallbackPlanVersion")))
        case .reject: valid = keys == ["submissionId", "reasonCode", "reason"] && positive("submissionId") && text("reasonCode", 64) && text("reason", 200) && (payload["reason"]?.text?.count ?? 0) >= 2
        }
        guard valid else { throw PlayExperienceError.invalidAction }
        self.activityID = activityID; self.nodeID = nodeID; self.expectedRevision = expectedRevision; self.requestID = requestID; self.action = action; self.payload = payload
    }
    var json: [String: PlayWireValue] { ["activityId": .int(activityID), "nodeId": nodeID.map(PlayWireValue.int) ?? .null, "expectedRevision": .int(expectedRevision), "requestId": .string(requestID), "action": .string(action.rawValue), "payload": .object(payload)] }
}
public struct PlayDirectorReceipt: Equatable {
    public let outcome: String; public let revision: Int; public let result: PlayWireValue
    public init(_ raw: PlayWireValue, command: PlayDirectorCommand) throws {
        guard raw["activityId"].integer == command.activityID, raw["requestId"].text == command.requestID, raw["action"].text == command.action.rawValue,
              let outcome = raw["outcome"].text, ["PENDING", "APPLIED", "FAILED"].contains(outcome), let revision = raw["revision"].integer, revision >= 0,
              (raw["receiptId"] == .null || (raw["receiptId"].integer ?? 0) > 0), outcome == "PENDING" || (raw["receiptId"].integer ?? 0) > 0 else { throw PlayExperienceError.malformed }
        self.outcome = outcome; self.revision = revision; result = raw["result"]
    }
}
extension PlayExperienceService {
    public func directorProjection(activityID: Int, token: String) async throws -> PlayDirectorProjection {
        try PlayDirectorProjection(await request("api/game/session/view", query: ["activityId": String(activityID), "perspective": "CLUB"], capability: .reads, token: token), activityID: activityID)
    }
    public func directorCommand(_ command: PlayDirectorCommand, token: String) async throws -> PlayDirectorReceipt {
        try PlayDirectorReceipt(await request("api/game/session/command", json: command.json, capability: .directorCommands, token: token), command: command)
    }
    public func directorReceipt(_ command: PlayDirectorCommand, token: String) async throws -> PlayDirectorReceipt {
        try PlayDirectorReceipt(await request("api/game/session/receipt", query: ["activityId": String(command.activityID), "requestId": command.requestID], capability: .reads, token: token), command: command)
    }
}
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayDirectorCoordinator {
    public let activityID: Int
    public private(set) var projection: PlayDirectorProjection?
    public private(set) var pending: PlayDirectorCommand?
    public private(set) var receipt: PlayDirectorReceipt?
    public private(set) var phase = "idle"
    public private(set) var issue: PlayExperienceError?
    let service: PlayExperienceService
    let currentSession: () -> PlayExperienceSession?
    private var owner: PlayExperienceSession?
    private var generation: UInt64 = 0
    public init(activityID: Int, service: PlayExperienceService, currentSession: @escaping () -> PlayExperienceSession?) { self.activityID = activityID; self.service = service; self.currentSession = currentSession }
    public func load() async {
        guard phase != "submitting", let session = currentSession() else { return }
        if let owner, owner != session { projection = nil; receipt = nil; phase = "stale"; return }
        owner = session; generation &+= 1; let generation = generation; phase = "loading"; issue = nil
        do { let value = try await service.directorProjection(activityID: activityID, token: session.token); try check(session, generation); projection = value; phase = pending == nil ? "ready" : "unknown" }
        catch { fail(error, session, generation) }
    }
    public func submit(_ command: PlayDirectorCommand) async {
        guard phase == "ready", pending == nil, projection?.allows(command) == true, owner == currentSession() else { return }
        pending = command; await sendExact()
    }
    private func sendExact() async {
        guard let pending, let session = owner, session == currentSession() else { return }
        let generation = generation; phase = "submitting"
        do { let receipt = try await service.directorCommand(pending, token: session.token); try await accept(receipt, session, generation) }
        catch { fail(error, session, generation) }
    }
    public func recover() async {
        guard phase == "unknown", let pending, let session = owner, session == currentSession() else { return }
        let generation = generation; phase = "loading"; issue = nil
        do { let receipt = try await service.directorReceipt(pending, token: session.token); try await accept(receipt, session, generation) }
        catch { fail(error, session, generation) }
    }
    public func retryExact() async { guard phase == "unknown", pending != nil else { return }; await sendExact() }
    public func exportRecap() async -> String? {
        guard phase == "ready", projection?.club["recap"]["exportAvailable"].bool == true,
              let session = owner, session == currentSession() else { return nil }
        let generation = generation
        do {
            let value = try await service.directorRecapExport(activityID: activityID, token: session.token); try check(session, generation)
            guard value["sessionId"].integer == projection?.sessionID else { throw PlayExperienceError.malformed }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(data: try encoder.encode(value), encoding: .utf8)
        } catch { fail(error, session, generation); return nil }
    }

    private func accept(_ receipt: PlayDirectorReceipt, _ session: PlayExperienceSession, _ generation: UInt64) async throws {
        try check(session, generation); self.receipt = receipt
        if receipt.outcome == "PENDING" { phase = "unknown"; return }
        if receipt.outcome == "FAILED" { pending = nil; phase = "rejected"; return }
        let value = try await service.directorProjection(activityID: activityID, token: session.token); try check(session, generation)
        guard value.revision >= receipt.revision, projection?.sessionID == nil || value.sessionID == projection?.sessionID else { throw PlayExperienceError.malformed }
        projection = value; pending = nil; phase = "ready"
    }
    private func check(_ session: PlayExperienceSession, _ generation: UInt64) throws { guard self.generation == generation, currentSession() == session, !Task.isCancelled else { throw PlayExperienceError.staleSession } }
    private func fail(_ error: Error, _ session: PlayExperienceSession, _ generation: UInt64) {
        guard self.generation == generation else { return }
        guard currentSession() == session else { projection = nil; receipt = nil; phase = "stale"; return }
        issue = error as? PlayExperienceError ?? .unknownResult
        if case PlayExperienceError.rejected = error { pending = nil; phase = "rejected" }
        else if case PlayExperienceError.disabled = error { pending = nil; phase = "disabled" }
        else { phase = pending == nil ? "failed" : "unknown" }
    }
}
