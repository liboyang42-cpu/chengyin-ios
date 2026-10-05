import Foundation
import Observation

public struct PlayPreferenceStep: Equatable, Identifiable {
    public struct Option: Equatable, Identifiable { public let id: String; public let text: String }
    public let id: String; public let type: String; public let title: String; public let options: [Option]
    public init(_ raw: PlayWireValue) throws {
        guard let id = raw["key"].text, !id.isEmpty, let type = raw["type"].text, ["single", "discard"].contains(type),
              let title = raw["title"].text, !title.isEmpty, let options = raw["options"].array, options.count >= 2 else { throw PlayExperienceError.malformed }
        self.id = id; self.type = type; self.title = title
        self.options = try options.map { option in
            guard let key = option["key"].text, !key.isEmpty, let text = option["text"].text, !text.isEmpty else { throw PlayExperienceError.malformed }
            return Option(id: key, text: text)
        }
        guard Set(self.options.map(\.id)).count == self.options.count else { throw PlayExperienceError.malformed }
    }
}
public struct PlayPreferenceTag: Equatable, Identifiable {
    public let id: Int; public let code: String; public let value: String; public let status: Int?
    public init(_ raw: PlayWireValue) throws {
        guard let id = raw["id"].tolerantInteger, id > 0, let code = raw["tagCode"].text, !code.isEmpty,
              let value = raw["tagValue"].text, !value.isEmpty else { throw PlayExperienceError.malformed }
        self.id = id; self.code = code; self.value = value; status = raw["status"].tolerantInteger
    }
}
public struct PlayPreferenceQuestionnaire: Equatable {
    public let nodeID: Int; public let steps: [PlayPreferenceStep]; public let inheritedTags: [PlayPreferenceTag]
    public init(_ raw: PlayWireValue, nodeID: Int) throws {
        guard nodeID > 0, raw["nodeId"].tolerantInteger == nodeID else { throw PlayExperienceError.malformed }
        self.nodeID = nodeID; steps = try (raw["steps"].array ?? []).map(PlayPreferenceStep.init)
        inheritedTags = try (raw["inheritedTags"].array ?? []).map(PlayPreferenceTag.init)
        guard !steps.isEmpty || !inheritedTags.isEmpty, Set(steps.map(\.id)).count == steps.count,
              Set(inheritedTags.map(\.id)).count == inheritedTags.count else { throw PlayExperienceError.malformed }
    }
}
public struct PlayPreferenceSubmission: Equatable {
    public let needsTiebreak: Bool; public let tiebreak: PlayPreferenceStep?
    public let evaluation: PlayWireValue; public let progress: PlayWireValue
    public let pendingTag: PlayPreferenceTag?; public let disclosure: PlayWireValue; public let availableTagValues: [String]
    public init(_ raw: PlayWireValue, nodeID: Int) throws {
        needsTiebreak = raw["needsTiebreak"].bool == true || raw["needsTiebreak"].tolerantInteger == 1
        tiebreak = raw["tiebreak"] == .null ? nil : try PlayPreferenceStep(raw["tiebreak"])
        evaluation = raw["evaluation"]; progress = raw["progress"]
        pendingTag = raw["pendingTag"] == .null ? nil : try PlayPreferenceTag(raw["pendingTag"])
        disclosure = raw["tagDisclosure"]; availableTagValues = raw["availableTagValues"].array?.compactMap(\.text) ?? []
        if needsTiebreak { guard tiebreak != nil else { throw PlayExperienceError.malformed } }
        else {
            guard evaluation["resultCode"].text?.isEmpty == false, evaluation["title"].text?.isEmpty == false,
                  evaluation["body"].text?.isEmpty == false, progress["nodeId"].tolerantInteger == nodeID else { throw PlayExperienceError.malformed }
        }
    }
    public var canDiscloseTag: Bool { disclosure["purpose"].text?.isEmpty == false && disclosure["recipientLabel"].text?.isEmpty == false }
}
public struct PlayPreferenceReview: Equatable {
    public let choices: [String: String]; public let reusedTagCode: String?; public let advance: PlayRouteAdvance?
    let session: PlayExperienceSession; let generation: UInt64
}
extension PlayExperienceService {
    public func preference(scope: PlaySessionScope, nodeID: Int, token: String) async throws -> PlayPreferenceQuestionnaire {
        guard nodeID > 0 else { throw APIError.invalidRequest }
        return try PlayPreferenceQuestionnaire(await request("api/play/preference/\(nodeID)", query: scopeFields(scope), capability: .reads, token: token), nodeID: nodeID)
    }
    public func submitPreference(scope: PlaySessionScope, nodeID: Int, review: PlayPreferenceReview, token: String) async throws -> PlayPreferenceSubmission {
        guard scope.isValid, nodeID > 0 else { throw APIError.invalidRequest }
        var json = scopeJSON(scope); json["choices"] = .object(review.choices.mapValues(PlayWireValue.string))
        if let reused = review.reusedTagCode { json["reuseTagCode"] = .string(reused) }
        if let advance = review.advance { json["routeActionId"] = .string(advance.actionID); json["expectedRouteVersion"] = .int(advance.expectedVersion) }
        return try PlayPreferenceSubmission(await request("api/play/preference/\(nodeID)/submit", json: json, capability: .preference, token: token), nodeID: nodeID)
    }
    public func writePreferenceTag(_ tag: PlayPreferenceTag, correctedValue: String?, token: String) async throws -> PlayPreferenceTag {
        let raw: PlayWireValue
        if let correctedValue {
            guard !correctedValue.isEmpty else { throw APIError.invalidRequest }
            raw = try await request("api/play/tag/\(tag.id)/correct", json: ["tagValue": .string(correctedValue)], capability: .tags, token: token)
        } else { raw = try await request("api/play/tag/\(tag.id)/confirm", postWithoutBody: true, capability: .tags, token: token) }
        let result = try PlayPreferenceTag(raw)
        guard result.id == tag.id, result.code == tag.code, correctedValue == nil ? result.status == 1 : result.value == correctedValue else { throw PlayExperienceError.malformed }
        return result
    }
}
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayPreferenceCoordinator {
    public let scope: PlaySessionScope; public let nodeID: Int
    public private(set) var steps: [PlayPreferenceStep] = []
    public private(set) var inheritedTags: [PlayPreferenceTag] = []
    public private(set) var choices: [String: String] = [:]
    public private(set) var submission: PlayPreferenceSubmission?
    public private(set) var pendingTag: PlayPreferenceTag?
    public private(set) var phase = "idle"
    public private(set) var issue: PlayExperienceError?
    private let service: PlayExperienceService
    private let currentSession: () -> PlayExperienceSession?
    private var owner: PlayExperienceSession?
    private var generation: UInt64 = 0
    private var snapshot: PlaySnapshot?
    private var pending: PlayPreferenceReview?
    private var tagOutcomeUnknown = false
    private var tiebreakStep: PlayPreferenceStep?
    private var routeAdvance: PlayRouteAdvance?
    private var tagExpectedValue: String?
    private var tagMustBeConfirmed = false
    public init(scope: PlaySessionScope, nodeID: Int, service: PlayExperienceService, currentSession: @escaping () -> PlayExperienceSession?) {
        self.scope = scope; self.nodeID = nodeID; self.service = service; self.currentSession = { service.hasCurrentReadLifetime ? currentSession() : nil }
    }
    public var readLifetimeID: String? { service.readLifetimeID }
    public var hasCurrentReadLifetime: Bool { service.hasCurrentReadLifetime }
    public var blocksReadRebinding: Bool { pending != nil || tagOutcomeUnknown || ["loading", "submitting"].contains(phase) }
    public func load() async {
        guard phase != "submitting", let session = currentSession() else { return }
        if let owner, owner != session { steps = []; inheritedTags = []; submission = nil; pendingTag = nil; phase = "stale"; return }
        owner = session; generation &+= 1; let generation = generation; phase = "loading"; issue = nil
        do {
            let document = try await service.nodes(scope: scope, token: session.token); try check(session, generation)
            let authority = document.base.routeState?.isBranch == true ? try await service.route(scope: scope, token: session.token) : nil
            try check(session, generation)
            let value = try PlaySnapshot(scope: scope, result: document.base, authority: authority)
            guard let node = value.visibleNodes.first(where: { $0.id == nodeID }), node.validationMethod == 6, !value.isLocked(node) else { throw PlayExperienceError.invalidAction }
            snapshot = value
            if value.isDone(node) {
                pending = nil; routeAdvance = nil
                if tagOutcomeUnknown, let tag = pendingTag {
                    let fresh = try await service.preference(scope: scope, nodeID: nodeID, token: session.token); try check(session, generation)
                    if let found = fresh.inheritedTags.first(where: { $0.id == tag.id && $0.code == tag.code && $0.value == tagExpectedValue && (!tagMustBeConfirmed || $0.status == 1) }) {
                        pendingTag = found; tagOutcomeUnknown = false
                    }
                }
                phase = tagOutcomeUnknown ? "unknown" : "completed"; return
            }
            guard value.availability == .active else { throw PlayExperienceError.invalidAction }
            let questionnaire = try await service.preference(scope: scope, nodeID: nodeID, token: session.token); try check(session, generation)
            steps = questionnaire.steps
            if let tiebreakStep, !steps.contains(where: { $0.id == tiebreakStep.id }) { steps.append(tiebreakStep) }
            choices = choices.filter { entry in steps.contains { $0.id == entry.key && $0.options.contains { $0.id == entry.value } } }
            inheritedTags = questionnaire.inheritedTags; phase = pending == nil && !tagOutcomeUnknown ? "ready" : "unknown"
        } catch { fail(error, session, generation) }
    }
    public func select(stepID: String, optionID: String) {
        guard phase == "ready", pending == nil, let step = steps.first(where: { $0.id == stepID }), step.options.contains(where: { $0.id == optionID }) else { return }
        choices[stepID] = optionID
    }
    public func review(reuseTagID: Int? = nil) throws -> PlayPreferenceReview {
        guard phase == "ready", pending == nil, let session = owner, session == currentSession(), let snapshot else { throw PlayExperienceError.invalidAction }
        let reuse: String?
        if let id = reuseTagID {
            guard let tag = inheritedTags.first(where: { $0.id == id }) else { throw PlayExperienceError.invalidAction }; reuse = tag.code
        } else {
            guard !steps.isEmpty, steps.allSatisfy({ step in step.options.contains { $0.id == choices[step.id] } }) else { throw PlayExperienceError.invalidAction }; reuse = nil
        }
        if snapshot.route?.isBranch == true, routeAdvance == nil {
            routeAdvance = try PlayRouteAdvance(actionID: UUID().uuidString, expectedVersion: snapshot.route?.version ?? -1)
        }
        phase = "reviewing"
        return .init(choices: reuse == nil ? choices : [:], reusedTagCode: reuse, advance: routeAdvance, session: session, generation: generation)
    }
    public func cancelReview() { if phase == "reviewing" { phase = "ready" } }
    public func submit(_ review: PlayPreferenceReview) async {
        guard phase == "reviewing", review.generation == generation, review.session == currentSession(), pending == nil else { return }
        pending = review; phase = "submitting"
        do {
            let result = try await service.submitPreference(scope: scope, nodeID: nodeID, review: review, token: review.session.token)
            try check(review.session, review.generation)
            if result.needsTiebreak, let step = result.tiebreak {
                if let existing = steps.first(where: { $0.id == step.id }), existing != step { throw PlayExperienceError.malformed }
                if !steps.contains(where: { $0.id == step.id }) { steps.append(step) }
                tiebreakStep = step
                pending = nil; phase = "ready"; return
            }
            submission = result; pendingTag = result.pendingTag; phase = "unknown"; await load()
        } catch {
            if case PlayExperienceError.rejected(let code, _) = error {
                pending = nil; routeAdvance = nil
                if code == 409 { phase = "ready"; await load(); return }
            }
            if case PlayExperienceError.disabled = error { pending = nil }
            fail(error, review.session, review.generation)
        }
    }
    public var canRetryExact: Bool {
        guard phase == "unknown", !tagOutcomeUnknown, let pending, let advance = pending.advance,
              pending.session == currentSession(), snapshot?.route?.version == advance.expectedVersion,
              snapshot?.route?.nodeStates[nodeID] == "PLAYABLE" else { return false }
        return true
    }
    public func retryExact() async {
        guard canRetryExact, let original = pending else { return }
        let review = PlayPreferenceReview(choices: original.choices, reusedTagCode: original.reusedTagCode,
            advance: original.advance, session: original.session, generation: generation)
        pending = nil; phase = "reviewing"; await submit(review)
    }
    public func writeTag(correctedValue: String? = nil) async {
        guard phase == "completed", !tagOutcomeUnknown, let tag = pendingTag, let result = submission,
              result.canDiscloseTag, let session = owner, session == currentSession() else { return }
        if let correctedValue { guard result.availableTagValues.contains(correctedValue), correctedValue != tag.value else { return } }
        else if tag.status == 1 { return }
        let generation = generation; phase = "submitting"; tagOutcomeUnknown = true
        tagExpectedValue = correctedValue ?? tag.value; tagMustBeConfirmed = correctedValue == nil
        do { let value = try await service.writePreferenceTag(tag, correctedValue: correctedValue, token: session.token); try check(session, generation); pendingTag = value; tagOutcomeUnknown = false; phase = "completed" }
        catch {
            if case PlayExperienceError.rejected = error { tagOutcomeUnknown = false }
            if case PlayExperienceError.disabled = error { tagOutcomeUnknown = false }
            fail(error, session, generation)
        }
    }
    private func check(_ session: PlayExperienceSession, _ generation: UInt64) throws { guard self.generation == generation, currentSession() == session, !Task.isCancelled else { throw PlayExperienceError.staleSession } }
    private func fail(_ error: Error, _ session: PlayExperienceSession, _ generation: UInt64) {
        guard self.generation == generation else { return }
        guard currentSession() == session else { steps = []; inheritedTags = []; submission = nil; pendingTag = nil; phase = "stale"; return }
        issue = error as? PlayExperienceError ?? .unknownResult; phase = pending != nil || tagOutcomeUnknown ? "unknown" : "failed"
    }
}
