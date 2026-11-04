import SwiftUI

@MainActor struct NativeRpgConditionAuthorEntry: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: NativeRpgConditionAuthorDraft?
    @State private var capture: Capture?
    @State private var review: Review?
    @State private var message: String?
    @State private var bufferRevision = 0
    @State private var saveUnconfirmed = false
    private struct Capture {
        let id = UUID()
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let snapshot: ProjectEditSnapshot
        let bytes: Data
    }
    private struct Review { let id = UUID(); let editorID: UUID; let revision: Int; let value: ProjectEditJSON; let bytes: Data }
    private var available: Bool { scenePhase == .active && model.fullEdit && model.confirmation == nil }
    private var current: Bool {
        guard available, let capture else { return false }
        return model.isCurrentStarterLease(capture.lease) && model.draftMutationRevision == capture.revision
            && model.coordinator.session?.storageNamespace.utf8.elementsEqual(capture.lease.session.storageNamespace.utf8) == true
            && model.coordinator.snapshot == capture.snapshot && ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes
    }
    private func open() {
        guard available, editor == nil, let lease = model.captureStarterLease(), let snapshot = model.coordinator.snapshot,
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return }
        do {
            let value = try NativeRpgConditionAuthorDraft(original: model.draft.preserved["journeyRules"])
            capture = .init(lease: lease, revision: model.draftMutationRevision, snapshot: snapshot, bytes: bytes)
            editor = value; review = nil; message = nil; saveUnconfirmed = false; bufferRevision += 1
        } catch { message = "须已有原 schema2 规则；不覆盖缺失、旧版或未识别配置。" }
    }
    private func mutate(_ id: UUID, revision: Int, _ change: (inout NativeRpgConditionAuthorDraft) -> Void) {
        guard current, capture?.id == id, bufferRevision == revision, var value = editor else { return }
        change(&value); editor = value; review = nil; message = nil; saveUnconfirmed = false; bufferRevision += 1
    }
    private func preview(_ id: UUID, revision: Int) {
        guard current, capture?.id == id, bufferRevision == revision, let editor else { return }
        do {
            let next = try editor.applying(to: model.draft)
            guard let value = next.preserved["journeyRules"], let bytes = ProjectEditPendingMaterials.exactData(next) else { return }
            review = .init(editorID: id, revision: revision, value: value, bytes: bytes); message = nil; saveUnconfirmed = false
        } catch { review = nil; message = "请按原合同明确配置；未写回。" }
    }
    private func apply(_ expected: Review) {
        guard current, let capture, capture.id == expected.editorID, review?.id == expected.id,
              bufferRevision == expected.revision, let editor else { return }
        do {
            let next = try editor.applying(to: model.draft)
            guard ProjectEditPendingMaterials.exactData(next) == expected.bytes else { return }
            if expected.bytes == capture.bytes { retire(); message = "配置未变，保留原字节；没有新增保存或发布。"; return }
            guard model.persistLocalChange(next, lease: capture.lease) else {
                saveUnconfirmed = true; message = "原完整本地草稿保存未确认；编辑和预览保留，可重试本地保存。尚未保存服务器或发布。"; return
            }
            retire(); message = "原保存器已保存完整本地草稿，尚未保存服务器或发布。"
        } catch { review = nil; message = "原项目或配置已变化，未覆盖。" }
    }
    private func close(_ id: UUID) { guard capture?.id == id else { return }; retire() }
    private func retire() { editor = nil; capture = nil; review = nil; saveUnconfirmed = false; bufferRevision += 1 }
    var body: some View {
        Section("原 RPG 状态规则") {
            if editor == nil {
                Button("读取本主题原状态配置") { open() }.disabled(!available)
            } else if let draft = editor, let editorID = capture?.id {
                let editRevision = bufferRevision
                Group {
                    if !current { NativeAuthorNotice(text: Text("项目或会话已变化，请关闭重开，不能写回旧副本。"), tone: .attention) }
                    Toggle("显式启用正式状态（每状态最多2层，总类数5）",isOn:Binding(get:{editor?.enabled ?? false},set:{value in mutate(editorID, revision: editRevision) {$0.configure(value)}}))
                    Button("明确保留当前开关并采用正式容量5") { mutate(editorID, revision: editRevision) {$0.configure(draft.enabled)} }
                    Text("持续沿原正式规则：疲惫3节点，受寒/中暑4，专注1，恐惧/亢奋2；受启发1次主动检定。节点首完才扣持续，GET或重进不扣。休息/成功检定/已知环境沿原事件，不是标签。").nativeAuthorSupportingCopy()
                    Button("预览原状态规则") { preview(editorID, revision: editRevision) }
                    if let review {
                        Text(review.value.text ?? "").font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button(saveUnconfirmed ? "重试保存原完整项目草稿" : "确认保存原完整项目草稿") { apply(review) }.nativeAuthorPrimaryAction()
                    }
                    Text("只写入原 schema2 的状态启用值与正式容量5，仍需原项目保存、请求恢复和发布。模板状态效果编辑尚未接入；本页不改变玩家状态或重置旧局。").nativeAuthorSupportingCopy()
                }.disabled(!current)
                Button("关闭状态编辑副本") { close(editorID) }
            }
            if let message { NativeAuthorNotice(text: Text(message)) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { retire() } }
        .onChange(of: current) { _, valid in if !valid { retire() } }
        .onChange(of: model.editorIncarnation) { _, _ in retire() }
        .onDisappear { retire() }
    }
}
