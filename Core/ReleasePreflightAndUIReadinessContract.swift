import Foundation

/// Release pre-flight verification and deterministic UI readiness / accessibility anchor
/// contract (`docs/release-readiness-checklist.md` & `PROGRESS.md` CI stabilization).
public enum ReleasePreflightAndUIReadinessContract {
    /// Legacy mini-program host that must never be used as `QUESTIFY_API_BASE_URL` in release archives.
    public static let forbiddenLegacyMiniProgramHost = "47.103.124.64"
    /// Default unconfigured bundle identifiers in `Config/Base.xcconfig` and release checklist docs.
    public static let placeholderBundleIdentifier = "invalid.example.questify.ios"
    public static let legacyPlaceholderBundleIdentifier = "com.example.questify"

    /// Explicit regional market profile for release archive isolation (`CN` vs `US`).
    public enum MarketProfile: String, CaseIterable, Equatable, Sendable {
        case cn = "CN"
        case us = "US"

        public static func parse(_ raw: String?) -> Self? {
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                  !trimmed.isEmpty else { return nil }
            return Self(rawValue: trimmed)
        }

        /// Expected realm prefix for strict regional session isolation (`cn-*` vs `us-*`).
        public var requiredRealmPrefix: String {
            switch self {
            case .cn: return "cn-"
            case .us: return "us-"
            }
        }

