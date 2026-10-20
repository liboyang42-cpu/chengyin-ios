import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

public struct PublishModerationCheckRow: Sendable, Equatable, Identifiable {
    public enum CheckStatus: String, Sendable, Equatable {
        case passed = "PASSED"
        case warning = "WARNING"
        case blocked = "BLOCKED"
    }

    public let id: String
    public let domainCode: String
    public let title: String
    public let detail: String
    public let status: CheckStatus

    public var statusBadgeText: String {
        switch status {
        case .passed:
            return "已就绪"
        case .warning:
            return "待人工复核"
        case .blocked:
            return "已拦截"
        }
    }

    public init(
        id: String,
        domainCode: String,
        title: String,
        detail: String,
        status: CheckStatus
    ) {
        self.id = id
        self.domainCode = domainCode
        self.title = title
        self.detail = detail
        self.status = status
    }
}

public struct PublishTopicModerationSnapshot: Sendable, Equatable {
    public static let maxNineGridMediaCount = 9

    public let sectionTitle: String
    public let specBadgeText: String
    public let nineGridMediaCount: Int
    public let topicDetailEndpoint: String
    public let commentListEndpoint: String
    public let ugcReportEndpoint: String
    public let ugcBlockUserEndpoint: String
    public let guideline12TermsAccepted: Bool
    public let hasActiveUgcViolationBanner: Bool
    public let ugcViolationBannerText: String
    public let checks: [PublishModerationCheckRow]

    public var isNineGridWithinLimit: Bool {
        (0...Self.maxNineGridMediaCount).contains(nineGridMediaCount)
    }

    public var isAppStoreGuideline12Compliant: Bool {
        guideline12TermsAccepted &&
            !ugcReportEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !ugcBlockUserEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !hasActiveUgcViolationBanner &&
            checks.allSatisfy { $0.status != .blocked }
    }

    public init(
        sectionTitle: String = "主题发布九宫格与评论审核治理看板 (w2-13 / Guideline 1.2)",
        specBadgeText: String = "w2-13 · UGC 1.2",
        nineGridMediaCount: Int = 9,
        topicDetailEndpoint: String = "api/topic/detail",
        commentListEndpoint: String = "api/comment/list",
        ugcReportEndpoint: String = "api/ugc/report",
        ugcBlockUserEndpoint: String = "api/ugc/block",
        guideline12TermsAccepted: Bool = true,
        hasActiveUgcViolationBanner: Bool = false,
        ugcViolationBannerText: String = "UGC 审核通过 · 已启用 EULA 同意、一键举报、拉黑屏蔽与 24h 处置闭环",
        checks: [PublishModerationCheckRow] = [
            .init(
                id: "w2-13-nine-grid",
                domainCode: "w2-13",
                title: "九宫格图文/视频发布器",
                detail: "最多 9 张配图或视频封面校验，支持拖拽排序与 OSS 预签名直传",
                status: .passed
            ),
            .init(
                id: "topic-detail-parity",
                domainCode: "TOPIC_DETAIL",
                title: "主题详情与章节流透传",
                detail: "api/topic/detail 完整承载富文本、坐标点位与章节结局布尔 fallback",
                status: .passed
            ),
            .init(
                id: "comment-thread-moderation",
                domainCode: "COMMENT_MOD",
                title: "评论盖楼与敏感词先审后发",
                detail: "主评/子评折叠展示，违规内容自动进入待审隔离区",
                status: .passed
            ),
            .init(
                id: "guideline-1-2-ugc",
                domainCode: "GUIDELINE_1_2",
                title: "App Store 1.2 UGC 举报与拉黑闭环",
                detail: "提供用户协议拦截、评论/主题举报、作者拉黑后本地立即隐藏其全部内容",
                status: .passed
            )
        ]
    ) {
        self.sectionTitle = sectionTitle
        self.specBadgeText = specBadgeText
        self.nineGridMediaCount = nineGridMediaCount
        self.topicDetailEndpoint = topicDetailEndpoint
        self.commentListEndpoint = commentListEndpoint
        self.ugcReportEndpoint = ugcReportEndpoint
        self.ugcBlockUserEndpoint = ugcBlockUserEndpoint
        self.guideline12TermsAccepted = guideline12TermsAccepted
        self.hasActiveUgcViolationBanner = hasActiveUgcViolationBanner
        self.ugcViolationBannerText = ugcViolationBannerText
        self.checks = checks
    }

