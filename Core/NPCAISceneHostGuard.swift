import Foundation

/// Reform plan v9 §7–9 / G-W04: Host preflight and response-validation guard bridging
/// `SceneAIScope`, `SceneAIAvailability`, `ThemeNPCSessionScope`, and `NPCNarrativePolicy`
/// for store-public, theme-bound, and roam NPC chat coordinators.
///
/// Defaults to `SceneAIAvailability.disabled` (non-generative, streaming display off),
/// refuses forbidden data classes, drops forbidden business effects and out-of-context
/// narrative proposals, and filters memory readbacks with deletion fences.
public enum NPCAISceneHostContext: Equatable, Sendable {
    case storePublic(merchantID: String, storeID: String)
    case themeBound(session: ThemeNPCSessionScope, clientThemeHint: String? = nil, clientReleaseHint: String? = nil)
    case roam(
        session: ThemeNPCSessionScope? = nil,
        storeMerchantID: String? = nil,
        storeID: String? = nil,
        clientThemeHint: String? = nil,
        clientReleaseHint: String? = nil
    )

    public enum ScopeResolution: Equatable, Sendable {
        case resolved(SceneAIScope)
        case clientHintMismatch
        case invalidScope
    }

    public func resolveScope() -> ScopeResolution {
        switch self {
        case let .storePublic(merchantID, storeID):
            let candidate = SceneAIScope.storePublic(merchantID: merchantID, storeID: storeID)
            return candidate.isValid ? .resolved(candidate) : .invalidScope

        case let .themeBound(session, clientThemeHint, clientReleaseHint):
            guard session.agrees(withClientThemeHint: clientThemeHint, releaseHint: clientReleaseHint) else {
                return .clientHintMismatch
            }
            let candidate = SceneAIScope.themeBinding(session)
            return candidate.isValid ? .resolved(candidate) : .invalidScope

        case let .roam(session, storeMerchantID, storeID, clientThemeHint, clientReleaseHint):
            if let session {
                guard session.agrees(withClientThemeHint: clientThemeHint, releaseHint: clientReleaseHint) else {
                    return .clientHintMismatch
                }
                let candidate = SceneAIScope.themeBinding(session)
                return candidate.isValid ? .resolved(candidate) : .invalidScope
            }
            guard clientThemeHint == nil, clientReleaseHint == nil,
                  let storeMerchantID, let storeID else {
                return .invalidScope
            }
            let candidate = SceneAIScope.storePublic(merchantID: storeMerchantID, storeID: storeID)
            return candidate.isValid ? .resolved(candidate) : .invalidScope
        }
    }
}

public enum NPCAIScenePreflightDecision: Equatable, Sendable {
    public enum RejectionReason: Equatable, Sendable {
        case invalidScope
        case clientHintMismatch
        case unregisteredBizType(String)
        case forbiddenDataClasses(Set<SceneAIDataClass>)
    }

    case generative(scope: SceneAIScope, isolationKey: String, bizType: String, allowsStreamingDisplay: Bool)
    case nonGenerative(scope: SceneAIScope, isolationKey: String, reasonKey: String, allowsStreamingDisplay: Bool)
    case rejected(RejectionReason)

    public var allowsStreamingDisplay: Bool { false }
}

public struct NPCAISceneRawProposal: Equatable, Sendable {
    public let rawAction: String
    public let target: String?

    public init(rawAction: String, target: String? = nil) {
        self.rawAction = rawAction
        self.target = target
    }
}

public struct NPCAISceneValidatedReply: Equatable, Sendable {
    public let scope: SceneAIScope
    public let isolationKey: String
    public let safeText: String
    public let traceID: String
    public let policyVersion: String
    public let promptVersion: String
    public let acceptedProposal: NPCNarrativeProposal?
    public let droppedProposalReason: NPCProposalDecision.DropReason?
    public let allowsStreamingDisplay: Bool

    public init(
        scope: SceneAIScope,
        isolationKey: String,
        safeText: String,
        traceID: String,
        policyVersion: String,
        promptVersion: String,
        acceptedProposal: NPCNarrativeProposal?,
        droppedProposalReason: NPCProposalDecision.DropReason?,
        allowsStreamingDisplay: Bool = false
    ) {
        self.scope = scope
        self.isolationKey = isolationKey
        self.safeText = safeText
        self.traceID = traceID
        self.policyVersion = policyVersion
        self.promptVersion = promptVersion
        self.acceptedProposal = acceptedProposal
        self.droppedProposalReason = droppedProposalReason
        self.allowsStreamingDisplay = allowsStreamingDisplay
    }
}

public enum NPCAISceneReplyOutcome: Equatable, Sendable {
    public enum DiscardReason: Equatable, Sendable {
        case scopeMismatch
        case missingAudit
        case emptySafeText
    }

    case display(NPCAISceneValidatedReply)
    case discarded(DiscardReason)
}

public enum NPCAIMemoryReadbackOutcome: Equatable, Sendable {
    case admissible([NPCMemoryEntry])
    case deletionFenceViolated(reappearedMemoryIDs: Set<String>)
}

