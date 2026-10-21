import SwiftUI

/// Store authoring flow. Review lines are read from server evidence; this view has no approval action.
struct MerchantAuthoringView: View {
    @Bindable var coordinator: MerchantAuthoringCoordinator
    let owner: MerchantAuthoringOwner

    var body: some View {
        Form {
            if coordinator.owner != owner {
                Text(verbatim: "私有内容已清除")
            } else {
            switch coordinator.phase {
            case .list, .returned:
                Text(verbatim: "本店草稿")
                Button { Task { await coordinator.reload() } } label: { Text(verbatim: "刷新") }
                    .accessibilityIdentifier("merchant.authoring.list")
                Button { Task { await coordinator.beginNew() } } label: { Text(verbatim: "新建草稿") }
                    .accessibilityIdentifier("merchant.authoring.new")
            case .drafting:
                fields
                Button { Task { await coordinator.generate() } } label: { Text(verbatim: "生成") }
                    .accessibilityIdentifier("merchant.authoring.generate")
            case .generating:
                ProgressView()
                Text(verbatim: "正在生成")
                Button { Task { await coordinator.cancel() } } label: { Text(verbatim: "取消") }
                    .accessibilityIdentifier("merchant.authoring.cancel")
            case .unknown:
                Text(verbatim: "结果未知，只查询原任务")
                Text(verbatim: coordinator.themeMainLineBlocked ? "" : "主题主线仍可继续")
                Button { Task { await coordinator.queryOriginal() } } label: { Text(verbatim: "查询原任务") }
                    .accessibilityIdentifier("merchant.authoring.query")
                Button { Task { await coordinator.openMainLine() } } label: { Text(verbatim: "主题主线") }
                    .accessibilityIdentifier("merchant.authoring.mainLine")
            case .editing:
                fields
                Button { Task { await coordinator.save() } } label: { Text(verbatim: "保存") }
                    .accessibilityIdentifier("merchant.authoring.save")
                Button { Task { await coordinator.loadReview() } } label: { Text(verbatim: "查看审核状态") }
                    .accessibilityIdentifier("merchant.authoring.review")
            case .review:
                if let presentation = coordinator.presentation {
                    Text(verbatim: presentation.merchantFactsReviewStatus)
                    Text(verbatim: presentation.themeContentReviewStatus)
                    Text(verbatim: presentation.clientMaySelfApprove ? "" : "客户端不能自行批准")
                }
                Button { coordinator.showPublishConfirm() } label: { Text(verbatim: "去发布确认") }
                    .accessibilityIdentifier("merchant.authoring.publish")
            case .publishConfirm:
                Text(verbatim: "确认后提交发布，取消不会变成已发布")
                Button { Task { await coordinator.confirmPublish() } } label: { Text(verbatim: "确认发布") }
                    .accessibilityIdentifier("merchant.authoring.publish")
                Button { Task { await coordinator.cancel() } } label: { Text(verbatim: "取消") }
                    .accessibilityIdentifier("merchant.authoring.cancel")
            case .readBack:
                Text(verbatim: "权威回读 \(coordinator.releaseID ?? "")")
                Button { Task { await coordinator.readBack() } } label: { Text(verbatim: "再次回读") }
                    .accessibilityIdentifier("merchant.authoring.readback")
                Button { Task { await coordinator.previewPublic() } } label: { Text(verbatim: "公开预览") }
                    .accessibilityIdentifier("merchant.authoring.preview")
            case .preview:
                if let read = coordinator.publicRead {
                    Text(verbatim: read.releaseID)
                    ForEach(read.facts.keys.sorted(), id: \.self) { key in Text(verbatim: key + "=" + (read.facts[key] ?? "")) }
                }
                Button { Task { await coordinator.finish() } } label: { Text(verbatim: "返回") }
                    .accessibilityIdentifier("merchant.authoring.back")
            case .cancelled:
                Text(verbatim: "已取消，未发布")
                Button { Task { await coordinator.finish() } } label: { Text(verbatim: "返回") }
                    .accessibilityIdentifier("merchant.authoring.back")
            }
            if let note = coordinator.statusNote { Text(verbatim: note) }
            if let refusal = coordinator.refusal { Text(verbatim: String(describing: refusal)) }
            }
        }
        .navigationTitle(Text(verbatim: "本店 AI 草稿"))
        .task { coordinator.restore(owner) }
        .onChange(of: owner) { _, new in coordinator.adopt(new) }
    }

    @ViewBuilder private var fields: some View {
        TextField(text: $coordinator.scene) { Text(verbatim: "场景") }
        TextField(text: $coordinator.binding) { Text(verbatim: "主题绑定") }
        TextField(text: $coordinator.templateID) { Text(verbatim: "已批准模板") }
        TextField(text: $coordinator.prompt) { Text(verbatim: "生成说明") }
        TextField(text: $coordinator.plot) { Text(verbatim: "剧情") }
        TextField(text: $coordinator.variablesText) { Text(verbatim: "允许变量") }
        TextField(text: $coordinator.branchesText) { Text(verbatim: "已批准分支") }
        TextField(text: $coordinator.rulesText) { Text(verbatim: "服务端动作规则") }
        TextField(text: $coordinator.durationText) { Text(verbatim: "时长分钟") }
        TextField(text: $coordinator.participantsText) { Text(verbatim: "人数") }
        TextField(text: $coordinator.businessHours) { Text(verbatim: "营业时段") }
        TextField(text: $coordinator.noise) { Text(verbatim: "噪音与拍摄") }
        TextField(text: $coordinator.accessible) { Text(verbatim: "无障碍替代") }
        TextField(text: $coordinator.offline) { Text(verbatim: "离线替代") }
        TextField(text: $coordinator.failureExit) { Text(verbatim: "失败退出") }
        TextField(text: $coordinator.rewardRuleID) { Text(verbatim: "奖励规则编号") }
        Button { coordinator.reward = .noReward } label: { Text(verbatim: "无奖励") }
        Button { let id = coordinator.rewardRuleID.trimmingCharacters(in: .whitespacesAndNewlines); if !id.isEmpty { coordinator.reward = .approvedRule(id: id) } } label: { Text(verbatim: "引用已批准奖励规则") }
        TextField(text: $coordinator.skuID) { Text(verbatim: "既有 SKU") }
        Button { coordinator.needsStaff = true } label: { Text(verbatim: "需要店员") }
        Button { coordinator.needsStaff = false } label: { Text(verbatim: "不需要店员") }
    }
}
