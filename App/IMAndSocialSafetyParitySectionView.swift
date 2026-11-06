import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row for each of the 4 social, growth, square & IM safety pillars:
/// `w2-03/04` member/social profile, `w2-10/I07` growth & leaderboard,
/// `w2-13/I05` square & topic like, and `w2-20` IM inbox safety.
public struct IMSocialSafetyPillarRow: Identifiable, Equatable, Sendable {
    public enum PillarKind: String, CaseIterable, Equatable, Sendable {
        case w203MemberSocialProfile = "w2-03/04"
        case w210GrowthAndLeaderboard = "w2-10/I07"
        case w213SquareAndTopicLike = "w2-13/I05"
        case w220ImInboxSafety = "w2-20"
    }

    public let id: String
    public let kind: PillarKind
    public let title: String
    public let summary: String
    public let safetyVerificationNote: String
    public let isVerified: Bool

    public init(
        id: String? = nil,
        kind: PillarKind,
        title: String,
        summary: String,
        safetyVerificationNote: String,
        isVerified: Bool
    ) {
        self.id = id ?? kind.rawValue
        self.kind = kind
        self.title = title
        self.summary = summary
        self.safetyVerificationNote = safetyVerificationNote
        self.isVerified = isVerified
    }
}

/// Self-contained snapshot for the 4 social, growth, square & IM safety parity pillars.
public struct IMAndSocialSafetyParitySnapshot: Equatable, Sendable {
    public let memberSocialProfileParityVerified: Bool
    public let growthAndLeaderboardNonCashVerified: Bool
    public let squareModerationAndTopicLikeGateVerified: Bool
    public let imInboxReportBlockAndRevokeVerified: Bool
    public let rows: [IMSocialSafetyPillarRow]

    public init(
        memberSocialProfileParityVerified: Bool,
        growthAndLeaderboardNonCashVerified: Bool,
        squareModerationAndTopicLikeGateVerified: Bool,
        imInboxReportBlockAndRevokeVerified: Bool,
        rows: [IMSocialSafetyPillarRow]
    ) {
        self.memberSocialProfileParityVerified = memberSocialProfileParityVerified
        self.growthAndLeaderboardNonCashVerified = growthAndLeaderboardNonCashVerified
        self.squareModerationAndTopicLikeGateVerified = squareModerationAndTopicLikeGateVerified
        self.imInboxReportBlockAndRevokeVerified = imInboxReportBlockAndRevokeVerified
        self.rows = rows
    }

    public var verifiedRowCount: Int {
        rows.filter(\.isVerified).count
    }

    public var isAllCompliant: Bool {
        memberSocialProfileParityVerified &&
            growthAndLeaderboardNonCashVerified &&
            squareModerationAndTopicLikeGateVerified &&
            imInboxReportBlockAndRevokeVerified &&
            Set(rows.map(\.kind)) == Set(IMSocialSafetyPillarRow.PillarKind.allCases) &&
            rows.allSatisfy(\.isVerified)
    }

    public static let compliantSample = IMAndSocialSafetyParitySnapshot(
        memberSocialProfileParityVerified: true,
        growthAndLeaderboardNonCashVerified: true,
        squareModerationAndTopicLikeGateVerified: true,
        imInboxReportBlockAndRevokeVerified: true,
        rows: [
            IMSocialSafetyPillarRow(
                kind: .w203MemberSocialProfile,
                title: "w2-03/04 会员与社交主页对齐",
                summary: "本人资料编辑、公开主页隐私边界、黑名单与拉黑即时过滤已核验",
                safetyVerificationNote: "跨账号越权编辑已拒绝 · 拉黑立即隐藏互动入口",
                isVerified: true
            ),
            IMSocialSafetyPillarRow(
                kind: .w210GrowthAndLeaderboard,
                title: "w2-10/I07 成长体系与排行榜安全",
                summary: "经验值、徽章、印章与俱乐部榜单仅作荣誉展示，不可提现或兑换现金",
                safetyVerificationNote: "非现金账本围栏已启用 · 榜单排序只读回放",
                isVerified: true
            ),
            IMSocialSafetyPillarRow(
                kind: .w213SquareAndTopicLike,
                title: "w2-13/I05 广场动态与主题点赞围栏",
                summary: "广场举报/屏蔽作者、404/DELETED 媒体缓存即时驱逐与点赞写开关默认关闭已核验",
                safetyVerificationNote: "I05.topicLikeGrantEnabled 默认关闭 · 404 缓存已驱逐",
                isVerified: true
            ),
            IMSocialSafetyPillarRow(
                kind: .w220ImInboxSafety,
                title: "w2-20 站内信与会话安全",
                summary: "会话举报、屏蔽对方、撤回优先准则与未读计数只读对齐已核验",
                safetyVerificationNote: "举报与拉黑入口齐备 · 撤回态不可被旧缓存覆盖",
                isVerified: true
            )
        ]
    )
}

