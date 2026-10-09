import XCTest
@testable import QuestifyCore

final class MerchantCustomerEmptyRecoveryTests: XCTestCase {
    private func document(_ query: MerchantCustomerQuery = .init(), count: MerchantBusinessValue? = .int(0)) throws -> MerchantBusinessDocument {
        var summary: MerchantBusinessObject = [:]; summary["all"] = count
        return try .init(query: .customers(query), payload: .object(["rows": .array([]), "total": .int(0), "segmentCounts": .object(summary)]))
    }
    private func recovery(_ query: MerchantCustomerQuery = .init(), count: MerchantBusinessValue? = .int(0)) throws -> MerchantCustomerEmptyRecovery {
        try XCTUnwrap(.init(document: document(query, count: count)))
    }
    func testSearchInGroupShowsAllGroupsAndPreservesKeywordAndAdvancedFilters() throws {
        var query = MerchantCustomerQuery(); query.keyword = "Example"; query.segment = "repeat"
        query.tagID = 7; query.sourceType = 1; query.sourceStart = "2026-01-01"; query.sourceEnd = "2026-02-01"
        let state = try recovery(query)
        XCTAssertEqual(state.kind, .searchInGroup); XCTAssertEqual(state.action, .allGroups)
        var expected = query; expected.segment = "all"
        XCTAssertEqual(state.recoveredQuery, expected)
    }
    func testSearchInAllGroupsClearsOnlyKeyword() throws {
        var query = MerchantCustomerQuery(); query.keyword = "Example"; query.tagID = 7; query.sourceType = 2
        let state = try recovery(query)
        XCTAssertEqual(state.kind, .search); XCTAssertEqual(state.action, .clearSearch)
        var expected = query; expected.keyword = ""
        XCTAssertEqual(state.recoveredQuery, expected)
    }
    func testAdvancedFilterEmptyDoesNotMisreportGlobalCountsOrClearGroup() throws {
        var query = MerchantCustomerQuery(); query.segment = "new"; query.tagID = 9
        query.sourceType = 1; query.sourceStart = "2026-01-01"; query.sourceEnd = "2026-02-01"
        let state = try recovery(query, count: .int(500))
        XCTAssertEqual(state.kind, .advanced); XCTAssertEqual(state.action, .clearAdvanced)
        let next = try XCTUnwrap(state.recoveredQuery)
        XCTAssertEqual(next.segment, "new"); XCTAssertEqual(next.keyword, "")
        XCTAssertNil(next.tagID); XCTAssertNil(next.sourceType); XCTAssertNil(next.sourceStart); XCTAssertNil(next.sourceEnd)
        XCTAssertEqual(next.page, 1)
    }
    func testEachAdvancedFieldIndependentlySelectsAdvancedRecovery() throws {
        for key in ["tag", "source", "start", "end"] {
            var query = MerchantCustomerQuery()
            switch key {
            case "tag": query.tagID = 1
            case "source": query.sourceType = 2
            case "start": query.sourceStart = "2026-01-01"
            default: query.sourceEnd = "2026-02-01"
            }
            XCTAssertEqual(try recovery(query).kind, .advanced)
        }
    }
    func testGroupWithoutOtherFiltersRecoversOnlyGroup() throws {
        for group in ["repeat", "new", "noted"] {
            var query = MerchantCustomerQuery(); query.segment = group
            let state = try recovery(query)
            XCTAssertEqual(state.kind, .group); XCTAssertEqual(state.recoveredQuery?.segment, "all")
        }
    }
    func testAbsentNullMalformedAndNegativeCountsRemainUnknownNotZero() throws {
        let values: [MerchantBusinessValue?] = [nil, .null, .bool(false), .string(""), .string("bad"), .int(-1), .array([]), .object([:])]
        for count in values {
            let state = try recovery(count: count)
            XCTAssertEqual(state.kind, .statisticsUnavailable); XCTAssertEqual(state.action, .retry)
            XCTAssertEqual(state.recoveredQuery, state.appliedQuery)
        }
    }
    func testPositiveCurrentCountWithNoRowsOffersReloadInsteadOfClaimingNoCustomers() throws {
        for count in [MerchantBusinessValue.int(3), .string("3"), .number(Decimal(string: "0.5")!)] {
            let state = try recovery(count: count)
            XCTAssertEqual(state.kind, .listUnavailable); XCTAssertEqual(state.action, .retry)
        }
    }
    func testExplicitZeroIsTheOnlyGeneralNoCustomersCase() throws {
        for count in [MerchantBusinessValue.int(0), .string("0")] {
            let state = try recovery(count: count)
            XCTAssertEqual(state.kind, .noCustomers); XCTAssertNil(state.action); XCTAssertNil(state.recoveredQuery)
        }
    }
    func testPopulatedOtherDomainAndLaterPagesDoNotUseFirstPageRecovery() throws {
        let populated = try MerchantBusinessDocument(query: .customers(.init()), payload: MerchantBusinessSyntheticFixtures.payload(.customers(.init())))
        XCTAssertNil(MerchantCustomerEmptyRecovery(document: populated))
        let other = try MerchantBusinessDocument(query: .operators, payload: .object(["operators": .array([]), "invites": .array([])]))
        XCTAssertNil(MerchantCustomerEmptyRecovery(document: other))
        var second = MerchantCustomerQuery(); second.page = 2
        XCTAssertNil(MerchantCustomerEmptyRecovery(document: try document(second)))
    }
    func testUnsubmittedDraftChangesCannotBeDiscardedByRecovery() throws {
        var query = MerchantCustomerQuery(); query.keyword = "Existing"; query.segment = "new"
        let state = try recovery(query)
        XCTAssertTrue(state.matchesDraft(keyword: "Existing", segment: "new", sourceType: 0, tagID: 0, sourceStart: "", sourceEnd: ""))
        XCTAssertFalse(state.matchesDraft(keyword: "Edited", segment: "new", sourceType: 0, tagID: 0, sourceStart: "", sourceEnd: ""))
        XCTAssertFalse(state.matchesDraft(keyword: "Existing", segment: "all", sourceType: 0, tagID: 0, sourceStart: "", sourceEnd: ""))
        XCTAssertFalse(state.matchesDraft(keyword: "Existing", segment: "new", sourceType: 1, tagID: 0, sourceStart: "", sourceEnd: ""))
        XCTAssertFalse(state.matchesDraft(keyword: "Existing", segment: "new", sourceType: 0, tagID: 1, sourceStart: "", sourceEnd: ""))
        XCTAssertFalse(state.matchesDraft(keyword: "Existing", segment: "new", sourceType: 0, tagID: 0, sourceStart: "2026-01-01", sourceEnd: ""))
        XCTAssertFalse(state.matchesDraft(keyword: "Existing", segment: "new", sourceType: 0, tagID: 0, sourceStart: "", sourceEnd: "2026-01-01"))
    }
    func testRefreshUsesCurrentCountsWithoutMutatingOriginalPayload() throws {
        let old = try document(count: .int(4)), next = try document(count: .int(0))
        XCTAssertEqual(MerchantCustomerEmptyRecovery(document: old)?.kind, .listUnavailable)
        XCTAssertEqual(MerchantCustomerEmptyRecovery(document: next)?.kind, .noCustomers)
        XCTAssertEqual(old.summary["all"], .int(4))
    }
}
