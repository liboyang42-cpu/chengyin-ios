import Foundation

/// Validator descriptor for a build/signing coordinate across `Config/Base.xcconfig`
/// (fail-closed repository defaults) and `Config/Local.xcconfig` (Day-3 production
/// TestFlight / App Store Archive signing coordinates).
public struct XcconfigSigningCoordinateCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let keyName: String
    public let baseDefaultIsFailClosedSafe: Bool
    public let validatesNonPlaceholderInReleaseArchive: Bool
    public let blocksLegacyMiniProgramHostInRelease: Bool

    public init(
        id: String? = nil,
        keyName: String,
        baseDefaultIsFailClosedSafe: Bool,
        validatesNonPlaceholderInReleaseArchive: Bool,
        blocksLegacyMiniProgramHostInRelease: Bool
    ) {
        self.id = id ?? keyName
        self.keyName = keyName
        self.baseDefaultIsFailClosedSafe = baseDefaultIsFailClosedSafe
        self.validatesNonPlaceholderInReleaseArchive = validatesNonPlaceholderInReleaseArchive
        self.blocksLegacyMiniProgramHostInRelease = blocksLegacyMiniProgramHostInRelease
    }

    public var isCompliant: Bool {
        baseDefaultIsFailClosedSafe
            && validatesNonPlaceholderInReleaseArchive
            && blocksLegacyMiniProgramHostInRelease
    }
}

/// Pure, self-contained validator contract for `Config/Base.xcconfig` fail-closed defaults
/// and `Config/Local.xcconfig` Day-3 production signing & regional archive coordinates.
public struct ProductionSigningAndLocalXcconfigValidatorContract: Sendable, Equatable {
    public static let forbiddenLegacyMiniProgramHost = "47.103.124.64"
    public static let placeholderBundleIdentifiers: Set<String> = [
        "invalid.example.questify.ios",
        "com.example.questify"
    ]

    public static let canonicalCoordinates: [XcconfigSigningCoordinateCheck] = [
        XcconfigSigningCoordinateCheck(
            id: "CODE_SIGNING_ALLOWED",
            keyName: "CODE_SIGNING_ALLOWED",
            baseDefaultIsFailClosedSafe: true,
            validatesNonPlaceholderInReleaseArchive: true,
            blocksLegacyMiniProgramHostInRelease: true
        ),
        XcconfigSigningCoordinateCheck(
            id: "DEVELOPMENT_TEAM",
            keyName: "DEVELOPMENT_TEAM",
            baseDefaultIsFailClosedSafe: true,
            validatesNonPlaceholderInReleaseArchive: true,
            blocksLegacyMiniProgramHostInRelease: true
        ),
        XcconfigSigningCoordinateCheck(
            id: "PRODUCT_BUNDLE_IDENTIFIER",
            keyName: "PRODUCT_BUNDLE_IDENTIFIER",
            baseDefaultIsFailClosedSafe: true,
            validatesNonPlaceholderInReleaseArchive: true,
            blocksLegacyMiniProgramHostInRelease: true
        ),
        XcconfigSigningCoordinateCheck(
            id: "QUESTIFY_API_BASE_URL",
            keyName: "QUESTIFY_API_BASE_URL",
            baseDefaultIsFailClosedSafe: true,
            validatesNonPlaceholderInReleaseArchive: true,
            blocksLegacyMiniProgramHostInRelease: true
        ),
        XcconfigSigningCoordinateCheck(
            id: "QUESTIFY_MARKET_AND_REALM",
            keyName: "QUESTIFY_MARKET_AND_REALM",
            baseDefaultIsFailClosedSafe: true,
            validatesNonPlaceholderInReleaseArchive: true,
            blocksLegacyMiniProgramHostInRelease: true
        )
    ]

    public static func evaluate(
        coordinates: [XcconfigSigningCoordinateCheck] = canonicalCoordinates
    ) -> (totalCoordinates: Int, compliantCoordinates: Int, isSigningValidatorReady: Bool) {
        let total = coordinates.count
        let compliant = coordinates.filter(\.isCompliant).count
        let isReady = total > 0 && compliant == total
        return (
            totalCoordinates: total,
            compliantCoordinates: compliant,
            isSigningValidatorReady: isReady
        )
    }

