import XCTest
@testable import QuestifyCore

final class ClubStatsOverviewTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81)
    private func context(operation: ClubGovernanceRead = .stats, clubID: Int = 81, signedIn: Bool = true) -> ClubGovernanceReadContext {
        .init(operation: operation, scope: .init(clubID: clubID), identity: .init(accountID: signedIn ? 701 : nil, epoch: 1), viewerRevision: 1, authorizationGeneration: nil)
    }
    private func permissions(owner: Bool) throws -> ClubGovernancePermissions {
        try .init(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
            "roleCodes": .array(owner ? [.string("CLUB_OWNER")] : [.string("CLUB_OPERATOR")]), "permissions": .array([])]), scope: scope)
    }
    private func project(_ id: Int) -> ClubGovernanceValue {
        .object(["topicId": .integer(id), "name": .string(" Project \(id) "), "participants": .integer(4),
                 "completed": .integer(1), "completionRate": .decimal(30.5)])
    }
    private func value() -> [String: ClubGovernanceValue] {
        ["clubId": .integer(81), "topicCount": .integer(20), "participants": .integer(10),
         "completed": .integer(3), "overallRate": .decimal(42.6), "topics": .array([project(91)])]
    }
    private func snapshot(_ fields: [String: ClubGovernanceValue]? = nil, owner: Bool = true) throws -> ClubGovernanceSnapshot {
        .init(operation: .stats, scope: scope, permissions: try permissions(owner: owner), value: .object(fields ?? value()))
    }
    private func overview(_ fields: [String: ClubGovernanceValue]? = nil) throws -> ClubStatsOverview {
        try .init(snapshot: snapshot(fields), context: context())
    }
    func testExactSourceMetricsAndRateNeverRecomputedFromCounts() throws {
        let result = try overview()
        XCTAssertEqual(result.topicCount, 20); XCTAssertEqual(result.participants, 10); XCTAssertEqual(result.completed, 3)
        XCTAssertEqual(result.completion, .percentage(42.6), "Not 3 / 10")
        XCTAssertEqual(result.projects[0].completion, .percentage(30.5), "Not 1 / 4")
    }
    func testFirstFivePreserveSourceOrderAndTotalIsNotDerivedFromRows() throws {
        var fields = value(); fields["topics"] = .array([8, 4, 9, 1, 6, 3, 2].map(project))
        let result = try overview(fields)
        XCTAssertEqual(result.projects.map(\.id), [8, 4, 9, 1, 6])
        XCTAssertEqual(result.topicCount, 20); XCTAssertTrue(result.hasMoreProjects)
    }
    func testEmptyTopicsIsAnExplicitEmptyListNotUnknownOrFailure() throws {
        var fields = value(); fields["topics"] = .array([]); fields["topicCount"] = .integer(0)
        let result = try overview(fields)
        XCTAssertTrue(result.projects.isEmpty); XCTAssertEqual(result.topicCount, 0); XCTAssertFalse(result.hasMoreProjects)
    }
    func testMissingNullBoolNegativeFractionalAndUnsafeCountsStayUnknown() throws {
        for bad in [ClubGovernanceValue.null, .bool(false), .integer(-1), .decimal(1.5), .string(""), .string("bad"), .decimal(.infinity), .integer(9_007_199_254_740_992)] {
            var fields = value(); fields["topicCount"] = bad; fields["participants"] = bad; fields["completed"] = bad
            let result = try overview(fields)
            XCTAssertNil(result.topicCount); XCTAssertNil(result.participants); XCTAssertNil(result.completed)
            XCTAssertEqual(result.completion, .unknown)
        }
        var fields = value(); fields.removeValue(forKey: "participants")
        XCTAssertEqual(try overview(fields).completion, .unknown)
    }
    func testKnownZeroCountsStayZeroAndRateIsNotApplicable() throws {
        var fields = value(); fields["participants"] = .integer(0); fields["completed"] = .integer(0); fields["overallRate"] = .null
        let result = try overview(fields)
        XCTAssertEqual(result.participants, 0); XCTAssertEqual(result.completed, 0)
        XCTAssertEqual(result.completion, .noParticipants)
        fields["participants"] = .integer(2); fields["overallRate"] = .integer(0)
        XCTAssertEqual(try overview(fields).completion, .percentage(0))
    }
    func testMissingOrOutOfRangePercentageIsUnknownDespiteKnownCounts() throws {
        for bad in [ClubGovernanceValue.null, .bool(true), .integer(-1), .decimal(100.1), .decimal(.nan), .string(""), .string("bad")] {
            var fields = value(); fields["overallRate"] = bad
            XCTAssertEqual(try overview(fields).completion, .unknown)
        }
        XCTAssertEqual(ClubStatsCompletion(participants: -1, sourceRate: .integer(50)), .unknown)
    }
    func testNumericStringsAndIntegralNumbersRemainMeasuredValues() throws {
        var fields = value(); fields["participants"] = .string("12"); fields["completed"] = .decimal(2)
        fields["topicCount"] = .string("0"); fields["overallRate"] = .string("16.7")
        let result = try overview(fields)
        XCTAssertEqual(result.participants, 12); XCTAssertEqual(result.completed, 2)
        XCTAssertEqual(result.topicCount, 0); XCTAssertEqual(result.completion, .percentage(16.7))
    }
    func testProjectUnknownValuesAndBlankNameDoNotInventFallbackMetrics() throws {
        var fields = value(); fields["topics"] = .array([.object(["topicId": .integer(91), "name": .string(" \n "), "completionRate": .integer(90)])])
        let project = try XCTUnwrap(overview(fields).projects.first)
        XCTAssertNil(project.name); XCTAssertNil(project.participants); XCTAssertNil(project.completed)
        XCTAssertEqual(project.completion, .unknown)
        XCTAssertEqual(try overview().projects[0].name, "Project 91")
    }
    func testWrongOperationClubGuestAndMissingOwnerPermissionCannotProject() throws {
        let source = try snapshot()
        for context in [context(operation: .topics), context(clubID: 82), context(signedIn: false)] {
            XCTAssertThrowsError(try ClubStatsOverview(snapshot: source, context: context))
        }
        XCTAssertThrowsError(try ClubStatsOverview(snapshot: snapshot(owner: false), context: context()))
        let missing = ClubGovernanceSnapshot(operation: .stats, scope: scope, permissions: nil, value: .object(value()))
        XCTAssertThrowsError(try ClubStatsOverview(snapshot: missing, context: context()))
    }
    func testWrongClubMissingTopicListAndContradictoryProjectFail() throws {
        for altered in ["clubId": ClubGovernanceValue.integer(82), "topics": .null] {
            var fields = value(); fields[altered.key] = altered.value
            XCTAssertThrowsError(try overview(fields))
        }
        var fields = value(); fields["topics"] = .array([.object(["topicId": .integer(91), "clubId": .integer(82)])])
        XCTAssertThrowsError(try overview(fields))
    }
    func testDuplicateOrInvalidRowsAreValidatedEvenBeyondVisibleFive() throws {
        var fields = value(); fields["topics"] = .array([1, 2, 3, 4, 5, 1].map(project))
        XCTAssertThrowsError(try overview(fields))
        fields["topics"] = .array([1, 2, 3, 4, 5].map(project) + [.object(["topicId": .integer(0)])])
        XCTAssertThrowsError(try overview(fields))
        fields["topics"] = .array([.null]); XCTAssertThrowsError(try overview(fields))
    }
    func testExistingStatsContractAndRequiredFieldValidationRemainAuthoritative() throws {
        XCTAssertEqual(ClubGovernanceRead.stats.path, "api/stats/club")
        XCTAssertEqual(ClubGovernanceRead.stats.permission, "OWNER")
        XCTAssertEqual(try ClubGovernanceRead.stats.fields(scope: scope), ["clubId": .integer(81)])
        var fields = value(); fields.removeValue(forKey: "participants")
        XCTAssertThrowsError(try ClubGovernanceValidation.validate(.object(fields), operation: .stats, scope: scope))
        XCTAssertNoThrow(try ClubGovernanceValidation.validate(.object(value()), operation: .stats, scope: scope))
    }
}
