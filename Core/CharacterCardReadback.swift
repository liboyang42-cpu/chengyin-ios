import Foundation
import Observation

/// Authoritative check breakdown from a signed receipt. Totals are never recomputed
/// from die + skill + mods, and success is never inferred from total vs DC.
/// Missing breakdowns stay `WAITING_SOURCE`; malformed payloads stay `UNKNOWN`.
public struct CharacterCheckBreakdown: Equatable {
    public struct Skill: Equatable {
        public let hidden: Bool
        public let statKey: String?
        public let label: String?
        public let value: Int?
    }
    public struct Situational: Equatable {
        public let raw: Int?
        public let applied: Int?
        public let cap: Int?
    }
    public let availability: WorldFactAvailability
    public let die: Int?
    public let skill: Skill?
    public let situational: Situational?
    public let bargain: Int?
    public let momentum: Int?
    public let total: Int?
    public let dc: Int?
    public let natAuto: Bool?
    public static let waitingSource = CharacterCheckBreakdown(
        availability: .waitingSource, die: nil, skill: nil, situational: nil,
        bargain: nil, momentum: nil, total: nil, dc: nil, natAuto: nil)
    public static func read(_ raw: PlayWireValue) -> Self {
        if raw == .null { return .waitingSource }
        guard raw.object != nil else { return .init(availability: .unknown, die: nil, skill: nil, situational: nil, bargain: nil, momentum: nil, total: nil, dc: nil, natAuto: nil) }
        let skill: Skill?
        if raw["skill"] == .null { skill = nil }
        else if raw["skill"]["hidden"].bool == true {
            skill = .init(hidden: true, statKey: nil, label: nil, value: nil)
        } else if raw["skill"].object != nil {
            skill = .init(hidden: false, statKey: raw["skill"]["statKey"].text, label: raw["skill"]["label"].text, value: raw["skill"]["value"].integer)
        } else { return .init(availability: .unknown, die: nil, skill: nil, situational: nil, bargain: nil, momentum: nil, total: nil, dc: nil, natAuto: nil) }
        let situational: Situational?
        if raw["situational"] == .null { situational = nil }
        else if raw["situational"].object != nil {
            situational = .init(raw: raw["situational"]["raw"].integer, applied: raw["situational"]["applied"].integer, cap: raw["situational"]["cap"].integer)
        } else { return .init(availability: .unknown, die: nil, skill: nil, situational: nil, bargain: nil, momentum: nil, total: nil, dc: nil, natAuto: nil) }
        return .init(availability: .ready, die: raw["die"].integer, skill: skill, situational: situational,
                     bargain: raw["bargain"].integer, momentum: raw["momentum"].integer,
                     total: raw["total"].integer, dc: raw["dc"].integer, natAuto: raw["natAuto"].bool)
    }
}

public struct CharacterCardAttribute: Equatable, Identifiable {
    public var id: String { stateKey }
    public let stateKey: String
    public let label: String
    public let value: Int
    public let min: Int
    public let max: Int
    public let displayType: String
    public let persistScope: String
}

public struct CharacterCard: Equatable {
    public let topicID: Int
    public let created: Bool
    public let running: Bool
    public let attributes: [CharacterCardAttribute]
    public let environment: WorldEnvironmentProjection
    public let party: PartyRosterProjection
    public let equipment: WorldEquipmentProjection
    public let breakdown: CharacterCheckBreakdown
    public let expiry: EnvironmentExpiryClock
    public let originalRequestID: String?
    func updating(breakdown: CharacterCheckBreakdown? = nil, originalRequestID: String? = nil) -> Self {
        .init(topicID: topicID, created: created, running: running, attributes: attributes,
              environment: environment, party: party, equipment: equipment,
              breakdown: breakdown ?? self.breakdown, expiry: expiry,
              originalRequestID: originalRequestID ?? self.originalRequestID)
    }
}