public struct NPCAISceneHostGuard: Equatable, Sendable {
    public var availability: SceneAIAvailability

    public init(availability: SceneAIAvailability = .disabled) {
        self.availability = availability
    }

    public static let disabled = NPCAISceneHostGuard(availability: .disabled)

    /// Preflight check before any NPC coordinator prepares or dispatches a prompt.
    public func preflight(
        context: NPCAISceneHostContext,
        bizType: String,
        requestedData: Set<SceneAIDataClass> = [.approvedStoreFacts]
    ) -> NPCAIScenePreflightDecision {
        let scope: SceneAIScope
        switch context.resolveScope() {
        case .resolved(let resolved):
            scope = resolved
        case .clientHintMismatch:
            return .rejected(.clientHintMismatch)
        case .invalidScope:
            return .rejected(.invalidScope)
        }

        guard scope.isValid, scope.scenario.availableInApp else {
            return .rejected(.invalidScope)
        }

        let forbiddenUsed = requestedData.intersection(scope.scenario.forbiddenData)
        guard forbiddenUsed.isEmpty else {
            return .rejected(.forbiddenDataClasses(forbiddenUsed))
        }

        guard scope.scenario.registeredBizTypes.contains(bizType) else {
            return .rejected(.unregisteredBizType(bizType))
        }

        switch availability.mode(for: scope) {
        case .generative:
            return .generative(
                scope: scope,
                isolationKey: scope.isolationKey,
                bizType: bizType,
                allowsStreamingDisplay: availability.allowsStreamingDisplay
            )
        case .nonGenerative(let reasonKey):
            return .nonGenerative(
                scope: scope,
                isolationKey: scope.isolationKey,
                reasonKey: reasonKey,
                allowsStreamingDisplay: availability.allowsStreamingDisplay
            )
        }
    }

    /// Validates an incoming NPC reply against the sent scope, audit echo, and visible narrative context.
    /// Forbidden business effects and non-visible targets are dropped before rendering.
    public func validateReply(
        safeText: String,
        echo: SceneAIReplyEcho,
        sentFor scope: SceneAIScope,
        proposal: NPCAISceneRawProposal? = nil,
        visibleContext: NPCVisibleContext? = nil
    ) -> NPCAISceneReplyOutcome {
        switch SceneAIAvailability.decide(echo, sentFor: scope) {
        case .discardScopeMismatch:
            return .discarded(.scopeMismatch)
        case .discardMissingAudit:
            return .discarded(.missingAudit)
        case .display:
            break
        }

        let trimmedText = safeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .discarded(.emptySafeText)
        }

        var acceptedProposal: NPCNarrativeProposal?
        var droppedReason: NPCProposalDecision.DropReason?

        if let proposal {
            switch Self.evaluateProposal(proposal, scope: scope, echo: echo, visibleContext: visibleContext) {
            case .accepted(let checked):
                acceptedProposal = checked
            case .dropped(let reason):
                droppedReason = reason
            }
        }

        return .display(
            NPCAISceneValidatedReply(
                scope: scope,
                isolationKey: scope.isolationKey,
                safeText: safeText,
                traceID: echo.traceID,
                policyVersion: echo.policyVersion,
                promptVersion: echo.promptVersion,
                acceptedProposal: acceptedProposal,
                droppedProposalReason: droppedReason,
                allowsStreamingDisplay: availability.allowsStreamingDisplay
            )
        )
    }

    /// Evaluates a proposed narrative action against `NPCNarrativePolicy`.
    public static func evaluateProposal(
        _ proposal: NPCAISceneRawProposal,
        scope: SceneAIScope,
        echo: SceneAIReplyEcho,
        visibleContext: NPCVisibleContext?
    ) -> NPCProposalDecision {
        if NPCForbiddenEffect(rawValue: proposal.rawAction) != nil {
            return .dropped(.forbiddenEffect)
        }
        guard NPCNarrativeAction(rawValue: proposal.rawAction) != nil else {
            return .dropped(.unknownAction)
        }
        guard case .themeBinding(let session) = scope, let visibleContext else {
            return .dropped(.targetNotVisible)
        }
        let effectiveReleaseID = echo.releaseID ?? session.releaseID
        return NPCNarrativePolicy.evaluate(
            rawAction: proposal.rawAction,
            target: proposal.target,
            releaseID: effectiveReleaseID,
            visible: visibleContext
        )
    }

    /// Filters NPC memory readback entries for the active scope, enforcing deletion fences,
    /// provenance, consent, and expiration rules.
    public func filterMemoryReadback(
        _ entries: [NPCMemoryEntry],
        in scope: SceneAIScope,
        at serverNow: Date,
        deletedMemoryIDs: Set<String> = []
    ) -> NPCAIMemoryReadbackOutcome {
        guard NPCMemoryEntry.respectsDeletion(entries, deleted: deletedMemoryIDs) else {
            let reappeared = Set(entries.map(\.memoryID)).intersection(deletedMemoryIDs)
            return .deletionFenceViolated(reappearedMemoryIDs: reappeared)
        }
        let kept = entries.filter { $0.admissible(in: scope, at: serverNow) }
        return .admissible(kept)
    }
}
