import SwiftUI

@MainActor struct NativeSharedRecoveryAuthorEntry: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: NativeSharedRecoveryAuthorDraft?
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
            let value = try NativeSharedRecoveryAuthorDraft(draft: model.draft)
            capture = .init(lease: lease, revision: model.draftMutationRevision, snapshot: snapshot, bytes: bytes)
            editor = value; review = nil; message = nil; saveUnconfirmed = false; bufferRevision += 1
        } catch { message = "须已有原 TEAM 主题、任务与幕目录，且恢复定义符合当前 REST／RESCUE 合同。新版或未知定义保留原文，不自动创建、降级或改写。" }
    }
    private func mutate(_ id: UUID?, revision: Int, _ change: (inout NativeSharedRecoveryAuthorDraft) -> Void) {
        guard let id, current, capture?.id == id, bufferRevision == revision, var value = editor else { return }
        change(&value); editor = value; review = nil; message = nil; saveUnconfirmed = false; bufferRevision += 1
    }
    private func preview(_ id: UUID, revision: Int) {
        guard current, capture?.id == id, bufferRevision == revision, let editor else { return }
        do {
            let next = try editor.applying(to: model.draft)
            guard let value = next.preserved["themeRuntimeConfig"], let bytes = ProjectEditPendingMaterials.exactData(next) else { return }
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
    private func binding(_ index: Int, _ key: String) -> Binding<String> {
        let id = capture?.id, revision = bufferRevision
        return Binding(get: { current && capture?.id == id && bufferRevision == revision ? editor?.text(index,key) ?? "" : "" },
            set: { value in mutate(id, revision: revision) { $0.edit(index,key,value) } })
    }
    var body: some View {
        Section("原共享队伍恢复定义") {
            if model.fullEdit, let snapshot = model.coordinator.snapshot, snapshot.topicID != nil,
               let saved = try? NativeSharedRecoveryAuthorDraft(draft:snapshot.draft) {
                DisclosureGroup("本次原项目读取基线：\(saved.recoveries.count)种恢复") {
                    ForEach(Array(saved.recoveries.enumerated()),id:\.offset) { index,_ in
                        Text(saved.text(index,"recoveryKey") + " · " + saved.text(index,"kind") + " · " + saved.text(index,"limit") + "次")
                        if saved.text(index,"kind") == "REST" { Text("生命增加量：" + saved.text(index,"hpDelta")) }
                        else { Text("生命下限：" + saved.text(index,"hpFloor")) }
                        Text(saved.actKeys(index).isEmpty ? "原规则：不限定幕" : "原限用幕：" + saved.actKeys(index).joined(separator:", "))
                    }
                    Text(saved.noEffectPolicy == "true" ? "原规则：无效果仍消耗次数。" : "原规则：无效果不消耗次数。")
                    Text("这是编辑器本次读取的原基线，不是下方尚未保存的编辑副本，也不代表旧局已更新。").font(.caption)
                }
            }
            if editor == nil {
                Button("编辑当前共享玩法的恢复定义") { open() }.disabled(!available)
            } else if let draft = editor, let editorID = capture?.id {
                let editRevision = bufferRevision
                Group {
                    if !current { NativeAuthorNotice(text: Text("原项目、会话或草稿已变化，须关闭重开；旧副本不能写回。"), tone: .attention) }
                    Text("仅编辑原 TEAM survival.recoveries。休整使用填写的团队 HP 增加量；救助使用生命下限，仍由原上限、次数和回执结算。不会恢复本人资源、加 XP，或把配给消耗、购买和救援改成补给。").nativeAuthorSupportingCopy()
                    Picker("所有恢复方式的无效果次数规则",selection:Binding(get:{editor?.noEffectPolicy ?? ""},set:{value in mutate(editorID, revision: editRevision) {$0.noEffectPolicy(value)}})) {
                        Text("原缺省：不消耗，不写该字段").tag("")
                        Text("显式不消耗").tag("false")
                        Text("显式仍消耗一次").tag("true")
                    }
                    if draft.recoveries.isEmpty { Text("当前没有恢复方式；不会自动添加默认休息。") }
                    ForEach(Array(draft.recoveries.enumerated()),id:\.offset) { index,_ in recoveryRow(index,draft:draft) }
                    Button("添加空白恢复方式") { mutate(editorID, revision: editRevision) { $0.appendBlank() } }.disabled(draft.recoveries.count >= 20)
                    ForEach(Array(draft.issues.enumerated()),id:\.offset) { _,issue in NativeAuthorNotice(text: Text(issue), tone: .attention) }
                    Button("预览原恢复定义修改") { preview(editorID, revision: editRevision) }.disabled(!draft.issues.isEmpty)
                    if let review {
                        Text(review.value.text ?? "").font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button(saveUnconfirmed ? "重试保存原完整项目草稿" : "确认保存原完整项目草稿") { apply(review) }.nativeAuthorPrimaryAction()
                    }
                    Text("随后使用原项目保存、同请求结果恢复及发布。保存后的原项目重载显示读取基线；新共享局按发布快照提供恢复方式，旧局和已保存动作不被追改。").nativeAuthorSupportingCopy()
                }.disabled(!current)
                Button("关闭恢复定义编辑副本") { close(editorID) }
            }
            if let message { NativeAuthorNotice(text: Text(message)) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { retire() } }
        .onChange(of: current) { _, valid in if !valid { retire() } }
        .onChange(of: model.editorIncarnation) { _, _ in retire() }
        .onDisappear { retire() }
    }
    @ViewBuilder private func recoveryRow(_ index: Int, draft: NativeSharedRecoveryAuthorDraft) -> some View {
        let editorID = capture?.id, editRevision = bufferRevision
        VStack(alignment:.leading,spacing:8) {
            Text("恢复方式 \(index + 1)").font(.headline)
            TextField("明确填写原恢复标识",text:binding(index,"recoveryKey")).textInputAutocapitalization(.never).autocorrectionDisabled()
            Picker("原恢复种类",selection:binding(index,"kind")) {
                Text("请选择，不预设").tag(""); Text("休整 REST").tag("REST"); Text("救助 RESCUE").tag("RESCUE")
            }
            TextField("明确次数上限 1–99",text:binding(index,"limit")).keyboardType(.numberPad)
            if draft.text(index,"kind") == "REST" { TextField("明确生命增加量 1–999",text:binding(index,"hpDelta")).keyboardType(.numberPad) }
            if draft.text(index,"kind") == "RESCUE" { TextField("明确生命下限 1–999",text:binding(index,"hpFloor")).keyboardType(.numberPad) }
            Text(draft.actKeys(index).isEmpty ? "当前不限定幕；可从原幕目录选择限用范围。" : "仅限以下已勾选原幕。")
            ForEach(Array(Set(draft.acts + draft.actKeys(index))).sorted(),id:\.self) { key in
                Toggle(draft.acts.contains(key) ? key : key + "（已不在原幕目录，须移除）",isOn:Binding(
                    get:{editor?.actKeys(index).contains(key) == true},set:{value in mutate(editorID, revision: editRevision) {$0.selectAct(index,key:key,selected:value)}}))
            }
            Button("从本地副本移除此方式",role:.destructive) { mutate(editorID, revision: editRevision) { $0.remove(index) } }
        }
    }
}
