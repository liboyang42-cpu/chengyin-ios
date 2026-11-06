import Foundation

/// Pure value-type contract modeling the end-to-end TestFlight and App Store Connect
/// archive sign-off checklist (`docs/release-readiness-checklist.md` & `Config/Base.xcconfig`).
public enum ReleaseArchiveAndTestFlightChecklistContract {
    public static let forbiddenLegacyHost = "47.103.124.64"
    public static let placeholderBundleIdentifiers: Set<String> = [
        "invalid.example.questify.ios",
        "com.example.questify",
        "<YOUR_PRODUCTION_BUNDLE_ID>"
    ]
    public static let placeholderDevelopmentTeams: Set<String> = [
        "<YOUR_APPLE_TEAM_ID>",
        "EXAMPLE",
        "PLACEHOLDER"
    ]

    public enum BlockerCode: String, CaseIterable, Equatable, Hashable, Sendable {
        case codeSigningNotAllowed = "CODE_SIGNING_NOT_ALLOWED"
        case missingOrPlaceholderDevelopmentTeam = "MISSING_OR_PLACEHOLDER_DEVELOPMENT_TEAM"
        case placeholderOrInvalidBundleIdentifier = "PLACEHOLDER_OR_INVALID_BUNDLE_IDENTIFIER"
        case invalidOrMissingMarket = "INVALID_OR_MISSING_MARKET"
        case missingOrNonHTTPSAPIBaseURL = "MISSING_OR_NON_HTTPS_API_BASE_URL"
        case forbiddenLegacyHostAPIBaseURL = "FORBIDDEN_LEGACY_HOST_API_BASE_URL"
        case missingOrMismatchedSessionRealm = "MISSING_OR_MISMATCHED_SESSION_REALM"
        case userInfoRoleAdmissionNotVerified = "USER_INFO_ROLE_ADMISSION_NOT_VERIFIED"
        case failClosedAllowlistsViolated = "FAIL_CLOSED_ALLOWLISTS_VIOLATED"
        case preArchiveVerificationIncomplete = "PRE_ARCHIVE_VERIFICATION_INCOMPLETE"
    }

    public enum ReadinessStatus: String, Equatable, Sendable {
        case readyForArchive = "READY_FOR_ARCHIVE"
        case blocked = "BLOCKED"
    }

    public enum PreArchiveCommand: String, CaseIterable, Equatable, Hashable, Sendable {
        case generateProject = "generate_project.py"
        case checkScaffold = "check_scaffold.py"
        case checkRoamPrivateTools = "check_roam_private_tools.py"
        case currentCICheck = "current_ci.py check"
        case testCurrentCI = "test_current_ci"

        public var commandLine: String {
            switch self {
            case .generateProject:
                return "python3 -B tools/generate_project.py"
            case .checkScaffold:
                return "python3 -B tools/check_scaffold.py"
            case .checkRoamPrivateTools:
                return "python3 -B tools/check_roam_private_tools.py"
            case .currentCICheck:
                return "python3 -B tools/current_ci.py check"
            case .testCurrentCI:
                return "python3 -B -m unittest -v tools.tests.test_current_ci"
            }
        }
    }

    public struct XCConfigOverrides: Equatable, Sendable {
        public let codeSigningAllowed: String
        public let developmentTeam: String
        public let productBundleIdentifier: String
        public let questifyMarket: String
        public let questifyAPIBaseURL: String
        public let questifySessionRealm: String

        public init(
            codeSigningAllowed: String,
            developmentTeam: String,
            productBundleIdentifier: String,
            questifyMarket: String,
            questifyAPIBaseURL: String,
            questifySessionRealm: String
        ) {
            self.codeSigningAllowed = codeSigningAllowed.trimmingCharacters(in: .whitespacesAndNewlines)
            self.developmentTeam = developmentTeam.trimmingCharacters(in: .whitespacesAndNewlines)
            self.productBundleIdentifier = productBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            self.questifyMarket = questifyMarket.trimmingCharacters(in: .whitespacesAndNewlines)
            self.questifyAPIBaseURL = questifyAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            self.questifySessionRealm = questifySessionRealm.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Represents the unconfigured `Config/Base.xcconfig` baseline before `Config/Local.xcconfig` overrides.
        public static let unconfiguredBase = XCConfigOverrides(
            codeSigningAllowed: "NO",
            developmentTeam: "",
            productBundleIdentifier: "invalid.example.questify.ios",
            questifyMarket: "CN",
            questifyAPIBaseURL: "",
            questifySessionRealm: ""
        )
    }

    public struct PreArchiveSuiteReport: Equatable, Sendable {
        public let passedCommands: Set<PreArchiveCommand>

