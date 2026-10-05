import XCTest
@testable import QuestifyCore

@MainActor private final class PublisherEvidenceTopics: TopicReading {
    var isConfigured = true
    var isOfflineExample = false
    var scope = UUID()
    var body = PublisherSourceAuthorityTests.topicJSON
    var reads = 0
    var beforeReturn: (() -> Void)?
    func topicList(query: TopicQuery, pageNumber: Int) async throws -> TopicPage { throw PublisherLifecycleError.unavailable }
    func topicDetail(id: Int) async throws -> TopicDetail {
        reads += 1; beforeReturn?()
        return try JSONDecoder().decode(TopicDetail.self, from: Data(body.utf8))
    }
}
@MainActor private final class PublisherEvidenceClubs: ClubReading {
    var isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 7, epoch: 1)
    var ownedBody = "[]"
    var detailBodies: [Int: String] = [:]
    var ownedReads = 0
    var detailReads = 0
    var beforeOwnedReturn: (() -> Void)?
    var beforeDetailReturn: (() -> Void)?
    var failure: Error?
    func clubHome() async throws -> ClubHome { throw PublisherLifecycleError.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { XCTFail("Directory is never transfer eligibility"); return [] }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw PublisherLifecycleError.unavailable }
    func clubOwned() async throws -> [ClubRecord] {
        ownedReads += 1; beforeOwnedReturn?()
        if let failure { throw failure }
        return try JSONDecoder().decode([ClubRecord].self, from: Data(ownedBody.utf8))
    }
    func clubDetail(id: Int) async throws -> ClubRecord {
        detailReads += 1; beforeDetailReturn?()
        guard let body = detailBodies[id] else { throw PublisherLifecycleError.unavailable }
        return try JSONDecoder().decode(ClubRecord.self, from: Data(body.utf8))
    }
}
@MainActor final class PublisherSourceAuthorityTests: XCTestCase {
    static let topicJSON = #"{"id":4,"name":"Route","isOwner":1,"betaFlag":1,"productType":1,"lifecycle":null,"selfPlay":1,"selfPlayPrice":30,"storyLocked":false,"totalChapterCount":1,"unlockedChapterCount":1,"chaptersList":[{"id":2,"title":"Chapter","nodes":[{"id":3,"name":"Stop","description":"Original","cmsMemberTemplate":{"id":20,"title":"Task","duration":15}}]}],"omsTicketList":[{"id":5,"name":"Ticket","price":20,"totalInventory":30,"remainingInventory":20,"refundRule":"Before start"}]}"#
    static let activityJSON = #"{"id":8,"memberId":7,"name":"Event","status":0,"publishStatus":1,"cancelTime":null,"cancelReason":null,"omsTicketList":[{"id":9,"name":"Ticket","price":10,"remainingInventory":20,"description":"Ticket terms"}]}"#

