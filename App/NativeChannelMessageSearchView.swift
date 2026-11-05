import SwiftUI

@MainActor struct NativeChannelMessageSearchView: View {
    @Bindable var model: NativeChannelMessageSearch
    @State private var keyword = ""
    @State private var author = ""
    @State private var from = ""
    @State private var to = ""
    @State private var invalidFilter = false
    @State private var readTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var phase
    @Environment(\.themeDomain) private var domain
    @Environment(\.dynamicTypeSize) private var typeSize
    var locateOriginal: ((NativeChannelMessageID) -> Void)?
    private var groups: [(String, [NativeChannelMessageSnapshot])] {
        var keys: [String] = []; var grouped: [String: [NativeChannelMessageSnapshot]] = [:]
        for row in model.rows {
            let date = row.message.createdAt ?? ""
            let key = date.range(of: "^\\d{4}-\\d{2}-\\d{2}", options: .regularExpression).map { String(date[$0]) } ?? "—"
            if grouped[key] == nil { keys.append(key) }; grouped[key, default: []].append(row)
        }
        return keys.map { ($0, grouped[$0] ?? []) }
    }
    var body: some View {
        List {
            Section { VStack(alignment: .leading, spacing: Theme.Space.s1) { Text("search.channel", tableName: "NativeChannelMessage"); Text(verbatim: model.channelID).font(Theme.Font.label).monospacedDigit().fixedSize(horizontal: false, vertical: true) } }
            Section {
                TextField("", text: $author, prompt: Text("search.author", tableName: "NativeChannelMessage")).keyboardType(.numberPad)
                    .accessibilityLabel(Text("search.author", tableName: "NativeChannelMessage"))
                TextField("", text: $from, prompt: Text("search.from", tableName: "NativeChannelMessage"))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel(Text("search.from", tableName: "NativeChannelMessage"))
                TextField("", text: $to, prompt: Text("search.to", tableName: "NativeChannelMessage"))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel(Text("search.to", tableName: "NativeChannelMessage"))
                Text("search.timezone", tableName: "NativeChannelMessage").font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain))
                Button { search() } label: { Text("search.run", tableName: "NativeChannelMessage") }
                    .nativeChannelPrimaryAction()
                if invalidFilter { Text("search.invalid", tableName: "NativeChannelMessage").foregroundStyle(Theme.Color.danger(in: domain)).nativeChannelNotice(systemImage: "exclamationmark.circle") }
            }
            if model.isCurrent {
                if let oldest = model.oldestSearchableAt {
                    Section { VStack(alignment: .leading, spacing: Theme.Space.s1) { Text("search.retention", tableName: "NativeChannelMessage"); Text(verbatim: oldest).font(Theme.Font.label).fixedSize(horizontal: false, vertical: true) } }
                }
                if let reason = model.degradedReason {
                    Section {
                        Text("search.degraded", tableName: "NativeChannelMessage")
                        Text(LocalizedStringKey(degradationKey(reason)), tableName: "NativeChannelMessage").font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain))
                    }
                }
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1, id: \.id) { row in
                            Button { if model.isCurrent { locateOriginal?(row.id) } } label: { Text(verbatim: row.content ?? "").lineLimit(typeSize.isAccessibilitySize ? nil : 4).fixedSize(horizontal: false, vertical: true) }
                                .disabled(locateOriginal == nil).accessibilityIdentifier("ncm47.search.\(row.id.rawValue)")
                        }
                    }
                }
                if model.rows.isEmpty && model.query != nil && !model.loading && !model.failed { Text("search.empty", tableName: "NativeChannelMessage").nativeChannelNotice(systemImage: "magnifyingglass") }
                if model.hasMore { Button { more() } label: { Text("search.more", tableName: "NativeChannelMessage") }.disabled(model.loading) }
            } else { Text("access.closed", tableName: "NativeChannelMessage").nativeChannelNotice(systemImage: "lock") }
            if model.loading { ProgressView() }
            if model.failed {
                Text("load.failed", tableName: "NativeChannelMessage").foregroundStyle(Theme.Color.danger(in: domain))
                Button { search() } label: { Text("search.run", tableName: "NativeChannelMessage") }
                    .disabled(!model.isCurrent || model.loading || phase != .active)
            }
        }
        .nativeChannelScreen()
        .tint(Theme.Color.accent(in: domain))
        .searchable(text: $keyword, prompt: Text("search.keyword", tableName: "NativeChannelMessage"))
        .onSubmit(of: .search, search)
        .onChange(of: keyword) { _, _ in retireRead() }
        .onChange(of: author) { _, _ in retireRead() }
        .onChange(of: from) { _, _ in retireRead() }
        .onChange(of: to) { _, _ in retireRead() }
        .onChange(of: phase) { _, value in if value != .active { retireRead() } }
        .onChange(of: model.isCurrent) { _, value in if !value { retireRead() } }
        .navigationTitle(Text("search.title", tableName: "NativeChannelMessage"))
        .onDisappear { retireRead() }
        .privacySensitive()
    }
    private func search() {
        guard phase == .active, model.isCurrent else { retireRead(); return }
        readTask?.cancel()
        let member = author.isEmpty ? nil : NativeChannelMessageID(rawValue: author)
        guard author.isEmpty || member != nil else { invalidFilter = true; model.retire(); return }
        let query = NativeChannelMessageQuery(keyword: keyword, from: from.isEmpty ? nil : from, to: to.isEmpty ? nil : to, authorID: member)
        do { try query.validate() }
        catch { invalidFilter = true; model.retire(); return }
        invalidFilter = false
        readTask = Task { await model.replace(query) }
    }
    private func more() {
        guard phase == .active, model.isCurrent else { retireRead(); return }
        readTask?.cancel()
        readTask = Task { await model.more() }
    }
    private func retireRead() {
        readTask?.cancel(); readTask = nil; model.retire()
    }
    private func degradationKey(_ reason: String) -> String {
        switch reason {
        case "SHORT_KEYWORD_LIKE": return "search.shortKeyword"
        case "RETENTION_BOUNDARY": return "search.retentionClipped"
        case "SHORT_KEYWORD_AND_RETENTION_BOUNDARY": return "search.shortAndClipped"
        default: return "search.degraded"
        }
    }
}
