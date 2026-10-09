import SwiftUI

@MainActor final class ProjectThoughtDefinitionsController: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID(), incarnation: UUID, session: ProjectEditSession?, identity: ProjectEditDraftIdentity?
        let revision: Int, bytes: Data
    }
    struct Removal: Identifiable {
        let id = UUID(), key: String, revision: Int, impacts: [String]
    }
    let model: ProjectEditModel
    @Published private(set) var presentation: Presentation?
    @Published private(set) var buffer: ProjectThoughtDefinitions?
    @Published private(set) var removal: Removal?
    @Published private(set) var invalid = false
    private(set) var bufferRevision = 0
    init(model: ProjectEditModel) { self.model = model }
    func open() {
        guard model.fullEdit, presentation == nil, let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return }
        buffer = .init(raw: model.draft.preserved["journeyRules"], draft: model.draft); bufferRevision += 1; invalid = false; removal = nil
        presentation = .init(incarnation: model.editorIncarnation, session: model.coordinator.session, identity: model.coordinator.identity,
                             revision: model.draftMutationRevision, bytes: bytes)
    }
    func isCurrent(_ original: Presentation) -> Bool {
        presentation?.id == original.id && model.fullEdit && original.incarnation == model.editorIncarnation &&
        original.session == model.coordinator.session && original.identity == model.coordinator.identity &&
        original.revision == model.draftMutationRevision && ProjectEditPendingMaterials.exactData(model.draft) == original.bytes
    }
    private func mutate(_ original: Presentation, _ action: (inout ProjectThoughtDefinitions) -> Void) {
        guard isCurrent(original), var value = buffer, !value.readOnly else { return }
        action(&value); buffer = value; bufferRevision += 1; removal = nil; invalid = false
    }
    func text(_ key: String, field: String, original: Presentation) -> Binding<String> {
        .init(get: {
            guard self.isCurrent(original), let row = self.buffer?.rows.first(where: { $0.key == key }) else { return "" }
            switch field { case "name": return row.name; case "summary": return row.summary; default: return row.need }
        }, set: { text in self.mutate(original) { value in
            guard let index = value.rows.firstIndex(where: { $0.key == key }) else { return }
            switch field { case "name": value.rows[index].name = text; case "summary": value.rows[index].summary = text; case "need": value.rows[index].need = text; default: break }
        } })
    }
    func tag(_ tag: String, key: String, done: Bool, original: Presentation) -> Binding<Bool> {
        .init(get: {
            guard self.isCurrent(original), let row = self.buffer?.rows.first(where: { $0.key == key }) else { return false }
            return (done ? row.doneTags : row.whenTags).contains(tag)
        }, set: { enabled in self.mutate(original) { value in
            guard value.tags.contains(where: { $0.tag == tag }), let index = value.rows.firstIndex(where: { $0.key == key }) else { return }
            if done { if enabled { value.rows[index].doneTags.insert(tag) } else { value.rows[index].doneTags.remove(tag) } }
            else { if enabled { value.rows[index].whenTags.insert(tag) } else { value.rows[index].whenTags.remove(tag) } }
        } })
    }
    func add(_ original: Presentation) { mutate(original) { _ = $0.add() } }
    func askRemoval(key: String, original: Presentation) {
        guard isCurrent(original), buffer?.readOnly == false, buffer?.rows.contains(where: { $0.key == key }) == true else { return }
        var impacts: [String] = []
        let tag = "thought." + key + ".done"
        for chapter in model.draft.chapters {
            for (index, block) in (chapter.blocks ?? []).enumerated() {
                if (block.kind == .thought && block.fieldText("thoughtKey").utf8.elementsEqual(key.utf8)) ||
                    (block.sourceFields?["when"]?.object?["op"] == .string("HAS_TAG") &&
                     block.sourceFields?["when"]?.object?["value"]?.text?.utf8.elementsEqual(tag.utf8) == true) {
                    impacts.append(chapter.name + " · " + String(index + 1) + " · " + block.kind.rawValue)
                }
            }
            if chapter.preserved["ending"]?.object?["when"]?.array?.contains(where: { $0.object?["op"] == .string("HAS_TAG") && $0.object?["value"]?.text?.utf8.elementsEqual(tag.utf8) == true }) == true {
                impacts.append(chapter.name + " · ending")
            }
        }
        removal = .init(key: key, revision: bufferRevision, impacts: impacts)
    }
    func confirmRemoval(_ value: Removal, original: Presentation) {
        guard removal?.id == value.id, bufferRevision == value.revision else { return }
        mutate(original) { $0.rows.removeAll { $0.key == value.key } }
    }
    func cancelRemoval(_ value: Removal) { if removal?.id == value.id { removal = nil } }
    func save(_ original: Presentation) {
        guard isCurrent(original), let buffer else { return }
        do {
            let raw = try buffer.serialized(matching: model.draft.preserved["journeyRules"])
            var next = model.draft; next.preserved["journeyRules"] = raw
            if ProjectEditPendingMaterials.exactData(next) != original.bytes { model.draft = next }
            close(original)
        } catch { invalid = true }
    }
    func close(_ original: Presentation) {
        guard presentation?.id == original.id else { return }; presentation = nil; buffer = nil; removal = nil; invalid = false; bufferRevision += 1
    }
    func retire() { if let presentation { close(presentation) } }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
    func removalBinding(_ value: Removal?, original: Presentation) -> Binding<Bool> {
        .init(get: { value.map { self.removal?.id == $0.id && self.bufferRevision == $0.revision && self.isCurrent(original) } ?? false },
              set: { if !$0, let value { self.cancelRemoval(value) } })
    }
}

