import SwiftUI

@MainActor struct NativeChannelMessageRevisionView: View {
    let client: any NativeChannelMessageAccess
    let messageID: NativeChannelMessageID
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [NativeChannelMessageRevision] = []
    @State private var cursor: Int64?
    @State private var hasMore = false
    @State private var loading = false
    @State private var failed = false
    @State private var identity: MessagingReadIdentity?
    @State private var generation = 0
    var body: some View {
        List {
            if phase == .active && identity != nil && client.identity == identity && client.allows(.revisions) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: Theme.Space.s1) {
                        Text("d7.channelRevisions.version \(row.revision_no)").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        if let content = row.content { Text(verbatim: content).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                        else { Text("message.unavailable", tableName: "NativeChannelMessage").foregroundStyle(.secondary) }
                    }
                }
                if hasMore { Button { Task { await load() } } label: { Text("search.more", tableName: "NativeChannelMessage") }.disabled(loading) }
                if rows.isEmpty && !loading && !failed && !hasMore {
                    ContentUnavailableView { Label("d7.channelRevisions.empty", systemImage: "clock.arrow.circlepath") }
                }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if failed {
                Label { Text("load.failed", tableName: "NativeChannelMessage") } icon: { Image(systemName: "exclamationmark.triangle") }
                Button { Task { await load() } } label: { Text("messaging.retry") }
                    .disabled(phase != .active || loading || identity == nil || client.identity != identity || !client.allows(.revisions))
                    .accessibilityIdentifier("ncm47.revisions.retry")
            }
        }.nativeChannelScreen().listStyle(.insetGrouped)
        .navigationTitle(Text("revisions.title", tableName: "NativeChannelMessage"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.done") { dismiss() } } }
        .task(id: phase) {
            clear()
            guard phase == .active else { return }
            identity = client.identity
            await load()
        }
        .onChange(of: client.identity) { _, _ in clear() }
        .onDisappear(perform: clear).privacySensitive()
    }
    private func clear() { generation += 1; rows = []; identity = nil; cursor = nil; hasMore = false; loading = false; failed = false }
    private func load() async {
        guard phase == .active, !Task.isCancelled, !loading, let identity, client.identity == identity, client.allows(.revisions) else { return }
        let run = generation, requested = cursor; loading = true; failed = false
        defer { if generation == run { loading = false } }
        do {
            let page = try await client.revisions(messageID: messageID, cursor: requested)
            guard generation == run, client.identity == identity, client.allows(.revisions), !Task.isCancelled else { return }
            let ids = Set(rows.map(\.id)); rows += page.list.filter { !ids.contains($0.id) }
            cursor = page.next_cursor.flatMap(Int64.init); hasMore = page.has_more
        } catch { if generation == run { failed = true; if !client.allows(.revisions) { clear() } } }
    }
}
