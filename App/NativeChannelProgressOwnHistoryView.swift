import SwiftUI

@MainActor struct NativeChannelProgressOwnHistoryView: View {
    @Bindable var model: NativeChannelProgressCoordinator
    @StateObject private var actions = NativeChannelProgressActionLifetime()
    var body: some View {
        List {
            if !model.isCurrent { Text("d7.channelProgress.closed", tableName: "NativeChannelProgress") }
            if model.busy { ProgressView() }
            Section {
                if let best = model.best { NativeChannelProgressRowView(row: best) }
                else if !model.busy && model.issue("best") == nil { Text(verbatim: "—").foregroundStyle(.secondary) }
                NativeChannelProgressIssueView(model: model, part: "best")
            } header: { Text("best", tableName: "NativeChannelProgress") }
            Section {
                if let page = model.recent.page {
                    if !page.visible { Text("d7.channelProgress.hidden", tableName: "NativeChannelProgress").foregroundStyle(.secondary) }
                    else {
                        if model.recent.rows.isEmpty { Text("d7.channelProgress.emptyHistory", tableName: "NativeChannelProgress").foregroundStyle(.secondary) }
                        ForEach(Array(model.recent.rows.enumerated()), id: \.offset) { _, row in NativeChannelProgressRowView(row: row) }
                        if page.nextCursor != nil { Button { actions.run { await model.loadMore(history: true) } } label: { Text("more", tableName: "NativeChannelProgress") }.disabled(model.busy) }
                    }
                }
                NativeChannelProgressIssueView(model: model, part: "recent")
            } header: { Text("d7.channelProgress.recent", tableName: "NativeChannelProgress") }
        }.nativeChannelScreen().navigationTitle(Text("d7.channelProgress.historyTitle", tableName: "NativeChannelProgress")).privacySensitive()
        .onAppear { actions.activate() }
        .onDisappear { actions.retire() }
        .onChange(of: model.isCurrent) { _, current in if !current { actions.retire() } }
        .task { await model.refreshOwnHistory() }
        .refreshable { await model.refreshOwnHistory() }
        .accessibilityIdentifier("channelProgress.ownHistory")
    }
}