@MainActor struct ProjectThoughtDefinitionsEntry: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectThoughtDefinitionsController
    init(model: ProjectEditModel) { self.model = model; _controller = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        let original = controller.presentation
        Button { controller.open() } label: { Text("projectThoughts.title", tableName: "ProjectThoughtDefinitions") }
            .disabled(!model.fullEdit).accessibilityIdentifier("projectThoughts.open")
            .sheet(item: controller.binding(original)) { original in ProjectThoughtDefinitionsSheet(controller: controller, original: original) }
            .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
            .onDisappear { controller.retire() }
    }
}

@MainActor private struct ProjectThoughtDefinitionsSheet: View {
    @ObservedObject var controller: ProjectThoughtDefinitionsController
    let original: ProjectThoughtDefinitionsController.Presentation
    var body: some View {
        let removal = controller.removal
        NavigationStack {
            Form {
                if !controller.isCurrent(original) { Text("projectStarter.stale") }
                else if let buffer = controller.buffer {
                    if buffer.readOnly { Text("projectThoughts.unsupported", tableName: "ProjectThoughtDefinitions") }
                    else {
                        Text("projectThoughts.scope", tableName: "ProjectThoughtDefinitions").font(.caption)
                        ForEach(buffer.rows) { row in
                            Section {
                                TextField(text: controller.text(row.key, field: "name", original: original)) { Text("projectThoughts.name", tableName: "ProjectThoughtDefinitions") }
                                TextField(text: controller.text(row.key, field: "summary", original: original)) { Text("projectThoughts.summary", tableName: "ProjectThoughtDefinitions") }
                                TextField(text: controller.text(row.key, field: "need", original: original)) { Text("projectThoughts.steps", tableName: "ProjectThoughtDefinitions") }.keyboardType(.numberPad)
                                if !row.whenNodeIDs.isEmpty {
                                    LabeledContent(content: { Text(verbatim: row.whenNodeIDs.map(String.init).joined(separator: ", ")) },
                                        label: { Text("projectThoughts.retainedWhenNodes", tableName: "ProjectThoughtDefinitions") })
                                }
                                if !row.doneNodeIDs.isEmpty {
                                    LabeledContent(content: { Text(verbatim: row.doneNodeIDs.map(String.init).joined(separator: ", ")) },
                                        label: { Text("projectThoughts.retainedDoneNodes", tableName: "ProjectThoughtDefinitions") })
                                }
                                if buffer.tags.isEmpty { Text("projectThoughts.noOptions", tableName: "ProjectThoughtDefinitions").font(.caption) }
                                ForEach(buffer.tags) { option in
                                    VStack(alignment: .leading) {
                                        Text(verbatim: option.label)
                                        if option.retained { Text("projectThoughts.retainedTag", tableName: "ProjectThoughtDefinitions").font(.caption) }
                                        Toggle(isOn: controller.tag(option.tag, key: row.key, done: false, original: original)) { Text("projectThoughts.when", tableName: "ProjectThoughtDefinitions") }
                                        Toggle(isOn: controller.tag(option.tag, key: row.key, done: true, original: original)) { Text("projectThoughts.done", tableName: "ProjectThoughtDefinitions") }
                                    }
                                }
                                Button(role: .destructive) { controller.askRemoval(key: row.key, original: original) } label: { Text("projectThoughts.remove", tableName: "ProjectThoughtDefinitions") }
                            }
                        }
                        Button { controller.add(original) } label: { Text("projectThoughts.add", tableName: "ProjectThoughtDefinitions") }.disabled(buffer.rows.count >= 8)
                        if !buffer.recoveryChanges.isEmpty {
                            Section {
                                Text("projectInitialState.recoveryNotice", tableName: "ProjectInitialState")
                                ForEach(buffer.recoveryChanges) { change in
                                    LabeledContent(content: { Text(verbatim: "\(change.before) → \(change.after)") },
                                        label: { Text(LocalizedStringKey("projectInitialState.recovery." + change.key), tableName: "ProjectInitialState") })
                                }
                            }
                        }
                        if controller.invalid { Text("projectThoughts.invalid", tableName: "ProjectThoughtDefinitions") }
                        Button { controller.save(original) } label: { Text("projectThoughts.save", tableName: "ProjectThoughtDefinitions") }
                            .accessibilityIdentifier("projectThoughts.save")
                    }
                }
            }
            .navigationTitle(Text("projectThoughts.title", tableName: "ProjectThoughtDefinitions"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } } }
            .scrollDismissesKeyboard(.interactively)
            .confirmationDialog(Text("projectThoughts.removeTitle", tableName: "ProjectThoughtDefinitions"),
                isPresented: controller.removalBinding(removal, original: original), titleVisibility: .visible) {
                    if let removal {
                        Button(role: .destructive) { controller.confirmRemoval(removal, original: original) } label: { Text("projectThoughts.remove", tableName: "ProjectThoughtDefinitions") }
                        Button("action.cancel", role: .cancel) { controller.cancelRemoval(removal) }
                    }
                } message: {
                    Text("projectThoughts.removeImpact", tableName: "ProjectThoughtDefinitions")
                    if let removal {
                        if removal.impacts.isEmpty { Text("projectThoughts.noKnownImpacts", tableName: "ProjectThoughtDefinitions") }
                        else { Text(verbatim: removal.impacts.joined(separator: "\n")) }
                    }
                }
        }
    }
}

