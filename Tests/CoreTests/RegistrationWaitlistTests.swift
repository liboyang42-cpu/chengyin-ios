import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class WaitlistWireFixture: HTTPTransport {
    var replies: [(String, Int)]
    var error: Error?
    var requests: [URLRequest] = []
    init(_ replies: [(String, Int)]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if let error { throw error }
        guard !replies.isEmpty else { throw APIError.malformedResponse }
        let reply = replies.removeFirst(); return (Data(reply.0.utf8), reply.1)
    }
}

final class RegistrationWaitlistTests: XCTestCase {
    private func decode(_ additions: String = "", state: String = "NONE", eligibility: String = "ELIGIBLE", allowed: Bool = true) throws -> RegistrationWaitlistStatus {
        try JSONDecoder().decode(RegistrationWaitlistStatus.self, from: Data("{\"activityId\":7,\"ticketId\":11,\"memberId\":1,\"state\":\"\(state)\",\"eligibilityState\":\"\(eligibility)\",\"waitlistJoinAllowed\":\(allowed)\(additions)}".utf8))
    }
    func testNoneEligibilityAndMemberScopeAreAuthoritative() throws {
        let status = try decode()
        XCTAssertTrue(status.canJoin); XCTAssertFalse(status.canCancel)
        XCTAssertTrue(status.matches(try .init(activityID: 7, ticketID: 11), accountID: 1))
        XCTAssertFalse(status.matches(try .init(activityID: 7, ticketID: 11), accountID: 2))
        XCTAssertFalse(try decode(eligibility: "NOT_MEMBER", allowed: false).canJoin)
    }
    func testUnknownStatesAndContradictoryEligibilityFailClosed() {
        XCTAssertThrowsError(try decode(state: "FUTURE"))
        XCTAssertThrowsError(try decode(eligibility: "FUTURE"))
        XCTAssertThrowsError(try decode(eligibility: "BLOCKED"))
        XCTAssertThrowsError(try decode(state: "WAITING"))
        XCTAssertThrowsError(try decode(",\"id\":-1", state: "WAITING"))
    }
    func testClaimedAndConvertedRequireAnExactPositiveOrderID() throws {
        for state in ["CLAIMED", "CONVERTED"] {
            XCTAssertThrowsError(try decode(",\"id\":5", state: state))
            let status = try decode(",\"id\":5,\"registrationId\":41", state: state)
            XCTAssertEqual(status.registrationID, 41); XCTAssertFalse(status.canCancel)
        }
    }
    func testOfferRequiresPairedTokenIDAndUnambiguousDeadline() {
        for addition in [",\"id\":5", ",\"id\":5,\"offerToken\":\"x\"", ",\"id\":5,\"offerToken\":\"x\",\"offerExpiresAt\":\"10/02/26 12:00\""] {
            XCTAssertThrowsError(try decode(addition, state: "OFFERED"))
        }
    }
    func testServerOneDayOfferIsNotTruncatedToLegacyTwoHours() throws {
        let status = try decode(",\"id\":5,\"offerToken\":\"fixture-offer\",\"offerExpiresAt\":\"2030-10-02T12:00:00+08:00\"", state: "OFFERED")
        let expiry = try XCTUnwrap(status.expiresAt)
        XCTAssertNotNil(status.offer(at: expiry.addingTimeInterval(-23 * 3600)))
        XCTAssertNil(status.offer(at: expiry)); XCTAssertNil(status.offer(at: expiry.addingTimeInterval(1)))
    }
    func testTimezoneFreeDeadlineUsesBackendZoneRatherThanDeviceZone() throws {
        XCTAssertEqual(RegistrationWaitlistStatus.parseDeadline("2030-10-02 12:00:00"), RegistrationWaitlistStatus.parseDeadline("2030-10-02T04:00:00Z"))
        XCTAssertEqual(RegistrationWaitlistStatus.parseDeadline("2030-10-02T04:00:00.000Z"), RegistrationWaitlistStatus.parseDeadline("2030-10-02T04:00:00Z"))
        XCTAssertNil(RegistrationWaitlistStatus.parseDeadline("2030-02-30 12:00:00"))
        XCTAssertNil(RegistrationWaitlistStatus.parseDeadline("2030-10-02T12:00:00"))
    }
    func testClosedEligibilityCannotMakeOfferedEntryClaimable() throws {
        let status = try decode(",\"id\":5,\"offerToken\":\"fixture-offer\",\"offerExpiresAt\":\"2030-10-02T12:00:00Z\"", state: "OFFERED", eligibility: "WAITLIST_CLOSED", allowed: false)
        XCTAssertNil(status.offer(at: Date(timeIntervalSince1970: 0)))
        XCTAssertTrue(status.canCancel)
    }
    func testQuoteEncodesSameOfferAndHasNoInventedQuantityOrParticipantID() throws {
        let offer = try RegistrationWaitlistOffer(id: 5, token: "fixture-offer")
        let quote = try RegistrationQuoteRequest(ownerID: 7, ticketID: 11, waitlistOffer: offer)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(quote)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["ownerType", "ownerId", "ticketId", "isUsePoint", "waitlistOfferId", "waitlistOfferToken"])
        XCTAssertEqual(object["waitlistOfferId"] as? Int, 5)
        XCTAssertEqual(object["waitlistOfferToken"] as? String, "fixture-offer")
        XCTAssertThrowsError(try RegistrationQuoteRequest(ownerID: 7, waitlistOffer: offer))
    }
    func testCreateCannotReplaceAnOfferBoundToTheQuote() throws {
        let selection = try RegistrationQuoteRequest(ownerID: 7, ticketID: 11, waitlistOffer: .init(id: 5, token: "offer-one"))
        let quote = try JSONDecoder().decode(RegistrationQuote.self, from: Data(#"{"payAmount":0,"quoteSign":"fixture"}"#.utf8))
        XCTAssertThrowsError(try RegistrationCreateIntent(selection: selection, quote: quote, realName: "Fixture", phone: "13800000000", waitlistOffer: .init(id: 6, token: "offer-two")))
        let intent = try RegistrationCreateIntent(selection: selection, quote: quote, realName: "Fixture", phone: "13800000000", waitlistOffer: selection.waitlistOffer)
        XCTAssertEqual(intent.waitlistOffer, selection.waitlistOffer)
    }
    func testWaitlistWireUsesOnlySourceRoutesAndScopeWithRawAuthorization() async throws {
        let status = #"{"code":200,"data":{"activityId":7,"ticketId":11,"memberId":1,"state":"NONE","eligibilityState":"ELIGIBLE","waitlistJoinAllowed":true}}"#
        let transport = WaitlistWireFixture([(status, 200)])
        let service = try RegistrationWaitlistService(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com/prod-api")!), transport: transport)
        _ = try await service.status(.init(activityID: 7, ticketID: 11), accountID: 1, token: "fixture-token")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/prod-api/api/club/event-ops/waitlist/status")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Int])
        XCTAssertEqual(body, ["activityId": 7, "ticketId": 11])
    }
    func testWrongAccountStatusIsRejectedWithoutRetry() async throws {
        let transport = WaitlistWireFixture([(#"{"code":200,"data":{"activityId":7,"ticketId":11,"memberId":2,"state":"NONE","eligibilityState":"ELIGIBLE","waitlistJoinAllowed":true}}"#, 200)])
        let service = try RegistrationWaitlistService(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com")!), transport: transport)
        do { _ = try await service.status(.init(activityID: 7, ticketID: 11), accountID: 1, token: "fixture-token"); XCTFail("Wrong account must fail") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        XCTAssertEqual(transport.requests.count, 1)
    }
}
