import SwiftUI
import QuestifyCore

/// Presentation row for one of the 3 auth, session admission & public discovery pillars:
/// - `w2-01` fail-closed auth flags & privacy view
/// - `IOS-I00-1` server role admission gate
/// - `w2-02` public config / official event 404 & 410 handling
public struct AuthAdmissionPillarRow: Identifiable, Equatable, Sendable {
    public enum PillarID: String, CaseIterable, Equatable, Sendable {
        case w201AuthFlagsAndPrivacy = "w2_01_auth_privacy"
        case i00ServerRoleAdmission = "i00_1_role_admission"
        case w202PublicDiscovery404And410 = "w2_02_public_discovery_404_410"
    }

    public let id: String
    public let pillar: PillarID
    public let title: String
    public let detail: String
    public let badgeText: String
    public let isFailClosedCompliant: Bool

    public init(
        pillar: PillarID,
        title: String,
        detail: String,
        badgeText: String,
        isFailClosedCompliant: Bool
    ) {
        self.id = pillar.rawValue
        self.pillar = pillar
        self.title = title
        self.detail = detail
        self.badgeText = badgeText
        self.isFailClosedCompliant = isFailClosedCompliant
    }
}

/// Self-contained snapshot evaluating the 3 auth, session admission & discovery pillars.
public struct AuthAndSessionAdmissionSnapshot: Equatable, Sendable {
    public let smsSendEnabled: Bool
    public let wechatSignInEnabled: Bool
    public let appleSignInEnabled: Bool
    public let privacyViewRequiredBeforeLogin: Bool
    public let serverUserInfoRole: String?
    public let admitsMissingRoleViaUserTypeFallback: Bool
    public let discoveryHTTPStatus: Int?
    public let rows: [AuthAdmissionPillarRow]

    public var isServerRoleAdmitted: Bool {
        guard let trimmed = serverUserInfoRole?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !trimmed.isEmpty else {
            return false
        }
        return ["USER", "PLAYER", "MERCHANT", "CLUB_ADMIN", "CLUB"].contains(trimmed)
    }

    public var isDiscoveryGracefulDegradation: Bool {
        guard let code = discoveryHTTPStatus else { return true }
        return code == 200 || code == 404 || code == 410
    }

    public var allPillarsCompliant: Bool {
        rows.count == 3 && rows.allSatisfy(\.isFailClosedCompliant)
    }

