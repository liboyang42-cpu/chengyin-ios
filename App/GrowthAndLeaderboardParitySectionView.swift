import SwiftUI
import QuestifyCore

public struct GrowthLeaderboardAuditRow: Identifiable, Equatable, Sendable {
    public static let anonymousMonogramFallback = "匿"

    public let id: String
    public let rank: Int
    public let memberID: Int
    public let nickname: String
    public let avatarURL: String?
    public let scoreText: String
    public let badgeTitle: String?
    public let isAnonymous: Bool

    public var resolvedAvatarMonogram: String {
        let trimmedAvatar = (avatarURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAvatar.isEmpty && !isAnonymous {
            let trimmedName = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = trimmedName.first {
                return String(first)
            }
        }
        if isAnonymous {
            return Self.anonymousMonogramFallback
        }
        let trimmedName = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != "匿名用户", trimmedName.lowercased() != "anonymous" else {
            return Self.anonymousMonogramFallback
        }
        guard !trimmedAvatar.isEmpty, let first = trimmedName.first else {
            return Self.anonymousMonogramFallback
        }
        return String(first)
    }

    public var usesRemoteAvatar: Bool {
        let trimmedAvatar = (avatarURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !isAnonymous && trimmedAvatar.lowercased().hasPrefix("https://")
    }

    public init(
        id: String,
        rank: Int,
        memberID: Int,
        nickname: String,
        avatarURL: String? = nil,
        scoreText: String,
        badgeTitle: String? = nil,
        isAnonymous: Bool = false
    ) {
        self.id = id
        self.rank = rank
        self.memberID = memberID
        self.nickname = nickname
        self.avatarURL = avatarURL
        self.scoreText = scoreText
        self.badgeTitle = badgeTitle
        self.isAnonymous = isAnonymous
    }
}

public struct GrowthAndLeaderboardParitySnapshot: Equatable, Sendable {
    public enum AuthSeparationState: String, Equatable, Sendable {
        case authorized = "200_OK"
        case forbiddenScopeRestricted403 = "403_FORBIDDEN_PRESERVE_SESSION"
        case unauthorizedReauthRequired401 = "401_UNAUTHORIZED_CLEAR_SESSION"
    }

    public struct BadgeParityItem: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let tierText: String
        public let isUnlocked: Bool
        public let progressText: String

        public init(
            id: String,
            title: String,
            tierText: String,
            isUnlocked: Bool,
            progressText: String
        ) {
            self.id = id
            self.title = title
            self.tierText = tierText
            self.isUnlocked = isUnlocked
            self.progressText = progressText
        }
    }

    public static let canonicalFormContentType = "application/x-www-form-urlencoded"

    public let sectionTitle: String
    public let badgeParitySpecID: String
    public let leaderboardSpecID: String
    public let formEncodedContentType: String
    public let formEncodedBodyPreview: String
    public let authSeparationState: AuthSeparationState
    public let preservesSessionOn403: Bool
    public let badges: [BadgeParityItem]
    public let rows: [GrowthLeaderboardAuditRow]

    public var isFormEncodingCompliant: Bool {
        formEncodedContentType == Self.canonicalFormContentType &&
        formEncodedBodyPreview.contains("type=") &&
        formEncodedBodyPreview.contains("timeRange=") &&
        !formEncodedBodyPreview.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
    }

    public var statusBannerText: String {
        switch authSeparationState {
        case .authorized:
            return "状态 200 · 成长勋章与排行榜数据已同步"
        case .forbiddenScopeRestricted403:
            return "状态 403 · 当前圈子/赛区权限受限（保持登录态，不清空 Token）"
        case .unauthorizedReauthRequired401:
            return "状态 401 · 登录凭证已失效（需重新认证）"
        }
    }

    public init(
        sectionTitle: String = "成长勋章与排行榜契约看板 (w2-10 / I07)",
        badgeParitySpecID: String = "w2-10",
        leaderboardSpecID: String = "I07",
        formEncodedContentType: String = Self.canonicalFormContentType,
        formEncodedBodyPreview: String = "type=CITY_SCORE&timeRange=WEEKLY&cityCode=330100&page=1&size=20",
        authSeparationState: AuthSeparationState = .authorized,
        preservesSessionOn403: Bool = true,
        badges: [BadgeParityItem] = [
            .init(
                id: "badge-pioneer",
                title: "城市拓荒者",
                tierText: "SSR · Lv.3",
                isUnlocked: true,
                progressText: "12/12"
            ),
            .init(
                id: "badge-night-owl",
                title: "夜行守望者",
                tierText: "SR · Lv.2",
                isUnlocked: false,
                progressText: "4/10"
            )
        ],
        rows: [GrowthLeaderboardAuditRow] = [
            .init(
                id: "rank-1",
                rank: 1,
                memberID: 1001,
                nickname: "林深见鹿",
                avatarURL: "https://cdn.questify.com/avatars/1001.png",
                scoreText: "2,480 pt",
                badgeTitle: "城市拓荒者",
                isAnonymous: false
            ),
            .init(
                id: "rank-2",
                rank: 2,
                memberID: 1002,
                nickname: "匿名探索者",
                avatarURL: nil,
                scoreText: "2,150 pt",
                badgeTitle: nil,
                isAnonymous: true
            )
        ]
    ) {
        self.sectionTitle = sectionTitle
        self.badgeParitySpecID = badgeParitySpecID
        self.leaderboardSpecID = leaderboardSpecID
        self.formEncodedContentType = formEncodedContentType
        self.formEncodedBodyPreview = formEncodedBodyPreview
        self.authSeparationState = authSeparationState
        self.preservesSessionOn403 = preservesSessionOn403
        self.badges = badges
        self.rows = rows
    }
}

public struct GrowthAndLeaderboardParitySectionView: View {
    public let snapshot: GrowthAndLeaderboardParitySnapshot

