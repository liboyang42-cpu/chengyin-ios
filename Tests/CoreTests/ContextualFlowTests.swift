import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ContextualFlowTests: XCTestCase {
    private func config() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.com/fixture/")!) }
    private func session(epoch: UInt64 = 1) throws -> ContextualReviewSession { try .init(accountID: 1, epoch: epoch, realm: "https://example.com/fixture/", token: "fixture-token") }
    func testReviewOwnerDomainsAndValidation() throws {
        let draft = ContextualReviewDraft(rating: 4, contents: " Experience ")
        XCTAssertEqual(try draft.fields(target: .topic(7))["owner_type"], "1")
        XCTAssertEqual(try draft.fields(target: .activity(7))["owner_type"], "2")
        XCTAssertEqual(try draft.fields(target: .topic(7))["contents"], "Experience")
        XCTAssertFalse(ContextualReviewDraft(rating: 0, contents: "A").isValid)
        XCTAssertFalse(ContextualReviewDraft(rating: 6, contents: "A").isValid)
        XCTAssertFalse(ContextualReviewDraft(rating: 1, contents: "  ").isValid)
        XCTAssertFalse(ContextualReviewDraft(rating: 1, contents: String(repeating: "x", count: 501)).isValid)
        XCTAssertThrowsError(try draft.fields(target: .topic(0)))
    }
    func testDormantWriterCannotDispatch() async throws {
        let transport = ProfileTestTransport([]), session = try session()
        let writer = ContextualReviewHTTPWriter(configuration: try config(), transport: transport, currentSession: { session })
        do { try await writer.submit(.init(rating: 5, contents: "Good"), target: .topic(7), session: session); XCTFail() }
        catch { XCTAssertEqual(error as? ContextualReviewFailure, .notSent) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testExactReviewRequestAndRepeatedAcknowledgmentLock() async throws {
        let transport = ProfileTestTransport([.json(#"{"code":200}"#)]), session = try session()
        let writer = ContextualReviewHTTPWriter(configuration: try config(), transport: transport, enabled: true, currentSession: { session })
        let owner = ContextualReviewCoordinator(target: .activity(7), writer: writer)
        let draft = ContextualReviewDraft(rating: 3, contents: "Good")
        await owner.submit(draft, expected: session); await owner.submit(draft, expected: session)
        XCTAssertEqual(owner.state, .acknowledged); XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fixture/api/comment/add")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        for (key, value) in try draft.fields(target: .activity(7)) { XCTAssertTrue(body.contains("name=\"\(key)\"\r\n\r\n\(value)\r\n")) }
    }
    func testUnknownReviewLocksAcrossSameAccountEpochAndHostReopen() async throws {
        let transport = ProfileTestTransport([.failure(URLError(.timedOut))])
        var current = try session()
        let writer = ContextualReviewHTTPWriter(configuration: try config(), transport: transport, enabled: true, currentSession: { current })
        let host = ContextualReviewHost(writer: writer), target = ContextualReviewTarget.topic(7)
        let draft = ContextualReviewDraft(rating: 2, contents: "Experience")
        await host.coordinator(target).submit(draft, expected: current)
        current = try session(epoch: 2)
        XCTAssertEqual(host.coordinator(target).state, .unknown)
        await host.coordinator(target).submit(draft, expected: current)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(host.coordinator(.activity(7)).state, .idle)
    }
    func testAmbiguousHTTPAndMalformedResponsesRemainLocked() async throws {
        for reply in [ProfileTestReply.json(#"{"code":500}"#, status: 408), .json(#"{"code":400}"#, status: 499),
                      .json(#"{"code":200}"#, status: 500), .json(#"{"code":400}"#, status: 503),
                      .json(#"{"code":200}"#, status: 403), .json("not-json", status: 200)] {
            let transport = ProfileTestTransport([reply]), session = try session()
            let writer = ContextualReviewHTTPWriter(configuration: try config(), transport: transport, enabled: true, currentSession: { session })
            let owner = ContextualReviewCoordinator(target: .topic(7), writer: writer)
            let draft = ContextualReviewDraft(rating: 4, contents: "Experience")
            await owner.submit(draft, expected: session); await owner.submit(draft, expected: session)
            XCTAssertEqual(owner.state, .unknown); XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testDeliveredAjaxRejectionIsDefinitive() async throws {
        let transport = ProfileTestTransport([.json(#"{"code":500}"#)]), session = try session()
        let writer = ContextualReviewHTTPWriter(configuration: try config(), transport: transport, enabled: true, currentSession: { session })
        let owner = ContextualReviewCoordinator(target: .topic(7), writer: writer)
        await owner.submit(.init(rating: 2, contents: "Experience"), expected: session)
        XCTAssertEqual(owner.state, .rejected); XCTAssertTrue(owner.canSubmit)
    }
    func testPostDispatchSessionChangeKeepsUnknownLock() async throws {
        let initial = try session(), replacement = try session(epoch: 2)
        var current = initial
        let transport = ContextualChangingTransport { current = replacement }
        let writer = ContextualReviewHTTPWriter(configuration: try config(), transport: transport, enabled: true, currentSession: { current })
        let owner = ContextualReviewCoordinator(target: .topic(7), writer: writer)
        await owner.submit(.init(rating: 3, contents: "Experience"), expected: initial)
        XCTAssertEqual(owner.state, .unknown); XCTAssertFalse(owner.canSubmit)
        XCTAssertEqual(transport.calls, 1)
    }
    func testCreatedParticipantReturnsAuthoritativeIDAndRequestKey() async throws {
        let transport = ProfileTestTransport([.json(#"{"code":200,"data":{"id":42,"fullName":"Fixture Person","mobilePhone":"13800000000"}}"#)])
        let service = ParticipantService(configuration: try config(), transport: transport)
        let requestID = UUID()
        let row = try await service.performReturningParticipant(.save(participantDraftFixture()), requestID: requestID, token: "fixture-token")
        XCTAssertEqual(row?.id, 42)
        let body = String(decoding: transport.requests[0].httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"requestId\"\r\n\r\n\(requestID.uuidString.lowercased())\r\n"))
    }
    func testLegacyCreateAcknowledgmentNeverInventsID() async throws {
        let transport = ProfileTestTransport([.json(#"{"code":200}"#)])
        let service = ParticipantService(configuration: try config(), transport: transport)
        let row = try await service.performReturningParticipant(.save(participantDraftFixture()), requestID: UUID(), token: "fixture-token")
        XCTAssertNil(row)
    }
    func testPreferencesPreserveUneditedWireOrReplaceExplicitSelection() throws {
        let snapshot = try JSONDecoder().decode(ProfileEditSnapshot.self, from: Data(#"{"id":1,"nickname":"Name","introduction":"","avatar":"avatar","wechat":"qr","casePics":"a;;b","tagIds":" 7,4 "}"#.utf8))
        XCTAssertEqual(try ProfileEditPayload(draft: snapshot.draft, preserving: snapshot).tagIds, " 7,4 ")
        var draft = snapshot.draft; draft.routePreferenceIDs = [9, 7]
        let value = try ProfileEditPayload(draft: draft, preserving: snapshot)
        XCTAssertEqual(value.tagIds, "9,7"); XCTAssertEqual(value.casePics, "a;;b")
        draft.routePreferenceIDs = []; XCTAssertEqual(try ProfileEditPayload(draft: draft, preserving: snapshot).tagIds, "")
        draft.routePreferenceIDs = [7, 7]; XCTAssertFalse(draft.isValid)
        draft.routePreferenceIDs = [0]; XCTAssertFalse(draft.isValid)
    }
}

@MainActor private final class ContextualChangingTransport: HTTPTransport {
    let change: () -> Void
    var calls = 0
    init(change: @escaping () -> Void) { self.change = change }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1; change(); return (Data(#"{"code":200}"#.utf8), 200)
    }
}
