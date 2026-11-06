import XCTest
@testable import QuestifyCore

@MainActor final class MerchantNPCOriginalDraftWriterTests: XCTestCase {
    private let heldRequest = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
    private let returnedRequest = "22222222-2222-4222-8222-222222222222"
    private let scope = MerchantNPCScope(
        accountID: 901, namespace: "synthetic.invalid", epoch: UUID(),
        merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID()
    )

    private final class ScriptedTransport: HTTPTransport {
        var sent: [URLRequest] = []
        var results: [(Data, Int)] = []
        var failureAt: Int?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let index = sent.count
            sent.append(request)
            if failureAt == index { throw APIError.malformedResponse }
            guard index < results.count else { return (Data(), 200) }
            return results[index]
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

    private func character(knowledge: String = "Local facts") -> MerchantStoreCharacter {
        var character = MerchantStoreCharacter()
        character.name = "Old"
        character.avatar = "px1:p01"
        character.greeting = "Hi"
        character.persona = "Calm"
        character.knowledge = knowledge
        return character
    }

    private func field(_ field: MerchantNPCTextField, from character: MerchantStoreCharacter, value: String) throws -> MerchantNPCFieldDraft {
        var draft = try XCTUnwrap(MerchantNPCFieldDraft(field: field, source: .character(character)))
        draft.value = value
        return draft
    }

    private func drafted(publisher: (any MerchantNPCOriginalReviewPublishing)? = nil,
                         knowledge: String = "Local facts") throws -> MerchantNPCKnowledgeAuthorFlow {
        let flow = MerchantNPCKnowledgeAuthorFlow(scope: scope, publisher: publisher, currentScope: { self.scope })
        let sourceCharacter = character(knowledge: knowledge)
        _ = try flow.supply(
            name: field(.name, from: sourceCharacter, value: "Guide"),
            greeting: field(.greeting, from: sourceCharacter, value: "Welcome"),
            persona: field(.persona, from: sourceCharacter, value: "Kind"),
            knowledge: field(.knowledge, from: sourceCharacter, value: knowledge),
            source: .character(sourceCharacter)
        )
        try flow.ingestAsAIDraft()
        return flow
    }

    private func writer(transport: ScriptedTransport, memberID: Int64 = 7, token: String? = "member-token") throws -> MerchantNPCOriginalDraftWriter {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let reader = MerchantNPCThemeDraftRequestRead(
            configuration: configuration,
            transport: transport,
            memberID: { memberID },
            token: { token }
        )
        return MerchantNPCOriginalDraftWriter(
            configuration: configuration,
            transport: transport,
            reader: reader,
            memberID: { memberID },
            token: { token }
        )
    }

    private func submitBody(requestID: String, requestState: String, code: Int = 200,
                            errorCode: String? = nil, nestedOnly: Bool = false) throws -> Data {
        var object: [String: Any] = [
            "code": code,
            "msg": "操作成功",
            "data": ["traceId": "t1", "draft": ["title": "第一份"]] as [String: Any]
        ]
        if !nestedOnly {
            object["requestId"] = requestID
            object["requestState"] = requestState
        } else {
            object["data"] = ["requestId": requestID, "draft": ["title": "第一份"]]
            object["requestState"] = requestState
        }
        if let errorCode { object["errorCode"] = errorCode }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func readBody(requestID: String, state: String) throws -> Data {
        let data: [String: Any] = ["requestId": requestID, "state": state, "memberId": 7]
        return try JSONSerialization.data(withJSONObject: ["code": 200, "msg": "操作成功", "data": data])
    }

    private func assertPost(_ request: URLRequest, held: String, knowledge: String) throws {
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "member-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Bearer"))
        let parts = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        XCTAssertEqual(parts?.path, "/api/ai/theme/draft")
        XCTAssertNil(parts?.queryItems)
        XCTAssertNotEqual(parts?.path, "/api/ai/theme/draft/request")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(Set(body.keys), ["requestId", "idea"])
        XCTAssertNil(body["name"])
        XCTAssertNil(body["greeting"])
        XCTAssertNil(body["persona"])
        XCTAssertNil(body["knowledge"])
        XCTAssertNil(body["productType"])
        XCTAssertNil(body["existingNodeNames"])
        XCTAssertEqual(body["requestId"], held)
        let idea = "name: Guide\ngreeting: Welcome\npersona: Kind\nknowledge: \(knowledge)"
        XCTAssertEqual(body["idea"], idea)
        XCTAssertEqual(idea.split(separator: "\n", omittingEmptySubsequences: false).count, 4)
    }

