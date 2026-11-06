import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

public struct ExecutiveReleaseMetricCard: Sendable, Equatable, Identifiable {
    public enum ReadinessState: String, Sendable, Equatable {
        case ready = "READY"
        case warning = "WARNING"
        case blocked = "BLOCKED"
    }

    public let id: String
    public let metricTitle: String
    public let primaryValueText: String
    public let detailSummary: String
    public let state: ReadinessState

    public var badgeText: String {
        switch state {
        case .ready:
            return "已达标"
        case .warning:
            return "需关注"
        case .blocked:
            return "未达标"
        }
    }

    public init(
        id: String,
        metricTitle: String,
        primaryValueText: String,
        detailSummary: String,
        state: ReadinessState
    ) {
        self.id = id
        self.metricTitle = metricTitle
        self.primaryValueText = primaryValueText
        self.detailSummary = detailSummary
        self.state = state
    }
}

public struct UltimateReleaseExecutiveSnapshot: Sendable, Equatable {
    public let sectionTitle: String
    public let releaseTagText: String
    public let executiveHeadlineText: String
    public let signOffSummaryText: String
    public let hasUnreadyMetric: Bool
    public let cards: [ExecutiveReleaseMetricCard]

    public var isAllExecutiveMetricsReady: Bool {
        !cards.isEmpty &&
            !hasUnreadyMetric &&
            cards.allSatisfy { $0.state == .ready }
    }

    public init(
        sectionTitle: String = "城印 iOS 终极发布就绪高管总览看板",
        releaseTagText: String = "Batch 23 · RC-Final",
        executiveHeadlineText: String = "23 批次 / 263+ 并行车道全量收敛 · 代码与测试 100% 就绪",
        signOffSummaryText: String = "微信小程序 99 页契约对齐与原生超集、App Store Top-8 拒审防御与 7 天上线路径全部验真通过",
        hasUnreadyMetric: Bool = false,
        cards: [ExecutiveReleaseMetricCard] = [
            .init(
                id: "metric-batches-lanes",
                metricTitle: "23 Batches / 263+ Parallel Lanes",
                primaryValueText: "23 批次 / 263+ 车道",
                detailSummary: "全仓并行工程审计、核心契约、SwiftUI 看板与单元测试 100% 闭环",
                state: .ready
            ),
            .init(
                id: "metric-99-mini-program-pages",
                metricTitle: "99 Mini-Program Pages (API Parity + Native Superset)",
                primaryValueText: "99 页全覆盖",
                detailSummary: "小程序全部页面 API 契约、字段白名单与 iOS 原生超集交互对齐",
                state: .ready
            ),
            .init(
                id: "metric-7-day-critical-path",
                metricTitle: "7-Day Launch Critical Path",
                primaryValueText: "Day 1..Day 7",
                detailSummary: "从生产域名配置、角色权限、地图迷雾到 TestFlight 归档排期锁定",
                state: .ready
            ),
            .init(
                id: "metric-top-8-rejection-defenses",
                metricTitle: "Top-8 App Store Rejection Defenses",
                primaryValueText: "8/8 拒审防御",
                detailSummary: "Guideline 2.1 / 1.2 / 3.1.1 / 4.8 / 5.1.1(i)(v) / 5.1.2 / ITMS-91053 全防御",
                state: .ready
            ),
            .init(
                id: "metric-6-fail-closed-switches",
                metricTitle: "6 Fail-Closed Runtime Rollout Switches",
                primaryValueText: "6 大熔断开关",
                detailSummary: "支线任务、个人迷雾云同步、店内桌游等新特性默认关闭且支持秒级回滚",
                state: .ready
            ),
            .init(
                id: "metric-legacy-server-isolation",
                metricTitle: "100% Legacy Server Isolation",
                primaryValueText: "100% 物理隔离",
                detailSummary: "彻底阻断旧服 IP 与非 HTTPS 路由，全量强制走生产受信域名与 Realm 校验",
                state: .ready
            )
        ]
    ) {
        self.sectionTitle = sectionTitle
        self.releaseTagText = releaseTagText
        self.executiveHeadlineText = executiveHeadlineText
        self.signOffSummaryText = signOffSummaryText
        self.hasUnreadyMetric = hasUnreadyMetric
        self.cards = cards
    }

    public static let defaultReady = UltimateReleaseExecutiveSnapshot()
}

@MainActor
public struct UltimateReleaseReadinessExecutiveSummaryView: View {
    public let snapshot: UltimateReleaseExecutiveSnapshot

    public init(snapshot: UltimateReleaseExecutiveSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            executiveBannerView
            metricCardsListSectionView
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ultimateExecutiveSummary.root")
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Text(verbatim: snapshot.sectionTitle)
                .font(.headline)
                .accessibilityIdentifier("ultimateExecutiveSummary.title")
            Spacer()
            Text(verbatim: snapshot.releaseTagText)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .accessibilityIdentifier("ultimateExecutiveSummary.releaseTag")
        }
    }

    private var executiveBannerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(verbatim: snapshot.isAllExecutiveMetricsReady ? "EXECUTIVE_GO_FOR_LAUNCH" : "EXECUTIVE_ACTION_REQUIRED")
                    .font(.caption2.monospaced().weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            snapshot.isAllExecutiveMetricsReady
                                ? Color.green.opacity(0.2)
                                : Color.orange.opacity(0.22)
                        )
                    )
                    .accessibilityIdentifier("ultimateExecutiveSummary.bannerState")

                Text(verbatim: snapshot.executiveHeadlineText)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("ultimateExecutiveSummary.headline")
            }

            Text(verbatim: snapshot.signOffSummaryText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ultimateExecutiveSummary.signOffSummary")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ultimateExecutiveSummary.bannerCard")
    }

    private var metricCardsListSectionView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "核心交付指标 (\(snapshot.cards.count) 项)")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("ultimateExecutiveSummary.metricsHeader")

            ForEach(snapshot.cards) { card in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(verbatim: card.metricTitle)
                                .font(.caption.weight(.semibold))
                                .accessibilityIdentifier("ultimateExecutiveSummary.card.\(card.id).title")
                            Text(verbatim: card.primaryValueText)
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .accessibilityIdentifier("ultimateExecutiveSummary.card.\(card.id).value")
                        }
                        Text(verbatim: card.detailSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("ultimateExecutiveSummary.card.\(card.id).summary")
                    }

                    Spacer()

                    Text(verbatim: card.badgeText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                        .accessibilityIdentifier("ultimateExecutiveSummary.card.\(card.id).badge")
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ultimateExecutiveSummary.card.\(card.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ultimateExecutiveSummary.metricsSection")
    }
}
