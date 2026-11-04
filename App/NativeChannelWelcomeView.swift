import SwiftUI

/// No member-side editor; destinations reopen the original channel host and its current authority.
@MainActor struct NativeChannelWelcomeEntry:View {
    @ObservedObject var session:AppSession
    let channels:NativeChannelManagementCoordinator
    var parentRouteIsActive: () -> Bool = { false }
    @State private var flow:NativeChannelWelcomeFlow?
    @StateObject private var selection = NativeChannelManagementSelectionState<NativeChannelManagementID>()
    @Environment(\.scenePhase) private var scene
    var body:some View {
        Group {
            if let flow { NativeChannelWelcomeView(flow:flow,selectChannel:{ if parentRouteIsActive() { selection.selected=$0 } }) }
            else { NativeChannelFlowNotice(title:Text("原欢迎屏的独立读取批准尚不可用；未改变原成员资格或规则状态。"),symbol:"lock.shield").padding(.horizontal,Theme.Space.pageX) }
        }.task { reopen() }
         .onDisappear { close() }
         .onChange(of:scene) { _,value in if value == .active { reopen() } else { close() } }
         .onChange(of:channels.isCurrent) { _,current in if !current { close() } }
         .onChange(of:parentRouteIsActive()) { _,current in if !current { selection.selected=nil;close() } }
         .navigationDestination(item:selection.binding) { id in
             let visit = selection.route(for:id,parentCurrent:parentRouteIsActive)
             NativeChannelMessageHostDestination(session:session,channels:channels.service,channelID:id,routeIsPresented:visit)
                 .id(selection.visitID)
         }
    }
    private func close() { flow?.deactivate();flow=nil }
    private func reopen() {
        close()
        let parent = parentRouteIsActive, owner = channels
        guard scene == .active,parent(),owner.isCurrent else{return}
        flow=session.makeNativeChannelWelcome(scope:owner.scope,sourceCurrent:{ [weak owner] in parent() && owner?.isCurrent == true })
    }
}
@MainActor struct NativeChannelWelcomeView:View {
    let flow:NativeChannelWelcomeFlow
    let selectChannel:(NativeChannelManagementID)->Void
    var body:some View {
        List {
            if flow.isCurrent {
                if let issue=flow.issue { NativeChannelFlowNotice(title:Text(verbatim:issue),symbol:"exclamationmark.circle") }
                if flow.busy { ProgressView() }
                if let value=flow.snapshot {
                    Section { Text(value.title).font(Theme.Font.sheetTitle).fixedSize(horizontal:false,vertical:true);Text(value.description).fixedSize(horizontal:false,vertical:true) }
                    Section("当前可访问的路标") {
                        ForEach(value.signposts) { item in
                            Button { select(item.id) } label: {
                                HStack(alignment:.top,spacing:Theme.Space.s3) {
                                    Text(item.emoji).accessibilityHidden(true)
                                    Text(item.label).fixedSize(horizontal:false,vertical:true)
                                    Spacer(minLength:Theme.Space.s2)
                                    Image(systemName:"chevron.right").font(Theme.Font.label).accessibilityHidden(true)
                                }.frame(minHeight:44,alignment:.leading)
                            }.disabled(flow.busy)
                        }
                    }
                    Section { Button("进入聊天") { select(value.entryChannelID) }.nativeChannelFlowAction().disabled(flow.busy);Text("沿原频道入口再次核验访问与发言权限；这里不自动发送消息。") }
                }
                Button("重新读取当前欢迎配置") { Task{await flow.refresh()} }.disabled(flow.busy)
            } else { NativeChannelFlowNotice(title:Text("身份或批准已失效，旧欢迎内容不可使用。"),symbol:"lock.shield") }
        }.nativeChannelFlowPage()
        .navigationTitle("空间欢迎屏").privacySensitive()
         .task { await flow.activate() }
         .onDisappear { flow.deactivate() }

    }
    private func select(_ id:NativeChannelManagementID) { guard flow.permits(id) else{return};selectChannel(id) }
}
