import XCTest
@testable import QuestifyCore

final class DeepLinkAndUniversalLinkSafetyAuditTests: XCTestCase {

    private let trustedHosts: Set<String> = ["link.chengyin.example"]
    private let cnAuthenticatedSession = DeepLinkAndUniversalLinkSafetyAudit.SessionContext(
        realmIdentifier: "cn-prod",
        isAuthenticated: true,
        accountID: 501
    )
    private let cnGuestSession = DeepLinkAndUniversalLinkSafetyAudit.SessionContext(
        realmIdentifier: "cn-prod",
        isAuthenticated: false,
        accountID: 0
    )

    func testValidPublicAndAuthenticatedRoutesRemainReadOnlyWithoutAutoTriggers() throws {
        let profileURL = try XCTUnwrap(URL(string: "https://link.chengyin.example/profile?memberId=42"))
        let profileReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: profileURL,
            session: cnGuestSession,
            verifiedHTTPSHosts: trustedHosts
        )
        XCTAssertEqual(profileReport.decision, .allowReadOnly(.publicMemberProfile(memberID: 42)))
        XCTAssertFalse(profileReport.autoTriggersMutation)
        XCTAssertFalse(profileReport.autoTriggersPayment)
        XCTAssertFalse(profileReport.autoTriggersLocationSharing)

