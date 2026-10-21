#if DEBUG
import SwiftUI

@MainActor private final class TemplateAuthoringMemberDetailFixtureReader: MemberTemplateReading {
    let scope = UUID()
    let isAuthenticated = true
    let isConfigured = true
    func memberTemplate(id: MemberPlayTemplateID) async throws -> MemberTemplateDetail {
        guard id.rawValue == 901 else { throw APIError.malformedResponse }
        return try JSONDecoder().decode(MemberTemplateDetail.self, from: Data(#"{"id":901,"title":"Synthetic owned detail","draftStatus":0}"#.utf8))
    }
}
@MainActor private final class TemplateAuthoringFixtureContext: ObservableObject {
    lazy var creatorHarness = WorkshopCreatorPendingFixtureHarness()
    let metadataReader: DiscoveryFixtureReader
    let memberReader = TemplateAuthoringMemberDetailFixtureReader()
    let storage = TemplateAuthoringMemoryStorage()
    let transport: TemplateAuthoringSyntheticTransport
    @Published var revision: UInt64 = 1
    @Published var mount = UUID()
    @Published var localSnapshot = ""
    private var inspectionSequence = 0
    var session: TemplateAuthoringSession? = try? .init(accountID: 901, namespace: "synthetic-template-author", epoch: 1, authorizationRevision: "member-fixture")
    private let disabled: Bool
    lazy var store = TemplateAuthoringLocalStore(storage: storage)
    lazy var coordinator = makeCoordinator()
    init() {
        let args = ProcessInfo.processInfo.arguments
        let metadataScenario = ProcessInfo.processInfo.environment["--template-author-metadata-scenario"]
            .flatMap(DiscoveryFixtureReader.MetadataScenario.init(rawValue:))
        metadataReader = DiscoveryFixtureReader(metadataScenario: metadataScenario)
        disabled = args.contains("--template-author-disabled")
        transport = .init(scenario: args.contains("--template-author-unknown") ? .uncertain : args.contains("--template-author-duplicate") ? .duplicate : .accepted)
    }
    func makeCoordinator() -> TemplateAuthoringCoordinator {
        let c = TemplateAuthoringCoordinator(adapter: .init(transport: disabled ? nil : transport), store: store, currentSession: { [weak self] in self?.session })
        let arguments = ProcessInfo.processInfo.arguments
        var seed: TemplateAuthoringDraft = arguments.contains("--template-author-blank") ? .init() : arguments.contains("--template-author-compound") ? TemplateAuthoringSyntheticFixtures.compoundDraft() : TemplateAuthoringSyntheticFixtures.draft()
        // Only this DEBUG, in-memory authoring host consumes synthetic test data.
        // Keep the ordinary method so UI tests must select the local editor themselves.
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["--template-author-preference-raw"] { seed.preferenceJson = raw }
        if let type = environment["--template-author-sensor-type"] {
            seed.sensorDraft = .init(type: type, config: environment["--template-author-sensor-raw"])
        }
        // Raw history is seeded without migrating it; all later changes use ordinary UI controls.
        if let raw = environment["--template-author-rules-raw"] { seed.ruleInstructions = raw }
        if let raw = environment["--template-author-story-raw"] { seed.storyJson = raw; seed.storyTimelineEdited = nil }
        if let text = environment["--template-author-story-text"] { seed.storyText = text }
        if let text = environment["--template-author-hint1"] { seed.hint1 = text }
        if let text = environment["--template-author-hint2"] { seed.hint2 = text }
        if let text = environment["--template-author-answer-reveal"] { seed.answerReveal = text }
        if arguments.contains("--template-author-media-fixture") {
            seed.questionImg = "  fixture:image-e\u{301}\r\n"
            seed.questionAudio = "\tfixture:audio "
            seed.voiceEnabled = true; seed.audioUrl = " fixture:narration\n"
            seed.questionOptionMediaJson = " \n" + #"{"A":{"img":"  fixture:option-A-e\u0301\r\n"},"B":{"audio":"\tfixture:option-B-audio "}}"# + "\t "
        }
        // Metadata seeds are input-only. Read ledgers and request snapshots never write drafts.
        switch metadataReader.metadataScenario {
        case .dictionary:
            seed.players = nil; seed.duration = nil; seed.activityCategoryids = nil
        case .categories:
            seed.activityCategoryids = " 999, 11,12 "; seed.categoryId = 777
        case .lifecycle:
            seed.players = "retired:group"; seed.duration = 17
            seed.activityCategoryids = "999"; seed.categoryId = 777
        case nil: break
        }
        c.open(seed: seed)
        return c
    }
    func signOut() { session = nil; coordinator.synchronizeSession(); revision += 1; mount = UUID() }
    func switchAccount() {
        session = try? .init(accountID: 902, namespace: "synthetic-template-author", epoch: revision + 1, authorizationRevision: "member-fixture")
        coordinator.synchronizeSession()
        metadataReader.releaseHeldMetadataRead()
        revision += 1; mount = UUID()
    }
    func reopen() { coordinator.leaveScreen(); coordinator = makeCoordinator(); localSnapshot = ""; mount = UUID() }
    func inspectLocalDraft() {
        // Read actual coordinator state after a user action, never echo the seed or
        // manufacture a success value. This probe cannot change or save the draft.
        struct Snapshot: Encodable {
            let draft: TemplateAuthoringDraft
            let requestCount: Int
            let inspectionSequence: Int
            let locked: Bool
            let state: String
            let accountID: Int?
            let metadataReadInvocations: [String]
            let metadataReadCompletions: [String]
            let metadataPendingReadCount: Int
            let lastRequestPath: String?
            let lastRequestFields: [String: TemplateAuthoringJSON]?
        }
        inspectionSequence += 1
        let lastRequestFields: [String: TemplateAuthoringJSON]?
        if let request = transport.requests.last, case .json(let fields) = request.body { lastRequestFields = fields }
        else { lastRequestFields = nil }
        let value = Snapshot(draft: coordinator.draft, requestCount: transport.requests.count,
                             inspectionSequence: inspectionSequence, locked: coordinator.locked,
                             state: String(describing: coordinator.state), accountID: coordinator.session?.accountID,
                             metadataReadInvocations: metadataReader.metadataReadInvocations,
                             metadataReadCompletions: metadataReader.metadataReadCompletions,
                             metadataPendingReadCount: metadataReader.metadataPendingReadCount,
                             lastRequestPath: transport.requests.last?.path, lastRequestFields: lastRequestFields)
        if let data = try? JSONEncoder().encode(value) { localSnapshot = String(decoding: data, as: UTF8.self) }
        else { localSnapshot = "unavailable" }
    }
}
@MainActor struct TemplateAuthoringFixtureHostView: View {
    @StateObject private var context = TemplateAuthoringFixtureContext()
    var body: some View {
        VStack {
            HStack {
                Button("templateAuthor.fixture.signOut") { context.signOut() }.accessibilityIdentifier("templateAuthor.fixture.signOut")
                Button("templateAuthor.fixture.switch") { context.switchAccount() }.accessibilityIdentifier("templateAuthor.fixture.switch")
                Button("templateAuthor.fixture.reopen") { context.reopen() }.accessibilityIdentifier("templateAuthor.fixture.reopen")
            }.buttonStyle(.bordered).font(.caption)
                // Harness controls must not consume the content viewport in XXXL scenarios.
                // The authored screen below still receives the requested accessibility size.
                .dynamicTypeSize(.large)
            if ProcessInfo.processInfo.arguments.contains("--template-author-local-probe") {
                Button("Inspect synthetic local draft") { context.inspectLocalDraft() }
                    .accessibilityIdentifier("templateAuthor.fixture.localSnapshot")
                    .accessibilityValue(context.localSnapshot)
                    .font(.caption).dynamicTypeSize(.large)
            }
            NavigationStack {
                if ProcessInfo.processInfo.arguments.contains("--template-author-shelf") {
                    TemplateAuthoringMineView(coordinator: context.coordinator, sessionRevision: context.revision, memberDetail: { AnyView(MemberTemplateDetailView(id: $0, reader: context.memberReader)) }, creatorConsent: ProcessInfo.processInfo.arguments.contains("--template-author-creator") ? { AnyView(WorkshopCreatorPendingFixtureView(selection: $0, harness: context.creatorHarness)) } : nil, fixtureSignOut: { context.signOut() })
                } else { TemplateAuthoringView(coordinator: context.coordinator, sessionRevision: context.revision, metadataReader: context.metadataReader,
                    mediaFixtureMode: ProcessInfo.processInfo.arguments.contains("--template-author-media-fixture") ? "generated" : nil) }
            }.id(context.mount)
        }
    }
}
#endif
