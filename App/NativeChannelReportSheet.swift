import SwiftUI

@MainActor struct NativeChannelReportSheet: View {
    @Environment(\.themeDomain) private var domain
    let owner: NativeChannelReportFlow
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if owner.isCurrent {
                    Form {
                        if let message = owner.messageID { Text("消息 \(message)").fixedSize(horizontal: false, vertical: true) }
                        switch owner.state {
                        case .reviewing:
                            Picker("举报原因", selection: Binding(get: { owner.selectedReason }, set: { owner.select(reason: $0, note: owner.note) })) {
                                Text("请选择原因").tag(Optional<NativeChannelReportReason>.none)
                                ForEach(NativeChannelReportReason.allCases) { reason in
                                    Text(reason.title).tag(Optional(reason))
                                }
                            }
                            TextField("补充说明（选填，最多 500 字）", text: Binding(get: { owner.note }, set: { owner.select(reason: owner.selectedReason, note: $0) }), axis: .vertical).lineLimit(3...8)
                            Text("提交只表示已进入原审核队列，不代表内容已被判定违规或下架。")
                            Button("确认提交举报") { Task { await owner.submit() } }.nativeChannelFlowAction()
                                .disabled(!owner.canSubmit || owner.selectedReason == nil || owner.note.utf16.count > 500)
                        case .submitting, .reading: ProgressView()
                        case .unknown:
                            NativeChannelFlowNotice(title:Text("结果尚未确认。保留原举报请求，不会自动重复提交。"),symbol:"clock.arrow.circlepath")
                            if let reason = owner.selectedReason { Text(reason.title) }
                            Button("读取原举报结果") { Task { await owner.recover() } }.disabled(!owner.canRecover)
                            Button("核对原结果后重试同一请求") { Task { await owner.submit() } }.disabled(!owner.canSubmit)
                            Text("先读取原回执；只有原服务明确允许原请求重试时才发送相同内容。未知或处理中不会重发。")
                        case .acknowledged(let reportID, let status):
                            Text("已确认原举报记录：\(reportID)").fixedSize(horizontal: false, vertical: true)
                            Text("当前状态：\(status)").fixedSize(horizontal: false, vertical: true)
                            Text("这不是对消息违规或下架的判定。")
                        case .unavailable: NativeChannelFlowNotice(title:Text("原请求记录或当前权限不可用，未发送新请求。"),symbol:"lock.shield")
                        case .idle: Text("请先选择要举报的原消息。")
                        }
                    }
                    .formStyle(.grouped)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary(in: domain))
                } else { Text("会话权限已变化，已隐藏原操作。") }
            }
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .nativeChannelFlowPage()
            .navigationTitle("举报消息")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .tint(Theme.Color.accent(in: domain))
    }
}
