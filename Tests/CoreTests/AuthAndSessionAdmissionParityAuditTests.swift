import XCTest
@testable import QuestifyCore

final class AuthAndSessionAdmissionParityAuditTests: XCTestCase {
    func testAllThreePillarsAndFailClosedAuthFlagsAreCompliantByDefault() {
        let audit = AuthAndSessionAdmissionParityAudit()
        XCTAssertTrue(audit.isAllCompliant)
        XCTAssertEqual(audit.pillars.map(\.pillar), [
            .w2_01_authGatesAndPrivacyDisclosure,
            .ios_i00_1_accountSessionRoleGate,
            .w2_02_publicConfigAndOfficialEventUnavailable
        ])
        XCTAssertFalse(audit.authGates.smsSendEnabled)
        XCTAssertFalse(audit.authGates.wechatSignInEnabled)
        XCTAssertFalse(audit.authGates.appleSignInEnabled)
        XCTAssertTrue(audit.authGates.privacyDisclosureMounted)
        XCTAssertTrue(audit.authGates.isFailClosedByDefault)
    }

    func testEnablingAnyUnapprovedAuthFlagBreaksFailClosedDefaultCheck() {
        let smsEnabled = AuthGateDefaultsSnapshot(
            smsSendEnabled: true,
            wechatSignInEnabled: false,
            appleSignInEnabled: false,
            privacyDisclosureMounted: true
        )
        XCTAssertFalse(smsEnabled.isFailClosedByDefault)
        XCTAssertFalse(AuthAndSessionAdmissionParityAudit(authGates: smsEnabled).isAllCompliant)
    }

    func testAccountSessionGateAdmitsOnlyKnownNonEmptyServerRoles() {
        XCTAssertEqual(
            AuthAndSessionAdmissionParityAudit.evaluateSessionAdmission(accountID: 42, rawRole: "USER"),
            .admitted(accountID: 42, role: .user)
        )
        XCTAssertEqual(
            AuthAndSessionAdmissionParityAudit.evaluateSessionAdmission(accountID: 42, rawRole: "MERCHANT"),
            .admitted(accountID: 42, role: .merchant)
        )
        XCTAssertEqual(
            AuthAndSessionAdmissionParityAudit.evaluateSessionAdmission(accountID: 42, rawRole: "CLUB_ADMIN"),
            .admitted(accountID: 42, role: .clubAdmin)
        )

        XCTAssertEqual(
            AuthAndSessionAdmissionParityAudit.evaluateSessionAdmission(accountID: 42, rawRole: nil),
            .rejectedMissingRole
        )
        XCTAssertEqual(
            AuthAndSessionAdmissionParityAudit.evaluateSessionAdmission(accountID: 42, rawRole: "   "),
            .rejectedMissingRole
        )
        XCTAssertEqual(
            AuthAndSessionAdmissionParityAudit.evaluateSessionAdmission(accountID: 42, rawRole: "GUEST_SUPERUSER"),
            .rejectedUnknownRole("GUEST_SUPERUSER")
        )
        XCTAssertEqual(
            AuthAndSessionAdmissionParityAudit.evaluateSessionAdmission(accountID: 0, rawRole: "USER"),
            .rejectedInvalidAccountID
        )
    }

    func testOfficialEventResponseMaps404And410ToSafeUnavailablePresentation() {
        XCTAssertEqual(
            AuthAndSessionAdmissionParityAudit.evaluateOfficialEventResponse(httpStatus: 200),
            .available
        )
        XCTAssertEqual(
            AuthAndSessionAdmissionParityAudit.evaluateOfficialEventResponse(httpStatus: 404),
            .safelyUnavailable(httpStatus: 404, fallbackHeadline: "官方活动不存在或已移除")
        )
        XCTAssertEqual(
            AuthAndSessionAdmissionParityAudit.evaluateOfficialEventResponse(httpStatus: 410),
            .safelyUnavailable(httpStatus: 410, fallbackHeadline: "官方活动已结束或已下线")
        )
        XCTAssertEqual(
            AuthAndSessionAdmissionParityAudit.evaluateOfficialEventResponse(httpStatus: 503),
            .retryableFailure(httpStatus: 503)
        )
    }
}
