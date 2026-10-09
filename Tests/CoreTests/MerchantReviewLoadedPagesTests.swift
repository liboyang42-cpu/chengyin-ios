import XCTest
@testable import QuestifyCore

final class MerchantReviewLoadedPagesTests: XCTestCase {
    private let scope = MerchantBusinessScope(realm: "synthetic://reviews", accountID: 99001, epoch: 1)
    private func snapshot(_ page: Int, merchant: Int = 610, change: ((inout MerchantBusinessObject) -> Void)? = nil) throws -> MerchantBusinessSnapshot {
        let query = MerchantBusinessQuery.reviews(page: page)
        var payload = try MerchantBusinessSyntheticFixtures.listToolsPayload(query).object!
        change?(&payload)
        var grant = try MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!
        grant["merchant"] = .object(["id": .int(merchant), "name": .string("Synthetic workshop")])
        return try .init(access: .init(grant), document: .init(query: query, payload: .object(payload)))
    }
    func testConsecutivePagesRetainMatchesAndExactSourceSnapshots() throws {
        let first = try snapshot(1), second = try snapshot(2)
        var pages = try MerchantReviewLoadedPages(snapshot: first, scope: scope, authorizationGeneration: nil)
        try pages.append(second, scope: scope, authorizationGeneration: nil)
        XCTAssertEqual(pages.rows.count, 21); XCTAssertEqual(pages.page, 2); XCTAssertFalse(pages.hasMore)
        XCTAssertEqual(pages.rows.filter(MerchantReviewFilter.photos.matches).map(\.id), ["63003"])
        XCTAssertEqual(pages.rows.filter(MerchantReviewFilter.pending.matches).map(\.id), ["63001"])
        XCTAssertEqual(pages.rows.filter(MerchantReviewFilter.low.matches).map(\.id), ["63002"])
        XCTAssertEqual(second.document.rows.map(\.id), ["63021"])
        XCTAssertEqual(second.document.summary["replyRatePct"], .int(65))
        XCTAssertEqual(pages.sourcePage(for: first.document.rows[2])?.query, .reviews(page: 1))
        XCTAssertEqual(pages.sourcePage(for: second.document.rows[0])?.query, .reviews(page: 2))
    }
    func testDuplicateIdentityUpdatesInPlaceAndUsesLatestSourcePage() throws {
        let first = try snapshot(1)
        let second = try snapshot(2) { payload in
            var row = payload["items"]!.array![0].object!
            row["id"] = .int(63003); row["version"] = .int(2)
            payload["items"] = .array([.object(row)])
        }
        var pages = try MerchantReviewLoadedPages(snapshot: first, scope: scope, authorizationGeneration: nil)
        try pages.append(second, scope: scope, authorizationGeneration: nil)
        XCTAssertEqual(pages.rows.count, 20); XCTAssertEqual(pages.rows[2].id, "63003")
        XCTAssertEqual(pages.rows[2].fields["version"], .int(2))
        XCTAssertEqual(pages.sourcePage(for: pages.rows[2])?.page, 2)
        XCTAssertNil(pages.sourcePage(for: first.document.rows[2]))
    }
    func testInitializationRequiresFirstReviewPage() throws {
        XCTAssertThrowsError(try MerchantReviewLoadedPages(snapshot: snapshot(2), scope: scope, authorizationGeneration: nil))
        let query = MerchantBusinessQuery.aftercare(.pending, page: 1)
        let wrong = try MerchantBusinessSnapshot(access: snapshot(1).access,
            document: .init(query: query, payload: MerchantBusinessSyntheticFixtures.listToolsPayload(query)))
        XCTAssertThrowsError(try MerchantReviewLoadedPages(snapshot: wrong, scope: scope, authorizationGeneration: nil))
    }
    func testRepeatedSkippedAndPostTerminalPagesAreRejectedAtomically() throws {
        var pages = try MerchantReviewLoadedPages(snapshot: snapshot(1), scope: scope, authorizationGeneration: nil)
        let original = pages
        XCTAssertThrowsError(try pages.append(snapshot(1), scope: scope, authorizationGeneration: nil))
        XCTAssertEqual(pages, original)
        let third = try snapshot(3) { $0["total"] = .int(41); $0["hasMore"] = .bool(false) }
        XCTAssertThrowsError(try pages.append(third, scope: scope, authorizationGeneration: nil))
        XCTAssertEqual(pages, original)
        try pages.append(snapshot(2), scope: scope, authorizationGeneration: nil)
        let terminal = pages
        XCTAssertThrowsError(try pages.append(third, scope: scope, authorizationGeneration: nil))
        XCTAssertEqual(pages, terminal)
    }
    func testScopeAuthorizationAndMerchantChangesCannotMixRows() throws {
        let authorization = UUID()
        var pages = try MerchantReviewLoadedPages(snapshot: snapshot(1), scope: scope, authorizationGeneration: authorization)
        let original = pages
        for changed in [MerchantBusinessScope(realm: "synthetic://other", accountID: 99001, epoch: 1),
                        .init(realm: scope.realm, accountID: 99002, epoch: 1), .init(realm: scope.realm, accountID: 99001, epoch: 2)] {
            XCTAssertThrowsError(try pages.append(snapshot(2), scope: changed, authorizationGeneration: authorization))
        }
        XCTAssertThrowsError(try pages.append(snapshot(2), scope: scope, authorizationGeneration: UUID()))
        XCTAssertThrowsError(try pages.append(snapshot(2, merchant: 611), scope: scope, authorizationGeneration: authorization))
        XCTAssertEqual(pages, original)
    }
    func testOriginalPageDestinationRequiresFreshExactContext() throws {
        let first = try snapshot(1), authorization = UUID()
        let pages = try MerchantReviewLoadedPages(snapshot: first, scope: scope, authorizationGeneration: authorization)
        let destination = try XCTUnwrap(pages.sourcePage(for: first.document.rows[0]))
        XCTAssertTrue(destination.matches(scope: scope, authorizationGeneration: authorization, snapshot: first))
        XCTAssertFalse(destination.matches(scope: nil, authorizationGeneration: authorization, snapshot: first))
        XCTAssertFalse(destination.matches(scope: scope, authorizationGeneration: nil, snapshot: first))
        XCTAssertFalse(destination.matches(scope: scope, authorizationGeneration: authorization, snapshot: try snapshot(2)))
        XCTAssertFalse(destination.matches(scope: scope, authorizationGeneration: authorization, snapshot: try snapshot(1, merchant: 611)))
    }
    func testAccumulatedRowNeverAuthorizesMutationAgainstLaterPage() throws {
        let first = try snapshot(1), second = try snapshot(2)
        var pages = try MerchantReviewLoadedPages(snapshot: first, scope: scope, authorizationGeneration: nil)
        try pages.append(second, scope: scope, authorizationGeneration: nil)
        let row = try XCTUnwrap(pages.rows.first)
        let mutation = MerchantBusinessMutation.review(id: try .init(63001), version: try row.fields.mbInt("version"), action: .reply, content: "Synthetic reply")
        XCTAssertThrowsError(try mutation.validate(in: second.document, access: second.access, roles: nil))
        XCTAssertNoThrow(try mutation.validate(in: first.document, access: first.access, roles: nil))
    }
    func testMissingOriginalTargetNeverGainsAuthorityFromRetainedRow() throws {
        let first = try snapshot(1)
        let pages = try MerchantReviewLoadedPages(snapshot: first, scope: scope, authorizationGeneration: nil)
        let destination = try XCTUnwrap(pages.sourcePage(for: first.document.rows[0]))
        let shifted = try snapshot(1) { payload in
            var rows = payload["items"]!.array!
            var replacement = rows[0].object!; replacement["id"] = .int(63100); rows[0] = .object(replacement)
            payload["items"] = .array(rows)
        }
        XCTAssertTrue(destination.matches(scope: scope, authorizationGeneration: nil, snapshot: shifted))
        XCTAssertFalse(shifted.document.rows.contains { $0.id == destination.reviewID })
        let mutation = MerchantBusinessMutation.review(id: try .init(63001), version: try first.document.rows[0].fields.mbInt("version"), action: .reply, content: "Synthetic reply")
        XCTAssertThrowsError(try mutation.validate(in: shifted.document, access: shifted.access, roles: nil))
    }
}
