import SwiftUI

@MainActor struct PlaySharedPlanR5HostEntry: View {
    let flow: PlaySharedPlanLifecycle
    let ticket: PlaySharedPlanOperationTicket
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var visit = UUID()
    @State private var active = false
    @State private var host: PlaySharedPlanR5Host?
    var body: some View {
        Group {
            if let host { PlaySharedPlanR5HostView(host: host) }
            else { ContentUnavailableView("原题组暂不可用", systemImage: "lock", description: Text("需要真实方案票据、读取批准及安全恢复存储。")) }
        }
        .onAppear { activate() }
        .onChange(of: session.sessionRevision) { _, _ in retire(); activate() }
        .onChange(of: scenePhase) { _, value in retire(); if value == .active { activate() } }
        .onDisappear { retire() }
    }
    private func activate() {
        guard scenePhase == .active, !active, flow.operationIsCurrent(ticket) else { return }
        active = true; visit = UUID(); let issued = visit
        host = session.sharedPlanR5Host(flow: flow, ticket: ticket,
            presentationCurrent: { active && visit == issued && scenePhase == .active })
    }
    private func retire() { active = false; visit = UUID(); host?.suspend(); host = nil }
}

@MainActor struct PlaySharedPlanR5HostView: View {
    @Bindable var host: PlaySharedPlanR5Host
    @State private var startConfirmation = false
    var body: some View {
        Form {
            if host.approvalMissing {
                Section { Label("等待原始回执合同与写权限批准", systemImage: "lock") }
            }
            if let recovery = host.recovery { PlaySharedPlanR5CheckSection(model: recovery) }
            else {
                Section {
                    if host.busy { ProgressView() }
                    switch host.phase {
                    case "unknownStart": Text("原启动结果尚未确认。保留原日志，不会重新启动或猜测场次。")
                    case "otherOriginalPending": Text("此节点另有原请求待确认，请返回原入口恢复。")
                    case "awaitingOriginalContract": Text("已保留真实场次，原始身份与回执合同尚未确认。")
                    case "blocked", "stale": Text("账号、方案或授权已变化，请返回后重新核对。")
                    default: Text("开始当前方案的原高级题组")
                    }
                    Button("开始原题组") { startConfirmation = true }.disabled(!host.canStart)
                }
            }
            Button("核对原记录") { Task { await host.load() } }.disabled(host.busy)
        }
        .navigationTitle("原题组").preferredColorScheme(.dark)
        .task { await host.load() }
        .confirmationDialog("开始当前原题组？", isPresented: $startConfirmation, titleVisibility: .visible) {
            Button("确认开始") { Task { await host.startConfirmed() } }.disabled(!host.canStart)
            Button("取消", role: .cancel) {}
        } message: { Text("只使用当前方案的真实节点与场次。启动响应丢失时会保留原记录，不自动重做。") }
    }
}

@MainActor private struct PlaySharedPlanR5CheckSection: View {
    @Bindable var model: PlaySharedPlanR5Recovery
    @State private var offered: PlaySharedPlanR5Recovery.Review?
    @State private var actionConfirmation = false
    @State private var retryConfirmation = false
    private let actions = ["ROLL_CHECK", "REROLL_CHECK", "SUBMIT_CHECK"]
    var body: some View {
        Section("原检定") {
            if let projection = model.projection {
                if !projection.dice.isEmpty { Text(projection.dice.map(String.init).joined(separator: " · ")).accessibilityLabel("原服务器骰点") }
                if projection.submitted { Text("检定已提交") }
                ForEach(actions, id: \.self) { action in
                    Button(title(action)) {
                        offered = try? model.review(action); actionConfirmation = offered != nil
                    }.disabled(!model.canReview(action))
                }
            } else { Text("原身份或回执合同尚未确认，不能提交检定。") }
            if let original = model.pending {
                LabeledContent("原请求", value: original.key).textSelection(.enabled)
                Text(model.acknowledged ? "已取得本人的原请求回执" : "原请求结果待确认，当前结果不代替原回执")
                Button("重试同一原请求") { retryConfirmation = true }.disabled(!model.canRetryOriginal)
            }
            if let outcome = model.outcome, let result = outcome.outcome {
                Text(result == "PASS" ? "原结算：通过" : "原结算：未通过")
                if let reply = outcome.reply, !reply.isEmpty { Text(reply) }
            } else if model.outcome?.status == "BLOCKED_COST" { Text("原结算费用尚未满足") }
            if model.busy { ProgressView() }
        }
        .confirmationDialog("确认原检定动作", isPresented: $actionConfirmation, titleVisibility: .visible) {
            if let offered { Button("确认" + title(offered.action)) { Task { await model.commit(offered); self.offered = nil } } }
            Button("取消", role: .cancel) { offered = nil }
        } message: { Text("使用当前服务器检定和原版本，不在设备上生成骰点或通过结果。") }
        .confirmationDialog("重试同一原请求？", isPresented: $retryConfirmation, titleVisibility: .visible) {
            Button("确认原请求重试") { Task { await model.retryOriginal() } }
            Button("取消", role: .cancel) {}
        } message: { Text("只重放已保存的原请求与原编号，不创建新的检定。") }
    }
    private func title(_ action: String) -> String {
        switch action { case "ROLL_CHECK": return "投掷"; case "REROLL_CHECK": return "重掷"; default: return "提交检定" }
    }
}
