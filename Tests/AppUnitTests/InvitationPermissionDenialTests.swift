import Foundation
import XCTest
@testable import Questify

private final class InvitationDenialTransport: HTTPTransport {
    var responses: [(String, Int)] = []
    var requests: [URLRequest] = []
    var afterRequest: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); afterRequest?()
        guard !responses.isEmpty else { throw URLError(.timedOut) }
        let response = responses.removeFirst()
        return (Data(response.0.utf8), response.1)
    }
}

/// Actual decoder + session reader + mounted view model, with offline responses only.
@MainActor final class InvitationPermissionDenialTests: XCTestCase {
    private let first = #"{"code":200,"data":{"rows":[{"id":7,"nickname":"Synthetic"}],"total":2}}"#
    private let next = #"{"code":200,"data":{"rows":[{"id":8}],"total":2}}"#
    private let rewards = #"{"code":200,"data":{"rows":[],"total":0}}"#
    private func service(_ transport: InvitationDenialTransport) throws -> SocialAccountService {
        .init(configuration: try .init(baseURL: URL(string: "https://invite.example/native")!), transport: transport)
    }
    private func identity() throws -> SocialAccountSession {
        try .init(accountID: 81, epoch: 1, role: "player", token: "synthetic-token")
    }

    func testRewardHTTPAndBusiness403NeverBecomeSuccessfulPartial() async throws {
        for denied in [("not JSON", 403), (#"{"code":403,"msg":"denied"}"#, 200)] {
            let transport = InvitationDenialTransport()
            transport.responses = [(first, 200), denied]
            let identity = try identity()
            let reader = SocialAccountSessionReader(service: try service(transport), currentSession: { identity })
            do { _ = try await reader.invitationHistory(page: 1); XCTFail("403 became a partial success") }
            catch { XCTAssertEqual(ProfileInviteHistoryIssueKind(error), .denied) }
            XCTAssertEqual(transport.requests.count, 2)
        }
    }

    func testIncremental403ClearsPriorPrivateRowsAndScanWithoutExpiringIdentity() async throws {
        for rewardFailure in [false, true] {
            for denied in [("not JSON", 403), (#"{"code":403}"#, 200)] {
                let transport = InvitationDenialTransport()
                transport.responses = [(first, 200), (rewards, 200)]
                let identity = try identity()
                var expirations = 0
                let reader = SocialAccountSessionReader(service: try service(transport), currentSession: { identity },
                    onUnauthorized: { _ in expirations += 1 })
                let model = SocialInviteHistoryModel()
                await model.appear(reader)?.value
                XCTAssertEqual(model.pagination.members.map(\.id), [7])
                XCTAssertNotNil(model.scan)
                transport.responses = rewardFailure ? [(next, 200), denied] : [denied]
                await model.start(reader, permit: model.permit(reader), reset: false)?.value
                XCTAssertTrue(model.accessDenied)
                XCTAssertTrue(model.pagination.members.isEmpty)
                XCTAssertNil(model.scan)
                XCTAssertEqual(expirations, 0, "403 must not invent a global logout")
                XCTAssertEqual(reader.identity.accountID, 81)
                XCTAssertEqual(ProfileInviteHistoryIssueKind(try XCTUnwrap(model.error)), .denied)
                model.suspend()
            }
        }
    }

    func testOrdinaryRewardFailureRetainsInvitationsWithUnknownRewards() async throws {
        let transport = InvitationDenialTransport()
        transport.responses = [(first, 200)] // Missing second response throws a synthetic timeout.
        let identity = try identity()
        let reader = SocialAccountSessionReader(service: try service(transport), currentSession: { identity })
        let model = SocialInviteHistoryModel()
        await model.appear(reader)?.value
        XCTAssertEqual(model.pagination.members.map(\.id), [7])
        XCTAssertNil(model.scan)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.accessDenied)
        XCTAssertEqual(transport.requests.count, 2)
        model.suspend()
    }

    func test401RetainsOriginalUnauthorizedCallbackAndClearsPrivateData() async throws {
        let transport = InvitationDenialTransport()
        transport.responses = [(first, 200), (rewards, 200)]
        let identity = try identity()
        var expirations = 0
        let reader = SocialAccountSessionReader(service: try service(transport), currentSession: { identity },
            onUnauthorized: { _ in expirations += 1 })
        let model = SocialInviteHistoryModel()
        await model.appear(reader)?.value
        transport.responses = [(next, 200), ("", 401)]
        await model.start(reader, permit: model.permit(reader), reset: false)?.value
        XCTAssertEqual(expirations, 1)
        XCTAssertTrue(model.accessDenied)
        XCTAssertTrue(model.pagination.members.isEmpty)
        XCTAssertNil(model.scan)
        model.suspend()
    }

    func testGuestPrivateHistoryMakesZeroRequests() async throws {
        let transport = InvitationDenialTransport()
        let reader = SocialAccountSessionReader(service: try service(transport), currentSession: { .init(guestEpoch: 2) })
        do { _ = try await reader.invitationHistory(page: 1); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testLate403AfterAccountChangeRemainsCancellationNotNewAccountDenial() async throws {
        let transport = InvitationDenialTransport()
        transport.responses = [(first, 200), ("", 403)]
        var identity = try identity()
        let replacement = try SocialAccountSession(accountID: 82, epoch: 2, role: "player", token: "synthetic-other")
        transport.afterRequest = { if transport.requests.count == 2 { identity = replacement } }
        var expirations = 0
        let reader = SocialAccountSessionReader(service: try service(transport), currentSession: { identity },
            onUnauthorized: { _ in expirations += 1 })
        do { _ = try await reader.invitationHistory(page: 1); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reader.identity.accountID, 82)
        XCTAssertEqual(expirations, 0)
    }
}
