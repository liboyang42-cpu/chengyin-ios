import SwiftUI

@MainActor enum CityMerchantValueCopy {
    static func text(_ key: String) -> Text { Text(LocalizedStringKey("cityValue." + key), tableName: "CityValue") }
    static func string(_ key: String) -> String { String(localized: String.LocalizationValue("cityValue." + key), table: "CityValue") }
}

@MainActor struct CityMerchantValueView: View {
    let model: CityMerchantValueController
    let boardTitle: String
    @Environment(\.scenePhase) private var phase
    @State private var from = Date().addingTimeInterval(-7 * 86400)
    @State private var to = Date()
    @State private var selectedBenefit: CityMerchantValueFact?
    @State private var loadedInitially = false
    @State private var work: Task<Void, Never>?
    private var window: CityMerchantValueWindow? { try? .init(from: from, to: to) }
    var body: some View {
        List {
            Section {
                Text(verbatim: boardTitle).font(.headline)
                DatePicker(CityMerchantValueCopy.string("from"), selection: $from)
                DatePicker(CityMerchantValueCopy.string("to"), selection: $to)
                CityMerchantValueCopy.text("windowHint").font(.footnote)
                Button { if let window { run { await model.load(window: window) } } } label: { CityMerchantValueCopy.text("query") }
                    .disabled(model.busy || window == nil).accessibilityIdentifier("cityValue.query")
                Button { if let window { run { await model.load(window: window, newSnapshot: false) } } } label: { CityMerchantValueCopy.text("retryQuery") }
                    .disabled(model.busy || window == nil)
                if model.busy { ProgressView() }
                if let issue = model.issue { CityMerchantValueCopy.text("issue." + issue) }
            }
            if let report = model.report {
                Section {
                    Text(verbatim: "\(report.from) → \(report.to)").font(.footnote)
                    Text(verbatim: "#\(report.resultId)").font(.caption)
                    if report.incomplete { CityMerchantValueCopy.text("incomplete") }
                    else {
                        metric("entry", report.funnel?["entry"]); metric("meaningful", report.funnel?["meaningfulAction"])
                        metric("success", report.funnel?["serviceSuccess"]); metric("publicGoal", report.funnel?["publicGoal"])
                        metric("cooperativeGoal", report.funnel?["cooperativeGoal"])
                        metric("firstChoiceTime", report.timeToFirstEffectiveChoice); metric("rating", report.serviceRatings)
                        metric("netPoints", report.visitCost?["netPoints"]); metric("budget", report.visitCost?["budget"])
                        metric("cohort", report.byCohort)
                        ForEach(["skip", "exit"], id: \.self) { key in
                            if let group = report.skipExitReasons?[key], group.status == "MEASURED" {
                                CityMerchantValueCopy.text(key).font(.subheadline)
                                if group.reasons?.isEmpty == true { CityMerchantValueCopy.text("noSamples") }
                                ForEach(group.reasons ?? []) { reason in
                                    LabeledContent { Text(verbatim: String(reason.visitCount)) } label: { CityMerchantValueCopy.text("reason." + reason.reasonCode) }
                                }
                            } else { LabeledContent { CityMerchantValueCopy.text("unknown") } label: { CityMerchantValueCopy.text(key) } }
                        }
                        if let groups = report.byServiceType?.types {
                            ForEach(groups) { group in
                                Text(verbatim: group.serviceType).font(.subheadline)
                                ForEach(group.services.services ?? []) { item in
                                    LabeledContent { if let count = item.serviceSuccess { Text(verbatim: String(count)) } else { CityMerchantValueCopy.text("unknown") } } label: { Text(verbatim: item.serviceId) }
                                    if let count = item.ratingCount, let sum = item.ratingSum, count > 0 {
                                        LabeledContent { Text(verbatim: "\(sum)/\(count)") } label: { CityMerchantValueCopy.text("rating") }
                                    }
                                }
                                if group.services.status != "MEASURED" { CityMerchantValueCopy.text("unknown") }
                            }
                        } else { CityMerchantValueCopy.text("unknown") }
                    }
                    Button { run { await model.readBack() } } label: { CityMerchantValueCopy.text("readBack") }.disabled(model.busy)
                }
            }
            Section {
                CityMerchantValueCopy.text("factsNotice").font(.footnote)
                ForEach(model.facts) { fact in
                    VStack(alignment: .leading, spacing: 4) {
                        CityMerchantValueCopy.text("fact." + fact.kind)
                        Text(verbatim: fact.occurredAt).font(.caption)
                        if let type = fact.serviceType { Text(verbatim: type).font(.caption) }
                        if let reason = fact.reasonCode { CityMerchantValueCopy.text("reason." + reason).font(.caption) }
                        if let rating = fact.rating { Text(verbatim: "\(rating) / 100") }
                        Text(verbatim: "#\(fact.id)").font(.caption2)
                        if fact.kind == "SERVICE_SUCCESS" {
                            Button { selectedBenefit = fact } label: { CityMerchantValueCopy.text("benefit.open") }
                                .disabled(!model.canReadBenefit(fact)).accessibilityIdentifier("cityValue.benefit.\(fact.id)")
                        }
                    }.accessibilityIdentifier("cityValue.fact.\(fact.id)")
                }
                if model.hasMore { Button { run { await model.loadMore() } } label: { CityMerchantValueCopy.text("more") }.disabled(model.busy).accessibilityIdentifier("cityValue.more") }
                CityMerchantValueCopy.text("missingSources").font(.footnote)
            }
        }.accessibilityIdentifier("cityValue.merchant")
            .task { guard !loadedInitially else { return }; loadedInitially = true; if let window { await model.load(window: window) } }
            .sheet(item: $selectedBenefit, onDismiss: { model.closeBenefit() }) { fact in
                CityMerchantValueBenefitView(model: model, fact: fact)
            }
            .onDisappear { stop() }.onChange(of: phase) { _, value in if value != .active { stop() } }
    }
    @ViewBuilder private func metric(_ title: String, _ value: CityMerchantValueMetric?) -> some View {
        LabeledContent {
            if let value, value.measured {
                if let count = value.visitCount { Text(verbatim: String(count)) }
                if let mean = value.mean { Text(verbatim: mean) }
                if let millis = value.medianMillis { Text(verbatim: "\(millis) ms") }
                if let sum = value.sum, value.mean == nil { Text(verbatim: String(sum)) }
                if value.visitCount == nil && value.mean == nil && value.medianMillis == nil && value.sum == nil { CityMerchantValueCopy.text("noSamples") }
            } else { CityMerchantValueCopy.text("unknown") }
        } label: { CityMerchantValueCopy.text(title) }
    }
    private func run(_ action: @escaping @MainActor () async -> Void) { guard phase == .active else { return }; work?.cancel(); work = Task { await action() } }
    private func stop() { work?.cancel(); work = nil; model.suspend() }
}

