import XCTest
@testable import QuestifyCore

final class WebViewAndExternalSafariSandboxAuditTests: XCTestCase {

    func testCanonicalContainersPassWebSandboxSafetyAudit() {
        let policies = WebViewAndExternalSafariSandboxAudit.canonicalPolicies
        XCTAssertEqual(policies.count, 3)
        XCTAssertEqual(
            policies.map(\.containerKind),
            [
                "legal-and-privacy-policy-reader",
                "merchant-external-campaign-preview",
                "help-center-and-faq-viewer"
            ]
        )

        let result = WebViewAndExternalSafariSandboxAudit.evaluate()
        XCTAssertEqual(result.totalContainers, 3)
        XCTAssertEqual(result.compliantContainers, 3)
        XCTAssertTrue(result.isWebSandboxSafe)
    }

    func testNonHTTPSATSViolationIsDetectedAndRejected() throws {
        let nonHTTPSPolicy = WebContainerSecurityPolicy(
            containerKind: "merchant-external-campaign-preview",
            enforcesHTTPSOnlyATS: false,
            disablesJSBridgeForUntrustedHosts: true,
            stripsAuthTokensFromExternalURLQuery: true
        )
        XCTAssertFalse(nonHTTPSPolicy.isCompliant)

        let evaluation = WebViewAndExternalSafariSandboxAudit.evaluate(policies: [nonHTTPSPolicy])
        XCTAssertEqual(evaluation.totalContainers, 1)
        XCTAssertEqual(evaluation.compliantContainers, 0)
        XCTAssertFalse(evaluation.isWebSandboxSafe)

        let httpURL = try XCTUnwrap(URL(string: "http://campaign.example.invalid/promo"))
        let httpsURL = try XCTUnwrap(URL(string: "https://campaign.example.invalid/promo"))
        XCTAssertFalse(WebViewAndExternalSafariSandboxAudit.isHTTPSOnlyURL(httpURL))
        XCTAssertTrue(WebViewAndExternalSafariSandboxAudit.isHTTPSOnlyURL(httpsURL))
    }

    func testUntrustedJSBridgeExposureIsDetectedAndRejected() {
        let exposedBridgePolicy = WebContainerSecurityPolicy(
            containerKind: "help-center-and-faq-viewer",
            enforcesHTTPSOnlyATS: true,
            disablesJSBridgeForUntrustedHosts: false,
            stripsAuthTokensFromExternalURLQuery: true
        )
        XCTAssertFalse(exposedBridgePolicy.isCompliant)

        let evaluation = WebViewAndExternalSafariSandboxAudit.evaluate(
            policies: [
                WebViewAndExternalSafariSandboxAudit.canonicalPolicies[0],
                exposedBridgePolicy
            ]
        )
        XCTAssertEqual(evaluation.totalContainers, 2)
        XCTAssertEqual(evaluation.compliantContainers, 1)
        XCTAssertFalse(evaluation.isWebSandboxSafe)
    }

    func testAuthTokenQueryParameterLeakIsDetectedAndRejected() throws {
        let leakyQueryPolicy = WebContainerSecurityPolicy(
            containerKind: "legal-and-privacy-policy-reader",
            enforcesHTTPSOnlyATS: true,
            disablesJSBridgeForUntrustedHosts: true,
            stripsAuthTokensFromExternalURLQuery: false
        )
        XCTAssertFalse(leakyQueryPolicy.isCompliant)
        XCTAssertFalse(WebViewAndExternalSafariSandboxAudit.evaluate(policies: [leakyQueryPolicy]).isWebSandboxSafe)

        let cleanURL = try XCTUnwrap(URL(string: "https://help.example.invalid/faq?lang=zh-Hans"))
        let leakedURL = try XCTUnwrap(URL(string: "https://help.example.invalid/faq?lang=zh-Hans&access_token=secret123"))
        XCTAssertFalse(WebViewAndExternalSafariSandboxAudit.containsAuthTokenInQuery(cleanURL))
        XCTAssertTrue(WebViewAndExternalSafariSandboxAudit.containsAuthTokenInQuery(leakedURL))
    }
}