        let teamURL = try XCTUnwrap(URL(string: "https://link.chengyin.example/pages/team/join/index?code=INVITE_2026"))
        let teamReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: teamURL,
            session: cnGuestSession,
            verifiedHTTPSHosts: trustedHosts
        )
        XCTAssertEqual(teamReport.decision, .allowReadOnly(.teamInvitation(inviteCode: "INVITE_2026")))

        let orderURL = try XCTUnwrap(URL(string: "https://link.chengyin.example/member/orders?orderId=ORD-9001"))
        let orderReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: orderURL,
            session: cnAuthenticatedSession,
            verifiedHTTPSHosts: trustedHosts
        )
        XCTAssertEqual(orderReport.decision, .allowReadOnly(.orderDetail(orderID: "ORD-9001")))
    }

    func testIncompleteProfileLinkFallbackWhenMemberIDIsZeroNegativeOrMissing() throws {
        let cases = [
            "https://link.chengyin.example/profile",
            "https://link.chengyin.example/profile?memberId=0",
            "https://link.chengyin.example/pages/profile/profile?id=-8",
            "https://link.chengyin.example/subpackageMember/pages/profile/index?userId=not-a-number"
        ]
        for raw in cases {
            let url = try XCTUnwrap(URL(string: raw))
            let report = DeepLinkAndUniversalLinkSafetyAudit.audit(
                url: url,
                session: cnGuestSession,
                verifiedHTTPSHosts: trustedHosts
            )
            XCTAssertEqual(
                report.decision,
                .incompleteProfileLinkFallback(fallbackLocalizationKey: "social.incompleteLink"),
                "Expected incompleteProfileLinkFallback for \(raw)"
            )
        }
    }

    func testNonHTTPSSchemeAndUntrustedOrRawIPHostRejection() throws {
        let httpURL = try XCTUnwrap(URL(string: "http://link.chengyin.example/profile?memberId=42"))
        let httpReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: httpURL,
            session: cnGuestSession,
            verifiedHTTPSHosts: trustedHosts
        )
        XCTAssertEqual(httpReport.decision, .rejected(.nonHTTPSScheme("http")))

        // Legacy IPv4 host is rejected even if a caller passes it in verifiedHTTPSHosts.
        let legacyIP = ["47", "103", "124", "64"].joined(separator: ".")
        let ipURL = try XCTUnwrap(URL(string: "https://\(legacyIP)/profile?memberId=42"))
        let ipReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: ipURL,
            session: cnGuestSession,
            verifiedHTTPSHosts: trustedHosts.union([legacyIP])
        )
        XCTAssertEqual(ipReport.decision, .rejected(.untrustedHost(legacyIP)))

        let unknownHostURL = try XCTUnwrap(URL(string: "https://untrusted.example.org/topic?topicId=9"))
        let unknownHostReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: unknownHostURL,
            session: cnGuestSession,
            verifiedHTTPSHosts: trustedHosts
        )
        XCTAssertEqual(unknownHostReport.decision, .rejected(.untrustedHost("untrusted.example.org")))
    }

    func testSessionRealmIsolationAndAuthenticationGatingForProtectedRoutes() throws {
        let crossRealmURL = try XCTUnwrap(
            URL(string: "https://link.chengyin.example/topic?topicId=108&realm=us-prod")
        )
        let crossRealmReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: crossRealmURL,
            session: cnAuthenticatedSession,
            verifiedHTTPSHosts: trustedHosts
        )
        XCTAssertEqual(
            crossRealmReport.decision,
            .rejected(.crossRealmRejected(linkRealm: .unitedStates, sessionRealm: .china))
        )

        let sameRealmURL = try XCTUnwrap(
            URL(string: "https://link.chengyin.example/topic?topicId=108&realm=cn-staging")
        )
        let sameRealmReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: sameRealmURL,
            session: cnAuthenticatedSession,
            verifiedHTTPSHosts: trustedHosts
        )
        XCTAssertEqual(sameRealmReport.decision, .allowReadOnly(.publicTopicDetail(topicID: 108)))

        let clubURL = try XCTUnwrap(URL(string: "https://link.chengyin.example/club/workspace?clubId=88"))
        let guestClubReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: clubURL,
            session: cnGuestSession,
            verifiedHTTPSHosts: trustedHosts
        )
        XCTAssertEqual(
            guestClubReport.decision,
            .authenticationRequired(target: .clubWorkspace(clubID: 88))
        )

        let authedClubReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: clubURL,
            session: cnAuthenticatedSession,
            verifiedHTTPSHosts: trustedHosts
        )
        XCTAssertEqual(
            authedClubReport.decision,
            .allowReadOnly(.clubWorkspace(clubID: 88))
        )
    }

    func testWritePaymentAndLocationSharingQueryIntentRejectionAndSanitization() throws {
        let unsafeURL = try XCTUnwrap(
            URL(string: "https://link.chengyin.example/topic?topicId=108&autoPay=1&shareLocation=true&action=write")
        )

        // Default strict mode rejects write/payment/location-sharing query intents.
        let strictReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: unsafeURL,
            session: cnAuthenticatedSession,
            verifiedHTTPSHosts: trustedHosts,
            rejectWriteIntentQuery: true
        )
        XCTAssertEqual(
            strictReport.decision,
            .rejected(.writeOrPaymentIntentRejected(keys: ["autoPay", "shareLocation", "action"]))
        )
        XCTAssertEqual(strictReport.strippedWriteIntentKeys, ["autoPay", "shareLocation", "action"])
        XCTAssertFalse(strictReport.autoTriggersMutation)
        XCTAssertFalse(strictReport.autoTriggersPayment)
        XCTAssertFalse(strictReport.autoTriggersLocationSharing)

        // Sanitizing mode strips the unsafe query parameters and routes read-only.
        let sanitizedReport = DeepLinkAndUniversalLinkSafetyAudit.audit(
            url: unsafeURL,
            session: cnAuthenticatedSession,
            verifiedHTTPSHosts: trustedHosts,
            rejectWriteIntentQuery: false
        )
        XCTAssertEqual(sanitizedReport.decision, .allowReadOnly(.publicTopicDetail(topicID: 108)))
        XCTAssertEqual(sanitizedReport.strippedWriteIntentKeys, ["autoPay", "shareLocation", "action"])
        XCTAssertEqual(sanitizedReport.sanitizedQueryItems, [URLQueryItem(name: "topicId", value: "108")])
        XCTAssertFalse(sanitizedReport.autoTriggersMutation)
        XCTAssertFalse(sanitizedReport.autoTriggersPayment)
        XCTAssertFalse(sanitizedReport.autoTriggersLocationSharing)
    }
}
