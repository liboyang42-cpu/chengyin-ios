import XCTest
@testable import Questify

final class PublicMerchantReviewRowsTests: XCTestCase {
    private func page(_ number: Int, rows: [(Int, Int, Bool)], total: Int = 40) throws -> PublicMerchantReviewPage {
        let items: [[String: Any]] = rows.map { id, version, canReport in
            ["id": id, "version": version, "rating": version == 1 ? 5 : 2,
             "content": "revision-\(version)", "imageUrls": version == 1 ? ["https://images.example/old.jpg"] : [],
             "verifiedRedemption": true, "status": "VISIBLE", "canReply": false, "canReport": canReport]
        }
        let data = try JSONSerialization.data(withJSONObject: ["mode": "public", "pageNum": number, "pageSize": 20,
            "total": total, "hasMore": (number - 1) * 20 + rows.count < total,
            "eligibility": ["canCreate": false, "reasonCode": "LOGIN_REQUIRED"], "items": items])
        let value = try JSONDecoder().decode(PublicMerchantReviewPage.self, from: data)
        try value.validate(page: number, size: 20)
        return value
    }

    func testBoundaryRepeatReplacesWholeRowAndPageWithoutMovingExistingRows() throws {
        var loaded = PublicMerchantReviewRows()
        let first = try page(1, rows: (81...100).reversed().map { ($0, 1, true) })
        loaded.accept(first)
        let next = try page(2, rows: [(81, 2, false)] + (62...80).reversed().map { ($0, 1, true) })
        loaded.accept(next)
        XCTAssertEqual(loaded.items.count, 39)
        XCTAssertEqual(Array(loaded.items.prefix(20).map(\.id)), first.items.map(\.id))
        let repeated = try XCTUnwrap(loaded.items.first { $0.id == 81 })
        XCTAssertEqual(repeated, next.items[0])
        XCTAssertEqual(repeated.version, 2)
        XCTAssertFalse(repeated.canReport, "Do not retain an older report permission")
        XCTAssertTrue(repeated.imageUrls.isEmpty)
        XCTAssertTrue(PublicMerchantReviewFilter.low.matches(repeated))
        XCTAssertFalse(PublicMerchantReviewFilter.photos.matches(repeated))
        XCTAssertEqual(loaded.pages[81], 2)
        XCTAssertEqual(loaded.pages[100], 1)
        XCTAssertFalse(next.hasMore, "Server paging is not recomputed from unique row count")
    }

    @MainActor func testReportUsesFreshLatestPageAndStillRejectsRevocationBeforeDispatch() async throws {
        var loaded = PublicMerchantReviewRows()
        loaded.accept(try page(1, rows: [(8, 1, true)]))
        let next = try page(2, rows: [(8, 2, true)])
        loaded.accept(next)
        let row = try XCTUnwrap(loaded.items.first)
        let sourcePage = try XCTUnwrap(loaded.pages[row.id])
        let writer = try ReviewRowsWriter(evidence: next)
        let coordinator = PublicMerchantReviewCoordinator(writer: writer, journal: MerchantBusinessMemoryIntentStore())
        let target = PublicMerchantReviewTarget(merchantRowID: try XCTUnwrap(PublicMerchantRowID(73)),
            ownerMemberID: try XCTUnwrap(PublicMerchantOwnerID(41)))
        let command = PublicMerchantReviewCommand.report(reviewID: row.id, expectedVersion: row.version, reason: "Synthetic reason")
        await coordinator.prepare(command, target: target, page: sourcePage)
        let review = try XCTUnwrap(coordinator.confirmation)
        XCTAssertEqual(review.page, 2)
        XCTAssertEqual(review.command, command)
        XCTAssertEqual(writer.pages, [2])
        XCTAssertEqual(writer.executions, 0)
        writer.value = try page(2, rows: [(8, 2, false)])
        await coordinator.confirm(review)
        XCTAssertEqual(writer.pages, [2, 2])
        XCTAssertEqual(coordinator.failure, .permissionChanged)
        XCTAssertEqual(writer.executions, 0, "A merged row never replaces the writer's fresh authorization check")
    }

    func testRepeatedPageIsIdempotentAndFirstPageRefreshDropsOldRowsAndPages() throws {
        var loaded = PublicMerchantReviewRows()
        loaded.accept(try page(1, rows: [(8, 1, true)]))
        let next = try page(2, rows: [(7, 1, true)])
        loaded.accept(next); loaded.accept(next)
        XCTAssertEqual(loaded.items.map(\.id), [8, 7])
        loaded.accept(try page(1, rows: [(6, 2, false)]))
        XCTAssertEqual(loaded.items.map(\.id), [6])
        XCTAssertEqual(loaded.pages, [6: 1])
        loaded.accept(try page(1, rows: [], total: 0))
        XCTAssertTrue(loaded.items.isEmpty)
        XCTAssertTrue(loaded.pages.isEmpty)
    }

    func testDuplicateWithinAcceptedPageHasOneConsistentLatestRow() throws {
        var loaded = PublicMerchantReviewRows()
        let value = try page(1, rows: [(8, 1, true), (8, 2, false)])
        loaded.accept(value)
        XCTAssertEqual(loaded.items, [value.items[1]])
        XCTAssertEqual(loaded.pages, [8: 1])
    }
}

@MainActor private final class ReviewRowsWriter: PublicMerchantReviewWriting {
    let isConfigured = true
    let session: PublicMerchantReviewSession?
    var value: PublicMerchantReviewPage
    var pages: [Int] = []
    var executions = 0
    init(evidence: PublicMerchantReviewPage) throws {
        value = evidence
        session = try .init(accountID: 8, scope: UUID(), realm: "fixture", token: "fixture-token")
    }
    func evidence(_ target: PublicMerchantReviewTarget, page: Int, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewPage {
        pages.append(page); return value
    }
    func execute(_ command: PublicMerchantReviewCommand, target: PublicMerchantReviewTarget, requestID: String, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewReceipt {
        executions += 1; throw PublicMerchantReviewWriteFailure.unknown
    }
}
