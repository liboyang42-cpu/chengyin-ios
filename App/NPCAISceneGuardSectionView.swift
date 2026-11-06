import SwiftUI

extension NPCAISceneHostGuard {
    public typealias PreflightVerdict = NPCAIScenePreflightDecision
    public typealias ReplyValidation = NPCAISceneReplyOutcome
    public typealias MemoryReadbackValidation = NPCAIMemoryReadbackOutcome
}

extension NPCAIMemoryReadbackOutcome {
    public var admissibleRecords: [NPCMemoryEntry] {
        switch self {
        case .admissible(let entries):
            return entries
        case .deletionFenceViolated:
            return []
        }
    }
}

@MainActor
public struct NPCAISceneGuardSectionView: View {
    public let preflightVerdict: NPCAISceneHostGuard.PreflightVerdict
    public let replyValidation: NPCAISceneHostGuard.ReplyValidation
    public let memoryReadback: NPCAISceneHostGuard.MemoryReadbackValidation
    public let totalMemoryCandidatesCount: Int

    public init(
        preflightVerdict: NPCAISceneHostGuard.PreflightVerdict,
        replyValidation: NPCAISceneHostGuard.ReplyValidation,
        memoryReadback: NPCAISceneHostGuard.MemoryReadbackValidation,
        totalMemoryCandidatesCount: Int = 0
    ) {
        self.preflightVerdict = preflightVerdict
        self.replyValidation = replyValidation
        self.memoryReadback = memoryReadback
        self.totalMemoryCandidatesCount = max(totalMemoryCandidatesCount, memoryReadback.admissibleRecords.count)
    }

    public init(hostGuard: NPCAISceneHostGuard = .disabled) {
        let defaultScope = SceneAIScope.storePublic(merchantID: "merchant-shanghai-01", storeID: "store-bund-01")
        let defaultContext = NPCAISceneHostContext.storePublic(
            merchantID: "merchant-shanghai-01",
            storeID: "store-bund-01"
        )
        let verdict = hostGuard.preflight(
            context: defaultContext,
            bizType: "merchant_npc_chat",
            requestedData: [.approvedStoreFacts]
        )
        let echo = SceneAIReplyEcho(
            scenario: defaultScope.scenario,
            isolationKey: defaultScope.isolationKey,
            traceID: "trace-npc-9901",
            policyVersion: "pol-2026-04",
            promptVersion: "prm-v4.2",
            releaseID: nil
        )
        let reply = hostGuard.validateReply(
            safeText: "Tea is still warm. Keep your voice low near the window.",
            echo: echo,
            sentFor: defaultScope,
            proposal: NPCAISceneRawProposal(
                rawAction: NPCForbiddenEffect.grantReward.rawValue,
                target: "gold_coin"
            ),
            visibleContext: nil
        )
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let sampleEntries = [
            NPCMemoryEntry(
                memoryID: "mem-01-canon",
                isolationKey: defaultScope.isolationKey,
                layer: .characterCanon,
                source: .reviewedContent,
                sourceEventID: nil,
                consentVersion: nil,
                expiresAt: now.addingTimeInterval(3_600),
                contentHash: "hash-canon-01"
            ),
            NPCMemoryEntry(
                memoryID: "mem-02-expired",
                isolationKey: defaultScope.isolationKey,
                layer: .consentedPreference,
                source: .playerStatement,
                sourceEventID: nil,
                consentVersion: "v1",
                expiresAt: now.addingTimeInterval(-60),
                contentHash: "hash-pref-02"
            ),
            NPCMemoryEntry(
                memoryID: "mem-03-unconsented",
                isolationKey: defaultScope.isolationKey,
                layer: .consentedPreference,
                source: .playerStatement,
                sourceEventID: nil,
                consentVersion: nil,
                expiresAt: now.addingTimeInterval(3_600),
                contentHash: "hash-pref-03"
            )
        ]
        let readback = hostGuard.filterMemoryReadback(
            sampleEntries,
            in: defaultScope,
            at: now,
            deletedMemoryIDs: ["mem-deleted-99"]
        )
        self.init(
            preflightVerdict: verdict,
            replyValidation: reply,
            memoryReadback: readback,
            totalMemoryCandidatesCount: sampleEntries.count
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            preflightCard
            replyValidationCard
            memoryPrivacyCard
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("npc_ai_scene_guard_section")
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .foregroundStyle(.teal)
            Text(verbatim: "NPC AI Scene Guard & Memory Privacy")
                .font(.headline)
            Spacer()
            statusPill(
                label: preflightModeLabel,
                tint: preflightModeTint
            )
        }
    }

