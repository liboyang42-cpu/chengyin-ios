import SwiftUI

@MainActor final class ProjectInitialAttributesController: ObservableObject {
    struct Capture {
        let controller: UUID
        let generation: Int
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let bytes: Data
    }
    struct Presentation: Identifiable { let id = UUID(); let capture: Capture }
    struct Removal: Identifiable {
        let id = UUID()
        let presentationID: UUID
        let bufferRevision: Int
        let rowID: UUID
        let key: String
        let label: String
    }
    let model: ProjectEditModel
    let chapterID: String
    private let identity = UUID()
    private var generation = 0
    private var bufferRevision = 0
    @Published private(set) var presentation: Presentation?
    @Published private(set) var buffer: ProjectInitialAttributes?
    @Published private(set) var removal: Removal?
    init(model: ProjectEditModel, chapterID: String) { self.model = model; self.chapterID = chapterID }
    var available: Bool {
        model.fullEdit && model.draft.product == .city && !chapterID.isEmpty &&
        model.draft.chapters.first?.id.utf8.elementsEqual(chapterID.utf8) == true &&
        model.draft.chapters.filter { $0.id == chapterID }.count == 1
    }
    func capture() -> Capture? {
        guard available, let lease = model.captureStarterLease(), let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return nil }
        return .init(controller: identity, generation: generation, lease: lease, revision: model.draftMutationRevision, bytes: bytes)
    }
    private func current(_ capture: Capture) -> Bool {
        capture.controller == identity && capture.generation == generation && available &&
        model.isCurrentStarterLease(capture.lease) && model.draftMutationRevision == capture.revision &&
        ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes
    }
    func open(_ capture: Capture) {
        guard presentation == nil, current(capture) else { return }
        buffer = .init(raw: model.draft.preserved["journeyRules"])
        bufferRevision += 1; removal = nil; presentation = .init(capture: capture)
    }
    func isCurrent(_ original: Presentation) -> Bool { presentation?.id == original.id && current(original.capture) }
    private func mutate(_ original: Presentation, _ action: (inout ProjectInitialAttributes) -> Void) {
        guard isCurrent(original), var value = buffer, !value.readOnly else { return }
        action(&value); buffer = value; bufferRevision += 1; removal = nil
    }
    func setEnabled(_ enabled: Bool, in original: Presentation) { mutate(original) { $0.setStateEnabled(enabled) } }
    func add(in original: Presentation) { mutate(original) { _ = $0.add() } }
    func replace(_ row: ProjectInitialAttributes.Row, in original: Presentation) { mutate(original) { _ = $0.replace(row) } }
    func requestRemoval(_ rowID: UUID, in original: Presentation) {
        guard isCurrent(original), let buffer, !buffer.readOnly, let row = buffer.rows.first(where: { $0.id == rowID }) else { return }
        removal = .init(presentationID: original.id, bufferRevision: bufferRevision, rowID: rowID, key: row.key, label: row.label)
    }
    func isCurrent(_ intent: Removal, in original: Presentation) -> Bool {
        isCurrent(original) && removal?.id == intent.id && intent.presentationID == original.id &&
        intent.bufferRevision == bufferRevision && buffer?.rows.contains(where: { $0.id == intent.rowID }) == true
    }
    @discardableResult func confirmRemoval(_ intent: Removal, in original: Presentation) -> Bool {
        guard isCurrent(intent, in: original) else { return false }
        mutate(original) { _ = $0.remove(intent.rowID) }; return true
    }
    func cancelRemoval(_ intent: Removal) { guard removal?.id == intent.id else { return }; removal = nil }
    @discardableResult func apply(_ original: Presentation) -> Bool {
        guard isCurrent(original), removal == nil, let buffer else { return false }
        do {
            let result = try buffer.serialized(matching: model.draft.preserved["journeyRules"])
            var next = model.draft; next.preserved["journeyRules"] = result
            if ProjectEditPendingMaterials.exactData(next) != original.capture.bytes { model.draft = next }
            close(original); return true
        } catch { return false }
    }
    func close(_ original: Presentation) { guard presentation?.id == original.id else { return }; retire() }
    func retire() { presentation = nil; buffer = nil; removal = nil; generation += 1; bufferRevision += 1 }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

/// Mounted alongside the existing HP/LUCK entry only in the real first chapter.
@MainActor struct ProjectInitialAttributesEntry: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectInitialAttributesController
    init(model: ProjectEditModel, chapterID: String) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID))
    }
    var body: some View {
        let captured = controller.capture()
        let original = controller.presentation
        Button { if let captured { controller.open(captured) } } label: {
            Text("projectInitialAttributes.title", tableName: "ProjectInitialAttributes")
        }.disabled(captured == nil || original != nil).accessibilityIdentifier("projectInitialAttributes.open")
            .sheet(item: controller.binding(original)) { original in ProjectInitialAttributesSheet(controller: controller, original: original) }
            .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
            .onDisappear { controller.retire() }
    }
}