    public static let defaultReady = PublishTopicModerationSnapshot()
}

@MainActor
public struct PublishTopicAndCommentModerationSectionView: View {
    public let snapshot: PublishTopicModerationSnapshot

    public init(snapshot: PublishTopicModerationSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            nineGridAndEndpointsCardView
            ugcGuidelineBannerView
            moderationChecklistSectionView
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publishTopicModeration.root")
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Text(verbatim: snapshot.sectionTitle)
                .font(.headline)
                .accessibilityIdentifier("publishTopicModeration.title")
            Spacer()
            Text(verbatim: snapshot.specBadgeText)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .accessibilityIdentifier("publishTopicModeration.specBadge")
        }
    }

    private var nineGridAndEndpointsCardView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: "九宫格媒体槽位：\(snapshot.nineGridMediaCount)/\(PublishTopicModerationSnapshot.maxNineGridMediaCount)")
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("publishTopicModeration.nineGridCount")
                Spacer()
                Text(verbatim: snapshot.isNineGridWithinLimit ? "容量合规" : "超出上限")
                    .font(.caption2.weight(.semibold))
                    .accessibilityIdentifier("publishTopicModeration.nineGridStatus")
            }

            HStack(spacing: 8) {
                Text(verbatim: snapshot.topicDetailEndpoint)
                    .font(.caption2.monospaced())
                    .accessibilityIdentifier("publishTopicModeration.topicDetailEndpoint")
                Text(verbatim: snapshot.commentListEndpoint)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("publishTopicModeration.commentListEndpoint")
            }

            HStack(spacing: 8) {
                Text(verbatim: snapshot.ugcReportEndpoint)
                    .font(.caption2.monospaced())
                    .accessibilityIdentifier("publishTopicModeration.ugcReportEndpoint")
                Text(verbatim: snapshot.ugcBlockUserEndpoint)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("publishTopicModeration.ugcBlockEndpoint")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publishTopicModeration.endpointsCard")
    }

    private var ugcGuidelineBannerView: some View {
        HStack(spacing: 8) {
            Text(verbatim: snapshot.hasActiveUgcViolationBanner ? "UGC_VIOLATION_BLOCKED" : "UGC_1_2_READY")
                .font(.caption2.monospaced().weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(
                        snapshot.hasActiveUgcViolationBanner
                            ? Color.red.opacity(0.22)
                            : Color.green.opacity(0.2)
                    )
                )
                .accessibilityIdentifier("publishTopicModeration.ugcBannerState")

            Text(verbatim: snapshot.ugcViolationBannerText)
                .font(.caption)
                .accessibilityIdentifier("publishTopicModeration.ugcBannerText")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publishTopicModeration.ugcBanner")
    }

    private var moderationChecklistSectionView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "发布与评论治理检查项 (\(snapshot.checks.count))")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("publishTopicModeration.checklistHeader")

            ForEach(snapshot.checks) { row in
                HStack(alignment: .top, spacing: 8) {
                    Text(verbatim: row.domainCode)
                        .font(.caption2.monospaced().weight(.bold))
                        .frame(width: 86, alignment: .leading)
                        .accessibilityIdentifier("publishTopicModeration.row.\(row.id).domain")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title)
                            .font(.caption.weight(.semibold))
                            .accessibilityIdentifier("publishTopicModeration.row.\(row.id).title")
                        Text(verbatim: row.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("publishTopicModeration.row.\(row.id).detail")
                    }

                    Spacer()

                    Text(verbatim: row.statusBadgeText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                        .accessibilityIdentifier("publishTopicModeration.row.\(row.id).status")
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("publishTopicModeration.row.\(row.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publishTopicModeration.checklistSection")
    }
}
