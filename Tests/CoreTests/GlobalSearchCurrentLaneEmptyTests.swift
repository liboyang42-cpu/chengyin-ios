import XCTest
@testable import QuestifyCore

/// Current domain-independent presentation only. No change to historical search fixtures.
final class GlobalSearchCurrentLaneEmptyTests: XCTestCase {
    func testSelectedSuccessfulEmptyIgnoresOtherDomainFailureOrGate() {
        for selected in GlobalSearchKind.allCases {
            let others = GlobalSearchKind.allCases.filter { $0 != selected }
            let value = GlobalSearchResults(rows: [GlobalSearchRow(kind: others[0], sourceID: 1, title: "Synthetic")],
                failedKinds: [others[1]], gatedKinds: [others[2]])
            XCTAssertTrue(value.showsEmptyState(for: selected, isLoading: false))
            XCTAssertFalse(value.showsEmptyState(for: nil, isLoading: false))
        }
    }
    func testSelectedFailureGateAndLoadingNeverBecomeEmptySuccess() {
        for selected in GlobalSearchKind.allCases {
            XCTAssertFalse(GlobalSearchResults(rows: [], failedKinds: [selected])
                .showsEmptyState(for: selected, isLoading: false))
            XCTAssertFalse(GlobalSearchResults(rows: [], gatedKinds: [selected])
                .showsEmptyState(for: selected, isLoading: false))
            XCTAssertFalse(GlobalSearchResults(rows: []).showsEmptyState(for: selected, isLoading: true))
        }
    }
    func testExistingSelectedRowAndRetainedFailedRowAreNotEmpty() {
        for selected in GlobalSearchKind.allCases {
            let row = GlobalSearchRow(kind: selected, sourceID: 1, title: "Synthetic")
            XCTAssertFalse(GlobalSearchResults(rows: [row]).showsEmptyState(for: selected, isLoading: false))
            XCTAssertFalse(GlobalSearchResults(rows: [row], failedKinds: [selected])
                .showsEmptyState(for: selected, isLoading: false))
        }
    }
    func testAllTabNeedsCompleteSuccessfulEmptyResult() {
        XCTAssertTrue(GlobalSearchResults(rows: []).showsEmptyState(for: nil, isLoading: false))
        XCTAssertFalse(GlobalSearchResults(rows: []).showsEmptyState(for: nil, isLoading: true))
        for kind in GlobalSearchKind.allCases {
            XCTAssertFalse(GlobalSearchResults(rows: [], failedKinds: [kind]).showsEmptyState(for: nil, isLoading: false))
            XCTAssertFalse(GlobalSearchResults(rows: [], gatedKinds: [kind]).showsEmptyState(for: nil, isLoading: false))
        }
    }
}
