import Foundation

/// Pure value-type parity audit across the 3 authentication, privacy & public discovery pillars:
/// 1. `w2-01`: `AuthFeatureFlags` (`smsSendEnabled == false`, `wechatSignInEnabled == false`, `appleSignInEnabled == false`)
///    default fail-closed gates + `PrivacyProtectionView` disclosure.
/// 2. `IOS-I00-1`: `AccountSessionGate` requiring non-empty server `role` (`USER` / `MERCHANT` / `CLUB_ADMIN`)
///    on `GET /api/userInfo` before session admission.
/// 3. `w2-02`: `GET /api/config/public` discovery & `OfficialEventUnavailableError` 404/410 safe unavailable presentation.
public enum AuthAndSessionAdmissionPillarID: String, CaseIterable, Sendable, Equatable {
    case w2_01_authGatesAndPrivacyDisclosure = "w2-01"
    case ios_i00_1_accountSessionRoleGate = "IOS-I00-1"
    case w2_02_publicConfigAndOfficialEventUnavailable = "w2-02"
}

public struct AuthAndSessionAdmissionPillarRecord: Identifiable, Equatable, Sendable {
    public let pillar: AuthAndSessionAdmissionPillarID
    public let coveredComponents: [String]
    public let endpointOrContract: String
    public let invariantSummary: String
    public let isCompliant: Bool

    public var id: String { pillar.rawValue }

    public init(
        pillar: AuthAndSessionAdmissionPillarID,
        coveredComponents: [String],
        endpointOrContract: String,
        invariantSummary: String,
        isCompliant: Bool = true
    ) {
        self.pillar = pillar
        self.coveredComponents = coveredComponents
        self.endpointOrContract = endpointOrContract
        self.invariantSummary = invariantSummary
        self.isCompliant = isCompliant
    }
}

public struct AuthGateDefaultsSnapshot: Equatable, Sendable {
    public let smsSendEnabled: Bool
    public let wechatSignInEnabled: Bool
    public let appleSignInEnabled: Bool
    public let privacyDisclosureMounted: Bool

    public static let failClosedDefault = AuthGateDefaultsSnapshot(
        smsSendEnabled: false,
        wechatSignInEnabled: false,
        appleSignInEnabled: false,
        privacyDisclosureMounted: true
    )

    public init(
        smsSendEnabled: Bool = false,
        wechatSignInEnabled: Bool = false,
        appleSignInEnabled: Bool = false,
        privacyDisclosureMounted: Bool = true
    ) {
        self.smsSendEnabled = smsSendEnabled
        self.wechatSignInEnabled = wechatSignInEnabled
        self.appleSignInEnabled = appleSignInEnabled
        self.privacyDisclosureMounted = privacyDisclosureMounted
    }

    public var isFailClosedByDefault: Bool {
        !smsSendEnabled && !wechatSignInEnabled && !appleSignInEnabled && privacyDisclosureMounted
    }
}

public enum AdmittedServerAccountRole: String, CaseIterable, Sendable, Equatable {
    case user = "USER"
    case merchant = "MERCHANT"
    case clubAdmin = "CLUB_ADMIN"
}

public enum SessionAdmissionAuditDecision: Equatable, Sendable {
    case admitted(accountID: Int, role: AdmittedServerAccountRole)
    case rejectedMissingRole
    case rejectedUnknownRole(String)
    case rejectedInvalidAccountID
}

public enum OfficialEventAvailabilityAuditState: Equatable, Sendable {
    case available
    case safelyUnavailable(httpStatus: Int, fallbackHeadline: String)
    case retryableFailure(httpStatus: Int)
}

public struct AuthAndSessionAdmissionParityAudit: Equatable, Sendable {
    public static let userInfoEndpoint = "GET /api/userInfo"
    public static let publicConfigEndpoint = "GET /api/config/public"

    public static let defaultPillars: [AuthAndSessionAdmissionPillarRecord] = [
        AuthAndSessionAdmissionPillarRecord(
            pillar: .w2_01_authGatesAndPrivacyDisclosure,
            coveredComponents: [
                "AuthFeatureFlags",
                "PrivacyProtectionView"
            ],
            endpointOrContract: "smsSendEnabled=false,wechatSignInEnabled=false,appleSignInEnabled=false",
            invariantSummary: "短信发送、微信登录与 Apple 登录门控默认关闭（fail-closed），隐私保护页披露完整摘要与协议状态。"
        ),
        AuthAndSessionAdmissionPillarRecord(
            pillar: .ios_i00_1_accountSessionRoleGate,
            coveredComponents: [
                "AccountSessionGate"
            ],
            endpointOrContract: userInfoEndpoint,
            invariantSummary: "GET /api/userInfo 必须返回非空合法服务端角色（USER / MERCHANT / CLUB_ADMIN）方可准入会话。"
        ),
        AuthAndSessionAdmissionPillarRecord(
            pillar: .w2_02_publicConfigAndOfficialEventUnavailable,
            coveredComponents: [
                "OfficialEventUnavailableError"
            ],
            endpointOrContract: publicConfigEndpoint,
            invariantSummary: "GET /api/config/public 公共发现与官方活动 404/410 下线状态安全降级展示，不崩溃不盲目重试。"
        )
    ]

    public let pillars: [AuthAndSessionAdmissionPillarRecord]
    public let authGates: AuthGateDefaultsSnapshot

    public init(
        pillars: [AuthAndSessionAdmissionPillarRecord] = AuthAndSessionAdmissionParityAudit.defaultPillars,
        authGates: AuthGateDefaultsSnapshot = .failClosedDefault
    ) {
        self.pillars = pillars
        self.authGates = authGates
    }

    public var isAllCompliant: Bool {
        pillars.count == AuthAndSessionAdmissionPillarID.allCases.count
            && pillars.allSatisfy(\.isCompliant)
            && authGates.isFailClosedByDefault
    }

    /// Evaluates `IOS-I00-1` session admission from `GET /api/userInfo` payload fields.
    public static func evaluateSessionAdmission(
        accountID: Int?,
        rawRole: String?
    ) -> SessionAdmissionAuditDecision {
        guard let accountID, accountID > 0 else {
            return .rejectedInvalidAccountID
        }
        guard let trimmedRole = rawRole?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedRole.isEmpty else {
            return .rejectedMissingRole
        }
        guard let role = AdmittedServerAccountRole(rawValue: trimmedRole) else {
            return .rejectedUnknownRole(trimmedRole)
        }
        return .admitted(accountID: accountID, role: role)
    }

    /// Evaluates `w2-02` official event HTTP status handling, mapping 404 and 410 to safe unavailable states (`OfficialEventUnavailableError`).
    public static func evaluateOfficialEventResponse(httpStatus: Int) -> OfficialEventAvailabilityAuditState {
        switch httpStatus {
        case 200:
            return .available
        case 404:
            return .safelyUnavailable(httpStatus: 404, fallbackHeadline: "官方活动不存在或已移除")
        case 410:
            return .safelyUnavailable(httpStatus: 410, fallbackHeadline: "官方活动已结束或已下线")
        default:
            return .retryableFailure(httpStatus: httpStatus)
        }
    }
}
