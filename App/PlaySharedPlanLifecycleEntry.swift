import SwiftUI

/// Normal activity navigation conveys no PLAYER or captain authority.
@MainActor struct PlaySharedPlanLifecycleEntry: View {
    let activityID: Int
    let sourceCurrent: () -> Bool
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var phase
    @State private var active = false
    @State private var visit = UUID()
    @State private var flow: PlaySharedPlanLifecycle?
    var body: some View {
        Group {
            if let flow, flow.isCurrent { PlaySharedPlanLifecycleView(model: flow, operationDestination: { owner, ticket in
                AnyView(PlaySharedPlanR5HostEntry(flow: owner, ticket: ticket))
            }).id(visit) }
            else { ContentUnavailableView("共同方案暂不可用", systemImage: "person.3",
                description: Text("需要当前活动原 PLAYER 读取、回执与安全恢复配置；公共地图和工作人员权限不能代替。")) }
        }
        .navigationTitle("共同方案")
        .onAppear { activate() }
        .onChange(of: session.sessionRevision) { _, _ in retire(); activate() }
        .onChange(of: phase) { _, next in retire(); if next == .active { activate() } }
        .onDisappear { retire() }
    }
    private func activate() {
        guard phase == .active, sourceCurrent() else { return }; active = true; visit = UUID(); let issued = visit
        flow = session.playSharedPlanLifecycle(activityID: activityID,
            presentationCurrent: { active && visit == issued && phase == .active && sourceCurrent() })
    }
    private func retire() { active = false; visit = UUID(); flow?.suspend(); flow = nil }
}
