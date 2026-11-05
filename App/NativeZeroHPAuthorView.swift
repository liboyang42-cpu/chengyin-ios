import SwiftUI

@MainActor struct NativeZeroHPAuthorEntry: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showing = false
    var body: some View {
        Section("生命值域 · 归零后") {
            Button { if scenePhase == .active && model.fullEdit && model.confirmation == nil && model.draft.owner == .personal { showing = true } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("编辑生命归零策略").font(.headline)
                    Text("挑战／等待、恢复值与次数上限、耗尽后策略及归零回复").nativeAuthorSupportingCopy()
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.disabled(scenePhase != .active || !model.fullEdit || model.confirmation != nil || model.draft.owner != .personal)
                .accessibilityIdentifier("zeroHPAuthor.open")
            Text("生命开关与上限沿用原值域配置；这里不执行挑战、不恢复生命或发奖。").font(.footnote)
        }
        // Keep the original ProjectEdit visit mounted; route departure retires leases.
        .sheet(isPresented: $showing) { NavigationStack { NativeZeroHPAuthorView(model: model) } }
    }
}

@MainActor final class NativeZeroHPAuthorController: ObservableObject {
    let model: ProjectEditModel
    @Published private(set) var staged: NativeZeroHPAuthorDraft?
    @Published private(set) var inputs: NativeRuntimeStructureAuthorInputs?
    @Published private(set) var busy = false
    @Published var message: String?
    private struct Capture {
        let incarnation: UUID, revision: Int, session: ProjectEditSession, snapshot: ProjectEditSnapshot, bytes: Data
        let lease: ProjectEditStarterController.Lease
    }
    private var capture: Capture?
    private var generation = UUID()
    private var buffer = UUID()
    struct EditToken: Equatable { let generation: UUID; let buffer: UUID }
    var editToken: EditToken { .init(generation: generation, buffer: buffer) }
    private var task: Task<Void, Never>?
    private var sceneActive = false
    private let readInputs: (ProjectEditDraft) async throws -> NativeRuntimeStructureAuthorInputs
    private let inputsAreCurrent: (NativeRuntimeStructureAuthorInputs) -> Bool
    init(model: ProjectEditModel,
         readInputs: ((ProjectEditDraft) async throws -> NativeRuntimeStructureAuthorInputs)? = nil,
         inputsAreCurrent: ((NativeRuntimeStructureAuthorInputs) -> Bool)? = nil) {
        self.model = model
        self.readInputs = readInputs ?? { try await model.coordinator.runtimeStructureInputs(draft: $0) }
        self.inputsAreCurrent = inputsAreCurrent ?? { model.coordinator.runtimeStructureInputsAreCurrent($0) }
    }
    var current: Bool {
        guard sceneActive, let capture, model.fullEdit, model.confirmation == nil, model.draft.owner == .personal else { return false }
        return model.editorIncarnation == capture.incarnation && model.draftMutationRevision == capture.revision
            && model.coordinator.session == capture.session && model.coordinator.snapshot == capture.snapshot
            && model.coordinator.session?.storageNamespace.utf8.elementsEqual(capture.session.storageNamespace.utf8) == true
            && ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes
            && model.isCurrentStarterLease(capture.lease)
    }
    var inputsCurrent: Bool { current && inputs.map(inputsAreCurrent) == true }
    var hasSavedTopic: Bool { current && (capture?.snapshot.topicID ?? 0) > 0 }
    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if !active { retire() }
    }
    func retireIfInvalid() {
        guard capture != nil, !current else { return }; retire()
    }
    func open() {
        retire()
        guard sceneActive, model.fullEdit, model.confirmation == nil, model.draft.owner == .personal, let session = model.coordinator.session,
              let snapshot = model.coordinator.snapshot, let lease = model.captureStarterLease(),
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else {
            message = "当前项目不可完整编辑，请返回原项目读取权限与版本。"; return
        }
        do {
            staged = try .init(draft: model.draft)
            capture = .init(incarnation: model.editorIncarnation, revision: model.draftMutationRevision, session: session, snapshot: snapshot, bytes: bytes, lease: lease)
            if staged?.readOnly != true { reload() }
        } catch { message = "原归零配置无法安全编辑；已保留原文，未替换为默认配置。" }
    }
    func reload() {
        guard current, !busy, staged?.readOnly != true else { return }
        task?.cancel(); generation = UUID(); let stamp = generation
        inputs = nil; busy = true; message = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await readInputs(model.draft)
                guard !Task.isCancelled, generation == stamp, current else { return }
                inputs = value; busy = false
            } catch {
                guard !Task.isCancelled, generation == stamp, current else { return }
                inputs = nil; busy = false
                message = "支持矩阵或已绑定玩法详情未读取。只读适配未配置、权限变化或网络失败时不能假定支持；可重试，副本尚未写回。"
            }
        }
    }
    func mutate(_ expected: EditToken, _ action: (inout NativeZeroHPAuthorDraft, NativeRuntimeStructureAuthorInputs) throws -> Void) {
        guard editToken == expected, inputsCurrent, !busy, var next = staged, !next.readOnly, let inputs else { return }
        do { try action(&next, inputs); staged = next; buffer = UUID(); message = nil }
        catch { message = "当前选择不符合原配置约束；副本未改变。请查看该字段的原因。" }
    }
    var issues: [String] {
        guard let staged, let inputs else { return [] }
        return staged.issues(inputs: inputs) + (!staged.readOnly && staged.selected == .challenge && !hasSavedTopic ? ["请先保存本主题服务器草稿并回读，再选择真实挑战节点"] : [])
    }
    var canFinish: Bool { current && !busy && (staged?.readOnly == true || (inputsCurrent && staged != nil && issues.isEmpty)) }
    func finish(_ expected: EditToken) async -> Bool {
        guard editToken == expected, canFinish, let staged, let capture else { return false }
        // Compatibility Done only closes the local panel, preserving exact old bytes.
        if staged.readOnly { retire(); return true }
        guard let inputs else { return false }
        let stamp = generation; busy = true
        defer { if stamp == generation { busy = false } }
        do {
            let fresh = try await readInputs(model.draft)
            guard !Task.isCancelled, stamp == generation, editToken == expected, current else { return false }
            busy = false; self.inputs = fresh
            guard fresh == inputs else {
                buffer = UUID()
                message = "支持矩阵或已绑定玩法版本已变化，已读取新版本；请核对提示后再完成。"; return false
            }
            let proposed = try staged.applying(to: model.draft, inputs: fresh)
            guard current, inputsAreCurrent(fresh) else { throw ProjectEditError.changedSession }
            if ProjectEditPendingMaterials.exactData(proposed) != ProjectEditPendingMaterials.exactData(model.draft) {
                // The original full-draft saver is the only persistence owner. Do not
                // discard this confirmation on a queued autosave or failed local write.
                guard model.persistLocalChange(proposed, lease: capture.lease) else {
                    message = "原本地保存未确认；已保留归零策略与挑战副本，请重试本地保存。尚未保存服务器或发布。"
                    return false
                }
            }
            retire(); return true
        } catch {
            guard stamp == generation, current else { return false }
            busy = false; self.inputs = nil
            message = "权限、玩法版本或引用未能确认，未覆盖原草稿。请重试读取；服务器保存尚未发起。"; return false
        }
    }
    func retire() {
        task?.cancel(); task = nil; generation = UUID(); capture = nil; staged = nil; inputs = nil; busy = false; message = nil
    }
}

