import SwiftUI

/// F10 editor price area for free-exploration topics. Reads sale readiness from the server,
/// shows open merchant slots with the author "自己承接" entry, and (lifecycle 2) lets the author
/// fill prices and publish for sale. Live writes stay disabled unless independently granted.
@MainActor struct ProjectFreeExploreSaleSection: View {
    @ObservedObject var model: ProjectEditModel
    let topicID: Int
    let client: PublisherLifecycleHTTP
    @Binding var readiness: FreeExploreSaleReadiness?
    @State private var prices: [String: String] = [:]
    @State private var message = ""
    @State private var busy = false
    @State private var confirming = false
    @State private var reloadKey = UUID()
    @Environment(\.locale) private var locale
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    private var state: FreeExplorePriceState { FreeExplorePriceState(readiness) }
    var body: some View {
        Section {
            if let readiness {
                LabeledContent(appLocalized("freeExplore.sale.merchantSlots", locale: locale), value: "\(readiness.filledSlots) / \(readiness.totalSlots)")
                if let open = state.openSlotCount {
                    Text(verbatim: String(format: appLocalized("freeExplore.sale.openSlots", locale: locale), open)).accessibilityIdentifier("projectEdit.freeExplore.openSlots")
                }
                if case .frozen = state { Text(appLocalized("freeExplore.sale.salesAreOpenPrices", locale: locale)) }
            } else {
                Text(appLocalized("freeExplore.sale.saleReadinessNotLoaded", locale: locale)).foregroundStyle(.secondary)
            }
            selfSupplyLinks
            if case .priceEntry(let canPublish) = state { priceEntry(canPublish: canPublish) }
            Button(appLocalized("freeExplore.sale.refresh", locale: locale)) { reloadKey = UUID() }.disabled(busy)
                .accessibilityIdentifier("projectEdit.freeExplore.refresh")
            if !message.isEmpty { Text(message).accessibilityIdentifier("projectEdit.freeExplore.message") }
        } header: {
            Text(appLocalized("freeExplore.sale.freeExplorationPricingAnd", locale: locale))
        } footer: {
            Text(appLocalized("freeExplore.sale.everyMerchantSlotNeeds", locale: locale))
        }
        .task(id: reloadKey) { await load() }
        .confirmationDialog(appLocalized("freeExplore.sale.publishForSale", locale: locale), isPresented: $confirming, titleVisibility: .visible) {
            Button(appLocalized("freeExplore.sale.publish", locale: locale), role: .destructive) { Task { await publish() } }
            Button(appLocalized("freeExplore.sale.cancel", locale: locale), role: .cancel) {}
        } message: {
            Text(appLocalized("freeExplore.sale.thesePricesGoOn", locale: locale))
        }
    }
    @ViewBuilder private var selfSupplyLinks: some View {
        let slots = model.draft.selfSupplySlots
        if let readiness, readiness.lifecycle == 1 || readiness.lifecycle == 2, !slots.isEmpty {
            ForEach(slots) { slot in
                NavigationLink {
                    ProjectSelfSupplyForm(topicID: topicID, slot: slot, client: client) { reloadKey = UUID() }
                } label: {
                    VStack(alignment: .leading) {
                        Text(verbatim: slot.name.isEmpty ? "#\(slot.chapterID)" : slot.name)
                        Text(appLocalized("freeExplore.sale.iLlSupplyThis", locale: locale)).font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("projectEdit.freeExplore.selfSupply.\(slot.chapterID)")
            }
        }
    }
    @ViewBuilder private func priceEntry(canPublish: Bool) -> some View {
        ForEach(model.draft.tickets) { ticket in
            TextField(ticket.name.isEmpty ? appLocalized("freeExplore.sale.ticketPrice", locale: locale) : ticket.name, text: Binding(
                get: { prices[ticket.id] ?? ticket.price }, set: { prices[ticket.id] = $0 }))
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("projectEdit.freeExplore.price.\(ticket.id)")
        }
        let request = try? FreeExplorePublishRequest(topicID: topicID, tickets: model.draft.tickets, prices: prices)
        Button(appLocalized("freeExplore.sale.publish", locale: locale)) { confirming = true }
            .disabled(busy || !canPublish || request == nil || !client.canPublishForSale)
            .accessibilityIdentifier("projectEdit.freeExplore.publish")
        if !client.canPublishForSale {
            Text(appLocalized("freeExplore.sale.livePublishingIsDisabled", locale: locale)).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func load() async {
        do { readiness = try await client.saleReadiness(topicID: topicID) }
        catch { readiness = nil; message = PublisherLifecycleCopy.error(error, zh: zh) }
    }
    private func publish() async {
        guard !busy, let request = try? FreeExplorePublishRequest(topicID: topicID, tickets: model.draft.tickets, prices: prices) else { return }
        busy = true; defer { busy = false }
        let outcome = (try? await client.publishForSale(request)) ?? .unknown
        message = PublisherLifecycleCopy.outcome(outcome, zh: zh)
        if case .acknowledged = outcome { reloadKey = UUID() }
    }
}

/// Author self-supply form: a PERK offer the author redeems personally. Dormant unless granted.
@MainActor struct ProjectSelfSupplyForm: View {
    let topicID: Int
    let slot: CoopFlowSelfSupplySlot
    let client: PublisherLifecycleHTTP
    let completed: () -> Void
    @State private var name = ""
    @State private var rule = ""
    @State private var validEnd = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var capacity = "100"
    @State private var busy = false
    @State private var message = ""
    @Environment(\.locale) private var locale
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    private var day: String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: validEnd)
    }
    private var request: CoopFlowSelfSupplyRequest? {
        guard let count = Int(capacity.trimmingCharacters(in: .whitespacesAndNewlines)),
              let perk = try? CoopFlowSelfSupplyPerk(name: name, redeemRule: rule, validEnd: day, capacity: count) else { return nil }
        return try? CoopFlowSelfSupplyRequest(topicID: topicID, chapterID: slot.chapterID, perk: perk)
    }
    var body: some View {
        Form {
            Section {
                Text(verbatim: slot.name.isEmpty ? "#\(slot.chapterID)" : slot.name).font(.headline)
                Text(appLocalized("freeExplore.sale.youSupplyThisSlot", locale: locale)).foregroundStyle(.secondary)
            }
            Section(appLocalized("freeExplore.sale.perk", locale: locale)) {
                TextField(appLocalized("freeExplore.sale.perkName", locale: locale), text: $name).accessibilityIdentifier("selfSupply.name")
                TextField(appLocalized("freeExplore.sale.redeemRuleEG", locale: locale), text: $rule, axis: .vertical)
                    .lineLimit(2...5).accessibilityIdentifier("selfSupply.rule")
                DatePicker(appLocalized("freeExplore.sale.validUntil", locale: locale), selection: $validEnd, displayedComponents: .date)
                TextField(appLocalized("freeExplore.sale.capacity", locale: locale), text: $capacity).keyboardType(.numberPad).accessibilityIdentifier("selfSupply.capacity")
            }
            Section {
                Button(appLocalized("freeExplore.sale.supplyThisSlot", locale: locale)) { Task { await submit() } }
                    .disabled(busy || request == nil || !client.canSelfSupply)
                    .accessibilityIdentifier("selfSupply.submit")
                if !client.canSelfSupply {
                    Text(appLocalized("freeExplore.sale.liveSelfSupplyIs", locale: locale)).font(.caption).foregroundStyle(.secondary)
                }
                if !message.isEmpty { Text(message).accessibilityIdentifier("selfSupply.message") }
            }
        }
        .navigationTitle(appLocalized("freeExplore.sale.selfSupply", locale: locale))
    }
    private func submit() async {
        guard !busy, let request else { return }
        busy = true; defer { busy = false }
        do {
            let offer = try await client.selfSupply(request)
            message = String(format: appLocalized("freeExplore.selfSupply.acknowledged", locale: locale), String(offer))
            completed()
        } catch CoopFlowFailure.disabled {
            message = appLocalized("freeExplore.sale.notSentAuthorizationIs", locale: locale)
        } catch {
            message = PublisherLifecycleCopy.error(error, zh: zh)
        }
    }
}
