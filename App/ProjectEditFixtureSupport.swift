#if DEBUG
import SwiftUI

@MainActor private final class ProjectEditFixtureContext: ObservableObject {
    var session: ProjectEditSession? = try? .init(accountID: 901, epoch: 1, storageNamespace: "synthetic-project-editor")
    let storage = ProjectEditMemoryStorage()
    let service: ProjectEditSyntheticService
    let initial: ProjectEditSnapshot
    let disabled: Bool
    @Published var revision: UInt64 = 1
    @Published var mount = UUID()
    lazy var store = ProjectEditLocalStore(storage: storage)
    lazy var coordinator = makeCoordinator()
    init(arguments: [String]) {
        disabled = arguments.contains("--project-edit-disabled")
        let scope: ProjectEditScope = arguments.contains("--project-edit-whitelist") ? .whitelist : .full
        var existing = ProjectEditSyntheticFixtures.snapshot(scope: scope)
        if arguments.contains("--project-edit-rich-story") { existing.draft = ProjectEditRichStoryFixtures.draft(); existing.draft.baseRevision = "fixture-r1"; existing.draft.publishToCreative = false }
        if arguments.contains("--project-edit-free-explore") { existing.draft.product = .freeExplore }
        service = ProjectEditSyntheticService(scenario: arguments.contains("--project-edit-unknown") ? .unknown : .accepted, snapshot: existing)
        if arguments.contains("--project-edit-edit") || scope == .whitelist { initial = existing }
        else {
            let draft = arguments.contains("--project-edit-blank") ? ProjectEditDraft(product: existing.draft.product) : (arguments.contains("--project-edit-rich-story") ? ProjectEditRichStoryFixtures.draft() : ProjectEditSyntheticFixtures.draft(product: existing.draft.product))
            initial = .init(draft: draft)
        }
    }
    func makeCoordinator() -> ProjectEditCoordinator {
        let selected: any ProjectEditServing = disabled ? ProjectEditDisabledService() : service
        return .init(initial: initial, service: selected, store: store, currentSession: { [weak self] in self?.session })
    }
    func signOut() { session = nil; coordinator.synchronizeSession(); revision += 1; mount = UUID() }
    func reopen() { coordinator.leaveScreen(); coordinator = makeCoordinator(); mount = UUID() }
}
@MainActor struct ProjectEditFixtureHostView: View {
    @StateObject private var context = ProjectEditFixtureContext(arguments: ProcessInfo.processInfo.arguments)
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("projectEdit.fixture.signOut") { context.signOut() }.accessibilityIdentifier("projectEdit.fixture.signOut")
                Button("projectEdit.fixture.reopen") { context.reopen() }.accessibilityIdentifier("projectEdit.fixture.reopen")
            }.buttonStyle(.bordered).padding(.horizontal)
            NavigationStack { ProjectEditView(coordinator: context.coordinator, sessionRevision: context.revision) }.id(context.mount)
        }
    }
}
#endif
