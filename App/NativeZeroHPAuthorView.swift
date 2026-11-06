import SwiftUI

@MainActor struct NativeZeroHPAuthorEntry: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    private var copy: NativeZeroHPAuthorPresentation { .init(locale: locale) }
    @State private var showing = false
    var body: some View {
        Section(copy.text("zeroHP.copy.000")) {
            Button { if scenePhase == .active && model.fullEdit && model.confirmation == nil && model.draft.owner == .personal { showing = true } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.text("zeroHP.copy.001")).font(.headline)
                    Text(copy.text("zeroHP.copy.002")).nativeAuthorSupportingCopy()
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.disabled(scenePhase != .active || !model.fullEdit || model.confirmation != nil || model.draft.owner != .personal)
                .accessibilityIdentifier("zeroHPAuthor.open")
            Text(copy.text("zeroHP.copy.003")).font(.footnote)
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
    @Environment(\.locale) private var locale
    private var copy: NativeZeroHPAuthorPresentation { .init(locale: locale) }
    @StateObject private var editor: NativeZeroHPAuthorController
    init(model: ProjectEditModel) { self.model = model; _editor = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        let token = editor.editToken
        Form {
            Section {
                Text(copy.text("zeroHP.copy.012")).nativeAuthorSupportingCopy()
                if editor.busy { NativeAuthorLoading(text: Text(copy.text("zeroHP.copy.013"))).accessibilityIdentifier("zeroHPAuthor.loading") }
                if let message = editor.message { NativeAuthorNotice(text: Text(verbatim: copy.message(message)), tone: .attention).accessibilityIdentifier("zeroHPAuthor.notice") }
                if !editor.current {
                    Text(copy.text("zeroHP.copy.014"))
                    Button(copy.text("zeroHP.copy.015")) { guard editor.editToken == token else { return }; editor.open() }.disabled(!model.fullEdit).accessibilityIdentifier("zeroHPAuthor.reloadProject")
                } else if editor.staged?.readOnly != true {
                    Button(copy.text("zeroHP.copy.016")) { guard editor.editToken == token else { return }; editor.reload() }.disabled(editor.busy).accessibilityIdentifier("zeroHPAuthor.reloadInputs")
                }
            }
            if editor.current, let staged = editor.staged {
                Section(copy.healthName(staged) + copy.text("zeroHP.copy.017")) {
                    Text(staged.hp.enabled ? copy.format("zeroHP.enabled", staged.hp.maximum) : copy.text("zeroHP.copy.018"))
                    Text(copy.format("zeroHP.editResource", copy.message(staged.hpEditorName))).font(.caption)
                }
                if staged.readOnly {
                    Section(copy.text("zeroHP.copy.019")) {
                        Text(verbatim: copy.compatibility(staged)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("zeroHPAuthor.readOnly")
                        Text(copy.text("zeroHP.copy.020")).nativeAuthorSupportingCopy()
                        if staged.selected == .steps {
                            Text(copy.text("zeroHP.copy.021") + staged.text("restoreTo"))
                            Text(copy.text("zeroHP.copy.022") + staged.text("limit"))
                            Text(copy.text("zeroHP.copy.023") + (NativeZeroHPAuthorDraft.Policy(rawValue: staged.text("thenPolicy")).map { copy.message($0.title) } ?? staged.text("thenPolicy")))
                            NativeAuthorNotice(text: Text(copy.text("zeroHP.copy.024")), tone: .attention)
                        }
                    }
                } else if let inputs = editor.inputs, editor.inputsCurrent {
                    policySection(staged, inputs: inputs)
                    if staged.selected == .challenge { challengeSection(staged, inputs: inputs) }
                    if staged.selected?.blockKey != nil { recoverySection(staged) }
                    Section(copy.text("zeroHP.copy.025")) {
                        TextField(copy.text("zeroHP.copy.026"), text: Binding(get: { staged.zeroMessage }, set: { text in editor.mutate(token) { value, _ in value.message(text) } }), axis: .vertical)
                            .lineLimit(3...8)
                            .accessibilityIdentifier("zeroHPAuthor.reply")
                            .accessibilityLabel(Text(copy.text("zeroHP.copy.026")))
                        Text(copy.text("zeroHP.copy.027")).font(.caption)
                    }.disabled(editor.busy)
                    if !editor.issues.isEmpty { Section(copy.text("zeroHP.copy.028")) {
                        ForEach(Array(editor.issues.enumerated()), id: \.offset) { _, issue in NativeAuthorNotice(text: Text(verbatim: copy.message(issue)), tone: .attention) }
                    } }
                } else if !editor.busy { Section { NativeAuthorNotice(text: Text(copy.text("zeroHP.copy.029")), tone: .attention) } }
            }
        }
        .nativeAuthorSurface()
        .navigationTitle(copy.text("zeroHP.copy.030"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(copy.text("zeroHP.copy.031")) { guard editor.editToken == token else { return }; editor.retire(); dismiss() }.accessibilityIdentifier("zeroHPAuthor.cancel") }
            ToolbarItem(placement: .confirmationAction) { Button(copy.text("zeroHP.copy.032")) { Task { if await editor.finish(token) { dismiss() } } }.disabled(!editor.canFinish).accessibilityIdentifier("zeroHPAuthor.done").accessibilityHint(Text(copy.completionHint(readOnly: editor.staged?.readOnly == true))) }
        }
        .onAppear { editor.setSceneActive(scenePhase == .active); if editor.staged == nil { editor.open() } }
        .onDisappear { editor.setSceneActive(false) }
        .onChange(of: scenePhase) { _, value in editor.setSceneActive(value == .active) }
        .onChange(of: editor.current) { _, valid in if !valid { editor.retireIfInvalid() } }
    }
    private func policySection(_ staged: NativeZeroHPAuthorDraft, inputs: NativeRuntimeStructureAuthorInputs) -> some View {
        let token = editor.editToken
        return Section(copy.text("zeroHP.copy.033")) {
            ForEach(NativeZeroHPAuthorDraft.Policy.allCases) { policy in
                let reason = NativeZeroHPAuthorPolicy.reason(policy, draft: staged, inputs: inputs)
                Button { editor.mutate(token) { try $0.select(policy, inputs: $1) } } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(verbatim: copy.message(policy.title)).font(.headline)
                            Spacer(minLength: 8)
                            if staged.selected == policy { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
                        }
                        if let reason { NativeAuthorNotice(text: Text(verbatim: copy.message(reason)), tone: .attention) }
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
        return Section(copy.text("zeroHP.copy.034")) {
            Text(copy.text("zeroHP.copy.035")).font(.caption)
            if staged.savedNodes.isEmpty || !editor.hasSavedTopic { Text(copy.text("zeroHP.copy.036")) }
            ForEach(staged.savedNodes) { node in
                if let id = node.localMetadata["id"]?.integer {
                    let reason = NativeZeroHPAuthorPolicy.nodeReason(node, draft: staged, inputs: inputs)
                    Button { editor.mutate(token) { try $0.main(nodeID: id, inputs: $1) } } label: {
                        VStack(alignment: .leading) {
                            HStack { Text(node.name.isEmpty ? copy.format("zeroHP.node", String(id)) : node.name); if staged.challenge["challengeNodeId"]?.integer == id { Text(copy.text("zeroHP.copy.037")) } }
                            Text(copy.format("zeroHP.nodeTemplate", String(id), node.templateID.map(String.init) ?? copy.text("zeroHP.copy.040"))).font(.caption)
                            if let reason { NativeAuthorNotice(text: Text(verbatim: copy.message(reason)), tone: .attention) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.disabled(reason != nil || editor.busy || !editor.hasSavedTopic)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(staged.challenge["challengeNodeId"]?.integer == id ? .isSelected : [])
                    .accessibilityIdentifier("zeroHPAuthor.main.\(id)")
                }
            }
            Text(copy.text("zeroHP.copy.038") + ((staged.challenge["gameplayKey"]?.text).map { copy.gameplay($0) } ?? copy.text("zeroHP.copy.039"))).font(.caption)
            DisclosureGroup(copy.format("zeroHP.alternatives", String(staged.alternatives.count))) {
                ForEach(staged.savedNodes.filter { $0.localMetadata["id"]?.integer != staged.challenge["challengeNodeId"]?.integer }) { node in
                    if let id = node.localMetadata["id"]?.integer {
                        let reason = NativeZeroHPAuthorPolicy.nodeReason(node, draft: staged, inputs: inputs)
                        Toggle(node.name.isEmpty ? copy.format("zeroHP.node", String(id)) : node.name, isOn: Binding(get: { staged.alternatives.contains(id) }, set: { flag in editor.mutate(token) { try $0.alternative(nodeID: id, selected: flag, inputs: $1) } }))
                            .accessibilityIdentifier("zeroHPAuthor.alternative.\(id)")
                            .frame(minHeight: 44)
                            .disabled(editor.busy || !editor.hasSavedTopic || (!staged.alternatives.contains(id) && (reason != nil || staged.alternatives.count >= 3)))
                        if let reason { NativeAuthorNotice(text: Text(copy.message(reason) + (staged.alternatives.contains(id) ? copy.text("zeroHP.copy.041") : "")), tone: .attention) }
                        else if NativeZeroHPAuthorPolicy.answerable(node, draft: staged, inputs: inputs) { Text(copy.text("zeroHP.copy.042")).font(.caption) }
                    }
                }
                ForEach(staged.alternatives.filter { id in !staged.savedNodes.contains { $0.localMetadata["id"]?.integer == id } || id == staged.challenge["challengeNodeId"]?.integer }, id: \.self) { stale in
                    Button(copy.format("zeroHP.removeStale", String(stale))) { editor.mutate(token) { try $0.alternative(nodeID: stale, selected: false, inputs: $1) } }.disabled(editor.busy)
                        .frame(minHeight: 44).accessibilityIdentifier("zeroHPAuthor.removeAlternative.\(stale)")
                }
            }
            number(staged, field: "requiredCompletions", label: copy.text("zeroHP.copy.043"))
            number(staged, field: "withinSeconds", label: copy.text("zeroHP.copy.044"))
        }
    }
    private func number(_ staged: NativeZeroHPAuthorDraft, field: String, label: String) -> some View {
        let token = editor.editToken
        return TextField(label, text: Binding(get: { staged.text(field) }, set: { text in editor.mutate(token) { value, _ in value.number(field, text: text) } }))
            .keyboardType(.numberPad).disabled(editor.busy)
            .frame(minHeight: 44).accessibilityLabel(Text(verbatim: label))
            .accessibilityIdentifier("zeroHPAuthor.number.\(field)")
    }
    private func recoverySection(_ staged: NativeZeroHPAuthorDraft) -> some View {
        let token = editor.editToken
        return Section(copy.text("zeroHP.copy.045")) {
            if staged.selected == .wait { number(staged, field: "minutes", label: copy.text("zeroHP.copy.046")) }
            if staged.selected == .steps {
                number(staged, field: "steps", label: copy.text("zeroHP.copy.047")).disabled(true)
                Text(copy.text("zeroHP.copy.048")).font(.caption)
            }
            number(staged, field: "restoreTo", label: copy.format("zeroHP.restoreRange", staged.hp.maximum))
            number(staged, field: "limit", label: copy.text("zeroHP.copy.049"))
            Picker(copy.text("zeroHP.copy.050"), selection: Binding(get: { staged.text("thenPolicy") }, set: { key in if let policy = NativeZeroHPAuthorDraft.Policy(rawValue: key) { editor.mutate(token) { value, _ in try value.then(policy) } } })) {
                Text(copy.text("zeroHP.copy.051")).tag("")
                Text(copy.text("zeroHP.copy.052")).tag(NativeZeroHPAuthorDraft.Policy.fail.rawValue)
                Text(copy.text("zeroHP.copy.053")).tag(NativeZeroHPAuthorDraft.Policy.block.rawValue)
            }.disabled(editor.busy).accessibilityIdentifier("zeroHPAuthor.thenPolicy")
        }
    }
}
