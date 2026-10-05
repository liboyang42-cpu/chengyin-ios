import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ClubFeedPresentationTests: XCTestCase {
    private let reader = NSObject(), access = NSObject()
    private func context(identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1), revision: UInt64 = 4,
                         authorization: UUID? = nil, reader: ObjectIdentifier? = nil, access: ObjectIdentifier? = nil) -> ClubGovernanceReadContext {
        .init(operation: .feed, scope: .init(), identity: identity, viewerRevision: revision, authorizationGeneration: authorization,
              readerIdentity: reader ?? ObjectIdentifier(self.reader), accessIdentity: access ?? ObjectIdentifier(self.access))
    }
    private func row(_ fields: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        var result: [String: ClubGovernanceValue] = ["id": .integer(191), "clubId": .integer(81), "nickname": .string(" Fixture author "),
            "clubName": .string(" Fixture club "), "content": .string("Synthetic post"), "createTime": .string("2026-10-04 18:30:00")]
        result.merge(fields) { _, new in new }; return .object(result)
    }
    private func snapshot(_ rows: [ClubGovernanceValue], count: ClubGovernanceValue = .integer(1)) -> ClubGovernanceSnapshot {
        .init(operation: .feed, scope: .init(), permissions: nil, value: .object(["clubCount": count, "rows": .array(rows)]))
    }
    private func route(_ snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext? = nil) throws -> ClubFeedClubRoute? {
        let post = try XCTUnwrap(ClubFeedPresentation(snapshot: snapshot).posts.first)
        return .init(post: post, snapshot: snapshot, context: context ?? self.context(), snapshotGeneration: 7)
    }
    func testFeedUsesLimitOnlyAndPostsKeepExistingPaging() throws {
        XCTAssertEqual(try ClubGovernanceRead.feed.fields(scope: .init()), ["limit": .integer(20)])
        XCTAssertEqual(try ClubGovernanceRead.feed.fields(scope: .init(), options: ["limit": .integer(50)]), ["limit": .integer(50)])
        for key in ["pageNum", "pageSize", "cursor", "offset", "clubId"] {
            XCTAssertThrowsError(try ClubGovernanceRead.feed.fields(scope: .init(), options: [key: .integer(1)]))
        }
        for value in [ClubGovernanceValue.integer(0), .integer(-1), .integer(51), .bool(true), .decimal(2.5), .null] {
            XCTAssertThrowsError(try ClubGovernanceRead.feed.fields(scope: .init(), options: ["limit": value]))
        }
        XCTAssertEqual(try ClubGovernanceRead.posts.fields(scope: .init(clubID: 81), options: ["pageNum": .integer(3)]),
                       ["clubId": .integer(81), "pageNum": .integer(3), "pageSize": .integer(20)])
    }
    func testTypedDisplayKeepsExactAttributionAndServerTimeWithoutInventingTimezone() throws {
        let post = try XCTUnwrap(ClubFeedPresentation(snapshot: snapshot([row()])).posts.first)
        XCTAssertEqual(post.id, 191); XCTAssertEqual(post.clubID, 81)
        XCTAssertEqual(post.nickname, "Fixture author"); XCTAssertEqual(post.clubName, "Fixture club")
        XCTAssertEqual(post.content, "Synthetic post"); XCTAssertEqual(post.createTime, "2026-10-04 18:30:00")
    }
    func testImageProjectionUsesSourceDelimitersOrderAndThreeImageBound() throws {
        let post = try XCTUnwrap(ClubFeedPresentation(snapshot: snapshot([row([
            "avatar": .string(" https://example.invalid/avatar.jpg "),
            "images": .string("https://example.invalid/a.jpg; https://example.invalid/b.jpg,https://example.invalid/c.jpg;https://example.invalid/d.jpg")])])).posts.first)
        XCTAssertEqual(post.avatar, "https://example.invalid/avatar.jpg")
        XCTAssertEqual(post.images, ["https://example.invalid/a.jpg", "https://example.invalid/b.jpg", "https://example.invalid/c.jpg"])
    }
    func testUnsafeFirstThreeImagesDoNotPromoteAnUnshownFourthReference() throws {
        let post = try XCTUnwrap(ClubFeedPresentation(snapshot: snapshot([row([
            "images": .string("object/one;http://example.invalid/two;file:///three;https://example.invalid/four")])])).posts.first)
        XCTAssertTrue(post.images.isEmpty)
    }
    func testMissingAndMalformedOptionalPresentationDoesNotInventData() throws {
        let values: [ClubGovernanceValue] = [.null, .bool(true), .integer(99), .array([]), .object([:]), .string(" \n ")]
        for value in values {
            let post = try XCTUnwrap(ClubFeedPresentation(snapshot: snapshot([row(["nickname": value, "clubName": value,
                "content": value, "createTime": value, "avatar": value, "images": value])])).posts.first)
            XCTAssertNil(post.nickname); XCTAssertNil(post.clubName); XCTAssertNil(post.content); XCTAssertNil(post.createTime)
            XCTAssertNil(post.avatar); XCTAssertTrue(post.images.isEmpty)
        }
    }
    func testUnsafeMediaIsNotTurnedIntoAnOriginGrantOrStorageHost() throws {
        for raw in ["object/key.jpg", "http://example.invalid/a.jpg", "file:///tmp/a.jpg", "data:image/png;base64,abc", "https://user:secret@example.invalid/a.jpg", "https://example.invalid/%ZZ", "https://example.invalid/a\nb.jpg", String(repeating: "a", count: 8193)] {
            let post = try XCTUnwrap(ClubFeedPresentation(snapshot: snapshot([row(["avatar": .string(raw)])])).posts.first)
            XCTAssertNil(post.avatar, raw)
        }
    }
    func testEmptyNoClubsAndJoinedWithoutPostsStayDistinctAndUnknownIsNotZero() throws {
        XCTAssertEqual(try ClubFeedPresentation(snapshot: snapshot([], count: .integer(0))).clubCount, 0)
        XCTAssertEqual(try ClubFeedPresentation(snapshot: snapshot([], count: .integer(2))).clubCount, 2)
        for value in [ClubGovernanceValue.null, .integer(-1), .string("unknown"), .bool(false), .decimal(1.5)] {
            XCTAssertThrowsError(try ClubFeedPresentation(snapshot: snapshot([], count: value)))
        }
    }
    func testSourceClubNeverUsesPostOrAuthorIdentifiers() throws {
        let snap = snapshot([row(["authorMemberId": .integer(999), "memberId": .integer(888)])])
        let route = try XCTUnwrap(route(snap))
        XCTAssertEqual(route.clubID, 81); XCTAssertNotEqual(route.clubID, route.postID)
        XCTAssertNotEqual(route.clubID, 999); XCTAssertNotEqual(route.clubID, 888)
        XCTAssertTrue(route.isCurrent(snapshot: snap, context: context(), snapshotGeneration: 7))
    }
    func testInvalidSourceClubPreservesPostButCannotNavigate() throws {
        for id in [ClubGovernanceValue.null, .integer(0), .integer(-1), .integer(Int.max), .decimal(1.5), .decimal(.infinity), .bool(true), .string("wrong")] {
            let snap = snapshot([row(["clubId": id])])
            XCTAssertEqual(try ClubFeedPresentation(snapshot: snap).posts.count, 1)
            XCTAssertNil(try route(snap))
        }
    }
    func testDuplicatePostIdentityAndWrongSnapshotCannotCreatePresentation() {
        XCTAssertThrowsError(try ClubFeedPresentation(snapshot: snapshot([row(), row()])))
        let snap = ClubGovernanceSnapshot(operation: .posts, scope: .init(clubID: 81), permissions: nil, value: .array([row()]))
        XCTAssertThrowsError(try ClubFeedPresentation(snapshot: snap))
    }
    func testSelectionExpiresForViewerReaderAccessAuthorityAndReadRevisions() throws {
        let snap = snapshot([row()]), route = try XCTUnwrap(route(snap)), replacement = NSObject()
        let variants = [context(identity: nil), context(identity: .init(accountID: 702, epoch: 1)),
            context(identity: .init(accountID: 701, epoch: 2)), context(revision: 5), context(revision: 6),
            context(authorization: UUID()), context(reader: ObjectIdentifier(replacement)), context(access: ObjectIdentifier(replacement))]
        for changed in variants { XCTAssertFalse(route.isCurrent(snapshot: snap, context: changed, snapshotGeneration: 7)) }
        XCTAssertFalse(route.isCurrent(snapshot: snap, context: context(), snapshotGeneration: 8))
        XCTAssertFalse(route.isCurrent(snapshot: nil, context: context(), snapshotGeneration: 7))
    }
    func testRemovedRetargetedOrChangedContentCannotRenderOldDestination() throws {
        let snap = snapshot([row()]), route = try XCTUnwrap(route(snap))
        for rows in [[], [row(["clubId": .integer(82)])], [row(["content": .string("Replaced")])], [row(), row()]] {
            XCTAssertFalse(route.isCurrent(snapshot: snapshot(rows), context: context(), snapshotGeneration: 7))
        }
        let post = try XCTUnwrap(ClubFeedPresentation(snapshot: snapshot([row(["clubId": .integer(82)])])).posts.first)
        XCTAssertNil(ClubFeedClubRoute(post: post, snapshot: snap, context: context(), snapshotGeneration: 7))
    }
    func testSignedOutAndMissingReaderContextCannotNavigate() throws {
        let snap = snapshot([row()])
        for identity in [nil, ClubReadIdentity(accountID: 0, epoch: 1), .init(accountID: -1, epoch: 1)] {
            XCTAssertNil(try route(snap, context: context(identity: identity)))
        }
        let unfenced = ClubGovernanceReadContext(operation: .feed, scope: .init(), identity: .init(accountID: 701, epoch: 1), viewerRevision: 4, authorizationGeneration: nil)
        XCTAssertNil(try route(snap, context: unfenced))
    }
    func testPrivateFieldsNeverEnterDisplayOrSourceSelection() throws {
        let snap = snapshot([row(["phone": .string("private"), "accessToken": .string("private")])])
        let sanitized = try ClubGovernanceValidation.validate(snap.value, operation: .feed, scope: .init())
        let accepted = ClubGovernanceSnapshot(operation: .feed, scope: .init(), permissions: nil, value: sanitized)
        XCTAssertEqual(sanitized["rows"].array?.first?["phone"], .null)
        XCTAssertNotNil(try route(accepted))
    }
}

