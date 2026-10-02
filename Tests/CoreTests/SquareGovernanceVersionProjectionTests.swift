import XCTest
@testable import QuestifyCore

final class SquareGovernanceVersionProjectionTests: XCTestCase {
    private func decode(_ fields: String = "") throws -> SquareComment {
        try JSONDecoder().decode(SquareComment.self, from: Data("{\"id\":61,\"author_id\":22,\"author_approval_state\":\"PENDING\"\(fields)}".utf8))
    }
    func testKnownVersionPreserved() throws {
        XCTAssertEqual(try decode(",\"version\":7").version, 7)
        XCTAssertEqual(try decode(",\"version\":0").version, 0)
    }
    func testMissingNullAndStringVersionStayUnknown() throws {
        XCTAssertNil(try decode().version)
        XCTAssertNil(try decode(",\"version\":null").version)
        XCTAssertNil(try decode(",\"version\":\"7\"").version)
    }
    func testProjectionDoesNotFabricateVersionOrChangeAuthors() throws {
        let post = try JSONDecoder().decode(SquarePost.self, from: Data("{\"id\":71,\"authorId\":11}".utf8))
        let projected = SquareGovernanceComment(comment: try decode(), post: post)
        XCTAssertEqual(projected.id, 61); XCTAssertEqual(projected.postID, 71)
        XCTAssertEqual(projected.commentAuthorID, 22); XCTAssertEqual(projected.postAuthorID, 11)
        XCTAssertNil(projected.version)
        XCTAssertFalse(projected.canApprove(.init(accountID: 11, epoch: 1, namespace: "test")))
        XCTAssertFalse(projected.canDelete(.init(accountID: 11, epoch: 1, namespace: "test")))
    }
    func testProjectionAllowsOnlyPostAuthorForPendingKnownVersion() throws {
        let post = try JSONDecoder().decode(SquarePost.self, from: Data("{\"id\":71,\"authorId\":11}".utf8))
        let projected = SquareGovernanceComment(comment: try decode(",\"version\":7"), post: post)
        XCTAssertTrue(projected.canApprove(.init(accountID: 11, epoch: 1, namespace: "test")))
        XCTAssertFalse(projected.canApprove(.init(accountID: 22, epoch: 1, namespace: "test")))
        XCTAssertTrue(projected.canDelete(.init(accountID: 22, epoch: 1, namespace: "test")))
    }
}
