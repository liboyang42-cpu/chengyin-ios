import SwiftUI

/// Normal original CLUB channel detail -> current member-list privacy -> explicit single-person request.
@MainActor struct NativeFriendChannelSourceEntry: View {
    @Environment(\.themeDomain) private var domain
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeFriendChannelSourceFlow?
    // This fresh account-owned destination does not borrow a channel grant or carry private rows.
    var recoveryHome: (() -> AnyView)? = nil
    @State private var flow: NativeFriendChannelSourceFlow?
    @State private var generation: UInt64 = 0
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if let flow { NativeFriendChannelSourceView(source: flow).id(ObjectIdentifier(flow)) }
            else { VStack { Text("当前原频道成员来源不可用；没有用聊天索引或管理员身份补名单权限。"); Button { Task { await open() } } label: { Text("重新读取当前频道").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading) } } }
        }.font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .privacySensitive()
        // Outside the optional source subtree: closing the channel source cannot remove this link host.
        .safeAreaInset(edge: .bottom) {
            if let recoveryHome {
                NavigationLink { recoveryHome() } label: {
                    Label { Text("friend.channelRecoveryHome", tableName: "NativeFriend") } icon: { Image(systemName: "person.2") }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .padding(.horizontal)
                .accessibilityIdentifier("friend.channelRecoveryHome")
            }
        }
        .task { await open() }
        .onChange(of: phase) { _, value in if value == .active { Task { await open() } } else { close() } }
        .onDisappear { close() }
        .tint(Theme.Color.accent(in: domain))
    }
    private func close() { generation &+= 1; flow?.deactivate(); flow = nil }
    private func open() async {
        close(); let stamp = generation
        do {
            let captured = try await channels.currentChannelContext(channelID: channelID)
            guard generation == stamp, phase == .active, !Task.isCancelled, channels.contextIsCurrent(captured),
                  captured.ownerType == "CLUB", captured.serverPermissionNames.contains("VIEW_CHANNEL") else { return }
            flow = makeFlow(captured)
        } catch { }
    }
}
@MainActor private struct NativeFriendChannelSourceView: View {
    @Environment(\.themeDomain) private var domain
    let source: NativeFriendChannelSourceFlow
    @StateObject private var navigation: NativeFriendHomeNavigation
    @State private var selected: NativeFriendChannelMember?
    @State private var message = ""
    init(source: NativeFriendChannelSourceFlow) { self.source = source; _navigation = StateObject(wrappedValue: NativeFriendHomeNavigation(source.friend)) }
    private var friend: NativeFriendFlow { navigation.flow }
    var body: some View {
        List {
            Section {
                Text("仅当前原频道可见名单；不展示进度、最近活跃、手机号或私有关系原因。读取名单不自动申请、接受或赋予任何角色。")
                if !source.channelName.isEmpty { Text("来源：《" + source.channelName + "》频道") }
                if source.busy || friend.busy { ProgressView() }
                if source.unavailable { Text("当前原成员/关系来源不可确认；没有用旧名单替代。") }
                if !source.isCurrent { Text("频道或独立授权已失效，成员与草稿已清除。原请求可从好友主入口回读，不恢复频道权限。") }
                if friend.pending != nil {
                    Text("有原请求待确认；只回读，不自动重发。")
                    Button { Task { await source.recover() } } label: { Text("回读原好友请求").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading) }.disabled(!friend.canRecover || !source.isCurrent)
                }
                if let issue = friend.issue { Text(LocalizedStringKey(issue), tableName: "NativeFriend") }
                if let review = friend.lastReview { Text("原内容审核：" + review.state.rawValue).font(Theme.Font.label) }
                if let relation = friend.relationship { Text(relation.state == .friend ? "原回读：已成为好友" : "原关系已重新读取；以当前成员行状态为准。") }
            }
            ForEach(source.members) { row in
                VStack(alignment: .leading, spacing: Theme.Space.s1_5) {
                    Text(verbatim: row.displayName).fixedSize(horizontal: false, vertical: true)
                    if row.friendRemark != nil { Text(verbatim: row.nickname).font(Theme.Font.label) }
                    switch row.state {
                    case .friend: Text("好友").foregroundStyle(Theme.Color.textSecondary(in: domain))
                    case .pendingOutgoing: Text("待验证").foregroundStyle(Theme.Color.textSecondary(in: domain))
                    case .pendingIncoming:
                        if row.actionAvailable { Button { selected = row; message = ""; Task { await source.prepareAccept(row) } } label: { Text("接受申请").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading) }.disabled(!friend.canWrite) }
                    case .none:
                        if row.actionAvailable {
                            Button {
                                selected = row
                                // Bounded original title preview; the full current source is displayed separately above.
                                message = "我们在《" + String(String.UnicodeScalarView(source.channelName.unicodeScalars.prefix(36))) + "》频道认识"
                            } label: { Text("加好友").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading) }.disabled(!friend.canWrite)
                        }
                    }
                }
            }
            if let selected, source.members.contains(selected), selected.state == .none, selected.actionAvailable {
                Section("给「\(selected.displayName)」的单人申请") {
                    Text("我们在《" + source.channelName + "》频道认识")
                    TextField("验证消息（最多60字）", text: $message, axis: .vertical)
                    Button { source.prepareRequest(selected, message: message) } label: { Text("查看提交前确认").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading) }
                        .disabled(!friend.canWrite || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.unicodeScalars.count > 60)
                    Button { self.selected = nil; message = ""; friend.cancelReview() } label: { Text("取消未提交草稿").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading) }
                }
            }
            if source.canReadMore { Button { Task { await source.reload(more: true) } } label: { Text("读取下一页原成员").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading) } }
            Button { selected = nil; message = ""; friend.cancelReview(); Task { await source.refresh() } } label: { Text("重新读取当前成员与关系").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading) }
                .disabled(source.busy || !source.isCurrent)
        }
        .listStyle(.insetGrouped)
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .navigationTitle("频道成员").privacySensitive()
        .task { await source.activate() }
        .onDisappear { selected = nil; message = ""; source.deactivate() }
        .onChange(of: source.isCurrent) { _, current in if !current { selected = nil; message = ""; friend.cancelReview() } }
        .sheet(isPresented: Binding(get: { source.isCurrent && friend.actionReview != nil }, set: { if !$0 { friend.cancelReview() } })) {
            if let review = friend.actionReview {
                NavigationStack {
                    Form {
                        Text("对象：" + (selected?.displayName ?? "") + " · #\(review.command.peerID)")
                        if review.command.source != nil { Text("来源：《" + source.channelName + "》频道"); Text(verbatim: review.command.message) }
                        else { Text("接受的是当前回读的原好友申请，不是新的频道成员资格。") }
                        Text(review.command.action == .request ? "验证消息先经过原内容安全审核；审核通过不等于对方已接受。互相申请才按原规则合并。" : "确认接受这一版本的好友申请？")
                        Button("确认这次操作") { Task { await source.confirm(); selected = nil; message = "" } }.disabled(!source.isCurrent || !friend.canWrite)
                        Button("取消未发送操作") { friend.cancelReview() }
                    }
                    .formStyle(.grouped)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary(in: domain))
                    .navigationTitle("好友操作确认")
                }.privacySensitive()
            }
        }
        .tint(Theme.Color.accent(in: domain))
    }
}
