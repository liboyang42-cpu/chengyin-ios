import SwiftUI
import XCTest
import QuestifyCore
@testable import QuestifyApp

@MainActor
final class AuthAndSessionAdmissionSectionViewTests: XCTestCase {

    func testDefaultFailClosedSnapshotRendersAllThreePillarsCompliant() {
        let view = AuthAndSessionAdmissionSectionView()
        _ = view.body

        let snapshot = view.snapshot
        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertTrue(snapshot.allPillarsCompliant)
        XCTAssertFalse(snapshot.smsSendEnabled)
        XCTAssertFalse(snapshot.wechatSignInEnabled)
        XCTAssertFalse(snapshot.appleSignInEnabled)
        XCTAssertTrue(snapshot.privacyViewRequiredBeforeLogin)
        XCTAssertFalse(snapshot.isServerRoleAdmitted)
        XCTAssertTrue(snapshot.isDiscoveryGracefulDegradation)
        XCTAssertEqual(
            snapshot.rows.map(\.pillar),
            [.w201AuthFlagsAndPrivacy, .i00ServerRoleAdmission, .w202PublicDiscovery404And410]
        )
    }

    func testAdmittedServerRoleAnd410DiscoveryDegradationStayCompliant() {
        let snapshot = AuthAndSessionAdmissionSnapshot(
            smsSendEnabled: false,
            wechatSignInEnabled: false,
            appleSignInEnabled: false,
            privacyViewRequiredBeforeLogin: true,
            serverUserInfoRole: "MERCHANT",
            admitsMissingRoleViaUserTypeFallback: false,
            discoveryHTTPStatus: 410
        )
        let view = AuthAndSessionAdmissionSectionView(snapshot: snapshot)
        _ = view.body

        XCTAssertTrue(view.snapshot.allPillarsCompliant)
        XCTAssertTrue(view.snapshot.isServerRoleAdmitted)
        XCTAssertTrue(view.snapshot.isDiscoveryGracefulDegradation)
        XCTAssertEqual(view.snapshot.rows[1].badgeText, "ADMITTED (MERCHANT)")
        XCTAssertEqual(view.snapshot.rows[2].badgeText, "DEGRADED (410 已过期容错)")
    }

    func testUnapprovedAuthFlagsOrUserTypeFallbackAreFlaggedAsNonCompliant() {
        let unsafeSnapshot = AuthAndSessionAdmissionSnapshot(
            smsSendEnabled: true,
            wechatSignInEnabled: false,
            appleSignInEnabled: true,
            privacyViewRequiredBeforeLogin: false,
            serverUserInfoRole: nil,
            admitsMissingRoleViaUserTypeFallback: true,
            discoveryHTTPStatus: 500
        )
        let view = AuthAndSessionAdmissionSectionView(snapshot: unsafeSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.allPillarsCompliant)
        XCTAssertFalse(view.snapshot.rows[0].isFailClosedCompliant)
        XCTAssertFalse(view.snapshot.rows[1].isFailClosedCompliant)
        XCTAssertFalse(view.snapshot.rows[2].isFailClosedCompliant)
        XCTAssertFalse(view.snapshot.isDiscoveryGracefulDegradation)
    }
}
