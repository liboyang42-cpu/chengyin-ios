import SwiftUI

@MainActor struct CreatorApplicationView: View {
    let coordinator: CreatorApplicationCoordinator
    /// Existing center reader supplies status; normal host recreates on reader.scope changes.
    let reader: any CreatorContentReading
    let onCenterRefresh: () -> Void
    @State private var name = ""; @State private var bio = ""
    @State private var center: CreatorContentCenter?
    @State private var review: CreatorApplicationReview?
    @State private var busy = false; @State private var message = ""
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        Form {
            if center?.status == .notApplied {
                TextField(zh ? "创作者名称" : "Creator name", text: $name).accessibilityIdentifier("creatorApplication.name")
                TextField(zh ? "简介（选填）" : "Bio (optional)", text: $bio, axis: .vertical).accessibilityIdentifier("creatorApplication.bio")
                Text(zh ? "仅首次申请；真实提交尚未启用。" : "First applications only. Live submission remains disabled.")
                Button(zh ? "审阅申请" : "Review application") { Task {
                    busy = true; defer { busy = false }
                    do { review = try await coordinator.prepare(CreatorApplicationDraft(creatorName: name, bio: bio)) }
                    catch { message = PublisherLifecycleCopy.error(error, zh: zh) }
                } }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("creatorApplication.review")
            } else if center?.status == .rejected {
                Text(zh ? "已有申请档案，服务器不支持重新申请。" : "An application profile already exists. The server does not support reapplication.").accessibilityIdentifier("creatorApplication.rejected")
                Text(center?.rejectReason ?? "")
            } else { Text(center?.status.rawValue ?? (zh ? "正在读取状态" : "Loading status")) }
            if let review {
                Section(zh ? "申请审阅" : "Application review") {
                    Text(review.draft.creatorName); Text(review.draft.bio ?? "")
                    Text(zh ? "将向创作者审核服务提交上述资料。" : "Submit these details to the creator application service.")
                    Button(zh ? "确认提交" : "Confirm submission") { Task {
                        busy = true; let result = await coordinator.confirm(review, approved: true)
                        switch result {
                        case .submitted(let updated): center = updated; message = zh ? "申请已提交。状态待刷新核实。" : "Application submitted. Refresh to verify status."; onCenterRefresh()
                        case .notSaved: message = zh ? "服务器未保存申请。" : "The server did not save this application."
                        case .notSent: message = zh ? "未发送。提交权限未启用或审阅过期。" : "Not sent. Submission is disabled or review expired."
                        case .unknown: message = zh ? "结果未知。请刷新核实，勿重复提交。" : "Outcome unknown. Refresh to verify; do not resubmit."
                        case .rejected(let text): message = text
                        }
                        self.review = nil; busy = false
                    } }.disabled(busy).accessibilityIdentifier("creatorApplication.confirm")
                }
            }
            Text(message).accessibilityIdentifier("creatorApplication.message")
            Button(zh ? "刷新状态" : "Refresh status") { Task { await refresh() } }.disabled(busy)
        }.navigationTitle(zh ? "申请成为创作者" : "Apply as a creator")
        .task { await refresh() }
        .onChange(of: name) { _, _ in clear() }.onChange(of: bio) { _, _ in clear() }
        .onDisappear { clear() }.onChange(of: phase) { _, value in if value != .active { clear() } }
    }
    private func clear() { coordinator.invalidate(); review = nil }
    private func refresh() async {
        clear(); busy = true; defer { busy = false }
        do { center = try await reader.center() } catch { center = nil; message = PublisherLifecycleCopy.error(error, zh: zh) }
    }
}
