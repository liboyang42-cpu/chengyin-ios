import Foundation
import XCTest
@testable import QuestifyCore

private final class AdmissionFakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var body = Data()
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (body, status)
    }
}

final class ChannelAdmissionGovernanceClientTests: XCTestCase {
    private func client(_ transport: AdmissionFakeTransport) throws -> ChannelAdmissionGovernanceClient {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let identity = try ChannelAccount4Identity(accountID: 7, epoch: 1)
        let admission = try ChannelRulesAdmission(identity: identity, consentedVersion: 3)
        return try ChannelAdmissionGovernanceClient(configuration: configuration, transport: transport, token: "token", admission: admission)
    }

    func testPausePostsTheOriginalRouteOnce() async throws {
        let transport = AdmissionFakeTransport()
        transport.body = try JSONSerialization.data(withJSONObject: [
            "code": 200,
            "data": ["guild_kind": 1, "guild_id": "12", "join_paused": true]
        ])
        let sent = try await client(transport).pause(
            kind: 1, spaceID: 12, paused: true, until: nil, reason: " full ", requestID: "c08-pause-01")
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url?.path, "/prod-api/api/space/join-pause")
        XCTAssertEqual(transport.requests[0].httpMethod, "POST")
        let raw = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(raw["guild_kind"] as? Int, 1)
        XCTAssertEqual(raw["guild_id"] as? Int, 12)
        XCTAssertEqual(raw["paused"] as? Bool, true)
        XCTAssertEqual(raw["request_id"] as? String, "c08-pause-01")
        XCTAssertNil(raw["paused_until"])
        XCTAssertEqual(sent["join_paused"] as? Bool, true)
    }

    func testBlankPauseReasonDoesNotPost() async throws {
        let transport = AdmissionFakeTransport()
        do {
            _ = try await client(transport).pause(kind: 1, spaceID: 12, paused: true, until: nil, reason: " ", requestID: "c08-pause-01")
            XCTFail()
        } catch ChannelAuthorizationError.invalidCatalog {}
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testRevokeAndReceiptUseTheOriginalRoutes() async throws {
        let transport = AdmissionFakeTransport()
        transport.body = try JSONSerialization.data(withJSONObject: [
            "code": 200, "data": ["invite_id": "8", "status": 1]
        ])
        _ = try await client(transport).revokeInvite(inviteID: 8, reason: "replaced", requestID: "c08-revoke-01")
        transport.body = try JSONSerialization.data(withJSONObject: [
            "code": 200, "data": ["request_id": "c08-revoke-01", "state": "UNKNOWN"]
        ])
        let recovered = try await client(transport).recover(requestID: "c08-revoke-01")
        XCTAssertEqual(transport.requests.map { $0.url?.path }, [
            "/prod-api/api/invite/revoke",
            "/prod-api/api/channel-platform/admission/requests/c08-revoke-01"
        ])
        XCTAssertEqual(transport.requests[1].httpMethod, "GET")
        XCTAssertEqual(recovered["state"] as? String, "UNKNOWN")
    }

    func testCancelPostsTheOriginalRouteAndSkipsABadIdentifier() async throws {
        let transport = AdmissionFakeTransport()
        do {
            _ = try await client(transport).cancel(applicationID: 0, requestID: "c08-cancel-01")
            XCTFail()
        } catch ChannelAuthorizationError.invalidCatalog {}
        XCTAssertTrue(transport.requests.isEmpty)
        transport.body = try JSONSerialization.data(withJSONObject: [
            "code": 200, "data": ["id": "15", "status": 3]
        ])
        _ = try await client(transport).cancel(applicationID: 15, requestID: "c08-cancel-01")
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url?.path, "/prod-api/api/join-request/cancel")
        let raw = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(raw["id"] as? Int, 15)
        XCTAssertEqual(raw["request_id"] as? String, "c08-cancel-01")
    }

    func testLeavePostsTheOriginalRoute() async throws {
        let transport = AdmissionFakeTransport()
        transport.body = try JSONSerialization.data(withJSONObject: [
            "code": 200, "data": ["guild_kind": 3, "guild_id": "12", "left": true]
        ])
        _ = try await client(transport).leave(kind: 3, spaceID: 12, requestID: "c08-leave-01")
        XCTAssertEqual(transport.requests[0].url?.path, "/prod-api/api/space/leave")
        XCTAssertEqual(transport.requests.count, 1)
    }
}
