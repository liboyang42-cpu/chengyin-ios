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
    @State private var review: PublisherLifecycleReview?
    @State private var message = ""
    @State private var busy = false
    @State private var generation = UUID()
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    private func text(_ en: String, _ zh: String) -> String { locale.language.languageCode?.identifier == "zh" ? zh : en }
    var body: some View {
        Form {
            Section {
                Text(text("Live pricing is disabled until independently approved. Confirming a price opens sales and freezes partner terms.", "真实定价需独立批准后启用。确认终价将开售并冻结合作条款。")).font(.footnote)
                // Source chip tabs 有人带 / 无人带.
                Picker(text("Format", "玩法"), selection: $subtype) {
                    Text(text("Guided", "有人带")).tag(PublisherPriceSubtype.guided)
                    Text(text("Self-guided", "无人带")).tag(PublisherPriceSubtype.selfPlay)
                }.pickerStyle(.segmented).accessibilityIdentifier("publisher.subtype")
            }
            if subtype == .guided {
                Section(text("Lead cost", "带队成本")) {
                    TextField(text("Total lead cost for this group", "本团带队总成本"), text: $cost).keyboardType(.decimalPad)
                    TextField(text("Group size", "成团人数"), text: $team).keyboardType(.numberPad)
                    if (Int(team) ?? 0) <= 0 {
                        Text(text("Guided pricing needs a group size above 0, otherwise the lead cost is counted as zero.", "有人带定价需填写成团人数（大于 0），否则带队成本会被算成 0 元")).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            Section {
                Button(subtype == .guided ? text("Recalculate floor", "重新计算地板") : text("Refresh price floor", "刷新价格地板")) { Task { await load() } }
                    .disabled(busy).accessibilityIdentifier("publisher.preview")
                if busy { Text(text("Checking the latest pricing…", "正在核对最新定价…")).font(.caption) }
            }
            if let preview {
                Section(text("Cost floor", "成本地板")) {
                    Text(verbatim: "¥" + NSDecimalNumber(decimal: preview.minimum).stringValue).font(.title2.bold()).accessibilityIdentifier("publisher.floor")
                    Text(text("Platform rate, the initiator's estimated guarantee, revenue-share ratios and fixed costs are included; the final price cannot be lower.", "平台率、发起人预估保底、分成型比例和固定成本已计入；终价不可低于此值。")).font(.caption)
                }
                Section(text("Your final price", "你的终价")) {
                    TextField(text("Final price", "终价"), text: $price).keyboardType(.decimalPad).accessibilityIdentifier("publisher.finalPrice")
                    let floorValue = TopicPricingXcx.initialPrice(floor: preview.minimum)
                    let maximum = TopicPricingXcx.sliderMax(floor: preview.minimum, reference: preview.reference)
                    Slider(value: Binding(get: { Double(price) ?? Double(floorValue) }, set: { price = String(Int($0.rounded())) }),
                           in: Double(floorValue)...Double(max(maximum, floorValue + 1)), step: 1)
                    HStack {
                        Text(verbatim: text("Floor", "地板") + " ¥" + NSDecimalNumber(decimal: preview.minimum).stringValue)
                        Spacer(); Text(verbatim: "¥\(maximum)")
                    }.font(.caption)
                    if let reference = preview.reference, let count = preview.sampleSize, count > 0 {
                        Text(verbatim: text("\(preview.referenceLabel ?? "Local") average for similar listings ¥\(TopicPricingXcx.twoDecimals(NSDecimalNumber(decimal: reference).stringValue) ?? "—") (\(count) samples)",
                                            "\(preview.referenceLabel ?? "同城")同类已开售均价 ¥\(TopicPricingXcx.twoDecimals(NSDecimalNumber(decimal: reference).stringValue) ?? "—")（\(count) 个样本）")).font(.caption)
                    } else { Text(text("Not enough samples; no reference price shown", "样本不足，暂不展示参考价")).font(.caption) }
                    switch TopicPricingXcx.delta(price: Decimal(string: price) ?? preview.minimum, reference: preview.reference, sampleSize: preview.sampleSize) {
                    case .above(let percent)?: Text(verbatim: text("\(percent)% above the local reference", "高于同城参考 \(percent)%")).font(.caption).foregroundStyle(.orange)
                    case .notAbove?: Text(text("Not above the local reference price", "未高于同城参考价")).font(.caption)
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
                                    Text(row.type == "club" ? text("Partner club", "合作俱乐部") : text("Hosting merchant", "承接商家"))
                                    Text(verbatim: termsText(row)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: { Text(text("Partner lineup", "合作阵容")) } footer: {
                        Text(text("The lineup is locked. Open a partner to see its settlement terms for this topic.", "阵容已锁定，点开可查该合作方在本主题中的结算条款。"))
                    }
                }
                Section {
                    Text(text("Anything above the cost floor is the initiator's margin; settlement guarantees only activate for merchants actually redeemed in this run.", "终价高出成本地板的部分就是发起人毛利；结算保底只按本场真实核销商家数激活。")).font(.caption)
                    if preview.canConfirm == false {
                        Text(text("This topic is not in its pricing phase yet: recruitment must end and the lineup must lock before you can confirm a final price and submit for sale review.", "主题还没进入定价阶段：招募结束、合作阵容锁定后，才能确认终价并提交开售审核。")).font(.caption).foregroundStyle(.orange)
                            .accessibilityIdentifier("publisher.phaseBlocked")
                    }
                    Button(text("Confirm final price and submit for sale review", "确认终价并提交开售审核")) { Task { await prepare() } }
                        .disabled(busy || preview.canConfirm == false).accessibilityIdentifier("publisher.reviewPrice")
                }
            }
            if let review {
                Section(text("Review", "审阅")) {
                    Text(text("This exact price will open sales. Partner lineup and settlement terms freeze. A fresh server check must still match.", "此终价将开售，合作阵容和结算条款冻结。提交前必须通过服务器重新核对。"))
                    Text(price).accessibilityIdentifier("publisher.reviewedPrice")
                    Button(text("Confirm opening sales", "确认开售"), role: .destructive) { Task { busy = true; let result = await coordinator.confirm(review, consequentialApproval: true); message = PublisherLifecycleCopy.outcome(result, zh: isChinese); self.review = nil; busy = false } }.disabled(busy).accessibilityIdentifier("publisher.confirmPrice")
                }
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("publisher.message") }
        }
        .navigationTitle(text("Confirm final price", "确认终价"))
        .onChange(of: subtype) { _, _ in invalidate() }
        .onChange(of: cost) { _, _ in invalidate() }
        .onChange(of: team) { _, _ in invalidate() }
        .onChange(of: price) { _, _ in review = nil; coordinator.invalidate() }
        .onChange(of: phase) { _, value in if value != .active { invalidate() } }
        .onDisappear { invalidate() }
    }
    private func termsText(_ row: PublisherLineup) -> String {
        switch TopicPricingXcx.terms(row) {
        case .chapterPerk: return text("Chapter supply · perks", "章节供给 · 给权益")
        case .chapterTraffic: return text("Chapter supply · referral", "章节供给 · 引流")
        case .chapterRevshare(let fee): return text("Chapter supply · ¥\(fee ?? "—") per redemption", "章节供给 · ¥\(fee ?? "—")/核销人次")
        case .share(let rate): return text("Revenue share · \(rate.map { $0 + "%" } ?? "—")", "分成型 · \(rate.map { $0 + "%" } ?? "—")")
        case .fixed(let fee): return text("Fixed · \(fee.map { "¥" + $0 + " per person" } ?? "—")", "固定 · \(fee.map { "¥" + $0 + "/人" } ?? "—")")
        case .traffic: return text("Referral", "引流型")
        }
    }
    private var isChinese: Bool { locale.language.languageCode?.identifier == "zh" }
    private func input() throws -> PublisherPricingInput { try .init(topicID: topicID, subtype: subtype, leadCost: Decimal(string: cost), teamSize: Int(team)) }
    private func invalidate() { generation = UUID(); preview = nil; review = nil; coordinator.invalidate() }
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
                    Text(text("This partner link is no longer valid", "合作链接已失效")).font(.headline)
                    Text(text("Open it again from the topic pricing page.", "合作链接无效或已失效，请从主题定价页重新进入。")).font(.footnote)
                }.accessibilityIdentifier("publisher.partner.invalid")
            } else {
                Text(text("The lineup is locked. These are this partner's settlement terms for the topic.", "阵容已锁定，以下为该合作方在本主题中的结算条款。")).font(.footnote)
                Section {
                    if loading { ProgressView(text("Loading partner information", "合作信息加载中")) }
                    else if let result {
                        let profile = result.profile.object ?? [:]
                        Text(profile["name"]?.text ?? "—").font(.headline)
                        if let description = profile["description"]?.text, !description.isEmpty { Text(description) }
                        let rows = profileRows(profile)
                        if rows.isEmpty { Text(text("No public profile information", "暂无公开档案信息")).foregroundStyle(.secondary) }
                        ForEach(rows, id: \.0) { key, value in LabeledContent(key, value: value) }
                    }
                } header: { Text(isClub ? text("Partner club", "合作俱乐部") : text("Hosting merchant", "承接商家")) }
                if let terms = result?.terms {
                    Section(text("Partnership terms", "合作条款")) {
                        LabeledContent(text("Settlement", "结算方式"), value: terms.mode == 1 ? text("Revenue share", "分成型") : terms.mode == 2 ? text("Fixed", "固定型") : text("Referral", "引流型"))
                        if terms.mode == 1 { LabeledContent(text("Share", "分成比例"), value: "\(terms.shareRate ?? "—")%") }
                        if terms.mode == 2 { LabeledContent(text("Fixed fee", "固定合作费"), value: "¥\(terms.fixedFee ?? "—")" + text(" per person", "/人")) }
                        LabeledContent(text("Frozen", "冻结时间"), value: text("When sales open", "开售即冻结"))
                        Text(terms.mode == 1 ? text("Terms freeze when sales open; settlement shares actual ticket revenue.", "开售后条款冻结，按实际票款参与分成结算。")
                             : terms.mode == 2 ? text("Terms freeze when sales open; settlement counts actual redeemed people.", "开售后条款冻结，按实际核销人头结算。")
                             : text("The lineup freezes when sales open; referral partnerships have no cash share.", "开售后阵容冻结；引流型合作不产生现金分成。")).font(.caption)
                    }
                }
            }
            if !message.isEmpty { Text(message) }
        }.accessibilityIdentifier("publisher.partner")
        .navigationTitle(isClub ? text("Partner club", "合作俱乐部") : text("Hosting merchant", "承接商家"))
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
            add(text("Leader", "主理人"), flat(profile["leaderName"]))
            add(text("City", "所在城市"), flat(profile["city"]) ?? flat(profile["address"]))
            add(text("Club type", "俱乐部类型"), flat(profile["clubType"]))
            add(text("Members", "成员数"), flat(profile["memberCount"]).map { $0 + text(" people", " 人") })
            add(text("Level", "等级"), flat(profile["levelText"]))
        } else {
            add(text("Category", "品类"), flat(profile["sysCategoryList"]))
            add(text("Capacity", "可容纳"), flat(profile["capacity"]).map { $0 + text(" people", " 人") })
            add(text("Suitable routes", "适合路线"), flat(profile["suitActivityTypes"]))
            add(text("Available times", "可承接时段"), flat(profile["availableTime"]))
            if let charge = profile["chargeType"] { add(text("Charging", "收费方式"), flat(charge) == "1" ? text("Paid hosting", "收费承接") : text("Free hosting", "免费承接")) }
            add(text("Partnership needs", "合作诉求"), flat(profile["demand"]))
            add(text("Opening hours", "营业时间"), flat(profile["businessTime"]))
            add(text("Address", "门店地址"), flat(profile["address"]))
        }
        return rows
    }
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    private func text(_ en: String, _ chinese: String) -> String { zh ? chinese : en }
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
