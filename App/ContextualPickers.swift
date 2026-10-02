import SwiftUI

/// Chooses a topic from the current server catalog. Only its topic ID leaves this sheet;
/// presentation metadata never enters an IM card payload.
@MainActor struct ContextualTopicPicker: View {
    @Environment(\.dismiss) private var dismiss
    let reader: any TopicReading
    let onSelect: (TopicSummary) -> Void
    @State private var keyword = ""
    @State private var rows = TopicPagination()
    @State private var busy = false
    @State private var failed = false
    @State private var loadedScope: UUID?
    @State private var generation = 0
    var body: some View {
        List {
            if busy { ProgressView("topic.loading") }
            if failed { Button("action.retry") { Task { await load(reset: rows.rows.isEmpty) } } }
            if !busy, !failed, rows.rows.isEmpty { Text("context.picker.empty") }
            ForEach(rows.rows) { row in
                Button {
                    guard loadedScope == reader.scope, !busy else { return }
                    onSelect(row); dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(verbatim: row.name)
                        if let detail = row.introduction { Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier("context.route.select.\(row.id)")
            }
            if !rows.rows.isEmpty, rows.hasMore { Button("context.picker.more") { Task { await load(reset: false) } }.disabled(busy) }
        }
        .navigationTitle("context.route.choose").searchable(text: $keyword, prompt: "context.route.search")
        .onSubmit(of: .search) { Task { await load(reset: true) } }
        .onChange(of: keyword) { _, _ in generation += 1; rows.reset(); loadedScope = nil; busy = false; failed = false }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } } }
        .task(id: reader.scope) { await load(reset: true) }
        .onDisappear { generation += 1 }
    }
    private func load(reset: Bool) async {
        if !reset, busy { return }
        generation += 1; let request = generation, scope = reader.scope
        if reset { rows.reset(); loadedScope = nil }
        busy = true; failed = false
        defer { if request == generation { busy = false } }
        do {
            let page = try await reader.topicList(query: .init(keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines)), pageNumber: rows.nextPage)
            guard request == generation, scope == reader.scope, !Task.isCancelled else { return }
            try rows.accept(page); loadedScope = scope
        } catch { if request == generation, scope == reader.scope, !Task.isCancelled { failed = true } }
    }
}

@MainActor struct ProfileRoutePreferencePicker: View {
    @Environment(\.dismiss) private var dismiss
    let reader: (any DiscoveryReading)?
    let currentIdentity: () -> ProfileReadIdentity?
    let onSave: ([Int]) -> Void
    @State private var selection: [Int]
    @State private var categories: [DiscoveryCategory] = []
    @State private var busy = false
    @State private var failed = false
    @State private var loaded = false
    @State private var identity: ProfileReadIdentity?
    @State private var generation = 0
    init(reader: (any DiscoveryReading)?, selected: [Int], currentIdentity: @escaping () -> ProfileReadIdentity?, onSave: @escaping ([Int]) -> Void) {
        self.reader = reader; self.currentIdentity = currentIdentity; self.onSave = onSave
        _selection = State(initialValue: selected)
    }
    var body: some View {
        List {
            if busy { ProgressView("topic.loading") }
            if failed { Button("action.retry") { Task { await load() } } }
            if loaded, categories.isEmpty { Text("context.picker.empty") }
            ForEach(categories) { category in
                Button {
                    if selection.contains(category.id) { selection.removeAll { $0 == category.id } }
                    else { selection.append(category.id) }
                } label: {
                    HStack {
                        Text(verbatim: category.name); Spacer()
                        if selection.contains(category.id) { Image(systemName: "checkmark") }
                    }.frame(minHeight: 44)
                }.accessibilityAddTraits(selection.contains(category.id) ? .isSelected : [])
            }
        }.navigationTitle("context.preferences.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("action.done") {
                    guard loaded, identity != nil, identity == currentIdentity() else { return }
                    onSave(selection); dismiss()
                }.disabled(!loaded || busy || failed) }
            }
            .task { await load() }
            .onDisappear { generation += 1 }
    }
    private func load() async {
        generation += 1; let request = generation; let captured = currentIdentity()
        busy = true; loaded = false; failed = false
        defer { if request == generation { busy = false } }
        do {
            guard let reader, reader.isConfigured, captured != nil else { throw APIError.notConfigured }
            let values = try await reader.discoveryCategories(type: 1)
            guard request == generation, currentIdentity() == captured, !Task.isCancelled else { return }
            guard values.allSatisfy({ $0.id > 0 }), Set(values.map(\.id)).count == values.count else { throw APIError.malformedResponse }
            categories = values; identity = captured; loaded = true
        } catch { if request == generation, currentIdentity() == captured { failed = true } }
    }
}
