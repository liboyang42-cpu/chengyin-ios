import Foundation

/// Audits incoming Universal Links and deep-link routes for security, privacy, and parity safety:
/// - Rejects non-HTTPS schemes and untrusted or raw-IP hosts (including legacy `47.103.124.64`),
/// - Detects incomplete social profile links (`memberID <= 0` -> `.incompleteProfileLinkFallback` with `"social.incompleteLink"`),
/// - Enforces session realm isolation (`cn-*` vs `us-*`) and authentication gating for protected member/club/merchant/order routes,
/// - Never auto-triggers mutations, payments, or location sharing from an inbound link.
public enum DeepLinkAndUniversalLinkSafetyAudit {

    // MARK: - Realm & Session Context

    public enum Realm: String, CaseIterable, Equatable, Sendable {
        case china = "cn"
        case unitedStates = "us"

        public static func parse(_ raw: String?) -> Realm? {
            guard let cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !cleaned.isEmpty else {
                return nil
            }
            if cleaned == "cn" || cleaned == "china" || cleaned.hasPrefix("cn-") {
                return .china
            }
            if cleaned == "us" || cleaned == "usa" || cleaned.hasPrefix("us-") {
                return .unitedStates
            }
            return nil
        }
    }

    public struct SessionContext: Equatable, Sendable {
        public let realmIdentifier: String
        public let realm: Realm?
        public let isAuthenticated: Bool
        public let accountID: Int

        public init(realmIdentifier: String, isAuthenticated: Bool, accountID: Int = 0) {
            self.realmIdentifier = realmIdentifier
            self.realm = Realm.parse(realmIdentifier)
            self.isAuthenticated = isAuthenticated && accountID > 0
            self.accountID = isAuthenticated && accountID > 0 ? accountID : 0
        }
    }

    // MARK: - Destinations, Fallbacks & Rejections

    public enum SafeDestination: Equatable, Sendable {
        case publicMemberProfile(memberID: Int)
        case publicTopicDetail(topicID: Int)
        case teamInvitation(inviteCode: String)
        case publicMerchantHome(merchantID: Int)
        case memberOrders
        case orderDetail(orderID: String)
        case clubWorkspace(clubID: Int)
        case merchantWorkbench(merchantID: Int)

        public var requiresAuthentication: Bool {
            switch self {
            case .publicMemberProfile, .publicTopicDetail, .teamInvitation, .publicMerchantHome:
                return false
            case .memberOrders, .orderDetail, .clubWorkspace, .merchantWorkbench:
                return true
            }
        }
    }

    public enum RejectionReason: Equatable, Sendable {
        case malformedURL
        case nonHTTPSScheme(String)
        case untrustedHost(String)
        case crossRealmRejected(linkRealm: Realm, sessionRealm: Realm)
        case unknownRealmIdentifier(String)
        case writeOrPaymentIntentRejected(keys: [String])
        case unsupportedRoute(String)
    }

    public enum AuditDecision: Equatable, Sendable {
        case allowReadOnly(SafeDestination)
        case incompleteProfileLinkFallback(fallbackLocalizationKey: String)
        case authenticationRequired(target: SafeDestination)
        case rejected(RejectionReason)
    }

    public struct AuditReport: Equatable, Sendable {
        public let decision: AuditDecision
        public let sanitizedQueryItems: [URLQueryItem]
        public let strippedWriteIntentKeys: [String]
        public let autoTriggersMutation: Bool
        public let autoTriggersPayment: Bool
        public let autoTriggersLocationSharing: Bool

        public init(
            decision: AuditDecision,
            sanitizedQueryItems: [URLQueryItem] = [],
            strippedWriteIntentKeys: [String] = []
        ) {
            self.decision = decision
            self.sanitizedQueryItems = sanitizedQueryItems
            self.strippedWriteIntentKeys = strippedWriteIntentKeys
            self.autoTriggersMutation = false
            self.autoTriggersPayment = false
            self.autoTriggersLocationSharing = false
        }
    }

    // MARK: - Constants & Guards

    public static let incompleteProfileFallbackKey = "social.incompleteLink"

    private static let legacyForbiddenIPv4Host: String = ["47", "103", "124", "64"].joined(separator: ".")

    private static let forbiddenActionQueryKeys: Set<String> = [
        "autosubmit",
        "autopay",
        "paynow",
        "payment",
        "confirmwrite",
        "mutate",
        "delete",
        "revoke",
        "withdraw",
        "transfer",
        "sharelocation",
        "enablepresence",
        "autoshare",
        "autojoin",
        "autocheckin"
    ]

    private static let forbiddenActionQueryValues: Set<String> = [
        "write",
        "mutate",
        "pay",
        "payment",
        "withdraw",
        "delete",
        "revoke",
        "sharelocation",
        "enablepresence",
        "autosubmit"
    ]

