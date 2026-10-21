import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

public struct MerchantParityStepRow: Identifiable, Equatable, Sendable {
    public enum StepState: String, Equatable, Sendable {
        case completed = "COMPLETED"
        case active = "ACTIVE"
        case pending = "PENDING"
    }

    public let id: String
    public let stepIndex: Int
    public let stepCode: String
    public let title: String
    public let summary: String
    public let state: StepState

    public var statusBadgeText: String {
        switch state {
        case .completed:
            return "已完成"
        case .active:
            return "进行中"
        case .pending:
            return "待填写"
        }
    }

    public init(
        id: String,
        stepIndex: Int,
        stepCode: String,
        title: String,
        summary: String,
        state: StepState
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.stepCode = stepCode
        self.title = title
        self.summary = summary
        self.state = state
    }
}

public struct MerchantDecorAndShopApplySnapshot: Equatable, Sendable {
    public static let canonicalPoiDetailEndpoint = "api/merchant/poi/detail"
    public static let canonicalDecorSaveEndpoint = "api/merchant/decor/save"
    public static let canonicalShopApplyEndpoint = "api/merchant/shop/apply"
    public static let canonicalNpcVoiceStatusEndpoint = "api/merchant/npc/voice/status"
    public static let canonicalMerchantInsightEndpoint = "api/merchant/insight"

    public static let requiredInsightTopLevelKeys: [String] = [
        "exposureCount",
        "checkInCount",
        "conversionRate",
        "repeatVisitRate",
        "couponRedemptionCount"
    ]

    public let sectionTitle: String
    public let paritySpecIDsText: String
    public let poiDetailEndpoint: String
    public let poiSummaryText: String
    public let decorSaveEndpoint: String
    public let decorSaveContentType: String
    public let decorSaveJsonPreview: String
    public let shopApplyEndpoint: String
    public let wizardSteps: [MerchantParityStepRow]
    public let npcVoiceStatusEndpoint: String
    public let npcVoiceSynthesisStateText: String
    public let merchantInsightEndpoint: String
    public let insightTopLevelKeys: [String]
    public let insightMetricsSummaryText: String

    public var isDecorJsonCompliant: Bool {
        let trimmed = decorSaveJsonPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        return decorSaveEndpoint == Self.canonicalDecorSaveEndpoint &&
            decorSaveContentType == "application/json" &&
            trimmed.hasPrefix("{") &&
            trimmed.contains("\"merchantId\"") &&
            trimmed.contains("\"decorConfig\"")
    }

    public var isFourStepWizardComplete: Bool {
        wizardSteps.count == 4 && wizardSteps.map(\.stepIndex) == [1, 2, 3, 4]
    }

    public var hasAllCanonicalInsightKeys: Bool {
        Set(Self.requiredInsightTopLevelKeys).isSubset(of: Set(insightTopLevelKeys))
    }

    public var isFullyCompliant: Bool {
        poiDetailEndpoint == Self.canonicalPoiDetailEndpoint &&
            isDecorJsonCompliant &&
            shopApplyEndpoint == Self.canonicalShopApplyEndpoint &&
            isFourStepWizardComplete &&
            npcVoiceStatusEndpoint == Self.canonicalNpcVoiceStatusEndpoint &&
            merchantInsightEndpoint == Self.canonicalMerchantInsightEndpoint &&
            hasAllCanonicalInsightKeys
    }

    public init(
        sectionTitle: String = "商户门店装修与入驻四步向导 (w2-17..19)",
        paritySpecIDsText: String = "w2-17 · w2-18 · w2-19",
        poiDetailEndpoint: String = Self.canonicalPoiDetailEndpoint,
        poiSummaryText: String = "POI 详情：杭州湖滨银泰旗舰店 (#POI-330102)",
        decorSaveEndpoint: String = Self.canonicalDecorSaveEndpoint,
        decorSaveContentType: String = "application/json",
        decorSaveJsonPreview: String = "{\"merchantId\":8801,\"decorConfig\":{\"bannerTheme\":\"CYBER_NIGHT\",\"lightingMode\":\"NEON\"},\"themeVersion\":3}",
        shopApplyEndpoint: String = Self.canonicalShopApplyEndpoint,
        wizardSteps: [MerchantParityStepRow] = [
            .init(
                id: "step-1",
                stepIndex: 1,
                stepCode: "BASIC_INFO",
                title: "基础门店信息",
                summary: "门店名称、营业时段、GCJ-02 坐标点位校验",
                state: .completed
            ),
            .init(
                id: "step-2",
                stepIndex: 2,
                stepCode: "QUALIFICATION_LICENSE",
                title: "营业执照与资质核验",
                summary: "主体信用代码、安全经营承诺书上传",
                state: .completed
            ),
            .init(
                id: "step-3",
                stepIndex: 3,
                stepCode: "STOREFRONT_MEDIA",
                title: "门头实景与装修配置",
                summary: "门头封面、店内空间动线与 NPC 站位图",
                state: .active
            ),
            .init(
                id: "step-4",
                stepIndex: 4,
                stepCode: "SETTLEMENT_AGREEMENT",
                title: "结算账户与入驻协议确认",
                summary: "分账路由、核销券码结算周期签约",
                state: .pending
            )
        ],
        npcVoiceStatusEndpoint: String = Self.canonicalNpcVoiceStatusEndpoint,
        npcVoiceSynthesisStateText: String = "NPC 语音状态：READY · 掌柜迎宾音色 v2 已就绪",
        merchantInsightEndpoint: String = Self.canonicalMerchantInsightEndpoint,
        insightTopLevelKeys: [String] = Self.requiredInsightTopLevelKeys,
        insightMetricsSummaryText: String = "曝光 12,480 · 到店打卡 1,860 · 转化率 14.9% · 复访率 31.2% · 核销 942"
    ) {
        self.sectionTitle = sectionTitle
        self.paritySpecIDsText = paritySpecIDsText
        self.poiDetailEndpoint = poiDetailEndpoint
        self.poiSummaryText = poiSummaryText
        self.decorSaveEndpoint = decorSaveEndpoint
        self.decorSaveContentType = decorSaveContentType
        self.decorSaveJsonPreview = decorSaveJsonPreview
        self.shopApplyEndpoint = shopApplyEndpoint
        self.wizardSteps = wizardSteps
        self.npcVoiceStatusEndpoint = npcVoiceStatusEndpoint
        self.npcVoiceSynthesisStateText = npcVoiceSynthesisStateText
        self.merchantInsightEndpoint = merchantInsightEndpoint
        self.insightTopLevelKeys = insightTopLevelKeys
        self.insightMetricsSummaryText = insightMetricsSummaryText
    }
}