/// Read-only original route action. Caller supplies an already-resolved actionId;
/// this does not invent a hashed action-id prefix. Missing mapper is WAITING_SOURCE.
/// A returned action id that is not the requested id is not a replay.
public enum RouteActionOriginalRecovery {
    public static let rpgRequestReceipts = "rpgv2.RpgRequestReceipts"
    public struct Receipt: Equatable {
        public let actionID: String
        public let replay: Bool
    }
    public struct WaitingSource: Error, Equatable {
        public let capability: String
    }
    public static func recoverFromRouteAction(
        sessionID: Int64?,
        memberID: Int64?,
        actionID: String?,
        selectAction: ((Int64, Int64, String) -> String?)?
    ) throws -> Receipt? {
        let trimmed = actionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let sessionID, let memberID, !trimmed.isEmpty else { return nil }
        guard let selectAction else {
            throw WaitingSource(capability: rpgRequestReceipts)
        }
        guard let found = selectAction(sessionID, memberID, trimmed), found == trimmed else { return nil }
        return Receipt(actionID: trimmed, replay: true)
    }
}

/// Read IGameSessionRuntimeService.receipt. PENDING is not applied. Does not command.
public enum GameReceiptOriginalRecovery {
    public static let gameReceipt = "gameSession.receipt"
    public struct Read: Equatable {
        public let requestID: String
        public let outcome: String
        public let replayed: Bool
        public let applied: Bool
    }
    public struct WaitingSource: Error, Equatable {
        public let capability: String
    }
    public static func recoverFromGameReceipt(
        memberID: Int64?,
        activityID: Int64?,
        requestID: String?,
        receipt: ((Int64, Int64, String) -> (requestID: String, outcome: String, replayed: Bool)?)?
    ) throws -> Read? {
        let trimmed = requestID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let memberID, memberID > 0, let activityID, activityID > 0, !trimmed.isEmpty else { return nil }
        guard let receipt else {
            throw WaitingSource(capability: gameReceipt)
        }
        guard let found = receipt(memberID, activityID, trimmed), found.requestID == trimmed else { return nil }
        return Read(requestID: trimmed, outcome: found.outcome, replayed: found.replayed,
                    applied: found.outcome == "APPLIED")
    }
}

