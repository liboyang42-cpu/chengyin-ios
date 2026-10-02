#if DEBUG
import SwiftUI

@MainActor private final class TemplateAuthoringFixtureContext: ObservableObject {
    let storage = TemplateAuthoringMemoryStorage()
    let transport: TemplateAuthoringSyntheticTransport
    @Published var revision: UInt64 = 1
    @Published var mount = UUID()
    var session: TemplateAuthoringSession? = try? .init(accountID: 901, namespace: "synthetic-template-author", epoch: 1, authorizationRevision: "member-fixture")
    private let disabled: Bool
    lazy var store = TemplateAuthoringLocalStore(storage: storage)
    lazy var coordinator = makeCoordinator()
    init() {
        let args = ProcessInfo.processInfo.arguments
        disabled = args.contains("--template-author-disabled")
        transport = .init(scenario: args.contains("--template-author-unknown") ? .uncertain : args.contains("--template-author-duplicate") ? .duplicate : .accepted)
    }
    func makeCoordinator() -> TemplateAuthoringCoordinator {
        let c = TemplateAuthoringCoordinator(adapter: .init(transport: disabled ? nil : transport), store: store, currentSession: { [weak self] in self?.session })
        c.open(seed: ProcessInfo.processInfo.arguments.contains("--template-author-blank") ? .init() : TemplateAuthoringSyntheticFixtures.draft())
        return c
    }
    func signOut() { session = nil; coordinator.synchronizeSession(); revision += 1; mount = UUID() }
    func switchAccount() { session = try? .init(accountID: 902, namespace: "synthetic-template-author", epoch: revision + 1, authorizationRevision: "member-fixture"); coordinator.synchronizeSession(); revision += 1; mount = UUID() }
    func reopen() { coordinator.leaveScreen(); coordinator = makeCoordinator(); mount = UUID() }
}
@MainActor struct TemplateAuthoringFixtureHostView: View {
    @StateObject private var context = TemplateAuthoringFixtureContext()
    var body: some View {
        VStack {
            HStack {
                Button("templateAuthor.fixture.signOut") { context.signOut() }.accessibilityIdentifier("templateAuthor.fixture.signOut")
                Button("templateAuthor.fixture.switch") { context.switchAccount() }.accessibilityIdentifier("templateAuthor.fixture.switch")
                Button("templateAuthor.fixture.reopen") { context.reopen() }.accessibilityIdentifier("templateAuthor.fixture.reopen")
            }.buttonStyle(.bordered)
            NavigationStack {
                if ProcessInfo.processInfo.arguments.contains("--template-author-shelf") {
                    TemplateAuthoringMineView(coordinator: context.coordinator, sessionRevision: context.revision)
                } else { TemplateAuthoringView(coordinator: context.coordinator, sessionRevision: context.revision) }
            }.id(context.mount)
        }
    }
}
#endif
