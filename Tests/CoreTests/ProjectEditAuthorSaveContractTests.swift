import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// BK-AUTHOR (B02 SOURCE_READY) frozen fixture: member42/topic700 values are sanitized test values.
/// Absent update fields are preserved server-side; native still sends the exact readback values,
/// so a rename-only save never turns stored configuration into a guessed default.
@MainActor final class ProjectEditAuthorSaveContractTests: XCTestCase {
    private let storedConfig: [String: ProjectEditJSON] = [
        "teamMode": .number(2), "teamMaxMembers": .number(3), "selfPlay": .number(1),
        "selfPlayPrice": .number(Decimal(string: "8.00")!), "selfPlayQuota": .number(9),
        "xpBudget": .number(6200), "publishMode": .string("simple")]

    private func detail(_ patch: [String: ProjectEditJSON]) throws -> Data {
        var root = try JSONDecoder().decode([String: ProjectEditJSON].self, from: ProjectEditRemoteFixtures.detail(product: .freeExplore))
        guard var body = root["data"]?.object, var topic = body["topic"]?.object else { throw ProjectEditError.invalidContract }
        topic["id"] = .number(700); topic.merge(patch) { _, new in new }
        body["topic"] = .object(topic); root["data"] = .object(body)
        return try JSONEncoder().encode(root)
    }
    private func snapshot(_ patch: [String: ProjectEditJSON]) throws -> ProjectEditSnapshot {
        try ProjectEditContract.decodeEditDetail(detail(patch), expectedTopicID: 700, owner: .personal)
    }

    func testTopic700RenameOnlySaveKeepsEveryStoredAuthorConfigValue() throws {
        let baseline = try snapshot(storedConfig)
        for (key, value) in storedConfig { XCTAssertEqual(baseline.draft.preserved[key], value, key) }
        var draft = baseline.draft; draft.name = "只改名称"
        let payload = try ProjectEditContract.payload(draft, topicID: 700, scope: baseline.scope, baseline: baseline)
        XCTAssertEqual(payload["id"], .number(700)); XCTAssertEqual(payload["name"], .string("只改名称"))
        for (key, value) in storedConfig { XCTAssertEqual(payload[key], value, "rename-only save changed \(key)") }
        XCTAssertEqual(try ProjectEditStoryContract.path(payload: payload, baseline: baseline), "api/topic/update")
        // Chapters and tickets remain full replacements, never omitted as a generic PATCH.
        XCTAssertEqual(payload["chapters"]?.array?.count, baseline.draft.chapters.count)
        XCTAssertEqual(payload["tickets"]?.array?.count, baseline.draft.tickets.count)
    }

    func testExplicitZeroStillClosesInsteadOfBeingDropped() throws {
        let baseline = try snapshot(storedConfig)
        var draft = baseline.draft
        draft.preserved["teamMode"] = .number(0); draft.preserved["selfPlay"] = .number(0)
        let payload = try ProjectEditContract.payload(draft, topicID: 700, scope: baseline.scope, baseline: baseline)
        XCTAssertEqual(payload["teamMode"], .number(0)); XCTAssertEqual(payload["selfPlay"], .number(0))
        XCTAssertEqual(payload["teamMaxMembers"], .number(3)); XCTAssertEqual(payload["xpBudget"], .number(6200))
    }

    func testUnsupportedStoredTeamModeIsNeverSubmitted() throws {
        var patch = storedConfig; patch["teamMode"] = .number(7)
        let baseline = try snapshot(patch)
        XCTAssertEqual(baseline.draft.preserved["teamMode"], .number(7))
        XCTAssertFalse(ProjectTeamConfiguration.canSubmit(baseline.draft, baseline: baseline))
        XCTAssertThrowsError(try ProjectEditContract.payload(baseline.draft, topicID: 700, scope: baseline.scope, baseline: baseline))
    }

    func testChangedBudgetOrStaleLocalEnvelopeCannotOverwriteReadback() throws {
        let baseline = try snapshot(storedConfig)
        var changed = baseline.draft; changed.preserved["xpBudget"] = .number(3000)
        XCTAssertThrowsError(try ProjectEditContract.payload(changed, topicID: 700, scope: baseline.scope, baseline: baseline))
        var stale = baseline.draft; stale.preserved["teamMode"] = nil
        XCTAssertThrowsError(try ProjectEditContract.payload(stale, topicID: 700, scope: baseline.scope, baseline: baseline))
    }

