import Foundation

/// Sensitive data classes audited by `NPCChatAndSceneAISafetyAudit` (`G-W04` & `I08`).
public enum NPCSafetyAuditedDataClass: String, CaseIterable, Comparable, Hashable, Sendable {
    case approvedStoreFacts = "APPROVED_STORE_FACTS"
    case unlockedClues = "UNLOCKED_CLUES"
    case coordinates = "PRECISE_COORDINATES"
    case contactInfo = "CONTACT_INFO"
    case paymentCredentials = "PAYMENT_CREDENTIALS"
    case lockedCluesAndEndings = "LOCKED_CLUES_AND_ENDINGS"
    case otherPlayerMemory = "OTHER_PLAYER_MEMORY"
    case privateStoreOperations = "PRIVATE_STORE_OPERATIONS"

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var isForbiddenForNPCChat: Bool {
        switch self {
        case .approvedStoreFacts, .unlockedClues:
            return false
        case .coordinates,
             .contactInfo,
             .paymentCredentials,
             .lockedCluesAndEndings,
             .otherPlayerMemory,
             .privateStoreOperations:
            return true
        }
    }
}

/// Authority effects audited on incoming NPC AI replies (`G-W04`).
public enum NPCSafetyAuditedAuthorityEffect: String, CaseIterable, Comparable, Hashable, Sendable {
    case presentUnlockedClue = "PRESENT_UNLOCKED_CLUE"
    case explainKnownRule = "EXPLAIN_KNOWN_RULE"
    case walletMutation = "WALLET_MUTATION"
    case inventoryMutation = "INVENTORY_MUTATION"
    case orderMutation = "ORDER_MUTATION"
    case grantReward = "GRANT_REWARD"
    case changePrice = "CHANGE_PRICE"
    case payment = "PAYMENT"
    case refund = "REFUND"

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var isForbiddenAuthorityMutation: Bool {
        switch self {
        case .presentUnlockedClue, .explainKnownRule:
            return false
        case .walletMutation,
             .inventoryMutation,
             .orderMutation,
             .grantReward,
             .changePrice,
             .payment,
             .refund:
            return true
        }
    }
}

/// Memory record candidate evaluated during `G-W04` / `I08` readback filtering.
public struct NPCSafetyMemoryRecordCandidate: Equatable, Sendable {
    public let memoryID: String
    public let isolationKey: String
    public let hasActiveConsent: Bool
    public let expiresAt: Date?
    public let isDeletedLocallyOrRemotely: Bool

    public init(
        memoryID: String,
        isolationKey: String,
        hasActiveConsent: Bool = true,
        expiresAt: Date? = nil,
        isDeletedLocallyOrRemotely: Bool = false
    ) {
        self.memoryID = memoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isolationKey = isolationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hasActiveConsent = hasActiveConsent
        self.expiresAt = expiresAt
        self.isDeletedLocallyOrRemotely = isDeletedLocallyOrRemotely
    }

    public func isAdmissible(expectedIsolationKey: String, at referenceDate: Date) -> Bool {
        guard !memoryID.isEmpty,
              isolationKey == expectedIsolationKey,
              hasActiveConsent,
              !isDeletedLocallyOrRemotely else {
            return false
        }
        if let expiresAt, expiresAt <= referenceDate {
            return false
        }
        return true
    }
}

/// Deterministic safety audit report for `G-W04` NPC AI scene guard and `I08` NPC chat deletion.
public struct NPCChatAndSceneAISafetyAuditReport: Equatable, Sendable {
    public enum Violation: Equatable, Sendable {
        case emptyIsolationKey
        case streamingDisplayEnabled
        case unapprovedRemoteChatDeleteEnabled
        case sensitiveDataClassesNotRejected([NPCSafetyAuditedDataClass])
        case forbiddenAuthorityEffectsNotDropped([NPCSafetyAuditedAuthorityEffect])
        case deletionFenceViolated(reappearedMemoryIDs: [String])
    }

    public let isolationKey: String
    public let sceneAIDefaultDisabled: Bool
    public let remoteChatDeleteGateEnabled: Bool
    public let remoteChatDeleteApproved: Bool
    public let isNonGenerativeBadgeActive: Bool
    public let isStreamingOffBadgeActive: Bool
    public let rejectedDataClasses: [NPCSafetyAuditedDataClass]
    public let droppedForbiddenEffects: [NPCSafetyAuditedAuthorityEffect]
    public let acceptedNarrativeEffects: [NPCSafetyAuditedAuthorityEffect]
    public let admissibleRecords: [NPCSafetyMemoryRecordCandidate]
    public let reappearedDeletedMemoryIDs: [String]
    public let violations: [Violation]

