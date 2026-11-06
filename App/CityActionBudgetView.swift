import SwiftUI

/// Explicit source-only host. Caller supplies original context/revision and approved providers, never a fixture grant.
@MainActor struct CityActionBudgetView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: CityActionBudgetRecovery
    let context: RuntimeDependencyContext
    let identityVersion: UInt64
    var body: some View {
        Group {
            if session.currentRuntimeDependencyContext == context, model.isCurrent {
                List {
                    Section("行动额度") {
                        Text("仅记录掷骰结果，不移动、不发奖。")
                        if let state = model.state {
                            Text(status(state.status))
                            if let remaining = state.remainingUnits { Text("剩余额度：\(remaining)") }
                            if let cost = state.rules?.rollCost { Text("每次消耗：\(cost)") }
                            if let dice = state.dice { Text("骰子：\(dice.diceId)") }
                        } else { Text("当前额度未读取，请刷新。") }
                        Button("刷新额度") { Task { await model.refresh() } }.disabled(model.busy)
                    }
                    Section("原请求") {
                        switch model.display {
                        case .unknown:
                            Text("结果待确认。不会再次提交原请求。")
                            Button("查询原结果") { Task { await model.recheck() } }.disabled(model.busy)
                        case .complete(let code):
                            Text(code == 200 ? "原请求已完成" : "原请求未获执行，请刷新后查看状态。")
                        case .storageBlocked: Text("原记录暂不可读，暂不能提交。")
                        case .unavailable, .hidden: Text("当前入口不可用")
                        case .empty: Text("没有待确认请求")
                        }
                    }
                    if let result = model.result {
                        Section("已核原结果") {
                            Text("骰面：\(result.faceValue)")
                            Text("消耗：\(result.costUnits)")
                            Text("剩余：\(result.afterUnits)")
                            Text(result.resultId).textSelection(.enabled)
                        }
                    }
                    if let prepared = model.prepared {
                        Section("确认本次掷骰") {
                            Text("消耗 \(prepared.cost) 行动额度，仅记录服务器结果。")
                            Button("确认提交") { Task { await model.submit() } }
                                .disabled(!model.canSubmit || scenePhase != .active)
                            Button("取消", role: .cancel) { model.cancelPreparation() }.disabled(model.busy)
                            if !model.canSubmit { Text("尚未取得本次原请求授权。") }
                        }
                    } else if model.display == .empty || complete {
                        Button("准备掷骰") { model.prepare() }
                            .disabled(model.busy || model.state?.status != "AVAILABLE" || model.state?.writeApproved != true || scenePhase != .active)
                    }
                }
            } else {
                VStack {
                    ContentUnavailableView("行动额度暂不可用", systemImage: "dice", description: Text("保留原请求，不会自动重新提交。"))
                    if session.currentRuntimeDependencyContext == context, scenePhase == .active {
                        Button("重新打开") { Task { await model.open() } }
                    }
                }
            }
        }
        .navigationTitle("行动额度")
        .task { await model.open() }
        .onChange(of: session.currentRuntimeDependencyContext) { _, current in if current != context { model.close() } }
        .onChange(of: identityVersion) { _, _ in model.close() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.close() } }
        .onDisappear { model.close() }
    }
    private var complete: Bool { if case .complete = model.display { return true }; return false }
    private func status(_ value: String) -> String {
        switch value {
        case "JOIN_REQUIRED": "请先加入城市队伍"
        case "TEAM_NOT_READY": "队伍尚未就绪"
        case "NOT_CONFIGURED": "当前规则未配置行动额度"
        case "EXHAUSTED": "本轮行动额度已用完"
        default: "当前行动额度可用"
        }
    }
}
