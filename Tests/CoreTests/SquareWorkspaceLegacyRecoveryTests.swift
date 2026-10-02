import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class LegacyWorkspaceHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [Data] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.timedOut) }
        return (responses.removeFirst(), 200)
    }
}
@MainActor final class SquareWorkspaceLegacyRecoveryTests: XCTestCase {
    private func envelope(_ data: Data = SquareWorkspaceFixtures.legacyPost) -> Data {
        Data("{\"code\":200,\"data\":\(String(data: data, encoding: .utf8)!)}".utf8)
    }
    private func service(_ transport: LegacyWorkspaceHTTP) throws -> SquareWorkspaceService {
        .init(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: transport)
    }
    private func session() throws -> SquareWorkspaceSession { try .init(accountID: 81, namespace: "legacy-tests", epoch: 1) }
    private func coordinator(_ transport: LegacyWorkspaceHTTP, store: SquareWorkspaceStore? = nil) throws -> SquareWorkspaceCoordinator {
        let identity = try session(); var grants = SquareWorkspaceGrants(); grants.live = true
        return .init(session: identity, store: store ?? .init(storage: SquareWorkspaceMemoryStorage()), service: try service(transport), grants: grants, currentSession: { identity }, token: { "fixture-token" })
    }
    private func legacyData(_ replacements: [String: Any]) throws -> Data {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: SquareWorkspaceFixtures.legacyPost) as? [String: Any])
        value.merge(replacements) { _, new in new }
        return try JSONSerialization.data(withJSONObject: value)
    }
    private func oldEntry(lane: SquareWorkspaceLane, pending: Bool = false) throws -> (SquareWorkspaceStore, SquareWorkspaceLocalEntry) {
        var draft = SquareWorkspaceFixtures.draft(); draft.postID = 701
        draft.expectedVersion = 3; draft.sourceLifecycle = "DRAFT"; draft.body = "My unsent changes"
        let entry = SquareWorkspaceLocalEntry(draft: draft, lane: lane, pending: pending, receipt: nil, updatedAt: Date(timeIntervalSince1970: 10))
        var row = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        var saved = try XCTUnwrap(row["draft"] as? [String: Any])
        for key in ["sourceLane", "legacySourceDigest"] { saved.removeValue(forKey: key) }; row["draft"] = saved
        let identity = try session(), storage = SquareWorkspaceMemoryStorage()
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "ownerKey": identity.ownerKey, "entries": [row]])
        try storage.write(data, key: "square.workspace.v1." + Data(identity.ownerKey.utf8).base64EncodedString())
        let store = SquareWorkspaceStore(storage: storage)
        return (store, try XCTUnwrap(try store.entries(session: identity).first))
    }
    func testRealLegacyShapeHydratesWithoutInventingVersionOrLifecycle() throws {
        let post = try SquareWorkspacePost(data: SquareWorkspaceFixtures.legacyPost, lane: .legacy)
        let draft = try post.editableDraft(lane: .legacy)
        XCTAssertNil(post.version); XCTAssertNil(post.lifecycle); XCTAssertNil(draft.expectedVersion); XCTAssertNil(draft.sourceLifecycle)
        XCTAssertEqual(draft.sourceLane, .legacy); XCTAssertEqual(draft.legacySourceDigest, post.sourceDigest)
        XCTAssertEqual(draft.body, "Synthetic legacy post"); XCTAssertEqual(draft.media.map(\.objectKey), ["one.jpg", "two.jpg"])
        XCTAssertEqual(draft.reference, .init(type: "ACTIVITY", id: 901))
        XCTAssertNoThrow(try draft.validate(publishing: true, lane: .legacy))
        XCTAssertThrowsError(try post.editableDraft(lane: .communityV1))
        XCTAssertThrowsError(try draft.validate(publishing: true, lane: .communityV1))
    }
    func testV1DecoderStillRejectsLegacyMissingNegativeAndEmptyVersionState() throws {
        XCTAssertThrowsError(try SquareWorkspacePost(data: SquareWorkspaceFixtures.legacyPost))
        for data in [Data(#"{"id":701,"authorId":81,"lifecycle":"DRAFT"}"#.utf8), Data(#"{"id":701,"authorId":81,"version":-1,"lifecycle":"DRAFT"}"#.utf8), Data(#"{"id":701,"authorId":81,"version":3,"lifecycle":""}"#.utf8)] {
            XCTAssertThrowsError(try SquareWorkspacePost(data: data))
        }
        XCTAssertThrowsError(try SquareWorkspacePost(data: SquareWorkspaceFixtures.post, lane: .legacy))
        XCTAssertThrowsError(try SquareWorkspacePost(data: legacyData(["status": 2]), lane: .legacy))
        XCTAssertThrowsError(try SquareWorkspacePost(data: legacyData(["memberId": 0]), lane: .legacy))
    }
    func testLegacyEditHydratesPreflightsAndReadsBackOnlyItsNamespace() async throws {
        let http = LegacyWorkspaceHTTP(), model = try coordinator(http)
        http.responses = [envelope(), envelope(), envelope(), Data(#"{"code":200}"#.utf8), envelope(try legacyData(["contents": "Edited facts"]))]
        var draft = try await model.editableDraft(postID: 701, lane: .legacy); draft.body = "Edited facts"
        let review = try await model.prepare(draft, lane: .legacy)
        try await model.confirm(review, unchangedDraft: draft, acceptCurrentGuideline: false)
        XCTAssertEqual(http.requests.map { $0.url!.path }, ["/api/creativesquare/info", "/api/creativesquare/info", "/api/creativesquare/info", "/api/creativesquare/action", "/api/creativesquare/info"])
        XCTAssertTrue(http.requests.allSatisfy { $0.httpMethod == "POST" })
        let body = String(data: http.requests[3].httpBody!, encoding: .utf8)!
        XCTAssertFalse(body.contains("expectedVersion")); XCTAssertFalse(body.contains("lifecycle"))
        XCTAssertEqual(model.lastPost?.lane, .legacy); XCTAssertNil(model.lastPost?.version)
        XCTAssertEqual(try model.lastPost?.editableDraft(lane: .legacy).body, "Edited facts")
    }
    func testChangedLegacySourceCannotPrepareOrConfirmAndMakesNoWrite() async throws {
        let http = LegacyWorkspaceHTTP(), model = try coordinator(http)
        http.responses = [envelope(), envelope(try legacyData(["contents": "Someone changed the source"]))]
        let draft = try await model.editableDraft(postID: 701, lane: .legacy)
        do { _ = try await model.prepare(draft, lane: .legacy); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .staleReview) }
        http.responses = [envelope(), envelope(try legacyData(["contents": "Changed after review"]))]
        let review = try await model.prepare(draft, lane: .legacy)
        do { try await model.confirm(review, unchangedDraft: draft, acceptCurrentGuideline: false); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .staleReview) }
        XCTAssertFalse(http.requests.contains { $0.url!.path.hasSuffix("/action") })
    }
    func testLegacyCannotPublishOrWithdrawThroughV1AndMakesNoRequest() async throws {
        let http = LegacyWorkspaceHTTP(), api = try service(http)
        let post = try SquareWorkspacePost(data: SquareWorkspaceFixtures.legacyPost, lane: .legacy)
        do { _ = try await api.publish(post: post, workflowID: "fixture-workflow", token: "fixture"); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .invalid) }
        do { try await api.withdrawLocation(post: post, requestID: "location-withdraw-fixture", token: "fixture"); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .invalid) }
        do { try await coordinator(http).withdrawLocation(reviewed: post, explicitIntent: true); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .invalid) }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testStoredOldFormatDraftRecoversOnlyPersistedLaneAndPreservesUserEdits() async throws {
        for lane in SquareWorkspaceLane.allCases {
            let (store, entry) = try oldEntry(lane: lane)
            XCTAssertNil(entry.draft.sourceLane)
            let http = LegacyWorkspaceHTTP(); http.responses = [envelope(lane == .legacy ? SquareWorkspaceFixtures.legacyPost : SquareWorkspaceFixtures.post)]
            let model = try coordinator(http, store: store)
            let resumed = try await model.resume(entry)
            XCTAssertEqual(resumed.sourceLane, lane); XCTAssertEqual(resumed.body, entry.draft.body)
            XCTAssertEqual(resumed.workflowID, entry.draft.workflowID); XCTAssertEqual(resumed.media, entry.draft.media)
            XCTAssertEqual(resumed.reference, entry.draft.reference); XCTAssertEqual(resumed.address, entry.draft.address)
            XCTAssertEqual(http.requests.first?.url?.path, lane == .legacy ? "/api/creativesquare/info" : "/api/v1/community/posts/701")
            XCTAssertEqual(try store.entries(session: session()).first?.draft, resumed)
            XCTAssertNoThrow(try resumed.validate(publishing: true, lane: lane))
        }
    }
    func testOldDraftForeignOwnerOrWrongShapeNeverFallsBackAndPreservesStoredBytes() async throws {
        for data in [try legacyData(["memberId": 82]), SquareWorkspaceFixtures.post] {
            let (store, entry) = try oldEntry(lane: .legacy)
            let http = LegacyWorkspaceHTTP(); http.responses = [envelope(data)]
            do { _ = try await coordinator(http, store: store).resume(entry); XCTFail() } catch {}
            XCTAssertEqual(try store.entries(session: session()).first, entry)
            XCTAssertEqual(http.requests.count, 1); XCTAssertEqual(http.requests.first?.url?.path, "/api/creativesquare/info")
        }
    }
    func testPendingOldDraftCannotBeReboundOrUnlockItsWorkflow() async throws {
        let (store, entry) = try oldEntry(lane: .legacy, pending: true), http = LegacyWorkspaceHTTP()
        do { _ = try await coordinator(http, store: store).resume(entry); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .pending) }
        XCTAssertEqual(try store.entries(session: session()).first, entry); XCTAssertTrue(http.requests.isEmpty)
    }
    func testChangedV1SourceCannotSilentlyRebaseOldEdit() async throws {
        let (store, entry) = try oldEntry(lane: .communityV1), http = LegacyWorkspaceHTTP()
        http.responses = [envelope(SquareReportFixtures.postData(version: 4))]
        do { _ = try await coordinator(http, store: store).resume(entry); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .staleReview) }
        XCTAssertEqual(try store.entries(session: session()).first, entry); XCTAssertEqual(http.requests.count, 1)
    }
}
