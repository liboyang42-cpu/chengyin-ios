import SwiftUI

/// Explicit injection only; no production route/factory is installed. identityVersion must track revocation too.
@MainActor struct CityParticipationFormView: View {
    @Bindable var model: CityParticipationFormModel
    let identityVersion: UInt64
    @Environment(\.scenePhase) private var scenePhase
    @State private var inviteCode = ""
    var body: some View {
        List {
            if model.unavailable { Text("参与信息暂不可用，请保留原请求记录。") }
            if let state = model.state {
                Text(verbatim: state.binding.title)
                if let team = state.team {
                    Text("队伍人数：\(team.memberCount)")
                    Text(team.present ? "当前在队" : "已退出，可恢复原队伍")
                    Text(team.confirmed ? "已确认参与" : "尚未确认参与")
                } else { Text("尚未加入本轮队伍。") }
                if !state.writeApproved || !model.hasApprovalHost { Text("参与提交尚未开放。") }
            }
            if model.availableKinds.contains(.join) {
                TextField("邀请码", text: $inviteCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(model.busy).onChange(of: inviteCode) { _, _ in model.invitationInputChanged() }
                    .accessibilityIdentifier("city.participation.inviteCode")
                Button("读取邀请") { Task { await model.inspectInvite(inviteCode) } }.disabled(model.busy)
                if let invitation = model.invitation { Text("邀请队伍人数：\(invitation.memberCount)") }
            }
            ForEach(model.availableKinds, id: \.rawValue) { kind in
                Button(label(kind)) { model.prepare(kind) }
                    .disabled(!model.hasApprovalHost || model.busy || kind == .join && model.invitation == nil)
                    .frame(minHeight: 44).accessibilityIdentifier("city.participation.prepare.\(kind.rawValue)")
            }
            if let command = model.prepared {
                Text("确认操作：\(label(command.kind))")
                Text("使用刚读取的原队伍与版本；结果不明时只查询原请求。")
                Button("确认提交") { Task { await model.submitPrepared() } }
                    .disabled(!model.hasApprovalHost || model.busy).frame(minHeight: 44)
                    .accessibilityIdentifier("city.participation.confirmOriginal")
                Button("取消", role: .cancel) { model.cancelReview() }.disabled(model.busy)
            }
            if model.busy { ProgressView().accessibilityLabel("正在读取或确认参与请求") }
            Section("原请求结果") {
                switch model.recovery.display {
                case .unknown:
                    Text("结果尚未确认，不会重复提交。")
                    Button("查询原结果") { Task { await model.recovery.recheck() } }.disabled(model.recovery.busy || model.busy)
                case .complete(let status): Text(status == 200 ? "原请求已完成，请重新读取参与信息。" : "原请求未获接受，请重新读取参与信息。")
                case .storageBlocked: Text("无法核实原记录，不会发起新请求。")
                case .unavailable: Text("原请求读取暂不可用。")
                case .empty, .hidden: EmptyView()
                }
            }
            Button("重新读取参与信息") { Task { await model.open() } }.disabled(model.busy)
        }
        .navigationTitle("城市队伍参与")
        .accessibilityIdentifier("city.participation.form")
        .task { if scenePhase == .active { await model.open() } }
        .onChange(of: identityVersion) { _, _ in inviteCode = ""; model.close() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.open() } } else { inviteCode = ""; model.close() }
        }
        .onDisappear { inviteCode = ""; model.close() }
    }
    private func label(_ kind: CityParticipationCommand.Kind) -> String {
        switch kind { case .create: "创建队伍"; case .join: "加入邀请队伍"; case .lock: "锁定队伍";
            case .confirm: "确认参与"; case .exit: "退出当前队伍"; case .resume: "恢复原队伍" }
    }
}
