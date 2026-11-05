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
            else { ContentUnavailableView { Label("d7.channelWelcome.unavailable",systemImage:"signpost.right") } }
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
                if flow.busy { ProgressView().frame(maxWidth:.infinity) }
                if let value=flow.snapshot {
                    Section {
                        VStack(alignment:.leading,spacing:Theme.Space.s2) {
                            Text(value.title).font(Theme.Font.sheetTitle).fixedSize(horizontal:false,vertical:true)
                            if !value.description.isEmpty { Text(value.description).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                        }
                        .padding(.vertical,Theme.Space.s2)
                    }
                    if !value.signposts.isEmpty {
                        Section("d7.channelWelcome.getStarted") {
                            ForEach(value.signposts) { item in
                                Button { select(item.id) } label: {
                                    HStack(alignment:.top,spacing:Theme.Space.s3) {
                                        Text(item.emoji).accessibilityHidden(true)
                                        Text(item.label).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true)
                                        Spacer(minLength:Theme.Space.s2)
                                        Image(systemName:"chevron.right").font(Theme.Font.label).foregroundStyle(.tertiary).accessibilityHidden(true)
                                    }.frame(minHeight:44,alignment:.leading)
                                }.disabled(flow.busy)
                            }
                        }
                    }
                    Section { Button("d7.channelWelcome.enter") { select(value.entryChannelID) }.nativeChannelFlowAction().disabled(flow.busy) }
                }
            } else {
                ContentUnavailableView { Label("d7.channelWelcome.expired",systemImage:"lock.shield") }
            }
        }
        .refreshable { await flow.refresh() }
        .nativeChannelFlowPage()
        .navigationTitle("d7.channelWelcome.title").privacySensitive()
         .task { await flow.activate() }
         .onDisappear { flow.deactivate() }

    }
    private func select(_ id:NativeChannelManagementID) { guard flow.permits(id) else{return};selectChannel(id) }
}