        public init(passedCommands: Set<PreArchiveCommand>) {
            self.passedCommands = passedCommands
        }

        public static let allPassed = PreArchiveSuiteReport(
            passedCommands: Set(PreArchiveCommand.allCases)
        )

        public var missingCommands: [PreArchiveCommand] {
            PreArchiveCommand.allCases.filter { !passedCommands.contains($0) }
        }

        public var isComplete: Bool {
            missingCommands.isEmpty
        }
    }

    public struct EvaluationResult: Equatable, Sendable {
        public let status: ReadinessStatus
        public let blockerCodes: [BlockerCode]
        public let missingPreArchiveCommands: [PreArchiveCommand]
        public let normalizedMarket: String?

        public var isReadyForArchive: Bool {
            status == .readyForArchive && blockerCodes.isEmpty
        }
    }

    /// Evaluates the full release archive & TestFlight readiness checklist deterministically.
    public static func evaluateChecklist(
        xcconfig: XCConfigOverrides,
        preArchiveSuite: PreArchiveSuiteReport = .allPassed,
        userInfoRoleAdmissionVerified: Bool = true,
        failClosedAllowlistsIntact: Bool = true
    ) -> EvaluationResult {
        var blockers: [BlockerCode] = []

        if xcconfig.codeSigningAllowed != "YES" {
            blockers.append(.codeSigningNotAllowed)
        }

        if !isValidDevelopmentTeam(xcconfig.developmentTeam) {
            blockers.append(.missingOrPlaceholderDevelopmentTeam)
        }

        if !isValidBundleIdentifier(xcconfig.productBundleIdentifier) {
            blockers.append(.placeholderOrInvalidBundleIdentifier)
        }

        let validMarket: String?
        if xcconfig.questifyMarket == "CN" || xcconfig.questifyMarket == "US" {
            validMarket = xcconfig.questifyMarket
        } else {
            validMarket = nil
            blockers.append(.invalidOrMissingMarket)
        }

        let urlStatus = validateAPIBaseURL(xcconfig.questifyAPIBaseURL)
        blockers.append(contentsOf: urlStatus)

        if !isValidSessionRealm(xcconfig.questifySessionRealm, market: validMarket) {
            blockers.append(.missingOrMismatchedSessionRealm)
        }

        if !userInfoRoleAdmissionVerified {
            blockers.append(.userInfoRoleAdmissionNotVerified)
        }

        if !failClosedAllowlistsIntact {
            blockers.append(.failClosedAllowlistsViolated)
        }

        let missingCommands = preArchiveSuite.missingCommands
        if !missingCommands.isEmpty {
            blockers.append(.preArchiveVerificationIncomplete)
        }

        return EvaluationResult(
            status: blockers.isEmpty ? .readyForArchive : .blocked,
            blockerCodes: blockers,
            missingPreArchiveCommands: missingCommands,
            normalizedMarket: validMarket
        )
    }

    private static func isValidDevelopmentTeam(_ team: String) -> Bool {
        guard !team.isEmpty,
              !placeholderDevelopmentTeams.contains(team),
              !team.contains("<"),
              !team.contains(">") else {
            return false
        }
        return team.range(of: "\\A[A-Z0-9]{10}\\z", options: .regularExpression) != nil
    }

    private static func isValidBundleIdentifier(_ bundleID: String) -> Bool {
        let lowered = bundleID.lowercased()
        guard !bundleID.isEmpty,
              !placeholderBundleIdentifiers.contains(bundleID),
              !lowered.contains("example"),
              !bundleID.contains("<"),
              !bundleID.contains(">") else {
            return false
        }
        return bundleID.range(
            of: "\\A[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*(?:\\.[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*)+\\z",
            options: .regularExpression
        ) != nil
    }

    private static func validateAPIBaseURL(_ rawURL: String) -> [BlockerCode] {
        guard !rawURL.isEmpty,
              !rawURL.contains("<"),
              !rawURL.contains(">"),
              let components = URLComponents(string: rawURL),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              !host.contains("example") else {
            return [.missingOrNonHTTPSAPIBaseURL]
        }
        if host == forbiddenLegacyHost || rawURL.contains(forbiddenLegacyHost) {
            return [.forbiddenLegacyHostAPIBaseURL]
        }
        return []
    }

    private static func isValidSessionRealm(_ realm: String, market: String?) -> Bool {
        guard let market, !realm.isEmpty else { return false }
        let expectedPrefix = market.lowercased() + "-"
        guard realm.lowercased().hasPrefix(expectedPrefix),
              realm.count > expectedPrefix.count else {
            return false
        }
        return realm.range(of: "\\A[a-z0-9]+(?:-[a-z0-9]+)+\\z", options: .regularExpression) != nil
    }
}
