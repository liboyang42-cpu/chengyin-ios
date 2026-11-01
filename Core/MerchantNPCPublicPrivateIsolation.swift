import Foundation

/// Public store / theme-run NPC facts stay isolated from private operating drafts.
public enum MerchantNPCAudience: Equatable {
    case playerPublicNPC, merchantPrivateAssistant, themeRun
}

@MainActor public final class MerchantNPCPublicPrivateIsolation {
    public static let themeMainlineAvailableWhenAIUnavailable = true
    private var privateScopes: Set<String> = []
    public init() {}
    public func audience(for phase: MerchantNPCDraftPhase) -> MerchantNPCAudience {
        phase == .published ? .playerPublicNPC : .merchantPrivateAssistant
    }
    public func visibilityIsPublic(_ phase: MerchantNPCDraftPhase) -> Bool { phase == .published }
    public func themeRunMayProceed(aiFailure: MerchantNPCDraftGateFailure?) -> Bool {
        switch aiFailure {
        case .aiUnavailable, .waitingSource, .none: return Self.themeMainlineAvailableWhenAIUnavailable
        default: return Self.themeMainlineAvailableWhenAIUnavailable
        }
    }
    public func retainPrivate(draft: MerchantNPCKnowledgeDraft, scope: MerchantNPCScope) {
        _ = draft
        privateScopes.insert(Self.key(scope))
    }
    public func publish(_ revision: MerchantNPCPublishedRevision, scope: MerchantNPCScope) {
        guard revision.scope == scope else { return }
        privateScopes.remove(Self.key(scope))
    }
    public func playerProjection(scope: MerchantNPCScope, qualification: MerchantNPCQualificationRevoke) throws -> Data {
        guard qualification.allowsServing(scope) else { throw MerchantNPCDraftGateFailure.qualificationRevoked }
        guard let revision = qualification.cachedPublic(scope), revision.scope == scope else {
            throw MerchantNPCDraftGateFailure.unpublished
        }
        guard !privateScopes.contains(Self.key(scope)) else { throw MerchantNPCDraftGateFailure.isolationViolation }
        return revision.facts
    }
    public func rejectPrivateLeak(playerPayload: Data, privateDraft: MerchantNPCKnowledgeDraft, phase: MerchantNPCDraftPhase) throws {
        guard phase == .published else {
            if let privateFacts = try? privateDraft.validatedPublicFactsJSON(), privateFacts == playerPayload {
                throw MerchantNPCDraftGateFailure.isolationViolation
            }
            return
        }
    }
    static func key(_ scope: MerchantNPCScope) -> String {
        "merchant-npc-iso:\(scope.namespace.utf8.count):\(scope.namespace):account:\(scope.accountID):row:\(scope.merchantRowID.rawValue)"
    }
}
