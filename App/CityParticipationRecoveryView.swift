import SwiftUI

/// Explicitly injected original-request recovery only. Not reachable from production composition.
/// Future host MUST change identityVersion on account/credential/permission changes, and own its model.
@MainActor struct CityParticipationRecoveryView: View {
    @Bindable var model: CityParticipationCommandRecovery
    let identityVersion: UInt64
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            switch model.display {
            case .hidden: EmptyView()
            case .unavailable: Text("参与恢复暂不可用，已保存的请求不会重发。")
            case .empty: Text("没有待确认的参与请求。")
            case .storageBlocked: Text("无法核实本地请求，请保留记录。不会发起新请求。")
            case .unknown:
                Text("原请求结果尚未确认。请查询原结果，不要重复提交。")
                Button("查询原结果") { Task { await model.recheck() } }
                    .disabled(model.busy).frame(minHeight: 44)
                    .accessibilityIdentifier("city.participation.recheckOriginal")
            case .complete(let status):
                Text(status == 200 ? "原参与请求已完成。" : "原参与请求未获接受。")
                Text("原记录已保留；此页面不会开启游戏或再次提交。")
            }
            if model.busy { ProgressView().accessibilityLabel("正在查询原请求") }
        }
        .navigationTitle("参与请求恢复")
        .accessibilityIdentifier("city.participation.recovery")
        .task { if scenePhase == .active { model.open() } }
        .onChange(of: identityVersion) { _, _ in model.identityChanged() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.open() } else { model.close() } }
        .onDisappear { model.close() }
    }
}
