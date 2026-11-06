import XCTest
@testable import Questify

@MainActor final class PlayThemeRecordsPaginationTests: XCTestCase {
    private func firstPage() -> [PlayWireValue] {
        (0..<PlayExperienceService.themeHistoryPageSize).map { offset in
            .object(["sessionId": .integer(100 - offset), "result": .object(["success": .bool(true)])])
        }
    }

    func testRefusalAfterFullPagePreservesRowsButDoesNotOfferMore() async {
        let errors: [PlayExperienceError] = [.unauthorized, .rejected(401, nil), .rejected(403, nil), .rejected(2, nil)]
        for error in errors {
            let reader = PaginationReader(pages: [.success(firstPage()), .failure(error)])
            let model = PlayThemeRecordsCoordinator(topicID: 71, reader: reader)
            await model.open()
            let original = model.rows
            XCTAssertTrue(PlayThemeRecordsPagination.isOffered(model))
            await model.loadMore()
            XCTAssertEqual(model.issue, .refused)
            XCTAssertTrue(model.hasMore, "The original cursor is retained, not rewritten by presentation")
            XCTAssertEqual(model.rows, original)
            XCTAssertEqual(reader.cursors, [nil, 81])
            XCTAssertFalse(PlayThemeRecordsPagination.isOffered(model))
        }
    }

    func testFirstPageRefusalDoesNotBecomeEmptyOrRetry() async {
        let reader = PaginationReader(pages: [.failure(PlayExperienceError.rejected(403, nil))])
        let model = PlayThemeRecordsCoordinator(topicID: 71, reader: reader)
        await model.open()
        XCTAssertEqual(model.issue, .refused)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertFalse(PlayThemeRecordsPagination.isOffered(model))
    }

    func testTransientPageFailureStillOffersSameCursorRecovery() async {
        let reader = PaginationReader(pages: [.success(firstPage()), .failure(PlayExperienceError.unknownResult),
            .success([.object(["sessionId": .integer(70)])])])
        let model = PlayThemeRecordsCoordinator(topicID: 71, reader: reader)
        await model.open()
        await model.loadMore()
        XCTAssertEqual(model.issue, .historyFailed)
        XCTAssertTrue(PlayThemeRecordsPagination.isOffered(model))
        await model.loadMore()
        XCTAssertEqual(reader.cursors, [nil, 81, 81])
        XCTAssertEqual(model.rows.count, 21)
        XCTAssertEqual(model.rows.last?.sessionID, 70)
        XCTAssertNil(model.issue)
        XCTAssertFalse(PlayThemeRecordsPagination.isOffered(model), "A short final page remains terminal")
    }

    func testTransientFirstPageFailureCanRecoverToEmpty() async {
        let reader = PaginationReader(pages: [.failure(PlayExperienceError.unknownResult), .success([])])
        let model = PlayThemeRecordsCoordinator(topicID: 71, reader: reader)
        await model.open()
        XCTAssertTrue(PlayThemeRecordsPagination.isOffered(model))
        await model.loadMore()
        XCTAssertEqual(reader.cursors, [nil, nil])
        XCTAssertNil(model.issue)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertFalse(PlayThemeRecordsPagination.isOffered(model))
    }

    func testClosingRefusedCardDoesNotReofferRetainedHistoryCursor() async {
        let reader = PaginationReader(pages: [.success(firstPage())])
        let model = PlayThemeRecordsCoordinator(topicID: 71, reader: reader)
        await model.open()
        await model.openCard(sessionID: 100)
        XCTAssertEqual(model.issue, .refused)
        model.closeCard()
        XCTAssertNil(model.cardSessionID)
        XCTAssertEqual(model.rows.count, 20)
        XCTAssertEqual(model.issue, .refused)
        XCTAssertFalse(PlayThemeRecordsPagination.isOffered(model))
        XCTAssertEqual(reader.cursors, [nil])
    }
}

@MainActor private final class PaginationReader: PlayThemeRecordsReading {
    var pages: [Result<[PlayWireValue], Error>]
    var cursors: [Int?] = []
    init(pages: [Result<[PlayWireValue], Error>]) { self.pages = pages }
    func history(topicID: Int, beforeSessionID: Int?) async throws -> [PlayWireValue] {
        cursors.append(beforeSessionID)
        guard !pages.isEmpty else { throw PlayExperienceError.malformed }
        return try pages.removeFirst().get()
    }
    func card(sessionID: Int) async throws -> PlayWireValue { throw PlayExperienceError.rejected(403, nil) }
}
