import SwiftUI

/// Personal backpack keeps the existing read projection and adds explicit native review.
/// TEAM, trade, plans, chapter actions and zero-HP writes remain outside this page.
@MainActor struct PlayThemeBackpackView: View {
    @Bindable var model: PlayThemeBackpackCoordinator
    @State private var tab = Tab.items
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: ActionSelection?
    @State private var discardQuantities: [String: Int] = [:]
    @State private var actionError: String?
    private struct ActionSelection: Identifiable {
        let id = UUID()
        let operation: PlayThemeBackpackOperation
        let contentID: String
        let name: String
        let sessionID: Int
        let version: Int
    }
    enum Tab: String, CaseIterable { case items, clues, game }

    var body: some View {
        List {
            switch model.phase {
            case .unavailable: Text("playx.backpack.unavailable").accessibilityIdentifier("playx.backpack.unavailable")
            case .failed(let message):
                Group { if let message { Text(verbatim: message) } else { Text("playx.backpack.failed") } }
                    .accessibilityIdentifier("playx.backpack.failed")
                Button("playx.backpack.retry") { Task { await model.refresh() } }.accessibilityIdentifier("playx.backpack.retry")
            case .loading where model.backpack == nil: ProgressView("playx.loading")
            default: EmptyView()
            }
            if let actions = model.actions { actionStatus(actions) }
            if let bag = model.displayedBackpack { content(bag) }
        }
        .navigationTitle(Text("playx.backpack.title"))
        .accessibilityIdentifier("playx.backpack")
        .refreshable { await model.refresh() }
        .task {
            model.actions?.activate()
            if model.actions != nil || model.backpack == nil { await model.refresh() }
        }
        .onDisappear {
            selection = nil; discardQuantities = [:]; actionError = nil
            model.actions?.suspend()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.actions?.activate()
                Task { await model.refresh() }
            } else {
                selection = nil; discardQuantities = [:]; actionError = nil
                model.actions?.suspend()
            }
        }
        .sheet(item: $selection, onDismiss: { discardQuantities = [:]; actionError = nil }) { choice in
            actionReview(choice)
        }
    }

    @ViewBuilder private func content(_ bag: PlayThemeBackpack) -> some View {
        Section {
            LabeledContent { Text("playx.backpack.slots \(bag.used) \(bag.capacity)") } label: { Text("playx.backpack.load") }
                .accessibilityIdentifier("playx.backpack.load")
            ForEach(bag.values, id: \.key) { row in
                LabeledContent {
                    Text(verbatim: row.max.map { "\(row.value) / \($0)" } ?? row.value)
                } label: {
                    HStack { name(row.name); if row.zero { Text("playx.backpack.zero").foregroundStyle(.red) } }
                }
                .accessibilityIdentifier("playx.backpack.value.\(row.key)")
            }
        }
        if let zero = bag.zeroHP { zeroSection(zero, hp: bag.values.first { $0.key == "hp" }?.name ?? .hp) }
        Picker("playx.backpack.tabs", selection: $tab) {
            Text("playx.backpack.tab.items").tag(Tab.items)
            Text("playx.backpack.tab.clues").tag(Tab.clues)
            Text("playx.backpack.tab.game").tag(Tab.game)
        }
        .pickerStyle(.segmented).accessibilityIdentifier("playx.backpack.tabs")
        if bag.claimOnly { Text("playx.backpack.claimOnly").font(.footnote) }
        switch tab {
        case .items:
            if !bag.pending.isEmpty {
                Section("playx.backpack.pending") {
                    ForEach(bag.pending) { row in
                        VStack(alignment: .leading) {
                            if let n = row.name { Text(verbatim: n) } else { Text("playx.backpack.pendingReward") }
                            HStack(spacing: 4) {
                                if let q = row.quantity { Text(verbatim: "×\(q)") }
                                if let slots = row.slots { Text("playx.backpack.takesSlots \(slots)") }
                            }.font(.caption)
                            if let actions = model.actions {
                                Button(copy("领取", "Receive")) {
                                    openReview(.receive, id: row.id, name: row.name ?? copy("待领奖励", "Pending reward"), actions: actions)
                                }
                                .disabled(!canSelect(.receive, id: row.id, actions: actions))
                                .accessibilityIdentifier("playx.backpack.receive.\(row.id)")
                                if actions.facts?.status == "ACTIVE", actions.facts?.hasRoomForPending(row.id) == false {
                                    Text(copy("背包已满或容量信息未确认，请先确认库存。", "The backpack is full or capacity is unconfirmed. Check your inventory first."))
                                        .font(.footnote)
                                }
                            }
                        }
                    }
                }
            }
            if !bag.items.isEmpty {
                Section("playx.backpack.carried") {
                    ForEach(bag.items) { item in
                        HStack {
                            VStack(alignment: .leading) { name(item.name); effect(item.effect).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            VStack(alignment: .trailing) {
                                if let q = item.quantity { Text(verbatim: "×\(q)") }
                                if let cost = item.slotCost { Text("playx.backpack.perItemSlots \(cost)").font(.caption) }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("playx.backpack.item.\(item.id)")
                        if let actions = model.actions {
                            HStack {
                                Button(copy("使用", "Use")) { openReview(.use, id: item.id, name: itemName(item.name), actions: actions) }
                                    .disabled(!canSelect(.use, id: item.id, actions: actions))
                                    .accessibilityIdentifier("playx.backpack.use.\(item.id)")
                                Button(copy("丢弃", "Discard"), role: .destructive) { openReview(.discard, id: item.id, name: itemName(item.name), actions: actions) }
                                    .disabled(!canSelect(.discard, id: item.id, actions: actions))
                                    .accessibilityIdentifier("playx.backpack.discard.\(item.id)")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            if bag.items.isEmpty, bag.pending.isEmpty { Text("playx.backpack.noItems").accessibilityIdentifier("playx.backpack.noItems") }
        case .clues:
            if bag.clues.isEmpty { Text("playx.backpack.noClues").accessibilityIdentifier("playx.backpack.noClues") }
            ForEach(bag.clues) { clue in
                VStack(alignment: .leading, spacing: 4) {
                    if let n = clue.name { Text(verbatim: n).font(.headline) } else { Text("playx.backpack.clue").font(.headline) }
                    switch clue.scope {
                    case .publicAll: Text("playx.backpack.scope.public").font(.caption)
                    case .team: Text("playx.backpack.scope.team").font(.caption)
                    case .none: EmptyView()
                    }
                    if let content = clue.content { Text(verbatim: content).textSelection(.enabled) }
                    ForEach(Array(clue.blocks.enumerated()), id: \.offset) { _, block in
                        if let source = block.source { Text(verbatim: source).font(.caption).foregroundStyle(.secondary) }
                        if let text = block.text { Text(verbatim: text).textSelection(.enabled) }
                        if block.imageCount > 0 { Text("playx.backpack.clueImages \(block.imageCount)").font(.caption) }
                    }
                }
                .accessibilityIdentifier("playx.backpack.clue")
            }
        case .game:
            Text("playx.backpack.gameUnavailable").accessibilityIdentifier("playx.backpack.gameUnavailable")
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        locale.language.languageCode?.identifier == "zh" ? chinese : english
    }
    private func itemName(_ value: PlayThemeBackpack.ValueName) -> String {
        switch value {
        case .server(let text): return text
        case .hp: return copy("生命值", "Health")
        case .luck: return copy("幸运值", "Luck")
        case .actions: return copy("行动次数", "Actions")
        case .genericNumber: return copy("数值", "Value")
        case .genericSupply: return copy("物资", "Supply")
        }
    }
    private func operationName(_ value: PlayThemeBackpackOperation) -> String {
        switch value { case .use: return copy("使用", "Use"); case .discard: return copy("丢弃", "Discard"); case .receive: return copy("领取", "Receive") }
    }
    private func canSelect(_ operation: PlayThemeBackpackOperation, id: String, actions: PlayThemeBackpackActions) -> Bool {
        actions.canStart && actions.facts?.allows(operation, contentID: id, completedReceiveAccepted: actions.completedReceiveAccepted) == true
    }
    private func openReview(_ operation: PlayThemeBackpackOperation, id: String, name: String, actions: PlayThemeBackpackActions) {
        guard canSelect(operation, id: id, actions: actions), let facts = actions.facts else { return }
        discardQuantities = [:]; actionError = nil
        selection = .init(operation: operation, contentID: id, name: name, sessionID: facts.sessionID, version: facts.version)
    }
    private func reviewIsCurrent(_ choice: ActionSelection, actions: PlayThemeBackpackActions) -> Bool {
        canSelect(choice.operation, id: choice.contentID, actions: actions) &&
            actions.facts?.sessionID == choice.sessionID && actions.facts?.version == choice.version
    }
    @ViewBuilder private func actionStatus(_ actions: PlayThemeBackpackActions) -> some View {
        Section {
            if !actions.isCurrent {
                Text(copy("账号或游玩状态已变化，请返回后重新进入。", "Your account or play session changed. Go back and open this page again."))
                    .accessibilityIdentifier("playx.backpack.action.stale")
            } else {
            switch actions.phase {
            case .idle, .ready, .reviewing: EmptyView()
            case .loading: ProgressView(copy("背包加载中", "Loading backpack"))
            case .sending: ProgressView(copy("正在确认操作结果", "Confirming the result"))
            case .active:
                Text(copy("上一条操作仍在处理中，请刷新确认结果。", "The previous action is still in progress. Refresh to check its result."))
                    .accessibilityIdentifier("playx.backpack.action.active")
            case .unknown:
                Text(copy("操作结果未确认，点击重试", "Result unconfirmed. Retry the original action."))
                    .accessibilityIdentifier("playx.backpack.action.unknown")
                Text(copy("重试会使用同一局、同一操作编号和原始选择，不会创建新操作。", "Retry keeps the same session, action ID and original choices. It does not create a new action."))
                    .font(.footnote)
                Button(copy("重试上一条操作", "Retry original action")) { Task { await actions.recover() } }
                    .disabled(!actions.canRecover).accessibilityIdentifier("playx.backpack.action.recover")
            case .storageUnavailable:
                Text(copy("无法安全保存操作，暂不能提交。请稍后刷新。", "The action cannot be saved safely. Submission is unavailable. Try refreshing later."))
                    .accessibilityIdentifier("playx.backpack.action.storageUnavailable")
            case .unavailable:
                Text(copy("物资操作尚未接通，请稍后再试。", "Inventory actions are not connected yet. Please try later."))
                    .accessibilityIdentifier("playx.backpack.action.unavailable")
            case .stale:
                Text(copy("账号或游玩状态已变化，请返回后重新进入。", "Your account or play session changed. Go back and open this page again."))
                    .accessibilityIdentifier("playx.backpack.action.stale")
            case .failed(let message):
                Text(verbatim: message ?? copy("背包暂未加载，点击重试", "Backpack unavailable. Refresh to try again."))
                    .accessibilityIdentifier("playx.backpack.action.failed")
            }
            if let command = actions.pendingCommand, actions.isCurrent {
                Text(verbatim: operationName(command.operation) + " · " + command.contentId)
                    .font(.footnote).accessibilityIdentifier("playx.backpack.action.original")
            }
            if actions.lastConfirmedOperation == .receive, actions.isCurrent {
                Text(copy("待领奖励已领取", "Pending reward received")).accessibilityIdentifier("playx.backpack.action.received")
            } else if actions.lastConfirmedOperation != nil, actions.isCurrent {
                Text(copy("操作已确认", "Action confirmed")).accessibilityIdentifier("playx.backpack.action.confirmed")
            }
            if actions.facts?.hasReservedSupplies == true {
                Text(copy("当前任务已预留物资，请先完成或取消任务", "The current task has reserved supplies. Complete or cancel it first."))
                    .accessibilityIdentifier("playx.backpack.action.reserved")
            }
            if actions.facts?.status == "COMPLETED", !actions.completedReceiveAccepted {
                Text(copy("本局待领奖励尚未接通安全结算，暂不能领取。", "Safe settlement for this completed session is not connected yet. Rewards cannot be received."))
                    .accessibilityIdentifier("playx.backpack.action.completedUnavailable")
            }
            Button(copy("刷新背包", "Refresh backpack")) { Task { await model.refresh() } }
                .disabled(actions.phase == .sending || actions.phase == .loading)
                .accessibilityIdentifier("playx.backpack.action.refresh")
            }
        }
    }
    private func actionReview(_ choice: ActionSelection) -> some View {
        NavigationStack {
            Form {
                Section {
                    if model.actions?.isCurrent == true {
                        Text(verbatim: choice.name)
                        Text(verbatim: operationName(choice.operation))
                    }
                    if choice.operation == .discard {
                        Text(copy("将丢弃 1 件持有物资，请确认后继续。", "This discards one held item. Confirm to continue."))
                    }
                    if let error = actionError { Text(verbatim: error).foregroundStyle(.red) }
                }
                if let actions = model.actions, actions.isCurrent {
                    if actions.facts?.status == "COMPLETED", choice.operation == .receive,
                       let bag = actions.facts?.backpack {
                        Section(copy("丢弃持有物资", "Discard held supplies")) {
                            Text(copy("可选择丢弃本人持有物资，腾出容量后领取待领奖励。", "You may discard your own held supplies to make space for the pending reward."))
                            ForEach(bag.items) { item in
                                if let quantity = item.quantity, quantity > 0 {
                                    Stepper(value: Binding(get: { discardQuantities[item.id] ?? 0 }, set: { discardQuantities[item.id] = $0 }), in: 0...quantity) {
                                        Text(verbatim: itemName(item.name) + " · " + String(discardQuantities[item.id] ?? 0) + " / " + String(quantity))
                                    }
                                    .disabled(actions.facts?.canDiscardOwned != true || !reviewIsCurrent(choice, actions: actions))
                                    .accessibilityIdentifier("playx.backpack.claim.discard.\(item.id)")
                                }
                            }
                        }
                    }
                    if !reviewIsCurrent(choice, actions: actions) {
                        Text(copy("状态已变化，请关闭后重新确认。", "The state changed. Close this review and confirm again."))
                            .accessibilityIdentifier("playx.backpack.action.reviewStale")
                    }
                    Button(copy("确认", "Confirm"), role: choice.operation == .discard ? .destructive : nil) {
                        guard reviewIsCurrent(choice, actions: actions) else { return }
                        do {
                            let discarded: [PlayThemeBackpackDiscard]? = actions.facts?.status == "COMPLETED" && choice.operation == .receive
                                ? (actions.facts?.backpack.items ?? []).compactMap { item in
                                    let quantity = discardQuantities[item.id] ?? 0
                                    return quantity > 0 ? PlayThemeBackpackDiscard(itemID: item.id, quantity: quantity) : nil
                                } : nil
                            try actions.begin(choice.operation, contentID: choice.contentID, discardOwned: discarded)
                            selection = nil
                            Task { await actions.confirm() }
                        } catch { actionError = copy("状态已变化，请关闭后重新确认。", "The state changed. Close this review and confirm again.") }
                    }
                    .disabled(!reviewIsCurrent(choice, actions: actions))
                    .accessibilityIdentifier("playx.backpack.action.confirm")
                }
            }
            .navigationTitle(copy("确认操作", "Confirm action"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy("取消", "Cancel")) { selection = nil }.accessibilityIdentifier("playx.backpack.action.cancel")
                }
            }
        }
    }

    @ViewBuilder private func zeroSection(_ zero: PlayThemeBackpack.ZeroHP, hp: PlayThemeBackpack.ValueName) -> some View {
        Section {
            Text(LocalizedStringKey("playx.backpack.zeroPolicy." + (zero.policy.flatMap { ["WAIT", "CHALLENGE", "STEPS", "BLOCK_HP_COST", "BLOCK_PAID", "THEME_FAIL"].contains($0) ? $0 : nil } ?? "OTHER")))
                .font(.headline)
            HStack { name(hp); Text("playx.backpack.zero") }
            if let message = zero.message { Text(verbatim: message) }
            if let progress = zero.progress, let required = zero.required {
                ProgressView(value: Double(min(progress, required)), total: Double(required)) { Text(verbatim: "\(progress) / \(required)") }
            }
        }
        .accessibilityIdentifier("playx.backpack.zeroHP")
    }

    private func name(_ value: PlayThemeBackpack.ValueName) -> Text {
        switch value {
        case .server(let text): return Text(verbatim: text)
        case .hp: return Text("playx.themeRecords.hp")
        case .luck: return Text("playx.themeRecords.luck")
        case .actions: return Text("playx.themeRecords.actions")
        case .genericNumber: return Text("playx.backpack.genericNumber")
        case .genericSupply: return Text("playx.backpack.genericSupply")
        }
    }
    private func effect(_ effect: PlayThemeBackpack.Item.Effect) -> Text {
        switch effect {
        case .stat(let stat, let delta): return name(stat) + Text(verbatim: delta > 0 ? " +\(delta)" : " \(delta)")
        case .text(let text): return Text(verbatim: text)
        case .carried: return Text("playx.backpack.carriedSupply")
        }
    }
}