    public static func isValidReleaseBundleIdentifier(_ bundleID: String) -> Bool {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !placeholderBundleIdentifiers.contains(trimmed),
              !trimmed.lowercased().hasPrefix("invalid."),
              trimmed.contains(".") else {
            return false
        }
        return true
    }

    public static func isValidDevelopmentTeam(_ teamID: String) -> Bool {
        let trimmed = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 10 else { return false }
        return trimmed.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }

    public static func isAllowedReleaseAPIBaseURL(_ rawURL: String) -> Bool {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              host != forbiddenLegacyMiniProgramHost,
              host != "localhost",
              host != "127.0.0.1",
              !host.hasSuffix(".invalid"),
              !host.hasSuffix(".example.com") else {
            return false
        }
        return true
    }
}

// MARK: - Verifiable build-settings evidence

/// Result of validating real build-settings evidence (an xcconfig or the text output of
/// `xcodebuild -showBuildSettings`, supplied as a string). Empty/missing evidence never passes.
public struct ProductionSigningEvidenceResult: Sendable, Equatable {
    public let violations: [String]
    public var isReleaseEvidenceValid: Bool { violations.isEmpty }
}

extension ProductionSigningAndLocalXcconfigValidatorContract {
    public static let evidenceRequiredKeys: [String] = [
        "CODE_SIGNING_ALLOWED",
        "DEVELOPMENT_TEAM",
        "PRODUCT_BUNDLE_IDENTIFIER",
        "QUESTIFY_API_BASE_URL",
        "QUESTIFY_SESSION_REALM"
    ]

    /// Parses `KEY = VALUE` lines (xcconfig or `-showBuildSettings` output). Full-line `//`
    /// comments and unrelated lines are ignored; `$()` is resolved to empty as xcconfig does.
    public static func parseBuildSettings(_ text: String) -> [String: String] {
        var settings: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("//"), !line.hasPrefix("#"),
                  let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty,
                  key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { continue }
            let value = line[line.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "$()", with: "")
            settings[key] = value
        }
        return settings
    }

    static func isPlaceholderValue(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v.isEmpty || v.contains("<") || v.contains(">") || v.contains("invalid")
            || v.contains("placeholder") || v.contains("your_") || v.contains("example")
            || v.contains("changeme") || v.contains("todo")
    }

    public static func validateReleaseEvidence(settings: [String: String]) -> ProductionSigningEvidenceResult {
        var violations: [String] = []
        if settings.isEmpty {
            return ProductionSigningEvidenceResult(violations: ["no build settings evidence provided"])
        }
        let signing = settings["CODE_SIGNING_ALLOWED"]?.trimmingCharacters(in: .whitespaces).uppercased()
        if signing != "YES" {
            violations.append("CODE_SIGNING_ALLOWED must be YES for release evidence")
        }
        let team = settings["DEVELOPMENT_TEAM"] ?? ""
        if !isValidDevelopmentTeam(team) {
            violations.append("DEVELOPMENT_TEAM missing, empty or malformed")
        }
        let bundle = settings["PRODUCT_BUNDLE_IDENTIFIER"] ?? ""
        if !isValidReleaseBundleIdentifier(bundle) || isPlaceholderValue(bundle) {
            violations.append("PRODUCT_BUNDLE_IDENTIFIER missing or placeholder")
        }
        let api = settings["QUESTIFY_API_BASE_URL"] ?? ""
        if isPlaceholderValue(api) || !isAllowedReleaseAPIBaseURL(api) {
            violations.append("QUESTIFY_API_BASE_URL missing, placeholder or disallowed")
        }
        let realm = settings["QUESTIFY_SESSION_REALM"] ?? ""
        if isPlaceholderValue(realm) {
            violations.append("QUESTIFY_SESSION_REALM missing or placeholder")
        }
        return ProductionSigningEvidenceResult(violations: violations)
    }

    public static func validateReleaseEvidence(text: String) -> ProductionSigningEvidenceResult {
        validateReleaseEvidence(settings: parseBuildSettings(text))
    }
}
