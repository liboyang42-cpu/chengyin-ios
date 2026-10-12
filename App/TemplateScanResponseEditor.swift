import SwiftUI
import Combine

@MainActor final class TemplateScanResponseController: ObservableObject {
    struct Request: Identifiable, Equatable { let id = UUID(); let kind: TemplateScanResponseConfiguration.Kind; let url: URL; let reference: Data }
    enum PreviewState: Equatable { case idle, loading, ready, failed }
    private let model: TemplateAuthoringModel
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private var mediaGeneration = UUID(), actionGeneration = UUID(), inputGeneration = UUID()
    private var writing = false
    private var publicationObservation: AnyCancellable?, draftObservation: AnyCancellable?, lockObservation: AnyCancellable?
    @Published private var active = false
    @Published private var configuration: TemplateScanResponseConfiguration
    @Published private var request: Request?
    @Published private(set) var previewState: PreviewState = .idle
    @Published private(set) var needsReload = false
    init(model: TemplateAuthoringModel) {
        self.model = model; session = model.coordinator.session; identity = model.coordinator.identity
        configuration = .init(model.draft.advanced); reload()
        publicationObservation = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }; self.actionGeneration = UUID()
            if !self.writing && (!self.canReload || !self.model.canEdit || self.mediaGeneration != self.model.mediaReviewGeneration) { self.suspend() }
        }
        draftObservation = model.$draft.dropFirst().sink { [weak self] _ in
            guard let self, !self.writing else { return }; self.suspend()
        }
        lockObservation = Publishers.CombineLatest(model.$busy, model.$review).dropFirst().sink { [weak self] values in
            if values.0 || values.1 != nil { self?.suspend() }
        }
    }
    var canReload: Bool { model.canReadStoryDraft && session != nil && session == model.coordinator.session && identity == model.coordinator.identity }
    private var hasLease: Bool { active && canReload && mediaGeneration == model.mediaReviewGeneration && configuration.isCurrent(model.draft.advanced) }
    var canEdit: Bool { hasLease && model.canEdit && !model.busy && model.review == nil && configuration.canEdit }
    var isSupported: Bool { hasLease && configuration.isSupported }
    var kind: TemplateScanResponseConfiguration.Kind { hasLease ? configuration.kind : .text }
    var arMode: TemplateScanResponseConfiguration.ARMode { hasLease ? configuration.arMode : .none }
    var currentFields: [TemplateScanResponseConfiguration.TextField] { hasLease ? configuration.currentTextFields : [] }
    var retainedFields: [TemplateScanResponseConfiguration.TextField] { hasLease ? configuration.retainedTextFields : [] }
    var showsRetainedAR: Bool { hasLease && configuration.showsRetainedAR }
    var widthPercent: Double { hasLease && configuration.isSupported ? configuration.previewWidthPercent : 100 }
    var canClearModel: Bool { canEdit && configuration.canClearModel }
    var canLoad: Bool { canEdit && configuration.previewURL != nil }
    var scene: Request? { guard let request, isCurrent(request) else { return nil }; return request }
    var issues: [TemplateCreatorIssue] { hasLease ? model.draft.advanced.creatorIssues(.scan) : [] }
    func reload() {
        actionGeneration = UUID(); inputGeneration = UUID(); clearPreview()
        guard canReload else { active = false; needsReload = true; return }
        configuration = .init(model.draft.advanced); mediaGeneration = model.mediaReviewGeneration; active = true; needsReload = false
    }
    func retire() { active = false; actionGeneration = UUID(); inputGeneration = UUID(); clearPreview() }
    func suspend() { retire(); needsReload = true }
    private func clearPreview() { request = nil; previewState = .idle }
    private func isCurrent(_ candidate: Request) -> Bool { canEdit && request?.id == candidate.id && configuration.kind == candidate.kind && configuration.previewReference.map({ Data($0.utf8) }) == candidate.reference }
    func kindInput() -> Binding<TemplateScanResponseConfiguration.Kind> {
        let stamp = inputGeneration
        return .init(get: { [weak self] in self?.kind ?? .text }, set: { [weak self] value in
            guard let self, self.canEdit, self.inputGeneration == stamp, self.configuration.kind != value else { return }
            self.change(.kind(value), rotatesInputs: true)
        })
    }
    func arModeInput() -> Binding<TemplateScanResponseConfiguration.ARMode> {
        let stamp = inputGeneration
        return .init(get: { [weak self] in self?.arMode ?? .none }, set: { [weak self] value in
            guard let self, self.canEdit, self.inputGeneration == stamp, self.configuration.arMode != value else { return }
            self.change(.arMode(value), rotatesInputs: true)
        })
    }
    func textInput(_ field: TemplateScanResponseConfiguration.TextField) -> Binding<String> {
        let stamp = inputGeneration
        return .init(get: { [weak self] in guard let self, self.hasLease, self.inputGeneration == stamp else { return "" }; return self.configuration.text(field) }, set: { [weak self] value in
            guard let self, self.canEdit, self.inputGeneration == stamp else { return }; self.change(.text(field, value))
        })
    }
    func scaleInput() -> Binding<Double> {
        let stamp = inputGeneration, reference = configuration.previewReference.map { Data($0.utf8) }
        return .init(get: { [weak self] in guard let self, self.hasLease, self.inputGeneration == stamp, self.configuration.kind == .overlay else { return 60 }; return self.configuration.scale }, set: { [weak self] value in
            guard let self, self.canEdit, self.inputGeneration == stamp, self.configuration.kind == .overlay, self.configuration.previewReference.map({ Data($0.utf8) }) == reference else { return }
            self.change(.scale(value))
        })
    }
    func clearModelAction() -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration, snapshot = configuration
        return { [weak self] in
            guard let self, self.canClearModel, self.actionGeneration == stamp, self.model.metadataGeneration == metadata, snapshot.isCurrent(self.model.draft.advanced) else { return }
            self.change(.clearModel, rotatesInputs: true)
        }
    }
    func loadAction() -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration, snapshot = configuration
        return { [weak self] in
            guard let self, self.canLoad, self.actionGeneration == stamp, self.model.metadataGeneration == metadata, snapshot.isCurrent(self.model.draft.advanced), let url = snapshot.previewURL, let reference = snapshot.previewReference else { return }
            self.actionGeneration = UUID(); self.clearPreview(); self.request = .init(kind: snapshot.kind, url: url, reference: Data(reference.utf8)); self.previewState = .loading
        }
    }
    func imageReady(_ candidate: Request) { guard isCurrent(candidate) else { return }; previewState = .ready }
    func imageFailed(_ candidate: Request) { guard isCurrent(candidate) else { return }; previewState = .failed }
    func saveAction() -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration
        return { [weak self] in guard let self, self.canEdit, self.actionGeneration == stamp, self.model.metadataGeneration == metadata else { return }; self.model.save() }
    }
    private func change(_ edit: TemplateScanResponseConfiguration.Edit, rotatesInputs: Bool = false) {
        guard canEdit, let next = configuration.applying(edit, to: model.draft.advanced) else { return }
        let updated = TemplateScanResponseConfiguration(next)
        actionGeneration = UUID(); if rotatesInputs { inputGeneration = UUID() }
        writing = true; defer { writing = false }
        if updated.kind != configuration.kind || updated.previewReference.map({ Data($0.utf8) }) != configuration.previewReference.map({ Data($0.utf8) }) { clearPreview() }
        if TemplateScanResponseConfiguration.TextField.allCases.filter({ $0 != .reply }).contains(where: { Data(updated.text($0).utf8) != Data(configuration.text($0).utf8) }) { model.mediaReferencesWillChange() }
        configuration = updated
        if !updated.isCurrent(model.draft.advanced) { model.draft.advanced = next; model.changed() }
    }
}

