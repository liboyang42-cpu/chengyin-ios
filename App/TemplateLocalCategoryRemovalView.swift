import SwiftUI
import Combine

@MainActor final class TemplateLocalCategoryRemovalController: ObservableObject {
    private let model: TemplateAuthoringModel
    private let owner: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private var generation = UUID()
    private var sceneActive = false
    private(set) var isVisible = false
    private var observation: AnyCancellable?
    @Published private var active = false
    @Published private var projection: TemplateLocalCategoryRemoval?
    init(model: TemplateAuthoringModel) {
        self.model = model; owner = model.coordinator.session; identity = model.coordinator.identity
        observation = model.objectWillChange.sink { [weak self] _ in self?.generation = UUID() }
    }
    var canReload: Bool {
        isVisible && sceneActive && model.canReadMetadataDraft && owner != nil &&
        owner == model.coordinator.session && identity == model.coordinator.identity
    }
    var canRead: Bool { active && canReload && projection?.isCurrent(model.draft) == true }
    var canEdit: Bool { canRead && model.canEdit && !model.busy && model.review == nil && isSupported }
    var isSupported: Bool { canRead && projection?.isSupported == true }
    var visibleIDs: [Int] { canRead ? projection?.selectedIDs ?? [] : [] }
    var visibleRaw: String? { canRead ? projection?.original : nil }
    func viewAppeared(sceneIsActive: Bool) {
        isVisible = true; sceneActive = sceneIsActive
        guard sceneActive else { retire(); return }
        if !active { reload() }
    }
    func viewDisappeared() { isVisible = false; retire() }
    func sceneChanged(isActive: Bool) {
        let becameActive = !sceneActive && isActive; sceneActive = isActive
        guard isVisible && sceneActive else { retire(); return }
        if becameActive || !active { reload() }
    }
    func reload() {
        guard canReload else { retire(); return }
        generation = UUID(); projection = .init(model.draft); active = true
    }
    private func retire() { generation = UUID(); active = false; projection = nil }
    func removeAction(_ id: Int) -> () -> Void {
        let stamp = generation, metadata = model.metadataGeneration, original = projection
        return { [weak self] in
            guard let self, self.canEdit, self.generation == stamp,
                  self.model.metadataGeneration == metadata,
                  let next = original?.removing(id, from: self.model.draft) else { return }
            self.generation = UUID()
            self.model.draft = next
            self.model.changed()
            self.reload()
        }
    }
}

@MainActor struct TemplateLocalCategoryRemovalView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateLocalCategoryRemovalController
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel) {
        self.model = model
        _controller = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        Form {
            Section {
                Text("templateLocalCategories.scope", tableName: "TemplateLocalCategoryRemoval")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if controller.canRead {
                Section {
                    if let raw = controller.visibleRaw {
                        Text(verbatim: raw).textSelection(.enabled)
                            .accessibilityIdentifier("templateLocalCategories.raw")
                    } else { Text("templateLocalCategories.unset", tableName: "TemplateLocalCategoryRemoval") }
                    if !controller.isSupported {
                        Text("templateLocalCategories.unsupported", tableName: "TemplateLocalCategoryRemoval")
                    } else if controller.visibleIDs.isEmpty {
                        Text("templateLocalCategories.empty", tableName: "TemplateLocalCategoryRemoval")
                    }
                }
                ForEach(controller.visibleIDs, id: \.self) { id in
                    HStack {
                        Text(verbatim: "#" + String(id))
                        Spacer()
                        Button(action: controller.removeAction(id)) {
                            Text("templateLocalCategories.remove", tableName: "TemplateLocalCategoryRemoval")
                        }
                        .buttonStyle(.borderless).disabled(!controller.canEdit)
                        .accessibilityIdentifier("templateLocalCategories.remove." + String(id))
                        .accessibilityLabel(Text("templateLocalCategories.removeID", tableName: "TemplateLocalCategoryRemoval") + Text(verbatim: " " + String(id)))
                    }
                }
            } else {
                Section {
                    Text("templateLocalCategories.changed", tableName: "TemplateLocalCategoryRemoval")
                    Button(action: controller.reload) {
                        Text("templateLocalCategories.reload", tableName: "TemplateLocalCategoryRemoval")
                    }.disabled(!controller.canReload)
                        .accessibilityIdentifier("templateLocalCategories.reload")
                }
            }
        }
        .navigationTitle(Text("templateLocalCategories.title", tableName: "TemplateLocalCategoryRemoval"))
        .onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }
        .onDisappear { controller.viewDisappeared() }
        .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
    }
}
