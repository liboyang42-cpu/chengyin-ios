import SwiftUI

@MainActor struct NativeChannelOnboardingEntry:View {
    @ObservedObject var session:AppSession
    let channels:NativeChannelManagementCoordinator
    var parentRouteIsActive: () -> Bool = { false }
    @State private var flow:NativeChannelOnboardingFlow?
    @StateObject private var welcomeRoute = NativeChannelManagementRouteState()
    @Environment(\.scenePhase) private var scene
    var body:some View {
        let welcomeVisit = NativeChannelManagementRouteState.child(welcomeRoute.binding,parentCurrent:parentRouteIsActive)
        Group {
            if let flow { NativeChannelOnboardingView(flow:flow,openWelcome:{welcomeVisit.wrappedValue=true}) }
            else {
                ContentUnavailableView {
                    Label("d7.channelOnboarding.unavailable",systemImage:"list.bullet.clipboard")
                } actions: {
                    Button("d7.channelOnboarding.skip"){welcomeVisit.wrappedValue=true}.disabled(!parentRouteIsActive() || !channels.isCurrent)
                }
            }
        }.task{reopen()}.onDisappear{close()}
         .onChange(of:scene){_,value in if value == .active{reopen()}else{close()}}
         .onChange(of:channels.isCurrent){_,current in if !current{close()}}
         .nativeChannelFlowPage()
         .onChange(of:parentRouteIsActive()){_,current in if !current{welcomeRoute.isPresented=false;close()}}
         .navigationDestination(isPresented:welcomeVisit){NativeChannelWelcomeEntry(session:session,channels:channels,parentRouteIsActive:{welcomeVisit.wrappedValue}).id(welcomeRoute.visitID)}
    }
    private func close(){flow?.deactivate();flow=nil}
    private func reopen(){
        close()
        let parent = parentRouteIsActive, owner = channels
        guard scene == .active,parent(),owner.isCurrent else{return}
        flow=session.makeNativeChannelOnboarding(scope:owner.scope,sourceCurrent:{ [weak owner] in parent() && owner?.isCurrent == true })
    }
}
@MainActor struct NativeChannelOnboardingView:View {
    let flow:NativeChannelOnboardingFlow
    let openWelcome:()->Void
    @State private var selections:[String:Set<String>]=[:]
    var body:some View {
        Form {
            if flow.isCurrent {
                if flow.confirmed != nil || flow.issue != nil || flow.busy {
                    Section {
                        if let confirmed=flow.confirmed{NativeChannelFlowNotice(title:Text(verbatim:confirmed),symbol:"checkmark.circle")}
                        if let issue=flow.issue{NativeChannelFlowNotice(title:Text(verbatim:issue),symbol:"exclamationmark.circle")}
                        if flow.busy{ProgressView().frame(maxWidth:.infinity)}
                    }
                }
                if flow.pending != nil {
                    Section {
                        NativeChannelFlowNotice(title:Text("d7.channelOnboarding.pending"),symbol:"clock.arrow.circlepath")
                        Button("d7.channelOnboarding.checkStatus"){Task{await flow.refresh()}}.disabled(flow.busy)
                    }
                } else if let review=flow.review {
                    Section("d7.channelOnboarding.yourAnswers") {
                        ForEach(review.answers,id:\.promptID) { answer in
                            VStack(alignment:.leading,spacing:Theme.Space.s2) {
                                if let snapshot=flow.snapshot,snapshot.configurationHash==review.configurationHash,
                                   let prompt=snapshot.prompts.first(where:{$0.id==answer.promptID}) {
                                    Text(prompt.title).font(Theme.Font.sectionTitle)
                                    ForEach(prompt.options.filter{answer.optionIDs.contains($0.id)}) { option in Text(option.label) }
                                } else {
                                    Text(verbatim:"—").font(Theme.Font.sectionTitle)
                                }
                            }.fixedSize(horizontal:false,vertical:true)
                        }
                    }
                    Section {
                        Button("d7.channelOnboarding.confirm"){selections=[:];Task{await flow.confirm()}}.nativeChannelFlowAction().disabled(flow.busy)
                        Button("d7.channelOnboarding.edit"){flow.cancelReview();selections=[:]}.disabled(flow.busy)
                    }
                } else if let snapshot=flow.snapshot {
                    Section {
                        LabeledContent("d7.channelOnboarding.status") {
                            Text(snapshot.submitted==1 ? LocalizedStringKey("d7.channelOnboarding.done") : LocalizedStringKey("d7.channelOnboarding.notDone"))
                        }
                        if snapshot.answerState=="SOURCE_CHANGED" { Text("d7.channelOnboarding.changed").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                    }
                    ForEach(snapshot.prompts) { prompt in
                        Section {
                            ForEach(prompt.options) { option in
                                Button {
                                    choose(prompt,option.id,selections[prompt.id]?.contains(option.id) != true)
                                } label: {
                                    HStack(alignment:.top,spacing:Theme.Space.s3) {
                                        VStack(alignment:.leading,spacing:Theme.Space.s1) {
                                            Text(verbatim:option.emoji.isEmpty ? option.label : option.emoji+" "+option.label).foregroundStyle(.primary)
                                            if !option.description.isEmpty { Text(option.description).font(.subheadline).foregroundStyle(.secondary) }
                                            if prompt.selected.contains(option.id) { Text("d7.channelOnboarding.saved").font(.footnote).foregroundStyle(.secondary) }
                                        }.fixedSize(horizontal:false,vertical:true)
                                        Spacer(minLength:Theme.Space.s2)
                                        Image(systemName:selections[prompt.id]?.contains(option.id)==true ? "checkmark.circle.fill":"circle")
                                            .foregroundStyle(selections[prompt.id]?.contains(option.id)==true ? Color.accentColor : Color.secondary)
                                            .accessibilityHidden(true)
                                    }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                                }
                                .buttonStyle(.plain)
                                .accessibilityValue(Text(selections[prompt.id]?.contains(option.id)==true ? LocalizedStringKey("d7.channelOnboarding.selected") : LocalizedStringKey("d7.channelOnboarding.notSelected")))
                                .disabled(!flow.canPrepare)
                            }
                        } header: {
                            if prompt.required { Text(verbatim:prompt.title) + Text(verbatim:" · ") + Text("d7.channelOnboarding.required") }
                            else { Text(verbatim:prompt.title) }
                        }
                    }
                    if flow.canPrepare {
                        Section { Button("d7.channelOnboarding.review"){flow.prepare(selections)}.nativeChannelFlowAction() }
                    }
                }
                Section { Button("d7.channelOnboarding.skip",action:openWelcome) }
            } else {
                ContentUnavailableView { Label("d7.channelOnboarding.expired",systemImage:"lock.shield") }
            }
        }
        .refreshable { selections=[:];await flow.refresh() }
        .nativeChannelFlowPage()
        .navigationTitle("d7.channelOnboarding.title").privacySensitive().task{await flow.activate()}.onDisappear{selections=[:];flow.deactivate()}
    }
    private func choose(_ prompt:NativeOnboardingSnapshot.Prompt,_ option:String,_ selected:Bool){
        guard flow.canPrepare else{return}
        if prompt.singleSelect{selections[prompt.id]=selected ? [option]:[]}
        else{var values=selections[prompt.id] ?? [];if selected{values.insert(option)}else{values.remove(option)};selections[prompt.id]=values}
    }
}
