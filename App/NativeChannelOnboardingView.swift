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
            else { VStack(alignment:.leading,spacing:Theme.Space.s4) { NativeChannelFlowNotice(title:Text("原引导的独立运行批准尚不可用。未改变原成员资格、规则或角色。"),symbol:"lock.shield")
                Button("跳过引导，查看原欢迎屏"){welcomeVisit.wrappedValue=true}.disabled(!parentRouteIsActive() || !channels.isCurrent) }.padding(.horizontal,Theme.Space.pageX) }
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
                Section {
                    Text("引导可跳过；跳过不完成规则同意、不改变原准入或成员资格。")
                    if let confirmed=flow.confirmed{NativeChannelFlowNotice(title:Text(verbatim:confirmed),symbol:"checkmark.circle")}
                    if let issue=flow.issue{NativeChannelFlowNotice(title:Text(verbatim:issue),symbol:"exclamationmark.circle")}
                    if flow.busy{ProgressView()}
                    Button("重新读取原配置与本人答案"){selections=[:];Task{await flow.refresh()}}.disabled(flow.busy)
                }
                if let pending=flow.pending {
                    Section("待确认的回答") {
                        NativeChannelFlowReference(label:Text("请求编号"),value:pending.id)
                        Text("原答案与配置hash已保护保存。未知时仅查询同一UUID，不提交新答案。")
                        Button("只查原回答"){Task{await flow.refresh()}}.disabled(flow.busy)
                    }
                } else if let review=flow.review {
                    Section("确认回答") {
                        ForEach(review.answers,id:\.promptID) { answer in
                            VStack(alignment:.leading,spacing:Theme.Space.s2) {
                                if let snapshot=flow.snapshot,snapshot.configurationHash==review.configurationHash,
                                   let prompt=snapshot.prompts.first(where:{$0.id==answer.promptID}) {
                                    Text(prompt.title).font(Theme.Font.sectionTitle)
                                    ForEach(prompt.options.filter{answer.optionIDs.contains($0.id)}) { option in Text(option.label) }
                                } else {
                                    Text("问题 \(answer.promptID)").font(Theme.Font.sectionTitle)
                                    Text(verbatim:answer.optionIDs.joined(separator:", "))
                                }
                            }.fixedSize(horizontal:false,vertical:true)
                        }
                        DisclosureGroup("查看本次请求内容") {
                            NativeChannelFlowReference(label:Text("配置 hash"),value:review.configurationHash)
                            Text(verbatim:String(data:review.body,encoding:.utf8) ?? "").font(.callout.monospaced()).textSelection(.enabled)
                        }
                        Text("此请求仅持久保存所选无授权效果答案，不声称授角色、入频道或获发言资格。")
                        Button("确认原回答"){selections=[:];Task{await flow.confirm()}}.nativeChannelFlowAction().disabled(flow.busy)
                        Button("取消未发出的回答"){flow.cancelReview();selections=[:]}.disabled(flow.busy)
                    }
                } else if let snapshot=flow.snapshot {
                    Section("当前回答状态") {
                        Text(snapshot.submitted==1 ? "当前配置的原回答已持久确认。":"当前配置的引导尚未确认完成。")
                        if snapshot.completionPolicy=="UNRESOLVED_OPTIONAL_POLICY" { Text("原配置含可选问题；正式完成策略存在待裁决差异。本页忠实显示，不改required或伪报完成；仍可跳过。") }
                        if snapshot.answerState=="SOURCE_CHANGED" {Text("存在旧配置下的本人答案，不能冒充当前配置答案或自动重做。原历史记录保留。")}
                    }
                    ForEach(snapshot.prompts) { prompt in
                        Section(prompt.title) {
                            Text(prompt.required ? "原配置：完成引导时必答（不阻断进入空间）":"原配置：可选，完成策略待确认")
                            Text(prompt.singleSelect ? "单选":"多选").font(.subheadline).foregroundStyle(.secondary)
                            ForEach(prompt.options) { option in
                                Button {
                                    choose(prompt,option.id,selections[prompt.id]?.contains(option.id) != true)
                                } label: {
                                    HStack(alignment:.top,spacing:Theme.Space.s3) {
                                        VStack(alignment:.leading,spacing:Theme.Space.s2) {
                                            Text(option.emoji+" "+option.label).font(Theme.Font.sectionTitle)
                                            if !option.description.isEmpty { Text(option.description).font(.subheadline).foregroundStyle(.secondary) }
                                            if option.hasEffects { Text("此原选项含角色/频道效果；真实委托未闭合，不能伪报授予。").font(.footnote).foregroundStyle(.secondary) }
                                            if prompt.selected.contains(option.id) { Text("原当前答案已保存此项").font(.footnote).foregroundStyle(.secondary) }
                                        }.fixedSize(horizontal:false,vertical:true)
                                        Spacer(minLength:Theme.Space.s2)
                                        Image(systemName:selections[prompt.id]?.contains(option.id)==true ? "checkmark.circle.fill":"circle")
                                            .accessibilityHidden(true)
                                    }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                                }
                                .buttonStyle(.plain)
                                .accessibilityValue(Text(selections[prompt.id]?.contains(option.id)==true ? "已选择":"未选择"))
                                .disabled(!flow.canPrepare)
                            }
                        }
                    }
                    Button("核对这次原回答"){flow.prepare(selections)}.nativeChannelFlowAction().disabled(!flow.canPrepare)
                }
                Section {
                    Button("跳过引导，查看原欢迎屏",action:openWelcome)
                    Text("仅导航，不提交skipped记录、不授角色、不清除待核对请求；原规则资格仍由原欢迎/频道服务核验。")
                }
            } else {Text("当前身份或批准已失效，旧配置与答案不能继续使用。")}
        }.nativeChannelFlowPage()
        .navigationTitle("入群引导").privacySensitive().task{await flow.activate()}.onDisappear{selections=[:];flow.deactivate()}
    }
    private func choose(_ prompt:NativeOnboardingSnapshot.Prompt,_ option:String,_ selected:Bool){
        guard flow.canPrepare else{return}
        if prompt.singleSelect{selections[prompt.id]=selected ? [option]:[]}
        else{var values=selections[prompt.id] ?? [];if selected{values.insert(option)}else{values.remove(option)};selections[prompt.id]=values}
    }
}
