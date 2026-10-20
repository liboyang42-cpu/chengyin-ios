import Foundation

extension RegionalMarket: Sendable {}

/// High-risk write endpoints that must remain fail-closed (blocked by default) across both
/// `CN` and `US` regional builds unless explicitly allowlisted for the active market.
public enum RegionalHighRiskWriteRoute: String, CaseIterable, Comparable, Hashable, Sendable {
    case assetWithdraw = "/api/asset/withdraw"
    case payCreate = "/api/pay/create"
    case npcChatDelete = "/api/npc/chat/delete"
    case topicLike = "/api/topic/like"
    case userSMSSend = "/api/user/sms/send"
    case merchantDecorSave = "/api/merchant/decor/save"

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static var canonicalPaths: [String] {
        allCases.map(\.rawValue)
    }

    /// Normalizes a route path or URL path component to a leading-slash canonical path.
    public static func normalizePath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let components = URLComponents(string: trimmed),
           components.scheme != nil || components.host != nil {
            let urlPath = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlPath.isEmpty else { return "/" }
            return urlPath.hasPrefix("/") ? urlPath : "/" + urlPath
        }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }

    public static func match(_ rawPathOrURL: String) -> Self? {
        let normalized = normalizePath(rawPathOrURL)
        return Self(rawValue: normalized)
    }
}

/// Deterministic release-preflight audit report for regional endpoint allowlist isolation (`CN` vs `US`).
public struct RegionalEndpointAuditReport: Equatable, Sendable {
    public enum RejectionReason: Equatable, Sendable {
        case legacyMiniProgramHostRejected
        case unapprovedOrMissingBaseURL
        case invalidEndpointURL
        case crossMarketEndpointIsolation
        case highRiskWriteBlockedByDefault
        case unallowlistedRoute
    }

    public struct RouteDecision: Equatable, Sendable {
        public let route: String
        public let isHighRiskWrite: Bool
        public let isAllowed: Bool
        public let rejectionReason: RejectionReason?

        public init(
            route: String,
            isHighRiskWrite: Bool,
            isAllowed: Bool,
            rejectionReason: RejectionReason?
        ) {
            self.route = route
            self.isHighRiskWrite = isHighRiskWrite
            self.isAllowed = isAllowed
            self.rejectionReason = rejectionReason
        }
    }

    public enum Violation: Equatable, Sendable {
        case legacyMiniProgramHostDetected(String)
        case unapprovedMarketBaseURL(String)
        case crossMarketBaseURLContamination(String)
        case unapprovedHighRiskWriteEnabled(String)
    }

    public let market: RegionalMarket
    public let evaluatedBaseURL: String?
    public let isBaseURLApproved: Bool
    public let rejectedLegacyMiniProgramURLs: [String]
    public let blockedHighRiskRoutes: [String]
    public let allowlistedHighRiskRoutes: [String]
    public let routeDecisions: [RouteDecision]
    public let violations: [Violation]

    public init(
        market: RegionalMarket,
        evaluatedBaseURL: String?,
        isBaseURLApproved: Bool,
        rejectedLegacyMiniProgramURLs: [String],
        blockedHighRiskRoutes: [String],
        allowlistedHighRiskRoutes: [String],
        routeDecisions: [RouteDecision],
        violations: [Violation]
    ) {
        self.market = market
        self.evaluatedBaseURL = evaluatedBaseURL
        self.isBaseURLApproved = isBaseURLApproved
        self.rejectedLegacyMiniProgramURLs = rejectedLegacyMiniProgramURLs
        self.blockedHighRiskRoutes = blockedHighRiskRoutes
        self.allowlistedHighRiskRoutes = allowlistedHighRiskRoutes
        self.routeDecisions = routeDecisions
        self.violations = violations
    }

    /// True when all 6 high-risk write routes remain blocked and no legacy host or cross-market violations exist.
    public var isFailClosedDefaultCompliant: Bool {
        allowlistedHighRiskRoutes.isEmpty &&
            Set(blockedHighRiskRoutes) == Set(RegionalHighRiskWriteRoute.canonicalPaths) &&
            rejectedLegacyMiniProgramURLs.isEmpty &&
            violations.isEmpty
    }

    /// True when no legacy `47.103.124.64` URLs or policy violations were detected.
    public var passesReleasePreflight: Bool {
        rejectedLegacyMiniProgramURLs.isEmpty && violations.isEmpty
    }

    public func decision(for route: RegionalHighRiskWriteRoute) -> RouteDecision? {
        routeDecisions.first { $0.route == route.rawValue }
    }

    public func decision(forPath rawPath: String) -> RouteDecision? {
        let normalized = RegionalHighRiskWriteRoute.normalizePath(rawPath)
        return routeDecisions.first { $0.route == normalized }
    }
}

