import XCTest
@testable import QuestifyCore

final class ThemeSeasonReleaseTests: XCTestCase {
    private let hashA = String(repeating: "a", count: 64), hashB = String(repeating: "b", count: 64)
    private func release(_ id: String, version: Int64, hash: String?, status: String) throws -> ThemeReleaseRef {
        let hashField = hash.map { ",\"contentHash\":\"\($0)\"" } ?? ""
        return try JSONDecoder().decode(ThemeReleaseRef.self, from: Data("{\"themeId\":\"theme-1\",\"releaseId\":\"\(id)\",\"version\":\(version),\"schemaVersion\":1,\"status\":\"\(status)\"\(hashField)}".utf8))
    }

    func testCapabilitiesAreAllDisabledByDefault() {
        for feature in ReformWorldCapabilities.Feature.allCases { XCTAssertFalse(ReformWorldCapabilities.disabled.allows(feature)) }
        XCTAssertFalse(ReformWorldCapabilities.syntheticFixture(Set(ReformWorldCapabilities.Feature.allCases)).allows(.meetingNFC))
    }

    func testSeasonAndReleaseTransitionsAreForwardOnly() {
        XCTAssertTrue(SeasonLifecycle.active.canAdvance(to: .ended))
        XCTAssertFalse(SeasonLifecycle.ended.canAdvance(to: .active))
        XCTAssertFalse(SeasonLifecycle.ended.acceptsNewSeasonScore)
        XCTAssertTrue(ThemeReleaseStatus.review.canAdvance(to: .draft))
        XCTAssertFalse(ThemeReleaseStatus.published.canAdvance(to: .draft))
        XCTAssertFalse(ThemeReleaseStatus.retired.canAdvance(to: .published))
    }

    func testApprovedReleaseRequiresHashAndDraftMustNotCarryOne() throws {
        XCTAssertThrowsError(try release("r1", version: 1, hash: nil, status: "PUBLISHED").validate())
        XCTAssertThrowsError(try release("r1", version: 1, hash: hashA, status: "DRAFT").validate())
        XCTAssertThrowsError(try release("r1", version: 1, hash: "A" + String(hashA.dropFirst()), status: "PUBLISHED").validate())
        XCTAssertNoThrow(try release("r1", version: 1, hash: hashA, status: "PUBLISHED").validate())
    }

    func testRunStaysPinnedWhenNewReleasePublishes() throws {
        let pin = try RunReleasePin(runId: "run-1", release: release("r1", version: 1, hash: hashA, status: "PUBLISHED"))
        XCTAssertEqual(try pin.reconcile(current: release("r1", version: 1, hash: hashA, status: "PUBLISHED")), .unchanged)
        let newer = try release("r2", version: 2, hash: hashB, status: "PUBLISHED")
        XCTAssertEqual(try pin.reconcile(current: newer), .newerReleaseForNewRuns(newer))
        XCTAssertEqual(pin.releaseId, "r1")
        XCTAssertEqual(try pin.reconcile(current: release("r1", version: 1, hash: hashA, status: "RETIRED")), .retiredForNewRuns)
    }

    func testSameReleaseWithDifferentBytesIsDrift() throws {
        let pin = try RunReleasePin(runId: "run-1", release: release("r1", version: 1, hash: hashA, status: "PUBLISHED"))
        XCTAssertThrowsError(try pin.reconcile(current: release("r1", version: 1, hash: hashB, status: "PUBLISHED"))) { XCTAssertEqual($0 as? ThemeReleaseIssue, .drift) }
        XCTAssertThrowsError(try pin.reconcile(current: release("r0", version: 1, hash: hashB, status: "PUBLISHED"))) { XCTAssertEqual($0 as? ThemeReleaseIssue, .drift) }
        XCTAssertThrowsError(try RunReleasePin(runId: "run-2", release: release("r3", version: 3, hash: hashA, status: "APPROVED")))
    }

    func testSeasonValidationUsesRealZoneAndOrderedWindow() throws {
        func season(_ zone: String, start: Int64, end: Int64) throws -> SeasonRef {
            try JSONDecoder().decode(SeasonRef.self, from: Data("{\"seasonId\":\"s1\",\"worldId\":\"w1\",\"code\":\"S1\",\"timezone\":\"\(zone)\",\"rulesVersion\":\"v1\",\"startsAt\":\(start),\"endsAt\":\(end),\"lifecycle\":\"ACTIVE\"}".utf8))
        }
        XCTAssertNoThrow(try season("Asia/Shanghai", start: 1, end: 2).validate())
        XCTAssertThrowsError(try season("Mars/Base", start: 1, end: 2).validate())
        XCTAssertThrowsError(try season("Asia/Shanghai", start: 2, end: 2).validate())
    }

    func testCrossOwnerAndCrossWorldEditsAreRefused() throws {
        let owner = try JSONDecoder().decode(ContentOwnership.self, from: Data("{\"ownerKind\":\"MERCHANT\",\"ownerId\":\"m1\",\"worldId\":\"w1\"}".utf8))
        XCTAssertNoThrow(try owner.permitsEdit(actorKind: .merchant, actorId: "m1", worldId: "w1"))
        XCTAssertThrowsError(try owner.permitsEdit(actorKind: .merchant, actorId: "m2", worldId: "w1"))
        XCTAssertThrowsError(try owner.permitsEdit(actorKind: .merchant, actorId: "m1", worldId: "w2"))
        XCTAssertThrowsError(try owner.permitsEdit(actorKind: .platform, actorId: "m1", worldId: "w1"))
    }
}
