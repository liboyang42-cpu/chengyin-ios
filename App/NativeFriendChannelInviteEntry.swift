import SwiftUI

/// Current real CLUB channel is resolved again; a non-default target never inherits parent approval as VIEW.
@MainActor struct NativeFriendChannelInviteChannelEntry: View {
    @Environment(\.themeDomain) private var domain
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeFriendChannelInviteFlow?
    @State private var flow: NativeFriendChannelInviteFlow?
    @State private var generation: UInt64 = 0
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if let flow { NativeFriendChannelInviteView(flow: flow).id(ObjectIdentifier(flow)) }
            else { VStack { Text("当前频道/原空间管理资格不可确认。未制造子频道或俱乐部权限。"); Button("重新读取当前频道") { Task { await open() } } } }
        }.font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .task { await open() }
        .onChange(of: phase) { _, next in if next == .active { Task { await open() } } else { close() } }
        .onDisappear { close() }
        .privacySensitive()
        .tint(Theme.Color.accent(in: domain))
    }
    private func close() { generation &+= 1; flow?.deactivate(); flow = nil }
    private func open() async {
        close(); let stamp = generation
        do {
            let captured = try await channels.currentChannelContext(channelID: channelID)
            guard phase == .active, stamp == generation, !Task.isCancelled, channels.contextIsCurrent(captured),
                  ["CLUB", "TEAM"].contains(captured.ownerType), captured.serverPermissionNames.isSuperset(of: ["VIEW_CHANNEL", "MANAGE_CHANNEL"]) else { return }
            flow = makeFlow(captured)
        } catch { }
    }
}
/// Own request history and actual original card destinations share this lifecycle, not a second command writer.
@MainActor struct NativeFriendChannelInviteEntry: View {
    @Environment(\.themeDomain) private var domain
    let makeFlow: @MainActor () -> NativeFriendChannelInviteFlow?
    var conversation: ((Int, Int64, Int64) -> AnyView)? = nil
    @State private var flow: NativeFriendChannelInviteFlow?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if let flow { NativeFriendChannelInviteView(flow: flow, conversation: conversation).id(ObjectIdentifier(flow)) }
            else { Text("当前独立原邀请读取授权不可用；没有发送、补发或加入任何空间。") }
        }.font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .task { reopen() }
        .onChange(of: phase) { _, next in if next == .active { reopen() } else { close() } }
        .onDisappear { close() }
        .tint(Theme.Color.accent(in: domain))
    }
    private func close() { flow?.deactivate(); flow = nil }
    private func reopen() { close(); if phase == .active { flow = makeFlow() } }
}
@MainActor private struct NativeFriendChannelInviteView: View {
    @Environment(\.themeDomain) private var domain
    let flow: NativeFriendChannelInviteFlow
    var conversation: ((Int, Int64, Int64) -> AnyView)? = nil
    private struct ChannelSelection: Identifiable { let kind: Int; let channel, space: Int64; var id: Int64 { channel } }
    @State private var selectedChannel: ChannelSelection?
    @State private var message = ""
    @State private var checked: Set<String> = []
    private var batches: [NativeFriendChannelInviteMine.Item] {
        var seen: Set<String> = []; return flow.mine.filter { seen.insert($0.requestID).inserted }
    }
    var body: some View {
        Form {
            Section {
                Text("好友只是选择来源；原空间审批与目标频道接受分别回读。不会授予私有子频道权限，也不会因好友关系免审。")
                if !flow.name.isEmpty { Text((flow.isTargetChannel ? "定向目标频道：《" : "来源默认频道：《") + flow.name + "》") }
                if flow.busy { ProgressView() }
                if !flow.isCurrent { Text("账号、页面或独立授权已失效；私人投影已清除。") }
                if let issue = flow.issue { Text(verbatim: issue).font(Theme.Font.label) }
                if let pending = flow.pending {
                    Text("原请求待确认：" + pending.requestID)
                    Button("只回读同一原请求") { Task { await flow.recover() } }.disabled(!flow.canRecover)
                }
                if let receipt = flow.receipt {
                    Text("原请求：" + receipt.requestID)
                    Text(receipt.outcome == "APPLIED" ? "已回读原操作回执；不代表当前成员或频道权限。" : receipt.outcome == "REJECTED" ? "同一原请求已明确拒绝并回滚；没有自动重发。请刷新当前资格后再明确操作。" : "原结果仍为 UNKNOWN；不自动重发。")
                }
            }
            if case .channel = flow.mode { NativeFriendPickerView(flow: flow) }
            if flow.mode == .mine {
                Section("我发出的原定向邀请") {
                    ForEach(batches) { row in
                        Button("回读原批次 · " + row.requestID) {
                            guard let channel = Int64(row.channelID) else { return }; Task { await flow.loadBatch(channel: channel, request: row.requestID) }
                        }.disabled(flow.busy)
                    }
                    if flow.canMore { Button("读取更早的本人记录") { Task { await flow.loadMine(more: true) } } }
                }
            }
            if let batch = flow.batch {
                Section("原邀请结果") {
                    Text("已邀请 \(batch.invited) · 已完成加入 \(batch.joined) · 待处理 \(batch.pending) · 已结束 \(batch.closed)")
                    Text(batch.targetChannel == true ? "这里的加入数只计本人明确接受目标频道的原 use 事实；原入会批准不计。当前频道可见性仍独立判断。" : "加入数是原邀请对应真实审批/加入的历史事实，不是当前会员人数；撤邀请不会撤销已经存在的会员或规则承诺。").font(Theme.Font.label)
                    ForEach(batch.items) { item in
                        VStack(alignment: .leading, spacing: Theme.Space.s2) {
                            Text(verbatim: item.friend.displayName + " · " + label(item.state))
                            if item.state == "JOINED" { Text(verbatim: item.friend.displayName + (batch.targetChannel == true ? " 已明确接受过你的频道邀请：《" : " 已通过你的邀请加入过《") + batch.name + "》。").font(Theme.Font.label) }
                            if batch.guildKind == 3 && batch.targetChannel != true {
                                Text(item.parentMember == true ? "原队伍：当前有效成员" : "原队伍：当前未确认有效成员；历史加入不恢复资格").font(Theme.Font.label)
                            }
                            if batch.targetChannel == true {
                                Text(item.parentMember == true ? "原空间：当前有效成员" : "原空间：当前未确认有效成员").font(Theme.Font.label)
                                Text(item.channelAccess == true ? "目标频道：当前可见" : "目标频道：当前不可见，历史接受不恢复权限").font(Theme.Font.label)
                            }
                            if ["INVITED", "PENDING_REVIEW"].contains(item.state) {
                                Button("撤销这份原邀请", role: .destructive) { flow.prepareRevoke(item) }.disabled(!flow.canWrite || flow.review != nil)
                            }
                        }
                    }
                    Button("重新读取当前结果") { Task { if case .invite = flow.mode { await flow.refresh() } else if let channel = Int64(batch.channelID) { await flow.loadBatch(channel: channel, request: batch.requestID) } } }.disabled(flow.busy)
                }
            }
            if let landing = flow.landing {
                Section("收到的原定向邀请") {
                    if landing.isTargetChannel {
                        Text("这是目标频道邀请，不是空间成员或私有频道授权。")
                        if let name = landing.channelName { Text(verbatim: "目标频道：《" + name + "》") }
                        Text(landing.parentMember == true ? "原空间成员：已成立" : "原空间成员：尚未成立")
                        if let application = landing.parentApplication {
                            Text("本人原空间申请 #" + application.id + " · 原状态 \(application.status)" + (application.expired ? " · 已过期" : "")).font(Theme.Font.label)
                        }
                        Text(landing.channelAccepted == true ? "目标频道接受：已有本人原 use 回执（不代表永久权限）" : "目标频道接受：尚未完成")
                        if landing.joiningPaused == true { Text("原空间当前已暂停加入/邀请接受；不绕过原暂停规则。") }
                        if landing.parentMember != true && landing.parentInviteAvailable == false { Text("此邀请不能再次建立父空间成员；历史加入不恢复已经退出的资格。") }
                        if landing.parentMember == true && landing.channelAccess != true { Text("原空间批准不代表目标频道可见；当前没有该频道权限，本入口不会代写权限覆盖。") }
                        if landing.channelAccepted != true && landing.inviteAvailable != true { Text("此原邀请当前不可再使用；没有补发或换码。") }
                        if landing.channelReady == true {
                            Button("查看目标频道接受确认") { flow.prepareRecipient(message: "", checked: []) }.disabled(!flow.canWrite || flow.review != nil)
                        }
                        if landing.canEnterOriginalChannel, conversation != nil {
                            Button("打开原频道（重新授权）") {
                                guard flow.isCurrent, let channel = Int64(landing.channelID ?? ""), let club = Int64(landing.guildID) else { return }
                                selectedChannel = .init(kind: landing.guildKind, channel: channel, space: club)
                            }
                        }
                    }
                    Text(verbatim: landing.space?.name ?? (landing.guildKind == 3 ? "原队伍" : "原俱乐部"))
                    Text("原空间 #" + landing.guildID + " · " + label(landing.joinState))
                    if landing.joinState == "NOT_MEMBER" && (!landing.isTargetChannel || (landing.inviteAvailable == true && landing.parentInviteAvailable == true)) {
                        TextField("原准入留言（可选，最多60字）", text: $message, axis: .vertical)
                        Button(landing.isTargetChannel ? "只办理原空间准入（不接受频道）" : "查看本次准入确认") { flow.prepareRecipient(message: message, checked: []) }.disabled(!flow.canWrite || message.unicodeScalars.count > 60 || flow.review != nil)
                    }
                    if landing.joinState == "SCREENING_REQUIRED" {
                        ForEach(landing.rules) { rule in
                            DisclosureGroup(rule.title) { Text(verbatim: rule.body).textSelection(.enabled) }
                            if rule.accepted { Text("此原版本已确认").font(Theme.Font.label) }
                            else { Toggle(rule.required ? "我同意此必选规则" : "我同意此规则", isOn: Binding(get: { checked.contains(rule.key) }, set: { if $0 { checked.insert(rule.key) } else { checked.remove(rule.key) } })).disabled(!flow.canWrite || flow.review != nil) }
                        }
                        Button("查看逐条规则确认") { flow.prepareRecipient(message: "", checked: checked) }
                            .disabled(!flow.canWrite || flow.review != nil || !landing.rules.allSatisfy { !$0.required || $0.accepted || checked.contains($0.key) })
                    }
                    if landing.joinState == "ALREADY_MEMBER" && !landing.isTargetChannel {
                        Text("原成员资格已回读；本卡不授予私有子频道权限。")
                        if landing.guildKind == 3, let team = Int(landing.guildID), team > 0 {
                            NavigationLink("重新读取原队伍详情") { SessionTeamDetailView(lookup: .id(team)) }
                        } else { Text("请从原俱乐部/频道目录进入。") }
                    }
                }
            }
            if let review = flow.review {
                Section("提交前确认") {
                    Text("原请求号：" + review.requestID)
                    if review.action == "CREATE" {
                        Text("向明确选择的 \(review.peers.count) 位当前好友，各创建1份7天有效、只供该人使用1次的" + (flow.isTargetChannel ? "目标频道邀请" : flow.originalSpaceLabel + "邀请") + "，由原单聊投递受控卡片。普通成员，不免审批、不自动加入。")
                        if flow.isTargetChannel { Text("若对方尚未成为原空间成员，必须先明确申请并通过原流程；之后还须具备当前频道访问权，另行明确接受。不会授予私有频道权限。") }
                        ForEach(review.peers, id: \.id) { peer in Text("好友 #\(peer.id) · 原关系版本 \(peer.version)") }
                    } else if review.action == "SUBMIT" {
                        Text(landingIsTeam(flow) ? "明确接受原队伍邀请：当前邀请制可由原入队流程加入；公开申请制仍等待队长原审批。原票、人数和屏蔽不变。" : "明确接受此原邀请并提交原准入流程。公开准入可直接加入；需要审核时仍等待原管理员审批。")
                        if !review.message.isEmpty { Text(verbatim: review.message) }
                    } else if review.action == "PARENT_SUBMIT" {
                        Text(landingIsTeam(flow) ? "这次仅办理父队伍准入：当前邀请制可立即原入队；公开申请制仍需队长原审批。不会消耗目标频道使用次数，不代表已接受频道，不授予 VIEW。" : "这次仅提交原空间申请：公开准入可能立即成为空间成员，审批制仍等待原审批。不会使用频道邀请，不计频道已加入，也不写目标频道权限。")
                        if !review.message.isEmpty { Text(verbatim: review.message) }
                    } else if review.action == "ACCEPT_CHANNEL" {
                        Text("明确接受这一份原目标频道邀请。服务端重新确认当前空间成员、频道可见与原规则，再消耗该目标的1次使用并建立原收件箱索引。索引不授予任何权限。")
                    } else if review.action == "ACCEPT_RULES" { Text("只确认刚刚逐条勾选的原规则正文与哈希；不改变角色或免审。") }
                    else { Text("只撤销这份原邀请，不移除已经加入的人，也不代替对方撤回已提交的入会申请。") }
                    Button("确认这次明确操作") { Task { await flow.confirm(); message = ""; checked = [] } }.disabled(!flow.canWrite)
                    Button("取消未发送确认") { flow.cancelReview() }.disabled(flow.busy)
                }
            }
            Button("刷新当前原来源") { message = ""; checked = []; Task { await flow.refresh() } }.disabled(flow.busy)
        }
        .formStyle(.grouped)
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .navigationTitle("好友定向邀请").privacySensitive()
        .task { await flow.activate() }
        .onChange(of: flow.landing) { _, _ in message = ""; checked = [] }
        .onChange(of: flow.isCurrent) { _, valid in if !valid { message = ""; checked = []; selectedChannel = nil } }
        .sheet(item: $selectedChannel) { target in
            NavigationStack {
                if flow.isCurrent, let destination = conversation?(target.kind, target.channel, target.space) { destination }
                else { Text("原账号或目标来源已变化；当前频道仍须独立授权。") }
            }
        }
        .onDisappear { message = ""; checked = []; selectedChannel = nil; flow.deactivate() }
        .tint(Theme.Color.accent(in: domain))
    }
    private func landingIsTeam(_ flow: NativeFriendChannelInviteFlow) -> Bool { flow.landing?.guildKind == 3 }
    private func label(_ state: String) -> String {
        ["JOINED":"已通过原邀请加入过", "INVITED":"尚未使用", "PENDING_REVIEW":"原准入申请待审批", "REQUEST_ENDED":"原申请已结束或来源已变", "INVITE_ENDED":"原邀请已失效",
         "NOT_MEMBER":"可明确提交原准入", "ALREADY_MEMBER":"当前已加入", "SCREENING_REQUIRED":"须逐条确认原规则", "SOURCE_CHANGED":"原来源已变化", "EXPIRED":"已过期", "REJECTED":"原申请未通过", "WITHDRAWN":"原申请已撤回", "ACCESS_ENDED":"原成员资格已结束", "UNKNOWN":"结果待核对", "JOIN_PAUSED":"原空间暂停加入", "INVITE_REVOKED":"原邀请已撤销", "INVITE_EXPIRED":"原邀请已过期", "INVITE_EXHAUSTED":"原邀请已使用"] [state] ?? "原状态待核对"
    }
}