/// Pure auditor enforcing `CN` vs `US` endpoint allowlist isolation, default fail-closed blocking
/// of high-risk write endpoints, and rejection of the legacy mini-program host `47.103.124.64`.
public enum RegionalEndpointAllowlistAudit {
    /// Legacy mini-program IP host that must never be used in any regional configuration or endpoint URL.
    public static let forbiddenLegacyMiniProgramHost = "47.103.124.64"

    /// Canonical list of high-risk write routes audited on every release preflight check.
    public static var requiredHighRiskWriteRoutes: [String] {
        RegionalHighRiskWriteRoute.canonicalPaths
    }

    /// Returns true if the candidate URL string or `URL` targets the legacy mini-program host `47.103.124.64`.
    public static func targetsLegacyMiniProgramHost(_ rawURL: String?) -> Bool {
        guard let trimmed = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return false
        }
        if let components = URLComponents(string: trimmed),
           let host = components.host?.lowercased(),
           host == forbiddenLegacyMiniProgramHost {
            return true
        }
        return trimmed.contains(forbiddenLegacyMiniProgramHost)
    }

    /// Evaluates whether a single endpoint URL or route is permitted for the active regional market.
    public static func evaluateEndpoint(
        urlOrPath: String,
        market: RegionalMarket,
        baseURL: String?,
        approvedBaseURLs: [RegionalMarket: Set<String>] = [:],
        allowlistedWriteRoutes: [RegionalMarket: Set<String>] = [:]
    ) -> RegionalEndpointAuditReport.RouteDecision {
        let trimmedTarget = urlOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = RegionalHighRiskWriteRoute.normalizePath(trimmedTarget)
        let isHighRisk = RegionalHighRiskWriteRoute.match(normalizedPath) != nil

        if targetsLegacyMiniProgramHost(trimmedTarget) || targetsLegacyMiniProgramHost(baseURL) {
            return RegionalEndpointAuditReport.RouteDecision(
                route: normalizedPath.isEmpty ? trimmedTarget : normalizedPath,
                isHighRiskWrite: isHighRisk,
                isAllowed: false,
                rejectionReason: .legacyMiniProgramHostRejected
            )
        }

        // If `urlOrPath` is a full URL, verify its scheme and origin match the active market's approved base URL.
        if let targetComponents = URLComponents(string: trimmedTarget),
           targetComponents.scheme != nil || targetComponents.host != nil {
            guard targetComponents.scheme?.lowercased() == "https",
                  let targetHost = targetComponents.host, !targetHost.isEmpty,
                  targetComponents.user == nil, targetComponents.password == nil else {
                return RegionalEndpointAuditReport.RouteDecision(
                    route: normalizedPath,
                    isHighRiskWrite: isHighRisk,
                    isAllowed: false,
                    rejectionReason: .invalidEndpointURL
                )
            }
            let foreignMarket: RegionalMarket = market == .china ? .unitedStates : .china
            if let foreignSet = approvedBaseURLs[foreignMarket],
               foreignSet.contains(where: { trimmedTarget.hasPrefix($0) }) {
                return RegionalEndpointAuditReport.RouteDecision(
                    route: normalizedPath,
                    isHighRiskWrite: isHighRisk,
                    isAllowed: false,
                    rejectionReason: .crossMarketEndpointIsolation
                )
            }
        }

        let trimmedBase = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let foreignMarket: RegionalMarket = market == .china ? .unitedStates : .china
        if !trimmedBase.isEmpty,
           approvedBaseURLs[foreignMarket]?.contains(trimmedBase) == true,
           approvedBaseURLs[market]?.contains(trimmedBase) != true {
            return RegionalEndpointAuditReport.RouteDecision(
                route: normalizedPath,
                isHighRiskWrite: isHighRisk,
                isAllowed: false,
                rejectionReason: .crossMarketEndpointIsolation
            )
        }

        let isBaseApproved: Bool
        if !trimmedBase.isEmpty,
           let parsedBase = URL(string: trimmedBase),
           (try? APIConfiguration(baseURL: parsedBase)) != nil,
           approvedBaseURLs[market]?.contains(trimmedBase) == true {
            isBaseApproved = true
        } else {
            isBaseApproved = false
        }

        guard isBaseApproved else {
            return RegionalEndpointAuditReport.RouteDecision(
                route: normalizedPath,
                isHighRiskWrite: isHighRisk,
                isAllowed: false,
                rejectionReason: .unapprovedOrMissingBaseURL
            )
        }

        let marketAllowlist = Set(
            (allowlistedWriteRoutes[market] ?? []).map(RegionalHighRiskWriteRoute.normalizePath)
        )

        if isHighRisk {
            guard marketAllowlist.contains(normalizedPath) else {
                return RegionalEndpointAuditReport.RouteDecision(
                    route: normalizedPath,
                    isHighRiskWrite: true,
                    isAllowed: false,
                    rejectionReason: .highRiskWriteBlockedByDefault
                )
            }
            return RegionalEndpointAuditReport.RouteDecision(
                route: normalizedPath,
                isHighRiskWrite: true,
                isAllowed: true,
                rejectionReason: nil
            )
        }

        guard marketAllowlist.contains(normalizedPath) else {
            return RegionalEndpointAuditReport.RouteDecision(
                route: normalizedPath,
                isHighRiskWrite: false,
                isAllowed: false,
                rejectionReason: .unallowlistedRoute
            )
        }

        return RegionalEndpointAuditReport.RouteDecision(
            route: normalizedPath,
            isHighRiskWrite: false,
            isAllowed: true,
            rejectionReason: nil
        )
    }

    /// Generates a deterministic `RegionalEndpointAuditReport` for release preflight inspection.
    public static func audit(
        market: RegionalMarket,
        baseURL: String? = nil,
        approvedBaseURLs: [RegionalMarket: Set<String>] = [:],
        allowlistedWriteRoutes: [RegionalMarket: Set<String>] = [:],
        signedOffHighRiskRoutes: [RegionalMarket: Set< RegionalHighRiskWriteRoute >]? = nil,
        additionalCandidateURLs: [String] = []
    ) -> RegionalEndpointAuditReport {
        let trimmedBase = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBase = (trimmedBase?.isEmpty == true) ? nil : trimmedBase

        var rejectedLegacyURLs: Set<String> = []
        var violations: [RegionalEndpointAuditReport.Violation] = []

        if let normalizedBase, targetsLegacyMiniProgramHost(normalizedBase) {
            rejectedLegacyURLs.insert(normalizedBase)
            violations.append(.legacyMiniProgramHostDetected(normalizedBase))
        }

        for (_, urls) in approvedBaseURLs {
            for candidate in urls.sorted() where targetsLegacyMiniProgramHost(candidate) {
                if rejectedLegacyURLs.insert(candidate).inserted {
                    violations.append(.legacyMiniProgramHostDetected(candidate))
                }
            }
        }

        for candidate in additionalCandidateURLs where targetsLegacyMiniProgramHost(candidate) {
            let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if rejectedLegacyURLs.insert(cleaned).inserted {
                violations.append(.legacyMiniProgramHostDetected(cleaned))
            }
        }

        let foreignMarket: RegionalMarket = market == .china ? .unitedStates : .china
        let isBaseApproved: Bool
        if let normalizedBase {
            if targetsLegacyMiniProgramHost(normalizedBase) {
                isBaseApproved = false
            } else if approvedBaseURLs[foreignMarket]?.contains(normalizedBase) == true &&
                        approvedBaseURLs[market]?.contains(normalizedBase) != true {
                isBaseApproved = false
                violations.append(.crossMarketBaseURLContamination(normalizedBase))
            } else if let url = URL(string: normalizedBase),
                      (try? APIConfiguration(baseURL: url)) != nil,
                      approvedBaseURLs[market]?.contains(normalizedBase) == true {
                isBaseApproved = true
            } else {
                isBaseApproved = false
                violations.append(.unapprovedMarketBaseURL(normalizedBase))
            }
        } else {
            isBaseApproved = false
        }

        var decisions: [RegionalEndpointAuditReport.RouteDecision] = []
        var blockedHighRisk: [String] = []
        var allowlistedHighRisk: [String] = []

        for highRiskRoute in RegionalHighRiskWriteRoute.allCases {
            let decision = evaluateEndpoint(
                urlOrPath: highRiskRoute.rawValue,
                market: market,
                baseURL: normalizedBase,
                approvedBaseURLs: approvedBaseURLs,
                allowlistedWriteRoutes: allowlistedWriteRoutes
            )
            decisions.append(decision)
            if decision.isAllowed {
                allowlistedHighRisk.append(highRiskRoute.rawValue)
                if let signedOffHighRiskRoutes,
                   signedOffHighRiskRoutes[market]?.contains(highRiskRoute) != true {
                    violations.append(.unapprovedHighRiskWriteEnabled(highRiskRoute.rawValue))
                }
            } else {
                blockedHighRisk.append(highRiskRoute.rawValue)
            }
        }

        for candidate in additionalCandidateURLs {
            let normalized = RegionalHighRiskWriteRoute.normalizePath(candidate)
            if RegionalHighRiskWriteRoute.match(normalized) != nil && !targetsLegacyMiniProgramHost(candidate) {
                continue
            }
            let decision = evaluateEndpoint(
                urlOrPath: candidate,
                market: market,
                baseURL: normalizedBase,
                approvedBaseURLs: approvedBaseURLs,
                allowlistedWriteRoutes: allowlistedWriteRoutes
            )
            decisions.append(decision)
        }

        return RegionalEndpointAuditReport(
            market: market,
            evaluatedBaseURL: normalizedBase,
            isBaseURLApproved: isBaseApproved,
            rejectedLegacyMiniProgramURLs: rejectedLegacyURLs.sorted(),
            blockedHighRiskRoutes: blockedHighRisk.sorted(),
            allowlistedHighRiskRoutes: allowlistedHighRisk.sorted(),
            routeDecisions: decisions,
            violations: violations
        )
    }
}