/// Existing Play/RPG surfaces (`PlayExperienceView`, `PlayAdvancedView`,
/// `PlayPlayerTeamStatusView`, `JourneyCheckCoordinator`, `PlayObjectCardRevealView`)
/// stay the host. This lease only projects character / world facts through
/// `PlayExperienceService` and never opens a private transport.
@available(macOS 14.0, *)
@MainActor @Observable public final class CharacterCardReadback {
    public let topicID: Int
    public let activityID: Int?
    public private(set) var card: CharacterCard?
    public private(set) var availability: WorldFactAvailability = .waitingSource
    public private(set) var originalRequestID: String?
    public private(set) var issue: PlayExperienceError?
    private let service: PlayExperienceService
    private let currentSession: () -> PlayExperienceSession?
    private var owner: PlayExperienceSession?
    private var original: PlayPlayerCommand?
    private var generation: UInt64 = 0
    private var retired = false
    public init?(topicID: Int, activityID: Int? = nil, service: PlayExperienceService,
                 currentSession: @escaping () -> PlayExperienceSession?) {
        guard topicID > 0, activityID.map({ $0 > 0 }) ?? true, service.enabled.contains(.reads) else { return nil }
        self.topicID = topicID; self.activityID = activityID; self.service = service; self.currentSession = currentSession
    }
    public var isCurrent: Bool { !retired && owner != nil && owner == currentSession() }
    public func dismiss() { retired = true; card = nil; availability = .waitingSource }
    /// Freeze the original command identity. A new UUID is never minted here.
    public func bindOriginal(_ command: PlayPlayerCommand) {
        guard command.requestID.range(of: "^[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil else { return }
        if let originalRequestID { guard originalRequestID == command.requestID else { return } }
        original = command; originalRequestID = command.requestID
        if let card { self.card = card.updating(originalRequestID: command.requestID) }
    }
    public func acceptBreakdown(_ raw: PlayWireValue) {
        guard isCurrent, let card else { return }
        self.card = card.updating(breakdown: CharacterCheckBreakdown.read(raw["breakdown"] == .null ? raw : raw["breakdown"]),
                                  originalRequestID: originalRequestID)
    }
    public func load() async {
        guard !retired, let session = currentSession() else { availability = .waitingSource; return }
        if owner != nil && owner != session { card = nil; availability = .unknown; issue = .staleSession; return }
        owner = session; generation &+= 1; let stamp = generation; issue = nil
        do {
            var query = ["topicId": String(topicID)]
            let raw = try await service.request("api/play/character", query: query, capability: .reads, token: session.token)
            try check(session, stamp)
            guard let topic = raw["topicId"].integer, topic == topicID,
                  let created = raw["created"].bool, let running = raw["running"].bool,
                  let rows = raw["attributes"].array else { throw PlayExperienceError.malformed }
            var attributes: [CharacterCardAttribute] = []; var keys = Set<String>()
            for row in rows {
                guard let stateKey = row["stateKey"].text, !stateKey.isEmpty, stateKey.utf16.count <= 64, keys.insert(stateKey).inserted,
                      let label = row["label"].text, !label.isEmpty, label.utf16.count <= 64,
                      let value = row["value"].integer, let min = row["min"].integer, let max = row["max"].integer,
                      min <= max, value >= min, value <= max,
                      let display = row["displayType"].text, !display.isEmpty,
                      let scope = row["persistScope"].text, ["run", "topic"].contains(scope) else { throw PlayExperienceError.malformed }
                attributes.append(.init(stateKey: stateKey, label: label, value: value, min: min, max: max, displayType: display, persistScope: scope))
            }
            var environment = WorldEnvironmentProjection.read(raw)
            var expiry = EnvironmentExpiryClock.read(raw["rpg"]["environment"] == .null ? raw["environment"] : raw["rpg"]["environment"])
            var party = PartyRosterProjection.read(party: raw["party"] == .null ? raw["rpg"]["party"] : raw["party"])
            var equipment = WorldEquipmentProjection.read(raw)
            if let activityID, service.enabled.contains(.reads) {
                query["activityId"] = String(activityID)
                let status = try await service.request("api/play/rpg/status", query: query, capability: .reads, token: session.token)
                try check(session, stamp)
                if status["topicId"].integer == topicID {
                    let overlay = WorldEnvironmentProjection.read(status)
                    if overlay.availability == .ready { environment = overlay }
                    let clock = EnvironmentExpiryClock.read(status["rpg"]["environment"] == .null ? status["environment"] : status["rpg"]["environment"])
                    if clock.availability != .waitingSource { expiry = clock }
                    let gear = WorldEquipmentProjection.read(status)
                    if gear.availability == .ready { equipment = gear }
                    let roster = PartyRosterProjection.read(party: status["party"] == .null ? status["rpg"]["party"] : status["party"])
                    if roster.availability == .ready { party = roster }
                }
                if party.availability == .waitingSource {
                    do {
                        let projection = try await service.playerProjection(activityID: activityID, token: session.token)
                        try check(session, stamp)
                        party = PartyRosterProjection.read(teamActions: projection.teamActions)
                    } catch {
                        try check(session, stamp)
                        party = .unknown
                    }
                }
            }
            try check(session, stamp)
            card = CharacterCard(topicID: topic, created: created, running: running, attributes: attributes,
                                 environment: environment, party: party, equipment: equipment,
                                 breakdown: .waitingSource, expiry: expiry, originalRequestID: originalRequestID)
            availability = .ready
        } catch {
            guard generation == stamp else { return }
            card = nil
            issue = error as? PlayExperienceError ?? .unknownResult
            availability = issue == .disabled ? .waitingSource : .unknown
        }
    }
    /// Replay the frozen command/requestId through the existing session writer. No new identity.
    public func retryOriginal() async {
        guard isCurrent, let session = owner, session == currentSession(),
              let command = original, let originalRequestID, command.requestID == originalRequestID else { return }
        guard service.enabled.contains(.playerCommands) else { issue = .disabled; availability = .waitingSource; return }
        generation &+= 1; let stamp = generation; issue = nil
        do {
            _ = try await service.playerCommand(command, token: session.token)
            try check(session, stamp)
            await load()
        } catch PlayExperienceError.unknownResult {
            guard generation == stamp, currentSession() == session else { return }
            do {
                _ = try await service.playerReceipt(command, token: session.token)
                try check(session, stamp)
                await load()
            } catch {
                guard generation == stamp else { return }
                issue = error as? PlayExperienceError ?? .unknownResult
                availability = .unknown
            }
        } catch {
            guard generation == stamp else { return }
            issue = error as? PlayExperienceError ?? .unknownResult
            availability = .unknown
        }
    }
    private func check(_ session: PlayExperienceSession, _ generation: UInt64) throws {
        guard self.generation == generation, !retired, currentSession() == session, !Task.isCancelled else { throw PlayExperienceError.staleSession }
    }
}
