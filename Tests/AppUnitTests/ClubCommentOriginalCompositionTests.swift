import Foundation
import XCTest
@testable import Questify

@MainActor final class ClubCommentOriginalCompositionTests: XCTestCase {
    func testNoLeaseAndMismatchedSessionNeverResolveTransport() throws {
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://composition.invalid")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "tests", token: "synthetic-token", role: "player"))
        let a = try ClubCommentOriginalApproval(context: context, clubID: 3, expiresAt: Date().addingTimeInterval(60), writes: true)
        var calls = 0
        for account in [7, 8] {
            let service = ClubCommentOriginalComposition.makeService(currentContext: { context }, selectApproval: { _ in account == 7 ? nil : a },
                currentSession: { try .init(identity: .init(accountID: account, epoch: 1), token: "synthetic-token") },
                transport: { calls += 1; return CommunityDormantHTTPTransport() })
            XCTAssertNil(service)
        }
        XCTAssertEqual(calls, 0)
    }
    func testExplicitReadLeaseNeverEnablesPublication() throws {
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://composition.invalid")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "tests", token: "synthetic-token", role: "player"))
        let a = try ClubCommentOriginalApproval(context: context, clubID: 3, expiresAt: Date().addingTimeInterval(60))
        let service = try XCTUnwrap(ClubCommentOriginalComposition.makeService(currentContext: { context }, selectApproval: { _ in a },
            currentSession: { try .init(identity: .init(accountID: 7, epoch: 1), token: "synthetic-token") },
            transport: { CommunityDormantHTTPTransport() }))
        XCTAssertTrue(service.allowsAuthoritativeQueries); XCTAssertFalse(service.allowsWrites)
    }
}
