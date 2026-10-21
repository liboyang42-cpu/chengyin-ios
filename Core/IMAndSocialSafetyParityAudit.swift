import Foundation

/// Four social, growth, square & IM messaging parity pillars audited by Batch 10 — Lane 102.
public enum SocialAndIMPillar: String, CaseIterable, Equatable, Sendable {
    case memberHomeAndSocial = "w2-03_w2-04"
    case growthBadgesAndStamps = "w2-10_I07"
    case squarePrivacyAndLikes = "w2-13_I05"
    case imInboxAndSafety = "w2-20"
}

/// Audit snapshot for `w2-03 / w2-04` (`MemberHomeProfileTab`, `balancePreviewText`, `social.incompleteLink`).
public struct MemberHomeSocialPillarAudit: Equatable, Sendable {
    public static let canonicalTabTitles: [String] = ["我的", "推文", "成就", "关于"]
    public static let expectedIncompleteLinkKey: String = "social.incompleteLink"

    public let tabTitles: [String]
    public let balancePreviewText: String
    public let incompleteLinkLocalizationKey: String

    public init(
        tabTitles: [String] = Self.canonicalTabTitles,
        balancePreviewText: String = "—",
        incompleteLinkLocalizationKey: String = Self.expectedIncompleteLinkKey
    ) {
        self.tabTitles = tabTitles
        self.balancePreviewText = balancePreviewText
        self.incompleteLinkLocalizationKey = incompleteLinkLocalizationKey
    }

    public var isCompliant: Bool {
        tabTitles == Self.canonicalTabTitles
            && !balancePreviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && incompleteLinkLocalizationKey == Self.expectedIncompleteLinkKey
    }
}

/// Audit snapshot for `w2-10 / I07` (`GrowthBadgeParity`, form-encoded leaderboard body, `GrowthLeaderboardStanding`, `ProfileReadFailure.isDenied`).
public struct GrowthAndBadgesPillarAudit: Equatable, Sendable {
    public let blankNicknameAvatarMonogram: String
    public let usesFormEncodedLeaderboardRequest: Bool
    public let preservesServerLeaderboardStanding: Bool
    public let distinguishesForbiddenFromUnauthorized: Bool

    public init(
        blankNicknameAvatarMonogram: String = "匿",
        usesFormEncodedLeaderboardRequest: Bool = true,
        preservesServerLeaderboardStanding: Bool = true,
        distinguishesForbiddenFromUnauthorized: Bool = true
    ) {
        self.blankNicknameAvatarMonogram = blankNicknameAvatarMonogram
        self.usesFormEncodedLeaderboardRequest = usesFormEncodedLeaderboardRequest
        self.preservesServerLeaderboardStanding = preservesServerLeaderboardStanding
        self.distinguishesForbiddenFromUnauthorized = distinguishesForbiddenFromUnauthorized
    }

    public var isCompliant: Bool {
        blankNicknameAvatarMonogram == "匿"
            && usesFormEncodedLeaderboardRequest
            && preservesServerLeaderboardStanding
            && distinguishesForbiddenFromUnauthorized
    }
}

/// Audit snapshot for `w2-13 / I05` (`SquareWorkspacePrivacy` 404/DELETED media cache eviction, `TopicLikeDirection`, `TopicLikeHostController.likeGrantEnabled == false`).
public struct SquarePrivacyAndLikePillarAudit: Equatable, Sendable {
    public let evictsMediaCacheOn404AndDeleted: Bool
    public let supportsBidirectionalTopicLike: Bool
    public let defaultLikeGrantEnabled: Bool

    public init(
        evictsMediaCacheOn404AndDeleted: Bool = true,
        supportsBidirectionalTopicLike: Bool = true,
        defaultLikeGrantEnabled: Bool = false
    ) {
        self.evictsMediaCacheOn404AndDeleted = evictsMediaCacheOn404AndDeleted
        self.supportsBidirectionalTopicLike = supportsBidirectionalTopicLike
        self.defaultLikeGrantEnabled = defaultLikeGrantEnabled
    }

    public var isCompliant: Bool {
        evictsMediaCacheOn404AndDeleted
            && supportsBidirectionalTopicLike
            && !defaultLikeGrantEnabled
    }
}

/// Audit snapshot for `w2-20` (`IMInbox` tabs & `IMConversationSafety` report/block/mute gates).
public struct IMInboxAndSafetyPillarAudit: Equatable, Sendable {
    public let inboxTabsConfigured: Bool
    public let supportsReportAction: Bool
    public let supportsBlockAction: Bool
    public let supportsMuteAction: Bool
    public let hidesBlockedSenderMessagesImmediately: Bool

    public init(
        inboxTabsConfigured: Bool = true,
        supportsReportAction: Bool = true,
        supportsBlockAction: Bool = true,
        supportsMuteAction: Bool = true,
        hidesBlockedSenderMessagesImmediately: Bool = true
    ) {
        self.inboxTabsConfigured = inboxTabsConfigured
        self.supportsReportAction = supportsReportAction
        self.supportsBlockAction = supportsBlockAction
        self.supportsMuteAction = supportsMuteAction
        self.hidesBlockedSenderMessagesImmediately = hidesBlockedSenderMessagesImmediately
    }

    public var isCompliant: Bool {
        inboxTabsConfigured
            && supportsReportAction
            && supportsBlockAction
            && supportsMuteAction
            && hidesBlockedSenderMessagesImmediately
    }
}

/// Aggregate evaluation of the 4 social, growth, square & IM messaging parity pillars.
public struct IMAndSocialSafetyParityReport: Equatable, Sendable {
    public let isAllCompliant: Bool
    public let compliantPillars: [SocialAndIMPillar]
    public let failingPillars: [SocialAndIMPillar]

    public init(
        isAllCompliant: Bool,
        compliantPillars: [SocialAndIMPillar],
        failingPillars: [SocialAndIMPillar]
    ) {
        self.isAllCompliant = isAllCompliant
        self.compliantPillars = compliantPillars
        self.failingPillars = failingPillars
    }
}

/// Evaluator for `w2-03 / w2-04`, `w2-10 / I07`, `w2-13 / I05`, and `w2-20`.
public enum IMAndSocialSafetyParityAudit {
    public static func evaluate(
        memberHome: MemberHomeSocialPillarAudit = MemberHomeSocialPillarAudit(),
        growthBadges: GrowthAndBadgesPillarAudit = GrowthAndBadgesPillarAudit(),
        squarePrivacy: SquarePrivacyAndLikePillarAudit = SquarePrivacyAndLikePillarAudit(),
        imSafety: IMInboxAndSafetyPillarAudit = IMInboxAndSafetyPillarAudit()
    ) -> IMAndSocialSafetyParityReport {
        var compliant: [SocialAndIMPillar] = []
        var failing: [SocialAndIMPillar] = []

        func record(_ pillar: SocialAndIMPillar, ok: Bool) {
            if ok {
                compliant.append(pillar)
            } else {
                failing.append(pillar)
            }
        }

        record(.memberHomeAndSocial, ok: memberHome.isCompliant)
        record(.growthBadgesAndStamps, ok: growthBadges.isCompliant)
        record(.squarePrivacyAndLikes, ok: squarePrivacy.isCompliant)
        record(.imInboxAndSafety, ok: imSafety.isCompliant)

        return IMAndSocialSafetyParityReport(
            isAllCompliant: failing.isEmpty && compliant.count == SocialAndIMPillar.allCases.count,
            compliantPillars: compliant,
            failingPillars: failing
        )
    }
}
