import SwiftUI

/// Additive host destination. Feature visibility and all service grants are independently default off.
struct MerchantMarketingEntry: View {
    let model: MerchantMarketingCoordinator
    var isSourceVisible = false
    var onSuggestion: (MerchantInsightDestination) -> Void = { _ in }
    var suggestionDestination: ((MerchantInsightDestination) -> AnyView)? = nil
    @State private var selectedSuggestion: MerchantInsightDestination?
    var body: some View {
        if isSourceVisible {
            NavigationLink {
                MerchantMarketingView(model: model, onSuggestion: { route in onSuggestion(route); selectedSuggestion = route })
                    .navigationDestination(item: $selectedSuggestion) { route in
                        if let suggestionDestination { suggestionDestination(route) }
                        else { AnyView(Text("merchantMarketing.unavailable")) }
                    }
            } label: { Label("merchantMarketing.dashboard", systemImage: "chart.bar.xaxis") }
            .accessibilityIdentifier("merchantMarketing.entry")
        }
    }
}

struct MerchantMarketingView: View {
    @Environment(\.locale) private var locale
    @Bindable var model: MerchantMarketingCoordinator
    var onSuggestion: (MerchantInsightDestination) -> Void = { _ in }
    @State private var selected: MerchantMarketingCoordinator.Surface = .dashboard
    init(model: MerchantMarketingCoordinator, initialSurface: MerchantMarketingCoordinator.Surface = .dashboard, onSuggestion: @escaping (MerchantInsightDestination) -> Void = { _ in }) {
        self.model = model; self.onSuggestion = onSuggestion; _selected = State(initialValue: initialSurface)
    }
    var body: some View {
        List {
            Section {
                Text("merchantMarketing.dormant").font(.footnote).foregroundStyle(.secondary)
                Picker("merchantMarketing.section", selection: $selected) {
                    ForEach(MerchantMarketingCoordinator.Surface.allCases) { item in Text(LocalizedStringKey(item.titleKey)).tag(item) }
                }.accessibilityIdentifier("merchantMarketing.sectionPicker")
            }
            if model.busy { ProgressView("merchantMarketing.loading") }
            if let error = model.failure { failure(error) }
            if let result = model.acknowledgement {
                Section("merchantMarketing.acknowledged") {
                    LabeledContent("merchantMarketing.winners", value: String(result.winners))
                        .accessibilityIdentifier("merchantMarketing.winners")
                }
            }
            if let dashboard = model.dashboard { dashboardSections(dashboard) }
            if let insight = model.insight { insightSections(insight) }
            if let subscriptions = model.subscriptions { entitlementSections(subscriptions) }
            if let rounds = model.rounds { predictionSections(rounds) }
        }
        .navigationTitle(LocalizedStringKey(selected.titleKey))
        .toolbar { Button("merchantMarketing.refresh") { Task { await model.load(selected) } }.disabled(model.busy) }
        .task(id: selected) { await model.load(selected) }
        .onChange(of: model.scopeIdentity) { _, _ in model.sessionChanged(); Task { await model.load(selected) } }
        .sheet(isPresented: Binding(get: { model.review != nil }, set: { if !$0 { model.cancelReview() } })) {
            if let accepted = model.review { MerchantPredictionReviewView(model: model, accepted: accepted) }
        }
    }
    private func failure(_ error: MerchantMarketingFailure) -> some View {
        Section {
            Text(LocalizedStringKey(error.key)).accessibilityIdentifier("merchantMarketing.error")
            if let message = error.serverMessage { Text(message).font(.footnote) }
        }
    }
    private func value(_ number: Int?) -> String { number.map(String.init) ?? "—" }
    private func percent(_ number: Double?) -> String { number.map { String(format: "%.1f%%", $0 * 100) } ?? "—" }
    @ViewBuilder private func dashboardSections(_ dashboard: MerchantMarketingDashboard) -> some View {
        Section("merchantMarketing.coupons") {
            LabeledContent("merchantMarketing.active", value: value(dashboard.couponCount))
            LabeledContent("merchantMarketing.claimed", value: value(dashboard.received))
            LabeledContent("merchantMarketing.redeemed", value: value(dashboard.verified))
            if let rate = dashboard.verificationRate { LabeledContent("merchantMarketing.redemptionRate", value: percent(rate)) }
        }
        Section("merchantMarketing.content") {
            LabeledContent("merchantMarketing.topics", value: value(dashboard.topics))
            LabeledContent("merchantMarketing.exploration", value: value(dashboard.exploration))
            LabeledContent("merchantMarketing.activities", value: value(dashboard.activities))
        }
        if !dashboard.funnel.isEmpty {
            Section("merchantMarketing.funnel") {
                ForEach(Array(dashboard.funnel.enumerated()), id: \.offset) { _, step in
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent(step.step, value: value(step.count))
                        if let rate = step.rate { Text(percent(rate)); ProgressView(value: min(1, max(0, rate))).accessibilityLabel(step.step).accessibilityValue(percent(rate)) }
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }
    @ViewBuilder private func insightSections(_ insight: MerchantMarketingInsight) -> some View {
        Section("merchantMarketing.facts") {
            LabeledContent("merchantMarketing.window", value: insight.facts["window"].text ?? "—")
            LabeledContent("merchantMarketing.sample", value: value(insight.facts["sampleMembers"].integer))
            if insight.facts["lowSample"].isTrue { Text("merchantMarketing.lowSample") }
            LabeledContent("merchantMarketing.checkins", value: value(insight.facts["checkin"]["total"].integer))
            LabeledContent("merchantMarketing.redemptionRate", value: percent(insight.facts["checkin"]["redeemRate"].decimal))
            LabeledContent("merchantMarketing.repeatRate", value: percent(insight.facts["checkin"]["repeatRate"].decimal))
            LabeledContent("merchantMarketing.wait", value: value(insight.facts["checkin"]["avgWaitMinutes"].integer))
            LabeledContent("merchantMarketing.members", value: value(insight.facts["crowd"]["members"].integer))
            LabeledContent("merchantMarketing.offers", value: value(insight.facts["supply"]["activeOffers"].integer))
            LabeledContent("merchantMarketing.quotaRate", value: percent(insight.facts["supply"]["quotaUsedRate"].decimal))
            ForEach(Array((insight.facts["checkin"]["hourBuckets"].array ?? []).enumerated()), id: \.offset) { _, bucket in
                VStack(alignment: .leading) {
                    LabeledContent("merchantMarketing.hour", value: value(bucket["hour"].integer))
                    LabeledContent("merchantMarketing.checkins", value: value(bucket["count"].integer))
                }.accessibilityElement(children: .combine)
            }
            LabeledContent("merchantMarketing.maleRate", value: percent(insight.facts["crowd"]["sexRatio"]["male"].decimal))
            LabeledContent("merchantMarketing.femaleRate", value: percent(insight.facts["crowd"]["sexRatio"]["female"].decimal))
            ForEach(Array((insight.facts["crowd"]["interestTop"].array ?? []).enumerated()), id: \.offset) { _, interest in
                if let text = interest.text { LabeledContent("merchantMarketing.interest", value: text) }
            }
        }
        Section("merchantMarketing.suggestions") {
            Text("merchantMarketing.suggestionNotice").font(.footnote)
            if let ai = insight.ai {
                Text(ai["summary"].text ?? "—")
                ForEach(Array((ai["audiences"].array ?? []).enumerated()), id: \.offset) { _, audience in
                    VStack(alignment: .leading) { Text(audience["label"].text ?? "—"); if let reason = audience["reason"].text { Text(reason) } }
                }
            } else { Text("merchantMarketing.aiUnavailable") }
            if let error = insight.aiError, !error.isEmpty { Text(error) }
            if let date = insight.generatedAt { LabeledContent("merchantMarketing.generatedAt", value: date) }
            ForEach(Array(insight.suggestions.enumerated()), id: \.offset) { _, suggestion in
                VStack(alignment: .leading, spacing: 8) {
                    Text(suggestion.title).font(.headline)
                    if let reason = suggestion.reason { Text(reason) }
                    if let slot = suggestion.timeSlot { Text(slot) }
                    if let audience = suggestion.audience { Text(audience) }
                    if let destination = suggestion.destination {
                        Button("merchantMarketing.openSuggestion") { onSuggestion(destination) }.accessibilityHint(suggestion.title)
                    }
                }
            }
        }
        Section("merchantMarketing.recommendedTopics") {
            ForEach(Array(insight.recommendedTopics.enumerated()), id: \.offset) { _, item in Text(item["name"].text ?? "—") }
        }
        Section("merchantMarketing.recommendedPartners") {
            ForEach(Array(insight.recommendedPartners.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading) { Text(item["name"].text ?? "—"); if let reason = item["reason"].text { Text(reason) } }
            }
        }
    }
    @ViewBuilder private func entitlementSections(_ subscriptions: [MerchantMarketingEntitlement]) -> some View {
        Section("merchantMarketing.activeEntitlements") {
            if subscriptions.isEmpty { Text("merchantMarketing.noEntitlements").accessibilityIdentifier("merchantMarketing.emptyEntitlements") }
            ForEach(Array(subscriptions.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey(entitlementTitle(item.subscriptionType))).font(.headline)
                    if item.isPermanent { Text("merchantMarketing.permanent") } else { Text(item.endDate ?? "—") }
                    if let max = item.maxUsage { LabeledContent("merchantMarketing.usage", value: "\(value(item.usedCount)) / \(max)") }
                }.accessibilityElement(children: .combine)
            }
        }
        Section("merchantMarketing.capabilities") {
            if let error = model.commerceFailure { Text(LocalizedStringKey(error.key)); if let message = error.serverMessage { Text(message) } }
            if let commerce = model.commerce {
                if let quota = commerce.premiumTemplate { quotaRow("merchantMarketing.premium", quota) }
                if let quota = commerce.cityNode { quotaRow("merchantMarketing.cityNode", quota) }
            }
            Text("merchantMarketing.iOSCheckoutUnavailable").accessibilityIdentifier("merchantMarketing.checkoutUnavailable")
        }
    }
    private func entitlementTitle(_ type: String) -> String {
        switch type { case "premium_template": return "merchantMarketing.premium"; case "promotion_slot": return "merchantMarketing.promotion"; case "brand_home": return "merchantMarketing.brand"; case "custom_event": return "merchantMarketing.customEvent"; default: return type }
    }
    private func quotaRow(_ key: String, _ quota: MerchantMarketingCommerce.Quota) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(key)).font(.headline)
            LabeledContent("merchantMarketing.used", value: value(quota.used))
            LabeledContent("merchantMarketing.limit", value: value(quota.limit))
            LabeledContent("merchantMarketing.remaining", value: value(quota.remaining))
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private func predictionSections(_ rounds: [MerchantPredictionRound]) -> some View {
        Section { Text("merchantMarketing.couponWarning").font(.footnote); Text("merchantMarketing.deadlinePolicy").font(.footnote) }
        if rounds.isEmpty { Section { Text("merchantMarketing.emptyPredictions") } }
        ForEach(rounds) { round in
            Section {
                Text(round.nodeName ?? appLocalized("merchantMarketing.unnamed", locale: locale)).font(.headline)
                Text(round.playDay); if let question = round.question { Text(question) }
                if let days = round.daysLeft {
                    if days <= 0 { Label("merchantMarketing.today", systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                    else { LabeledContent("merchantMarketing.daysLeft", value: String(days)) }
                }
                if let count = round.betCount, count > 0 { LabeledContent("merchantMarketing.bets", value: String(count)) }
                else if round.betCount == 0 { Text("merchantMarketing.noBets") }
                ForEach(round.options) { option in
                    Button { Task { await model.prepare(round, option: option.key) } } label: { Text(option.label) }
                    .disabled(model.busy || !model.service.permitsSettlement)
                    .accessibilityIdentifier("merchantMarketing.option.\(option.key)")
                    .accessibilityHint(Text("merchantMarketing.reviewHint"))
                }
            }
        }
    }
}

private struct MerchantPredictionReviewView: View {
    @Environment(\.locale) private var locale
    @Bindable var model: MerchantMarketingCoordinator
    let accepted: MerchantPredictionReview
    @State private var acknowledged = false
    var body: some View {
        NavigationStack {
            Form {
                Section("merchantMarketing.review") {
                    Text(accepted.round.nodeName ?? appLocalized("merchantMarketing.unnamed", locale: locale))
                    Text(accepted.round.playDay); Text(accepted.round.question ?? "—")
                    LabeledContent("merchantMarketing.answer", value: accepted.option.label)
                    Text("merchantMarketing.couponWarning").font(.headline)
                    Toggle("merchantMarketing.acknowledgeEffects", isOn: $acknowledged).accessibilityIdentifier("merchantMarketing.acknowledgeEffects")
                }
                Button("merchantMarketing.confirmSettlement", role: .destructive) { Task { await model.confirm(couponEffectsAcknowledged: acknowledged) } }
                    .disabled(!acknowledged || model.busy).accessibilityIdentifier("merchantMarketing.confirmSettlement")
            }
            .navigationTitle("merchantMarketing.review")
            .toolbar { Button("merchantMarketing.cancel") { model.cancelReview() }.disabled(model.busy) }
            .interactiveDismissDisabled(model.busy)
        }
    }
}
