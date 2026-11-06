import SwiftUI

@MainActor struct NativeRpgEnvironmentAuthorEntry: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    private var copy: NativeRpgEnvironmentAuthorPresentation { .init(locale: locale) }
    @State private var editor: NativeRpgEnvironmentAuthorDraft?
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
            let value = try NativeRpgEnvironmentAuthorDraft(original: model.draft.preserved["journeyRules"])
            capture = .init(lease: lease, revision: model.draftMutationRevision, snapshot: snapshot, bytes: bytes)
            editor = value; review = nil; message = nil; saveUnconfirmed = false; bufferRevision += 1
        } catch { message = "须已有原 schema2 规则；不覆盖缺失、旧版或未识别配置。" }
    }
    private func mutate(_ id: UUID, revision: Int, _ change: (inout NativeRpgEnvironmentAuthorDraft) -> Void) {
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
        Section(copy.text("rpgEnvironment.copy.006")) {
            if editor == nil {
                Button(copy.text("rpgEnvironment.copy.007")) { open() }.disabled(!available).accessibilityIdentifier("rpgEnvironment.open")
            } else if let draft = editor, let editorID = capture?.id {
                let editRevision = bufferRevision
                Group {
                    if !current { NativeAuthorNotice(text: Text(copy.text("rpgEnvironment.copy.008")), tone: .attention) }
                    Toggle(copy.text("rpgEnvironment.copy.009"), isOn: Binding(get: { editor?.enabled ?? false }, set: { value in mutate(editorID, revision: editRevision) { $0.configure(enabled: value, authorOverride: draft.authorOverride, location: draft.locationEnabled) } })).frame(minHeight: 44).accessibilityIdentifier("rpgEnvironment.enabled")
                    Toggle(copy.text("rpgEnvironment.copy.010"), isOn: Binding(get: { editor?.authorOverride ?? false }, set: { value in mutate(editorID, revision: editRevision) { $0.configure(enabled: draft.enabled, authorOverride: value, location: draft.locationEnabled) } })).frame(minHeight: 44).accessibilityIdentifier("rpgEnvironment.authorOverride")
                    Toggle(copy.text("rpgEnvironment.copy.011"), isOn: Binding(get: { editor?.locationEnabled ?? false }, set: { value in mutate(editorID, revision: editRevision) { $0.configure(enabled: draft.enabled, authorOverride: draft.authorOverride, location: value) } })).frame(minHeight: 44).accessibilityIdentifier("rpgEnvironment.location")
                    Button(copy.text("rpgEnvironment.copy.012")) { mutate(editorID, revision: editRevision) { $0.configure(enabled: draft.enabled, authorOverride: draft.authorOverride, location: draft.locationEnabled) } }
                    Text(copy.text("rpgEnvironment.copy.013")).nativeAuthorSupportingCopy()
                    Text(copy.text("rpgEnvironment.copy.014")).nativeAuthorSupportingCopy()
                    Button(copy.text("rpgEnvironment.copy.015")) { preview(editorID, revision: editRevision) }.accessibilityIdentifier("rpgEnvironment.review")
                    if let review {
                        Text(verbatim: review.value.text ?? "").font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("rpgEnvironment.preview")
                        Button(saveUnconfirmed ? copy.text("rpgEnvironment.copy.016") : copy.text("rpgEnvironment.copy.017")) { apply(review) }.nativeAuthorPrimaryAction().accessibilityIdentifier("rpgEnvironment.confirm").accessibilityHint(Text(copy.text("rpgEnvironment.localOnly")))
                    }
                }.disabled(!current)
                Button(copy.text("rpgEnvironment.copy.018")) { close(editorID) }.accessibilityIdentifier("rpgEnvironment.close")
            }
            if let message { NativeAuthorNotice(text: Text(verbatim: copy.message(message))).accessibilityIdentifier("rpgEnvironment.notice") }
        }
        .accessibilityIdentifier("rpgEnvironment.author")
        .onChange(of: scenePhase) { _, phase in if phase != .active { retire() } }
        .onChange(of: current) { _, valid in if !valid { retire() } }
        .onChange(of: model.editorIncarnation) { _, _ in retire() }
        .onDisappear { retire() }
    }
}
