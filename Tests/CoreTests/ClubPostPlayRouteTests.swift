import XCTest
@testable import QuestifyCore

final class ClubPostPlayRouteTests: XCTestCase {
    private final class Host {}
    private let host = Host(), scope = UUID()
    private func context(club: Int? = 81, account: Int? = 701, epoch: UInt64 = 1,
                         readScope: UUID? = nil, hostID: ObjectIdentifier? = nil, revision: UInt64 = 1) -> ClubPostPlayContext {
        .init(clubID: club, identity: .init(accountID: account, epoch: epoch), readScope: readScope ?? scope,
              hostIdentifier: hostID ?? ObjectIdentifier(host), viewerRevision: revision)
    }
    private func post(topic: Int? = 301, type: Int? = 2, template: Bool = true, club: Int? = 81,
                      title: String = "Sample reference", cover: String = "https://fixture.invalid/cover", version: Int = 2) throws -> ClubCommunityPost {
        var value: [String: Any] = ["id": 91, "authorMemberId": 702, "refId": 401, "isTopicTemplate": template,
                                   "sportName": title, "sportCover": cover, "version": version, "content": "Sample"]
        value["sportTopicId"] = topic; value["refType"] = type; value["clubId"] = club
        return try .init(json: value)
    }
    func testExactSportTopicBecomesTopicGameplayScopeNotReferenceActivityOrAuthor() throws {
        let post = try post(), route = try XCTUnwrap(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: context()))
        XCTAssertEqual(route.destination, .gameplay(.topic(301)))
        XCTAssertNotEqual(route.destination, .gameplay(.activity(301)))
        XCTAssertNotEqual(route.destination, .gameplay(.topic(401)))
        XCTAssertNotEqual(route.destination, .gameplay(.topic(91)))
        XCTAssertNotEqual(route.destination, .gameplay(.topic(702)))
    }
    func testResolvedScopeUsesTheExistingExactTopicWireContract() throws {
        let post = try post(), route = try XCTUnwrap(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: context()))
        guard case let .gameplay(scope) = route.destination else { return XCTFail("Expected existing gameplay scope") }
        XCTAssertEqual(scope.fields, ["topicId": "301"]); XCTAssertNil(scope.fields["activityId"])
        XCTAssertTrue(scope.isValid)
    }
    func testMissingZeroNegativeUnsafeTopicFallsBackToCommentsWithoutGuessingRefID() throws {
        for id in [nil, 0, -1, 9_007_199_254_740_992] as [Int?] {
            let post = try post(topic: id)
            XCTAssertEqual(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: context())?.destination, .comments)
        }
    }
    func testRemixTemplateFlagDoesNotGateTryOnAnOrdinaryCoverCard() throws {
        for post in [try post(template: true), try post(template: false), try post(type: nil, template: false)] {
            XCTAssertTrue(ClubPostPlayRoute.showsTryAction(for: post))
            XCTAssertNotNil(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: context()))
        }
    }
    func testCompletionCardsAndCardsWithoutNameOrCoverDoNotGainTry() throws {
        for post in [try post(type: 1), try post(title: ""), try post(cover: "")] {
            XCTAssertFalse(ClubPostPlayRoute.showsTryAction(for: post))
            XCTAssertNil(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: context()))
        }
    }
    func testOnlyOneExactAcceptedSameClubPostCanResolve() throws {
        let post = try post()
        XCTAssertNil(ClubPostPlayRoute(post: post, acceptedPosts: [], context: context()))
        XCTAssertNil(ClubPostPlayRoute(post: post, acceptedPosts: [post, post], context: context()))
        XCTAssertNil(ClubPostPlayRoute(post: post, acceptedPosts: [try self.post(topic: 302)], context: context()))
        XCTAssertNil(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: context(club: 82)))
        XCTAssertNil(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: context(account: 0)))
    }
    func testAccountEpochRoleRevisionHostAndRefreshRetireSelectedGameplay() throws {
        let post = try post(), replacement = Host()
        let route = try XCTUnwrap(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: context()))
        for value in [context(account: nil), context(account: 703), context(epoch: 2), context(revision: 2),
                      context(hostID: ObjectIdentifier(replacement)), context(readScope: UUID()), context(club: 82)] {
            XCTAssertFalse(route.isCurrent(acceptedPosts: [post], context: value))
        }
    }
    func testRemovedReplacedDuplicateOrVersionChangedPostRetiresCallback() throws {
        let post = try post(), route = try XCTUnwrap(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: context()))
        for rows in [[], [post, post], [try self.post(version: 3)], [try self.post(topic: 302)], [try self.post(title: "Changed")]] {
            XCTAssertFalse(route.isCurrent(acceptedPosts: rows, context: context()))
        }
        XCTAssertFalse(route.isCurrent(acceptedPosts: nil, context: context()))
    }
    func testGuestSelectionCannotBeReplayedAfterSignInEvenForTheSamePost() throws {
        let post = try post(), guest = context(account: nil)
        let route = try XCTUnwrap(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: guest))
        XCTAssertTrue(route.isCurrent(acceptedPosts: [post], context: guest))
        XCTAssertFalse(route.isCurrent(acceptedPosts: [post], context: context(account: 701, epoch: 2, revision: 2)))
    }
    func testCommentsNeedKnownClubAndReopeningCreatesIndependentEntry() throws {
        let unknown = try post(topic: nil, club: nil)
        XCTAssertNil(ClubPostPlayRoute(post: unknown, acceptedPosts: [unknown], context: context(club: nil)))
        let post = try post()
        let a = try XCTUnwrap(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: context()))
        let b = try XCTUnwrap(ClubPostPlayRoute(post: post, acceptedPosts: [post], context: context()))
        XCTAssertNotEqual(a.id, b.id); XCTAssertEqual(a.destination, b.destination)
    }
}
