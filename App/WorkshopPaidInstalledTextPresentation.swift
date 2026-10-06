import Foundation
import Observation

/// Shared by the actual entry View and app-host regression. Selection owns a single irreversible
/// appearance; old sheet setters/disappear callbacks never select or close a replacement.
@MainActor @Observable final class WorkshopPaidInstalledTextPresentation {
    @MainActor final class Selection: Identifiable {
        let id = UUID()
        let controller: WorkshopPaidInstalledTextController
        let appearance = WorkshopPaidInstalledTextAppearance()
        init(controller: WorkshopPaidInstalledTextController) { self.controller = controller }
    }
    private(set) var selection: Selection?
    private(set) var unavailable = false
    func open(makeReference: @MainActor () -> WorkshopPaidInstalledTextReference?, makeController: WorkshopPaidInstalledTextControllerFactory) {
        guard selection == nil, let reference = makeReference() else { return }
        guard let controller = makeController(reference) else { unavailable = true; return }
        unavailable = false; selection = Selection(controller: controller)
    }
    func replace(_ replacement: Selection?, expected: UUID?) {
        guard selection?.id == expected else { return }
        if let old = selection, old.id != replacement?.id { old.controller.close(old.appearance) }
        selection = replacement
    }
    func dismiss(_ displayed: Selection) {
        displayed.controller.close(displayed.appearance)
        guard selection === displayed else { return }
        selection = nil
    }
}
