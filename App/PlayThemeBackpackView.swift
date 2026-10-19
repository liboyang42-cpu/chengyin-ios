import SwiftUI

/// 背包 (mini-program theme backpack), read-only: load, values, items, pending rewards, clues
/// and zero-HP status. Every action (use, discard, receive, plans, trade, recovery) stays unported.
@MainActor struct PlayThemeBackpackView: View {
    @Bindable var model: PlayThemeBackpackCoordinator
    @State private var tab = Tab.items
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
            if let bag = model.backpack { content(bag) }
        }
        .navigationTitle(Text("playx.backpack.title"))
        .accessibilityIdentifier("playx.backpack")
        .refreshable { await model.refresh() }
        .task { if model.backpack == nil { await model.refresh() } }
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
