import XCTest
@testable import QuestifyCore

final class ClubPostReferenceRouteTests: XCTestCase {
    private let readScope = UUID()
    private func context(club: Int? = 81, account: Int? = 701, epoch: UInt64 = 1,
                         scope: UUID? = nil, revision: UInt64 = 1) -> ClubPostReferenceContext {
        .init(clubID: club, identity: .init(accountID: account, epoch: epoch), readScope: scope ?? readScope, viewerRevision: revision)
    }
    private func post(topic: Int? = 301, refID: Int = 401, refType: Int = 1, club: Int? = 81,
                      version: Int = 2, title: String = "Referenced topic", cover: String = "", content: String = "Sample") throws -> ClubCommunityPost {
        var json: [String: Any] = ["id": 91, "authorMemberId": 702, "content": content, "refId": refID, "refType": refType,
                                   "sportName": title, "sportCover": cover, "version": version]
        json["sportTopicId"] = topic; json["clubId"] = club
        return try .init(json: json)
    }
    func testTopicIDIsExactAndNeverPostRefOrMemberID() throws {
        let post = try post(), target = try XCTUnwrap(ClubPostReferenceRoute(post: post, acceptedPosts: [post], context: context()))
        XCTAssertEqual(target.destination, .topic(301))
        XCTAssertNotEqual(target.destination, .topic(91)); XCTAssertNotEqual(target.destination, .topic(401))
        XCTAssertNotEqual(target.destination, .topic(702)); XCTAssertNotEqual(target.destination, .topic(701))
    }
    func testMissingZeroNegativeAndUnsafeTopicUseExistingComments() throws {
        for id in [nil, 0, -1, 9_007_199_254_740_992] as [Int?] {
            let post = try post(topic: id)
            let target = try XCTUnwrap(ClubPostReferenceRoute(post: post, acceptedPosts: [post], context: context()))
            XCTAssertEqual(target.destination, .comments)
        }
    }
    func testTopicDoesNotRequireRefIDToEqualTopicOrReferenceToBeATemplate() throws {
        let template = try post(refID: 401), activity = try post(refID: 501, refType: 2, cover: "https://fixture.invalid/cover")
        for post in [template, activity] {
            XCTAssertEqual(ClubPostReferenceRoute(post: post, acceptedPosts: [post], context: context())?.destination, .topic(301))
        }
    }
    func testInvisibleReferenceAndUnknownClubCommentsDoNotManufactureAction() throws {
        for post in [try post(title: ""), try post(refType: 2)] {
            XCTAssertNil(ClubPostReferenceRoute(post: post, acceptedPosts: [post], context: context()))
        }
        let noClub = try post(topic: nil, club: nil)
        XCTAssertNil(ClubPostReferenceRoute(post: noClub, acceptedPosts: [noClub], context: context(club: nil)))
        let exactTopic = try post(club: nil)
        XCTAssertNotNil(ClubPostReferenceRoute(post: exactTopic, acceptedPosts: [exactTopic], context: context(club: nil)))
    }
    func testExactUniqueAcceptedSameClubPostRequired() throws {
        let post = try post()
        XCTAssertNil(ClubPostReferenceRoute(post: post, acceptedPosts: [], context: context()))
        XCTAssertNil(ClubPostReferenceRoute(post: post, acceptedPosts: [post, post], context: context()))
        XCTAssertNil(ClubPostReferenceRoute(post: post, acceptedPosts: [try self.post(topic: 302)], context: context()))
        XCTAssertNil(ClubPostReferenceRoute(post: post, acceptedPosts: [post], context: context(club: 82)))
        XCTAssertNil(ClubPostReferenceRoute(post: post, acceptedPosts: [post], context: context(account: 0)))
    }
    func testAccountEpochScopeRevisionAndClubRetireRoute() throws {
        let post = try post(), target = try XCTUnwrap(ClubPostReferenceRoute(post: post, acceptedPosts: [post], context: context()))
        for context in [context(account: nil), context(account: 703), context(epoch: 2), context(scope: UUID()), context(revision: 2), context(club: 82)] {
            XCTAssertFalse(target.isCurrent(acceptedPosts: [post], context: context))
        }
    }
    func testPostRemovalReplacementAndDuplicateRetireRoute() throws {
        let post = try post(), target = try XCTUnwrap(ClubPostReferenceRoute(post: post, acceptedPosts: [post], context: context()))
        for posts in [[], [post, post], [try self.post(topic: 302)], [try self.post(version: 3)], [try self.post(content: "Replaced")]] {
            XCTAssertFalse(target.isCurrent(acceptedPosts: posts, context: context()))
        }
        XCTAssertFalse(target.isCurrent(acceptedPosts: nil, context: context()))
    }
    func testGuestContextAndIndependentReopeningRemainSupported() throws {
        let post = try post(), guest = context(account: nil)
        let first = try XCTUnwrap(ClubPostReferenceRoute(post: post, acceptedPosts: [post], context: guest))
        let second = try XCTUnwrap(ClubPostReferenceRoute(post: post, acceptedPosts: [post], context: guest))
        XCTAssertTrue(first.isCurrent(acceptedPosts: [post], context: guest))
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(first.destination, second.destination)
    }
}
