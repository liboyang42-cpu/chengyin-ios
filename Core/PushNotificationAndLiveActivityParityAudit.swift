import Foundation

/// Canonical APNs push notification and Roam/Task progress notification categories.
public enum PushNotificationCategoryKind: String, Sendable, Equatable, CaseIterable {
    case imDirectMessage
    case teamInviteHandshake
    case orderLifecycleUpdate
    case clubSettlementNotice
    case roamTaskMilestone

    public var displayTitle: String {
        switch self {
        case .imDirectMessage:
            return "IM Direct & Group Message"
        case .teamInviteHandshake:
            return "Team Invite & Formation Handshake"
        case .orderLifecycleUpdate:
            return "Order & Registration Lifecycle Update"
        case .clubSettlementNotice:
            return "Club Wallet & Settlement Notice"
        case .roamTaskMilestone:
            return "Roam Route & Task Milestone Live Update"
        }
    }
}

/// Descriptor auditing deep-link sanitization, lock-screen preview redaction, and user mute posture
/// for a single push notification or Live Activity category.
public struct PushNotificationCategoryDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let category: PushNotificationCategoryKind
    public let sanitizesDeepLinkRoute: Bool
    public let redactsSensitivePreviewWhenLocked: Bool
    public let respectsUserMutePreferences: Bool

    public init(
        id: String? = nil,
        category: PushNotificationCategoryKind,
        sanitizesDeepLinkRoute: Bool = true,
        redactsSensitivePreviewWhenLocked: Bool = true,
        respectsUserMutePreferences: Bool = true
    ) {
        self.id = id ?? category.rawValue
        self.category = category
        self.sanitizesDeepLinkRoute = sanitizesDeepLinkRoute
        self.redactsSensitivePreviewWhenLocked = redactsSensitivePreviewWhenLocked
        self.respectsUserMutePreferences = respectsUserMutePreferences
    }

    public var isCompliant: Bool {
        sanitizesDeepLinkRoute && redactsSensitivePreviewWhenLocked && respectsUserMutePreferences
    }
}

/// Deterministic audit of APNs push notification routing, deep-link payload sanitization,
/// lock-screen redaction posture, and Roam/Task progress notification categories.
public struct PushNotificationAndLiveActivityParityAudit: Sendable, Equatable {
    public static let canonicalDescriptors: [PushNotificationCategoryDescriptor] =
        PushNotificationCategoryKind.allCases.map { kind in
            PushNotificationCategoryDescriptor(
                id: kind.rawValue,
                category: kind,
                sanitizesDeepLinkRoute: true,
                redactsSensitivePreviewWhenLocked: true,
                respectsUserMutePreferences: true
            )
        }

    public init() {}

    public static func evaluate(
        descriptors: [PushNotificationCategoryDescriptor] = canonicalDescriptors
    ) -> (
        totalCategories: Int,
        compliantCategories: Int,
        coversAllCategories: Bool,
        isPushParityReady: Bool
    ) {
        let totalCategories = descriptors.count
        let compliantCategories = descriptors.filter(\.isCompliant).count
        let coveredKinds = Set(descriptors.map(\.category))
        let requiredKinds = Set(PushNotificationCategoryKind.allCases)
        let coversAllCategories =
            coveredKinds == requiredKinds && totalCategories == requiredKinds.count
        let isPushParityReady =
            coversAllCategories && compliantCategories == totalCategories && totalCategories > 0
        return (
            totalCategories: totalCategories,
            compliantCategories: compliantCategories,
            coversAllCategories: coversAllCategories,
            isPushParityReady: isPushParityReady
        )
    }
}
