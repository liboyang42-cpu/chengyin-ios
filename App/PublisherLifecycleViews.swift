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
                Text(text("Live pricing is disabled until independently approved. Confirming a price opens sales and freezes partner terms.", "真实定价需独立批准后启用。确认终价将开售并冻结合作条款。"))
                Picker(text("Format", "玩法"), selection: $subtype) {
                    Text(text("Self-guided", "自玩")).tag(PublisherPriceSubtype.selfPlay)
                    Text(text("Guided", "带队")).tag(PublisherPriceSubtype.guided)
                }.accessibilityIdentifier("publisher.subtype")
                if subtype == .guided {
                    TextField(text("Lead cost", "带队成本"), text: $cost).keyboardType(.decimalPad)
                    TextField(text("Team size", "成团人数"), text: $team).keyboardType(.numberPad)
                }
                Button(text("Refresh price floor", "刷新价格地板")) { Task { await load() } }.disabled(busy).accessibilityIdentifier("publisher.preview")
            }
            if let preview {
                Section(text("Server pricing", "服务器定价")) {
                    LabeledContent(text("Minimum price", "最低价"), value: NSDecimalNumber(decimal: preview.minimum).stringValue)
                    if let reference = preview.reference, let count = preview.sampleSize, count > 0 {
                        Text("\(preview.referenceLabel ?? "") · \(NSDecimalNumber(decimal: reference).stringValue) · \(count)")
                    } else { Text(text("Insufficient reference samples", "参考样本不足")) }
                    TextField(text("Final price", "终价"), text: $price).keyboardType(.decimalPad).accessibilityIdentifier("publisher.finalPrice")
                    ForEach(preview.lineup) { row in
                        NavigationLink {
                            PublisherPartnerView(topicID: topicID, row: row, client: client)
                        } label: { Text("\(row.type) #\(row.partnerID) · \(row.shareRate ?? row.fixedFee ?? "—")") }
                    }
                    Button(text("Review opening sales", "审阅开售")) { Task { await prepare() } }.disabled(busy).accessibilityIdentifier("publisher.reviewPrice")
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
        .navigationTitle(text("Pricing", "定价"))
        .onChange(of: subtype) { _, _ in invalidate() }
        .onChange(of: cost) { _, _ in invalidate() }
        .onChange(of: team) { _, _ in invalidate() }
        .onChange(of: price) { _, _ in review = nil; coordinator.invalidate() }
        .onChange(of: phase) { _, value in if value != .active { invalidate() } }
        .onDisappear { invalidate() }
    }
    private var isChinese: Bool { locale.language.languageCode?.identifier == "zh" }
    private func input() throws -> PublisherPricingInput { try .init(topicID: topicID, subtype: subtype, leadCost: Decimal(string: cost), teamSize: Int(team)) }
    private func invalidate() { generation = UUID(); preview = nil; review = nil; coordinator.invalidate() }
    private func load() async {
        let stamp = generation; busy = true; defer { busy = false }
        do { let result = try await client.pricing(input()); guard generation == stamp else { return }; preview = result; price = NSDecimalNumber(decimal: result.minimum).stringValue; message = "" }
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
    @Environment(\.locale) private var locale
    var body: some View {
        List {
            if let result {
                Text(result.profile.object?["name"]?.text ?? "—").font(.headline)
                Text(result.profile.object?["description"]?.text ?? "")
                if result.terms.mode == 1 { Text("\(result.terms.shareRate ?? "—")%") }
                else if result.terms.mode == 2 { Text("¥\(result.terms.fixedFee ?? "—") / \(zh ? "人" : "redeemed player")") }
                else { Text(zh ? "引流型，无现金分成" : "Referral mode, no cash share") }
                Text(zh ? "开售后条款冻结；分成按实际票款，固定费用按实际核销人头；引流不产生现金分成。" : "Terms freeze when sales open. Revenue share uses actual ticket revenue; fixed fees use actual redeemed attendance; referral mode has no cash share.")
            }
            if !message.isEmpty { Text(message) }
        }.accessibilityIdentifier("publisher.partner")
        .task { do { result = try await client.partner(topicID: topicID, type: row.type, id: row.partnerID) } catch { message = PublisherLifecycleCopy.error(error, zh: zh) } }
    }
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
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
