import Foundation
import Observation

@MainActor @Observable final class WorkshopPaidProfessionalPresentation {
    @MainActor final class Selection: Identifiable {
        let id = UUID()
        let controller: WorkshopPaidProfessionalController
        let appearance = WorkshopPaidProfessionalAppearance()
        init(_ controller: WorkshopPaidProfessionalController) { self.controller = controller }
    }
    private(set) var selection: Selection?
    private(set) var unavailable = false
    func open(makeReference: @MainActor () -> WorkshopPaidInstalledTextReference?, makeController: WorkshopPaidProfessionalControllerFactory) {
        guard selection == nil, let reference = makeReference() else { return }
        guard let controller = makeController(reference) else { unavailable = true; return }
        unavailable = false; selection = Selection(controller)
    }
    func replace(_ replacement: Selection?, expected: UUID?) {
        guard selection?.id == expected else { return }
        if let old = selection, old.id != replacement?.id { old.controller.close(old.appearance) }
        selection = replacement
    }
    func dismiss(_ displayed: Selection) {
        displayed.controller.close(displayed.appearance)
        guard selection === displayed else { return }; selection = nil
    }
}
