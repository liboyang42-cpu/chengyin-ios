import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ChapterThoughtSyncTests: XCTestCase {
    func testOnlyActuallyReachedUnownedThoughtKeysAreClaimed() throws {
        let document: PlayExperienceDocument = try JSONDecoder().decode(PlayExperienceDocument.self, from: Data(ChapterThoughtTestTransport.nodes(claimed: false).utf8))
        let snapshot = try PlaySnapshot(scope: .topic(9), result: document.base)
        let chapter = try XCTUnwrap(document.chapterStories[8])
        XCTAssertEqual(ChapterStoryProjection.claimableThoughtKeys(chapter: chapter, snapshot: snapshot, thoughts: []), ["new"])
        let known: [PlayWireValue] = [.object(["key": .string("new"), "name": .string("Earned")])]
        XCTAssertTrue(ChapterStoryProjection.claimableThoughtKeys(chapter: chapter, snapshot: snapshot, thoughts: known).isEmpty)
    }
    func testClaimOnlyJSONContainsExactScopeAndNoNativeStepOrCipherSubstitute() async throws {
        let transport = ChapterThoughtTestTransport()
        let service = try self.service(transport, enabled: [.thoughtClaims])
        _ = try await service.syncChapterThoughts(scope: .activity(41), topicID: 9, claims: ["new"], sessionID: 50, previousVersion: 1, token: "synthetic-token")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/api/play/journey/thought/sync"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.object?.keys.sorted(), ["activityId", "claim", "topicId"])
        XCTAssertEqual(body["claim"], .array([.string("new")]))
        XCTAssertEqual(body["activityId"], .integer(41)); XCTAssertEqual(body["topicId"], .integer(9))
    }
    func testWrongTopicAndDuplicateClaimsRejectBeforeDispatch() async throws {
        let transport = ChapterThoughtTestTransport(); let service = try self.service(transport, enabled: [.thoughtClaims])
        do { _ = try await service.syncChapterThoughts(scope: .topic(10), topicID: 9, claims: ["new"], sessionID: 50, previousVersion: 1, token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? PlayExperienceError, .invalidAction) }
        do { _ = try await service.syncChapterThoughts(scope: .topic(9), topicID: 9, claims: ["new", "new"], sessionID: 50, previousVersion: 1, token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? PlayExperienceError, .invalidAction) }
        let count = await transport.requests.count; XCTAssertEqual(count, 0)
    }
    @MainActor func testDefaultSeparateGrantNeverSendsClaimAndDoesNotBlockBasePlay() async throws {
        let transport = ChapterThoughtTestTransport(); let model = try self.model(transport, enabled: [.reads])
        await model.load(); await model.claimVisibleThoughts(chapterID: 8)
        XCTAssertEqual(model.thoughtSyncPhase, .disabled); XCTAssertTrue(model.pendingThoughtKeys.isEmpty); XCTAssertTrue(model.canWrite)
        let writes = await transport.requests.filter { $0.httpMethod == "POST" }; XCTAssertTrue(writes.isEmpty)
    }
    @MainActor func testSuccessfulReceiptRequiresFreshReadbackBeforeShowingEarnedThought() async throws {
        let transport = ChapterThoughtTestTransport(); let model = try self.model(transport, enabled: [.reads, .thoughtClaims])
        await model.load(); XCTAssertTrue(model.storyThoughts.isEmpty)
        await model.claimVisibleThoughts(chapterID: 8)
        XCTAssertEqual(model.thoughtSyncPhase, .synced); XCTAssertTrue(model.pendingThoughtKeys.isEmpty)
        XCTAssertEqual(model.storyThoughts.first?["key"], .string("new")); XCTAssertTrue(model.canWrite)
        let requests = await transport.requests; XCTAssertEqual(requests.filter { $0.httpMethod == "GET" }.count, 2)
    }
    @MainActor func testUnknownClaimNeverAutoRetriesAndUnchangedReadbackKeepsLock() async throws {
        let transport = ChapterThoughtTestTransport(); await transport.setUnknown()
        let model = try self.model(transport, enabled: [.reads, .thoughtClaims])
        await model.load(); await model.claimVisibleThoughts(chapterID: 8); await model.claimVisibleThoughts(chapterID: 8)
        XCTAssertEqual(model.thoughtSyncPhase, .needsReadback); XCTAssertFalse(model.canWrite)
        await model.load(); XCTAssertEqual(model.pendingThoughtKeys, ["new"])
        let writes = await transport.requests.filter { $0.httpMethod == "POST" }; XCTAssertEqual(writes.count, 1)
        await transport.setClaimed(); await model.load()
        XCTAssertTrue(model.pendingThoughtKeys.isEmpty); XCTAssertEqual(model.thoughtSyncPhase, .synced)
    }
    private func service(_ transport: any HTTPTransport, enabled: Set<PlayExperienceCapability>) throws -> PlayExperienceService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://thought.test")!), transport: transport, enabled: enabled)
    }
    @MainActor private func model(_ transport: any HTTPTransport, enabled: Set<PlayExperienceCapability>) throws -> PlayExperienceCoordinator {
        let session = try PlayExperienceSession(accountID: 9, epoch: 1, namespace: "synthetic-cn", token: "synthetic-token")
        return .init(scope: .topic(9), service: try service(transport, enabled: enabled), recovery: PlayMemoryCompletionRecovery(),
            pausedStorage: PlayMemoryPausedStorage(), currentSession: { session })
    }
}
private actor ChapterThoughtTestTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var claimed = false
    private var unknown = false
    func setUnknown() { unknown = true }
    func setClaimed() { claimed = true }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.path == "/api/play/journey/thought/sync" {
            if unknown { throw URLError(.timedOut) }
            claimed = true
            return (Data(#"{"code":200,"data":{"routeMode":"LINEAR","sessionId":50,"version":2,"status":"ACTIVE","thoughts":[{"key":"new","name":"Earned"}]}}"#.utf8), 200)
        }
        return (Data(("{\"code\":200,\"data\":" + Self.nodes(claimed: claimed) + "}").utf8), 200)
    }
    nonisolated static func nodes(claimed: Bool) -> String {
        let thoughts = claimed ? #"[{"key":"new","name":"Earned"}]"# : "[]"
        let version = claimed ? 2 : 1
        return #"{"topicId":9,"mode":1,"registered":true,"playable":true,"total":1,"doneCount":0,"nodes":[{"nodeId":1,"chapterId":8,"done":false,"validationMethod":1}],"chapters":[{"chapterId":8,"name":"Synthetic chapter","blocks":[{"type":"thought","thoughtKey":"new"},{"type":"thought","thoughtKey":"new"},{"type":"node","nodeId":1},{"type":"thought","thoughtKey":"future"}]}],"routeState":{"routeMode":"LINEAR","sessionId":50,"status":"ACTIVE","version":\#(version),"thoughts":\#(thoughts)}}"#
    }
}
