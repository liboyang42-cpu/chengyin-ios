import SwiftUI

/// Lives inside the existing full editor; its normal draft save retains unknown-result recovery.
@MainActor struct CollectSetAuthorEntry: View {
    @ObservedObject var model: ProjectEditModel
    var body: some View {
        if model.fullEdit {
            NavigationLink("配置收集套组") { CollectSetAuthorView(model: model) }
                .accessibilityIdentifier("collectSet.author.open")
        }
    }
}

@MainActor private struct CollectSetAuthorView: View {
    @ObservedObject var model: ProjectEditModel
    @State private var values: [CollectSetAuthorDefinition] = []
    @State private var error: String?
    @State private var editToken = UUID()
    @State private var appeared = false
    private struct Capture {
        let incarnation: UUID; let revision: Int; let session: ProjectEditSession
        let snapshot: ProjectEditSnapshot; let draft: ProjectEditDraft; let bytes: Data
    }
    @State private var capture: Capture?
    private var isCurrent: Bool {
        guard phase == .active, let capture, model.fullEdit, model.confirmation == nil else { return false }
        return capture.incarnation == model.editorIncarnation && capture.revision == model.draftMutationRevision
            && capture.session == model.coordinator.session && capture.snapshot == model.coordinator.snapshot
            && model.coordinator.session?.storageNamespace.utf8.elementsEqual(capture.session.storageNamespace.utf8) == true
            && ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    private var canRead: Bool {
        phase == .active && model.fullEdit && model.confirmation == nil &&
            model.coordinator.session != nil && model.coordinator.snapshot != nil &&
            ProjectEditPendingMaterials.exactData(model.draft) != nil
    }
    private var nodes: [(Int, String)] {
        guard isCurrent, let capture else { return [] }
        return capture.draft.chapters.flatMap(\.nodes).compactMap { node in
            guard let id = node.localMetadata["id"]?.integer, id > 0 else { return nil }
            return (id, node.name)
        }
    }
    var body: some View {
        let token = editToken
        Form {
            Text("每组集齐所选点位即可完成；历史收藏不计入本次游玩。")
            if let error { NativeAuthorNotice(text: Text(verbatim: error), tone: .failure) }
            if isCurrent {
                if nodes.isEmpty {
                    NativeAuthorNotice(text: Text("请先在原编辑器保存并回读点位，再配置套组。"))
                        .accessibilityIdentifier("collectSet.author.noNodes")
                } else if values.isEmpty {
                    NativeAuthorNotice(text: Text("当前草稿尚未配置套组，可从新增套组开始。"))
                }
                ForEach(values) { set in
                    Section {
                        TextField("套组名称", text: title(set.key))
                        ForEach(nodes, id: \.0) { id, name in
                            Toggle(name, isOn: Binding(get: { set.nodeIds.contains(id) }, set: { selected in
                                mutate(set.key, token: token) { value in
                                    if selected && !value.nodeIds.contains(id) { value.nodeIds.append(id) }
                                    if !selected { value.nodeIds.removeAll { $0 == id } }
                                }
                            }))
                        }
                        Button("移除此套组", role: .destructive) { guard isCurrent, editToken == token else { return }; values.removeAll { $0.key == set.key }; editToken = UUID() }
                    }
                }
                Button("新增套组") { guard isCurrent, editToken == token else { return }; values.append(.init(key: UUID().uuidString, title: "", nodeIds: [])); editToken = UUID() }
                    .disabled(nodes.isEmpty || values.count >= 64 || !isCurrent)
                if values.count >= 64 { Text("最多可配置64组。").font(.footnote).foregroundStyle(.secondary) }
                Button("保存到原草稿") { save(token) }.nativeAuthorPrimaryAction().disabled(!isCurrent || !model.fullEdit)
                Text("此处只保存到原草稿；云端保存和发布结果请返回原编辑器查看。离页或切换后台会丢弃本页尚未写入原草稿的套组修改。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Section {
                    Text("请重新读取当前草稿后继续配置；本页尚未写入原草稿的修改不会恢复。")
                    if !canRead {
                        Text("当前草稿暂不可编辑。请返回原编辑器处理登录、权限或原保存结果后重试。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("重新读取当前草稿") { read(token) }
                        .disabled(!canRead)
                        .accessibilityIdentifier("collectSet.author.reread")
                    Button("返回原编辑器") { dismiss() }
                        .accessibilityIdentifier("collectSet.author.return")
                }.accessibilityIdentifier("collectSet.author.recovery")
            }
        }
        .nativeAuthorSurface()
        .navigationTitle("收集套组")
        .onAppear {
            guard !appeared else { return }; appeared = true; read(editToken)
        }
        .onChange(of: isCurrent) { _, current in if !current { retire() } }
        .onChange(of: phase) { _, phase in if phase != .active { retire() } }
        .onDisappear { retire() }
    }
    private func read(_ token: UUID) {
        guard editToken == token, capture == nil else { return }
        retire()
        guard canRead, let bytes = ProjectEditPendingMaterials.exactData(model.draft), let session = model.coordinator.session,
              let snapshot = model.coordinator.snapshot else { return }
        do {
            let next = try CollectSetAuthoring.definitions(in: model.draft)
            capture = .init(incarnation: model.editorIncarnation, revision: model.draftMutationRevision,
                            session: session, snapshot: snapshot, draft: model.draft, bytes: bytes)
            values = next
        } catch { self.error = "原套组配置无法读取，请返回检查草稿" }
    }
    private func retire() { editToken = UUID(); capture = nil; values = []; error = nil }
    private func title(_ key: String) -> Binding<String> {
        let token = editToken
        return Binding(get: { values.first(where: { $0.key == key })?.title ?? "" },
            set: { value in mutate(key, token: token) { $0.title = value } })
    }
    private func mutate(_ key: String, token: UUID, _ action: (inout CollectSetAuthorDefinition) -> Void) {
        guard isCurrent, editToken == token, let index = values.firstIndex(where: { $0.key == key }) else { return }
        action(&values[index]); editToken = UUID(); error = nil
    }
    private func save(_ token: UUID) {
        guard isCurrent, editToken == token, let original = capture else { return }
        do {
            model.draft = try CollectSetAuthoring.applying(values, to: model.draft)
            model.changed()
            guard model.editorIncarnation == original.incarnation, model.coordinator.session == original.session,
                  model.coordinator.snapshot == original.snapshot, let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return }
            editToken = UUID()
            capture = .init(incarnation: original.incarnation, revision: model.draftMutationRevision,
                            session: original.session, snapshot: original.snapshot, draft: model.draft, bytes: bytes)
            guard model.saveLocalForExit() else { error = "草稿暂未保存，请重试"; return }
            dismiss()
        }
        catch { self.error = "请填写名称，并为每组选择有效且不重复的点位" }
    }
}
