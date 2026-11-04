import SwiftUI

@MainActor struct NativeFriendTeamInviteHooks {
    let makeFlow: (NativeFriendTeamInviteMode) -> NativeFriendTeamInviteFlow?
}
private struct NativeFriendTeamInviteHooksKey: EnvironmentKey { static let defaultValue: NativeFriendTeamInviteHooks? = nil }
extension EnvironmentValues {
    var friendTeamInviteHooks: NativeFriendTeamInviteHooks? {
        get { self[NativeFriendTeamInviteHooksKey.self] }
        set { self[NativeFriendTeamInviteHooksKey.self] = newValue }
    }
}
@MainActor struct NativeFriendTeamInviteEntry: View {
    @Environment(\.themeDomain) private var domain
    let mode: NativeFriendTeamInviteMode
    let makeFlow: @MainActor (NativeFriendTeamInviteMode) -> NativeFriendTeamInviteFlow?
    @State private var flow: NativeFriendTeamInviteFlow?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if let flow {
                List {
                    Section {
                        Text("只处理队长明确选择的原好友，不随机撮合、不自动入队。邀请不占名额；本人确认后仍遵循原票、容量和公开队伍审批规则。").font(Theme.Font.label)
                        if let issue = flow.issue { Text(verbatim: issue) }
                        Button("刷新原邀请与当前资格") { Task { await flow.refresh() } }.disabled(flow.busy)
                    }
                    if case .team = mode { NativeFriendPickerView(flow: flow) }
                    if let context = flow.reviewContext {
                        let review = context.command
                        Section("明确确认") {
                            Text("队伍：\(context.teamName) · #\(review.teamID)")
                            Text(verbatim: review.requestID).font(Theme.Font.label).textSelection(.enabled)
                            ForEach(context.peers) { peer in
                                Text("\(peer.friend.displayName) · #\(peer.id) · 关系版本 \(peer.friend.version)")
                            }
                            if let offerID = review.body.offerId { Text("原邀请：" + offerID).font(Theme.Font.label).textSelection(.enabled) }
                            if review.action == "FRIEND_OFFER" { Text("向已选 \(review.body.peers?.count ?? 0) 位好友发送队长邀请；不会替任何人同意或预占人数。") }
                            else if review.action == "FRIEND_CONFIRM" { Text(review.body.joinMode == 2 ? "确认后仅提交本人同意，仍等待队长按原规则审核；尚未入队。" : "确认加入当前原队伍；服务端重新核验票、名额、屏蔽和队伍状态。") }
                            else { Text(review.action == "FRIEND_DECLINE" ? "明确拒绝这份邀请；不会产生退队记录或扣减人数。" : "撤销尚未被本人确认的邀请；不撤销已成立的个人申请或成员资格。") }
                            Button("确认本次原操作") { Task { await flow.confirm() } }.disabled(!flow.canWrite)
                            Button("返回，不发送") { flow.cancelReview() }.disabled(flow.busy)
                        }
                    }
                    if let pending = flow.pending {
                        Section("原请求恢复") {
                            Text(verbatim: pending.requestID).font(Theme.Font.label).textSelection(.enabled)
                            Text("冻结队伍 #\(pending.teamID)")
                            ForEach(pending.body.peers ?? [], id: \.id) { peer in
                                Text("原选择好友 #\(peer.id) · 关系版本 \(peer.version)").font(Theme.Font.label)
                            }
                            if let offerID = pending.body.offerId { Text("原邀请：" + offerID).font(Theme.Font.label).textSelection(.enabled) }
                            Text("记录已先保存到本人保护存储。未知结果不自动重发，也不创建另一请求。")
                            Button("仅回读原请求") { Task { await flow.recover() } }.disabled(!flow.canRecover)
                        }
                    }
                    if let receipt = flow.receipt {
                        Section("同一原请求结果") {
                            Text(verbatim: receipt.requestId).font(Theme.Font.label).textSelection(.enabled)
                            if let teamID = receipt.teamId { Text("原请求队伍 #\(teamID)") }
                            Text(receipt.outcome == "APPLIED" ? "原操作已记录；不代表对方已接受、已经入队或仍有当前权限。" : "原请求已明确拒绝；没有自动重发或扩大选择。")
                            if let error = receipt.errorCode { Text(verbatim: error).font(Theme.Font.label) }
                            ForEach(receipt.friendOffer?.offers ?? []) { issued in
                                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                                    Text("原选择好友 #" + issued.peerID)
                                    Text(verbatim: issued.offerID).font(Theme.Font.label).textSelection(.enabled)
                                    NavigationLink("重新读取此原邀请的当前状态") {
                                        NativeFriendTeamInviteEntry(mode: .offer(issued.offerID), makeFlow: makeFlow)
                                    }
                                }
                            }
                            if let offerID = receipt.friendOffer?.offerID { Text("已处理原邀请：" + offerID).font(Theme.Font.label).textSelection(.enabled) }
                            if receipt.outcome == "APPLIED", receipt.action == "FRIEND_OFFER", receipt.friendOffer == nil {
                                Text("旧原回执没有逐人邀请编号；不会用当前历史列表猜测本次结果。")
                            }
                            Text("以下当前状态与这份历史回执分开读取；当前名单不可读不会改写同一请求结果。").font(Theme.Font.label)
                        }
                    }
                    ForEach(flow.offers) { offer in
                        Section {
                            if let inviter = offer.inviter { Text("\(inviter.displayName) 邀请你加入") }
                            Text(verbatim: offer.name); Text(verbatim: offer.stateLabel)
                            if case .offer = mode {
                                if offer.canAct {
                                    if offer.recipient {
                                        Button(offer.joinMode == 2 ? "本人确认并等待原审核" : "本人确认加入") { flow.prepare(offer, action: "FRIEND_CONFIRM") }.disabled(!flow.canWrite || flow.hasPickerReview)
                                        Button("拒绝这份邀请", role: .destructive) { flow.prepare(offer, action: "FRIEND_DECLINE") }.disabled(!flow.canWrite || flow.hasPickerReview)
                                    } else {
                                        Button("撤销未确认邀请", role: .destructive) { flow.prepare(offer, action: "FRIEND_REVOKE") }.disabled(!flow.canWrite || flow.hasPickerReview)
                                    }
                                }
                                if offer.state == "JOINED", let id = Int(offer.teamID), id > 0 {
                                    NavigationLink("重新读取原队伍详情") { SessionTeamDetailView(lookup: .id(id)) }
                                }
                            } else {
                                NavigationLink("读取这份原邀请") { NativeFriendTeamInviteEntry(mode: .offer(offer.offerID), makeFlow: makeFlow) }
                            }
                        }
                    }
                    if flow.canMore { Button("继续读取本人历史") { Task { await flow.loadMine(more: true) } }.disabled(flow.busy) }
                }
                .listStyle(.insetGrouped)
                .font(Theme.Font.body)
                .scrollContentBackground(.hidden)
                .background(Theme.Color.bgPage(in: domain))
                .foregroundStyle(Theme.Color.textPrimary(in: domain))
                .id(ObjectIdentifier(flow)).task { await flow.activate() }
            } else { VStack { Text("当前账号或原好友队伍邀请能力尚未配置/已撤回。未打开旧随机组队能力。"); Button("重新读取能力") { open() } } }
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .navigationTitle("原好友队伍邀请")
        .onAppear { if flow == nil { open() } }
        .onChange(of: phase) { _, value in if value == .active { open() } else { close() } }
        .onDisappear { close() }
        .privacySensitive()
        .themeDomain(domain)
        .tint(Theme.Color.accent(in: domain))
    }
    private func open() { close(); guard phase == .active else { return }; flow = makeFlow(mode) }
    private func close() { flow?.deactivate(); flow = nil }
}
