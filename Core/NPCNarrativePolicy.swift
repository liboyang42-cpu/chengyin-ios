import Foundation

/// Reform plan v9 §9 / W04.5–W04.7. The model may only *propose* one whitelisted narrative
/// action; the server re-judges it. The client additionally drops anything outside the
/// whitelist or outside the visible context before rendering, and never mutates play state.
public enum NPCNarrativeAction: String, CaseIterable, Sendable {
    case explainKnownRule = "EXPLAIN_KNOWN_RULE"
    case presentUnlockedClue = "PRESENT_UNLOCKED_CLUE"
    case askCurrentNodeQuestion = "ASK_CURRENT_NODE_QUESTION"
    case selectApprovedTone = "SELECT_APPROVED_TONE"
    case suggestAvailableSideQuest = "SUGGEST_AVAILABLE_SIDE_QUEST"
}

/// Business decisions owned by independent services. An NPC proposal naming any of them is
/// dropped, even when the surrounding reply text is otherwise displayable.
public enum NPCForbiddenEffect: String, CaseIterable, Sendable {
    case grantReward = "GRANT_REWARD"
    case deductStock = "DEDUCT_STOCK"
    case changePrice = "CHANGE_PRICE"
    case createDiscount = "CREATE_DISCOUNT"
    case confirmArrival = "CONFIRM_ARRIVAL"
    case completeTask = "COMPLETE_TASK"
    case payment = "PAYMENT"
    case refund = "REFUND"
    case adjustPoints = "ADJUST_POINTS"
}

/// Minimal projection of what the current run can see (GetVisibleQuestContext).
public struct NPCVisibleContext: Equatable, Sendable {
    public let releaseID: String
    public let currentNodeID: String
    public let unlockedClueIDs: Set<String>
    public let approvedToneKeys: Set<String>
    public let availableSideQuestIDs: Set<String>
    public init(releaseID: String, currentNodeID: String, unlockedClueIDs: Set<String>, approvedToneKeys: Set<String>, availableSideQuestIDs: Set<String>) {
        self.releaseID = releaseID; self.currentNodeID = currentNodeID; self.unlockedClueIDs = unlockedClueIDs
        self.approvedToneKeys = approvedToneKeys; self.availableSideQuestIDs = availableSideQuestIDs
    }
}

public struct NPCNarrativeProposal: Equatable, Sendable {
    public let action: NPCNarrativeAction
    /// Clue, node, tone or side-quest identifier, depending on the action.
    public let target: String?
}

public enum NPCProposalDecision: Equatable, Sendable {
    public enum DropReason: String, Sendable { case unknownAction, forbiddenEffect, targetNotVisible, staleRelease }
    case accepted(NPCNarrativeProposal)
    case dropped(DropReason)
}

public enum NPCNarrativePolicy {
    public static func evaluate(rawAction: String, target: String?, releaseID: String, visible: NPCVisibleContext) -> NPCProposalDecision {
        if NPCForbiddenEffect(rawValue: rawAction) != nil { return .dropped(.forbiddenEffect) }
        guard let action = NPCNarrativeAction(rawValue: rawAction) else { return .dropped(.unknownAction) }
        guard releaseID == visible.releaseID else { return .dropped(.staleRelease) }
        let visibleTarget: Bool
        switch action {
        case .explainKnownRule: visibleTarget = target == nil
        case .presentUnlockedClue: visibleTarget = target.map { visible.unlockedClueIDs.contains($0) } ?? false
        case .askCurrentNodeQuestion: visibleTarget = target == visible.currentNodeID
        case .selectApprovedTone: visibleTarget = target.map { visible.approvedToneKeys.contains($0) } ?? false
        case .suggestAvailableSideQuest: visibleTarget = target.map { visible.availableSideQuestIDs.contains($0) } ?? false
        }
        return visibleTarget ? .accepted(NPCNarrativeProposal(action: action, target: target)) : .dropped(.targetNotVisible)
    }
}

/// Memory readback for the "view / clear memory" surface (W04.5–W04.6). Trusted facts come only
/// from runtime or order events; a model summary or a player's claim stays an unverified note.
public struct NPCMemoryEntry: Equatable, Sendable {
    public enum Layer: String, Sendable {
        case characterCanon = "CHARACTER_CANON"
        case runFact = "RUN_FACT"
        case consentedPreference = "CONSENTED_PREFERENCE"
    }
    public enum Source: String, Sendable {
        case reviewedContent = "REVIEWED_CONTENT"
        case runtimeEvent = "RUNTIME_EVENT"
        case orderEvent = "ORDER_EVENT"
        case modelSummary = "MODEL_SUMMARY"
        case playerStatement = "PLAYER_STATEMENT"
    }
    public let memoryID: String
    public let isolationKey: String
    public let layer: Layer
    public let source: Source
    public let sourceEventID: String?
    public let consentVersion: String?
    public let expiresAt: Date?
    public let contentHash: String
    public init(memoryID: String, isolationKey: String, layer: Layer, source: Source, sourceEventID: String?, consentVersion: String?, expiresAt: Date?, contentHash: String) {
        self.memoryID = memoryID; self.isolationKey = isolationKey; self.layer = layer; self.source = source
        self.sourceEventID = sourceEventID; self.consentVersion = consentVersion; self.expiresAt = expiresAt; self.contentHash = contentHash
    }
    public var isTrustedFact: Bool {
        layer == .runFact && (source == .runtimeEvent || source == .orderEvent) && !(sourceEventID ?? "").isEmpty
    }
    /// Fail-closed readback filter: wrong scope, a run fact without event provenance, a preference
    /// without consent, canon not from reviewed content, or anything already expired is not shown.
    public func admissible(in scope: SceneAIScope, at serverNow: Date) -> Bool {
        guard isolationKey == scope.isolationKey, !contentHash.isEmpty else { return false }
        if let expiresAt, expiresAt <= serverNow { return false }
        switch layer {
        case .characterCanon: return source == .reviewedContent
        case .runFact: return isTrustedFact
        case .consentedPreference: return !(consentVersion ?? "").isEmpty
        }
    }
    /// After a delete or consent withdrawal the same memory must never reappear in a later read.
    public static func respectsDeletion(_ later: [NPCMemoryEntry], deleted: Set<String>) -> Bool {
        later.allSatisfy { !deleted.contains($0.memoryID) }
    }
}