        /// Validates that the session realm is non-empty and belongs to this market without cross-market contamination.
        public func acceptsSessionRealm(_ rawRealm: String?) -> Bool {
            guard let realm = rawRealm?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !realm.isEmpty,
                  realm.count <= 64,
                  realm.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
                return false
            }
            let foreignPrefix = self == .cn ? "us-" : "cn-"
            guard !realm.hasPrefix(foreignPrefix) else { return false }
            return realm.hasPrefix(requiredRealmPrefix)
        }
    }

    /// `IOS-I00-1` (`AccountSessionGate`) server role requirement on `GET /api/userInfo`.
    public enum CanonicalServerRole: String, CaseIterable, Equatable, Sendable {
        case user = "USER"
        case merchant = "MERCHANT"
        case clubAdmin = "CLUB_ADMIN"

        /// Maps either raw backend role (`USER` / `MERCHANT` / `CLUB_ADMIN`) or normalized
        /// client role (`player` / `merchant` / `club`). Empty or unknown strings fail closed.
        public static func resolve(_ rawRole: String?) -> Self? {
            guard let trimmed = rawRole?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { return nil }
            switch trimmed.uppercased() {
            case "USER", "PLAYER":
                return .user
            case "MERCHANT":
                return .merchant
            case "CLUB_ADMIN", "CLUB":
                return .clubAdmin
            default:
                return nil
            }
        }
    }

    /// Result of `IOS-I00-1` session admission role verification.
    public enum SessionAdmissionEvaluation: Equatable, Sendable {
        case admitted(CanonicalServerRole)
        case missingOrEmptyRole
        case unrecognizedRole(String)
    }

    /// Evaluates `IOS-I00-1` fail-closed session admission for a server `userInfo` role projection.
    public static func evaluateSessionAdmission(serverRole: String?) -> SessionAdmissionEvaluation {
        guard let trimmed = serverRole?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return .missingOrEmptyRole
        }
        guard let canonical = CanonicalServerRole.resolve(trimmed) else {
            return .unrecognizedRole(trimmed)
        }
        return .admitted(canonical)
    }

    /// Reasons an API base URL is rejected by release preflight.
    public enum APIBaseURLViolation: Error, Equatable, Sendable {
        case missingOrMalformed
        case nonHTTPS
        case legacyMiniProgramHostRejected
        case placeholderOrLoopbackHost
        case containsCredentialsQueryOrFragment
    }

    /// Validates `QUESTIFY_API_BASE_URL` for release readiness, explicitly rejecting `47.103.124.64`.
    public static func validateAPIBaseURL(_ rawURL: String?) -> Result<URL, APIBaseURLViolation> {
        guard let trimmed = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let url = components.url,
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return .failure(.missingOrMalformed)
        }
        if host == forbiddenLegacyMiniProgramHost || trimmed.contains(forbiddenLegacyMiniProgramHost) {
            return .failure(.legacyMiniProgramHostRejected)
        }
        guard components.scheme?.lowercased() == "https" else {
            return .failure(.nonHTTPS)
        }
        if components.user != nil || components.password != nil || components.query != nil || components.fragment != nil {
            return .failure(.containsCredentialsQueryOrFragment)
        }
        let forbiddenSuffixes = [".invalid", ".test", ".localhost"]
        if host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0" ||
            host == placeholderBundleIdentifier || host == legacyPlaceholderBundleIdentifier ||
            host.hasPrefix("invalid.") ||
            forbiddenSuffixes.contains(where: { host == String($0.dropFirst()) || host.hasSuffix($0) }) ||
            isRawIPv4Address(host) {
            return .failure(.placeholderOrLoopbackHost)
        }
        return .success(url)
    }

    private static func isRawIPv4Address(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let octet = Int(part), (0...255).contains(octet) else { return false }
            return String(octet) == part
        }
    }

    /// High-risk feature / write gates that must remain fail-closed (`false`) unless signed off.
    public struct EndpointAllowlistGates: Equatable, Sendable {
        public enum GateIdentifier: String, CaseIterable, Comparable, Sendable {
            case smsSend = "w2-01.smsSendEnabled"
            case wechatSignIn = "w2-01.wechatSignInEnabled"
            case appleSignIn = "w2-01.appleSignInEnabled"
            case paymentAndWithdrawal = "w2-03-05.paymentAndWithdrawalEnabled"
            case topicLikeWrite = "I05.topicLikeGrantEnabled"
            case npcChatRemoteDelete = "I08.npcChatRemoteDeleteEnabled"

            public static func < (lhs: Self, rhs: Self) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        public var smsSendEnabled: Bool
        public var wechatSignInEnabled: Bool
        public var appleSignInEnabled: Bool
        public var paymentAndWithdrawalEnabled: Bool
        public var topicLikeGrantEnabled: Bool
        public var npcChatRemoteDeleteEnabled: Bool
        public var approvedGates: Set<GateIdentifier>
        public var unreviewedWriteRoutes: Set<String>

        public init(
            smsSendEnabled: Bool = false,
            wechatSignInEnabled: Bool = false,
            appleSignInEnabled: Bool = false,
            paymentAndWithdrawalEnabled: Bool = false,
            topicLikeGrantEnabled: Bool = false,
            npcChatRemoteDeleteEnabled: Bool = false,
            approvedGates: Set<GateIdentifier> = [],
            unreviewedWriteRoutes: Set<String> = []
        ) {
            self.smsSendEnabled = smsSendEnabled
            self.wechatSignInEnabled = wechatSignInEnabled
            self.appleSignInEnabled = appleSignInEnabled
            self.paymentAndWithdrawalEnabled = paymentAndWithdrawalEnabled
            self.topicLikeGrantEnabled = topicLikeGrantEnabled
            self.npcChatRemoteDeleteEnabled = npcChatRemoteDeleteEnabled
            self.approvedGates = approvedGates
            self.unreviewedWriteRoutes = unreviewedWriteRoutes
        }

        /// True when all high-risk gates are disabled and no unreviewed write routes are present.
        public var isFailClosedDefault: Bool {
            enabledGates.isEmpty && unreviewedWriteRoutes.isEmpty
        }

        public var enabledGates: Set<GateIdentifier> {
            var set: Set<GateIdentifier> = []
            if smsSendEnabled { set.insert(.smsSend) }
            if wechatSignInEnabled { set.insert(.wechatSignIn) }
            if appleSignInEnabled { set.insert(.appleSignIn) }
            if paymentAndWithdrawalEnabled { set.insert(.paymentAndWithdrawal) }
            if topicLikeGrantEnabled { set.insert(.topicLikeWrite) }
            if npcChatRemoteDeleteEnabled { set.insert(.npcChatRemoteDelete) }
            return set
        }

        /// Gates that are enabled without an explicit compliance sign-off in `approvedGates`.
        public var unapprovedEnabledGates: [GateIdentifier] {
            enabledGates.subtracting(approvedGates).sorted()
        }
    }

    /// Build/signing coordinates from `Config/Base.xcconfig` or `Config/Local.xcconfig`.
    public struct BuildCoordinates: Equatable, Sendable {
        public let codeSigningAllowed: Bool
        public let bundleIdentifier: String
        public let developmentTeam: String
        public let rawMarket: String
        public let rawAPIBaseURL: String
        public let rawSessionRealm: String

        public init(
            codeSigningAllowed: Bool,
            bundleIdentifier: String,
            developmentTeam: String = "",
            rawMarket: String,
            rawAPIBaseURL: String,
            rawSessionRealm: String
        ) {
            self.codeSigningAllowed = codeSigningAllowed
            self.bundleIdentifier = bundleIdentifier
            self.developmentTeam = developmentTeam
            self.rawMarket = rawMarket
            self.rawAPIBaseURL = rawAPIBaseURL
            self.rawSessionRealm = rawSessionRealm
        }

        /// Safe unconfigured `Config/Base.xcconfig` defaults used in CI.
        public static let safeBaseDefaults = BuildCoordinates(
            codeSigningAllowed: false,
            bundleIdentifier: placeholderBundleIdentifier,
            developmentTeam: "",
            rawMarket: "",
            rawAPIBaseURL: "",
            rawSessionRealm: ""
        )

        public var isSafeUnconfiguredCIDefault: Bool {
            let trimmedBundle = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let isPlaceholderBundle = trimmedBundle == placeholderBundleIdentifier ||
                trimmedBundle == legacyPlaceholderBundleIdentifier
            return !codeSigningAllowed &&
                isPlaceholderBundle &&
                rawAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                rawSessionRealm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Specific violations detected during release preflight verification.
    public enum PreflightViolation: Equatable, Sendable {
        case codeSigningDisabled
        case placeholderOrEmptyBundleIdentifier
        case missingDevelopmentTeam
        case invalidOrMissingMarket
        case crossMarketOrInvalidSessionRealm
        case apiBaseURLViolation(APIBaseURLViolation)
        case sessionAdmissionRoleRejected(SessionAdmissionEvaluation)
        case unapprovedHighRiskGates([EndpointAllowlistGates.GateIdentifier])
        case unreviewedWriteRoutesPresent([String])
    }

    /// Runs all release preflight checks for a candidate TestFlight / App Store archive.
    public static func verifyReleasePreflight(
        coordinates: BuildCoordinates,
        serverUserInfoRole: String?,
        gates: EndpointAllowlistGates = .init()
    ) -> [PreflightViolation] {
        var violations: [PreflightViolation] = []

        if !coordinates.codeSigningAllowed {
            violations.append(.codeSigningDisabled)
        }
        let bundleID = coordinates.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if bundleID.isEmpty ||
            bundleID == placeholderBundleIdentifier ||
            bundleID == legacyPlaceholderBundleIdentifier ||
            bundleID.hasPrefix("invalid.") ||
            !bundleID.contains(".") {
            violations.append(.placeholderOrEmptyBundleIdentifier)
        }
        if coordinates.developmentTeam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            violations.append(.missingDevelopmentTeam)
        }
        if let market = MarketProfile.parse(coordinates.rawMarket) {
            if !market.acceptsSessionRealm(coordinates.rawSessionRealm) {
                violations.append(.crossMarketOrInvalidSessionRealm)
            }
        } else {
            violations.append(.invalidOrMissingMarket)
        }

        if case .failure(let urlViolation) = validateAPIBaseURL(coordinates.rawAPIBaseURL) {
            violations.append(.apiBaseURLViolation(urlViolation))
        }

        let roleEval = evaluateSessionAdmission(serverRole: serverUserInfoRole)
        if case .admitted = roleEval {
            // Valid server role for IOS-I00-1.
        } else {
            violations.append(.sessionAdmissionRoleRejected(roleEval))
        }

        let unapproved = gates.unapprovedEnabledGates
        if !unapproved.isEmpty {
            violations.append(.unapprovedHighRiskGates(unapproved))
        }
        let unreviewed = gates.unreviewedWriteRoutes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        if !unreviewed.isEmpty {
            violations.append(.unreviewedWriteRoutesPresent(unreviewed))
        }

        return violations
    }
}

/// Key UI flow surfaces tracked for deterministic UI readiness and accessibility anchor verification.
public enum UIReadinessFlowSurface: String, CaseIterable, Equatable, Sendable {
    case projectEditor
    case profileSelfEdit
    case roamFinishedHistory
    case couponRuntimeJourney
    case mapCoreEntry
}

/// Deterministic accessibility anchor contract and off-screen reveal requirement for a UI surface.
public struct UIReadinessAnchorContract: Equatable, Sendable {
    public let surface: UIReadinessFlowSurface
    public let rootAccessibilityIdentifier: String
    public let primaryInteractiveAnchorIdentifier: String
    public let requiredAnchorIdentifiers: [String]
    /// True when the primary field may be below the fold inside a `Form` / `List` and must be
    /// explicitly revealed (e.g. `revealProjectEditorNameInForm`) before UI tests or hosts interact.
    public let requiresOffScreenFormReveal: Bool
    public let revealHelperIdentifier: String?

    public init(
        surface: UIReadinessFlowSurface,
        rootAccessibilityIdentifier: String,
        primaryInteractiveAnchorIdentifier: String,
        requiredAnchorIdentifiers: [String],
        requiresOffScreenFormReveal: Bool,
        revealHelperIdentifier: String? = nil
    ) {
        self.surface = surface
        self.rootAccessibilityIdentifier = rootAccessibilityIdentifier
        self.primaryInteractiveAnchorIdentifier = primaryInteractiveAnchorIdentifier
        self.requiredAnchorIdentifiers = requiredAnchorIdentifiers
        self.requiresOffScreenFormReveal = requiresOffScreenFormReveal
        self.revealHelperIdentifier = revealHelperIdentifier
    }

    public static func contract(for surface: UIReadinessFlowSurface) -> Self {
        switch surface {
        case .projectEditor:
            return Self(
                surface: .projectEditor,
                rootAccessibilityIdentifier: "projectEditor.form",
                primaryInteractiveAnchorIdentifier: "projectEditor.name",
                requiredAnchorIdentifiers: [
                    "projectEditor.form",
                    "projectEditor.name",
                    "projectEditor.reviewReadiness"
                ],
                requiresOffScreenFormReveal: true,
                revealHelperIdentifier: "revealProjectEditorNameInForm"
            )
        case .profileSelfEdit:
            return Self(
                surface: .profileSelfEdit,
                rootAccessibilityIdentifier: "profileSelfEdit.form",
                primaryInteractiveAnchorIdentifier: "profileSelfEdit.nickname",
                requiredAnchorIdentifiers: [
                    "profileSelfEdit.form",
                    "profileSelfEdit.nickname",
                    "profileSelfEdit.review"
                ],
                requiresOffScreenFormReveal: false,
                revealHelperIdentifier: nil
            )
        case .roamFinishedHistory:
            return Self(
                surface: .roamFinishedHistory,
                rootAccessibilityIdentifier: "roamFinishedHistory.list",
                primaryInteractiveAnchorIdentifier: "roamFinishedHistory.filter",
                requiredAnchorIdentifiers: [
                    "roamFinishedHistory.list",
                    "roamFinishedHistory.filter"
                ],
                requiresOffScreenFormReveal: false,
                revealHelperIdentifier: nil
            )
        case .couponRuntimeJourney:
            return Self(
                surface: .couponRuntimeJourney,
                rootAccessibilityIdentifier: "couponRuntime.root",
                primaryInteractiveAnchorIdentifier: "couponRuntime.readOnlyConfirm",
                requiredAnchorIdentifiers: [
                    "couponRuntime.root",
                    "couponRuntime.readOnlyConfirm"
                ],
                requiresOffScreenFormReveal: false,
                revealHelperIdentifier: nil
            )
        case .mapCoreEntry:
            return Self(
                surface: .mapCoreEntry,
                rootAccessibilityIdentifier: "mapCore.root",
                primaryInteractiveAnchorIdentifier: "mapCore.manualBrowse",
                requiredAnchorIdentifiers: [
                    "mapCore.root",
                    "mapCore.manualBrowse"
                ],
                requiresOffScreenFormReveal: false,
                revealHelperIdentifier: nil
            )
        }
    }

    public static var allContracts: [Self] {
        UIReadinessFlowSurface.allCases.map(contract(for:))
    }

    public enum ReadinessEvaluation: Equatable, Sendable {
        case ready
        case missingAnchors([String])
        case awaitingOffScreenReveal(helper: String, targetAnchor: String)
    }

    /// Evaluates whether the surface's required accessibility anchors are mounted and any
    /// required off-screen `Form` scroll reveal has been completed before interaction.
    public func evaluateReadiness(
        mountedIdentifiers: Set<String>,
        offScreenRevealed: Bool
    ) -> ReadinessEvaluation {
        let missing = requiredAnchorIdentifiers.filter { !mountedIdentifiers.contains($0) }
        if !missing.isEmpty {
            return .missingAnchors(missing)
        }
        if requiresOffScreenFormReveal && !offScreenRevealed {
            return .awaitingOffScreenReveal(
                helper: revealHelperIdentifier ?? "revealInForm",
                targetAnchor: primaryInteractiveAnchorIdentifier
            )
        }
        return .ready
    }
}