    public init(
        isolationKey: String,
        sceneAIDefaultDisabled: Bool,
        remoteChatDeleteGateEnabled: Bool,
        remoteChatDeleteApproved: Bool,
        isNonGenerativeBadgeActive: Bool,
        isStreamingOffBadgeActive: Bool,
        rejectedDataClasses: [NPCSafetyAuditedDataClass],
        droppedForbiddenEffects: [NPCSafetyAuditedAuthorityEffect],
        acceptedNarrativeEffects: [NPCSafetyAuditedAuthorityEffect],
        admissibleRecords: [NPCSafetyMemoryRecordCandidate],
        reappearedDeletedMemoryIDs: [String],
        violations: [Violation]
    ) {
        self.isolationKey = isolationKey
        self.sceneAIDefaultDisabled = sceneAIDefaultDisabled
        self.remoteChatDeleteGateEnabled = remoteChatDeleteGateEnabled
        self.remoteChatDeleteApproved = remoteChatDeleteApproved
        self.isNonGenerativeBadgeActive = isNonGenerativeBadgeActive
        self.isStreamingOffBadgeActive = isStreamingOffBadgeActive
        self.rejectedDataClasses = rejectedDataClasses
        self.droppedForbiddenEffects = droppedForbiddenEffects
        self.acceptedNarrativeEffects = acceptedNarrativeEffects
        self.admissibleRecords = admissibleRecords
        self.reappearedDeletedMemoryIDs = reappearedDeletedMemoryIDs
        self.violations = violations
    }

    public var isSafetyCompliant: Bool {
        violations.isEmpty
    }
}

/// Pure auditor for `G-W04` NPC AI scene guard and `I08` (`AI-DELETE`) NPC chat log deletion safety.
public enum NPCChatAndSceneAISafetyAudit {
    public static let remoteChatDeleteRoute = "/api/npc/chat/delete"

    public static func audit(
        isolationKey: String,
        sceneAIDefaultDisabled: Bool = true,
        allowsStreamingDisplay: Bool = false,
        remoteChatDeleteGateEnabled: Bool = false,
        remoteChatDeleteApproved: Bool = false,
        requestedDataClasses: Set<NPCSafetyAuditedDataClass> = [.approvedStoreFacts],
        proposedEffects: [NPCSafetyAuditedAuthorityEffect] = [],
        memoryCandidates: [NPCSafetyMemoryRecordCandidate] = [],
        deletedMemoryIDFence: Set<String> = [],
        referenceDate: Date = Date(timeIntervalSince1970: 1_750_000_000)
    ) -> NPCChatAndSceneAISafetyAuditReport {
        var violations: [NPCChatAndSceneAISafetyAuditReport.Violation] = []
        let trimmedKey = isolationKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedKey.isEmpty {
            violations.append(.emptyIsolationKey)
        }

        if allowsStreamingDisplay {
            violations.append(.streamingDisplayEnabled)
        }

        if remoteChatDeleteGateEnabled && !remoteChatDeleteApproved {
            violations.append(.unapprovedRemoteChatDeleteEnabled)
        }

        let rejectedData = requestedDataClasses
            .filter(\.isForbiddenForNPCChat)
            .sorted()

        var droppedEffects: [NPCSafetyAuditedAuthorityEffect] = []
        var acceptedEffects: [NPCSafetyAuditedAuthorityEffect] = []
        for effect in proposedEffects {
            if effect.isForbiddenAuthorityMutation {
                droppedEffects.append(effect)
            } else {
                acceptedEffects.append(effect)
            }
        }
        droppedEffects.sort()
        acceptedEffects.sort()

        let reappearedIDs = memoryCandidates
            .map(\.memoryID)
            .filter { deletedMemoryIDFence.contains($0) }
            .sorted()
        if !reappearedIDs.isEmpty {
            violations.append(.deletionFenceViolated(reappearedMemoryIDs: reappearedIDs))
        }

        let admissible: [NPCSafetyMemoryRecordCandidate]
        if reappearedIDs.isEmpty {
            admissible = memoryCandidates.filter {
                !deletedMemoryIDFence.contains($0.memoryID) &&
                    $0.isAdmissible(expectedIsolationKey: trimmedKey, at: referenceDate)
            }
        } else {
            admissible = []
        }

        return NPCChatAndSceneAISafetyAuditReport(
            isolationKey: trimmedKey,
            sceneAIDefaultDisabled: sceneAIDefaultDisabled,
            remoteChatDeleteGateEnabled: remoteChatDeleteGateEnabled,
            remoteChatDeleteApproved: remoteChatDeleteApproved,
            isNonGenerativeBadgeActive: sceneAIDefaultDisabled,
            isStreamingOffBadgeActive: !allowsStreamingDisplay,
            rejectedDataClasses: rejectedData,
            droppedForbiddenEffects: droppedEffects,
            acceptedNarrativeEffects: acceptedEffects,
            admissibleRecords: admissible,
            reappearedDeletedMemoryIDs: reappearedIDs,
            violations: violations
        )
    }
}