@MainActor struct NativeZeroHPAuthorView: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var editor: NativeZeroHPAuthorController
    init(model: ProjectEditModel) { self.model = model; _editor = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        let token = editor.editToken
        Form {
            Section {
                Text("先编辑副本，完成后沿原保存器持久保存整份本地草稿；本地保存失败会保留副本。退出或返回放弃未确认副本，之后仍须在原项目保存服务器草稿／发布。").nativeAuthorSupportingCopy()
                if editor.busy { NativeAuthorLoading(text: Text("正在读取支持矩阵与已绑定玩法")).accessibilityIdentifier("zeroHPAuthor.loading") }
                if let message = editor.message { NativeAuthorNotice(text: Text(message), tone: .attention).accessibilityIdentifier("zeroHPAuthor.notice") }
                if !editor.current {
                    Text("项目、账号、权限、版本或编辑实例已变化，旧副本不能写回。")
                    Button("重新读取本项目") { guard editor.editToken == token else { return }; editor.open() }.disabled(!model.fullEdit)
                } else if editor.staged?.readOnly != true {
                    Button("重试支持矩阵与玩法详情") { guard editor.editToken == token else { return }; editor.reload() }.disabled(editor.busy)
                }
            }
            if editor.current, let staged = editor.staged {
                Section(staged.hpName + "值域") {
                    Text(staged.hp.enabled ? "已开启 · 上限 \(staged.hp.maximum)" : "未开启；仅禁止扣该值的任务不会启用生命")
                    Text("如需修改开关、开局值或上限，请退出本面板，到" + staged.hpEditorName + "编辑。完成后不会自动改动初始生命。").font(.caption)
                }
                if staged.readOnly {
                    Section("兼容配置 · 只读") {
                        Text(staged.compatibilitySummary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("zeroHPAuthor.readOnly")
                        Text("旧版 BLOCK_PAID／LEGACY_END／旧挑战、原生端未支持的步数恢复及未知版本原样保留；退出与完成都不改写原配置。").nativeAuthorSupportingCopy()
                        if staged.selected == .steps {
                            Text("恢复到：" + staged.text("restoreTo"))
                            Text("最多恢复次数：" + staged.text("limit"))
                            Text("次数用完后：" + (NativeZeroHPAuthorDraft.Policy(rawValue: staged.text("thenPolicy"))?.title ?? staged.text("thenPolicy")))
                            NativeAuthorNotice(text: Text("微信运动证明未在原生端开放；本机步数不是等价证明，不能启用或修改此恢复项。"), tone: .attention)
                        }
                    }
                } else if let inputs = editor.inputs, editor.inputsCurrent {
                    policySection(staged, inputs: inputs)
                    if staged.selected == .challenge { challengeSection(staged, inputs: inputs) }
                    if staged.selected?.blockKey != nil { recoverySection(staged) }
                    Section("归零时回复") {
                        TextField("回复内容（最多 2000 字）", text: Binding(get: { staged.zeroMessage }, set: { text in editor.mutate(token) { value, _ in value.message(text) } }), axis: .vertical)
                            .lineLimit(3...8)
                            .accessibilityIdentifier("zeroHPAuthor.reply")
                        Text("可留空；不会覆盖普通节点的通过／没通过回复。").font(.caption)
                    }.disabled(editor.busy)
                    if !editor.issues.isEmpty { Section("请修正后完成") {
                        ForEach(Array(editor.issues.enumerated()), id: \.offset) { _, issue in NativeAuthorNotice(text: Text(issue), tone: .attention) }
                    } }
                } else if !editor.busy { Section { NativeAuthorNotice(text: Text("未取得当前支持矩阵，不能替换为默认配置。原草稿及未完成请求保持不变。"), tone: .attention) } }
            }
        }
        .nativeAuthorSurface()
        .navigationTitle("生命归零后")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("退出") { guard editor.editToken == token else { return }; editor.retire(); dismiss() }.accessibilityIdentifier("zeroHPAuthor.cancel") }
            ToolbarItem(placement: .confirmationAction) { Button("完成") { Task { if await editor.finish(token) { dismiss() } } }.disabled(!editor.canFinish).accessibilityIdentifier("zeroHPAuthor.done") }
        }
        .onAppear { editor.setSceneActive(scenePhase == .active); if editor.staged == nil { editor.open() } }
        .onDisappear { editor.setSceneActive(false) }
        .onChange(of: scenePhase) { _, value in editor.setSceneActive(value == .active) }
        .onChange(of: editor.current) { _, valid in if !valid { editor.retireIfInvalid() } }
    }
    private func policySection(_ staged: NativeZeroHPAuthorDraft, inputs: NativeRuntimeStructureAuthorInputs) -> some View {
        let token = editor.editToken
        return Section("归零后") {
            ForEach(NativeZeroHPAuthorDraft.Policy.allCases) { policy in
                let reason = NativeZeroHPAuthorPolicy.reason(policy, draft: staged, inputs: inputs)
                Button { editor.mutate(token) { try $0.select(policy, inputs: $1) } } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(policy.title).font(.headline)
                            Spacer(minLength: 8)
                            if staged.selected == policy { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
                        }
                        if let reason { NativeAuthorNotice(text: Text(reason), tone: .attention) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, 4).contentShape(Rectangle())
                }
                .accessibilityAddTraits(staged.selected == policy ? .isSelected : [])
                .accessibilityIdentifier("zeroHPAuthor.policy.\(policy.rawValue)")
                .disabled(reason != nil || editor.busy)
            }
        }
    }
    private func challengeSection(_ staged: NativeZeroHPAuthorDraft, inputs: NativeRuntimeStructureAuthorInputs) -> some View {
        let token = editor.editToken
        return Section("真实恢复挑战节点") {
            Text("从本主题已保存节点的已绑定玩法选择，不创建临时模板。挑战不扣费、不发普通奖励、不推进章节；完成后沿原章节同步排除主／备挑战节点。").font(.caption)
            if staged.savedNodes.isEmpty || !editor.hasSavedTopic { Text("请先保存主题和挑战节点，并回读服务器草稿，再返回选择。") }
            ForEach(staged.savedNodes) { node in
                if let id = node.localMetadata["id"]?.integer {
                    let reason = NativeZeroHPAuthorPolicy.nodeReason(node, draft: staged, inputs: inputs)
                    Button { editor.mutate(token) { try $0.main(nodeID: id, inputs: $1) } } label: {
                        VStack(alignment: .leading) {
                            HStack { Text(node.name.isEmpty ? "节点 \(id)" : node.name); if staged.challenge["challengeNodeId"]?.integer == id { Text("主挑战") } }
                            Text("已保存节点 \(id) · 绑定模板 \(node.templateID.map(String.init) ?? "未绑定")").font(.caption)
                            if let reason { NativeAuthorNotice(text: Text(reason), tone: .attention) }
                        }
                    }.disabled(reason != nil || editor.busy || !editor.hasSavedTopic)
                }
            }
            Text("恢复玩法：" + (staged.challenge["gameplayKey"]?.text ?? "未选择")).font(.caption)
            DisclosureGroup("备选节点（\(staged.alternatives.count)/3）") {
                ForEach(staged.savedNodes.filter { $0.localMetadata["id"]?.integer != staged.challenge["challengeNodeId"]?.integer }) { node in
                    if let id = node.localMetadata["id"]?.integer {
                        let reason = NativeZeroHPAuthorPolicy.nodeReason(node, draft: staged, inputs: inputs)
                        Toggle(node.name.isEmpty ? "节点 \(id)" : node.name, isOn: Binding(get: { staged.alternatives.contains(id) }, set: { flag in editor.mutate(token) { try $0.alternative(nodeID: id, selected: flag, inputs: $1) } }))
                            .disabled(editor.busy || !editor.hasSavedTopic || (!staged.alternatives.contains(id) && (reason != nil || staged.alternatives.count >= 3)))
                        if let reason { NativeAuthorNotice(text: Text(reason + (staged.alternatives.contains(id) ? " · 可以移除" : "")), tone: .attention) }
                        else if NativeZeroHPAuthorPolicy.answerable(node, draft: staged, inputs: inputs) { Text("可作答的题目类备选").font(.caption) }
                    }
                }
                ForEach(staged.alternatives.filter { id in !staged.savedNodes.contains { $0.localMetadata["id"]?.integer == id } || id == staged.challenge["challengeNodeId"]?.integer }, id: \.self) { stale in
                    Button("移除失效备选节点 \(stale)") { editor.mutate(token) { try $0.alternative(nodeID: stale, selected: false, inputs: $1) } }.disabled(editor.busy)
                }
            }
            number(staged, field: "requiredCompletions", label: "需完成次数（1–99）")
            number(staged, field: "withinSeconds", label: "限时秒数（1–86400）")
        }
    }
    private func number(_ staged: NativeZeroHPAuthorDraft, field: String, label: String) -> some View {
        let token = editor.editToken
        return TextField(label, text: Binding(get: { staged.text(field) }, set: { text in editor.mutate(token) { value, _ in value.number(field, text: text) } }))
            .keyboardType(.numberPad).disabled(editor.busy)
    }
    private func recoverySection(_ staged: NativeZeroHPAuthorDraft) -> some View {
        let token = editor.editToken
        return Section("恢复条件与耗尽后") {
            if staged.selected == .wait { number(staged, field: "minutes", label: "等待分钟（1–10080）") }
            if staged.selected == .steps {
                number(staged, field: "steps", label: "恢复步数（1–100000）").disabled(true)
                Text("原规则以归零后第一次同步的微信运动步数为起点。原生端不以本地传感器替代；此选项不可启用。").font(.caption)
            }
            number(staged, field: "restoreTo", label: "恢复到（1–\(staged.hp.maximum)）")
            number(staged, field: "limit", label: "最多恢复次数（1–99）")
            Picker("次数用完后", selection: Binding(get: { staged.text("thenPolicy") }, set: { key in if let policy = NativeZeroHPAuthorDraft.Policy(rawValue: key) { editor.mutate(token) { value, _ in try value.then(policy) } } })) {
                Text("请选择").tag("")
                Text("主题失败").tag(NativeZeroHPAuthorDraft.Policy.fail.rawValue)
                Text("仅禁止扣该值的任务").tag(NativeZeroHPAuthorDraft.Policy.block.rawValue)
            }.disabled(editor.busy)
        }
    }
}
