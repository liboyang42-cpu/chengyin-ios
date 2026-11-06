import SwiftUI
@MainActor private final class MerchantOfferWithdrawalOriginalModel:ObservableObject {
    let flow:MerchantOfferWithdrawalOriginalFlow
    @Published var revision=UUID()
    private var task:Task<Void,Never>?
    init(_ flow:MerchantOfferWithdrawalOriginalFlow){self.flow=flow;flow.onChange={[weak self] in self?.revision=UUID()}}
    func recover(){task?.cancel();task=Task{await flow.recover()}}
    func confirm(_ r:MerchantOfferWithdrawalOriginalReview){task?.cancel();task=Task{await flow.confirm(r)}}
    func stop(){task?.cancel();task=nil;flow.stop()}
}
@MainActor struct MerchantOfferWithdrawalOriginalView:View {
    @Environment(\.themeDomain) private var domain
    @StateObject private var model:MerchantOfferWithdrawalOriginalModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var reason=""
    @State private var localIssue:String?
    @State private var acknowledge=false
    init(flow:MerchantOfferWithdrawalOriginalFlow){_model=StateObject(wrappedValue:MerchantOfferWithdrawalOriginalModel(flow))}
    private var flow:MerchantOfferWithdrawalOriginalFlow{model.flow}
    var body:some View {
        let _=model.revision
        List {
            Section("普通自由探索 · 原供给退出"){
                Text("原供给 #\(flow.offerID)")
                Text("退出沿原商家权限与原章节生命周期，不混圈层暂停；锁价本身不禁止原退出，结算/关闭或未知生命周期仍由原 writer 拒绝。")
                Text("已售订单、履约应收、核销事实不因退出删除。原规则会处理申请退休、原审核/批准失效及提交后通知安排；安排通知不等于送达。")
                    .font(.footnote)
                Button("只回读原退出结果与当前供给"){clearLocal();model.recover()}.disabled(flow.busy || !flow.isCurrent)
            }
            if let issue=flow.issue{Section{Text(issue).foregroundStyle(.orange)}}
            if let localIssue{Section{Text(localIssue).foregroundStyle(.orange)}}
            if let r=flow.receipt{receipt(r)}
            if let s=flow.snapshot{
                Section("当前原供给（不是历史请求结果）"){
                    Text("原章 #\(s.chapterId.map(String.init) ?? "未知") · 主题 #\(s.topicId.map(String.init) ?? "未知")")
                    Text("原 status \(s.status.map(String.init) ?? "未知") · 原条款 \(s.termsMode ?? "未知")")
                    Text("原总人次 \(s.quotaTotal.map(String.init) ?? "未知") / 已用 \(s.quotaUsed.map(String.init) ?? "未知") · 每人次计酬 \(s.perHeadFee ?? "未配置")")
                    Text("原有效截止："+time(s.validEndEpoch));Text("原行更新时间："+time(s.updatedAtEpoch))
                    Text("原主题生命周期 \(s.topicLifecycle.map(String.init) ?? "未知") · userStatus \(s.topicUserStatus.map(String.init) ?? "未知")")
                    if let old=s.withdrawReason,!old.isEmpty{Text("当前原退出原因："+old)}
                    Text("当前已停用、过期或退出，不等于某个 UNKNOWN UUID 已成功。当前状态不会触发自动重新申请/入驻。")
                }
                Section("原影响核对"){
                    impact(s)
                    if !s.isOrdinary{Text("当前原主题不是已确认普通自由探索；本页不提供退出动作，也不改作圈层暂停。")}
                }
                if s.canWithdraw{Section("填写原退出原因"){
                    TextField("原要求 1–500 字原因",text:$reason,axis:.vertical).lineLimit(3...8)
                    Text("按原服务端 UTF-16 长度计数，拒绝超长而不截断；原因进入原供给记录，本机仅持久摘要。")
                        .font(.footnote)
                    Button("冻结原因及原影响，核对退出"){
                        do{try flow.prepare(reason:reason);localIssue=nil}catch{localIssue="原因未满足原 1–500 字要求，或当前原状态/权限未满足；未提交。"}
                    }
                }.disabled(!flow.canPrepare || flow.review != nil)}
            }
            if let r=flow.review{review(r)}
            if flow.busy{Section{ProgressView("核对原退出请求…")}}
        }
        .font(Theme.Font.body)
        .tint(Theme.Generated.color("--cy-color-brand",in:domain))
        .scrollContentBackground(Theme.Generated.color("--cy-color-bg-page",in:domain) == nil ? .automatic : .hidden)
        .background { if let page=Theme.Generated.color("--cy-color-bg-page",in:domain){page} }
        .preferredColorScheme(domain.colorScheme)
        .navigationTitle("原供给退出 / 结果")
            .onAppear{model.recover()}.onDisappear{model.stop();clearLocal()}
            .onChange(of:scenePhase){_,phase in if phase != .active{model.stop();clearLocal()}else{model.recover()}}
            .onChange(of:flow.draftRetirement){_,_ in clearLocal()}
            .confirmationDialog("已阅匹配的原退出结果？",isPresented:$acknowledge){
                Button("已阅，只清本机原请求身份"){do{try flow.acknowledgeKnown();clearLocal()}catch{localIssue="未确认匹配原结果，未清除。"}}
                Button("保留",role:.cancel){}
            }message:{Text("不删除原供给/服务端回执，不恢复申请、供给或批准；UNKNOWN 不可清除。")}
    }
    private func clearLocal(){reason="";localIssue=nil;acknowledge=false}
    private func time(_ epoch:Int64?)->String{guard let epoch else{return "未提供"};return Date(timeIntervalSince1970:Double(epoch)/1000).formatted(date:.abbreviated,time:.shortened)}
    @ViewBuilder private func impact(_ s:MerchantOfferWithdrawalOriginalCurrent)->some View {
        Text("原章 required 配置：\(s.chapterRequired.map(String.init) ?? "未提供")")
        if s.requiredByOriginalRule==true{Text("原规则按必选章处理：退出会影响新增报名，须主办沿原补位方案处理。")}
        else if s.requiredByOriginalRule==false{Text("原规则按非必选章处理；原复核失效仍可能影响新增报名，不能承诺保持售卖。")}
        else{Text("原必选性未确认，不推断影响。")}
        Text("不撤销已售订单，不改履约应收或既有核销。实际原批准/申请处理仍由原 writer；此页不发起资金动作或补位邀请。")
    }
    @ViewBuilder private func review(_ r:MerchantOfferWithdrawalOriginalReview)->some View {
        Section("不可变核对 · 明确退出一次"){
            Text(r.id.uuidString.lowercased()).font(.caption).textSelection(.enabled)
            Text("原供给 #\(r.source.offerId) / 原章 #\(r.source.chapterId.map(String.init) ?? "未知")")
            Text("本次原退出原因：").font(.headline);Text(r.reason)
            impact(r.source)
            Text("发送前先原子保存此 UUID。结果未知只回读；当前供给消失、status 0、原因相同或通知出现均不能替代回执。")
            Button("确认以上原因与影响，退出一次",role:.destructive){model.confirm(r)}.disabled(flow.busy || !flow.isCurrent)
            Button("取消本地核对",role:.cancel){flow.cancelReview()}.disabled(flow.busy)
        }
    }
    @ViewBuilder private func receipt(_ r:MerchantOfferWithdrawalOriginalReceipt)->some View {
        Section("同 UUID 历史原结果"){
            Text(r.requestId).font(.caption).textSelection(.enabled)
            switch r.outcome{
            case "WITHDRAWN":
                Text("本请求已退出原供给 #\(r.offerId)，写入时 status 0；原行更新时间："+time(r.offerUpdatedAt))
                Text("写入时原必选标记 \(r.requiredAtWrite.map(String.init) ?? "未知") · 原主题 userStatus \(r.userStatusAtWrite.map(String.init) ?? "未知")。不冒充此刻公开/报名状态。")
                Text("原提交后通知链仍由原 writer 安排；本回执不证明通知已送达，不证明退款/补位/重新批准完成。")
            case "REJECTED_CHANGED":Text("冻结核对后的原供给/影响已变化，此请求未调用原退出 writer。")
            case "REJECTED_STATE":Text("原状态不允许普通供给退出，此请求未调用原退出 writer。")
            case "REJECTED_INPUT":Text("原因不满足原长度/内容一致性；防护处理后的文本与冻结原因不一致也会拒绝，不静默修改或截断。此请求未调用原退出 writer。")
            default:Text("UNKNOWN：仅按原 UUID 回读；当前消失/停用/原因相同不能证明本请求成功，不重发。")
            }
            if r.known {
                if !flow.receiptIsFresh { Text("历史原结果，本次尚未重新确认；只展示，不清除原请求。") }
                else if !flow.canAcknowledgeKnown && !flow.busy { Text("本机记录尚不满足安全清除条件，继续保留。") }
                Button("已阅此原结果…") { acknowledge=true }.disabled(!flow.canAcknowledgeKnown)
            }
        }
    }
}