/// A sheet preserves the existing report list, filters, scroll and page cursor. Dismiss never re-runs the report.
@MainActor private struct CityMerchantValueBenefitView: View {
    let model: CityMerchantValueController
    let fact: CityMerchantValueFact
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var retry: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    CityMerchantValueCopy.text("benefit.historyOnly").font(.footnote)
                    LabeledContent { Text(verbatim: "#\(fact.id)") } label: { CityMerchantValueCopy.text("benefit.factID") }
                    Text(verbatim: fact.occurredAt)
                }
                if model.benefitBusy { ProgressView() }
                if let value = model.benefit {
                    Section {
                        if value.verified, let source = value.sourceRecordId, let coupon = value.couponId {
                            CityMerchantValueCopy.text("benefit.verified")
                            LabeledContent { Text(verbatim: "#\(source)") } label: { CityMerchantValueCopy.text("benefit.sourceID") }
                            LabeledContent { Text(verbatim: "#\(coupon)") } label: { CityMerchantValueCopy.text("benefit.couponID") }
                        } else { CityMerchantValueCopy.text("benefit.unknown") }
                        LabeledContent { Text(verbatim: value.serviceId) } label: { CityMerchantValueCopy.text("benefit.serviceID") }
                    }.accessibilityIdentifier(value.verified ? "cityValue.benefit.verified" : "cityValue.benefit.unknown")
                }
                if let issue = model.benefitIssue { CityMerchantValueCopy.text("issue." + issue) }
                Button {
                    guard phase == .active else { return }; retry?.cancel(); retry = Task { await model.readBenefit(fact) }
                } label: { CityMerchantValueCopy.text("benefit.retry") }
                    .disabled(model.benefitBusy || !model.canReadBenefit(fact))
            }.navigationTitle(CityMerchantValueCopy.string("benefit.title"))
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { CityMerchantValueCopy.text("benefit.close") }.accessibilityIdentifier("cityValue.benefit.close")
                } }
        }.accessibilityIdentifier("cityValue.benefit.detail")
            .task { guard phase == .active else { return }; await model.readBenefit(fact) }
            .onDisappear { retry?.cancel(); model.closeBenefit() }
            .onChange(of: phase) { _, value in if value != .active { retry?.cancel(); model.closeBenefit() } }
    }
}
