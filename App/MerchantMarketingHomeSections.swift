import SwiftUI

/// Source pages/merchant/marketing/index.wxml: hero, permission-filtered tools, my content,
/// coupon deck, cooperation banner and the all-zero empty state. Counts never render as a dash and
/// no funnel percentage is shown; the only ratio is the same-batch "verified after receiving" coupon rate.
@MainActor struct MerchantMarketingHomeSections: View {
    let home: MerchantMarketingHome
    let access: MerchantMarketingAccess
    var onRetry: () -> Void = {}
    var onInsight: () -> Void = {}
    var onRoute: (MerchantInsightDestination) -> Void = { _ in }
    var body: some View {
        if home.isAllZero {
            Section {
                Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.empty.title")).font(.headline)
                    .accessibilityIdentifier("merchantOps.marketing.empty")
                if access.canManageProjects {
                    Button(MerchantOpsCopy.text("merchantOps.marketing.empty.cta")) { onRoute(.content) }
                        .accessibilityIdentifier("merchantOps.marketing.firstContent")
                }
            }
        }
        hero
        // Source tiles: up to four round tools under the hero.
        Section {
            HStack(alignment: .top, spacing: Theme.Space.s2) {
                if access.canReadMarketing {
                    QuestifyRoundAction(title: tool("merchantOps.marketing.tool.insight"), systemImage: "chart.bar.xaxis", action: onInsight)
                        .accessibilityIdentifier("merchantOps.marketing.tool.insight")
                }
                if access.canManageCoop {
                    QuestifyRoundAction(title: tool("merchantOps.marketing.tool.decor"), systemImage: "paintbrush") { onRoute(.decoration) }
                        .accessibilityIdentifier("merchantOps.marketing.tool.decor")
                }
                QuestifyRoundAction(title: tool("merchantOps.marketing.tool.topic"), systemImage: "square.and.pencil") { onRoute(.content) }
                    .accessibilityIdentifier("merchantOps.marketing.tool.topic")
                QuestifyRoundAction(title: tool("merchantOps.marketing.tool.activity"), systemImage: "calendar.badge.plus") { onRoute(.topicCooperation) }
                    .accessibilityIdentifier("merchantOps.marketing.tool.activity")
            }
            .padding(.vertical, Theme.Space.s1)
        }
        Section(MerchantOpsCopy.text("merchantOps.marketing.myContent")) {
            LabeledContent("merchantMarketing.topics", value: String(home.content.topicCount))
            LabeledContent("merchantMarketing.exploration", value: String(home.content.freeExploreCount))
            LabeledContent("merchantMarketing.activities", value: String(home.content.activityCount))
        }
        Section("merchantMarketing.coupons") {
            if home.hasCouponDeck {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.coupon.live %lld", home.coupons.couponCount)).font(.headline)
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.coupon.counts %lld %lld", home.coupons.received, home.coupons.verified)).font(.footnote)
                    if let rate = home.verifiedAfterReceivePercent {
                        Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.coupon.rate %lld", rate)).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("merchantOps.marketing.coupon.rate")
                    }
                }.accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.marketing.couponDeck")
                LabeledContent("merchantMarketing.claimed", value: String(home.coupons.received))
                LabeledContent("merchantMarketing.redeemed", value: String(home.coupons.verified))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.coupon.empty.title")).font(.headline)
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.coupon.empty.body")).font(.footnote).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.marketing.coupon.empty")
            }
        }
        Section(MerchantOpsCopy.text("merchantOps.marketing.coop.title")) {
            Button { onRoute(.topicCooperation) } label: {
                LabeledContent {
                    if home.recruiting.count > 0 {
                        Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.coop.count %lld", home.recruiting.count))
                    }
                } label: {
                    Text("merchant.marketing.enterCoop").foregroundStyle(.primary)
                }
            }.accessibilityIdentifier("merchantOps.marketing.coop")
        }
    }
    /// MerchantOps copy is already resolved for the current language; wrap it for QuestifyRoundAction.
    private func tool(_ key: String) -> LocalizedStringKey { LocalizedStringKey(MerchantOpsCopy.text(key)) }
    @ViewBuilder private var hero: some View {
        Section {
            VStack(spacing: Theme.Space.s1) {
                Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.hero.label %lld", MerchantMarketingHome.windowDays))
                    .font(.subheadline).foregroundStyle(.secondary)
                QuestifyHeroValue(value: Text(verbatim: home.heroValue))
                    .accessibilityIdentifier("merchantOps.marketing.hero.value")
                Group {
                    if home.analytics == nil {
                        Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.analytics.unavailable")).foregroundStyle(.secondary)
                    } else {
                        switch home.heroSubtitle {
                        case .noSignup: Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.hero.noSignup"))
                        case .noVerification: Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.hero.noVerification"))
                        case .verified(let count): Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.hero.verified %@", count))
                        }
                    }
                }
                .font(.footnote).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Space.s4)
            .accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.marketing.hero")
            if home.analytics == nil {
                Button(MerchantOpsCopy.text("merchantOps.marketing.analytics.retry"), action: onRetry).accessibilityIdentifier("merchantOps.marketing.analytics.retry")
            }
        }
    }
}

/// Source ai-insight value card delta and the explicit all-zero guidance.
struct MerchantInsightParityRows: View {
    let facts: MerchantMarketingValue
    let isEmpty: Bool
    var onCoopCenter: (() -> Void)? = nil
    var body: some View {
        if let delta = MerchantInsightParity.visitorDelta(facts) {
            Text(verbatim: MerchantOpsCopy.text("merchantOps.insight.delta %@", (delta > 0 ? "+" : "") + String(delta)))
                .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("merchantOps.insight.delta")
        }
        if isEmpty {
            Text(verbatim: MerchantOpsCopy.text("merchantOps.insight.empty.body")).font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("merchantOps.insight.empty")
            if let onCoopCenter,
               let cta = MerchantInsightParity.emptyCTATitle(isEmpty: isEmpty, canOpenCoopCenter: true) {
                Button(action: onCoopCenter) {
                    Text(verbatim: cta)
                }
                .accessibilityIdentifier("merchantOps.insight.emptyGuidance.cta")
            }
        }
    }
}
