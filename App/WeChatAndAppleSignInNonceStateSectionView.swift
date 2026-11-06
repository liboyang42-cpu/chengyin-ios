import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

public struct OAuthSecurityProviderRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let providerName: String
    public let bindsCryptographicNonceOrState: Bool
    public let satisfiesGuideline4_8Parity: Bool
    public let failClosedUntilAllowlisted: Bool
    public let securitySummary: String

    public init(
        id: String,
        providerName: String,
        bindsCryptographicNonceOrState: Bool = true,
        satisfiesGuideline4_8Parity: Bool = true,
        failClosedUntilAllowlisted: Bool = true,
        securitySummary: String
    ) {
        self.id = id
        self.providerName = providerName
        self.bindsCryptographicNonceOrState = bindsCryptographicNonceOrState
        self.satisfiesGuideline4_8Parity = satisfiesGuideline4_8Parity
        self.failClosedUntilAllowlisted = failClosedUntilAllowlisted
        self.securitySummary = securitySummary
    }

    public var isCompliant: Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bindsCryptographicNonceOrState
            && satisfiesGuideline4_8Parity
            && failClosedUntilAllowlisted
    }
}

public struct OAuthNonceStateSecuritySnapshot: Sendable, Equatable {
    public static let defaultProviders: [OAuthSecurityProviderRow] = [
        OAuthSecurityProviderRow(
            id: "apple-sign-in-sha256-nonce",
            providerName: "Sign in with Apple (SHA-256 Nonce & Guideline 4.8)",
            bindsCryptographicNonceOrState: true,
            satisfiesGuideline4_8Parity: true,
            failClosedUntilAllowlisted: true,
            securitySummary: "每次授权生成单次有效随机 Nonce 并绑定 SHA-256 摘要，满足 Guideline 4.8 同等显著展示"
        ),
        OAuthSecurityProviderRow(
            id: "wechat-app-oauth-csrf-state",
            providerName: "微信 App 授权登录 (Anti-CSRF State & OpenID/UnionID 校验)",
            bindsCryptographicNonceOrState: true,
            satisfiesGuideline4_8Parity: true,
            failClosedUntilAllowlisted: true,
            securitySummary: "强制校验单次随机 anti-CSRF state 回显，后端身份核验通过前保持默认关闭"
        )
    ]

    public static let defaultReady = OAuthNonceStateSecuritySnapshot(
        providers: defaultProviders,
        appleSHA256NonceVerified: true,
        wechatAntiCSRFStateVerified: true,
        guideline4_8ParitySatisfied: true
    )

    public let providers: [OAuthSecurityProviderRow]
    public let appleSHA256NonceVerified: Bool
    public let wechatAntiCSRFStateVerified: Bool
    public let guideline4_8ParitySatisfied: Bool

    public init(
        providers: [OAuthSecurityProviderRow] = OAuthNonceStateSecuritySnapshot.defaultProviders,
        appleSHA256NonceVerified: Bool = true,
        wechatAntiCSRFStateVerified: Bool = true,
        guideline4_8ParitySatisfied: Bool = true
    ) {
        self.providers = providers
        self.appleSHA256NonceVerified = appleSHA256NonceVerified
        self.wechatAntiCSRFStateVerified = wechatAntiCSRFStateVerified
        self.guideline4_8ParitySatisfied = guideline4_8ParitySatisfied
    }

    public var isOAuthSecurityReady: Bool {
        !providers.isEmpty
            && providers.allSatisfy(\.isCompliant)
            && appleSHA256NonceVerified
            && wechatAntiCSRFStateVerified
            && guideline4_8ParitySatisfied
    }

    public var statusHeadline: String {
        if isOAuthSecurityReady {
            return "Apple SHA-256 Nonce 与微信 OAuth State 防重放/防跨站校验已就绪"
        }
        return "三方登录 Nonce/State 安全校验或 Guideline 4.8 对齐存在告警"
    }
}

/// Self-contained SwiftUI section presenting Apple Sign-In SHA-256 `nonce`, Guideline 4.8 parity,
/// and WeChat OAuth anti-CSRF `state` verification.
/// Uses `Text(verbatim:)` throughout so zero new `.xcstrings` keys are required.
@MainActor
public struct WeChatAndAppleSignInNonceStateSectionView: View {
    public let snapshot: OAuthNonceStateSecuritySnapshot

    public init(snapshot: OAuthNonceStateSecuritySnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Group {
            Section {
                HStack {
                    Text(verbatim: snapshot.statusHeadline)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(verbatim: snapshot.isOAuthSecurityReady ? "VERIFIED" : "WARNING")
                        .font(.caption2.monospaced().weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(snapshot.isOAuthSecurityReady ? Color.green.opacity(0.18) : Color.red.opacity(0.18))
                        )
                        .accessibilityIdentifier("oauthNonceStateSecurity.statusBadge")
                }
                .accessibilityIdentifier("oauthNonceStateSecurity.header")

                HStack {
                    Text(verbatim: "Apple Sign-In SHA-256 Nonce 绑定")
                    Spacer()
                    Text(verbatim: snapshot.appleSHA256NonceVerified ? "已启用" : "缺失")
                        .font(.caption)
                        .foregroundStyle(snapshot.appleSHA256NonceVerified ? Color.secondary : Color.red)
                }
                .accessibilityIdentifier("oauthNonceStateSecurity.appleNonce")

                HStack {
                    Text(verbatim: "微信 OAuth Anti-CSRF State 校验")
                    Spacer()
                    Text(verbatim: snapshot.wechatAntiCSRFStateVerified ? "已启用" : "缺失")
                        .font(.caption)
                        .foregroundStyle(snapshot.wechatAntiCSRFStateVerified ? Color.secondary : Color.red)
                }
                .accessibilityIdentifier("oauthNonceStateSecurity.wechatState")

                HStack {
                    Text(verbatim: "App Store Guideline 4.8 登录对等性")
                    Spacer()
                    Text(verbatim: snapshot.guideline4_8ParitySatisfied ? "已达标" : "未达标")
                        .font(.caption)
                        .foregroundStyle(snapshot.guideline4_8ParitySatisfied ? Color.secondary : Color.red)
                }
                .accessibilityIdentifier("oauthNonceStateSecurity.guideline48")
            } header: {
                Text(verbatim: "三方登录 Nonce 与 State 安全校验")
            }
            .accessibilityIdentifier("oauthNonceStateSecurity.summary.section")

            Section {
                ForEach(snapshot.providers) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: row.providerName)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: row.isCompliant ? "COMPLIANT" : "ALERT")
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(row.isCompliant ? Color.green : Color.red)
                        }
                        Text(verbatim: row.securitySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("oauthNonceStateSecurity.provider.\(row.id)")
                }
            } header: {
                Text(verbatim: "授权通道安全契约明细")
            }
            .accessibilityIdentifier("oauthNonceStateSecurity.providers.section")
        }
    }
}
