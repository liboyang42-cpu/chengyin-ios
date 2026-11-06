import SwiftUI

/// Source "我的游玩记录" sheet: paged history (20 per page) and a per-run result card. Read-only; no replay.
@MainActor struct TopicThemeRecordsView: View {
    let topicID: Int
    let topicName: String
    let reader: any TopicThemeRecordsReading
    @State private var rows: [TopicThemeRecord] = []
    @State private var nextBefore: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var failed = false
    @State private var loadedScope: UUID?
    var body: some View {
        List {
            Section { Text(verbatim: topicName).font(.subheadline).foregroundStyle(.secondary) }
            if loading && rows.isEmpty { ProgressView("topicXcx.records.loading") }
            else if failed && rows.isEmpty {
                Text("topicXcx.records.failed").accessibilityIdentifier("topic.records.failed")
                Button("topicXcx.records.reload") { Task { await load(reset: true) } }
            } else if rows.isEmpty && loadedScope == reader.scope {
                Text("topicXcx.records.empty").accessibilityIdentifier("topic.records.empty")
            }
            ForEach(rows) { row in
                NavigationLink { TopicThemeCardView(sessionID: row.sessionID, reader: reader) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        switch row.title {
                        case .server(let text): Text(verbatim: text).font(.headline)
                        case .completed: Text("topicXcx.records.completed").font(.headline)
                        case .ended: Text("topicXcx.records.ended").font(.headline)
                        case .playing: Text("topicXcx.records.playing").font(.headline)
                        }
                        if let scene = row.sceneName { Text(verbatim: scene).font(.caption) }
                        if let ended = row.endedAt { Text(verbatim: ended).font(.caption).foregroundStyle(.secondary) }
                        else { Text("topicXcx.records.playing").font(.caption).foregroundStyle(.secondary) }
                        if let summary = row.summary { Text(verbatim: summary).font(.footnote).lineLimit(2) }
                    }
                }.accessibilityIdentifier("topic.records.row.\(row.sessionID)")
            }
            if hasMore && !rows.isEmpty {
                Button(failed ? "topicXcx.records.reload" : "topicXcx.records.more") { Task { await load(reset: false) } }
                    .disabled(loading).accessibilityIdentifier("topic.records.more")
            }
        }
        .appNavigationTitle("topicXcx.records.title")
        .task(id: reader.scope) { await load(reset: true) }
        .accessibilityIdentifier("topic.records")
    }
    private func load(reset: Bool) async {
        guard !loading, reader.isConfigured else { return }
        let scope = reader.scope
        loading = true; failed = false
        defer { loading = false }
        do {
            let page = try await reader.themeHistory(topicID: topicID, beforeSessionID: reset ? nil : nextBefore)
            guard scope == reader.scope else { return }
            var seen = Set(reset ? [] : rows.map(\.sessionID))
            rows = (reset ? [] : rows) + page.rows.filter { seen.insert($0.sessionID).inserted }
            hasMore = page.hasMore; nextBefore = page.nextBefore; loadedScope = scope
        } catch is CancellationError { }
        catch { if scope == reader.scope { failed = true; if reset { rows = [] }; loadedScope = scope } }
    }
}

@MainActor struct TopicThemeCardView: View {
    let sessionID: Int
    let reader: any TopicThemeRecordsReading
    @State private var card: TopicThemeCard?
    @State private var failed = false
    var body: some View {
        List {
            if let card {
                Section {
                    if let title = card.title { Text(verbatim: title).font(.title3.bold()) } else { Text("topicXcx.records.cardTitle").font(.title3.bold()) }
                    if let scene = card.scene { LabeledContent { Text(verbatim: scene) } label: { Text("topicXcx.records.scene") } }
                    if let summary = card.summary { Text(verbatim: summary) }
                }
                if !card.values.isEmpty {
                    Section {
                        ForEach(Array(card.values.enumerated()), id: \.offset) { _, row in
                            LabeledContent {
                                Text(verbatim: String(row.value))
                            } label: {
                                if let label = row.label { Text(verbatim: label) } else { Text(LocalizedStringKey("topicXcx.records.value." + row.kind)) }
                            }
                        }
                    }
                }
                quantitySection(card.items, title: "topicXcx.records.items")
                quantitySection(card.medals, title: "topicXcx.records.medals")
                if !card.epilogues.isEmpty {
                    Section("topicXcx.records.epilogues") {
                        ForEach(Array(card.epilogues.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading) { Text(verbatim: row.name).font(.headline); if let line = row.line { Text(verbatim: line) } }
                        }
                    }
                }
                if let next = card.nextScene { Text("topicXcx.records.nextScene \(next)") }
            } else if failed {
                Text("topicXcx.records.cardFailed").accessibilityIdentifier("topic.records.cardFailed")
                Button("topicXcx.records.cardReload") { Task { await load() } }
            } else { ProgressView("topicXcx.records.cardLoading") }
        }
        .task(id: reader.scope) { await load() }
        .accessibilityIdentifier("topic.records.card")
    }
    @ViewBuilder private func quantitySection(_ rows: [TopicThemeCard.Quantity], title: LocalizedStringKey) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    LabeledContent { if let q = row.quantity { Text(verbatim: "×\(q)") } } label: { Text(verbatim: row.name) }
                }
            }
        }
    }
    private func load() async {
        let scope = reader.scope; failed = false
        do { let value = try await reader.themeCard(sessionID: sessionID); if scope == reader.scope { card = value } }
        catch is CancellationError { }
        catch { if scope == reader.scope { failed = true } }
    }
}
