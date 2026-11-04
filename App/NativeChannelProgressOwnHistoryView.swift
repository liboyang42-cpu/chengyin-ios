import SwiftUI

@MainActor struct NativeChannelProgressOwnHistoryView: View {
    @Bindable var model: NativeChannelProgressCoordinator
    @StateObject private var actions = NativeChannelProgressActionLifetime()
    var body: some View {
        List {
            if !model.isCurrent { Text("closed", tableName: "NativeChannelProgress") }
            if model.busy { ProgressView() }
            Section {
                if let best = model.best { NativeChannelProgressRowView(row: best) }
                NativeChannelProgressIssueView(model: model, part: "best")
            } header: { Text("best", tableName: "NativeChannelProgress") }
            Section {
                if let page = model.recent.page {
                    if !page.visible { Text("hidden", tableName: "NativeChannelProgress") }
                    else {
                        if model.recent.rows.isEmpty { Text("emptyHistory", tableName: "NativeChannelProgress") }
                        ForEach(Array(model.recent.rows.enumerated()), id: \.offset) { _, row in NativeChannelProgressRowView(row: row) }
                        if page.nextCursor != nil { Button { actions.run { await model.loadMore(history: true) } } label: { Text("more", tableName: "NativeChannelProgress") }.disabled(model.busy) }
                    }
                }
                NativeChannelProgressIssueView(model: model, part: "recent")
            } header: { Text("recent", tableName: "NativeChannelProgress") }
        }.nativeChannelScreen().navigationTitle(Text("ownHistory", tableName: "NativeChannelProgress")).privacySensitive()
        .onAppear { actions.activate() }
        .onDisappear { actions.retire() }
        .onChange(of: model.isCurrent) { _, current in if !current { actions.retire() } }
        .task { await model.refreshOwnHistory() }
        .refreshable { await model.refreshOwnHistory() }
        .accessibilityIdentifier("channelProgress.ownHistory")
    }
}