    public init(
        smsSendEnabled: Bool = false,
        wechatSignInEnabled: Bool = false,
        appleSignInEnabled: Bool = false,
        privacyViewRequiredBeforeLogin: Bool = true,
        serverUserInfoRole: String? = nil,
        admitsMissingRoleViaUserTypeFallback: Bool = false,
        discoveryHTTPStatus: Int? = 404
    ) {
        self.smsSendEnabled = smsSendEnabled
        self.wechatSignInEnabled = wechatSignInEnabled
        self.appleSignInEnabled = appleSignInEnabled
        self.privacyViewRequiredBeforeLogin = privacyViewRequiredBeforeLogin
        self.serverUserInfoRole = serverUserInfoRole
        self.admitsMissingRoleViaUserTypeFallback = admitsMissingRoleViaUserTypeFallback
        self.discoveryHTTPStatus = discoveryHTTPStatus

        let w201Compliant = !smsSendEnabled
            && !wechatSignInEnabled
            && !appleSignInEnabled
            && privacyViewRequiredBeforeLogin

        let roleTrimmed = serverUserInfoRole?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let roleValid = ["USER", "PLAYER", "MERCHANT", "CLUB_ADMIN", "CLUB"].contains(roleTrimmed)
        // IOS-I00-1 is compliant as long as missing/unknown roles are rejected and userType fallback is never used for admission.
        let i00Compliant = !admitsMissingRoleViaUserTypeFallback
        let i00Badge: String
        if admitsMissingRoleViaUserTypeFallback {
            i00Badge = "VIOLATION (userType 越权兜底)"
        } else if roleValid {
            i00Badge = "ADMITTED (\(roleTrimmed))"
        } else {
            i00Badge = "FAIL-CLOSED (缺省/未知 role 阻断)"
        }

        let w202Compliant: Bool
        let w202Badge: String
        switch discoveryHTTPStatus {
        case nil, 200?:
            w202Compliant = true
            w202Badge = "NORMAL (200)"
        case 404?:
            w202Compliant = true
            w202Badge = "DEGRADED (404 已下架容错)"
        case 410?:
            w202Compliant = true
            w202Badge = "DEGRADED (410 已过期容错)"
        case let code?:
            w202Compliant = false
            w202Badge = "UNHANDLED (\(code))"
        }

        self.rows = [
            AuthAdmissionPillarRow(
                pillar: .w201AuthFlagsAndPrivacy,
                title: "w2-01 认证通道默认关闭与隐私协议前置",
                detail: "短信发送、微信登录与 Apple 登录在未获独立审批前保持默认关闭；登录前显式展示原生隐私与协议说明。",
                badgeText: w201Compliant ? "FAIL-CLOSED (PASS)" : "OPEN / UNSAFE",
                isFailClosedCompliant: w201Compliant
            ),
            AuthAdmissionPillarRow(
                pillar: .i00ServerRoleAdmission,
                title: "IOS-I00-1 服务端 role 准入门禁",
                detail: "POST /api/userInfo 必须返回合法的 role 字段方可恢复或建立会话；严禁使用 userType 兜底准入。",
                badgeText: i00Badge,
                isFailClosedCompliant: i00Compliant
            ),
            AuthAdmissionPillarRow(
                pillar: .w202PublicDiscovery404And410,
                title: "w2-02 公共配置与官方活动 404/410 容错",
                detail: "首页公共配置与官方活动详情遇到 404/410 下架或过期响应时进入明确空态，不崩溃且不残留过期准入。",
                badgeText: w202Badge,
                isFailClosedCompliant: w202Compliant
            )
        ]
    }

    public static let failClosedDefault = AuthAndSessionAdmissionSnapshot()
}

/// SwiftUI section view rendering the 3 auth, session admission & discovery pillars (`w2-01`, `IOS-I00-1`, `w2-02`)
/// using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor
public struct AuthAndSessionAdmissionSectionView: View {
    public let snapshot: AuthAndSessionAdmissionSnapshot

    public init(snapshot: AuthAndSessionAdmissionSnapshot = .failClosedDefault) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(
                    verbatim: snapshot.allPillarsCompliant
                        ? "认证与会话准入审计：3/3 支柱符合 Fail-Closed 规范"
                        : "认证与会话准入审计：存在未闭合门禁风险"
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.allPillarsCompliant ? "PASS" : "BLOCKED")
                    .font(.caption.monospaced())
                    .foregroundStyle(snapshot.allPillarsCompliant ? .green : .red)
            }
            .accessibilityIdentifier("authAdmissionAudit.summary")

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(verbatim: row.badgeText)
                            .font(.caption.monospaced())
                            .foregroundStyle(row.isFailClosedCompliant ? .secondary : .red)
                            .accessibilityIdentifier("authAdmissionAudit.pillar.\(row.id).status")
                    }
                    Text(verbatim: row.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("authAdmissionAudit.pillar.\(row.id)")
            }

            HStack {
                Text(verbatim: "服务端角色准入状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    verbatim: snapshot.isServerRoleAdmitted
                        ? "已准入 (\(snapshot.serverUserInfoRole ?? ""))"
                        : "未准入（缺少或未知 role 保持阻断）"
                )
                .font(.caption.monospaced())
            }
            .accessibilityIdentifier("authAdmissionAudit.roleGate")

            HStack {
                Text(verbatim: "公共发现页 404/410 状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    verbatim: snapshot.isDiscoveryGracefulDegradation
                        ? "已启用下架/过期降级保护"
                        : "未识别状态码 (\(snapshot.discoveryHTTPStatus ?? -1))"
                )
                .font(.caption.monospaced())
            }
            .accessibilityIdentifier("authAdmissionAudit.discovery404_410")
        } header: {
            Text(verbatim: "认证、会话准入与公共配置门禁 (w2-01 / IOS-I00-1 / w2-02)")
        }
        .accessibilityIdentifier("authAdmissionAudit.section")
    }
}
