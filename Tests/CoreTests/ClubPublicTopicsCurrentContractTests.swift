import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ClubPublicTopicsCurrentContractTests: XCTestCase {
    func testExactClubReadShapeRejectsExtraFieldsAndMutation() throws {
        let base = URL(string: "https://example.test")!
        var request = URLRequest(url: base.appendingPathComponent("api/club/topics"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"id":41}"#.utf8)
        XCTAssertEqual(ClubPublicTopicsRoute(request: request, baseURL: base)?.clubID, 41)
        request.httpBody = Data(#"{"id":41,"page":1}"#.utf8)
        XCTAssertNil(ClubPublicTopicsRoute(request: request, baseURL: base))
        request.httpBody = Data(#"{"id":41}"#.utf8)
        request.setValue("request", forHTTPHeaderField: "X-Club-Request-Id")
        XCTAssertNil(ClubPublicTopicsRoute(request: request, baseURL: base))
    }
    func testGuestSessionCannotSmuggleCredentialOrRole() throws {
        let base = URL(string: "https://example.test")!
        let context = ClubPublicTopicsContext(identity: .init(accountID: nil, epoch: 4),
            viewerRevision: 8, role: nil, baseURL: base, namespace: "test")
        XCTAssertNoThrow(try ClubPublicTopicsSession(context: context, membershipRevision: 0, token: nil))
        XCTAssertThrowsError(try ClubPublicTopicsSession(context: context, membershipRevision: 0, token: "synthetic"))
        let invalid = ClubPublicTopicsContext(identity: context.identity, viewerRevision: 8,
            role: "player", baseURL: base, namespace: "test")
        XCTAssertThrowsError(try ClubPublicTopicsSession(context: invalid, membershipRevision: 0, token: nil))
    }
}
