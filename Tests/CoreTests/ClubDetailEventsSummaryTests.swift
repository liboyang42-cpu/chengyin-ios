import XCTest
@testable import QuestifyCore

final class ClubDetailEventsSummaryTests: XCTestCase {
    private final class AccessToken {}
    private let token = AccessToken()
    private let generation = UUID()
    private let now = Date(timeIntervalSince1970: 1_791_691_200) // 2026-10-11 12:00:00 +0800

    private func context(
        operation: ClubGovernanceRead = .topics,
        clubID: Int? = 81,
        identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1),
        viewerRevision: UInt64 = 1,
        authorizationGeneration: UUID? = nil,
        accessIdentity: ObjectIdentifier? = nil
    ) -> ClubGovernanceReadContext {
        .init(
            operation: operation,
            scope: .init(clubID: clubID),
            identity: identity,
            viewerRevision: viewerRevision,
            authorizationGeneration: authorizationGeneration ?? generation,
            accessIdentity: accessIdentity ?? ObjectIdentifier(token)
        )
    }

    private func makeOverview(
        _ rows: [ClubGovernanceValue],
        club: Int = 81,
        active: Bool = true,
        readContext: ClubGovernanceReadContext? = nil
    ) throws -> ClubActivityOverview {
        let scope = ClubGovernanceScope(clubID: club)
        let permissions = try ClubGovernancePermissions(
            value: .object([
                "active": .bool(active),
                "club": .object(["id": .integer(club)]),
                "roleCodes": .array([]),
                "permissions": .array([])
            ]),
            scope: scope
        )
        let snapshot = ClubGovernanceSnapshot(operation: .topics, scope: scope, permissions: permissions, value: .array(rows))
        return try .init(snapshot: snapshot, context: readContext ?? context(clubID: club), now: now)
    }

    private func row(_ id: Int, clubID: Int = 81, _ fields: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        .object(["id": .integer(id), "clubId": .integer(clubID), "name": .string("Synthetic activity \(id)")].merging(fields) { _, new in new })
    }

    func testNoOverviewAndNoFailureIsLoading() {
        XCTAssertEqual(ClubDetailEventsSummary(overview: nil, failure: nil, loading: true).state, .loading)
        XCTAssertEqual(ClubDetailEventsSummary(overview: nil, failure: nil, loading: false).state, .loading)
        XCTAssertEqual(ClubDetailEventsSummary(state: .loading).state, .loading)
    }

    func testFailuresAreIsolatedAndMapToExistingKeys() throws {
        XCTAssertEqual(ClubDetailEventsSummary(overview: nil, failure: .forbidden, loading: false).state, .failed(localizationKey: "club.gov.denied"))
        XCTAssertEqual(ClubDetailEventsSummary(overview: nil, failure: .signedOut, loading: false).state, .failed(localizationKey: "club.gov.signedOut"))
        XCTAssertEqual(ClubDetailEventsSummary(overview: nil, failure: .malformed, loading: false).state, .failed(localizationKey: "club.gov.malformed"))
        XCTAssertEqual(ClubDetailEventsSummary(overview: nil, failure: .notConfigured, loading: false).state, .failed(localizationKey: "club.gov.unavailable"))
        XCTAssertEqual(ClubDetailEventsSummary(overview: nil, failure: .targetChanged, loading: false).state, .failed(localizationKey: "club.gov.changed"))
        let loadedOverview = try makeOverview([row(91, ["startDate": .string("2026-10-12 09:00:00")])])
        XCTAssertEqual(
            ClubDetailEventsSummary(overview: loadedOverview, failure: .forbidden, loading: false).state,
            .failed(localizationKey: "club.gov.denied"),
            "A read failure must never mix with stale loaded rows"
        )
    }

    func testUpcomingLimitIsThree() { XCTAssertEqual(ClubDetailEventsSummary.upcomingLimit, 3) }

    func testEmptyAuthorizedOverviewProjectsEmptyState() throws {
        let expected = context()
        let emptyOverview = try makeOverview([], readContext: expected)
        XCTAssertTrue(emptyOverview.rows.isEmpty)
        XCTAssertTrue(emptyOverview.current.isEmpty)
        XCTAssertTrue(emptyOverview.ended.isEmpty)
        XCTAssertEqual(ClubDetailEventsSummary(overview: emptyOverview, failure: nil, loading: false).state, .empty)
        XCTAssertEqual(
            ClubDetailEventsSummary(
                overview: emptyOverview,
                acceptedContext: expected,
                expectedContext: expected,
                failure: nil,
                loading: false
            ).state,
            .empty
        )
    }

    func testLoadedProjectionCountsCurrentAndEndedAndCapsUpcomingAtThreeInSourceOrder() throws {
        let expected = context()
        let populated = try makeOverview([
            row(91, ["name": .string("Ended yesterday"), "endDate": .string("2026-10-11 11:59:59")]),
            row(92, ["name": .string("  Morning Run  "), "startDate": .string("2026-10-11 12:00:00")]),
            row(93, ["name": .string("   "), "startDate": .string("2026-10-12 09:00:00")]),
            row(94, ["name": .string("Ended earlier"), "endDate": .string("2026-10-10 18:00:00")]),
            row(95, ["name": .string("City Orienteering"), "startDate": .string("2026-10-13 10:00:00")]),
            row(96, ["name": .string("Fourth Upcoming"), "startDate": .string("2026-10-14 14:00:00")])
        ], readContext: expected)

        let summary = ClubDetailEventsSummary(
            overview: populated,
            acceptedContext: expected,
            expectedContext: expected,
            failure: nil,
            loading: false
        )
        guard case let .loaded(current, ended, upcoming) = summary.state else {
            return XCTFail("Expected .loaded summary state, got \(summary.state)")
        }
        XCTAssertEqual(current, 4)
        XCTAssertEqual(ended, 2)
        XCTAssertEqual(upcoming.count, ClubDetailEventsSummary.upcomingLimit)
        XCTAssertEqual(upcoming.map(\.id), [92, 93, 95])
        XCTAssertEqual(upcoming.map(\.name), ["Morning Run", nil, "City Orienteering"])
        XCTAssertEqual(upcoming.map(\.status), [.live, .recruiting, .recruiting])
    }

    func testEndedOnlyOverviewProjectsLoadedWithZeroCurrentAndEmptyUpcomingRatherThanEmpty() throws {
        let endedOnly = try makeOverview([
            row(91, ["endDate": .string("2026-10-11 11:59:59")]),
            row(92, ["endDate": .string("2026-10-10 08:00:00")])
        ])
        let summary = ClubDetailEventsSummary(overview: endedOnly, failure: nil, loading: false)
        XCTAssertEqual(summary.state, .loaded(current: 0, ended: 2, upcoming: []))
        XCTAssertNotEqual(summary.state, .empty)
    }

    func testScopeAccessAndStaleContextDiscardProjectLoadingWithoutLeakingRows() throws {
        let accepted = context()
        let loadedOverview = try makeOverview([row(91, ["startDate": .string("2026-10-12 09:00:00")])], readContext: accepted)
        let emptyOverview = try makeOverview([], readContext: accepted)
        let otherToken = AccessToken()

        let mismatchedContexts: [ClubGovernanceReadContext] = [
            context(clubID: 82),
            context(identity: .init(accountID: 702, epoch: 1)),
            context(identity: .init(accountID: 701, epoch: 2)),
            context(identity: nil),
            context(identity: .init(accountID: 0, epoch: 1)),
            context(viewerRevision: 2),
            context(authorizationGeneration: UUID()),
            context(accessIdentity: ObjectIdentifier(otherToken)),
            context(operation: .access)
        ]

        for mismatched in mismatchedContexts {
            for candidate in [loadedOverview, emptyOverview] {
                XCTAssertEqual(
                    ClubDetailEventsSummary(
                        overview: candidate,
                        acceptedContext: accepted,
                        expectedContext: mismatched,
                        failure: nil,
                        loading: true
                    ).state,
                    .loading
                )
                XCTAssertEqual(
                    ClubDetailEventsSummary(
                        overview: nil,
                        acceptedContext: accepted,
                        expectedContext: mismatched,
                        failure: .forbidden,
                        loading: true
                    ).state,
                    .loading,
                    "Stale failure from a previous context must not leak across club/account/access switches"
                )
            }
        }

        XCTAssertThrowsError(try makeOverview([row(91, clubID: 82)]))
        XCTAssertThrowsError(try makeOverview([row(91)], club: 81, readContext: context(clubID: 82)))
        XCTAssertThrowsError(try makeOverview([row(91)], active: false))
        XCTAssertThrowsError(try makeOverview([row(91), row(91)]))
    }
}
