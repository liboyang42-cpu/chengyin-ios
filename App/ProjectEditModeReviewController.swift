import SwiftUI

/// Each picker and copy confirmation owns its original model incarnation and exact
/// draft bytes. Closing or confirming an old presentation never reacquires a new one.
@MainActor final class ProjectEditModeReviewController: ObservableObject {
    struct Context: Equatable {
        let incarnation: UUID
        let session: ProjectEditSession
        let bytes: Data
    }
    struct Picker: Identifiable { let id = UUID(); let context: Context; let product: ProjectEditProduct }
    struct Copy: Identifiable { let id = UUID(); let context: Context; let product: ProjectEditProduct; let draft: ProjectEditDraft }
    struct Presentation: Identifiable { let id = UUID() }
    @Published private(set) var presentation: Presentation?
    let model: ProjectEditModel
    @Published private(set) var picker: Picker?
    @Published private(set) var copy: Copy?
    init(model: ProjectEditModel) { self.model = model }
    private var context: Context? {
        guard model.fullEdit, model.draft.owner != .merchant, let session = model.coordinator.session,
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return nil }
        return .init(incarnation: model.editorIncarnation, session: session, bytes: bytes)
    }
    func open() { guard let context else { return }; picker = .init(context: context, product: model.draft.product); copy = nil; presentation = .init() }
    func select(_ product: ProjectEditProduct, from original: Picker) {
        guard picker?.id == original.id, context == original.context else { return }
        picker = nil
        if product != original.product { copy = .init(context: original.context, product: product, draft: model.draft) }
        else { presentation = nil }
    }
    func close(_ original: Picker) { guard picker?.id == original.id else { return }; picker = nil; presentation = nil }
    func cancel(_ original: Copy) { guard copy?.id == original.id else { return }; copy = nil; presentation = nil }
    func perform(_ original: Copy) throws -> ProjectEditCoordinator? {
        guard copy?.id == original.id, context == original.context else { return nil }
        copy = nil; presentation = nil // Claim synchronously before any persistence/callback can run.
        return try model.coordinator.copyForMode(original.draft, to: original.product)
    }
    func dismiss(_ original: Presentation) {
        guard presentation?.id == original.id else { return }
        presentation = nil; picker = nil; copy = nil
    }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        Binding(get: { self.presentation?.id == original?.id ? self.presentation : nil }, set: { next in
            guard next == nil, let original else { return }; self.dismiss(original)
        })
    }
}

@MainActor struct ProjectEditModeReviewSheet: View {
    @ObservedObject var controller: ProjectEditModeReviewController
    let original: ProjectEditModeReviewController.Presentation
    let finished: (ProjectEditCoordinator) -> Void
    let failed: () -> Void
    var body: some View {
        if controller.presentation?.id == original.id {
            if let copy = controller.copy {
                NavigationStack {
                    Form {
                        Text("contextPublish.mode.confirmBody")
                        Text(LocalizedStringKey(copy.product == .city ? "projectEdit.city" : "projectEdit.freeExplore"))
                        Text(verbatim: copy.draft.name)
                    }.navigationTitle("contextPublish.mode.confirmTitle")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.cancel(copy) }.accessibilityIdentifier("projectRemote.copy.cancel") }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("contextPublish.mode.copy") {
                                do { if let created = try controller.perform(copy) { finished(created) } }
                                catch { failed() }
                            }.accessibilityIdentifier("projectRemote.copy.confirm")
                        }
                    }
                }
            } else if let picker = controller.picker {
                PublishingModePickerSheet(current: picker.product) { controller.select($0, from: picker) }
            }
        }
    }
}