    private func session(role: String = "player") -> PublishingSession {
        PublishingSession(namespace: "fixture", accountID: 7, epoch: UUID(), role: role, region: .china)
    }
    private func topic(_ raw: String) throws -> TopicDetail { try JSONDecoder().decode(TopicDetail.self, from: Data(raw.utf8)) }
    private func activity(_ raw: String) throws -> ActivityDetailAccess { try JSONDecoder().decode(ActivityDetailAccess.self, from: Data(raw.utf8)) }
    private func mutate(_ raw: String, key: String, value: Any?) throws -> String {
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        body[key] = value
        return String(decoding: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), as: UTF8.self)
    }
    private func reader(_ topics: PublisherEvidenceTopics, _ clubs: PublisherEvidenceClubs,
                        session: PublishingSession,
                        activityBody: String? = nil) -> PublisherSourceAuthorityReader {
        let body = activityBody ?? Self.activityJSON
        return PublisherSourceAuthorityReader(topics: topics, clubs: clubs,
            activityDetail: { _ in try self.activity(body) }, currentSession: { session })
    }
    private func assertFailure(_ expected: PublisherLifecycleError,
                               _ operation: () async throws -> PublisherAuthority,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Missing fail-closed check", file: file, line: line) }
        catch { XCTAssertEqual(error as? PublisherLifecycleError, expected, file: file, line: line) }
    }
    func testMissingOrMalformedOwnerBetaAndIncompleteStoryStayUnavailable() throws {
        for key in ["isOwner", "betaFlag", "chaptersList", "omsTicketList", "totalChapterCount", "storyLocked", "productType"] {
            XCTAssertNil(try topic(mutate(Self.topicJSON, key: key, value: nil)).publisherAuthoritySource, key)
        }
        for key in ["isOwner", "betaFlag"] {
            XCTAssertNil(try topic(mutate(Self.topicJSON, key: key, value: "1")).publisherAuthoritySource)
            XCTAssertNil(try topic(mutate(Self.topicJSON, key: key, value: 2)).publisherAuthoritySource)
        }
        XCTAssertNil(try topic(mutate(Self.topicJSON, key: "storyLocked", value: true)).publisherAuthoritySource)
        XCTAssertNil(try topic(mutate(Self.topicJSON, key: "totalChapterCount", value: 2)).publisherAuthoritySource)
        XCTAssertNil(try topic(mutate(Self.topicJSON, key: "unlockedChapterCount", value: 0)).publisherAuthoritySource)
        XCTAssertNotNil(try topic(mutate(Self.topicJSON, key: "isOwner", value: true)).publisherAuthoritySource)
    }
    func testSourceOwnerProofNeverUsesDisplayDefaultsOrLocalRole() async throws {
        let topics = PublisherEvidenceTopics(), clubs = PublisherEvidenceClubs(), captured = session(role: "club")
        topics.body = try mutate(Self.topicJSON, key: "isOwner", value: 0)
        await assertFailure(.forbidden) { try await self.reader(topics, clubs, session: captured).freshAuthority(PublishedResource(kind: .topic, value: 4), session: captured) }
        topics.body = try mutate(Self.topicJSON, key: "isOwner", value: nil)
        await assertFailure(.unavailable) { try await self.reader(topics, clubs, session: captured).freshAuthority(PublishedResource(kind: .topic, value: 4), session: captured) }
        XCTAssertEqual(clubs.ownedReads, 0)
    }
    func testExactResourceAndFreshReadEveryTime() async throws {
        let topics = PublisherEvidenceTopics(), clubs = PublisherEvidenceClubs(), captured = session()
        let source = reader(topics, clubs, session: captured)
        let resource = try PublishedResource(kind: .topic, value: 4)
        let first = try await source.freshAuthority(resource, session: captured)
        let second = try await source.freshAuthority(resource, session: captured)
        XCTAssertEqual(first, second); XCTAssertEqual(first.ownerAccountID, 7)
        XCTAssertEqual(topics.reads, 2); XCTAssertEqual(clubs.ownedReads, 2)
        XCTAssertFalse(first.revision.isEmpty)
        await assertFailure(.unavailable) { try await source.freshAuthority(PublishedResource(kind: .topic, value: 99), session: captured) }
        await assertFailure(.unavailable) { try await source.freshAuthority(PublishedResource(kind: .template, value: 4), session: captured) }
    }
    func testMyPlusFreshLeadershipOnly() async throws {
        let topics = PublisherEvidenceTopics(), clubs = PublisherEvidenceClubs(), captured = session()
        clubs.ownedBody = #"[{"id":9,"isOwner":true},{"id":10,"isOwner":true},{"id":11}]"#
        clubs.detailBodies = [9: #"{"id":9,"name":"Leader club","isOwner":true}"#,
                              10: #"{"id":10,"viewerIsAdmin":true,"isOwner":false}"#,
                              11: #"{"id":11,"viewerIsAdmin":true}"#]
        let source = reader(topics, clubs, session: captured), resource = try PublishedResource(kind: .topic, value: 4)
        let first = try await source.freshAuthority(resource, session: captured)
        XCTAssertEqual(first.eligibleClubIDs, [9]); XCTAssertEqual(clubs.detailReads, 3)
        clubs.detailBodies[9] = #"{"id":9,"name":"Leader club","isOwner":false}"#
        let second = try await source.freshAuthority(resource, session: captured)
        XCTAssertTrue(second.eligibleClubIDs.isEmpty); XCTAssertNotEqual(first, second)
    }
    func testClubReadFailureAndMismatchedIdentityNeverBecomeEmptyProof() async throws {
        let topics = PublisherEvidenceTopics(), clubs = PublisherEvidenceClubs(), captured = session()
        let source = reader(topics, clubs, session: captured), resource = try PublishedResource(kind: .topic, value: 4)
        clubs.failure = PublisherLifecycleError.unavailable
        await assertFailure(.unavailable) { try await source.freshAuthority(resource, session: captured) }
        clubs.failure = nil; clubs.ownedBody = #"[{"id":9}]"#; clubs.detailBodies[9] = #"{"id":10,"isOwner":true}"#
        await assertFailure(.unavailable) { try await source.freshAuthority(resource, session: captured) }
        clubs.clubIdentity = .init(accountID: 42, epoch: 1)
        await assertFailure(.unavailable) { try await source.freshAuthority(resource, session: captured) }
    }
    func testSessionAndReaderEpochChangesInvalidateInFlightAuthority() async throws {
        let topics = PublisherEvidenceTopics(), clubs = PublisherEvidenceClubs(), captured = session()
        var current: PublishingSession? = captured
        let source = PublisherSourceAuthorityReader(topics: topics, clubs: clubs,
            activityDetail: { _ in try self.activity(Self.activityJSON) }, currentSession: { current })
        let resource = try PublishedResource(kind: .topic, value: 4)
        topics.beforeReturn = { current = self.session() }
        await assertFailure(.stale) { try await source.freshAuthority(resource, session: captured) }
        current = captured; topics.beforeReturn = nil
        clubs.beforeOwnedReturn = { topics.scope = UUID() }
        await assertFailure(.stale) { try await source.freshAuthority(resource, session: captured) }
        clubs.beforeOwnedReturn = nil; clubs.ownedBody = #"[{"id":9}]"#; clubs.detailBodies[9] = #"{"id":9,"isOwner":true}"#
        clubs.beforeDetailReturn = { clubs.clubIdentity = .init(accountID: 7, epoch: 2) }
        await assertFailure(.stale) { try await source.freshAuthority(resource, session: captured) }
    }
    func testFingerprintIgnoresVolatileDataButKeepsTermsContentDatesAndPrices() async throws {
        let topics = PublisherEvidenceTopics(), clubs = PublisherEvidenceClubs(), captured = session()
        let source = reader(topics, clubs, session: captured), resource = try PublishedResource(kind: .topic, value: 4)
        let original = try await source.freshAuthority(resource, session: captured)
        topics.body = try mutate(Self.topicJSON, key: "viewCount", value: 999)
        topics.body = try mutate(topics.body, key: "updateTime", value: "2030-01-01")
        topics.body = try mutate(topics.body, key: "isSignUp", value: 1)
        topics.body = topics.body.replacingOccurrences(of: #""remainingInventory":20"#, with: #""remainingInventory":19"#)
        let volatile = try await source.freshAuthority(resource, session: captured)
        XCTAssertEqual(original, volatile)
        for (key, value) in [("selfPlayPrice", 31 as Any), ("betaFlag", 0 as Any), ("lifecycle", 2 as Any), ("startDate", "2030-02-01" as Any)] {
            topics.body = try mutate(Self.topicJSON, key: key, value: value)
            let changed = try await source.freshAuthority(resource, session: captured)
            XCTAssertNotEqual(original.revision, changed.revision, key)
        }
        for (old, new) in [("Original", "New content"), ("Before start", "No refunds"), (#""price":20"#, #""price":25"#), (#""totalInventory":30"#, #""totalInventory":40"#)] {
            topics.body = Self.topicJSON.replacingOccurrences(of: old, with: new)
            let changed = try await source.freshAuthority(resource, session: captured)
            XCTAssertNotEqual(original.revision, changed.revision, old)
        }
    }
    func testClubOrderDoesNotChangeFingerprintButEligibleNameDoes() async throws {
        let topics = PublisherEvidenceTopics(), clubs = PublisherEvidenceClubs(), captured = session()
        clubs.ownedBody = #"[{"id":9},{"id":10}]"#
        clubs.detailBodies = [9: #"{"id":9,"name":"A","isOwner":true}"#, 10: #"{"id":10,"name":"B","isOwner":true}"#]
        let source = reader(topics, clubs, session: captured), resource = try PublishedResource(kind: .topic, value: 4)
        let original = try await source.freshAuthority(resource, session: captured)
        clubs.ownedBody = #"[{"id":10},{"id":9}]"#
        let reordered = try await source.freshAuthority(resource, session: captured)
        XCTAssertEqual(original, reordered)
        clubs.detailBodies[9] = #"{"id":9,"name":"New A","isOwner":true}"#
        let renamed = try await source.freshAuthority(resource, session: captured)
        XCTAssertNotEqual(original, renamed)
    }
    func testOfflineSourceDuplicateCandidatesAndWrongActivityCannotAuthorize() async throws {
        let topics = PublisherEvidenceTopics(), clubs = PublisherEvidenceClubs(), captured = session()
        let source = reader(topics, clubs, session: captured), resource = try PublishedResource(kind: .topic, value: 4)
        topics.isOfflineExample = true
        await assertFailure(.unavailable) { try await source.freshAuthority(resource, session: captured) }
        topics.isOfflineExample = false
        clubs.ownedBody = #"[{"id":9},{"id":9}]"#; clubs.detailBodies[9] = #"{"id":9,"isOwner":true}"#
        await assertFailure(.unavailable) { try await source.freshAuthority(resource, session: captured) }
        await assertFailure(.unavailable) { try await source.freshAuthority(PublishedResource(kind: .activity, value: 99), session: captured) }
        XCTAssertNil(try topic(mutate(Self.topicJSON, key: "betaFlag", value: true)).publisherAuthoritySource)
    }
    func testActivityRequiresExactRealOwnerAndCompleteCancellationState() async throws {
        let topics = PublisherEvidenceTopics(), clubs = PublisherEvidenceClubs(), captured = session()
        let resource = try PublishedResource(kind: .activity, value: 8)
        let original = try await reader(topics, clubs, session: captured).freshAuthority(resource, session: captured)
        XCTAssertEqual(original.ownerAccountID, 7); XCTAssertFalse(original.beta)
        XCTAssertEqual(topics.reads, 0); XCTAssertEqual(clubs.ownedReads, 0)
        for key in ["memberId", "status", "publishStatus", "omsTicketList"] {
            let raw = try mutate(Self.activityJSON, key: key, value: nil)
            await assertFailure(.unavailable) { try await self.reader(topics, clubs, session: captured, activityBody: raw).freshAuthority(resource, session: captured) }
        }
        let wrongOwner = try mutate(Self.activityJSON, key: "memberId", value: 99)
        await assertFailure(.forbidden) { try await self.reader(topics, clubs, session: captured, activityBody: wrongOwner).freshAuthority(resource, session: captured) }
        await assertFailure(.unavailable) { try await self.reader(topics, clubs, session: captured, activityBody: #"{"gate":true,"clubId":9}"#).freshAuthority(resource, session: captured) }
        let cancelled = try mutate(Self.activityJSON, key: "cancelReason", value: "Weather")
        let changed = try await reader(topics, clubs, session: captured, activityBody: cancelled).freshAuthority(resource, session: captured)
        XCTAssertNotEqual(original.revision, changed.revision)
    }
}