@MainActor struct TemplateScanResponseEditor: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateScanResponseController
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel) { self.model = model; _editor = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        Form {
            Section {
                Text("templateScan.instructions").font(.callout)
                if editor.needsReload {
                    Text("templateScan.changed").font(.caption)
                    Button("templateScan.reload") { editor.reload() }.disabled(!editor.canReload)
                } else if !editor.isSupported { Text("templateScan.unsupported") }
            }
            Section("templateScan.response") {
                Picker("creator.field.kind", selection: editor.kindInput()) {
                    ForEach(TemplateScanResponseConfiguration.Kind.allCases) { Text(LocalizedStringKey("creator.choice." + $0.rawValue)).tag($0) }
                }.accessibilityIdentifier("templateScan.kind")
                ForEach(editor.currentFields.filter { ![.markerUrl, .modelUrl].contains($0) }) { field in textField(field) }
            }.disabled(!editor.canEdit)
            if editor.isSupported && editor.kind == .overlay {
                Section("templateScan.overlay") {
                    Slider(value: editor.scaleInput(), in: 20...100, step: 5).accessibilityLabel("creator.field.overlayScale").accessibilityIdentifier("templateScan.scale")
                    Text("templateScan.width \(Int(editor.widthPercent))").font(.caption)
                    arPicker
                    ForEach(editor.currentFields.filter { [.markerUrl, .modelUrl].contains($0) }) { field in textField(field) }
                }.disabled(!editor.canEdit)
            }
            if !editor.retainedFields.isEmpty || editor.showsRetainedAR {
                Section("templateScan.retained") {
                    Text("templateScan.retainedNotice").font(.caption)
                    if editor.showsRetainedAR { arPicker }
                    ForEach(editor.retainedFields) { field in textField(field) }
                }.disabled(!editor.canEdit)
            }
            if editor.kind == .image || editor.kind == .overlay {
                Section("templateScan.preview") {
                    Text("templateScan.previewNotice").font(.caption)
                    Button("templateScan.load", systemImage: "photo", action: editor.loadAction()).disabled(!editor.canLoad).accessibilityIdentifier("templateScan.load")
                    if let scene = editor.scene {
                        AsyncImage(url: scene.url) { phase in
                            if let image = phase.image {
                                GeometryReader { geometry in
                                    ZStack {
                                        Color.gray.opacity(0.15)
                                        image.resizable().scaledToFit().frame(width: geometry.size.width * editor.widthPercent / 100, height: geometry.size.height)
                                    }.frame(width: geometry.size.width, height: geometry.size.height)
                                }.frame(height: 240).onAppear { editor.imageReady(scene) }
                            } else if phase.error != nil {
                                Text("templateScan.failed").onAppear { editor.imageFailed(scene) }
                            } else { ProgressView("templateScan.loading") }
                        }.id(scene.id).accessibilityIdentifier("templateScan.image")
                    }
                }
            }
            if !editor.issues.isEmpty {
                Section("templateAuthor.validationTitle") {
                    ForEach(editor.issues) { issue in VStack(alignment: .leading) { Text(LocalizedStringKey(issue.labelKey)); Text(verbatim: issue.path).font(.caption) } }
                }
            }
            Section { Button("templateAuthor.saveLocal", action: editor.saveAction()).disabled(!editor.canEdit || !model.draft.canSave).accessibilityIdentifier("templateScan.saveLocal") }
        }.navigationTitle("templateScan.title")
            .onDisappear { editor.retire() }
            .onChange(of: model.canEdit) { _, allowed in if !allowed { editor.suspend() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { editor.suspend() } }
    }
    private var arPicker: some View {
        Picker("creator.field.arMode", selection: editor.arModeInput()) {
            ForEach(TemplateScanResponseConfiguration.ARMode.allCases) { Text(LocalizedStringKey("creator.choice." + $0.rawValue)).tag($0) }
        }.accessibilityIdentifier("templateScan.arMode")
    }
    @ViewBuilder private func textField(_ field: TemplateScanResponseConfiguration.TextField) -> some View {
        VStack(alignment: .leading) {
            Text(LocalizedStringKey(field.labelKey)).font(.headline)
            TextField(LocalizedStringKey(field.labelKey), text: editor.textInput(field), axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("templateScan.field." + field.rawValue)
            if field == .modelUrl {
                Text("templateScan.modelNotice").font(.caption)
                Button("templateScan.clearModel", role: .destructive, action: editor.clearModelAction()).disabled(!editor.canClearModel).accessibilityIdentifier("templateScan.clearModel")
            }
        }
    }
}
