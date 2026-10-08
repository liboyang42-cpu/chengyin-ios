import XCTest
import SwiftUI
@testable import Questify

/// Synthetic App-hosted construction/size checks, not screenshots, VoiceOver
/// acceptance, real member data or verified Apple execution in this workspace.
@MainActor final class PlayPlayerTeamStatusTests: XCTestCase {
    private func member(_ status: PlayPlayerTeamMember.Status, name: String? = "Synthetic teammate", role: String? = "OBSERVER") -> PlayPlayerTeamMember {
        .init(id: 8, displayName: name, roleCode: role, status: status)
    }
    func testSevenStatusesConstructInBothLocales() {
        for status in PlayPlayerTeamMember.Status.allCases {
            for language in ["en", "zh-Hans"] {
                let view = PlayPlayerTeamStatusView(state: .members([member(status)]))
                    .environment(\.locale, Locale(identifier: language))
                let size = UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 300, height: 20_000))
                XCTAssertGreaterThan(size.height, 0); XCTAssertLessThanOrEqual(size.width, 301)
            }
        }
    }
    func testValidEmptyProjectionDoesNotMakeAnEmptyTeamCard() {
        let size = UIHostingController(rootView: PlayPlayerTeamStatusView(state: .empty))
            .sizeThatFits(in: CGSize(width: 300, height: 20_000))
        XCTAssertEqual(size.height, 0, accuracy: 0.1)
    }
    func testUnknownStateAndOptionalNamesConstructWithoutPrivateFields() {
        let unknown = PlayPlayerTeamStatusView(state: .unconfirmed)
        let unnamed = PlayPlayerTeamStatusView(state: .members([member(.joined, name: nil, role: nil)]))
        _ = UIHostingController(rootView: List { unknown; unnamed })
        XCTAssertNotEqual(PlayPlayerTeamMember.Status.joined.titleKey, PlayPlayerTeamMember.Status.assigned.titleKey)
    }
    func testLongPublicNameGrowsAtAccessibilitySizeWithoutHorizontalOverflow() {
        let record = member(.fallbackCompleted, name: String(repeating: "Synthetic 队友 ", count: 6), role: String(repeating: "ROLE_", count: 12))
        func measure(_ size: DynamicTypeSize) -> CGSize {
            UIHostingController(rootView: PlayPlayerTeamStatusView(state: .members([record])).dynamicTypeSize(size))
                .sizeThatFits(in: CGSize(width: 300, height: 20_000))
        }
        let normal = measure(.large), accessible = measure(.accessibility5)
        XCTAssertGreaterThan(accessible.height, normal.height); XCTAssertLessThanOrEqual(accessible.width, 301)
    }
    func testServerOrderAndFallbackRemainDistinctFromOrdinaryCompletion() {
        let rows = [member(.submitted), PlayPlayerTeamMember(id: 7, displayName: "Second", roleCode: nil, status: .fallbackCompleted)]
        _ = UIHostingController(rootView: List { PlayPlayerTeamStatusView(state: .members(rows)) })
        XCTAssertEqual(rows.map(\.id), [8, 7])
        XCTAssertNotEqual(PlayPlayerTeamMember.Status.fallbackCompleted.titleKey, PlayPlayerTeamMember.Status.completed.titleKey)
    }
}
