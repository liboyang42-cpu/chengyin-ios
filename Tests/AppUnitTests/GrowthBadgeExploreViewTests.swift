import XCTest
import SwiftUI
@testable import Questify

@MainActor final class GrowthBadgeExploreViewTests: XCTestCase {
    private final class Marker {}
    private let reader = Marker()
    private let key = GrowthCenterLoadKey(scope: UUID())
    private let presentation = UUID()
    private func center(empty: Bool = true, points: Int = 4) throws -> GrowthCenterRecord {
        let badges = empty ? "[]" : #"[{"badgeCode":"explorer"}]"#
        return try JSONDecoder().decode(GrowthCenterRecord.self,
            from: Data("{\"growth\":{},\"points\":\(points),\"badges\":\(badges),\"missions\":[]}".utf8))
    }
    private func selection(empty: Bool = true) throws -> GrowthBadgeExploreSelection {
        .init(readerID: ObjectIdentifier(reader), key: key, center: try center(empty: empty), presentationID: presentation)
    }
    private func accepts(_ value: GrowthBadgeExploreSelection, center: GrowthCenterRecord?,
                         key: GrowthCenterLoadKey? = nil, readerID: ObjectIdentifier? = nil,
                         presentationID: UUID? = nil, visible: Bool = true,
                         authenticated: Bool = true, configured: Bool = true,
                         loading: Bool = false, hasIssue: Bool = false) -> Bool {
        value.accepts(readerID: readerID ?? ObjectIdentifier(reader), key: key ?? self.key, center: center,
            presentationID: presentationID ?? presentation, visible: visible, authenticated: authenticated,
            configured: configured, loading: loading, hasIssue: hasIssue)
    }
    func testCurrentSuccessfulEmptyBadgesCanUseExistingHomeAction() throws {
        XCTAssertTrue(accepts(try selection(), center: try center()))
    }
    func testMissingFailedLoadingAndUnauthorizedNeverEstablishEmptyBadges() throws {
        let value = try selection(), center = try center()
        XCTAssertFalse(accepts(value, center: nil))
        XCTAssertFalse(accepts(value, center: center, hasIssue: true))
        XCTAssertFalse(accepts(value, center: center, loading: true))
        XCTAssertFalse(accepts(value, center: center, authenticated: false))
        XCTAssertFalse(accepts(value, center: center, configured: false))
    }
    func testMissingNullAndMalformedBadgePayloadsAreNotSuccessfulEmptyRecords() {
        for json in [#"{"growth":{},"missions":[]}"#,
                     #"{"growth":{},"badges":null,"missions":[]}"#,
                     #"{"growth":{},"badges":{},"missions":[]}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(GrowthCenterRecord.self, from: Data(json.utf8)))
        }
    }
    func testPartialOverviewUsesOnlyCurrentSuccessfulCenterForBadgeEmptiness() throws {
        let value = try selection(), record = try center()
        let partial = GrowthCenterOverview(center: .content(record), progress: .failure(.network),
            completed: .failure(.unavailable), rank: .failure(.failed))
        XCTAssertTrue(accepts(value, center: partial.center.value, hasIssue: partial.center.issue != nil))
        let failed = GrowthCenterOverview(center: .failure(.network), progress: .failure(.network),
            completed: .failure(.unavailable), rank: .failure(.failed))
        XCTAssertFalse(accepts(value, center: failed.center.value, hasIssue: failed.center.issue != nil))
    }
    func testNonemptyAndReplacedEmptyRecordsRejectOldAction() throws {
        XCTAssertFalse(accepts(try selection(empty: false), center: try center(empty: false)))
        XCTAssertFalse(accepts(try selection(), center: try center(empty: false)))
        XCTAssertFalse(accepts(try selection(), center: try center(points: 5)))
    }
    func testReaderScopeAndPresentationReplacementRejectOldCallback() throws {
        let value = try selection(), record = try center(), other = Marker()
        XCTAssertFalse(accepts(value, center: record, readerID: ObjectIdentifier(other)))
        XCTAssertFalse(accepts(value, center: record, key: .init(scope: UUID())))
        XCTAssertFalse(accepts(value, center: record, presentationID: UUID()))
        XCTAssertFalse(accepts(value, center: record, visible: false))
    }
}
