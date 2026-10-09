import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class GrowthLeaderboardExploreViewTests: XCTestCase {
    private final class Marker {}
    private let reader = Marker()
    private let key = GrowthCenterLoadKey(scope: UUID(), query: .init())
    private let presentation = UUID()
    private func board(empty: Bool = true) throws -> GrowthLeaderboard {
        let list = empty ? "[]" : #"[{"memberId":7,"rank":1,"score":4}]"#
        return try JSONDecoder().decode(GrowthLeaderboard.self,
            from: Data("{\"metric\":\"point\",\"period\":\"total\",\"list\":\(list),\"me\":{}}".utf8))
    }
    private func selection(empty: Bool = true) throws -> GrowthLeaderboardExploreSelection {
        .init(readerID: ObjectIdentifier(reader), key: key, board: try board(empty: empty), presentationID: presentation)
    }
    private func accepts(_ value: GrowthLeaderboardExploreSelection, board: GrowthLeaderboard?, key: GrowthCenterLoadKey? = nil,
                         readerID: ObjectIdentifier? = nil, presentationID: UUID? = nil,
                         visible: Bool = true, authenticated: Bool = true, configured: Bool = true,
                         loading: Bool = false, hasIssue: Bool = false) -> Bool {
        value.accepts(readerID: readerID ?? ObjectIdentifier(reader), key: key ?? self.key, board: board,
            presentationID: presentationID ?? presentation, visible: visible, authenticated: authenticated,
            configured: configured, loading: loading, hasIssue: hasIssue)
    }
    func testCurrentSuccessfulEmptyBoardCanUseExistingHomeAction() throws {
        XCTAssertTrue(accepts(try selection(), board: try board()))
    }
    func testMissingFailedLoadingAndUnauthorizedAreNeverEmptyBoardActions() throws {
        let value = try selection(), board = try board()
        XCTAssertFalse(accepts(value, board: nil))
        XCTAssertFalse(accepts(value, board: board, loading: true))
        XCTAssertFalse(accepts(value, board: board, hasIssue: true))
        XCTAssertFalse(accepts(value, board: board, authenticated: false))
        XCTAssertFalse(accepts(value, board: board, configured: false))
    }
    func testNonemptyResultsCannotOfferEmptyStateNavigation() throws {
        XCTAssertFalse(accepts(try selection(empty: false), board: try board(empty: false)))
        XCTAssertFalse(accepts(try selection(), board: try board(empty: false)))
    }
    func testReaderScopeMetricAndPeriodReplacementRejectOldCallback() throws {
        let value = try selection(), board = try board(), other = Marker()
        XCTAssertFalse(accepts(value, board: board, readerID: ObjectIdentifier(other)))
        XCTAssertFalse(accepts(value, board: board, key: .init(scope: UUID(), query: .init())))
        XCTAssertFalse(accepts(value, board: board, key: .init(scope: key.scope, query: .init(metric: .exp))))
        XCTAssertFalse(accepts(value, board: board, key: .init(scope: key.scope, query: .init(period: .week))))
    }
    func testRereadHiddenAndConsumedPresentationCannotReviveOldAction() throws {
        let value = try selection(), board = try board()
        XCTAssertFalse(accepts(value, board: board, visible: false))
        XCTAssertFalse(accepts(value, board: board, presentationID: UUID()))
    }
    func testDefaultEnvironmentHasNoFakeHomeAction() {
        XCTAssertNil(EnvironmentValues().growthExploreHomeAction)
    }
}