    public init(snapshot: GrowthAndLeaderboardParitySnapshot = GrowthAndLeaderboardParitySnapshot()) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            formEncodingAuditView
            authSeparationBannerView
            badgeParityStripView
            leaderboardListView
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("growthLeaderboardAudit.root")
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Text(verbatim: snapshot.sectionTitle)
                .font(.headline)
                .accessibilityIdentifier("growthLeaderboardAudit.title")
            Spacer()
            Text(verbatim: "\(snapshot.badgeParitySpecID) · \(snapshot.leaderboardSpecID)")
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .accessibilityIdentifier("growthLeaderboardAudit.specBadge")
        }
    }

    private var formEncodingAuditView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: "I07 Form-Encoded 请求体")
                    .font(.caption.weight(.semibold))
                Text(verbatim: snapshot.formEncodedContentType)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("growthLeaderboardAudit.contentType")
            }
            Text(verbatim: snapshot.formEncodedBodyPreview)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("growthLeaderboardAudit.formBodyPreview")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityIdentifier("growthLeaderboardAudit.formEncodingCard")
    }

    private var authSeparationBannerView: some View {
        HStack(spacing: 8) {
            Text(verbatim: snapshot.authSeparationState.rawValue)
                .font(.caption2.monospaced().weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.2)))
                .accessibilityIdentifier("growthLeaderboardAudit.authStateCode")

            Text(verbatim: snapshot.statusBannerText)
                .font(.caption)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("growthLeaderboardAudit.authStatusBanner")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("growthLeaderboardAudit.authSeparationSection")
    }

    private var badgeParityStripView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "w2-10 成长勋章对齐 (\(snapshot.badges.count))")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("growthLeaderboardAudit.badgeSectionHeader")

            ForEach(snapshot.badges) { badge in
                HStack(spacing: 8) {
                    Text(verbatim: badge.isUnlocked ? "已解锁" : "未解锁")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(badge.isUnlocked ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                        )
                    Text(verbatim: badge.title)
                        .font(.caption.weight(.medium))
                    Text(verbatim: badge.tierText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: badge.progressText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("growthLeaderboardAudit.badge.\(badge.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("growthLeaderboardAudit.badgeStrip")
    }

    private var leaderboardListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "排行榜单 (\(snapshot.rows.count))")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("growthLeaderboardAudit.leaderboardHeader")

            ForEach(snapshot.rows) { row in
                HStack(spacing: 10) {
                    Text(verbatim: "#\(row.rank)")
                        .font(.caption.monospaced().weight(.bold))
                        .frame(width: 28, alignment: .leading)
                        .accessibilityIdentifier("growthLeaderboardAudit.row.\(row.id).rank")

                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.18))
                            .frame(width: 28, height: 28)
                        Text(verbatim: row.resolvedAvatarMonogram)
                            .font(.caption.weight(.bold))
                            .accessibilityIdentifier("growthLeaderboardAudit.row.\(row.id).monogram")
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.nickname)
                            .font(.caption.weight(.medium))
                            .accessibilityIdentifier("growthLeaderboardAudit.row.\(row.id).nickname")
                        if let badgeTitle = row.badgeTitle {
                            Text(verbatim: badgeTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("growthLeaderboardAudit.row.\(row.id).badge")
                        }
                    }

                    Spacer()

                    Text(verbatim: row.scoreText)
                        .font(.caption.monospaced().weight(.semibold))
                        .accessibilityIdentifier("growthLeaderboardAudit.row.\(row.id).score")
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("growthLeaderboardAudit.row.\(row.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("growthLeaderboardAudit.leaderboardList")
    }
}
