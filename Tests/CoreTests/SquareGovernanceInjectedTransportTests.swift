import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Deliberately conforms only to HTTPTransport, proving the non-marker adapter.
private final class SquareGovernancePlainHTTPFake: HTTPTransport {
    var requests: [URLRequest] = []
    var failMutation = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.httpMethod != "GET" {
            if failMutation { throw SquareGovernanceFailure.unknown }
            return (Data("{\"code\":200}".utf8), 200)
        }
        let json: String
        switch request.url?.path {
        case "/api/v1/community/me/enforcements": json = "{\"code\":200,\"data\":{\"items\":[{\"id\":91,\"status\":\"ACTIVE\"}]}}"
        case "/api/v1/community/notifications": json = "{\"code\":200,\"data\":{\"items\":[{\"id\":81,\"read_at\":null}]}}"
        case "/api/v1/community/notification-preferences": json = "{\"code\":200,\"data\":{\"interactionEnabled\":true,\"mentionEnabled\":true,\"socialEnabled\":false}}"
        default: throw SquareGovernanceFailure.invalid
        }
        return (Data(json.utf8), 200)
    }
}
@MainActor final class SquareGovernanceInjectedTransportTests: XCTestCase {
    func testDormantInitializerDefaultsOffForPlainTransport() async throws {
        let fake = SquareGovernancePlainHTTPFake()
        let service = SquareGovernanceService(dormantBaseURL: URL(string: "https://square-governance.invalid")!, transport: fake)
        XCTAssertFalse(service.allowsInjectedWrites)
        do { _ = try await service.enforcements(token: "synthetic-token", check: {}); XCTFail() } catch { XCTAssertEqual(error as? SquareGovernanceFailure, .disabled) }
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testEveryOperationDispatchesThroughReviewedPlainHTTPTransport() async throws {
        let actions: [(SquareGovernanceCapability, SquareGovernanceAction, String, String)] = [
            (.appeal, .appeal(enforcementID: 91, reason: "facts"), "POST", "/api/v1/community/appeals"),
            (.markRead, .markRead(notificationID: 81), "POST", "/api/v1/community/notifications/81/read"),
            (.preferences, .preferences([.socialEnabled: true]), "PATCH", "/api/v1/community/notification-preferences"),
            (.approveComment, .approveComment(postID: 71, commentID: 61), "POST", "/api/v1/community/posts/71/comments/61/approve"),
            (.deleteOwnComment, .deleteOwnComment(commentID: 62), "POST", "/api/comment/delete")
        ]
        for (capability, action, method, path) in actions {
            let fake = SquareGovernancePlainHTTPFake(), access = SquareGovernanceSyntheticAccess()
            let service = SquareGovernanceService(dormantBaseURL: URL(string: "https://square-governance.invalid")!, transport: fake, readsEnabled: true, grant: .reviewedInjection([capability]))
            let coordinator = SquareGovernanceCoordinator(service: service, journal: .ephemeral())
            let snapshot = try await coordinator.load(access: access)
            let review = try coordinator.prepare(action, snapshot: snapshot, access: access)
            let receipt = try await coordinator.confirm(review, access: access)
            XCTAssertEqual(receipt, .acknowledgedNeedsRefresh)
            let writes = fake.requests.filter { $0.httpMethod != "GET" }
            XCTAssertEqual(writes.count, 1); XCTAssertEqual(writes.first?.httpMethod, method); XCTAssertEqual(writes.first?.url?.path, path)
            XCTAssertNotNil(writes.first?.httpBody)
            XCTAssertEqual(writes.first?.value(forHTTPHeaderField: "Authorization"), "synthetic-only-token")
        }
    }
    func testOperationGrantDoesNotAuthorizeOtherMutation() async throws {
        let fake = SquareGovernancePlainHTTPFake(), access = SquareGovernanceSyntheticAccess()
        let service = SquareGovernanceService(dormantBaseURL: URL(string: "https://square-governance.invalid")!, transport: fake, readsEnabled: true, grant: .reviewedInjection([.markRead]))
        let coordinator = SquareGovernanceCoordinator(service: service, journal: .ephemeral())
        let snapshot = try await coordinator.load(access: access)
        let review = try coordinator.prepare(.deleteOwnComment(commentID: 62), snapshot: snapshot, access: access)
        do { _ = try await coordinator.confirm(review, access: access); XCTFail() } catch { XCTAssertEqual(error as? SquareGovernanceFailure, .disabled) }
        XCTAssertTrue(fake.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testPlainTransportUnknownRemainsLockedAcrossNewReview() async throws {
        let fake = SquareGovernancePlainHTTPFake(), access = SquareGovernanceSyntheticAccess()
        let service = SquareGovernanceService(dormantBaseURL: URL(string: "https://square-governance.invalid")!, transport: fake, readsEnabled: true, grant: .reviewedInjection([.appeal]))
        let coordinator = SquareGovernanceCoordinator(service: service, journal: .ephemeral())
        let snapshot = try await coordinator.load(access: access)
        let review = try coordinator.prepare(.appeal(enforcementID: 91, reason: "facts"), snapshot: snapshot, access: access)
        fake.failMutation = true
        do { _ = try await coordinator.confirm(review, access: access); XCTFail() } catch { XCTAssertEqual(error as? SquareGovernanceFailure, .unknown) }
        XCTAssertThrowsError(try coordinator.prepare(review.action, snapshot: snapshot, access: access))
        XCTAssertEqual(fake.requests.filter { $0.httpMethod != "GET" }.count, 1)
    }
}
