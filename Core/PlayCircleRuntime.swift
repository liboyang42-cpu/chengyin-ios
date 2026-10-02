import Foundation
import Observation

public struct PlayCircleCard: Equatable {
    public let sessionID: String
    public let themeCode: String
    public let status: String?
    public let records: [PlayWireValue]
    public let answers: [PlayWireValue]
    public let memoryLines: [String]
    public let raw: PlayWireValue
    public init(_ raw: PlayWireValue, expectedSessionID: String) throws {
        guard raw.object != nil, Self.validID(expectedSessionID) else { throw PlayExperienceError.malformed }
        if let id = Self.identifier(raw["id"]) ?? Self.identifier(raw["sessionId"]), id != expectedSessionID { throw PlayExperienceError.malformed }
        sessionID = expectedSessionID; themeCode = raw["themeCode"].text?.uppercased() ?? ""
        status = raw["status"].text; records = raw["records"].array ?? []; answers = raw["answers"].array ?? []
        memoryLines = raw["memoryLines"].array?.compactMap(\.text) ?? []; self.raw = raw
    }
    public static func identifier(_ value: PlayWireValue) -> String? { value.text ?? value.integer.map(String.init) }
    static func validID(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9_-]{1,96}$", options: .regularExpression) != nil }
    public var stages: [String] {
        let all: [String]
        switch themeCode {
        case "FITNESS": all = ["PRE_CHOICE", "POST_CHOICE"]
        case "MIDLIFE": all = ["SELF_MOMENT"]
        case "DATE": all = ["QUESTION_CARD"]
        case "FRIENDS": all = ["PRE_WISH", "NEXT_PICK"]
        case "SHANGHAI": all = ["CITY_KEYWORDS"]
        default: all = []
        }
        let count = raw["recordedMerchantCount"].tolerantInteger ?? records.count
        return all.filter { stage in
            if ["PRE_CHOICE", "PRE_WISH"].contains(stage) { return count == 0 }
            if ["POST_CHOICE", "NEXT_PICK"].contains(stage) { return count >= 2 }
            return true
        }
    }
    public func confirms(_ intent: PlayCircleIntent) -> Bool {
        switch intent {
        case .record(let offerID, _): return records.contains { Self.identifier($0["offerId"]) == offerID }
        case .answer(let stage, let value): return answers.contains {
            ($0["answerStage"].text ?? $0["stage"].text) == stage &&
            ($0["answerValue"].text ?? $0["value"].text)?.trimmingCharacters(in: .whitespacesAndNewlines) == value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    }
}
public enum PlayCircleIntent: Equatable { case record(offerID: String, note: String), answer(stage: String, value: String) }
extension PlayExperienceService {
    public func circleOffers(topicID: Int, token: String) async throws -> [PlayWireValue] {
        guard topicID > 0 else { throw APIError.invalidRequest }
        let raw = try await request("api/circle-theme/instance/\(topicID)/offers", capability: .reads, token: token)
        guard let rows = raw.array, rows.allSatisfy({ $0.object != nil }) else { throw PlayExperienceError.malformed }; return rows
    }
    public func circleOpen(topicID: Int, inviteCode: String?, token: String) async throws -> String {
        guard topicID > 0 else { throw APIError.invalidRequest }
        let raw: PlayWireValue
        if let inviteCode, !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            raw = try await request("api/circle-theme/session/join", json: ["inviteCode": .string(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())], capability: .circle, token: token)
        } else { raw = try await request("api/circle-theme/session", json: ["topicId": .int(topicID)], capability: .circle, token: token) }
        guard let id = PlayCircleCard.identifier(raw["id"]) ?? PlayCircleCard.identifier(raw["sessionId"]), PlayCircleCard.validID(id) else { throw PlayExperienceError.malformed }; return id
    }
    public func circleCard(sessionID: String, token: String) async throws -> PlayCircleCard {
        guard PlayCircleCard.validID(sessionID) else { throw APIError.invalidRequest }
        return try PlayCircleCard(await request("api/circle-theme/session/\(sessionID)/card", capability: .reads, token: token), expectedSessionID: sessionID)
    }
    public func circleWrite(sessionID: String, intent: PlayCircleIntent, token: String) async throws {
        guard PlayCircleCard.validID(sessionID) else { throw APIError.invalidRequest }
        var json: [String: PlayWireValue] = ["sessionId": .string(sessionID)]
        let path: String
        switch intent {
        case .record(let offerID, let note):
            guard PlayCircleCard.validID(offerID) else { throw APIError.invalidRequest }
            json["offerId"] = Int(offerID).map(PlayWireValue.int) ?? .string(offerID); json["note"] = .string(note.trimmingCharacters(in: .whitespacesAndNewlines)); path = "record"
        case .answer(let stage, let value):
            guard !stage.isEmpty, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidRequest }
            json["stage"] = .string(stage); json["value"] = .string(value.trimmingCharacters(in: .whitespacesAndNewlines)); path = "answer"
        }
        _ = try await request("api/circle-theme/session/" + path, json: json, capability: .circle, token: token)
    }
}
/// Circle has no per-write receipt endpoint or idempotency key. Readback proves only
/// record/answer presence, never physical arrival/redemption/purchase; never blind retry.
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayCircleCoordinator {
    public let topicID: Int
    public private(set) var offers: [PlayWireValue] = []
    public private(set) var card: PlayCircleCard?
    public private(set) var pending: PlayCircleIntent?
    public private(set) var phase = "idle"
    public private(set) var issue: PlayExperienceError?
    let service: PlayExperienceService
    let currentSession: () -> PlayExperienceSession?
    private var owner: PlayExperienceSession?
    private var generation: UInt64 = 0
    private var openingUnresolved = false
    private var openedSessionID: String?
    public init(topicID: Int, service: PlayExperienceService, currentSession: @escaping () -> PlayExperienceSession?) { self.topicID = topicID; self.service = service; self.currentSession = currentSession }
    public func loadOffers() async {
        guard phase != "submitting", let session = currentSession() else { return }
        if owner != nil && owner != session { card = nil; offers = []; phase = "stale"; return }
        owner = session; generation &+= 1; let generation = generation; phase = "loading"; issue = nil
        do { let rows = try await service.circleOffers(topicID: topicID, token: session.token); try check(session, generation); offers = rows
            if let openedSessionID {
                let recovered = try await service.circleCard(sessionID: openedSessionID, token: session.token); try check(session, generation)
                card = recovered; openingUnresolved = false
            }
            phase = openingUnresolved ? "unknownOpen" : pending == nil ? "ready" : "unknown" }
        catch { fail(error, session, generation) }
    }
    public func open(inviteCode: String? = nil) async {
        guard phase == "ready", !openingUnresolved, openedSessionID == nil, card == nil, pending == nil, offers.count >= 3, let session = owner, session == currentSession() else { return }
        let generation = generation; phase = "submitting"; openingUnresolved = true
        do {
            let id = try await service.circleOpen(topicID: topicID, inviteCode: inviteCode, token: session.token)
            try check(session, generation); openedSessionID = id
            let card = try await service.circleCard(sessionID: id, token: session.token); try check(session, generation)
            self.card = card; openingUnresolved = false; phase = "ready"
        } catch {
            if case PlayExperienceError.rejected = error { openingUnresolved = false }
            if case PlayExperienceError.disabled = error { openingUnresolved = false }
            fail(error, session, generation)
            if currentSession() == session, openingUnresolved { phase = "unknownOpen" }
        }
    }
    public func submit(_ intent: PlayCircleIntent) async {
        guard phase == "ready", pending == nil, let card, card.raw["completed"].bool != true, offers.count >= 3, let session = owner, session == currentSession() else { return }
        switch intent {
        case .record(let offerID, _): guard offers.contains(where: { (PlayCircleCard.identifier($0["id"]) ?? PlayCircleCard.identifier($0["offerId"])) == offerID }) else { return }
        case .answer(let stage, _): guard card.stages.contains(stage) else { return }
        }
        let generation = generation; pending = intent; phase = "submitting"
        do { try await service.circleWrite(sessionID: card.sessionID, intent: intent, token: session.token); try check(session, generation); phase = "unknown"; await recover() }
        catch {
            if case PlayExperienceError.rejected = error { pending = nil }
            if case PlayExperienceError.disabled = error { pending = nil }
            fail(error, session, generation)
        }
    }
    public func recover() async {
        guard let card, let session = owner, session == currentSession(), phase == "unknown" else { return }
        let generation = generation; phase = "loading"; issue = nil
        do {
            let value = try await service.circleCard(sessionID: card.sessionID, token: session.token); try check(session, generation)
            self.card = value; if let pending, value.confirms(pending) { self.pending = nil }
            phase = pending == nil ? "ready" : "unknown"
        } catch { fail(error, session, generation) }
    }
    private func check(_ session: PlayExperienceSession, _ generation: UInt64) throws {
        guard self.generation == generation, currentSession() == session, !Task.isCancelled else { throw PlayExperienceError.staleSession }
    }
    private func fail(_ error: Error, _ session: PlayExperienceSession, _ generation: UInt64) {
        guard self.generation == generation else { return }
        guard currentSession() == session else { card = nil; offers = []; phase = "stale"; return }
        issue = error as? PlayExperienceError ?? .unknownResult; phase = pending == nil ? "failed" : "unknown"
    }
}