public struct MerchantDecorAndShopApplyWizardSectionView: View {
    public let snapshot: MerchantDecorAndShopApplySnapshot

    public init(snapshot: MerchantDecorAndShopApplySnapshot = MerchantDecorAndShopApplySnapshot()) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            poiAndDecorJsonCardView
            shopApplyWizardSectionView
            npcVoiceAndInsightCardView
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("merchantDecorWizard.root")
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Text(verbatim: snapshot.sectionTitle)
                .font(.headline)
                .accessibilityIdentifier("merchantDecorWizard.title")
            Spacer()
            Text(verbatim: snapshot.paritySpecIDsText)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .accessibilityIdentifier("merchantDecorWizard.specBadge")
        }
    }

    private var poiAndDecorJsonCardView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: snapshot.poiDetailEndpoint)
                    .font(.caption2.monospaced().weight(.semibold))
                    .accessibilityIdentifier("merchantDecorWizard.poiEndpoint")
                Spacer()
                Text(verbatim: snapshot.isDecorJsonCompliant ? "JSON 契约通过" : "JSON 契约异常")
                    .font(.caption2.weight(.semibold))
                    .accessibilityIdentifier("merchantDecorWizard.decorComplianceBadge")
            }

            Text(verbatim: snapshot.poiSummaryText)
                .font(.caption)
                .accessibilityIdentifier("merchantDecorWizard.poiSummary")

            HStack(spacing: 6) {
                Text(verbatim: snapshot.decorSaveEndpoint)
                    .font(.caption2.monospaced())
                    .accessibilityIdentifier("merchantDecorWizard.decorSaveEndpoint")
                Text(verbatim: snapshot.decorSaveContentType)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchantDecorWizard.decorContentType")
            }

            Text(verbatim: snapshot.decorSaveJsonPreview)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("merchantDecorWizard.decorJsonPreview")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("merchantDecorWizard.poiAndDecorCard")
    }

    private var shopApplyWizardSectionView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: "入驻四步向导 (\(snapshot.wizardSteps.count) 步)")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("merchantDecorWizard.wizardHeader")
                Spacer()
                Text(verbatim: snapshot.shopApplyEndpoint)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchantDecorWizard.shopApplyEndpoint")
            }

            ForEach(snapshot.wizardSteps) { step in
                HStack(alignment: .top, spacing: 8) {
                    Text(verbatim: "S\(step.stepIndex)")
                        .font(.caption.monospaced().weight(.bold))
                        .frame(width: 24, alignment: .leading)
                        .accessibilityIdentifier("merchantDecorWizard.step.\(step.id).index")

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(verbatim: step.title)
                                .font(.caption.weight(.semibold))
                                .accessibilityIdentifier("merchantDecorWizard.step.\(step.id).title")
                            Text(verbatim: step.stepCode)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("merchantDecorWizard.step.\(step.id).code")
                        }
                        Text(verbatim: step.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("merchantDecorWizard.step.\(step.id).summary")
                    }

                    Spacer()

                    Text(verbatim: step.statusBadgeText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                        .accessibilityIdentifier("merchantDecorWizard.step.\(step.id).status")
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("merchantDecorWizard.step.\(step.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("merchantDecorWizard.wizardSection")
    }

    private var npcVoiceAndInsightCardView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: snapshot.npcVoiceStatusEndpoint)
                    .font(.caption2.monospaced())
                    .accessibilityIdentifier("merchantDecorWizard.npcVoiceEndpoint")
                Spacer()
                Text(verbatim: snapshot.npcVoiceSynthesisStateText)
                    .font(.caption2)
                    .accessibilityIdentifier("merchantDecorWizard.npcVoiceStatusText")
            }

            Divider()

            HStack(spacing: 6) {
                Text(verbatim: snapshot.merchantInsightEndpoint)
                    .font(.caption2.monospaced().weight(.semibold))
                    .accessibilityIdentifier("merchantDecorWizard.insightEndpoint")
                Spacer()
                Text(verbatim: snapshot.insightTopLevelKeys.joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("merchantDecorWizard.insightTopLevelKeys")
            }

            Text(verbatim: snapshot.insightMetricsSummaryText)
                .font(.caption)
                .accessibilityIdentifier("merchantDecorWizard.insightMetricsSummary")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("merchantDecorWizard.npcAndInsightCard")
    }
}
