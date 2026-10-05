import SwiftUI
import Combine

/// Presentation-only metadata. None of these labels enter the authoring payload.
enum TemplateMetadataField: String, CaseIterable, Identifiable {
    case players, duration, categories
    var id: String { rawValue }
    var titleKey: String { "templateAuthor.field." + (self == .categories ? "activityCategoryids" : rawValue) }
    var dictionaryKind: TemplateMetadataKind? {
        switch self { case .players: return .players; case .duration: return .duration; case .categories: return nil }
    }
    func rawValue(in draft: TemplateAuthoringDraft) -> String? {
        switch self { case .players: return draft.players; case .duration: return draft.duration.map(String.init); case .categories: return draft.activityCategoryids }
    }
}

@MainActor final class TemplateAuthoringMetadataEditor: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, empty, failed, unavailable }
    let field: TemplateMetadataField
    private let model: TemplateAuthoringModel
    private let reader: (any DiscoveryReading)?
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private let modelGeneration: UUID
    private let readerIdentity: String?
    private let originalDraft: TemplateAuthoringDraft
    private var generation = 0
    private var active = true
    @Published private(set) var state: State = .idle
    @Published private(set) var options: [TemplateMetadataOption] = []
    @Published private(set) var categories: [DiscoveryCategory] = []
    @Published private(set) var selection: TemplateMetadataCategorySelection

    init(model: TemplateAuthoringModel, reader: (any DiscoveryReading)?, field: TemplateMetadataField) {
        self.model = model; self.reader = reader; self.field = field
        session = model.coordinator.session; identity = model.coordinator.identity
        modelGeneration = model.metadataGeneration; readerIdentity = reader?.discoveryPresentationIdentity
        originalDraft = model.draft; selection = .init(raw: model.draft.activityCategoryids)
    }
    var canRead: Bool {
        active && model.canReadMetadataDraft && session != nil && session == model.coordinator.session &&
        identity == model.coordinator.identity && modelGeneration == model.metadataGeneration &&
        originalDraft == model.draft && readerIdentity == reader?.discoveryPresentationIdentity
    }
    var canEdit: Bool { canRead && model.canEdit && !model.busy && model.coordinator.review == nil }
    var savedRawValue: String? { canRead ? field.rawValue(in: originalDraft) : nil }
    var visibleOptions: [TemplateMetadataOption] { canRead ? options : [] }
    var visibleCategories: [DiscoveryCategory] { canRead ? categories : [] }
    var visibleSelectedIDs: [Int] { canRead ? selection.selectedIDs : [] }
    var canSaveCategories: Bool { canEdit && reader?.isConfigured == true && field == .categories && selection.isSupported && (state == .loaded || state == .empty) }
    var visibleState: State { canRead ? state : .unavailable }
    func close() { active = false; generation += 1; options = []; categories = []; state = .unavailable }
    func canSelect(_ option: TemplateMetadataOption) -> Bool {
        guard canEdit, reader?.isConfigured == true, state == .loaded, options.contains(option),
              options.filter({ $0.value == option.value }).count == 1 else { return false }
        return field == .players || (field == .duration && option.losslessDurationMinutes != nil)
    }
    @discardableResult func select(_ option: TemplateMetadataOption) -> Bool {
        guard canSelect(option) else { return false }
        switch field {
        case .players: model.draft.players = option.value
        case .duration:
            guard let minutes = option.losslessDurationMinutes else { return false }
            model.draft.duration = minutes
        case .categories: return false
        }
        model.changed(); close(); return true
    }
    func toggleCategory(_ id: Int) {
        guard canSaveCategories, categories.contains(where: { $0.id == id }) || selection.selectedIDs.contains(id) else { return }
        selection.toggle(id)
    }
    func replaceUnsupportedCategories() {
        guard canEdit, field == .categories, state == .loaded || state == .empty else { return }
        selection.replaceUnsupportedSelection()
    }
    @discardableResult func saveCategories() -> Bool {
        guard canSaveCategories else { return false }
        if selection.hasChanges {
            model.draft.activityCategoryids = selection.savedValue
            // The legacy primary category is never normalized or rewritten here.
            model.changed()
        }
        close(); return true
    }
    func load() async {
        guard canEdit else { return }
        generation += 1; let stamp = generation
        state = .loading; options = []; categories = []
        guard let reader, reader.isConfigured else { state = .unavailable; return }
        if let kind = field.dictionaryKind {
            let request = reader.templateMetadataDictionaryRequest(kind: kind)
            do {
                let rows = try await request.read()
                guard accepts(stamp) else { return }
                options = rows; state = rows.isEmpty ? .empty : .loaded
            } catch { accept(error, stamp: stamp, unauthorized: request.onUnauthorized) }
        } else {
            let request = reader.templateMetadataCategoriesRequest()
            do {
                let rows = try await request.read()
                guard accepts(stamp) else { return }
                guard Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
                categories = rows; state = rows.isEmpty ? .empty : .loaded
            } catch { accept(error, stamp: stamp, unauthorized: request.onUnauthorized) }
        }
    }
    private func accepts(_ stamp: Int) -> Bool { stamp == generation && canEdit && !Task.isCancelled }
    private func accept(_ error: Error, stamp: Int, unauthorized: @MainActor () -> Void) {
        guard accepts(stamp) else { return }
        if case APIError.unauthorized = error { unauthorized() }
        guard accepts(stamp) else { return }
        state = error as? APIError == .notConfigured ? .unavailable : .failed
    }
}

@MainActor struct TemplateAuthoringMetadataFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    let reader: (any DiscoveryReading)?
    @State private var presented: TemplateMetadataField?
    var body: some View {
        // A concrete container owns the presentation. A sheet attached directly
        // to the lazy ForEach can disappear when Form flattens its children.
        VStack(spacing: 12) {
            ForEach(TemplateMetadataField.allCases) { field in
                if field != .players { Divider() }
                Button { presented = field } label: {
                    LabeledContent {
                        if let value = field.rawValue(in: model.draft) { Text(verbatim: value).foregroundStyle(.secondary) }
                        else { Text("templateMetadata.choose").foregroundStyle(.secondary) }
                    } label: { Text(LocalizedStringKey(field.titleKey)) }
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                // Three independent controls share this Form row.
                .buttonStyle(.borderless)
                .accessibilityIdentifier("templateMetadata.open." + field.rawValue)
            }
        }
        .sheet(item: $presented) { field in
            NavigationStack { TemplateAuthoringMetadataSelector(model: model, reader: reader, field: field) }
        }
    }
}

@MainActor private struct TemplateAuthoringMetadataSelector: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateAuthoringMetadataEditor
    @State private var presentationRevision = 0
    private let reader: (any DiscoveryReading)?
    init(model: TemplateAuthoringModel, reader: (any DiscoveryReading)?, field: TemplateMetadataField) {
        self.model = model; self.reader = reader
        _editor = StateObject(wrappedValue: .init(model: model, reader: reader, field: field))
    }
    var body: some View {
        let _ = presentationRevision
        List {
            if editor.canRead {
                Section("templateMetadata.saved") {
                    if let raw = editor.savedRawValue { Text(verbatim: raw).accessibilityIdentifier("templateMetadata.savedRaw") }
                    else { Text("templateMetadata.unset") }
                }
            }
            switch editor.visibleState {
            case .idle, .loading: ProgressView("templateMetadata.loading")
            case .empty: Text("templateMetadata.empty").accessibilityIdentifier("templateMetadata.empty")
            case .failed:
                Text("templateMetadata.failed")
                Button("action.retry") { Task { await editor.load() } }.accessibilityIdentifier("templateMetadata.retry")
            case .unavailable: Text("templateMetadata.unavailable").accessibilityIdentifier("templateMetadata.unavailable")
            case .loaded: EmptyView()
            }
            if editor.field == .categories { categoryRows }
            else {
                ForEach(Array(editor.visibleOptions.enumerated()), id: \.offset) { index, option in
                    Button { if editor.select(option) { dismiss() } } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(verbatim: option.label)
                                Text(verbatim: option.value).font(.caption).foregroundStyle(.secondary)
                                if !editor.canSelect(option) { Text("templateMetadata.unsupportedOption").font(.caption) }
                            }
                            Spacer()
                            if editor.savedRawValue == option.value { Image(systemName: "checkmark") }
                        }
                    }.disabled(!editor.canSelect(option)).accessibilityIdentifier("templateMetadata.option.\(index)")
                }
            }
        }
        .navigationTitle(LocalizedStringKey(editor.field.titleKey))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("templateAuthor.cancel") { editor.close(); dismiss() }.accessibilityIdentifier("templateMetadata.cancel")
            }
            if editor.field == .categories {
                ToolbarItem(placement: .confirmationAction) {
                    Button("templateMetadata.save") { if editor.saveCategories() { dismiss() } }
                        .disabled(!editor.canSaveCategories).accessibilityIdentifier("templateMetadata.save")
                }
            }
        }
        .task { await editor.load() }
        .onDisappear { editor.close() }
        .onReceive(reader?.discoveryPresentationChanges ?? Empty<Void, Never>().eraseToAnyPublisher()) { presentationRevision &+= 1 }
        .onChange(of: reader?.discoveryPresentationIdentity) { _, _ in editor.close() }
    }
    @ViewBuilder private var categoryRows: some View {
        if editor.canRead, !editor.selection.isSupported {
            Text("templateMetadata.legacyCategories")
            Button("templateMetadata.replaceCategories") { editor.replaceUnsupportedCategories() }
                .disabled(!editor.canEdit || (editor.visibleState != .loaded && editor.visibleState != .empty))
                .accessibilityIdentifier("templateMetadata.replaceCategories")
        }
        ForEach(editor.visibleSelectedIDs.filter { id in !editor.visibleCategories.contains(where: { $0.id == id }) }, id: \.self) { id in
            Button { editor.toggleCategory(id) } label: {
                HStack { Text("templateMetadata.unknownCategory"); Text(verbatim: String(id)); Spacer(); Image(systemName: "checkmark") }
            }.disabled(!editor.canSaveCategories).accessibilityIdentifier("templateMetadata.category.\(id)")
        }
        ForEach(editor.visibleCategories) { row in
            Button { editor.toggleCategory(row.id) } label: {
                HStack { Text(verbatim: row.name); Spacer(); if editor.visibleSelectedIDs.contains(row.id) { Image(systemName: "checkmark") } }
            }.disabled(!editor.canSaveCategories).accessibilityIdentifier("templateMetadata.category.\(row.id)")
                .accessibilityAddTraits(editor.visibleSelectedIDs.contains(row.id) ? .isSelected : [])
        }
    }
}
