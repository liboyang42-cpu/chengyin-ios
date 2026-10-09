import SwiftUI
import Combine

private struct ProjectCategoryReaderKey: EnvironmentKey {
    static let defaultValue: (any DiscoveryReading)? = nil
}
extension EnvironmentValues {
    var projectCategoryReader: (any DiscoveryReading)? {
        get { self[ProjectCategoryReaderKey.self] }
        set { self[ProjectCategoryReaderKey.self] = newValue }
    }
}

@MainActor final class ProjectCategoryPickerController: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, empty, failed, unavailable }
    struct Presentation: Identifiable {
        let id = UUID()
        let generation: Int
        let incarnation: UUID
        let session: ProjectEditSession?
        let identity: ProjectEditDraftIdentity?
        let revision: Int
        let bytes: Data
        let readerIdentity: String?
        let readerConfigured: Bool?
        let originalIDs: [Int]
    }
    let model: ProjectEditModel
    let reader: (any DiscoveryReading)?
    private var generation = 0
    private var requestRevision = 0
    @Published private(set) var presentation: Presentation?
    @Published private(set) var state: State = .idle
    @Published private(set) var categories: [DiscoveryCategory] = []
    @Published private(set) var retainedIDs: [Int] = []
    @Published private(set) var selection = TemplateMetadataCategorySelection(raw: nil)
    init(model: ProjectEditModel, reader: (any DiscoveryReading)?) { self.model = model; self.reader = reader }
    func isCurrent(_ value: Presentation) -> Bool {
        presentation?.id == value.id && value.generation == generation && model.canEdit &&
        model.editorIncarnation == value.incarnation && model.coordinator.session == value.session &&
        model.coordinator.identity == value.identity && model.draftMutationRevision == value.revision &&
        ProjectEditPendingMaterials.exactData(model.draft) == value.bytes && reader?.discoveryPresentationIdentity == value.readerIdentity &&
        reader?.isConfigured == value.readerConfigured
    }
    func open() {
        guard presentation == nil, model.canEdit, let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return }
        selection = .init(raw: model.draft.categoryIDs.map(String.init).joined(separator: ",")); categories = []; retainedIDs = model.draft.categoryIDs; state = .idle
        presentation = .init(generation: generation, incarnation: model.editorIncarnation,
            session: model.coordinator.session, identity: model.coordinator.identity, revision: model.draftMutationRevision,
            bytes: bytes, readerIdentity: reader?.discoveryPresentationIdentity, readerConfigured: reader?.isConfigured, originalIDs: model.draft.categoryIDs)
    }
    func canSave(_ value: Presentation) -> Bool {
        isCurrent(value) && reader?.isConfigured == true && selection.isSupported && (state == .loaded || state == .empty)
    }
    func toggle(_ id: Int, in value: Presentation) {
        guard canSave(value), categories.contains(where: { $0.id == id }) || retainedIDs.contains(id) else { return }
        selection.toggle(id)
        if selection.selectedIDs.contains(id), !retainedIDs.contains(id) { retainedIDs.append(id) }
    }
    func save(_ value: Presentation) {
        guard canSave(value) else { return }
        if selection.hasChanges { model.draft.categoryIDs = selection.selectedIDs }
        close(value)
    }
    func load(_ value: Presentation) async {
        guard isCurrent(value) else { return }
        requestRevision += 1; let requestID = requestRevision
        state = .loading; categories = []
        guard let reader, reader.isConfigured else { state = .unavailable; return }
        let request = reader.projectMetadataCategoriesRequest()
        do {
            let rows = try await request.read()
            guard accepts(value, requestID: requestID) else { return }
            guard Set(rows.map(\.id)).count == rows.count,
                  rows.allSatisfy({ $0.id > 0 && ($0.type == nil || $0.type == 1) }) else { throw APIError.malformedResponse }
            categories = rows; state = rows.isEmpty ? .empty : .loaded
        } catch {
            guard accepts(value, requestID: requestID) else { return }
            if case APIError.unauthorized = error { request.onUnauthorized() }
            guard accepts(value, requestID: requestID) else { return }
            state = error as? APIError == .notConfigured ? .unavailable : .failed
        }
    }
    private func accepts(_ value: Presentation, requestID: Int) -> Bool {
        requestID == requestRevision && isCurrent(value) && !Task.isCancelled
    }
    func close(_ value: Presentation) {
        guard presentation?.id == value.id else { return }
        retire()
    }
    func retire() {
        generation += 1; requestRevision += 1; presentation = nil; categories = []; retainedIDs = []
        selection = .init(raw: nil); state = .idle
    }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectCategoryPickerEntry: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.projectCategoryReader) private var reader
    private struct Identity: Hashable { let model: ObjectIdentifier; let reader: ObjectIdentifier? }
    var body: some View {
        ProjectCategoryPickerHost(model: model, reader: reader)
            .id(Identity(model: ObjectIdentifier(model), reader: reader.map(ObjectIdentifier.init)))
    }
}