    public static func isUntrustedOrLiteralIPHost(_ host: String, verifiedHTTPSHosts: Set<String>) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        if normalized == legacyForbiddenIPv4Host
            || normalized == "localhost"
            || normalized == "127.0.0.1"
            || normalized.hasSuffix(".invalid")
            || normalized.hasSuffix(".local")
            || normalized.contains(":") {
            return true
        }
        // Reject any numeric IPv4 literal host.
        let octets = normalized.split(separator: ".", omittingEmptySubsequences: false)
        if octets.count == 4, octets.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return true
        }
        let trustedNormalized = Set(verifiedHTTPSHosts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return !trustedNormalized.contains(normalized)
    }

    public static func sanitizeQueryItems(_ items: [URLQueryItem]) -> (sanitized: [URLQueryItem], strippedKeys: [String]) {
        var kept: [URLQueryItem] = []
        var stripped: [String] = []
        for item in items {
            let keyLower = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let valueLower = (item.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if forbiddenActionQueryKeys.contains(keyLower)
                || ((keyLower == "action" || keyLower == "intent" || keyLower == "mode")
                    && forbiddenActionQueryValues.contains(valueLower)) {
                stripped.append(item.name)
            } else {
                kept.append(item)
            }
        }
        return (kept, stripped)
    }

    // MARK: - Main Audit Entry Point

    public static func audit(
        url: URL,
        session: SessionContext,
        verifiedHTTPSHosts: Set<String>,
        rejectWriteIntentQuery: Bool = true
    ) -> AuditReport {
        guard url.absoluteString.utf8.count <= 8192,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return AuditReport(decision: .rejected(.malformedURL))
        }

        let rawScheme = (components.scheme ?? "").lowercased()
        guard rawScheme == "https" else {
            return AuditReport(decision: .rejected(.nonHTTPSScheme(rawScheme)))
        }

        guard components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil else {
            return AuditReport(decision: .rejected(.malformedURL))
        }

        let rawHost = (components.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !rawHost.isEmpty else {
            return AuditReport(decision: .rejected(.malformedURL))
        }
        if isUntrustedOrLiteralIPHost(rawHost, verifiedHTTPSHosts: verifiedHTTPSHosts) {
            return AuditReport(decision: .rejected(.untrustedHost(rawHost)))
        }

        let pathSegments = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if pathSegments.contains("..") || pathSegments.contains(".") {
            return AuditReport(decision: .rejected(.malformedURL))
        }

        let rawQueryItems = components.queryItems ?? []
        let (sanitizedItems, strippedKeys) = sanitizeQueryItems(rawQueryItems)
        if rejectWriteIntentQuery && !strippedKeys.isEmpty {
            return AuditReport(
                decision: .rejected(.writeOrPaymentIntentRejected(keys: strippedKeys)),
                sanitizedQueryItems: sanitizedItems,
                strippedWriteIntentKeys: strippedKeys
            )
        }

        // Check realm isolation when link specifies `realm` or `market`.
        if let realmItem = sanitizedItems.first(where: { ["realm", "market"].contains($0.name.lowercased()) }),
           let rawLinkRealm = realmItem.value {
            guard let linkRealm = Realm.parse(rawLinkRealm) else {
                return AuditReport(
                    decision: .rejected(.unknownRealmIdentifier(rawLinkRealm)),
                    sanitizedQueryItems: sanitizedItems,
                    strippedWriteIntentKeys: strippedKeys
                )
            }
            guard let sessionRealm = session.realm else {
                return AuditReport(
                    decision: .rejected(.unknownRealmIdentifier(session.realmIdentifier)),
                    sanitizedQueryItems: sanitizedItems,
                    strippedWriteIntentKeys: strippedKeys
                )
            }
            if linkRealm != sessionRealm {
                return AuditReport(
                    decision: .rejected(.crossRealmRejected(linkRealm: linkRealm, sessionRealm: sessionRealm)),
                    sanitizedQueryItems: sanitizedItems,
                    strippedWriteIntentKeys: strippedKeys
                )
            }
        }

        let normalizedPath = "/" + pathSegments.joined(separator: "/")

        // 1. Social / Member Profile routes (`w2-12` `social.incompleteLink` when memberID <= 0 or missing)
        if isProfilePath(normalizedPath) {
            guard let rawMemberID = queryValue(in: sanitizedItems, names: ["memberId", "id", "userId"]),
                  let memberID = Int(rawMemberID),
                  String(memberID) == rawMemberID,
                  memberID > 0 else {
                return AuditReport(
                    decision: .incompleteProfileLinkFallback(fallbackLocalizationKey: incompleteProfileFallbackKey),
                    sanitizedQueryItems: sanitizedItems,
                    strippedWriteIntentKeys: strippedKeys
                )
            }
            return AuditReport(
                decision: .allowReadOnly(.publicMemberProfile(memberID: memberID)),
                sanitizedQueryItems: sanitizedItems,
                strippedWriteIntentKeys: strippedKeys
            )
        }

        // 2. Public Topic Detail route
        if normalizedPath == "/topic" || normalizedPath == "/pages/topic/index" {
            guard let rawTopicID = queryValue(in: sanitizedItems, names: ["topicId", "id"]),
                  let topicID = Int(rawTopicID),
                  topicID > 0 else {
                return AuditReport(
                    decision: .rejected(.unsupportedRoute(normalizedPath)),
                    sanitizedQueryItems: sanitizedItems,
                    strippedWriteIntentKeys: strippedKeys
                )
            }
            return AuditReport(
                decision: .allowReadOnly(.publicTopicDetail(topicID: topicID)),
                sanitizedQueryItems: sanitizedItems,
                strippedWriteIntentKeys: strippedKeys
            )
        }

        // 3. Team Invitation route (read-only preview; never auto-joins)
        if normalizedPath == "/team/join" || normalizedPath == "/pages/team/join/index" {
            guard let code = queryValue(in: sanitizedItems, names: ["code", "inviteCode"]),
                  code.range(of: "\\A[A-Za-z0-9_-]{4,64}\\z", options: .regularExpression) != nil else {
                return AuditReport(
                    decision: .rejected(.unsupportedRoute(normalizedPath)),
                    sanitizedQueryItems: sanitizedItems,
                    strippedWriteIntentKeys: strippedKeys
                )
            }
            return AuditReport(
                decision: .allowReadOnly(.teamInvitation(inviteCode: code)),
                sanitizedQueryItems: sanitizedItems,
                strippedWriteIntentKeys: strippedKeys
            )
        }

        // 4. Public Merchant Home route
        if normalizedPath == "/merchant/public-home" {
            guard let rawMerchantID = queryValue(in: sanitizedItems, names: ["merchantId", "id"]),
                  let merchantID = Int(rawMerchantID),
                  merchantID > 0 else {
                return AuditReport(
                    decision: .rejected(.unsupportedRoute(normalizedPath)),
                    sanitizedQueryItems: sanitizedItems,
                    strippedWriteIntentKeys: strippedKeys
                )
            }
            return AuditReport(
                decision: .allowReadOnly(.publicMerchantHome(merchantID: merchantID)),
                sanitizedQueryItems: sanitizedItems,
                strippedWriteIntentKeys: strippedKeys
            )
        }

        // 5. Protected Member / Order / Club / Merchant destinations (require authenticated session)
        let protectedDestination: SafeDestination?
        switch normalizedPath {
        case "/member/orders", "/pages/order/index":
            if let orderID = queryValue(in: sanitizedItems, names: ["orderId", "orderNo"]),
               !orderID.isEmpty,
               orderID.range(of: "\\A[A-Za-z0-9_-]{4,64}\\z", options: .regularExpression) != nil {
                protectedDestination = .orderDetail(orderID: orderID)
            } else {
                protectedDestination = .memberOrders
            }
        case "/club/workspace", "/pages/club/detail/index":
            if let rawClubID = queryValue(in: sanitizedItems, names: ["clubId", "id"]),
               let clubID = Int(rawClubID),
               clubID > 0 {
                protectedDestination = .clubWorkspace(clubID: clubID)
            } else {
                protectedDestination = nil
            }
        case "/merchant/workbench", "/pages/merchant/index":
            if let rawMerchantID = queryValue(in: sanitizedItems, names: ["merchantId", "id"]),
               let merchantID = Int(rawMerchantID),
               merchantID > 0 {
                protectedDestination = .merchantWorkbench(merchantID: merchantID)
            } else {
                protectedDestination = nil
            }
        default:
            protectedDestination = nil
        }

        if let destination = protectedDestination {
            guard session.isAuthenticated else {
                return AuditReport(
                    decision: .authenticationRequired(target: destination),
                    sanitizedQueryItems: sanitizedItems,
                    strippedWriteIntentKeys: strippedKeys
                )
            }
            return AuditReport(
                decision: .allowReadOnly(destination),
                sanitizedQueryItems: sanitizedItems,
                strippedWriteIntentKeys: strippedKeys
            )
        }

        return AuditReport(
            decision: .rejected(.unsupportedRoute(normalizedPath)),
            sanitizedQueryItems: sanitizedItems,
            strippedWriteIntentKeys: strippedKeys
        )
    }

    // MARK: - Private Helpers

    private static func isProfilePath(_ path: String) -> Bool {
        switch path {
        case "/profile",
             "/member/profile",
             "/pages/profile/profile",
             "/subpackageMember/pages/profile/index":
            return true
        default:
            return false
        }
    }

    private static func queryValue(in items: [URLQueryItem], names: [String]) -> String? {
        let loweredNames = Set(names.map { $0.lowercased() })
        guard let match = items.first(where: { loweredNames.contains($0.name.lowercased()) }),
              let value = match.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