@MainActor private struct ProjectInitialAttributesSheet: View {
    @ObservedObject var controller: ProjectInitialAttributesController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectInitialAttributesController.Presentation
    @State private var invalid = false
    init(controller: ProjectInitialAttributesController, original: ProjectInitialAttributesController.Presentation) {
        self.controller = controller; self.original = original; model = controller.model
    }
    private func text(_ key: String) -> Text { Text(LocalizedStringKey("projectInitialAttributes." + key), tableName: "ProjectInitialAttributes") }
    var body: some View {
        let intent = controller.removal
        NavigationStack {
            Form {
                if !controller.isCurrent(original) { Text("projectStarter.stale") }
                else if let buffer = controller.buffer, !buffer.readOnly {
                    Section {
                        text("scope").font(.footnote)
                        Toggle(isOn: .init(get: { controller.buffer?.stateEnabled ?? false },
                            set: { controller.setEnabled($0, in: original); invalid = false })) { text("enabled") }
                            .accessibilityIdentifier("projectInitialAttributes.enabled")
                        text("enabledHint").font(.footnote)
                    }
                    ForEach(buffer.rows) { row in
                        Section {
                            if row.existingKey != nil {
                                LabeledContent { Text(verbatim: row.key).textSelection(.enabled) } label: { text("key") }
                                text("keyLocked").font(.caption)
                            } else {
                                TextField(text: field(row, \.key)) { text("key") }
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityIdentifier("projectInitialAttributes.key." + row.id.uuidString)
                            }
                            TextField(text: field(row, \.label)) { text("label") }
                                .accessibilityIdentifier("projectInitialAttributes.label." + row.id.uuidString)
                            TextField(text: field(row, \.initial)) { text("initial") }.keyboardType(.numbersAndPunctuation)
                            TextField(text: field(row, \.minimum)) { text("minimum") }.keyboardType(.numbersAndPunctuation)
                            TextField(text: field(row, \.maximum)) { text("maximum") }.keyboardType(.numbersAndPunctuation)
                            Toggle(isOn: visible(row)) { text("visible") }
                            text(row.isFlag ? "flagHint" : "integerHint").font(.caption)
                            Button(role: .destructive) { controller.requestRemoval(row.id, in: original) } label: { text("remove") }
                                .accessibilityIdentifier("projectInitialAttributes.remove." + row.id.uuidString)
                        }
                    }
                    Section {
                        Button { controller.add(in: original); invalid = false } label: { text("add") }
                            .disabled(buffer.rows.count >= 32).accessibilityIdentifier("projectInitialAttributes.add")
                        text("keysHint").font(.caption)
                        if invalid { text("invalid").foregroundStyle(.red).accessibilityIdentifier("projectInitialAttributes.invalid") }
                    }
                } else { text("unsupported") }
            }
            .navigationTitle(text("title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { invalid = !controller.apply(original) } label: { text("apply") }
                        .disabled(!controller.isCurrent(original) || controller.buffer?.readOnly != false || intent != nil)
                        .accessibilityIdentifier("projectInitialAttributes.apply")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onDisappear { controller.close(original) }
            .alert(Text("projectInitialAttributes.removeTitle", tableName: "ProjectInitialAttributes"), isPresented: removalBinding(intent), presenting: intent) { intent in
                Button(role: .destructive) { _ = controller.confirmRemoval(intent, in: original) } label: { text("remove") }
                Button("action.cancel", role: .cancel) { controller.cancelRemoval(intent) }
            } message: { intent in
                Text(verbatim: intent.label + " (" + intent.key + ")") + Text("\n") + text("removeHint")
            }
        }
    }
    private func removalBinding(_ intent: ProjectInitialAttributesController.Removal?) -> Binding<Bool> {
        .init(get: { intent.map { controller.isCurrent($0, in: original) } ?? false },
              set: { if !$0, let intent { controller.cancelRemoval(intent) } })
    }
    private func field(_ row: ProjectInitialAttributes.Row, _ keyPath: WritableKeyPath<ProjectInitialAttributes.Row, String>) -> Binding<String> {
        .init(get: { controller.buffer?.rows.first(where: { $0.id == row.id })?[keyPath: keyPath] ?? "" }, set: { value in
            guard var current = controller.buffer?.rows.first(where: { $0.id == row.id }) else { return }
            current[keyPath: keyPath] = value; controller.replace(current, in: original); invalid = false
        })
    }
    private func visible(_ row: ProjectInitialAttributes.Row) -> Binding<Bool> {
        .init(get: { controller.buffer?.rows.first(where: { $0.id == row.id })?.visible ?? false }, set: { value in
            guard var current = controller.buffer?.rows.first(where: { $0.id == row.id }) else { return }
            current.visible = value; controller.replace(current, in: original); invalid = false
        })
    }
}
