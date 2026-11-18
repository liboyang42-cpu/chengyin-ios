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
    private func t(_ en: String, _ cn: String) -> String { zh ? cn : en }
    private var state: FreeExplorePriceState { FreeExplorePriceState(readiness) }
    var body: some View {
        Section {
            if let readiness {
                LabeledContent(t("Merchant slots", "商家位置"), value: "\(readiness.filledSlots) / \(readiness.totalSlots)")
                if let text = state.openSlotsText(zh: zh) {
                    Text(text).accessibilityIdentifier("projectEdit.freeExplore.openSlots")
                }
                if case .frozen = state { Text(t("Sales are open; prices are frozen.", "已开售，票价已冻结。")) }
            } else {
                Text(t("Sale readiness not loaded. Live reads require approval.", "未读取开售状态。真实读取需独立批准后启用。")).foregroundStyle(.secondary)
            }
            selfSupplyLinks
            if case .priceEntry(let canPublish) = state { priceEntry(canPublish: canPublish) }
            Button(t("Refresh", "刷新")) { reloadKey = UUID() }.disabled(busy)
                .accessibilityIdentifier("projectEdit.freeExplore.refresh")
            if !message.isEmpty { Text(message).accessibilityIdentifier("projectEdit.freeExplore.message") }
        } header: {
            Text(t("Free exploration · pricing and sale", "自由探索 · 票价与开售"))
        } footer: {
            Text(t("Every merchant slot needs a supplier (a merchant or yourself) before pricing. Project review applies at first publication; this author path has no separate sale review.",
                   "所有商家位置都有人承接（商家或你自己）后才能填票价。首次发布仍需立项审核；此路径填完票价直接发布，无单独开售审核。"))
        }
        .task(id: reloadKey) { await load() }
        .confirmationDialog(t("Publish for sale?", "确认发布开售？"), isPresented: $confirming, titleVisibility: .visible) {
            Button(t("Publish", "发布"), role: .destructive) { Task { await publish() } }
            Button(t("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(t("These prices go on sale immediately and partner terms freeze.", "按这些票价立即开售，合作条款随之冻结。"))
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
                        Text(t("I'll supply this slot", "自己承接")).font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("projectEdit.freeExplore.selfSupply.\(slot.chapterID)")
            }
        }
    }
    @ViewBuilder private func priceEntry(canPublish: Bool) -> some View {
        ForEach(model.draft.tickets) { ticket in
            TextField(ticket.name.isEmpty ? t("Ticket price", "票价") : ticket.name, text: Binding(
                get: { prices[ticket.id] ?? ticket.price }, set: { prices[ticket.id] = $0 }))
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("projectEdit.freeExplore.price.\(ticket.id)")
        }
        let request = try? FreeExplorePublishRequest(topicID: topicID, tickets: model.draft.tickets, prices: prices)
        Button(t("Publish", "发布")) { confirming = true }
            .disabled(busy || !canPublish || request == nil || !client.canPublishForSale)
            .accessibilityIdentifier("projectEdit.freeExplore.publish")
        if !client.canPublishForSale {
            Text(t("Live publishing is disabled until independently approved.", "真实发布需独立批准后启用。")).font(.caption).foregroundStyle(.secondary)
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
    private func t(_ en: String, _ cn: String) -> String { zh ? cn : en }
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
                Text(t("You supply this slot yourself and redeem the perk in person.", "由你自己承接这个位置，并亲自核销权益。")).foregroundStyle(.secondary)
            }
            Section(t("Perk", "权益")) {
                TextField(t("Perk name", "权益名称"), text: $name).accessibilityIdentifier("selfSupply.name")
                TextField(t("Redeem rule (e.g. 20% off, show at the counter)", "核销规则（如 8 折，到店出示）"), text: $rule, axis: .vertical)
                    .lineLimit(2...5).accessibilityIdentifier("selfSupply.rule")
                DatePicker(t("Valid until", "有效期至"), selection: $validEnd, displayedComponents: .date)
                TextField(t("Capacity", "数量"), text: $capacity).keyboardType(.numberPad).accessibilityIdentifier("selfSupply.capacity")
            }
            Section {
                Button(t("Supply this slot", "确认自己承接")) { Task { await submit() } }
                    .disabled(busy || request == nil || !client.canSelfSupply)
                    .accessibilityIdentifier("selfSupply.submit")
                if !client.canSelfSupply {
                    Text(t("Live self-supply is disabled until independently approved.", "真实承接需独立批准后启用。")).font(.caption).foregroundStyle(.secondary)
                }
                if !message.isEmpty { Text(message).accessibilityIdentifier("selfSupply.message") }
            }
        }
        .navigationTitle(t("Self-supply", "自己承接"))
    }
    private func submit() async {
        guard !busy, let request else { return }
        busy = true; defer { busy = false }
        do {
            let offer = try await client.selfSupply(request)
            message = t("Server acknowledged offer #\(offer). Refresh to verify.", "服务器已接收承接 #\(offer)，请刷新核实。")
            completed()
        } catch CoopFlowFailure.disabled {
            message = t("Not sent. Authorization is disabled.", "未发送。授权关闭。")
        } catch {
            message = PublisherLifecycleCopy.error(error, zh: zh)
        }
    }
}
