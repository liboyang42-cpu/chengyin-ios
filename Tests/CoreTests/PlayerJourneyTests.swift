import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PlayerJourneyTests: XCTestCase {
    private let record = #"{"id":71,"ownerType":1,"ownerId":91,"registrationStatus":2,"paymentStatus":2,"verificationStatus":0,"cmsTopic":{"id":91,"name":"Synthetic route","startDate":"2099-01-01 10:00:00","productType":2},"refundInfo":{"refundable":true}}"#
    func testParticipationIsNotParticipantAndFiltersUseOrderProjection() throws {
        let row = try JSONDecoder().decode(ParticipationRecord.self, from: Data(record.utf8))
        XCTAssertEqual(row.id, 71); XCTAssertEqual(row.destination, .topic(91)); XCTAssertTrue(row.isFreeExplore)
        XCTAssertTrue(ParticipationFilter.notStarted.includes(row, now: Date(timeIntervalSince1970: 0)))
        XCTAssertFalse(ParticipationFilter.completed.includes(row, now: Date(timeIntervalSince1970: 0)))
    }
    func testCancellationUsesCurrentMiniStatusNotThreeDayHeuristic() throws {
        let detail = try JSONDecoder().decode(ParticipationDetail.self, from: Data(record.utf8))
        let nearStart = try XCTUnwrap(OrderLifecycleTime.date("2099-01-01 09:59:00"))
        XCTAssertTrue(detail.canCancel(now: nearStart)); XCTAssertEqual(detail.cancellationAction, .refund)
        let cancelled = record.replacingOccurrences(of: "\"registrationStatus\":2", with: "\"registrationStatus\":3")
        XCTAssertFalse(try JSONDecoder().decode(ParticipationDetail.self, from: Data(cancelled.utf8)).canCancel(now: nearStart))
    }
    func testMissingAndInvalidVerificationCountsStayUnknown() throws {
        let raw = String(record.dropLast()) + #", "status":1,"totalOrderNum":2,"verifiedNum":3}"#
        let detail = try JSONDecoder().decode(ParticipationDetail.self, from: Data(raw.utf8))
        XCTAssertTrue(detail.showOrderStats); XCTAssertNil(detail.total); XCTAssertNil(detail.pending)
    }
    func testCompletedDestinationUsesActivityThenTopicAndNeverZero() throws {
        let values = try JSONDecoder().decode([CompletedPlayRecord].self, from: Data(#"[{"activityId":3,"topicId":4},{"activityId":0,"topicId":4},{"activityId":0,"topicId":0},{"total":0}]"#.utf8))
        XCTAssertEqual(values[0].destination, .activity(3)); XCTAssertEqual(values[1].destination, .topic(4))
        XCTAssertNil(values[2].destination); XCTAssertNil(values[3].doneCount)
    }
    func testExactReadOnlyPostContractsAndStringEnvelopeCode() async throws {
        let transport = JourneyTestTransport(replies: [Data("{\"code\":\"200\",\"data\":[\(record)]}".utf8),
            Data("{\"code\":200,\"data\":\(record)}".utf8), Data(#"{"code":200,"data":[]}"#.utf8)])
        let service = try makeService(transport, enabled: true)
        _ = try await service.participations(token: "synthetic-token")
        _ = try await service.detail(id: 71, token: "synthetic-token")
        _ = try await service.completed(token: "synthetic-token")
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/api/registration/my-joined", "/api/registration/info", "/api/play/my-completed"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "POST" })
        XCTAssertNil(requests[0].httpBody); XCTAssertNil(requests[2].httpBody)
        let detailBody = try XCTUnwrap(requests[1].httpBody).utf8String
        XCTAssertTrue(detailBody.contains("name=\"id\"\r\n\r\n71\r\n"))
        XCTAssertFalse(detailBody.contains("merchant"))
    }
    func testDisabledServiceNeverDispatches() async throws {
        let transport = JourneyTestTransport(replies: [])
        do { _ = try await makeService(transport).completed(token: "synthetic-token"); XCTFail("Expected disabled read") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let count = await transport.requests.count; XCTAssertEqual(count, 0)
    }
    func testMalformedListIsNotEmptyAndWrongDetailIDIsRejected() async throws {
        let transport = JourneyTestTransport(replies: [Data(#"{"code":200,"data":{}}"#.utf8), Data("{\"code\":200,\"data\":\(record)}".utf8)])
        let service = try makeService(transport, enabled: true)
        do { _ = try await service.completed(token: "synthetic-token"); XCTFail("Malformed list") } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        do { _ = try await service.detail(id: 72, token: "synthetic-token"); XCTFail("Wrong detail") } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    @MainActor func testReloginDuringReadRejectsStaleResponseAndStaleUnauthorized() async throws {
        let transport = JourneySuspendedTransport()
        var current = try PlayerJourneySession(accountID: 1, epoch: 1, namespace: "cn", token: "synthetic-a")
        var expired = 0
        let reader = PlayerJourneySessionReader(service: try makeService(transport, enabled: true), currentSession: { current }, onUnauthorized: { _ in expired += 1 })
        let scope = reader.scope
        let request = Task { try await reader.completed() }
        await transport.waitUntilStarted()
        current = try PlayerJourneySession(accountID: 1, epoch: 2, namespace: "cn", token: "synthetic-b")
        XCTAssertNotEqual(scope, reader.scope)
        await transport.finish(Data(#"{"code":401,"msg":"Expired"}"#.utf8))
        do { _ = try await request.value; XCTFail("Stale result") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
    }
    private func makeService(_ transport: any HTTPTransport, enabled: Bool = false) throws -> PlayerJourneyService {
        try PlayerJourneyService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport, readsEnabled: enabled)
    }
}
private extension Data { var utf8String: String { String(decoding: self, as: UTF8.self) } }
private actor JourneyTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var replies: [Data]
    init(replies: [Data]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (replies.removeFirst(), 200) }
}
private actor JourneySuspendedTransport: HTTPTransport {
    private var continuation: CheckedContinuation<Data, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let data = await withCheckedContinuation { continuation in self.continuation = continuation; waiter?.resume(); waiter = nil }
        return (data, 200)
    }
    func waitUntilStarted() async { if continuation != nil { return }; await withCheckedContinuation { waiter = $0 } }
    func finish(_ data: Data) { continuation?.resume(returning: data); continuation = nil }
}
