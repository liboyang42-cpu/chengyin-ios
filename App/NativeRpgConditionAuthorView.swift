import SwiftUI

@MainActor struct NativeRpgConditionAuthorEntry: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    private var copy: NativeRpgConditionAuthorPresentation { .init(locale: locale) }
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
        Section(copy.text("rpgCondition.copy.006")) {
            if editor == nil {
                Button(copy.text("rpgCondition.copy.007")) { open() }.disabled(!available).accessibilityIdentifier("rpgCondition.open")
            } else if let draft = editor, let editorID = capture?.id {
                let editRevision = bufferRevision
                Group {
                    if !current { NativeAuthorNotice(text: Text(copy.text("rpgCondition.copy.008")), tone: .attention) }
                    Toggle(copy.text("rpgCondition.copy.009"),isOn:Binding(get:{editor?.enabled ?? false},set:{value in mutate(editorID, revision: editRevision) {$0.configure(value)}})).frame(minHeight: 44).accessibilityIdentifier("rpgCondition.enabled")
                    Button(copy.text("rpgCondition.copy.010")) { mutate(editorID, revision: editRevision) {$0.configure(draft.enabled)} }.accessibilityIdentifier("rpgCondition.keep")
                    Text(copy.text("rpgCondition.copy.011")).nativeAuthorSupportingCopy()
                    Button(copy.text("rpgCondition.copy.012")) { preview(editorID, revision: editRevision) }.accessibilityIdentifier("rpgCondition.review")
                    if let review {
                        Text(verbatim: review.value.text ?? "").font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("rpgCondition.preview")
                        Button(saveUnconfirmed ? copy.text("rpgCondition.copy.013") : copy.text("rpgCondition.copy.014")) { apply(review) }.nativeAuthorPrimaryAction().accessibilityIdentifier("rpgCondition.confirm").accessibilityHint(Text(copy.text("rpgCondition.localOnly")))
                    }
                    Text(copy.text("rpgCondition.copy.015")).nativeAuthorSupportingCopy()
                }.disabled(!current)
                Button(copy.text("rpgCondition.copy.016")) { close(editorID) }.accessibilityIdentifier("rpgCondition.close")
            }
            if let message { NativeAuthorNotice(text: Text(verbatim: copy.message(message))).accessibilityIdentifier("rpgCondition.notice") }
        }
        .accessibilityIdentifier("rpgCondition.author")
        .onChange(of: scenePhase) { _, phase in if phase != .active { retire() } }
        .onChange(of: current) { _, valid in if !valid { retire() } }
        .onChange(of: model.editorIncarnation) { _, _ in retire() }
        .onDisappear { retire() }
    }
}