    private func assertGet(_ request: URLRequest, requestID: String) {
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(parts?.path, "/api/ai/theme/draft/request")
        XCTAssertEqual(parts?.queryItems, [URLQueryItem(name: "requestId", value: requestID)])
    }

    func testAcceptedResponseSubmitsHeldRequestAndFourFieldsThenReadsReturnedID() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let knowledge = String(repeating: "a", count: 601)
        let flow = try drafted(publisher: publisher, knowledge: knowledge)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        XCTAssertFalse(flow.gate.draft.faq.contains { $0.answer == knowledge })
        transport.results = [
            (try submitBody(requestID: returnedRequest, requestState: "SUCCEEDED"), 200),
            (try readBody(requestID: returnedRequest, state: "SUCCEEDED"), 200)
        ]
        let fact = try await writer(transport: transport).submitHeldDraftThenRead(flow)
        XCTAssertEqual(fact?.requestID, returnedRequest)
        XCTAssertEqual(fact?.state, "SUCCEEDED")
        XCTAssertEqual(transport.sent.count, 2)
        try assertPost(transport.sent[0], held: heldRequest, knowledge: knowledge)
        assertGet(transport.sent[1], requestID: returnedRequest)
        XCTAssertNotEqual(transport.sent[1].url?.query, "requestId=\(heldRequest)")
        XCTAssertEqual(flow.heldThemeDraftRequestID, returnedRequest)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
        XCTAssertNil(flow.gate.published)
        XCTAssertNotEqual(flow.gate.phase, .published)
        XCTAssertEqual(publisher.published, 0)
    }

    func testNonAcceptanceDoesNotReadOrReplaceHeldID() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher: publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        transport.failureAt = 1
        transport.results = [
            (try submitBody(requestID: returnedRequest, requestState: "PROCESSING", code: 409, errorCode: "AI_DRAFT_IN_PROGRESS"), 200),
            (try readBody(requestID: returnedRequest, state: "SUCCEEDED"), 200)
        ]
        let fact = try await writer(transport: transport).submitHeldDraftThenRead(flow)
        XCTAssertNil(fact)
        XCTAssertEqual(transport.sent.count, 1)
        try assertPost(transport.sent[0], held: heldRequest, knowledge: "Local facts")
        XCTAssertEqual(flow.heldThemeDraftRequestID, heldRequest)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
    }

    func testMissingReturnedRequestIDDoesNotReadHeldOrMintedID() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher: publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        let legacy = try JSONSerialization.data(withJSONObject: [
            "code": 200, "msg": "操作成功", "data": ["traceId": "t1", "draft": ["title": "第一份"]]
        ])
        transport.results = [(legacy, 200)]
        let fact = try await writer(transport: transport).submitHeldDraftThenRead(flow)
        XCTAssertNil(fact)
        XCTAssertEqual(transport.sent.count, 1)
        try assertPost(transport.sent[0], held: heldRequest, knowledge: "Local facts")
        XCTAssertEqual(flow.heldThemeDraftRequestID, heldRequest)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
    }

    func testInvalidReturnedRequestIDDoesNotFallBackToHeldID() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher: publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        transport.results = [(try submitBody(requestID: "hand-filled", requestState: "SUCCEEDED"), 200)]
        let fact = try await writer(transport: transport).submitHeldDraftThenRead(flow)
        XCTAssertNil(fact)
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(flow.heldThemeDraftRequestID, heldRequest)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
    }

    func testNestedRequestIDIsNotTheSubmitResponseID() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher: publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        transport.results = [(try submitBody(requestID: returnedRequest, requestState: "SUCCEEDED", nestedOnly: true), 200)]
        let fact = try await writer(transport: transport).submitHeldDraftThenRead(flow)
        XCTAssertNil(fact)
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(flow.heldThemeDraftRequestID, heldRequest)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
    }

    func testMissingHeldRequestDoesNotSubmit() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher: publisher)
        XCTAssertNil(flow.heldThemeDraftRequestID)
        let fact = try await writer(transport: transport).submitHeldDraftThenRead(flow)
        XCTAssertNil(fact)
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
    }

    func testSucceededSubmitWithoutReadHitDoesNotInventReceipt() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher: publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        transport.results = [
            (try submitBody(requestID: returnedRequest, requestState: "SUCCEEDED"), 200),
            (try readBody(requestID: returnedRequest, state: "NOT_FOUND"), 200)
        ]
        let fact = try await writer(transport: transport).submitHeldDraftThenRead(flow)
        XCTAssertNil(fact)
        XCTAssertEqual(transport.sent.count, 2)
        assertGet(transport.sent[1], requestID: returnedRequest)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
    }

    func testMissingPublisherDoesNotPublish() async throws {
        let missingTransport = ScriptedTransport()
        let missing = try drafted(publisher: nil)
        XCTAssertTrue(missing.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        missingTransport.results = [
            (try submitBody(requestID: returnedRequest, requestState: "SUCCEEDED"), 200),
            (try readBody(requestID: returnedRequest, state: "SUCCEEDED"), 200)
        ]
        let missingFact = try await writer(transport: missingTransport).submitHeldDraftThenRead(missing)
        XCTAssertEqual(missingFact?.requestID, returnedRequest)
        XCTAssertNil(missing.gate.published)
        XCTAssertNotEqual(missing.gate.phase, .published)
        XCTAssertEqual(missing.gate.phase, .aiDraft)

        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher: publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        transport.results = [
            (try submitBody(requestID: returnedRequest, requestState: "SUCCEEDED"), 200),
            (try readBody(requestID: returnedRequest, state: "SUCCEEDED"), 200)
        ]
        _ = try await writer(transport: transport).submitHeldDraftThenRead(flow)
        XCTAssertEqual(publisher.published, 0)
        XCTAssertNil(flow.gate.published)
        XCTAssertNotEqual(flow.gate.phase, .published)
    }

    func testNonAcceptanceDoesNotReachReadFailure() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher: publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        transport.results = [
            (try submitBody(requestID: returnedRequest, requestState: "FAILED", code: 500, errorCode: "AI_DRAFT_FAILED"), 200)
        ]
        transport.failureAt = 1
        let fact = try await writer(transport: transport).submitHeldDraftThenRead(flow)
        XCTAssertNil(fact)
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(flow.heldThemeDraftRequestID, heldRequest)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
    }

    func testUnknownAndNonSuccessStatusDoNotRead() async throws {
        let cases: [(String, Int, Int, String?)] = [
            ("UNKNOWN", 200, 200, nil),
            ("SUCCEEDED", 500, 200, nil),
            ("SUCCEEDED", 200, 200, "AI_DRAFT_OUTCOME_UNKNOWN"),
            ("FAILED", 200, 500, "AI_DRAFT_FAILED")
        ]
        for (state, status, code, errorCode) in cases {
            let transport = ScriptedTransport()
            let publisher = RecordingPublisher()
            let flow = try drafted(publisher: publisher)
            XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
            transport.failureAt = 1
            transport.results = [(try submitBody(requestID: returnedRequest, requestState: state, code: code, errorCode: errorCode), status)]
            let fact = try await writer(transport: transport).submitHeldDraftThenRead(flow)
            XCTAssertNil(fact)
            XCTAssertEqual(transport.sent.count, 1)
            try assertPost(transport.sent[0], held: heldRequest, knowledge: "Local facts")
            XCTAssertEqual(flow.heldThemeDraftRequestID, heldRequest)
            XCTAssertNil(flow.gate.published)
            XCTAssertEqual(publisher.published, 0)
            XCTAssertEqual(flow.gate.phase, .aiDraft)
        }
    }

    func testReadFailureAfterAcceptanceKeepsReturnedIDAndDoesNotPublish() async throws {
        let transport = ScriptedTransport()
        let publisher = RecordingPublisher()
        let flow = try drafted(publisher: publisher)
        XCTAssertTrue(flow.holdThemeDraftRequest(memberID: 7, requestID: heldRequest))
        transport.results = [
            (try submitBody(requestID: returnedRequest, requestState: "SUCCEEDED"), 200)
        ]
        transport.failureAt = 1
        do {
            _ = try await writer(transport: transport).submitHeldDraftThenRead(flow)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? APIError, .malformedResponse)
        }
        XCTAssertEqual(transport.sent.count, 2)
        try assertPost(transport.sent[0], held: heldRequest, knowledge: "Local facts")
        assertGet(transport.sent[1], requestID: returnedRequest)
        XCTAssertEqual(flow.heldThemeDraftRequestID, returnedRequest)
        XCTAssertNil(flow.gate.published)
        XCTAssertEqual(publisher.published, 0)
        XCTAssertEqual(flow.gate.phase, .aiDraft)
    }
}
