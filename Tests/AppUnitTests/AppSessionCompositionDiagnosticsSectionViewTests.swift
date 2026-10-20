#if canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
import XCTest
@testable import Questify

@MainActor
final class AppSessionCompositionDiagnosticsSectionViewTests: XCTestCase {
    func testDefaultFixtureShortCircuitDraftFenceAndAccountGateAreCompliant() {
        let view = AppSessionCompositionDiagnosticsSectionView()
        _ = view.body

        XCTAssertTrue(view.snapshot.isFixtureLaunchMode)
        XCTAssertTrue(view.snapshot.sessionIsNilOnFixtureShortCircuit)
        XCTAssertTrue(view.snapshot.contentDraftReaderIsolatedByScope)
        XCTAssertTrue(view.snapshot.accountSessionGateEnforced)
        XCTAssertTrue(view.snapshot.hasCanonicalComponents)
        XCTAssertTrue(view.snapshot.isAllCompliant)
        XCTAssertEqual(
            view.snapshot.rows.map(\.componentID),
            ["AppSessionContainer", "ContentDraftContextFence", "AccountSessionGate"]
        )
        XCTAssertTrue(view.statusHeadline.contains("AppSessionContainer"))
    }

    func testFixtureLaunchWithoutNilSessionShortCircuitFailsCompliance() {
        let leakyFixtureSnapshot = AppSessionCompositionSnapshot(
            isFixtureLaunchMode: true,
            sessionIsNilOnFixtureShortCircuit: false,
            contentDraftReaderIsolatedByScope: true,
            accountSessionGateEnforced: true
        )
        let view = AppSessionCompositionDiagnosticsSectionView(snapshot: leakyFixtureSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isAllCompliant)
        XCTAssertFalse(view.snapshot.rows[0].isCompliant)
        XCTAssertTrue(view.statusHeadline.contains("session = nil"))
    }

    func testDraftContextFenceOrAccountSessionGateViolationReportsFailure() {
        let unisolatedDraftSnapshot = AppSessionCompositionSnapshot(
            isFixtureLaunchMode: false,
            sessionIsNilOnFixtureShortCircuit: false,
            contentDraftReaderIsolatedByScope: false,
            accountSessionGateEnforced: true
        )
        let draftView = AppSessionCompositionDiagnosticsSectionView(snapshot: unisolatedDraftSnapshot)
        _ = draftView.body

        XCTAssertFalse(draftView.snapshot.isAllCompliant)
        XCTAssertTrue(draftView.statusHeadline.contains("ContentDraftContextFence"))

        let unguardedAccountSnapshot = AppSessionCompositionSnapshot(
            isFixtureLaunchMode: false,
            sessionIsNilOnFixtureShortCircuit: false,
            contentDraftReaderIsolatedByScope: true,
            accountSessionGateEnforced: false
        )
        let gateView = AppSessionCompositionDiagnosticsSectionView(snapshot: unguardedAccountSnapshot)
        _ = gateView.body

        XCTAssertFalse(gateView.snapshot.isAllCompliant)
        XCTAssertTrue(gateView.statusHeadline.contains("AccountSessionGate"))
    }
}