@MainActor
public struct IMAndSocialSafetyParitySectionView: View {
    public let snapshot: IMAndSocialSafetyParitySnapshot

    public init(snapshot: IMAndSocialSafetyParitySnapshot = .compliantSample) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "社交、成长、广场与私信安全对齐审计")
                    .font(.headline)
                    .accessibilityIdentifier("imSocialSafetyAudit.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllCompliant ? .green : .red)
                    .accessibilityIdentifier("imSocialSafetyAudit.overallStatus")

                Text(verbatim: Self.memberProfileStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("imSocialSafetyAudit.memberProfileStatus")

                Text(verbatim: Self.growthStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("imSocialSafetyAudit.growthStatus")

                Text(verbatim: Self.squareStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("imSocialSafetyAudit.squareStatus")

                Text(verbatim: Self.imInboxStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("imSocialSafetyAudit.imInboxStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无社交与私信安全检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("imSocialSafetyAudit.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    IMSocialSafetyPillarRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("imSocialSafetyAudit.section")
    }

    public static func overallStatusText(for snapshot: IMAndSocialSafetyParitySnapshot) -> String {
        snapshot.isAllCompliant
            ? "整体状态：四大社交与私信安全支柱全部达标（\(snapshot.verifiedRowCount)/\(snapshot.rows.count)）"
            : "整体状态：存在未达标的社交或私信安全支柱（\(snapshot.verifiedRowCount)/\(snapshot.rows.count)）"
    }

    public static func memberProfileStatusText(for snapshot: IMAndSocialSafetyParitySnapshot) -> String {
        snapshot.memberSocialProfileParityVerified
            ? "w2-03/04 会员与社交主页：权限与拉黑隔离已核验"
            : "w2-03/04 会员与社交主页：权限或拉黑隔离待核验"
    }

    public static func growthStatusText(for snapshot: IMAndSocialSafetyParitySnapshot) -> String {
        snapshot.growthAndLeaderboardNonCashVerified
            ? "w2-10/I07 成长与排行榜：非现金荣誉约束已核验"
            : "w2-10/I07 成长与排行榜：非现金荣誉约束待核验"
    }

    public static func squareStatusText(for snapshot: IMAndSocialSafetyParitySnapshot) -> String {
        snapshot.squareModerationAndTopicLikeGateVerified
            ? "w2-13/I05 广场与主题点赞：举报/缓存驱逐与写围栏已核验"
            : "w2-13/I05 广场与主题点赞：举报/缓存驱逐或写围栏待核验"
    }

    public static func imInboxStatusText(for snapshot: IMAndSocialSafetyParitySnapshot) -> String {
        snapshot.imInboxReportBlockAndRevokeVerified
            ? "w2-20 站内信与会话安全：举报/屏蔽与撤回准则已核验"
            : "w2-20 站内信与会话安全：举报/屏蔽或撤回准则待核验"
    }
}

@MainActor
private struct IMSocialSafetyPillarRowView: View {
    let row: IMSocialSafetyPillarRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isVerified ? "已核验" : "待修复")
                    .font(.caption)
                    .foregroundStyle(row.isVerified ? .green : .red)
            }

            Text(verbatim: row.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: "安全凭据：\(row.safetyVerificationNote)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("imSocialSafetyAudit.row")
    }
}