@MainActor private struct ProjectCategoryPickerHost: View {
    @ObservedObject var model: ProjectEditModel
    @StateObject private var controller: ProjectCategoryPickerController
    @State private var readerRevision = 0
    init(model: ProjectEditModel, reader: (any DiscoveryReading)?) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, reader: reader))
    }
    var body: some View {
        let _ = readerRevision
        let original = controller.presentation
        Button { controller.open() } label: {
            Text("projectCategoryPicker.choose", tableName: "ProjectCategoryPicker")
        }.disabled(!model.canEdit).accessibilityIdentifier("projectCategoryPicker.open")
            .sheet(item: controller.binding(original)) { value in ProjectCategoryPickerSheet(controller: controller, original: value) }
            .onReceive(controller.reader?.discoveryPresentationChanges ?? Empty<Void, Never>().eraseToAnyPublisher()) { _ in readerRevision += 1 }
            .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
            .onDisappear { controller.retire() }
    }
}

@MainActor private struct ProjectCategoryPickerSheet: View {
    @ObservedObject var controller: ProjectCategoryPickerController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectCategoryPickerController.Presentation
    @State private var readerRevision = 0
    init(controller: ProjectCategoryPickerController, original: ProjectCategoryPickerController.Presentation) {
        self.controller = controller; self.original = original; model = controller.model
    }
    var body: some View {
        let _ = readerRevision
        let current = controller.isCurrent(original), canSave = controller.canSave(original)
        NavigationStack {
            List {
                if current {
                    switch controller.state {
                    case .idle, .loading: ProgressView { Text("projectCategoryPicker.loading", tableName: "ProjectCategoryPicker") }
                    case .empty: Text("projectCategoryPicker.empty", tableName: "ProjectCategoryPicker")
                    case .failed:
                        Text("projectCategoryPicker.failed", tableName: "ProjectCategoryPicker")
                        Button("action.retry") { Task { await controller.load(original) } }
                    case .unavailable: Text("projectCategoryPicker.unavailable", tableName: "ProjectCategoryPicker")
                    case .loaded: EmptyView()
                    }
                    if !controller.selection.isSupported {
                        Text("projectCategoryPicker.unsupported", tableName: "ProjectCategoryPicker")
                        Text(verbatim: original.originalIDs.map(String.init).joined(separator: ","))
                    }
                    ForEach(controller.categories) { category in
                        Button { controller.toggle(category.id, in: original) } label: {
                            HStack {
                                Text(verbatim: category.name.isEmpty ? String(category.id) : category.name)
                                Spacer()
                                if controller.selection.selectedIDs.contains(category.id) { Image(systemName: "checkmark") }
                            }
                        }.disabled(!canSave).accessibilityIdentifier("projectCategoryPicker.option." + String(category.id))
                    }
                    let visible = Set(controller.categories.map(\.id))
                    let retained = controller.retainedIDs.filter { !visible.contains($0) }
                    if !retained.isEmpty {
                        Section {
                            Text("projectCategoryPicker.retained", tableName: "ProjectCategoryPicker")
                            ForEach(Array(retained.enumerated()), id: \.offset) { _, id in
                                Button { controller.toggle(id, in: original) } label: {
                                    HStack { Text(verbatim: String(id)); Spacer(); if controller.selection.selectedIDs.contains(id) { Image(systemName: "checkmark") } }
                                }.disabled(!canSave).accessibilityIdentifier("projectCategoryPicker.retained." + String(id))
                            }
                        }
                    }
                    Button { controller.save(original) } label: { Text("projectCategoryPicker.save", tableName: "ProjectCategoryPicker") }
                        .disabled(!canSave).accessibilityIdentifier("projectCategoryPicker.save")
                } else { Text("projectStarter.stale") }
            }
            .navigationTitle(Text("projectCategoryPicker.title", tableName: "ProjectCategoryPicker"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } } }
        }
        .task(id: original.id) { await controller.load(original) }
        .onReceive(controller.reader?.discoveryPresentationChanges ?? Empty<Void, Never>().eraseToAnyPublisher()) { _ in readerRevision += 1 }
    }
}