@MainActor struct ProjectThoughtReferencePicker: View {
    @ObservedObject var model: ProjectEditModel
    @Binding var block: ProjectEditBlock
    let chapterID: String
    private var ownsTarget: Bool {
        let chapters = model.draft.chapters.filter { $0.id == chapterID }
        guard chapters.count == 1, let chapter = chapters.first, chapter.id.utf8.elementsEqual(chapterID.utf8) else { return false }
        let blocks = (chapter.blocks ?? []).filter { $0.id == block.id }
        return blocks.count == 1 && blocks.first?.id.utf8.elementsEqual(block.id.utf8) == true &&
            ProjectEditPendingMaterials.exactData(blocks[0]) == ProjectEditPendingMaterials.exactData(block)
    }
    var body: some View {
        let definitions = ProjectThoughtDefinitions(raw: model.draft.preserved["journeyRules"], draft: model.draft)
        let originalKey = block.fieldText("thoughtKey"), originalID = Data(block.id.utf8)
        let revision = model.draftMutationRevision, incarnation = model.editorIncarnation, bytes = ProjectEditPendingMaterials.exactData(model.draft)
        let session = model.coordinator.session, identity = model.coordinator.identity
        if ownsTarget, !definitions.readOnly, !definitions.rows.isEmpty {
            Picker(selection: Binding(get: { block.fieldText("thoughtKey") }, set: { key in
                guard model.fullEdit, ownsTarget, model.coordinator.session == session, model.coordinator.identity == identity,
                      model.editorIncarnation == incarnation, model.draftMutationRevision == revision,
                      bytes != nil, ProjectEditPendingMaterials.exactData(model.draft) == bytes, Data(block.id.utf8) == originalID,
                      definitions.rows.contains(where: { $0.key.utf8.elementsEqual(key.utf8) }),
                      !key.utf8.elementsEqual(originalKey.utf8) else { return }
                guard let next = try? definitions.assigningReference(key, chapterID: chapterID, blockID: block.id, in: model.draft) else { return }
                if ProjectEditPendingMaterials.exactData(next) != bytes { model.draft = next }
            })) {
                if !definitions.rows.contains(where: { $0.key.utf8.elementsEqual(originalKey.utf8) }) {
                    Text(verbatim: originalKey.isEmpty ? "—" : originalKey).tag(originalKey)
                }
                ForEach(definitions.rows) { row in Text(verbatim: row.name).tag(row.key) }
            } label: { Text("projectThoughts.reference", tableName: "ProjectThoughtDefinitions") }
        } else { Text("projectThoughts.noDefinitions", tableName: "ProjectThoughtDefinitions").font(.caption) }
    }
}
