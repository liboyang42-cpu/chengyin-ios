import SwiftUI
import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
#else
@testable import Questify
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#endif

@MainActor
final class WeChatAndAppleSignInNonceStateSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotVerifiesAppleNonceWeChatStateAndGuideline48() {
        let snapshot = OAuthNonceStateSecuritySnapshot.defaultReady
        XCTAssertTrue(snapshot.isOAuthSecurityReady)
        XCTAssertTrue(snapshot.appleSHA256NonceVerified)
        XCTAssertTrue(snapshot.wechatAntiCSRFStateVerified)
        XCTAssertTrue(snapshot.guideline4_8ParitySatisfied)
        XCTAssertEqual(
            snapshot.providers.map(\.id),
            ["apple-sign-in-sha256-nonce", "wechat-app-oauth-csrf-state"]
        )
        XCTAssertEqual(snapshot.statusHeadline, "Apple SHA-256 Nonce 与微信 OAuth State 防重放/防跨站校验已就绪")
    }

    func testMissingNonceOrCSRFStateTriggersSecurityWarningState() {
        var providers = OAuthNonceStateSecuritySnapshot.defaultProviders
        providers[1] = OAuthSecurityProviderRow(
            id: "wechat-app-oauth-csrf-state",
            providerName: "微信 App 授权登录",
            bindsCryptographicNonceOrState: false,
            satisfiesGuideline4_8Parity: true,
            failClosedUntilAllowlisted: true,
            securitySummary: "缺少 state 校验"
        )
        let warningSnapshot = OAuthNonceStateSecuritySnapshot(
            providers: providers,
            appleSHA256NonceVerified: true,
            wechatAntiCSRFStateVerified: false,
            guideline4_8ParitySatisfied: true
        )
        XCTAssertFalse(warningSnapshot.providers[1].isCompliant)
        XCTAssertFalse(warningSnapshot.isOAuthSecurityReady)
        XCTAssertEqual(warningSnapshot.statusHeadline, "三方登录 Nonce/State 安全校验或 Guideline 4.8 对齐存在告警")
    }

    func testMainActorViewBodyInstantiationForReadyAndWarningStates() {
        let readyView = WeChatAndAppleSignInNonceStateSectionView(snapshot: .defaultReady)
        XCTAssertTrue(readyView.snapshot.isOAuthSecurityReady)
        _ = readyView.body

        let warningView = WeChatAndAppleSignInNonceStateSectionView(
            snapshot: OAuthNonceStateSecuritySnapshot(
                providers: OAuthNonceStateSecuritySnapshot.defaultProviders,
                appleSHA256NonceVerified: true,
                wechatAntiCSRFStateVerified: true,
                guideline4_8ParitySatisfied: false
            )
        )
        XCTAssertFalse(warningView.snapshot.isOAuthSecurityReady)
        _ = warningView.body
    }
}
