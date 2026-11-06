import SwiftUI

/// N01 shared policy author. Personal notification preferences remain on their existing screen.
/// Reopening / foreground reads current authority and the original receipt, never auto-submits.
@MainActor struct NativeClubNotificationDefaultView: View {
    @Environment(\.scenePhase) private var phase
    let makeFlow: () -> NativeChannelNotificationCoordinator?
    let sourceCurrent: () -> Bool
    @State private var model: NativeChannelNotificationCoordinator?
    @State private var selection = NativeChannelNotificationLevel.mentions
    @State private var review: Review?
    @State private var attempted = false
    private struct Review: Identifiable {
        let id = UUID()
        let club: String
        let version: Int64
        let level: NativeChannelNotificationLevel
    }
    @Environment(\.themeDomain) private var domain
    var body: some View {
        Form {
            if sourceCurrent(), let model, model.isCurrent {
                if let row = model.clubDefault {
                    Section("俱乐部共同默认，不是我的个人设置") {
                        Text(row.level == .all ? "当前：所有消息" : "当前：仅提及我")
                        Text(row.configured ? "原政策版本 \(row.version)" : "尚未设置，使用正式默认：仅提及我")
                        Picker("共同默认", selection: $selection) {
                            Text("所有消息").tag(NativeChannelNotificationLevel.all)
                            Text("仅提及我").tag(NativeChannelNotificationLevel.mentions)
                        }.disabled(!model.canSaveClubDefault)
                        Button("核对并保存") {
                            review = Review(club: row.clubID, version: row.version, level: selection)
                        }.disabled(!model.canSaveClubDefault)
                        Text("只在成员自己的频道、分类和俱乐部偏好继承时使用；不会取消任何人的静音、免打扰或系统权限。")
                            .font(Theme.Font.label)
                    }
                }
                Section("原请求与当前状态") {
                    if model.isBusy { ProgressView("正在读取原服务") }
                    if let request = model.pendingRequestID {
                        Text("原请求：" + request).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Text("结果未确定时只回读原请求，不重发，也不会另建请求覆盖它。")
                    }
                    if let rejected = model.sharedDefaultRejection {
                        Text(rejected == "CLUB_DEFAULT_VERSION_EXHAUSTED" ? "原请求未写入：政策版本已不可递增。" : "原请求已明确拒绝；不会自动重试。请核对最新政策后重新确认。")
                    }
                    Text(status(model.state)).fixedSize(horizontal: false, vertical: true)
                    Button(model.pendingRequestID == nil ? "重新读取当前政策" : "回读原请求") {
                        review = nil
                        Task { await model.refresh() }
                    }.disabled(model.isBusy || (model.pendingRequestID != nil && !model.canCheckReceipt))
                }
            } else if attempted {
                ContentUnavailableView("共同默认当前不可用", systemImage: "bell.slash",
                    description: Text("需要原俱乐部管理权限及独立通知操作授权；本页不会授予权限。"))
            } else { ProgressView("正在读取原权限") }
        }
        .font(Theme.Font.body)
        .scrollContentBackground(Theme.Generated.color("--cy-color-bg-page", in: domain) != nil ? .hidden : .automatic)
        .background {
            if let background = Theme.Generated.color("--cy-color-bg-page", in: domain) { background }
        }
        .navigationTitle("俱乐部共同通知默认").privacySensitive()
        .task { await reopen() }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await reopen() } } else { clear() }
        }
        .onChange(of: sourceCurrent()) { _, current in if !current { clear() } }
        .onChange(of: model?.clubDefault?.version) { _, _ in
            review = nil; selection = model?.clubDefault?.level ?? .mentions
        }
        .onDisappear { clear() }
        .sheet(item: $review) { item in
            VStack(spacing: 18) {
                Text("修改所有继承此政策的俱乐部频道默认通知").font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
                Text(item.level == .all ? "所有消息" : "仅提及我")
                Text("基于原版本 \(item.version)，不修改成员自己的偏好。")
                Button("确认保存共同默认") {
                    guard sourceCurrent(), let model, model.canSaveClubDefault,
                          model.clubDefault?.clubID == item.club, model.clubDefault?.version == item.version else { review = nil; return }
                    review = nil
                    Task { await model.saveClubDefault(level: item.level, expectedVersion: item.version) }
                }
                Button("取消", role: .cancel) { review = nil }
            }.padding().privacySensitive()
        }
    }
    private func clear() { review = nil; selection = .mentions; model?.deactivate(); model = nil }
    private func reopen() async {
        clear(); attempted = true
        guard sourceCurrent(), let candidate = makeFlow(), candidate.sharedClubDefaultMode else { return }
        model = candidate
        await candidate.activate()
        guard sourceCurrent(), model === candidate else { candidate.deactivate(); return }
        selection = candidate.clubDefault?.level ?? .mentions
    }
    private func status(_ state: NativeChannelNotificationState) -> String {
        switch state {
        case .applied: return "原请求已写入；展示来自重新读取的当前政策。"
        case .appliedRedacted: return "原请求已完成，当前已无权读取结果内容。"
        case .pending, .outcomeUnknown: return "原请求结果待核对，未认定成功或失败。"
        case .persistenceFailed: return "原请求存储不可确认；已停止提交。"
        case .accessClosed: return "原权限已关闭，当前政策已清除。"
        case .refreshFailed, .failed: return "当前状态读取未完成，不使用旧政策代替。"
        default: return "仅使用当前原服务及原请求回执。"
        }
    }
}
