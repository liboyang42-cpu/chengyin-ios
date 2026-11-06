import SwiftUI

/// Original public game facts and original NPC receipts. Published facts are not an executable game.
/// A real game renderer requires its original runtime/authority factory; this view never invents one.
struct MerchantGamePlayerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Bindable var coordinator: MerchantGamePlayerCoordinator
    let chat: AnyView?
    @State private var confirmAcknowledge = false
    @State private var didRequestExit = false
    @State private var isPresented = false

    var body: some View {
        Group {
            if coordinator.active { playerContent }
            else { failureCard(coordinator.failure ?? .stale) }
        }
        .privacySensitive()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .navigationTitle(copy("Store content and original reply", "店内内容与原回复"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(copy("Close", "关闭"))
                    .accessibilityIdentifier("merchant.game.player.close")
            }
        }
        .task {
            coordinator.activate()
            await coordinator.load()
            dismissIfRevoked()
        }
        .onAppear { isPresented = true; didRequestExit = false }
        .onDisappear { isPresented = false; confirmAcknowledge = false; coordinator.revoke() }
        .onChange(of: coordinator.active) { _, active in
            if !active { dismissIfRevoked() }
        }
        .onChange(of: scenePhase) { _, phase in
            confirmAcknowledge = false
            guard isPresented else { return }
            if phase == .active {
                coordinator.activate()
                Task { await coordinator.load(); dismissIfRevoked() }
            } else { coordinator.revoke() }
        }
        .alert(isPresented: $confirmAcknowledge) {
            Alert(title: copy("Close the verified terminal request?", "关闭已核实的终态请求？"),
                  message: copy("Only this local pending marker will be removed. The server reply is not deleted, and AI will not be called again. Any new question is a separate explicit action.", "仅移除本地待确认标记，不删除服务端回复，也不再次调用 AI。新问题需要另行明确发送。"),
                  primaryButton: .default(copy("Close this pending record", "关闭该待确认记录")) { coordinator.acknowledgeOriginal() },
                  secondaryButton: .cancel())
        }
    }
    private var playerContent: some View {
        Form {
            Section(header: copy("Current published content", "当前发布内容")) {
                copy("Published facts only. This page does not start a playable game. The current publication does not prove which version an earlier request used.", "这里只展示已发布资料，不启动可玩游戏。当前发布版本不代表之前请求采用的版本。")
                if let publication = coordinator.publication {
                    switch publication {
                    case .none: copy("No published in-store game is available.", "暂无已发布店内游戏。")
                    case .withdrawn: copy("This game has been withdrawn. An older version will not be restored.", "该游戏已撤回，不会恢复使用旧版本。")
                    case .published(let releaseID, let version, let facts):
                        LabeledContent { Text(verbatim: "\(releaseID) · v\(version)") } label: { copy("Release and revision", "发布与内容版本") }
                        ForEach(facts.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 6) {
                                fieldLabel(key).font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: facts[key] ?? "").lineLimit(nil).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }.accessibilityElement(children: .combine)
                        }
                    }
                }
                Button { Task { await coordinator.load() } } label: { copy("Refresh", "刷新") }
                if let chat {
                    NavigationLink { chat } label: { copy("Ask the existing store NPC", "进入本店 NPC 对话") }
                        .disabled(!coordinator.canOpenChat)
                        .accessibilityIdentifier("merchant.game.player.npc")
                }
                copy("A publication or NPC reply is not proof of game completion, rewards or redemption. Safety exits remain controlled by the server.", "发布内容或 NPC 回复不代表通关、奖励或核销。安全退出仍由服务端决定。")
            }
            Section(header: copy("Original request result", "原请求结果")) {
                if let pending = coordinator.pending {
                    LabeledContent { Text(verbatim: pending.operationID.uuidString) } label: { copy("Original request ID", "原请求编号") }
                    copy("Reads the stored result only. It does not resend a question or call AI.", "只读取已存结果，不重新发送问题或调用 AI。")
                    Button { Task { await coordinator.readOriginal() } } label: { copy("Read original result", "读取原结果") }
                        .accessibilityIdentifier("merchant.game.player.readOriginal")
                } else if !coordinator.busy && coordinator.failure == nil { (coordinator.acknowledged ? copy("The terminal result was read and its local pending marker was closed. No new request was sent.", "已回读终态并关闭本地待确认记录，没有发送新请求。") : copy("No pending request is recorded for this account and store.", "当前账号在本店没有待确认请求。")) }
                if let result = coordinator.original {
                    status(result)
                    if !result.safeText.isEmpty { Text(verbatim: result.safeText).font(.body).lineSpacing(4).textSelection(.enabled).accessibilityIdentifier("merchant.game.player.originalText") }
                    if result.terminal && coordinator.pending != nil {
                        Button { confirmAcknowledge = true } label: { copy("Close this pending record", "关闭该待确认记录") }
                            .disabled(!coordinator.canAcknowledge)
                            .accessibilityIdentifier("merchant.game.player.closePending")
                    }
                }
            }
            if let failure = coordinator.failure { failureCard(failure) }
            if coordinator.busy { ProgressView() }
        }
        .formStyle(.grouped)
        .disabled(coordinator.busy)
    }
    private func failureCard(_ failure: MerchantGamePlayerFailure) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { message(failure) } icon: {
                Image(systemName: failureIcon(failure))
            }
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("merchant.game.player.failure")
    }
    private func failureIcon(_ failure: MerchantGamePlayerFailure) -> String {
        switch failure {
        case .configuration: return "lock.circle"
        case .unauthorized, .stale: return "hand.raised"
        case .unknown: return "wifi.exclamationmark"
        case .malformed: return "exclamationmark.circle"
        }
    }
    /// Respond only to the original coordinator's terminal authority state while foreground.
    /// Background suspension also revokes the projection, so it alone must not pop navigation.
    private func dismissIfRevoked() {
        guard isPresented, scenePhase == .active, !coordinator.active, !didRequestExit else { return }
        didRequestExit = true
        confirmAcknowledge = false
        dismiss()
    }
    private func status(_ result: MerchantGamePlayerOriginal) -> Text {
        if result.retryable { return copy("The original request remains retryable. Keep its pending record; this read does not retry or send a replacement.", "原请求仍可重试，请保留待确认记录。此次回读不会重试或发送替代请求。") }
        if result.outcome == "PROCESSING" { return copy("The original request is still unresolved. Keep its ID; do not send a replacement.", "原请求仍待确认，请保留原编号，不要用新请求替代。") }
        if result.errorCode == "MERCHANT_ENVIRONMENT_EXIT" { return copy("Original fixed safety exit", "原请求的固定安全退出") }
        if result.succeeded { return copy("Original NPC reply is available", "原 NPC 回复已回读") }
        return copy("The original request ended without success.", "原请求已结束，但并未成功。")
    }
    private func message(_ failure: MerchantGamePlayerFailure) -> Text {
        switch failure {
        case .configuration: return copy("This read endpoint has not been independently enabled. Chat or authoring approval does not enable it.", "该只读接口尚未独立启用，对话或编辑权限不会自动启用它。")
        case .unauthorized, .stale: return copy("Your account or permission changed. Private content was cleared; reopen this page.", "身份或权限已变化，私有内容已清除，请重新进入。")
        case .unknown, .malformed:
            if coordinator.pending != nil { return copy("The content or original result could not be verified. Its pending marker has been retained.", "无法核实内容或原结果，已保留待确认记录。") }
            return copy("The published content could not be verified. No new request was sent.", "暂时无法核实发布内容，没有发送新请求。")
        }
    }
    // View-private copy: the public baseline has no MerchantAuthoring string table.
    private func copy(_ english: String, _ chinese: String) -> Text {
        Text(verbatim: locale.identifier.hasPrefix("zh") ? chinese : english)
    }
    private func fieldLabel(_ key: String) -> Text {
        switch key {
        case "store_knowledge": return copy("Store knowledge", "店铺知识")
        case "service_information": return copy("Service information", "服务信息")
        case "canonical_plot": return copy("Plot", "剧情")
        case "allowed_variables": return copy("Allowed variables", "允许变量")
        case "approved_branches": return copy("Approved branches", "已批准分支")
        case "server_action_rules": return copy("Server action rules", "服务端动作规则")
        case "duration_minutes": return copy("Duration in minutes", "时长分钟")
        case "headcount": return copy("Maximum participants", "人数上限")
        case "business_segment": return copy("Business hours segment", "营业时段")
        case "staff_need": return copy("Staff requirement", "店员需求")
        case "noise_limit": return copy("Noise limits", "噪音限制")
        case "photo_limit": return copy("Photography limits", "拍摄限制")
        case "accessibility_alternative": return copy("Accessible alternative", "无障碍替代")
        case "offline_alternative": return copy("Offline alternative", "断网替代")
        case "fail_exit": return copy("Failure exit", "失败退出")
        case "reward_rule_ref": return copy("Existing reward rule reference", "现有奖励规则引用")
        case "product_facts": return copy("Product source facts", "商品来源事实")
        case "product_id": return copy("Product ID", "商品 ID")
        case "sku_id": return copy("SKU ID", "SKU ID")
        default: return copy("Field label unavailable", "字段标签不可用")
        }
    }

}
