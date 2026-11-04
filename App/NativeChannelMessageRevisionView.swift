import SwiftUI

@MainActor struct NativeChannelMessageRevisionView: View {
    let client: any NativeChannelMessageAccess
    let messageID: NativeChannelMessageID
    @Environment(\.scenePhase) private var phase
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
                    VStack(alignment: .leading) {
                        Text("v\(row.revision_no)").font(Theme.Font.label).foregroundStyle(.secondary).monospacedDigit()
                        if let content = row.content { Text(verbatim: content).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                        else { Text("message.unavailable", tableName: "NativeChannelMessage") }
                    }
                }
                if hasMore { Button { Task { await load() } } label: { Text("search.more", tableName: "NativeChannelMessage") }.disabled(loading) }
            }
            if loading { ProgressView() }
            if failed {
                Text("load.failed", tableName: "NativeChannelMessage").nativeChannelNotice(systemImage: "exclamationmark.circle")
                Button { Task { await load() } } label: { Text("history.retry", tableName: "NativeChannelMessage") }
                    .disabled(phase != .active || loading || identity == nil || client.identity != identity || !client.allows(.revisions))
                    .accessibilityIdentifier("ncm47.revisions.retry")
            }
        }.nativeChannelScreen().listStyle(.insetGrouped)
        .navigationTitle(Text("revisions.title", tableName: "NativeChannelMessage"))
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
