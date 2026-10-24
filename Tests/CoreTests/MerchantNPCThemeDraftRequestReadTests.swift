import XCTest
@testable import QuestifyCore

@MainActor final class MerchantNPCThemeDraftRequestReadTests: XCTestCase {
    private let heldRequest = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
    private let otherRequest = "11111111-1111-4111-8111-111111111111"
    private let scope = MerchantNPCScope(
        accountID: 901, namespace: "synthetic.invalid", epoch: UUID(),
        merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID()
    )

    private final class ScriptedTransport: HTTPTransport {
        var sent: [URLRequest] = []
        var result: (Data, Int) = (Data(), 200)
        var failure: Error?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            sent.append(request)
            if let failure { throw failure }
            return result
        }
    }

    private final class RecordingPublisher: MerchantNPCOriginalReviewPublishing {
        var published = 0
        func submitForOriginalReview(_ draft: MerchantNPCKnowledgeDraft, requestID: UUID, scope: MerchantNPCScope) async throws -> MerchantNPCOriginalReviewTicket {
            throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority)
        }
        func publishApproved(_ ticket: MerchantNPCOriginalReviewTicket, scope: MerchantNPCScope) async throws -> MerchantNPCPublishedRevision {
            published += 1
            throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeDraftHTTP)
        }
    }

    private func character() -> MerchantStoreCharacter {
        var character = MerchantStoreCharacter()
        character.name = "Old"
        character.avatar = "px1:p01"
        character.greeting = "Hi"
        character.persona = "Calm"
        character.knowledge = "Old facts"
        return character
    }

    private func field(_ field: MerchantNPCTextField, from character: MerchantStoreCharacter, value: String) throws -> MerchantNPCFieldDraft {
        var draft = try XCTUnwrap(MerchantNPCFieldDraft(field: field, source: .character(character)))
        draft.value = value
        return draft
    }

    private func drafted(_ publisher: RecordingPublisher) throws -> MerchantNPCKnowledgeAuthorFlow {
        let flow = MerchantNPCKnowledgeAuthorFlow(scope: scope, publisher: publisher, currentScope: { self.scope })
        let sourceCharacter = character()
        _ = try flow.supply(
            name: field(.name, from: sourceCharacter, value: "Guide"),
            greeting: field(.greeting, from: sourceCharacter, value: "Welcome"),
            persona: field(.persona, from: sourceCharacter, value: "Kind"),
            knowledge: field(.knowledge, from: sourceCharacter, value: "Local facts"),
            source: .character(sourceCharacter)
        )
        try flow.ingestAsAIDraft()
        return flow
    }

    private func caller(transport: ScriptedTransport, memberID: Int64 = 7, token: String? = "member-token") throws -> MerchantNPCThemeDraftRequestRead {
        MerchantNPCThemeDraftRequestRead(
            configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!),
            transport: transport,
            memberID: { memberID },
            token: { token }
        )
    }

    private func envelope(requestID: String, state: String, memberID: Int64? = 7, result: Bool = false) throws -> Data {
        var data: [String: Any] = ["requestId": requestID, "state": state]
        if let memberID { data["memberId"] = Int(memberID) }
        if result { data["result"] = ["traceId": "t1", "draft": ["title": "第一份"]] }
        return try JSONSerialization.data(withJSONObject: ["code": 200, "msg": "操作成功", "data": data])
    }

    private func assertGet(_ request: URLRequest, requestID: String) {
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "member-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(parts?.path, "/api/ai/theme/draft/request")
        XCTAssertEqual(parts?.queryItems, [URLQueryItem(name: "requestId", value: requestID)])
        XCTAssertNotEqual(parts?.path, "/api/ai/theme/draft")
    }

    func testMatchingRequestAndMemberPassesHitAndDoesNotPublish() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        transport.result = (try envelope(requestID: heldRequest, state: "SUCCEEDED", memberID: nil, result: true), 200)
        let fact = try await caller(transport: transport).readAndRecover(flow)
        XCTAssertEqual(fact?.requestID, heldRequest)
        XCTAssertEqual(fact?.state, "SUCCEEDED")
        XCTAssertEqual(transport.sent.count, 1)
        assertGet(transport.sent[0], requestID: heldRequest)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
    }

    func testNotFoundLeavesPhaseUnchanged() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: "  \(heldRequest)  "))
        transport.result = (try envelope(requestID: heldRequest, state: "NOT_FOUND", memberID: 7), 200)
        let fact = try await caller(transport: transport).readAndRecover(flow)
        XCTAssertNil(fact)
        assertGet(transport.sent[0], requestID: heldRequest)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
    }

    func testMismatchedRequestIdDoesNotPassHit() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        transport.result = (try envelope(requestID: otherRequest, state: "SUCCEEDED", memberID: 7), 200)
        let fact = try await caller(transport: transport).readAndRecover(flow)
        XCTAssertNil(fact)
        assertGet(transport.sent[0], requestID: heldRequest)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
    }

    func testReturnedMemberIdMismatchDoesNotPassHit() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        transport.result = (try envelope(requestID: heldRequest, state: "SUCCEEDED", memberID: 8), 200)
        let fact = try await caller(transport: transport).readAndRecover(flow)
        XCTAssertNil(fact)
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
    }

    func testMismatchedMemberDoesNotSendOrPublish() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        let fact = try await caller(transport: transport, memberID: 8).readAndRecover(flow)
        XCTAssertNil(fact)
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
    }

    func testInvalidRequestIdIsRejectedBeforeRead() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher)
        XCTAssertFalse(flow.holdThemeDraftRequest(memberID: 7, requestID: "x"))
        XCTAssertFalse(MerchantNPCKnowledgeAuthorFlow.isThemeDraftRequestID("x"))
        XCTAssertNil(flow.heldThemeDraftRequestID)
        let fact = try await caller(transport: transport).readAndRecover(flow)
        XCTAssertNil(fact)
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
    }

    func testMissingHeldRequestDoesNotInventOne() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher)
        XCTAssertNil(flow.heldThemeDraftRequestID)
        let fact = try await caller(transport: transport).readAndRecover(flow)
        XCTAssertNil(fact)
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
        XCTAssertFalse(flow.holdThemeDraftRequest(memberID: 0, requestID: heldRequest))
        XCTAssertNil(try await caller(transport: transport).readAndRecover(flow))
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testReadFailureLeavesPhaseUnchanged() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        transport.failure = APIError.malformedResponse
        do {
            _ = try await caller(transport: transport).readAndRecover(flow)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? APIError, .malformedResponse)
        }
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
    }
}
