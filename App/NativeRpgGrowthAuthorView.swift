import SwiftUI

@MainActor struct NativeRpgGrowthAuthorEntrySection: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var author: NativeRpgGrowthAuthorController
    init(model: ProjectEditModel) { self.model = model; _author = StateObject(wrappedValue: NativeRpgGrowthAuthorController(project: model)) }
    var body: some View {
        Section("主题角色成长规则") {
            if author.editor == nil {
                Text("沿已有 RPG 角色配置编辑本主题成长曲线，不与平台经验互相换算。不会创建缺失角色模板或自动开启成长。")
                Button("读取原成长配置") { author.open() }.disabled(!author.available)
            } else {
                if !author.isCurrent { NativeAuthorNotice(text: Text("原项目已变化，请重新读取；不会覆盖其他编辑。"), tone: .attention) }
                editor.disabled(!author.isCurrent)
                let editorID = author.editorID
                Button("关闭成长编辑副本", role: .cancel) { author.close(editorID: editorID) }
            }
            if let notice = author.notice { NativeAuthorNotice(text: Text(notice)) }
        }
        .onAppear { author.setSceneActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in author.setSceneActive(phase == .active) }
        .onChange(of: author.isCurrent) { _, current in if !current { author.retireIfInvalid() } }
        .onChange(of: model.editorIncarnation) { _, _ in author.retire() }
        .onDisappear { author.setSceneActive(false) }
    }
    @ViewBuilder private var editor: some View {
        if let draft = author.editor, let editorID = author.editorID {
            Text("正式 XP 来源：节点完成 10；成功 5；大成功 10；红检通过 20；发现线索 5；章节完成 30。实际仅由对应原事件提交，不能在此发经验。").nativeAuthorSupportingCopy()
            Text("等级 4、8 各有一个原专长位；技能单项上限 10。升级资源恢复沿原 LEVEL_UP 事件。")
            if !draft.roleEnabled { Text("当前原角色模块未启用，不能开启成长；不会借此按钮开角色权限。") }
            Button("明确填入正式 36 的十级曲线与每级 1 点") { author.mutate(editorID: editorID, changesThresholds: true) { $0.useFormalCurve() } }
            if let growth = draft.growth {
                Toggle("显式启用本主题成长", isOn: author.enabled)
                TextField("等级上限（1–20）", text: author.number("maxLevel"))
                TextField("每级技能点", text: author.number("skillPointsPerLevel"))
                Text("以下为累计 XP 阈值，必须严格递增，条数等于等级上限减一；不会按输入等级自动猜测或倍增。")
                ForEach(Array((growth["xpThresholds"]?.array ?? []).enumerated()), id: \.offset) { index, _ in
                    TextField("升至等级 \(index + 2) 的累计 XP", text: author.threshold(index))
                }
                Button("添加一项空阈值") { author.mutate(editorID: editorID, changesThresholds: true) { $0.addThreshold() } }
                Button("移除末项阈值", role: .destructive) { author.mutate(editorID: editorID, changesThresholds: true) { $0.removeLastThreshold() } }
                Text("可选专长范围：")
                if growth["feats"] == nil {
                    Text("沿原正式六种专长，不改变原缺省语义。")
                    Button("显式选择专长子集") { author.mutate(editorID: editorID) { $0.set("feats", .array([])) } }
                } else {
                    ForEach(NativeRpgGrowthAuthorDraft.featKeys, id: \.self) { key in Toggle(key, isOn: author.feat(key)) }
                }
                Button("预览本地成长修改") { author.preview(editorID: editorID) }
                if let review = author.review {
                    Text(review.value.text ?? "") .font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Button(author.saveUnconfirmed ? "重试保存原项目本地草稿" : "确认写回并保存原项目草稿") { author.apply(review) }.nativeAuthorPrimaryAction()
                    Text("先由原保存器确认完整本地草稿保存成功，再关闭此副本；本地失败保留编辑。仍须使用页面原云保存／发布，服务器按本版本角色与属性定义校验并冻结。").nativeAuthorSupportingCopy()
                }
            }
        }
    }
}
@MainActor final class NativeRpgGrowthAuthorController: ObservableObject {
    private let project: ProjectEditModel
    private struct Capture {
        let id: UUID
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let snapshot: ProjectEditSnapshot
        let bytes: Data
    }
    struct Review: Identifiable {
        let id = UUID()
        let editorID: UUID
        let bufferRevision: Int
        let value: ProjectEditJSON
    }
    private var capture: Capture?
    @Published private(set) var editorID: UUID?
    @Published private(set) var editor: NativeRpgGrowthAuthorDraft?
    @Published private(set) var review: Review?
    @Published private(set) var notice: String?
    @Published private(set) var sceneActive = false
    @Published private(set) var saveUnconfirmed = false
    private var bufferRevision = 0
    private var thresholdRevision = 0
    init(project: ProjectEditModel) { self.project = project }
    var available: Bool { sceneActive && project.fullEdit && project.confirmation == nil }
    var isCurrent: Bool {
        guard available, let capture, editorID == capture.id else { return false }
        return project.isCurrentStarterLease(capture.lease)
            && capture.revision == project.draftMutationRevision
            && project.coordinator.session?.storageNamespace.utf8.elementsEqual(capture.lease.session.storageNamespace.utf8) == true
            && capture.snapshot == project.coordinator.snapshot
            && ProjectEditPendingMaterials.exactData(project.draft) == capture.bytes
    }
    private func accepts(_ id: UUID?) -> Bool { id != nil && id == editorID && isCurrent }
    func open() {
        guard available, editor == nil, let lease = project.captureStarterLease(),
              let snapshot = project.coordinator.snapshot,
              let bytes = ProjectEditPendingMaterials.exactData(project.draft) else { return }
        do {
            let next = try NativeRpgGrowthAuthorDraft(original: project.draft.preserved["journeyRules"])
            let id = UUID()
            capture = .init(id: id, lease: lease, revision: project.draftMutationRevision, snapshot: snapshot, bytes: bytes)
            editorID = id; editor = next; review = nil; notice = nil; saveUnconfirmed = false
            bufferRevision += 1; thresholdRevision += 1
        } catch { notice = "需要现存 schema2 RPG 规则；缺失、旧版或非原字符串配置保留，不用空模板替换。" }
    }
    func close(editorID: UUID?) { guard editorID != nil, self.editorID == editorID else { return }; retire() }
    func retire() {
        editor = nil; editorID = nil; review = nil; capture = nil; notice = nil; saveUnconfirmed = false
        bufferRevision += 1; thresholdRevision += 1
    }
    func retireIfInvalid() { if editor != nil && !isCurrent { retire() } }
    func setSceneActive(_ active: Bool) { sceneActive = active; if !active { retire() } }
    func mutate(editorID: UUID?, changesThresholds: Bool = false, _ body: (inout NativeRpgGrowthAuthorDraft) -> Void) {
        guard accepts(editorID), var next = editor else { return }
        body(&next); guard next != editor else { return }
        editor = next; review = nil; notice = nil; saveUnconfirmed = false; bufferRevision += 1
        if changesThresholds { thresholdRevision += 1 }
    }
    var enabled: Binding<Bool> {
        let id = editorID
        return Binding(get: { self.accepts(id) && self.editor?.growth?["enabled"] == .bool(true) },
            set: { value in self.mutate(editorID: id) { $0.set("enabled", .bool(value)) } })
    }
    func number(_ key: String) -> Binding<String> {
        let id = editorID
        return Binding(get: { self.accepts(id) ? NativeAuthorNumericInput.display(self.editor?.growth?[key]) : "" },
            set: { value in self.mutate(editorID: id) { $0.set(key, NativeAuthorNumericInput.numberInput(value)) } })
    }
    func threshold(_ index: Int) -> Binding<String> {
        let id = editorID, revision = thresholdRevision
        return Binding(get: {
            guard self.accepts(id), self.thresholdRevision == revision,
                  let rows = self.editor?.growth?["xpThresholds"]?.array, rows.indices.contains(index) else { return "" }
            return NativeAuthorNumericInput.display(rows[index])
        }, set: { value in
            guard self.thresholdRevision == revision else { return }
            self.mutate(editorID: id) { $0.threshold(index, value: value) }
        })
    }
    func feat(_ key: String) -> Binding<Bool> {
        let id = editorID
        return Binding(get: { self.accepts(id) && (self.editor?.growth?["feats"]?.array?.contains(.string(key)) ?? false) },
            set: { value in self.mutate(editorID: id) { draft in
                guard var rows = draft.growth?["feats"]?.array else { return }
                rows.removeAll { $0 == .string(key) }; if value { rows.append(.string(key)) }; draft.set("feats", .array(rows))
            } })
    }
    func preview(editorID: UUID?) {
        guard accepts(editorID), let editorID, let editor else { return }
        do {
            review = .init(editorID: editorID, bufferRevision: bufferRevision, value: try editor.serialized())
            notice = nil; saveUnconfirmed = false
        } catch { review = nil; notice = "成长配置未完整满足原合同：检查启用角色、等级、技能点和严格递增阈值；未写回。" }
    }
    func apply(_ expected: Review) {
        guard accepts(expected.editorID), let capture, let editor, review?.id == expected.id,
              expected.bufferRevision == bufferRevision else { return }
        do {
            let next = try editor.applying(to: project.draft)
            guard let proposed = next.preserved["journeyRules"]?.text, let reviewed = expected.value.text,
                  proposed.utf8.elementsEqual(reviewed.utf8),
                  let bytes = ProjectEditPendingMaterials.exactData(next) else { return }
            if bytes == capture.bytes { retire(); notice = "配置未变，保留原草稿字节；没有新增保存或发布。"; return }
            // The original store confirms the complete draft before this staged editor can be discarded.
            // Queuing changed()/autosave cannot prove persistence, and does not authorize a server write.
            guard project.persistLocalChange(next, lease: capture.lease) else {
                saveUnconfirmed = true
                notice = "原本地保存未确认；完整成长编辑与确认预览仍保留，可重试本地保存。尚未保存服务器或发布。"
                return
            }
            retire(); notice = "已由原保存器保存完整本地草稿，尚未保存服务器或发布。"
        } catch { review = nil; saveUnconfirmed = false; notice = "原项目或配置已变化，没有覆盖。" }
    }
}
