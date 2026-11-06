import Foundation

/// Snapshot of an `AppSession` context fence (`ContentDraftContextFence.matches` contract)
/// used to isolate account-scoped readers and draft mutations.
public struct AppSessionFenceSnapshot: Equatable, Sendable {
    public let accountID: String
    public let sessionEpoch: Int
    public let canonicalRole: String
    public let sessionRealm: String

    public init(
        accountID: String,
        sessionEpoch: Int,
        canonicalRole: String,
        sessionRealm: String
    ) {
        self.accountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sessionEpoch = sessionEpoch
        self.canonicalRole = canonicalRole.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.sessionRealm = sessionRealm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var isValid: Bool {
        !accountID.isEmpty &&
            sessionEpoch > 0 &&
            AppSessionCompositionAndFixtureShortCircuitAudit.isRecognizedServerRole(canonicalRole) &&
            !sessionRealm.isEmpty
    }

    /// Mirrors `ContentDraftContextFence.matches`: returns true only if the active session
    /// still matches every identity, epoch, role, and realm coordinate of the captured fence.
    public func matches(_ active: AppSessionFenceSnapshot?) -> Bool {
        guard let active, isValid, active.isValid else {
            return false
        }
        return accountID == active.accountID &&
            sessionEpoch == active.sessionEpoch &&
            canonicalRole == active.canonicalRole &&
            sessionRealm == active.sessionRealm
    }
}

/// Verdict for `AccountSessionGate` fail-closed session admission (`GET /api/userInfo`).
public enum AccountSessionAdmissionVerdict: Equatable, Sendable {
    case admitted(canonicalRole: String)
    case rejectedMissingRole
    case rejectedUnrecognizedRole(String)
    case rejectedInvalidAccountID
}

/// Deterministic audit report for `AppSessionContainer.init` fixture short-circuiting,
/// `ContentDraftContextFence.matches` reader composition, and `AccountSessionGate` admission.
public struct AppSessionCompositionAuditReport: Equatable, Sendable {
    public enum Violation: Equatable, Sendable {
        case fixtureLaunchDidNotShortCircuitSessionToNil(activeFlags: [String])
        case fixtureShortCircuitActivatedWithoutFixtureFlags
        case sessionAdmissionFailed(AccountSessionAdmissionVerdict)
        case staleOrCrossAccountReaderAccepted
    }

    public let activeFixtureFlags: [String]
    public let isFixtureShortCircuited: Bool
    public let admissionVerdict: AccountSessionAdmissionVerdict?
    public let contextFenceMatched: Bool
    public let violations: [Violation]

    public init(
        activeFixtureFlags: [String],
        isFixtureShortCircuited: Bool,
        admissionVerdict: AccountSessionAdmissionVerdict?,
        contextFenceMatched: Bool,
        violations: [Violation]
    ) {
        self.activeFixtureFlags = activeFixtureFlags
        self.isFixtureShortCircuited = isFixtureShortCircuited
        self.admissionVerdict = admissionVerdict
        self.contextFenceMatched = contextFenceMatched
        self.violations = violations
    }

    public var isCompliant: Bool {
        violations.isEmpty
    }
}

/// Pure auditor for `AppSessionContainer.init` short-circuiting (`session = nil`),
/// `AppSession` account-fenced reader composition (`ContentDraftContextFence.matches`),
/// and `AccountSessionGate` fail-closed session admission (`GET /api/userInfo`).
public enum AppSessionCompositionAndFixtureShortCircuitAudit {
    /// Launch arguments that must short-circuit `AppSessionContainer.init` so `session == nil`.
    public static let knownShortCircuitFixtureFlags: [String] = [
        "--uitesting",
        "--second-registration-fixture",
        "--merchant-city-template-handoff-fixture",
        "--merchant-ai-commerce-fixture",
        "--uitesting-map-core-entry"
    ]

    /// Canonical server roles accepted by `AccountSessionGate` on `GET /api/userInfo`.
    public static let recognizedServerRoles: Set<String> = [
        "USER",
        "PLAYER",
        "MERCHANT",
        "CLUB_ADMIN",
        "CLUB"
    ]

    public static func isRecognizedServerRole(_ rawRole: String?) -> Bool {
        guard let trimmed = rawRole?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !trimmed.isEmpty else {
            return false
        }
        return recognizedServerRoles.contains(trimmed)
    }

