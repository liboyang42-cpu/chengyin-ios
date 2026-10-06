#if DEBUG
import SwiftUI

@MainActor final class ProjectOwnedContentFixture: ObservableObject {
    final class Wire: HTTPTransport {
        var data: Data; var status = 200; private(set) var requests = 0; var beforeReply: (() async -> Void)?
        init(_ data: Data) { self.data = data }
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests += 1; if let beforeReply { await beforeReply() }; return (data, status) }
    }
    let reader = CreatorContentFixtureReader()
    let detailReader = TopicFixtureReader()
    let storage = ProjectEditMemoryStorage()
    let wire: Wire
    @Published var revision: UInt64 = 1
    @Published var session: ProjectEditSession? = try? .init(accountID: 901, epoch: 1, storageNamespace: "owned-editor-fixture")
    lazy var store = ProjectEditLocalStore(storage: storage)
    private let seedCompleted: Bool
    private var retained: ProjectEditCoordinator?
    init(arguments: [String]) {
        seedCompleted = arguments.contains("--project-owned-completed")
        let product: ProjectEditProduct = arguments.contains("--project-owned-city") ? .city : .freeExplore
        wire = Wire((try? ProjectEditRemoteFixtures.detail(product: product)) ?? Data())
        reader.projectsJSON = #"{"code":200,"data":{"rows":[{"id":71,"bizType":"topic","ownerType":"member","title":"Owned fixture route","projectTypeText":"Synthetic own-account content"}],"total":1}}"#
        if arguments.contains("--project-owned-denied") { wire.status = 403; wire.data = Data(#"{"code":403,"msg":"Synthetic forbidden edit"}"#.utf8) }
    }
    func editor(_ target: ProjectEditRemoteTarget) -> ProjectEditCoordinator? {
        guard target.readerScope == reader.scope, reader.isAuthenticated, session != nil else { return nil }
        if let retained { return retained }
        guard let config = try? APIConfiguration(baseURL: URL(string: "https://example.com")!) else { return nil }
        let service = ProjectEditHTTPService(configuration: config, transport: wire, owner: target.owner, currentCredentials: { [weak self] in
            self?.session.flatMap { try? .init(session: $0, token: "synthetic-owned-editor-token") }
        })
        if seedCompleted, let session, let identity = try? ProjectEditDraftIdentity(topicID: target.topicID) {
            let completed = ProjectEditPending(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
                payload: ["id": .number(Decimal(target.topicID))], completedTopicID: target.topicID, serverAcknowledged: true)
            try? store.savePending(completed, session: session)
        }
        var placeholder = ProjectEditDraft(); placeholder.owner = target.owner
        let co = ProjectEditCoordinator(initial: .init(topicID: target.topicID, draft: placeholder), service: service,
            store: store, currentSession: { [weak self] in self?.session })
        retained = co; return co
    }
    func signOut() { session = nil; reader.signOut(); retained?.synchronizeSession(); revision += 1 }
}
@MainActor struct ProjectOwnedContentFixtureHost: View {
    @StateObject private var context = ProjectOwnedContentFixture(arguments: ProcessInfo.processInfo.arguments)
    var body: some View {
        VStack(spacing: 0) {
            Button("projectEdit.fixture.signOut") { context.signOut() }
                .accessibilityIdentifier("projectOwned.fixture.signOut").font(.caption).dynamicTypeSize(.large)
            NavigationStack {
                ProjectOwnedContentBrowser(reader: context.reader, revision: context.revision,
                    makeEditor: { context.editor($0) }, detail: { destination in
                        if case .topic(let id) = destination { return AnyView(TopicDetailView(id: id, reader: context.detailReader)) }
                        return AnyView(EmptyView())
                    })
            }.id(context.revision)
        }
    }
}
#endif
