import XCTest
@testable import QuestifyCore

final class ClubRosterPresentationTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81, activityID: 205)
    private func context(identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)) -> ClubGovernanceReadContext {
        .init(operation: .roster, scope: scope, identity: identity, viewerRevision: 0, authorizationGeneration: nil)
    }
    private func member(_ id: Int, version: ClubGovernanceValue = .integer(4)) -> ClubGovernanceValue {
        .object(["memberId": .integer(id), "nickname": .string(" Same "), "correctionVersion": version, "state": .string("WAITING"), "phone": .string("not-rendered")])
    }
    private func snapshot(_ changes: [String: ClubGovernanceValue] = [:], allowed: Bool = true) throws -> ClubGovernanceSnapshot {
        let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
            "roleCodes": .array([]), "permissions": .array(allowed ? [.string("club:event:checkin")] : []), "canManageRoles": .bool(false)]), scope: scope)
        var value: [String: ClubGovernanceValue] = ["phoneIncluded": .bool(false), "registered": .array([member(41), member(42)]),
            "waitlist": .array([member(51)]), "arrived": .array([member(61)]), "noShow": .array([])]
        value.merge(changes) { _, new in new }
        return .init(operation: .roster, scope: scope, permissions: permissions, value: .object(value))
    }
    private func presentation(_ changes: [String: ClubGovernanceValue] = [:]) throws -> ClubRosterPresentation {
        try .init(snapshot: snapshot(changes), context: context())
    }
    func testFourBucketsAndTotalExcludeWaitlist() throws {
        let value = try presentation()
        XCTAssertEqual(ClubRosterBucket.allCases.map(\.rawValue), ["registered", "waitlist", "arrived", "noShow"])
        XCTAssertEqual(value.rosterTotal, 3); XCTAssertEqual(value.count(in: .waitlist), 1)
        XCTAssertEqual(value.members(in: .registered).map(\.id), [41, 42]); XCTAssertTrue(value.members(in: .noShow).isEmpty)
    }
    func testNamesAreTrimmedAndWaitlistStateOnlyBelongsToWaitlist() throws {
        let value = try presentation()
        XCTAssertEqual(value.members(in: .registered).first?.nickname, "Same")
        XCTAssertNil(value.members(in: .registered).first?.waitlistState)
        XCTAssertEqual(value.members(in: .waitlist).first?.waitlistState, "WAITING")
    }
    func testMissingBucketAndPrivacyFlagCannotBecomeEmptySuccess() {
        XCTAssertThrowsError(try presentation(["registered": .null]))
        XCTAssertThrowsError(try presentation(["phoneIncluded": .null]))
        XCTAssertThrowsError(try presentation(["phoneIncluded": .bool(true)]))
    }
    func testDuplicateInvalidAndCrossScopeMembersFail() {
        let bad: [ClubGovernanceValue] = [.null, .object(["id": .integer(41)]), .object(["memberId": .integer(0)]),
            .object(["memberId": .integer(41), "clubId": .integer(82)]), .object(["memberId": .integer(41), "activityId": .integer(206)])]
        for row in bad { XCTAssertThrowsError(try presentation(["registered": .array([row])])) }
        XCTAssertThrowsError(try presentation(["registered": .array([member(41), member(41)])]))
    }
    func testFreshPermissionAndSignedInExactScopeRequired() throws {
        XCTAssertThrowsError(try ClubRosterPresentation(snapshot: snapshot(allowed: false), context: context()))
        XCTAssertThrowsError(try ClubRosterPresentation(snapshot: snapshot(), context: context(identity: nil)))
        let wrong = ClubGovernanceReadContext(operation: .roster, scope: .init(clubID: 81, activityID: 206), identity: context().identity, viewerRevision: 0, authorizationGeneration: nil)
        XCTAssertThrowsError(try ClubRosterPresentation(snapshot: snapshot(), context: wrong))
    }
    func testUnknownCorrectionVersionNeverDefaultsToZero() throws {
        let value = try presentation(["registered": .array([member(41, version: .null)])])
        XCTAssertNil(value.members(in: .registered).first?.correctionVersion)
        XCTAssertNil(value.correctionRoute(memberID: 41, bucket: .registered, context: context(), snapshotGeneration: 1, namespace: "n"))
        XCTAssertThrowsError(try presentation(["registered": .array([member(41, version: .integer(-1))])]))
    }
    func testWaitlistCannotAcquireCorrectionEvenWithKnownVersion() throws {
        XCTAssertNil(try presentation().correctionRoute(memberID: 51, bucket: .waitlist, context: context(), snapshotGeneration: 1, namespace: "n"))
    }
    func testServerClosedWindowBlocksEntriesAndKeepsKnownBoundsOnly() throws {
        let value = try presentation(["correctionWindow": .object(["operable": .bool(false), "startAt": .string("2026-10-11 09:00:00")])])
        XCTAssertEqual(value.correctionOperable, false); XCTAssertEqual(value.correctionStart, "2026-10-11 09:00:00"); XCTAssertNil(value.correctionEnd)
        XCTAssertNil(value.correctionRoute(memberID: 41, bucket: .registered, context: context(), snapshotGeneration: 1, namespace: "n"))
    }
    func testUnknownWindowDoesNotInventBlockOrBoundsAndKnownZeroVersionIsUsable() throws {
        let value = try presentation(["registered": .array([member(41, version: .integer(0))]), "correctionWindow": .object(["operable": .string("false"), "startAt": .string("ignored")])])
        XCTAssertNil(value.correctionOperable); XCTAssertNil(value.correctionStart)
        XCTAssertEqual(value.correctionRoute(memberID: 41, bucket: .registered, context: context(), snapshotGeneration: 1, namespace: "n")?.version, 0)
    }
    func testCurrentRouteUsesExactMemberActivityVersionAndNamespace() throws {
        let snapshot = try self.snapshot(), expected = context(), value = try ClubRosterPresentation(snapshot: snapshot, context: expected)
        let route = try XCTUnwrap(value.correctionRoute(memberID: 41, bucket: .registered, context: expected, snapshotGeneration: 3, namespace: "n"))
        XCTAssertEqual(route.scope, .init(clubID: 81, activityID: 205, memberID: 41)); XCTAssertEqual(route.version, 4)
        XCTAssertTrue(route.isCurrent(snapshot: snapshot, context: expected, snapshotGeneration: 3, namespace: "n"))
        XCTAssertFalse(route.isCurrent(snapshot: snapshot, context: expected, snapshotGeneration: 4, namespace: "n"))
        XCTAssertFalse(route.isCurrent(snapshot: snapshot, context: expected, snapshotGeneration: 3, namespace: "other"))
        XCTAssertFalse(route.isCurrent(snapshot: nil, context: expected, snapshotGeneration: 3, namespace: "n"))
    }
    func testOldSourceCannotMintRouteForNewAccountOrForgeRowInAnotherBucket() throws {
        let value = try presentation()
        XCTAssertNil(value.correctionRoute(memberID: 41, bucket: .registered, context: context(identity: .init(accountID: 702, epoch: 2)), snapshotGeneration: 1, namespace: "n"))
        XCTAssertNil(value.correctionRoute(memberID: 41, bucket: .arrived, context: context(), snapshotGeneration: 1, namespace: "n"))
    }
    func testChangedRosterInvalidatesPriorRouteEvenWithSameCounter() throws {
        let value = try presentation(), route = try XCTUnwrap(value.correctionRoute(memberID: 41, bucket: .registered, context: context(), snapshotGeneration: 1, namespace: "n"))
        XCTAssertFalse(route.isCurrent(snapshot: try snapshot(["registered": .array([member(41, version: .integer(5))])]), context: context(), snapshotGeneration: 1, namespace: "n"))
    }
}
