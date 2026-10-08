import XCTest
import SwiftUI
@testable import Questify

/// Authored App-hosted rendering checks. All records are synthetic; these tests
/// do not use a player account, real submission, merchant verification or award.
@MainActor final class PlayPlayerSubmissionStatusTests: XCTestCase {
    private func record(_ status: PlayPlayerSubmissionRecord.Status, reason: String? = nil) -> PlayPlayerSubmissionRecord {
        .init(sessionID: 501, activityID: 41, teamID: 61, revision: 2, nodeID: 701,
              taskCode: "SYNTHETIC", submissionID: 91, status: status, rejectionReason: reason)
    }
    func testAllFourStatesConstructInBothLanguages() {
        for status in PlayPlayerSubmissionRecord.Status.allCases {
            for locale in ["en", "zh-Hans"] {
                let view = PlayPlayerSubmissionStatusView(state: .record(record(status, reason: "Synthetic reason")))
                    .environment(\.locale, Locale(identifier: locale))
                let size = UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 300, height: 20_000))
                XCTAssertGreaterThan(size.height, 0); XCTAssertLessThanOrEqual(size.width, 301)
            }
        }
    }
    func testMissingRecordHasNoStatusCard() {
        let size = UIHostingController(rootView: PlayPlayerSubmissionStatusView(state: .none))
            .sizeThatFits(in: CGSize(width: 300, height: 20_000))
        XCTAssertEqual(size.height, 0, accuracy: 0.1)
    }
    func testUnconfirmedStateCanRenderWithoutPrivateRecord() {
        let size = UIHostingController(rootView: PlayPlayerSubmissionStatusView(state: .unconfirmed))
            .sizeThatFits(in: CGSize(width: 300, height: 20_000))
        XCTAssertGreaterThan(size.height, 0)
    }
    func testLongRejectionGrowsAtAccessibilitySizeWithoutHorizontalOverflow() {
        let value = record(.rejected, reason: String(repeating: "Synthetic reason / 请重新拍摄。", count: 9))
        func measure(_ dynamicType: DynamicTypeSize) -> CGSize {
            UIHostingController(rootView: PlayPlayerSubmissionStatusView(state: .record(value))
                .dynamicTypeSize(dynamicType)).sizeThatFits(in: CGSize(width: 300, height: 20_000))
        }
        let regular = measure(.large), maximum = measure(.accessibility5)
        XCTAssertGreaterThan(maximum.height, regular.height); XCTAssertLessThanOrEqual(maximum.width, 301)
    }
    func testEvidenceOnlyAndApprovalRemainDifferentReadOnlyViews() {
        let evidence = PlayPlayerSubmissionStatusView(state: .record(record(.recorded)))
        let approved = PlayPlayerSubmissionStatusView(state: .record(record(.approved)))
        _ = UIHostingController(rootView: List { evidence; approved })
        XCTAssertNotEqual(PlayPlayerSubmissionRecord.Status.recorded.titleKey, PlayPlayerSubmissionRecord.Status.approved.titleKey)
    }
}
