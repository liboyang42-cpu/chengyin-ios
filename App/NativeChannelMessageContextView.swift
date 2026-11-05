import SwiftUI

struct NativeChannelContextSelection: Identifiable {let id:NativeChannelMessageID}

/// The sheet owns the current original source across child preview navigation.
/// A pushed media screen is not departure from this sheet's account/channel scope.
@MainActor struct NativeChannelMessageContextEntry: View {
    @State var model:NativeChannelMessageContext
    var expanded:((NativeChannelMessageContext)->IMExpandedNavigationContext?)?
    @Environment(\.scenePhase) private var phase
    var body:some View {
        NavigationStack {
            NativeChannelMessageContextView(model:model,expanded:expanded?(model))
        }
        .presentationDragIndicator(.visible)
        .task(id:phase) {
            guard phase == .active else {model.retire();return}
            await model.open()
            while !Task.isCancelled {
                do{try await Task.sleep(nanoseconds:8_000_000_000)}catch{return}
                guard model.isCurrent else {model.retire();return}
                if !model.loading {await model.refresh()}
            }
        }
        .onDisappear{model.retire()}
        .onChange(of:model.isCurrent){_,value in if !value{model.retire()}}
        .privacySensitive()
    }
}

@MainActor struct NativeChannelMessageContextView: View {
    @Bindable var model:NativeChannelMessageContext
    var expanded:IMExpandedNavigationContext?
    @State private var readTask:Task<Void,Never>?
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        List {
            if !model.isCurrent {
                ContentUnavailableView { Label("d7.channelContext.unavailable", systemImage: "lock") }
            }
            else if let page=model.page {
                if page.older.has_more,let cursor=page.older.next_cursor,let id=NativeChannelMessageID(rawValue:cursor) {
                    Button("d7.channelContext.earlier") {open(id)}
                }
                if !page.older.list.isEmpty {
                    Section {ForEach(page.older.list,id:\.id){row in line(row)}} header: { Text("d7.channelContext.before") }
                }
                Section {line(page.anchor)} header: { Text("d7.channelContext.anchor") }
                if !page.newer.list.isEmpty {
                    Section {ForEach(page.newer.list,id:\.id){row in line(row)}} header: { Text("d7.channelContext.after") }
                }
                if page.newer.has_more,let cursor=page.newer.next_after,let id=NativeChannelMessageID(rawValue:cursor) {
                    Button("d7.channelContext.later") {open(id)}
                }
            } else if model.failed {
                ContentUnavailableView {
                    Label("d7.channelContext.failed", systemImage: "exclamationmark.bubble")
                } actions: {
                    Button("messaging.retry") {open()}.disabled(model.loading || phase != .active)
                }
            }
            if model.loading {ProgressView().frame(maxWidth: .infinity)}
        }.nativeChannelScreen().listStyle(.insetGrouped).navigationTitle(Text("d7.channelContext.title")).privacySensitive()
        .refreshable { open(); await readTask?.value }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.done") { dismiss() } } }
        // The enclosing sheet continues its current-source reads while a preview is pushed.
        // Only this view's explicit read task ends here; sheet departure retires the model.
        .onDisappear{readTask?.cancel();readTask=nil}
        .onChange(of:phase){_,value in if value != .active {readTask?.cancel();readTask=nil}}
    }
    private func open(_ id:NativeChannelMessageID?=nil) {
        guard phase == .active,model.isCurrent else{return}
        readTask?.cancel()
        readTask=Task{await model.open(id)}
    }
    @ViewBuilder private func line(_ row:NativeChannelMessageSnapshot)->some View {
        VStack(alignment:.leading,spacing:Theme.Space.s1) {
            Text(verbatim: row.message.senderName ?? "—").font(.footnote).foregroundStyle(.secondary)
            NativeChannelMessageBubbleView(snapshot:row,isCurrent:{model.containsCurrent(row)},
                locateOriginal:{open($0)},
                videoOwner:expanded?.videoCoordinator?(row.message.conversationID),
                fileOwner:expanded?.fileCoordinator?(row.message.conversationID),
                voiceOwner:expanded?.voiceCoordinator?(row.message.conversationID),
                attachmentPreview:expanded?.attachmentPreview?(row.message),pollCoordinator:expanded?.pollCoordinator)
        }
    }
}
