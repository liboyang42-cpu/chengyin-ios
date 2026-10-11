import SwiftUI
import Combine

@MainActor final class TemplateHotspotPlacementController: ObservableObject {
    struct SceneRequest: Identifiable, Equatable { let id = UUID(); let url: URL; let reference: Data }
    private let model: TemplateAuthoringModel
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private var mediaGeneration = UUID()
    private var actionGeneration = UUID()
    private var textGeneration = UUID()
    private var writing = false
    private var writingText = false
    private var observation: AnyCancellable?
    private var draftObservation: AnyCancellable?
    @Published private var active = false
    @Published private(set) var armedID: String?
    @Published private(set) var sceneRequest: SceneRequest?
    @Published private var readyID: UUID?

    init(model: TemplateAuthoringModel) {
        self.model = model; session = model.coordinator.session; identity = model.coordinator.identity
        reload()
        observation = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.actionGeneration = UUID()
            if !self.writingText { self.textGeneration = UUID() }
            if !self.writing && !self.canEdit { self.clearScene() }
        }
        // Draft publication distinguishes external edits from the parent Form's
        // later changed() notification for an edit already applied by this controller.
        draftObservation = model.$draft.sink { [weak self] _ in
            guard let self, !self.writing else { return }
            self.clearScene()
        }
    }
    private var projection: TemplateHotspotPlacement { .init(model.draft.advanced) }
    private var hasLease: Bool {
        active && model.canReadStoryDraft && session != nil && session == model.coordinator.session &&
            identity == model.coordinator.identity && mediaGeneration == model.mediaReviewGeneration
    }
    var canEdit: Bool { hasLease && model.canEdit && projection.canEdit }
    var canAdd: Bool { canEdit && projection.canAdd }
    var canRemove: Bool { canEdit && projection.canRemove }
    var canLoadScene: Bool { canEdit && projection.sceneURL != nil }
    var targets: [TemplateHotspotPlacement.Target] { hasLease ? projection.targets : [] }
    var scene: SceneRequest? { guard let sceneRequest, isCurrent(sceneRequest) else { return nil }; return sceneRequest }
    var isSceneReady: Bool { scene.map { readyID == $0.id } ?? false }
    var issues: [TemplateCreatorIssue] {
        guard hasLease else { return [] }
        return model.draft.advanced.creatorIssues(.hiddenObject).filter { $0.path == "imageUrl" || $0.path == "hotspots" || $0.path.hasPrefix("hotspots[") }
    }
    func reload() { actionGeneration = UUID(); textGeneration = UUID(); clearScene(); mediaGeneration = model.mediaReviewGeneration; active = true }
    func retire() { active = false; actionGeneration = UUID(); textGeneration = UUID(); clearScene() }
    private func clearScene() { armedID = nil; readyID = nil; sceneRequest = nil }
    private func isCurrent(_ request: SceneRequest) -> Bool {
        canEdit && sceneRequest?.id == request.id && Data(projection.sceneReference.utf8) == request.reference
    }
    func loadSceneAction() -> () -> Void {
        let stamp = actionGeneration, snapshot = projection
        return { [weak self] in
            guard let self, self.canLoadScene, self.actionGeneration == stamp, snapshot.isCurrent(self.model.draft.advanced), let url = snapshot.sceneURL else { return }
            self.actionGeneration = UUID(); self.textGeneration = UUID(); self.clearScene()
            self.sceneRequest = .init(url: url, reference: Data(snapshot.sceneReference.utf8))
        }
    }
    func imageReady(_ request: SceneRequest) { guard isCurrent(request) else { return }; readyID = request.id }
    func imageFailed(_ request: SceneRequest) { guard isCurrent(request) else { return }; readyID = nil; armedID = nil }
    func armAction(_ id: String) -> () -> Void {
        let stamp = actionGeneration, snapshot = projection
        return { [weak self] in
            guard let self, self.canEdit, self.isSceneReady, self.actionGeneration == stamp,
                  snapshot.isCurrent(self.model.draft.advanced), self.targets.contains(where: { $0.id == id }) else { return }
            self.actionGeneration = UUID(); self.textGeneration = UUID()
            self.armedID = self.armedID == id ? nil : id
        }
    }
    func placementAction() -> (Double, Double, Double, Double) -> Void {
        let stamp = actionGeneration, snapshot = projection, id = armedID, requestID = scene?.id
        return { [weak self] x, y, width, height in
            guard let self, self.canEdit, self.isSceneReady, self.actionGeneration == stamp,
                  requestID == self.scene?.id, let id, self.armedID == id,
                  let next = snapshot.applying(.place(id, x: x, y: y, width: width, height: height), to: self.model.draft.advanced) else { return }
            self.armedID = nil; self.actionGeneration = UUID(); self.textGeneration = UUID(); self.apply(next)
        }
    }
    func addAction() -> () -> Void { action(.add("spot_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))) }
    func removeAction(_ id: String) -> () -> Void { action(.remove(id)) }
    func moveAction(_ id: String, to destination: Int) -> () -> Void { action(.move(id, destination)) }
    private func action(_ edit: TemplateHotspotPlacement.Edit) -> () -> Void {
        let stamp = actionGeneration, snapshot = projection, metadata = model.metadataGeneration
        return { [weak self] in
            guard let self, self.canEdit, self.actionGeneration == stamp, self.model.metadataGeneration == metadata,
                  let next = snapshot.applying(edit, to: self.model.draft.advanced) else { return }
            self.armedID = nil; self.actionGeneration = UUID(); self.textGeneration = UUID(); self.apply(next)
        }
    }
    func label(_ id: String) -> Binding<String> {
        let stamp = textGeneration
        return .init(get: { [weak self] in
            guard let self, self.hasLease, self.textGeneration == stamp else { return "" }
            return self.targets.first(where: { $0.id == id })?.label ?? ""
        }, set: { [weak self] text in
            guard let self, self.canEdit, self.textGeneration == stamp,
                  let next = self.projection.applying(.label(id, text), to: self.model.draft.advanced) else { return }
            self.armedID = nil; self.writingText = true; defer { self.writingText = false }; self.apply(next)
        })
    }
    private func apply(_ next: TemplateAdvancedDraft) {
        guard next != model.draft.advanced else { return }
        writing = true; defer { writing = false }
        model.draft.advanced = next; model.changed()
    }
}

@MainActor struct TemplateHotspotPlacementView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateHotspotPlacementController
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel) { self.model = model; _editor = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        Form {
            Section {
                Text("templateHotspots.instructions").font(.callout)
                Button("templateHotspots.loadScene", systemImage: "photo", action: editor.loadSceneAction())
                    .disabled(!editor.canLoadScene).accessibilityIdentifier("creator.hotspots.load")
                if !editor.canLoadScene { Text("templateHotspots.sceneUnavailable").font(.caption) }
                if let request = editor.scene { canvas(request).id(request.id) }
            }
            Section("creator.field.hotspots") {
                ForEach(Array(editor.targets.enumerated()), id: \.element.id) { index, target in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("templateHotspots.targetNumber \(index + 1)").font(.headline)
                        TextField("creator.field.label", text: editor.label(target.id), axis: .vertical)
                            .accessibilityIdentifier("creator.hotspots.label." + target.id)
                        HStack {
                            Button(action: editor.armAction(target.id)) {
                                Label(LocalizedStringKey(editor.armedID == target.id ? "templateHotspots.cancel" : "templateHotspots.mark"), systemImage: editor.armedID == target.id ? "xmark.circle" : "scope")
                            }.disabled(!editor.isSceneReady).accessibilityIdentifier("creator.hotspots.arm." + target.id)
                            Spacer()
                            Text(LocalizedStringKey(target.point == nil ? "templateHotspots.unplaced" : "templateHotspots.placed")).font(.caption)
                            Button("creator.remove", role: .destructive, action: editor.removeAction(target.id)).disabled(!editor.canRemove)
                        }.buttonStyle(.borderless)
                        HStack {
                            Button(action: editor.moveAction(target.id, to: index - 1)) { Label("playkit.sort.up", systemImage: "arrow.up") }.disabled(index == 0)
                            Button(action: editor.moveAction(target.id, to: index + 1)) { Label("playkit.sort.down", systemImage: "arrow.down") }.disabled(index == editor.targets.count - 1)
                        }.buttonStyle(.borderless)
                    }
                }
                Button("templateHotspots.add", systemImage: "plus", action: editor.addAction()).disabled(!editor.canAdd)
                    .accessibilityIdentifier("creator.hotspots.add")
                Text("templateHotspots.countBoundary").font(.caption).foregroundStyle(.secondary)
            }
            if !editor.issues.isEmpty {
                Section("templateAuthor.validationTitle") {
                    ForEach(editor.issues) { issue in VStack(alignment: .leading) { Text(LocalizedStringKey(issue.labelKey)); Text(verbatim: issue.path).font(.caption) } }
                }
            }
        }.navigationTitle("templateHotspots.title").disabled(!editor.canEdit)
            .onAppear { editor.reload() }.onDisappear { editor.retire() }
            .onChange(of: model.mediaReviewGeneration) { _, _ in editor.reload() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { editor.reload() } else { editor.retire() } }
    }
    private func canvas(_ request: TemplateHotspotPlacementController.SceneRequest) -> some View {
        AsyncImage(url: request.url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit().overlay {
                    GeometryReader { geometry in
                        let place = editor.placementAction()
                        ZStack(alignment: .topLeading) {
                            Color.clear.contentShape(Rectangle())
                                .gesture(SpatialTapGesture().onEnded { event in
                                    place(Double(event.location.x), Double(event.location.y), Double(geometry.size.width), Double(geometry.size.height))
                                })
                            ForEach(Array(editor.targets.enumerated()), id: \.element.id) { index, target in
                                if let point = target.point {
                                    Text(verbatim: String(index + 1)).font(.caption.bold()).padding(6)
                                        .background(editor.armedID == target.id ? Color.orange : Color.accentColor, in: Circle())
                                        .foregroundStyle(.white).position(x: geometry.size.width * CGFloat(point.x), y: geometry.size.height * CGFloat(point.y))
                                        .allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                        }
                    }
                }.frame(maxHeight: 320).onAppear { editor.imageReady(request) }
                    .accessibilityLabel("templateHotspots.canvas").accessibilityIdentifier("creator.hotspots.canvas")
            } else if phase.error != nil {
                Text("templateHotspots.loadFailed").onAppear { editor.imageFailed(request) }
            } else { ProgressView().accessibilityLabel("templateHotspots.loading") }
        }
    }
}
