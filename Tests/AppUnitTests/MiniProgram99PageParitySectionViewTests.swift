import XCTest
import SwiftUI
@testable import Questify
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor
final class MiniProgram99PageParitySectionViewTests: XCTestCase {

    func testDefaultInstantiationAnd99PageCoverageTotals() {
        let view = MiniProgram99PageParitySectionView()
        _ = view.body

        XCTAssertEqual(view.domainRows.count, 4)
        XCTAssertEqual(view.totalCoveredPages, 99)
        XCTAssertEqual(view.totalExpectedPages, 99)
        XCTAssertEqual(view.integratedWave2Count, 21)
        XCTAssertEqual(
            view.overallHeaderBadgeText,
            "99-Page Parity: 99/99 · Wave-2: 21/21 · Write Gates: FAIL-CLOSED"
        )
    }

    func testFourDomainsAndFailClosedGateProjections() {
        let view = MiniProgram99PageParitySectionView()
        let titles = view.domainRows.map(\.domainTitle)
        XCTAssertEqual(
            titles,
            [
                "Domain B: Main/Home/Square/Profile",
                "Domain C: Roam/Play/Game",
                "Domain D: Social/Team/Club",
                "Domain E: Merchant/Wallet/Order/Publish"
            ]
        )
        XCTAssertTrue(view.domainRows.allSatisfy(\.isFullyAligned))
        for row in view.domainRows {
            XCTAssertFalse(row.failClosedWriteGates.isEmpty)
            XCTAssertTrue(row.failClosedGateBadgeText.hasSuffix("[OFF]"))
            XCTAssertTrue(row.coverageSummaryText.contains(row.domainTitle))
        }
    }

    func testAll21Wave2ScopesProjectedInOrder() {
        let view = MiniProgram99PageParitySectionView()
        let expectedIDs = (1...21).map { String(format: "w2-%02d", $0) }
        XCTAssertEqual(view.wave2Badges.map(\.id), expectedIDs)
        XCTAssertEqual(view.wave2ScopeIDsSummaryText, expectedIDs.joined(separator: ", "))
    }
}