private actor SuspendedGovernanceFeedTransport: HTTPTransport {
    private var completion: CheckedContinuation<(Data, Int), Error>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return try await withCheckedThrowingContinuation { completion = $0; started?.resume(); started = nil }
    }
    func waitForRequest() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(code: Int = 200, status: Int = 200) throws {
        let data = try JSONEncoder().encode(ClubGovernanceValue.object(["code": .integer(code), "data": ClubGovernanceFixtures.value(.feed)]))
        let pending = completion; completion = nil; pending?.resume(returning: (data, status))
    }
}
@MainActor private final class GovernanceFeedReadFixture {
    let transport = SuspendedGovernanceFeedTransport()
    var session: ClubGovernanceSession?
    var revision: UInt64 = 1
    var expired: [ClubReadIdentity] = []
    let service: ClubGovernanceService
    lazy var access = ClubGovernanceSessionAccess(service: service, currentSession: { [unowned self] in session },
        viewerRevision: { [unowned self] in revision }, onUnauthorized: { [unowned self] in expired.append($0) })
    init() throws {
        session = try .init(accountID: 701, epoch: 1, token: "synthetic", storageNamespace: "fixture")
        service = ClubGovernanceService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: transport)
    }
    func read(check: @escaping () throws -> Void = {}) -> Task<ClubGovernanceSnapshot, Error> {
        Task { try await access.read(.feed, scope: .init(), options: ["limit": .integer(20)], check: check) }
    }
}
@MainActor final class ClubFeedReadLifecycleTests: XCTestCase {
    private func stale(_ task: Task<ClubGovernanceSnapshot, Error>) async {
        do { _ = try await task.value; XCTFail("Accepted an obsolete feed response") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
    }
    func testExistingFeedRequestIsOneSignedInJSONPostWithLimit() async throws {
        let fixture = try GovernanceFeedReadFixture(), task = fixture.read()
        await fixture.transport.waitForRequest(); try await fixture.transport.finish()
        let snapshot = try await task.value
        XCTAssertEqual(snapshot.operation, .feed); XCTAssertNil(snapshot.permissions)
        let requests = await fixture.transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/api/club/post/feed"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try JSONDecoder().decode([String: ClubGovernanceValue].self, from: XCTUnwrap(request.httpBody)), ["limit": .integer(20)])
    }
    func testLateSuccessAnd401AfterAccountEpochOrLogoutAreRejected() async throws {
        let replacements: [ClubGovernanceSession?] = [nil,
            try .init(accountID: 702, epoch: 1, token: "synthetic"),
            try .init(accountID: 701, epoch: 2, token: "synthetic"),
            try .init(accountID: 701, epoch: 1, token: "replacement")]
        for replacement in replacements {
            for code in [200, 401] {
                let fixture = try GovernanceFeedReadFixture(), task = fixture.read()
                await fixture.transport.waitForRequest(); fixture.session = replacement
                try await fixture.transport.finish(code: code); await stale(task)
                XCTAssertTrue(fixture.expired.isEmpty)
            }
        }
    }
    func testLateSuccessAnd401AfterRevisionABAAndNewerReloadAreRejected() async throws {
        for code in [200, 401] {
            for viewerChange in [true, false] {
                let fixture = try GovernanceFeedReadFixture()
                var generation = 1
                let task = fixture.read { guard generation == 1 else { throw CancellationError() } }
                await fixture.transport.waitForRequest()
                if viewerChange { fixture.revision &+= 2 } else { generation += 1 }
                try await fixture.transport.finish(code: code); await stale(task)
                XCTAssertTrue(fixture.expired.isEmpty)
            }
        }
    }
    func testCancelledReadCannotExpireSessionWhenTransportIgnoresCancellation() async throws {
        let fixture = try GovernanceFeedReadFixture(), task = fixture.read()
        await fixture.transport.waitForRequest(); task.cancel(); try await fixture.transport.finish(code: 401)
        await stale(task); XCTAssertTrue(fixture.expired.isEmpty)
    }
    func testCurrent401StillExpiresOnceForEnvelopeAndHTTP() async throws {
        for status in [200, 401] {
            let fixture = try GovernanceFeedReadFixture(), task = fixture.read()
            await fixture.transport.waitForRequest(); try await fixture.transport.finish(code: 401, status: status)
            do { _ = try await task.value; XCTFail("Accepted current unauthorized response") }
            catch { XCTAssertEqual(error as? ClubGovernanceFailure, .signedOut) }
            XCTAssertEqual(fixture.expired, [try XCTUnwrap(fixture.session).identity])
        }
    }
}
