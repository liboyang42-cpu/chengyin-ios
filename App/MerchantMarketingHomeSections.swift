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
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.empty.title")).font(.headline)
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.empty.body")).font(.footnote).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.marketing.empty")
                if access.canManageProjects {
                    Button(MerchantOpsCopy.text("merchantOps.marketing.empty.cta")) { onRoute(.content) }
                        .accessibilityIdentifier("merchantOps.marketing.firstContent")
                }
            }
        }
        hero
        Section {
            if access.canReadMarketing { Button(MerchantOpsCopy.text("merchantOps.marketing.tool.insight"), action: onInsight).accessibilityIdentifier("merchantOps.marketing.tool.insight") }
            if access.canManageCoop { Button(MerchantOpsCopy.text("merchantOps.marketing.tool.decor")) { onRoute(.decoration) }.accessibilityIdentifier("merchantOps.marketing.tool.decor") }
            Button(MerchantOpsCopy.text("merchantOps.marketing.tool.topic")) { onRoute(.content) }.accessibilityIdentifier("merchantOps.marketing.tool.topic")
            Button(MerchantOpsCopy.text("merchantOps.marketing.tool.activity")) { onRoute(.topicCooperation) }.accessibilityIdentifier("merchantOps.marketing.tool.activity")
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.coop.count %lld", home.recruiting.count))
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.coop.body")).font(.footnote).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("merchantOps.marketing.coop")
        }
    }
    @ViewBuilder private var hero: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.hero.label %lld", MerchantMarketingHome.windowDays)).font(.footnote)
                Text(verbatim: home.heroValue).font(.largeTitle.bold()).accessibilityIdentifier("merchantOps.marketing.hero.value")
                if home.analytics == nil {
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.analytics.unavailable")).font(.footnote).foregroundStyle(.secondary)
                } else {
                    switch home.heroSubtitle {
                    case .noSignup: Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.hero.noSignup")).font(.footnote)
                    case .noVerification: Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.hero.noVerification")).font(.footnote)
                    case .verified(let count): Text(verbatim: MerchantOpsCopy.text("merchantOps.marketing.hero.verified %@", count)).font(.footnote)
                    }
                }
            }.accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.marketing.hero")
            if home.analytics == nil {
                Button(MerchantOpsCopy.text("merchantOps.marketing.analytics.retry"), action: onRetry).accessibilityIdentifier("merchantOps.marketing.analytics.retry")
            }
        }
    }
}
