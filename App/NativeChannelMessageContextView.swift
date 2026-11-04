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
    var body:some View {
        List {
            Section {
                Text("原消息上下文 · 只读，不改变未读")
                Text("重新进入会从原权限与原消息重新读取；搜索摘要不作为正文或发送证明。") .font(.caption)
                Text("附件仅进入原预览入口；仍需其独立授权、审核与当前有效来源。") .font(.caption)
                Button("从原消息重新读取") {open()}.disabled(model.loading || phase != .active)
            }
            if !model.isCurrent {Text("当前会话权限不可用，正文已隐藏").nativeChannelNotice(systemImage: "lock")}
            else if let page=model.page {
                if page.older.has_more,let cursor=page.older.next_cursor,let id=NativeChannelMessageID(rawValue:cursor) {
                    Button("读取更早的原上下文") {open(id)}
                }
                Section("原消息之前") {ForEach(page.older.list,id:\.id){row in line(row)}}
                Section("当前定位原消息") {line(page.anchor)}
                Section("原消息之后") {ForEach(page.newer.list,id:\.id){row in line(row)}}
                if page.newer.has_more,let cursor=page.newer.next_after,let id=NativeChannelMessageID(rawValue:cursor) {
                    Button("读取更新的原上下文") {open(id)}
                }
            } else if model.failed {Text("原消息可能已撤回、不可见或读取失败；未当作没有搜索结果。").nativeChannelNotice(systemImage: "exclamationmark.circle")}
            if model.loading {ProgressView()}
        }.nativeChannelScreen().listStyle(.insetGrouped).navigationTitle("原消息定位").privacySensitive()
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
        VStack(alignment:.leading) {
            Text("原消息 "+row.id.rawValue).font(Theme.Font.label).foregroundStyle(.secondary).monospacedDigit()
            NativeChannelMessageBubbleView(snapshot:row,isCurrent:{model.containsCurrent(row)},
                locateOriginal:{open($0)},
                videoOwner:expanded?.videoCoordinator?(row.message.conversationID),
                fileOwner:expanded?.fileCoordinator?(row.message.conversationID),
                voiceOwner:expanded?.voiceCoordinator?(row.message.conversationID),
                attachmentPreview:expanded?.attachmentPreview?(row.message),pollCoordinator:expanded?.pollCoordinator)
        }
    }
}