    private var preflightCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "1. Preflight Verdict & Scenario Isolation")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 6) {
                statusPill(label: preflightModeLabel, tint: preflightModeTint)
                statusPill(label: streamingBadgeLabel, tint: .orange)
                if isNonGenerativeBadgeVisible {
                    statusPill(label: "NON-GENERATIVE FALLBACK", tint: .yellow)
                }
            }

            Text(verbatim: "Isolation Key: \(isolationKeyText)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("npc_ai_isolation_key_label")

            Text(verbatim: "Rejected Data Classes: \(rejectedDataClassesText)")
                .font(.caption)
                .foregroundStyle(rejectedDataClassesTint)
                .accessibilityIdentifier("npc_ai_rejected_data_classes_label")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var replyValidationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "2. Reply Narrative Action & Effect Guard")
                .font(.subheadline.weight(.semibold))

            Text(verbatim: "Narrative Action Decision: \(narrativeActionDecisionText)")
                .font(.caption.weight(.medium))
                .accessibilityIdentifier("npc_ai_narrative_decision_label")

            Text(verbatim: "Dropped Forbidden Effects: \(droppedForbiddenEffectsText)")
                .font(.caption)
                .foregroundStyle(droppedEffectsTint)
                .accessibilityIdentifier("npc_ai_dropped_effects_label")

            if let safeReplyPreview = safeReplyPreviewText {
                Text(verbatim: "Validated Reply: \(safeReplyPreview)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var memoryPrivacyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "3. Memory Privacy & Deletion/Expiry/Consent Filter")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                statusPill(
                    label: "Admissible: \(admissibleMemoryCount)/\(totalMemoryCandidatesCount)",
                    tint: memoryStatusTint
                )
                statusPill(
                    label: memoryFenceBadgeText,
                    tint: memoryStatusTint
                )
            }

            Text(verbatim: memoryReadbackSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("npc_ai_memory_readback_label")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func statusPill(label: String, tint: Color) -> some View {
        Text(verbatim: label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
            )
            .foregroundStyle(tint)
    }

    // MARK: - Derived Presentation Properties

    public var isolationKeyText: String {
        switch preflightVerdict {
        case .generative(_, let isolationKey, _, _):
            return isolationKey
        case .nonGenerative(_, let isolationKey, _, _):
            return isolationKey
        case .rejected(let reason):
            return "REJECTED (\(Self.describeRejection(reason)))"
        }
    }

    public var preflightModeLabel: String {
        switch preflightVerdict {
        case .generative(_, _, let bizType, _):
            return "GENERATIVE · \(bizType)"
        case .nonGenerative(_, _, let reasonKey, _):
            return "NON-GENERATIVE · \(reasonKey)"
        case .rejected:
            return "PREFLIGHT REJECTED"
        }
    }

    private var preflightModeTint: Color {
        switch preflightVerdict {
        case .generative:
            return .green
        case .nonGenerative:
            return .orange
        case .rejected:
            return .red
        }
    }

    public var isNonGenerativeBadgeVisible: Bool {
        if case .nonGenerative = preflightVerdict {
            return true
        }
        return false
    }

    public var isStreamingDisabledBadgeVisible: Bool {
        !preflightVerdict.allowsStreamingDisplay
    }

    public var streamingBadgeLabel: String {
        switch preflightVerdict {
        case .generative(_, _, _, let allowsStreaming),
             .nonGenerative(_, _, _, let allowsStreaming):
            return allowsStreaming ? "STREAMING ON" : "STREAMING OFF"
        case .rejected:
            return "STREAMING OFF"
        }
    }

    public var rejectedDataClasses: [SceneAIDataClass] {
        if case .rejected(.forbiddenDataClasses(let classes)) = preflightVerdict {
            return classes.sorted { $0.rawValue < $1.rawValue }
        }
        return []
    }

    public var rejectedDataClassesText: String {
        let sorted = rejectedDataClasses.map(\.rawValue)
        return sorted.isEmpty ? "none" : sorted.joined(separator: ", ")
    }

    private var rejectedDataClassesTint: Color {
        rejectedDataClasses.isEmpty ? .secondary : .red
    }

    public var narrativeActionDecisionText: String {
        switch replyValidation {
        case .display(let reply):
            if let proposal = reply.acceptedProposal {
                if let target = proposal.target {
                    return "ACCEPTED (\(proposal.action.rawValue) -> \(target))"
                }
                return "ACCEPTED (\(proposal.action.rawValue))"
            } else if reply.droppedProposalReason != nil {
                return "DIALOGUE ONLY (proposal dropped)"
            } else {
                return "DIALOGUE ONLY (no narrative proposal)"
            }
        case .discarded(let reason):
            return "REPLY DISCARDED (\(Self.describeDiscard(reason)))"
        }
    }

    public var droppedForbiddenEffectsText: String {
        switch replyValidation {
        case .display(let reply):
            guard let dropReason = reply.droppedProposalReason else {
                return "none"
            }
            return Self.describeDropReason(dropReason)
        case .discarded(let reason):
            return "entire reply discarded: \(Self.describeDiscard(reason))"
        }
    }

    private var droppedEffectsTint: Color {
        switch replyValidation {
        case .display(let reply):
            return reply.droppedProposalReason == nil ? .secondary : .orange
        case .discarded:
            return .red
        }
    }

    public var safeReplyPreviewText: String? {
        guard case .display(let reply) = replyValidation else {
            return nil
        }
        return reply.safeText
    }

    public var admissibleRecords: [NPCMemoryEntry] {
        memoryReadback.admissibleRecords
    }

    public var admissibleMemoryCount: Int {
        admissibleRecords.count
    }

    public var memoryFenceBadgeText: String {
        switch memoryReadback {
        case .admissible:
            return "DELETION/EXPIRY/CONSENT VERIFIED"
        case .deletionFenceViolated(let ids):
            return "FENCE VIOLATION (\(ids.count))"
        }
    }

    public var memoryReadbackSummaryText: String {
        switch memoryReadback {
        case .admissible(let entries):
            let filteredOut = max(0, totalMemoryCandidatesCount - entries.count)
            return "Admissible memories: \(entries.count) kept, \(filteredOut) filtered by deletion/expiry/consent."
        case .deletionFenceViolated(let reappearedIDs):
            let sortedIDs = reappearedIDs.sorted().joined(separator: ", ")
            return "Deletion fence violated! Reappeared IDs blocked: \(sortedIDs)"
        }
    }

    private var memoryStatusTint: Color {
        switch memoryReadback {
        case .admissible:
            return .teal
        case .deletionFenceViolated:
            return .red
        }
    }

    private static func describeRejection(_ reason: NPCAIScenePreflightDecision.RejectionReason) -> String {
        switch reason {
        case .invalidScope:
            return "invalid_scope"
        case .clientHintMismatch:
            return "client_hint_mismatch"
        case .unregisteredBizType(let bizType):
            return "unregistered_biz_type:\(bizType)"
        case .forbiddenDataClasses(let classes):
            return "forbidden_data_classes:\(classes.map(\.rawValue).sorted().joined(separator: ","))"
        }
    }

    private static func describeDropReason(_ reason: NPCProposalDecision.DropReason) -> String {
        switch reason {
        case .forbiddenEffect:
            return "forbidden_effect"
        case .unknownAction:
            return "unknown_action"
        case .targetNotVisible:
            return "target_not_visible"
        case .staleRelease:
            return "stale_release"
        }
    }

    private static func describeDiscard(_ reason: NPCAISceneReplyOutcome.DiscardReason) -> String {
        switch reason {
        case .emptySafeText:
            return "empty_safe_text"
        case .missingAudit:
            return "missing_audit"
        case .scopeMismatch:
            return "scope_mismatch"
        }
    }
}