    func testCreateBodyHasNoBudgetRevisionOrInventedRequestIdentity() throws {
        let payload = try ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(), topicID: nil, scope: .full)
        for key in ["id", "xpBudget", "requestId", "revision", "clientRequestId"] { XCTAssertNil(payload[key], key) }
    }

    // MARK: - Lost responses and failed publish keep the author's work

    private final class Wire: HTTPTransport {
        var createReply: Result<Data, URLError>; var requests: [URLRequest] = []
        init(_ reply: Result<Data, URLError>) { createReply = reply }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path == "/api/publish/home" { return (Data(#"{"code":200,"data":{"permission":{"canProPublish":true},"quota":{"themesRemaining":2}}}"#.utf8), 200) }
            return (try createReply.get(), 200)
        }
        var creates: Int { requests.filter { $0.url?.path == "/api/topic/v2/create" }.count }
    }
    private func harness(_ reply: Result<Data, URLError>) throws -> (ProjectEditSession, ProjectEditLocalStore, ProjectEditHTTPService, Wire) {
        let session = try ProjectEditSession(accountID: 42, epoch: 1, storageNamespace: "author-save-test")
        let store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let credentials = try ProjectEditCredentials(session: session, token: "synthetic-only-token")
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.storageNamespace, accountID: session.accountID, paths: [ProjectEditStoryContract.createPath])
        let wire = Wire(reply)
        let service = ProjectEditHTTPService(configuration: configuration, transport: wire, owner: .personal, approval: approval, store: store, currentCredentials: { credentials })
        return (session, store, service, wire)
    }

    func testFirstCreateLostResponseStaysUnknownAcrossReopenAndIsNeverResent() async throws {
        let (session, store, service, wire) = try harness(.failure(URLError(.networkConnectionLost)))
        var draft = ProjectEditSyntheticFixtures.draft(); draft.name = "Unknown first create"
        let co = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: store, currentSession: { session })
        await co.load(); co.prepare(draft); await co.confirm(try XCTUnwrap(co.confirmation))
        XCTAssertEqual(co.state, .unknown); XCTAssertTrue(co.isLocked); XCTAssertEqual(wire.creates, 1)
        let pending = try XCTUnwrap(co.pending)
        XCTAssertNil(pending.completedTopicID); XCTAssertEqual(try store.pending(session: session, identity: pending.identity)?.dispatchStarted, true)

        // A later success reply cannot be used: no create requestId exists to match it by name.
        wire.createReply = .success(Data(#"{"code":200,"data":{"topicId":7001,"auditTaskId":1,"reviewState":"PENDING","published":false,"bundledTemplateIds":[]}}"#.utf8))
        let reopened = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: store, currentSession: { session })
        await reopened.load()
        XCTAssertEqual(reopened.state, .unknown); XCTAssertTrue(reopened.isLocked); XCTAssertNil(reopened.restoredDraft())
        reopened.prepare(draft); XCTAssertNil(reopened.confirmation)
        let resend = await service.submit(try XCTUnwrap(reopened.pending), session: session)
        XCTAssertEqual(resend, .unknown); XCTAssertEqual(wire.creates, 1)
        let receipt = try await service.terminalReceipt(operationID: pending.operationID, session: session)
        XCTAssertNil(receipt)
    }

    func testRejectedPublishClearsOnlyTheIntentAndKeepsTheEditedDraft() async throws {
        let (session, store, service, wire) = try harness(.success(Data(#"{"code":500,"msg":"内容需修改"}"#.utf8)))
        var draft = ProjectEditSyntheticFixtures.draft(); draft.name = "Edited before failed publish"
        let co = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: store, currentSession: { session })
        await co.load(); co.prepare(draft); await co.confirm(try XCTUnwrap(co.confirmation))
        XCTAssertEqual(co.state, .rejected); XCTAssertNil(co.pending); XCTAssertEqual(wire.creates, 1)

        let reopened = ProjectEditCoordinator(initial: .init(draft: ProjectEditSyntheticFixtures.draft()), service: service, store: store, currentSession: { session })
        await reopened.load()
        XCTAssertFalse(reopened.isLocked)
        XCTAssertEqual(reopened.restoredDraft()?.name, "Edited before failed publish")
    }
}
