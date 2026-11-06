import SwiftUI

/// Add these scoped destinations to the existing PublishModes/project editor/topic hosts.
/// Default grants are dormant; UI review never changes activation policy.
@MainActor struct PublisherPricingView: View {
    let topicID: Int
    let client: PublisherLifecycleHTTP
    let coordinator: PublisherLifecycleCoordinator
    @State private var subtype = PublisherPriceSubtype.selfPlay
    @State private var cost = ""
    @State private var team = ""
    @State private var price = ""
    @State private var preview: PublisherPricingPreview?
    /// Source lineup names, loaded per row after the preview; missing names keep the type label.
    @State private var partnerNames: [String: String] = [:]
    @State private var review: PublisherLifecycleReview?
    @State private var message = ""
    @State private var busy = false
    @State private var generation = UUID()
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    private func text(_ key: String) -> String { appLocalized(String.LocalizationValue(key), locale: locale) }
    var body: some View {
        Form {
            Section {
                // Source chip tabs 有人带 / 无人带.
                Picker(text("publisherPricing.format"), selection: $subtype) {
                    Text(text("publisherPricing.guided")).tag(PublisherPriceSubtype.guided)
                    Text(text("publisherPricing.selfGuided")).tag(PublisherPriceSubtype.selfPlay)
                }.pickerStyle(.segmented).accessibilityIdentifier("publisher.subtype")
            }
            if subtype == .guided {
                Section(text("publisherPricing.leadCost")) {
                    TextField(text("publisherPricing.totalLeadCostForThisGroup"), text: $cost).keyboardType(.decimalPad)
                    TextField(text("publisherPricing.groupSize"), text: $team).keyboardType(.numberPad)
                    if (Int(team) ?? 0) <= 0 {
                        Text(text("publisherPricing.guidedPricingNeedsAGroupSize")).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            Section {
                Button(subtype == .guided ? text("publisherPricing.recalculateMinimum") : text("publisherPricing.refreshMinimumPrice")) { Task { await load() } }
                    .disabled(busy).accessibilityIdentifier("publisher.preview")
                if busy { Text(text("publisherPricing.checkingTheLatestPricing")).font(.caption) }
            }
            if let preview {
                Section(text("publisherPricing.minimumPrice")) {
                    Text(verbatim: "¥" + NSDecimalNumber(decimal: preview.minimum).stringValue).font(.title2.bold()).accessibilityIdentifier("publisher.floor")
                    Text(text("publisherPricing.theFinalPriceCanTBe")).font(.caption).foregroundStyle(.secondary)
                }
                Section(text("publisherPricing.yourFinalPrice")) {
                    TextField(text("publisherPricing.finalPrice"), text: $price).keyboardType(.decimalPad).accessibilityIdentifier("publisher.finalPrice")
                    let floorValue = TopicPricingXcx.initialPrice(floor: preview.minimum)
                    let maximum = TopicPricingXcx.sliderMax(floor: preview.minimum, reference: preview.reference)
                    Slider(value: Binding(get: { Double(price) ?? Double(floorValue) }, set: { price = String(Int($0.rounded())) }),
                           in: Double(floorValue)...Double(max(maximum, floorValue + 1)), step: 1)
                    HStack {
                        Text(verbatim: text("publisherPricing.minimum") + " ¥" + NSDecimalNumber(decimal: preview.minimum).stringValue)
                        Spacer(); Text(verbatim: "¥\(maximum)")
                    }.font(.caption)
                    if let reference = preview.reference, let count = preview.sampleSize, count > 0 {
                        let area = preview.referenceLabel ?? text("publisherPricing.local")
                        let average = TopicPricingXcx.twoDecimals(NSDecimalNumber(decimal: reference).stringValue) ?? "—"
                        Text("publisherPricing.reference \(area) \(average) \(count)").font(.caption)
                    } else { Text(text("publisherPricing.notEnoughSamplesNoReferencePrice")).font(.caption) }
                    switch TopicPricingXcx.delta(price: Decimal(string: price) ?? preview.minimum, reference: preview.reference, sampleSize: preview.sampleSize) {
                    case .above(let percent)?: Text("publisherPricing.aboveReference \(percent)").font(.caption).foregroundStyle(.orange)
                    case .notAbove?: Text(text("publisherPricing.notAboveTheLocalReferencePrice")).font(.caption)
                    case nil: EmptyView()
                    }
                }
                if !preview.lineup.isEmpty {
                    Section {
                        ForEach(preview.lineup) { row in
                            NavigationLink {
                                PublisherPartnerView(topicID: topicID, row: row, client: client)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    if let name = partnerNames[row.id] { Text(verbatim: name) }
                                    else { Text(row.type == "club" ? text("publisherPricing.partnerClub") : text("publisherPricing.hostingMerchant")) }
                                    Text(verbatim: termsText(row)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: { Text(text("publisherPricing.partnerLineup")) }
                }
                Section {
                    if preview.canConfirm == false {
                        Text(text("publisherPricing.youCanSetThePriceOnce")).font(.caption).foregroundStyle(.orange)
                            .accessibilityIdentifier("publisher.phaseBlocked")
                    }
                    Button(text("publisherPricing.confirmFinalPriceAndSubmitFor")) { Task { await prepare() } }
                        .disabled(busy || preview.canConfirm == false).accessibilityIdentifier("publisher.reviewPrice")
                }
            }
            if let review {
                Section(text("publisherPricing.review")) {
                    Text(text("publisherPricing.salesOpenAtThisPriceAnd"))
                    Text(price).accessibilityIdentifier("publisher.reviewedPrice")
                    Button(text("publisherPricing.confirmOpeningSales"), role: .destructive) { Task { busy = true; let result = await coordinator.confirm(review, consequentialApproval: true); message = PublisherLifecycleCopy.outcome(result, zh: isChinese); self.review = nil; busy = false } }.disabled(busy).accessibilityIdentifier("publisher.confirmPrice")
                }
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("publisher.message") }
        }
        .navigationTitle(text("publisherPricing.confirmFinalPrice"))
        .task(id: preview?.lineup.map(\.id) ?? []) { await loadPartnerNames() }
        .onChange(of: subtype) { _, _ in invalidate() }
        .onChange(of: cost) { _, _ in invalidate() }
        .onChange(of: team) { _, _ in invalidate() }
        .onChange(of: price) { _, _ in review = nil; coordinator.invalidate() }
        .onChange(of: phase) { _, value in if value != .active { invalidate() } }
        .onDisappear { invalidate() }
    }
    private func loadPartnerNames() async {
        guard let lineup = preview?.lineup else { return }
        let stamp = generation
        for row in lineup where partnerNames[row.id] == nil {
            guard let name = try? await client.partnerName(type: row.type, id: row.partnerID), generation == stamp, !Task.isCancelled else { continue }
            partnerNames[row.id] = name
        }
    }
    private func termsText(_ row: PublisherLineup) -> String {
        switch TopicPricingXcx.terms(row) {
        case .chapterPerk: return text("publisherPricing.chapterSupplyPerks")
        case .chapterTraffic: return text("publisherPricing.chapterSupplyReferral")
        case .chapterRevshare(let fee): return appLocalized("publisherPricing.terms.chapterRevshare \(fee ?? "—")", locale: locale)
        case .share(let rate): return appLocalized("publisherPricing.terms.share \(rate.map { $0 + "%" } ?? "—")", locale: locale)
        case .fixed(let fee): return fee.map { appLocalized("publisherPricing.terms.fixed \($0)", locale: locale) } ?? appLocalized("publisherPricing.terms.fixedUnknown", locale: locale)
        case .traffic: return text("publisherPricing.referral")
        }
    }
    private var isChinese: Bool { locale.language.languageCode?.identifier == "zh" }
    private func input() throws -> PublisherPricingInput { try .init(topicID: topicID, subtype: subtype, leadCost: Decimal(string: cost), teamSize: Int(team)) }
    private func invalidate() { generation = UUID(); preview = nil; partnerNames = [:]; review = nil; coordinator.invalidate() }
    private func load() async {
        let stamp = generation; busy = true; defer { busy = false }
        do { let result = try await client.pricing(input()); guard generation == stamp else { return }; preview = result; price = String(TopicPricingXcx.initialPrice(floor: result.minimum)); message = "" }
        catch { if generation == stamp { preview = nil; message = PublisherLifecycleCopy.error(error, zh: isChinese) } }
    }
    private func prepare() async {
        busy = true; defer { busy = false }; let stamp = generation
        do { guard let price = Decimal(string: price) else { throw PublisherLifecycleError.incomplete }; let value = try await coordinator.prepare(.pricing(input(), price)); guard generation == stamp else { return }; review = value }
        catch { message = PublisherLifecycleCopy.error(error, zh: isChinese) }
    }
}
@MainActor struct PublisherPartnerView: View {
    let topicID: Int; let row: PublisherLineup; let client: PublisherLifecycleHTTP
    @State private var result: PublisherPartnerInspection?
    @State private var message = ""
    @State private var loading = true
    @Environment(\.locale) private var locale
    private var isClub: Bool { row.type == "club" }
    var body: some View {
        List {
            if topicID <= 0 || row.partnerID <= 0 || !["club", "merchant"].contains(row.type) {
                // Source invalid-link state.
                VStack(alignment: .leading, spacing: 4) {
                    Text(text("publisherPricing.thisPartnerLinkIsNoLonger")).font(.headline)
                    Text(text("publisherPricing.goBackAndOpenItAgain")).font(.footnote)
                }.accessibilityIdentifier("publisher.partner.invalid")
            } else {
                Section {
                    if loading { ProgressView(text("publisherPricing.loadingPartnerInformation")) }
                    else if let result {
                        let profile = result.profile.object ?? [:]
                        Text(profile["name"]?.text ?? "—").font(.headline)
                        if let description = profile["description"]?.text, !description.isEmpty { Text(description) }
                        let rows = profileRows(profile)
                        if rows.isEmpty { Text(text("publisherPricing.noProfileYet")).foregroundStyle(.secondary) }
                        ForEach(rows, id: \.0) { key, value in LabeledContent(key, value: value) }
                    }
                } header: { Text(isClub ? text("publisherPricing.partnerClub") : text("publisherPricing.hostingMerchant")) }
                if let terms = result?.terms {
                    Section(text("publisherPricing.partnershipTerms")) {
                        LabeledContent(text("publisherPricing.settlement"), value: terms.mode == 1 ? text("publisherPricing.revenueShare") : terms.mode == 2 ? text("publisherPricing.fixed") : text("publisherPricing.referral"))
                        if terms.mode == 1 { LabeledContent(text("publisherPricing.share"), value: "\(terms.shareRate ?? "—")%") }
                        if terms.mode == 2 { LabeledContent(text("publisherPricing.fixedFee"), value: "¥\(terms.fixedFee ?? "—")" + text("publisherPricing.perPerson")) }
                        LabeledContent(text("publisherPricing.locked"), value: text("publisherPricing.whenSalesOpen"))
                        Text(terms.mode == 1 ? text("publisherPricing.termsFreezeWhenSalesOpenSettlement")
                             : terms.mode == 2 ? text("publisherPricing.termsFreezeWhenSalesOpenSettlement44")
                             : text("publisherPricing.theLineupFreezesWhenSalesOpen")).font(.caption)
                    }
                }
            }
            if !message.isEmpty { Text(message) }
        }.accessibilityIdentifier("publisher.partner")
        .navigationTitle(isClub ? text("publisherPricing.partnerClub") : text("publisherPricing.hostingMerchant"))
        .task {
            guard topicID > 0, row.partnerID > 0 else { loading = false; return }
            do { result = try await client.partner(topicID: topicID, type: row.type, id: row.partnerID) } catch { message = PublisherLifecycleCopy.error(error, zh: zh) }
            loading = false
        }
    }
    /// Source profile rows; values may be strings, numbers, arrays or objects (flattened by name/title/label).
    private func profileRows(_ profile: [String: ProjectEditJSON]) -> [(String, String)] {
        func flat(_ value: ProjectEditJSON?) -> String? {
            guard let value else { return nil }
            if case .number(let number) = value { return NSDecimalNumber(decimal: number).stringValue }
            if let array = value.array { let parts = array.compactMap { flat($0) }; return parts.isEmpty ? nil : parts.joined(separator: " · ") }
            if let object = value.object { return ["name", "title", "label", "address", "categoryName"].lazy.compactMap { object[$0]?.text }.first }
            guard let text = value.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text != "null" else { return nil }
            return text
        }
        var rows: [(String, String)] = []
        func add(_ label: String, _ value: String?) { if let value { rows.append((label, value)) } }
        if isClub {
            add(text("publisherPricing.leader"), flat(profile["leaderName"]))
            add(text("publisherPricing.city"), flat(profile["city"]) ?? flat(profile["address"]))
            add(text("publisherPricing.clubType"), flat(profile["clubType"]))
            add(text("publisherPricing.members"), flat(profile["memberCount"]).map { $0 + text("publisherPricing.people") })
            add(text("publisherPricing.level"), flat(profile["levelText"]))
        } else {
            add(text("publisherPricing.category"), flat(profile["sysCategoryList"]))
            add(text("publisherPricing.capacity"), flat(profile["capacity"]).map { $0 + text("publisherPricing.people") })
            add(text("publisherPricing.suitableRoutes"), flat(profile["suitActivityTypes"]))
            add(text("publisherPricing.availableTimes"), flat(profile["availableTime"]))
            if let charge = profile["chargeType"] { add(text("publisherPricing.charging"), flat(charge) == "1" ? text("publisherPricing.paidHosting") : text("publisherPricing.freeHosting")) }
            add(text("publisherPricing.partnershipNeeds"), flat(profile["demand"]))
            add(text("publisherPricing.openingHours"), flat(profile["businessTime"]))
            add(text("publisherPricing.address"), flat(profile["address"]))
        }
        return rows
    }
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    private func text(_ key: String) -> String { appLocalized(String.LocalizationValue(key), locale: locale) }
}
@MainActor struct PublisherCancellationView: View {
    let resource: PublishedResource; let coordinator: PublisherLifecycleCoordinator
    @State private var reason = ""; @State private var review: PublisherLifecycleReview?
    @State private var message = ""; @State private var busy = false
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        Form {
            Text(zh ? "主办方取消并退款，无法撤销。原因将展示给玩家。" : "Organizer cancellation and refunds are irreversible. The reason is shown to players.")
            TextField(zh ? "取消原因" : "Cancellation reason", text: $reason, axis: .vertical).accessibilityIdentifier("publisher.cancelReason")
            Button(zh ? "查看退款影响" : "Preview refund impact") { Task {
                busy = true; defer { busy = false }
                do { review = try await coordinator.prepare(.cancel(resource, reason: reason, scope: nil)); message = "" }
                catch { message = PublisherLifecycleCopy.error(error, zh: zh) }
            } }.disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("publisher.refundPreview")
            if let review, let count = review.paidPlayers {
                Text(zh ? "将给 \(count) 位已付款玩家全额退款。" : "Full refunds will be issued to \(count) paid players.").accessibilityIdentifier("publisher.paidPlayers")
                Text(resource.kind == .topic ? (zh ? "主题停售，名下场次一并取消；已核销票不自动退款。" : "Topic sales stop and its sessions are cancelled; redeemed tickets are not automatically refunded.") : (zh ? "活动下架，玩家无法报名或进入。" : "The activity is removed from sale; players cannot register or enter."))
                Text(reason)
                Button(zh ? "确认取消并退款" : "Confirm cancellation and refunds", role: .destructive) { Task {
                    busy = true; let outcome = await coordinator.confirm(review, consequentialApproval: true)
                    message = PublisherLifecycleCopy.outcome(outcome, zh: zh); self.review = nil; busy = false
                } }.disabled(busy).accessibilityIdentifier("publisher.confirmRefund")
            }
            Text(message)
        }.navigationTitle(zh ? "取消并退款" : "Cancel and refund")
        .onChange(of: reason) { _, _ in clear() }.onDisappear { clear() }
        .onChange(of: phase) { _, value in if value != .active { clear() } }
    }
    private func clear() { review = nil; coordinator.invalidate() }
}
/// Use for selected eligible club or current topic beta action. No arbitrary identity editor.
@MainActor struct PublisherOwnershipReviewView: View {
    let action: PublisherLifecycleAction; let coordinator: PublisherLifecycleCoordinator
    @State private var review: PublisherLifecycleReview?; @State private var message = ""; @State private var busy = false
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        Form {
            if case .transfer(let topic, let club) = action {
                Text("#\(topic) → #\(club)")
                Text(zh ? "为俱乐部复制新草稿，原主题下架；发起人保留内容所有权，俱乐部只能组织带队。" : "Create a new club draft and take the original topic offline. The initiator retains content ownership; the club organizes only.")
            } else { Text(zh ? "永久移除 Beta 标识，无法撤销。" : "Permanently remove the Beta designation. This cannot be undone.") }
            Button(zh ? "刷新并审阅" : "Refresh and review") { Task { busy = true; defer { busy = false }; do { review = try await coordinator.prepare(action) } catch { message = PublisherLifecycleCopy.error(error, zh: zh) } } }.disabled(busy)
            if let review {
                Button(zh ? "确认此操作" : "Confirm this action", role: .destructive) { Task { busy = true; let result = await coordinator.confirm(review, consequentialApproval: true); message = PublisherLifecycleCopy.outcome(result, zh: zh); self.review = nil; busy = false } }.disabled(busy).accessibilityIdentifier("publisher.confirmOwnership")
            }
            Text(message)
        }.onDisappear { coordinator.invalidate(); review = nil }
        .onChange(of: phase) { _, value in if value != .active { coordinator.invalidate(); review = nil } }
    }
}
@MainActor struct PublisherXPBudgetSection: View {
    let topicID: Int; let client: PublisherLifecycleHTTP
    @State private var budget: PublisherXPBudget?; @State private var message = ""
    @Environment(\.locale) private var locale
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        Section("XP") {
            if let budget {
                Text("\(budget.totalXP.map(String.init) ?? "—") / \(budget.budget.map(String.init) ?? "—")")
                Text(zh ? "通关奖励：\(budget.remain.map(String.init) ?? "—")" : "Completion reward: \(budget.remain.map(String.init) ?? "—")")
                Text(budget.over.map { $0 ? (zh ? "服务器：超预算" : "Server: over budget") : (zh ? "服务器：未超预算" : "Server: within budget") } ?? (zh ? "预算状态未知" : "Budget status unknown"))
                ForEach(budget.nodes) { node in Text("\(node.name ?? "#\(node.id)"): \(node.xp.map(String.init) ?? "—")") }
            }
            Text(message)
        }.accessibilityIdentifier("publisher.xpBudget")
        .task(id: topicID) { do { budget = try await client.budget(topicID: topicID) } catch { message = PublisherLifecycleCopy.error(error, zh: zh) } }
    }
}
enum PublisherLifecycleCopy {
    static func error(_ error: Error, zh: Bool) -> String {
        if case PublisherLifecycleError.rejected(let message) = error, !message.isEmpty { return message }
        return zh ? "未能核实信息，操作未提交。请刷新；真实操作尚未启用。" : "Information could not be verified. No operation submitted. Refresh; live actions remain disabled."
    }
    static func outcome(_ outcome: PublisherLifecycleOutcome, zh: Bool) -> String {
        switch outcome {
        case .acknowledged(let message, let id): return (message ?? (zh ? "服务器已接收，请刷新核实。" : "Server acknowledged; refresh to verify.")) + (id.map { " #\($0)" } ?? "")
        case .rejected(let message): return message
        case .notSent: return zh ? "未发送。授权关闭或审阅已过期。" : "Not sent. Authorization is disabled or review expired."
        case .unknown: return zh ? "结果未知。请核对服务器状态，勿重复提交。" : "Outcome unknown. Check server state; do not resubmit."
        }
    }
}
