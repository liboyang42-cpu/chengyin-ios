import SwiftUI

/// Factory invocation happens at the normal entry, never during a request or by a
/// context-search card. The retained owner binds the original actor/channel issuance.
@MainActor struct NativeChannelChainLaunchView: View {
    let makeFlow: () -> NativeChannelChainFlow?
    let current: () -> Bool
    @State private var flow: NativeChannelChainFlow?
    @State private var attempted = false
    var body: some View {
        Group {
            if let flow { NativeChannelChainView(flow: flow, current: current) }
            else if attempted { ContentUnavailableView("原接龙当前不可用", systemImage: "list.number", description: Text("需要当前频道身份和独立接口授权。")) }
            else { ProgressView() }
        }.task {
            guard !attempted else { return }
            attempted = true
            if current() { flow = makeFlow() }
        }
    }
}

@MainActor private struct NativeChannelChainView: View {
    @Bindable var flow: NativeChannelChainFlow
    let current: () -> Bool
    @Environment(\.scenePhase) private var scene
    @State private var title = ""
    @State private var maxSlots = "0"
    @State private var hasDeadline = false
    @State private var deadline = Date().addingTimeInterval(86400)
    @State private var content = ""
    @State private var retryPresented = false
    @State private var operation = NativeChannelActivityScreenTask()
    private var available: Bool { current() && scene == .active }
    var body: some View {
        Form {
            if !flow.isCurrent { Text("当前身份、频道或原消息已不可用。").fixedSize(horizontal: false, vertical: true) }
            else {
                status
                // A confirmed original receipt survives a separate current-roster read failure.
                // Scope/account/receipt authority still gates this memory-only projection.
                if let confirmed = flow.lastConfirmedRequest {
                    Section {
                        Text(verbatim: confirmed.requestID).font(Theme.Font.label).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text(label(confirmed.operation)).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        if confirmed.resultRedacted { Text("request.redacted", tableName: "NativeChannelMessage") }
                    } header: { Text("request.applied", tableName: "NativeChannelMessage") }
                        .accessibilityIdentifier("channel.chain.originalReceipt")
                }
                if let review = flow.review { reviewSection(review) }
                else if let pending = flow.pending { recoverySection(pending) }
                if let page = flow.page {
                    Section("原接龙") {
                        Text(page.chain.title).font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
                        LabeledContent("状态", value: page.chain.status == "CLOSED" ? "已关闭" : (page.chain.accepting ? "进行中" : "已截止"))
                        LabeledContent("当前参加", value: page.chain.maxSlots == 0 ? "\(page.chain.activeCount) / 不限" : "\(page.chain.activeCount) / \(page.chain.maxSlots)")
                        if let end = page.chain.deadlineAt { LabeledContent("截止时间") { Text(Date(timeIntervalSince1970: Double(end) / 1000), style: .date).fixedSize(horizontal: false, vertical: true); Text(Date(timeIntervalSince1970: Double(end) / 1000), style: .time).fixedSize(horizontal: false, vertical: true) } }
                        Button("刷新原结果") { run { _ in await flow.refresh() } }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy || flow.review != nil)
                    }
                    Section("接龙名单") {
                        if flow.entries.isEmpty { Text("暂无接龙记录").fixedSize(horizontal: false, vertical: true) }
                        ForEach(flow.entries) { entry in
                            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                                Text("第 \(entry.position) 位\(entry.memberId == flow.service.actorID ? " · 我" : "")").fixedSize(horizontal: false, vertical: true).font(Theme.Font.label).foregroundStyle(.secondary)
                                if entry.status == "ACTIVE", let text = entry.content { Text(text).fixedSize(horizontal: false, vertical: true) }
                                else { Text("已撤回").fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary) }
                            }
                        }
                        if page.hasMore { Button("展开后续记录") { run { _ in await flow.more() } }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy || flow.review != nil) }
                    }
                    if flow.pending == nil, flow.review == nil {
                        Section("我的接龙") {
                            if let mine = page.mine {
                                Text(mine.status == "ACTIVE" ? "已参加（第 \(mine.position) 位）" : "已撤回；重新参加沿用原序号").fixedSize(horizontal: false, vertical: true)
                                if mine.status == "ACTIVE", let original = mine.content {
                                    Text(original).fixedSize(horizontal: false, vertical: true)
                                    Button("载入我的原内容") { content = original }.font(Theme.Font.button).frame(minHeight: 44).disabled(!flow.canJoin)
                                }
                            }
                            TextField("接龙内容", text: $content, axis: .vertical).disabled(!flow.canJoin)
                            Button(page.mine?.status == "ACTIVE" ? "确认修改我的接龙…" : "确认参加接龙…") { flow.prepareJoin(content: content) }.font(Theme.Font.button).frame(minHeight: 44).disabled(!flow.canJoin)
                            Button("撤回我的接龙…", role: .destructive) { flow.prepareWithdraw() }.font(Theme.Font.button).frame(minHeight: 44).disabled(!flow.canWithdraw)
                            if flow.canClose { Button("关闭我创建的接龙…", role: .destructive) { flow.prepareClose() }.font(Theme.Font.button).frame(minHeight: 44) }
                            if !page.chain.canParticipate { Text("当前仅可查看原结果，不能参加或修改。").fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                } else if flow.reference != nil, !flow.busy, flow.phase != .appliedRedacted {
                    Section { Text("原结果尚不可读；不是空名单或操作失败。").fixedSize(horizontal: false, vertical: true)
                        Button("重新读取原接龙") { run { _ in await flow.refresh() } }.font(Theme.Font.button).frame(minHeight: 44).disabled(!flow.service.canRead || flow.review != nil)
                    }
                } else if flow.reference == nil, flow.pending == nil, flow.review == nil {
                    Section("发起接龙") {
                        TextField("标题", text: $title)
                        TextField("人数上限，0 为不限", text: $maxSlots).keyboardType(.numberPad)
                        Toggle("设置截止时间", isOn: $hasDeadline)
                        if hasDeadline { DatePicker("截止时间", selection: $deadline, displayedComponents: [.date, .hourAndMinute]) }
                        Button("核对并创建…") {
                            guard let maximum = Int(maxSlots) else { return }
                            flow.prepareCreate(title: title, maxSlots: maximum, deadline: hasDeadline ? deadline : nil)
                        }.nativeChannelPrimaryAction().disabled(!flow.canCreate || Int(maxSlots) == nil)
                        if !flow.canCreate { Text("创建、读取和原请求恢复需各自独立授权。").fixedSize(horizontal: false, vertical: true) }
                    }.disabled(!flow.canCreate)
                }
            }
        }
        .font(Theme.Font.body)
        .nativeChannelScreen()
        .navigationTitle("原频道接龙")
        .privacySensitive()
        .task(id: available) {
            if available { await flow.activate(current: current) }
            else { retireScreen() }
        }
        .onChange(of: current()) { _, valid in if !valid { retireScreen() } }
        .onChange(of: scene) { _, phase in if phase != .active { retireScreen() } }
        .onDisappear { retireScreen() }
        .confirmationDialog("只重试原请求；不会创建新的请求或更改内容", isPresented: $retryPresented, titleVisibility: .visible) {
            Button("先查原结果，再重试同一请求") { run { current in await flow.retryOriginal(); guard current() else { return }; await refreshAfterSettlement() } }
            Button("取消", role: .cancel) {}
        }
    }
    @ViewBuilder private var status: some View {
        switch flow.phase {
        case .reading: ProgressView("读取原结果…").font(Theme.Font.body)
        case .submitting: ProgressView("原请求已提交，等待确认…").font(Theme.Font.body)
        case .unknown: Text("原请求结果待确认；不会自动重发或替换。").nativeChannelNotice(systemImage: "clock")
        case .applied: Text("原请求已完成，正在读取当前结果。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
        case .appliedRedacted: Text("原请求已完成；当前权限或消息状态不允许展示结果。").nativeChannelNotice(systemImage: "lock")
        case .rejected(let code):
            if code == "SCREENING_PENDING" { Text("请返回频道逐条确认规则；此请求不会自动重发。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
            else { Text("原请求未提交成功或原状态已变，请刷新后重新核对。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
        case .failed: Text("原结果读取失败，未推断为空名单。").nativeChannelNotice(systemImage: "exclamationmark.circle")
        case .persistenceFailed: Text("原请求记录无法安全保存或核对，已停止操作。请勿清除存储或另发请求。").nativeChannelNotice(systemImage: "exclamationmark.circle")
        default: EmptyView()
        }
    }
    @ViewBuilder private func reviewSection(_ command: NativeChannelChainCommand) -> some View {
        Section("核对原操作") {
            Text(label(command.operation)).font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
            if let title = command.title { Text(title).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
            if let slots = command.maxSlots { Text(slots == 0 ? "人数不限" : "最多 \(slots) 人").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
            if let end = command.deadlineAt { Text(Date(timeIntervalSince1970: Double(end) / 1000), style: .date).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true); Text(Date(timeIntervalSince1970: Double(end) / 1000), style: .time).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
            if let text = command.content { Text(text).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
            Text("确认前会重读当前原状态；服务器仍核对成员、权限、可见性和容量。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
            Button("确认原操作") { run { current in await flow.confirm(); guard current() else { return }; await refreshAfterSettlement() } }.nativeChannelPrimaryAction().disabled(flow.busy)
            Button("取消核对", role: .cancel) { flow.cancelReview() }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy)
        }
    }
    @ViewBuilder private func recoverySection(_ command: NativeChannelChainCommand) -> some View {
        Section("原请求恢复") {
            if flow.ownsPending {
                Text(label(command.operation)).font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
                if let title = command.title { Text(title).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                if let text = command.content { Text(text).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                Button("只查询原请求结果") { run { current in await flow.recover(); guard current() else { return }; await refreshAfterSettlement() } }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy || !flow.service.canRecover)
                Button("核对并重试同一原请求…") { retryPresented = true }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy || !flow.service.canRecover || !flow.service.allows(command.operation))
            } else { Text("本频道另一个接龙原操作待确认，请返回频道工具栏的接龙入口恢复。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func label(_ operation: NativeChannelChainCommand.Operation) -> String {
        switch operation { case .create: return "创建接龙"; case .join: return "参加或更新自己的接龙"; case .withdraw: return "撤回自己的接龙（释放一个名额）"; case .close: return "关闭自己创建的接龙" }
    }
    private func run(_ work: @escaping NativeChannelActivityScreenWork) {
        operation.start(current: { available && flow.isCurrent }, work: work)
    }
    private func retireScreen() {
        operation.retire(); flow.deactivate(); clearDraft()
    }
    private func refreshAfterSettlement() async {
        guard flow.isCurrent, flow.pending == nil, flow.reference != nil,
              flow.phase != .appliedRedacted, flow.phase != .persistenceFailed else { return }
        content = ""; title = ""
        await flow.refresh()
    }
    private func clearDraft() { title = ""; content = ""; maxSlots = "0"; hasDeadline = false; retryPresented = false }
}

/// Local presentation work only. The activity flow remains the sole writer/journal owner.
/// Retiring a screen releases its task slot even when a transport ignores cancellation.
typealias NativeChannelActivityScreenWork = @MainActor (_ current: @escaping @MainActor () -> Bool) async -> Void
@MainActor final class NativeChannelActivityScreenTask {
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    var isRunning: Bool { task != nil }
    func start(current sourceCurrent: @escaping @MainActor () -> Bool,
               work: @escaping NativeChannelActivityScreenWork) {
        guard task == nil, sourceCurrent() else { return }
        generation &+= 1
        let ticket = generation
        task = Task { @MainActor in
            defer { if generation == ticket { task = nil } }
            let current: @MainActor () -> Bool = {
                !Task.isCancelled && self.generation == ticket && sourceCurrent()
            }
            guard current() else { return }
            await work(current)
        }
    }
    func retire() {
        generation &+= 1
        task?.cancel(); task = nil
    }
}