    public static func normalizeServerRole(_ rawRole: String?) -> String? {
        guard let trimmed = rawRole?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !trimmed.isEmpty else {
            return nil
        }
        switch trimmed {
        case "USER", "PLAYER":
            return "USER"
        case "MERCHANT":
            return "MERCHANT"
        case "CLUB_ADMIN", "CLUB":
            return "CLUB_ADMIN"
        default:
            return nil
        }
    }

    /// Evaluates `AccountSessionGate` fail-closed session admission from `GET /api/userInfo`.
    public static func evaluateSessionAdmission(
        accountID: String?,
        serverRole: String?
    ) -> AccountSessionAdmissionVerdict {
        guard let trimmedID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedID.isEmpty else {
            return .rejectedInvalidAccountID
        }
        guard let trimmedRole = serverRole?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedRole.isEmpty else {
            return .rejectedMissingRole
        }
        guard let normalized = normalizeServerRole(trimmedRole) else {
            return .rejectedUnrecognizedRole(trimmedRole)
        }
        return .admitted(canonicalRole: normalized)
    }

    /// Returns all active fixture flags in `launchArguments` that require `AppSessionContainer.init`
    /// to short-circuit `session = nil`.
    public static func activeFixtureShortCircuitFlags(in launchArguments: [String]) -> [String] {
        let knownSet = Set(knownShortCircuitFixtureFlags)
        var detected: Set<String> = []
        for raw in launchArguments {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if knownSet.contains(trimmed) || trimmed.hasSuffix("-fixture") || trimmed.hasPrefix("--uitesting") {
                detected.insert(trimmed)
            }
        }
        return detected.sorted()
    }

    /// Audits `AppSessionContainer.init` short-circuiting, `AccountSessionGate` admission,
    /// and `ContentDraftContextFence.matches` reader composition.
    public static func audit(
        launchArguments: [String],
        sessionIsNil: Bool,
        userInfoAccountID: String? = nil,
        userInfoServerRole: String? = nil,
        capturedReaderFence: AppSessionFenceSnapshot? = nil,
        activeSessionFence: AppSessionFenceSnapshot? = nil,
        didApplyReaderOutput: Bool = false
    ) -> AppSessionCompositionAuditReport {
        var violations: [AppSessionCompositionAuditReport.Violation] = []
        let activeFlags = activeFixtureShortCircuitFlags(in: launchArguments)

        if !activeFlags.isEmpty {
            if !sessionIsNil {
                violations.append(.fixtureLaunchDidNotShortCircuitSessionToNil(activeFlags: activeFlags))
            }
            return AppSessionCompositionAuditReport(
                activeFixtureFlags: activeFlags,
                isFixtureShortCircuited: sessionIsNil,
                admissionVerdict: nil,
                contextFenceMatched: false,
                violations: violations
            )
        }

        if sessionIsNil && userInfoAccountID != nil && userInfoServerRole != nil {
            let verdict = evaluateSessionAdmission(
                accountID: userInfoAccountID,
                serverRole: userInfoServerRole
            )
            if case .admitted = verdict {
                violations.append(.fixtureShortCircuitActivatedWithoutFixtureFlags)
            }
            return AppSessionCompositionAuditReport(
                activeFixtureFlags: [],
                isFixtureShortCircuited: true,
                admissionVerdict: verdict,
                contextFenceMatched: false,
                violations: violations
            )
        }

        var admissionVerdict: AccountSessionAdmissionVerdict?
        if userInfoAccountID != nil || userInfoServerRole != nil {
            let verdict = evaluateSessionAdmission(
                accountID: userInfoAccountID,
                serverRole: userInfoServerRole
            )
            admissionVerdict = verdict
            if case .admitted = verdict {
                // Valid admission.
            } else if !sessionIsNil {
                violations.append(.sessionAdmissionFailed(verdict))
            }
        }

        let fenceMatched: Bool
        if let capturedReaderFence {
            fenceMatched = capturedReaderFence.matches(activeSessionFence)
            if !fenceMatched && didApplyReaderOutput {
                violations.append(.staleOrCrossAccountReaderAccepted)
            }
        } else {
            fenceMatched = activeSessionFence?.isValid == true
        }

        return AppSessionCompositionAuditReport(
            activeFixtureFlags: [],
            isFixtureShortCircuited: sessionIsNil,
            admissionVerdict: admissionVerdict,
            contextFenceMatched: fenceMatched,
            violations: violations
        )
    }
}
