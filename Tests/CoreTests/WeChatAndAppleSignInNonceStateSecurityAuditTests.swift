import XCTest
@testable import QuestifyCore

final class WeChatAndAppleSignInNonceStateSecurityAuditTests: XCTestCase {
    func testCanonicalProvidersPassOAuthSecurityReadiness() {
        let providers = WeChatAndAppleSignInNonceStateSecurityAudit.canonicalProviders
        XCTAssertEqual(providers.map(\.id), [
            "apple-id-sha256-nonce-auth",
            "wechat-oauth2-csrf-state-exchange",
            "sms-otp-rate-limited-admission"
        ])
        XCTAssertTrue(providers.allSatisfy(\.isCompliant))

        let result = WeChatAndAppleSignInNonceStateSecurityAudit.evaluate()
        XCTAssertEqual(result.totalProviders, 3)
        XCTAssertEqual(result.compliantProviders, 3)
        XCTAssertTrue(result.isOAuthSecurityReady)
    }

    func testMissingCryptographicNonceOrCSRFStateIsRejected() {
        var providers = WeChatAndAppleSignInNonceStateSecurityAudit.canonicalProviders
        providers[0] = OAuthProviderSecurityCheck(
            id: "apple-id-sha256-nonce-auth",
            providerName: "Sign in with Apple",
            usesCryptographicNonceOrCSRFState: false,
            enforcesGuideline48AppleSignInParity: true,
            verifiesIdentityTokenOnBackend: true
        )
        XCTAssertFalse(providers[0].isCompliant)

        let result = WeChatAndAppleSignInNonceStateSecurityAudit.evaluate(providers: providers)
        XCTAssertEqual(result.totalProviders, 3)
        XCTAssertEqual(result.compliantProviders, 2)
        XCTAssertFalse(result.isOAuthSecurityReady)
    }

    func testGuideline48AppleSignInParityViolationIsDetected() {
        var providers = WeChatAndAppleSignInNonceStateSecurityAudit.canonicalProviders
        providers[1] = OAuthProviderSecurityCheck(
            id: "wechat-oauth2-csrf-state-exchange",
            providerName: "WeChat OAuth2",
            usesCryptographicNonceOrCSRFState: true,
            enforcesGuideline48AppleSignInParity: false,
            verifiesIdentityTokenOnBackend: true
        )
        XCTAssertFalse(providers[1].isCompliant)

        let result = WeChatAndAppleSignInNonceStateSecurityAudit.evaluate(providers: providers)
        XCTAssertEqual(result.totalProviders, 3)
        XCTAssertEqual(result.compliantProviders, 2)
        XCTAssertFalse(result.isOAuthSecurityReady)
    }

    func testUnverifiedBackendIdentityTokenAndEmptyProviderListAreRejected() {
        let unverifiedTokenProvider = OAuthProviderSecurityCheck(
            id: "apple-id-sha256-nonce-auth",
            providerName: "Sign in with Apple",
            usesCryptographicNonceOrCSRFState: true,
            enforcesGuideline48AppleSignInParity: true,
            verifiesIdentityTokenOnBackend: false
        )
        XCTAssertFalse(unverifiedTokenProvider.isCompliant)

        let result = WeChatAndAppleSignInNonceStateSecurityAudit.evaluate(providers: [unverifiedTokenProvider])
        XCTAssertEqual(result.totalProviders, 1)
        XCTAssertEqual(result.compliantProviders, 0)
        XCTAssertFalse(result.isOAuthSecurityReady)

        let emptyResult = WeChatAndAppleSignInNonceStateSecurityAudit.evaluate(providers: [])
        XCTAssertFalse(emptyResult.isOAuthSecurityReady)
    }
}
