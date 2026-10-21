import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// W17 non-cash pledge. Inventory CAS, coupon grant and outbox live on hengyin
/// `cursor/w17-i-reward-pledge` (`ApiRewardPledgeController`, `ApiNonCashRewardController`).
/// This client stores a stable intent and fails closed when an approved policy value is absent.
public enum RewardPledgeFailure: Error, Equatable {
    case closed(String)
    case stale
    case terminal(String)
}

public struct RewardPledgePolicy: Equatable, Sendable {
    public enum ReadSource: String, Equatable, Sendable {
        case plannedController
        case couponHistory
    }
    public var ruleVersion: String?
    public var validity: String?
    public var quota: Int?
    public var reserveShare: Int?
    public var serviceCapacity: Int?
    public var merchantEvidence: String?
    public var minorEligible: Bool?
    public var antiAbuseReview: String?
    public var returnToPool: String?
    public var topUp: String?
    public var refusalPolicy: String?
    public var nonCashEnabled: Bool?
    public var readSource: ReadSource?
    public init() {}
    public static let unset = RewardPledgePolicy()
}

public enum RewardPledgeDependency {
    public static let backendBranch = "cursor/w17-i-reward-pledge"
    public static let controllers = ["ApiRewardPledgeController", "ApiNonCashRewardController"]
    public static let couponGrantOwner = "SmsCouponHistoryServiceImpl"
    /// Shared stock reservation is not in this client. W06 is the unique owner.
    public static let stockReservationOwner = "W06"
}

public enum RewardPledgeRoutes {
    public static let plannedNonCashList = "api/rewards/noncash"
    public static let plannedClaim = "api/rewards/noncash/claims"
    public static let plannedIntentQuery = "api/rewards/noncash/claims/recover"
    public static let offerPrefix = "api/rewards/noncash/versions/"
    public static let preview = "api/reward-pledge/fulfilment/preview"
    public static let redeem = "api/reward-pledge/fulfilment/redeem"
    public static let storeAwards = "api/reward-pledge/fulfilment/awards"
    public static let resolve = "api/reward-pledge/fulfilment/resolve"
    public static let expire = "api/reward-pledge/fulfilment/expire"
    public static let drafts = "api/reward-pledge/drafts"
    public static let cases = "api/rewards/noncash/cases"
    /// Names the one operation `CompositionHTTPTransport` may forward. Unknown URLs stay nil.
    public static func operation(_ request: URLRequest, baseURL: URL) -> String? {
        guard let url = request.url, url.fragment == nil, let method = request.httpMethod?.uppercased(),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil else { return nil }
        let query = parts.queryItems ?? []
        parts.query = nil
        guard let bare = parts.url else { return nil }
        func exact(_ path: String) -> Bool { bare == baseURL.appendingPathComponent(path) }
        func one(_ prefix: String) -> String? {
            let root = baseURL.appendingPathComponent(prefix).absoluteString
            guard bare.absoluteString.hasPrefix(root + "/") else { return nil }
            let rest = String(bare.absoluteString.dropFirst(root.count + 1))
            guard id(rest) else { return nil }
            return rest
        }
        func action(_ prefix: String, _ name: String) -> Bool {
            let root = baseURL.appendingPathComponent(prefix).absoluteString
            guard bare.absoluteString.hasPrefix(root + "/") else { return false }
            let parts = String(bare.absoluteString.dropFirst(root.count + 1)).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            return parts.count == 2 && id(parts[0]) && parts[1] == name
        }
        if method == "GET", query.isEmpty, exact(plannedNonCashList) { return "read" }
        if method == "POST", query.isEmpty, exact(plannedClaim) { return "claim" }
        if method == "POST", query.isEmpty, exact(plannedIntentQuery) { return "recover" }
        if method == "POST", query.isEmpty, exact(cases) { return "case" }
        if method == "GET", query.isEmpty, one(cases) != nil { return "case" }
        if method == "GET", query.count == 2,
           query.contains(URLQueryItem(name: "branch", value: "THEME")),
           let subject = query.first(where: { $0.name == "subjectId" })?.value, id(subject),
           one(offerPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) != nil { return "offer" }
        if method == "GET", query.isEmpty, let award = one(plannedNonCashList),
           !["versions", "claims", "cases"].contains(award) { return "detail" }
        if method == "GET", query.isEmpty, exact(storeAwards) { return "store" }
        if method == "POST", query.isEmpty, exact(preview) { return "preview" }
        if method == "POST", query.isEmpty, exact(redeem) { return "redeem" }
        if method == "POST", query.isEmpty, exact(resolve) { return "resolve" }
        if method == "POST", query.isEmpty, exact(expire) { return "expire" }
        if method == "POST", query.isEmpty, exact(drafts) { return "draft" }
        if method == "POST", query.isEmpty, action("api/reward-pledge", "submit") { return "submit" }
        if method == "POST", query.isEmpty, action("api/reward-pledge", "confirm") { return "confirm" }
        if method == "POST", query.isEmpty, action("api/reward-pledge", "freeze") { return "freeze" }
        if method == "GET", query.isEmpty, action("api/reward-pledge", "stats") { return "stats" }
        if method == "GET", query.isEmpty, let pledge = one("api/reward-pledge"),
           !["drafts", "fulfilment", "versions", "awards", "compensations"].contains(pledge) { return "readPledge" }
        if method == "POST", query.isEmpty, action("api/reward-pledge/versions", "withdraw") { return "withdraw" }
        if method == "POST", query.isEmpty, action("api/reward-pledge/versions", "hold") { return "hold" }
        if method == "POST", query.isEmpty, action("api/reward-pledge/awards", "return-to-pool") { return "return" }
        return nil
    }
    static func id(_ value: String) -> Bool {
        value.count <= 64 && value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }
    public static let couponQRToken = "api/coupon/qr-token"
    public static let couponStatus = "api/coupon/status"
    public static let couponVerification = "api/coupon/verification"
    public static let couponRecvList = "api/coupon/myrecvlist"
    public static let staffRedeem = [couponQRToken, couponStatus, couponVerification, couponRecvList]

    /// One granted-coupon read. Unset approval returns nil. The two sources are never combined.
    public static func listPath(_ source: RewardPledgePolicy.ReadSource?) -> String? {
        switch source {
        case .plannedController: return plannedNonCashList
        case .couponHistory: return couponRecvList
        case nil: return nil
        }
    }

    public static func detailPath(_ source: RewardPledgePolicy.ReadSource?, awardID: String) -> String? {
        switch source {
        case .plannedController: return plannedNonCashList + "/" + awardID
        case .couponHistory: return couponRecvList
        case nil: return nil
        }
    }
}

public enum RewardPledgeIdentity {
    public static let separator = "\u{1e}"
    public static func businessKey(ruleVersion: String, eligibility: String, beneficiary: String, rewardScope: String) -> String {
        [ruleVersion, eligibility, beneficiary, rewardScope].joined(separator: separator)
    }
    public static func requestID(for businessKey: String) -> String {
        SHA256.hash(data: Data(businessKey.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Persisted recovery record. Owner and the original intent only — no chat, trace or token.
public struct RewardPledgeUnknown: Codable, Equatable, Sendable {
    public let ownerID: String
    public let storeID: String
    public let businessKey: String
    public let requestID: String
    public let kind: String
    public init(ownerID: String, storeID: String, businessKey: String, requestID: String, kind: String) {
        self.ownerID = ownerID; self.storeID = storeID; self.businessKey = businessKey
        self.requestID = requestID; self.kind = kind
    }
    public var intent: RewardPledgeIntent {
        RewardPledgeIntent(ownerID: ownerID, storeID: storeID, businessKey: businessKey, requestID: requestID, kind: kind)
    }
}

public struct RewardPledgeTerms: Equatable, Sendable {
    public let ruleVersion: String
    public let limitText: String
    public let validity: String
    public let eligibilityFact: String
    public let rewardScope: String
    public let beneficiaryID: String
    public let storeID: String
    public let quota: Int
    public var businessKey: String {
        RewardPledgeIdentity.businessKey(ruleVersion: ruleVersion, eligibility: eligibilityFact, beneficiary: beneficiaryID, rewardScope: rewardScope)
    }
}

public struct RewardPledgeIntent: Equatable, Sendable {
    public let ownerID: String
    public let storeID: String
    public let businessKey: String
    public let requestID: String
    public let kind: String
}

public struct RewardPledgeGrant: Equatable, Sendable {
    public let awardID: String
    public let termsVersion: String
    public let termsText: String
    public let state: String
}

public struct RewardPledgeVersion: Equatable, Sendable {
    public let pledgeID: String
    public let version: Int
    public let status: String
    public let storeID: String
    public let quantityText: String
    public let termsText: String
}

public struct RewardPledgeServiceCase: Equatable, Sendable {
    public let caseID: String
    public let awardID: String
    public let reason: String
    public let readable: String
}

public struct RewardPledgeScope: Equatable, Sendable {
    public let accountID: String
    public let storeID: String
    public let generation: UInt64
}

public struct RewardPledgeCounts: Equatable, Sendable {
    public let grantedUnredeemed: Int
    public let redeemed: Int
    public let expired: Int
    public let withdrawn: Int
    public let refused: Int
    public let version: Int
    public let asOf: String
}

public final class RewardPledgeFileJournal {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [RewardPledgeUnknown] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do { return try JSONDecoder().decode([RewardPledgeUnknown].self, from: Data(contentsOf: url)) }
        catch { throw RewardPledgeFailure.closed("journal") }
    }
    public func save(_ rows: [RewardPledgeUnknown]) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(rows).write(to: url, options: .atomic)
        } catch { throw RewardPledgeFailure.closed("journal") }
    }
}

public enum RewardPledgeRequests {
    public static func claim(requestID: String, versionID: String, subjectID: String, baseURL: URL, token: String) throws -> URLRequest {
        guard segment(requestID), segment(versionID), segment(subjectID) else { throw RewardPledgeFailure.closed("requestID") }
        return try json(RewardPledgeRoutes.plannedClaim, [
            "requestId": requestID, "versionId": versionID, "branch": "THEME", "subjectId": subjectID
        ], baseURL, token)
    }
    /// Recovery posts the original request id. A different id is not sent.
    public static func query(original: RewardPledgeUnknown, proposedRequestID: String, baseURL: URL, token: String) throws -> URLRequest {
        guard proposedRequestID == original.requestID,
              original.requestID == RewardPledgeIdentity.requestID(for: original.businessKey) else {
            throw RewardPledgeFailure.closed("requestID")
        }
        return try json(RewardPledgeRoutes.plannedIntentQuery, ["requestId": original.requestID], baseURL, token)
    }
    public static func offer(versionID: String, subjectID: String, baseURL: URL, token: String) throws -> URLRequest {
        guard segment(versionID), segment(subjectID), !versionID.contains("/"),
              AuthRequestBuilder.isValidToken(token),
              var parts = URLComponents(url: baseURL.appendingPathComponent(RewardPledgeRoutes.offerPrefix + versionID), resolvingAgainstBaseURL: false)
        else { throw RewardPledgeFailure.closed("versionId") }
        parts.queryItems = [URLQueryItem(name: "branch", value: "THEME"), URLQueryItem(name: "subjectId", value: subjectID)]
        guard let url = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    public static func preview(awardID: String, baseURL: URL, token: String) throws -> URLRequest {
        guard segment(awardID) else { throw RewardPledgeFailure.closed("award") }
        return try json(RewardPledgeRoutes.preview, ["awardId": awardID], baseURL, token)
    }
    /// Redeem body is awardId plus explicit confirm. The server keeps the award's original request id.
    public static func redeem(awardID: String, baseURL: URL, token: String) throws -> URLRequest {
        guard segment(awardID) else { throw RewardPledgeFailure.closed("award") }
        return try json(RewardPledgeRoutes.redeem, ["awardId": awardID, "confirm": "true"], baseURL, token)
    }
    public static func detail(awardID: String, baseURL: URL, token: String) throws -> URLRequest {
        guard segment(awardID), !awardID.contains("/"), AuthRequestBuilder.isValidToken(token) else { throw RewardPledgeFailure.closed("award") }
        var request = URLRequest(url: baseURL.appendingPathComponent(RewardPledgeRoutes.plannedNonCashList + "/" + awardID))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    /// `listMine` returns the owner's awards in one response. There is no cursor contract.
    public static func list(baseURL: URL, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw RewardPledgeFailure.closed("permission") }
        var request = URLRequest(url: baseURL.appendingPathComponent(RewardPledgeRoutes.plannedNonCashList))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    /// This store's awards. The server binds the store from the staff session.
    public static func storeAwards(baseURL: URL, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw RewardPledgeFailure.closed("permission") }
        var request = URLRequest(url: baseURL.appendingPathComponent(RewardPledgeRoutes.storeAwards))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    /// Existing coupon dynamic code. The server resolves it to this store's award.
    public static func resolve(code: String, baseURL: URL, token: String) throws -> URLRequest {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512, !trimmed.contains("\n") else { throw RewardPledgeFailure.closed("award") }
        return try json(RewardPledgeRoutes.resolve, ["code": trimmed], baseURL, token)
    }
    /// Supply copied from one published coupon. `requestID` is the pledge id. The server assigns the store.
    public struct Supply: Equatable, Sendable {
        public let requestID: String
        public let couponID: Int
        public let supplyRef: String
        public let terms: String
        public let quantity: Int
        public let windowStart: Int64
        public let windowEnd: Int64
        public init(coupon: CouponDefinition, supplyRef: String, terms: String, quantity: Int, requestID: String) throws {
            let ref = supplyRef.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = terms.trimmingCharacters(in: .whitespacesAndNewlines)
            guard RewardPledgeRoutes.id(requestID), coupon.id.value > 0, quantity > 0, !ref.isEmpty, ref.count <= 128,
                  !text.isEmpty, text.count <= 128, !ref.contains("\n"), !text.contains("\n"),
                  let startRaw = coupon.startTime, let endRaw = coupon.endTime,
                  let start = CouponValidityTime.parse(startRaw), let end = CouponValidityTime.parse(endRaw), end > start else {
                throw RewardPledgeFailure.closed("validity")
            }
            let startMs = Int64((start.timeIntervalSince1970 * 1000).rounded())
            let endMs = Int64((end.timeIntervalSince1970 * 1000).rounded())
            guard startMs > 0, endMs > startMs else { throw RewardPledgeFailure.closed("validity") }
            self.requestID = requestID
            couponID = coupon.id.value
            self.supplyRef = ref
            self.terms = text
            self.quantity = quantity
            windowStart = startMs
            windowEnd = endMs
        }
    }
    public static func draft(_ supply: Supply, baseURL: URL, token: String) throws -> URLRequest {
        // ponytail: service window copies the coupon redeem window until a pledge must outlive the coupon
        return try jsonAny(RewardPledgeRoutes.drafts, [
            "requestId": supply.requestID,
            "couponId": supply.couponID, "supplyRef": supply.supplyRef, "terms": supply.terms, "quantity": supply.quantity,
            "serviceStart": NSNumber(value: supply.windowStart), "serviceEnd": NSNumber(value: supply.windowEnd),
            "redeemStart": NSNumber(value: supply.windowStart), "redeemEnd": NSNumber(value: supply.windowEnd),
            "rewardKind": "NON_CASH"
        ], baseURL, token)
    }
    public static func submit(pledgeID: String, baseURL: URL, token: String) throws -> URLRequest {
        return try post("api/reward-pledge/" + (try pathID(pledgeID)) + "/submit", baseURL, token)
    }
    public static func confirm(pledgeID: String, baseURL: URL, token: String) throws -> URLRequest {
        return try post("api/reward-pledge/" + (try pathID(pledgeID)) + "/confirm", baseURL, token)
    }
    public static func readPledge(pledgeID: String, baseURL: URL, token: String) throws -> URLRequest {
        return try get("api/reward-pledge/" + (try pathID(pledgeID)), baseURL, token)
    }
    public static func freeze(pledgeID: String, ruleVersion: String, baseURL: URL, token: String) throws -> URLRequest {
        let rule = ruleVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty, rule.count <= 128, !rule.contains("\n") else { throw RewardPledgeFailure.closed("ruleVersion") }
        return try json("api/reward-pledge/" + (try pathID(pledgeID)) + "/freeze", ["ruleVersion": rule], baseURL, token)
    }
    public static func hold(versionID: String, baseURL: URL, token: String) throws -> URLRequest {
        return try post("api/reward-pledge/versions/" + (try pathID(versionID)) + "/hold", baseURL, token)
    }
    public static func withdraw(versionID: String, baseURL: URL, token: String) throws -> URLRequest {
        return try post("api/reward-pledge/versions/" + (try pathID(versionID)) + "/withdraw", baseURL, token)
    }
    public static func expire(awardID: String, baseURL: URL, token: String) throws -> URLRequest {
        return try json(RewardPledgeRoutes.expire, ["awardId": try pathID(awardID)], baseURL, token)
    }
    public static func returnToPool(awardID: String, baseURL: URL, token: String) throws -> URLRequest {
        return try post("api/reward-pledge/awards/" + (try pathID(awardID)) + "/return-to-pool", baseURL, token)
    }
    public static func readCase(caseID: String, baseURL: URL, token: String) throws -> URLRequest {
        return try get(RewardPledgeRoutes.cases + "/" + (try pathID(caseID)), baseURL, token)
    }
    public static func openCase(awardID: String, versionID: String, reason: String, baseURL: URL, token: String) throws -> URLRequest {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != "CASH_REFUND" else { throw RewardPledgeFailure.closed("CASH_CLOSED") }
        guard !text.isEmpty, text.count <= 128, !text.contains("\n") else { throw RewardPledgeFailure.closed("validity") }
        return try json(RewardPledgeRoutes.cases, ["awardId": try pathID(awardID), "versionId": try pathID(versionID), "reason": text], baseURL, token)
    }
    public static func stats(pledgeID: String, baseURL: URL, token: String) throws -> URLRequest {
        return try get("api/reward-pledge/" + (try pathID(pledgeID)) + "/stats", baseURL, token)
    }
    /// Existing coupon routes, in order. City-node redeem is not one of them.
    public static func staff(historyID: Int, verificationCode: String, baseURL: URL, token: String) throws -> [URLRequest] {
        guard historyID > 0, !verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RewardPledgeFailure.closed("award")
        }
        guard CityNodeRedemptionCode.acceptsPledgeRedeem(RewardPledgeRoutes.couponVerification) == false else {
            throw RewardPledgeFailure.closed("cityNode")
        }
        let issued = try OrderLifecycleRequestContract.issueCoupon(historyID: historyID, baseURL: baseURL, token: token)
        let status = try form(RewardPledgeRoutes.couponStatus, ["couponHistoryId": String(historyID)], baseURL, token, "pledge-status")
        let verify = try OrderLifecycleRequestContract.verifyCoupon(code: verificationCode, baseURL: baseURL, token: token)
        let list = try form(RewardPledgeRoutes.couponRecvList, [:], baseURL, token, "pledge-recv")
        let built = [issued, status, verify, list]
        let suffixes = built.map { request -> String? in
            guard let path = request.url?.path else { return nil }
            return RewardPledgeRoutes.staffRedeem.first { path.hasSuffix($0) }
        }
        guard suffixes == RewardPledgeRoutes.staffRedeem.map({ Optional($0) }) else { throw RewardPledgeFailure.closed("route") }
        return built
    }
    private static func segment(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 128 && !value.contains("\n") && !value.contains("\r")
    }
    private static func pathID(_ value: String) throws -> String {
        guard RewardPledgeRoutes.id(value) else { throw RewardPledgeFailure.closed("route") }
        return value
    }
    private static func json(_ path: String, _ fields: [String: String], _ baseURL: URL, _ token: String) throws -> URLRequest {
        return try jsonAny(path, fields, baseURL, token)
    }
    private static func jsonAny(_ path: String, _ fields: [String: Any], _ baseURL: URL, _ token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token), JSONSerialization.isValidJSONObject(fields),
              let body = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { throw APIError.invalidRequest }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    private static func get(_ path: String, _ baseURL: URL, _ token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw RewardPledgeFailure.closed("permission") }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    private static func post(_ path: String, _ baseURL: URL, _ token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw RewardPledgeFailure.closed("permission") }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    private static func form(_ path: String, _ fields: [String: String], _ baseURL: URL, _ token: String, _ boundary: String) throws -> URLRequest {
        guard RewardPledgeRoutes.staffRedeem.contains(path) || path.hasPrefix("api/rewards/pledge/") else {
            throw RewardPledgeFailure.closed("route")
        }
        return try AuthRequestBuilder.makeFormRequest(url: baseURL.appendingPathComponent(path), fields: fields, token: token, boundary: boundary)
    }
}

/// Coupon history row projected into the granted-unredeemed read. Not a second inventory.
public enum RewardPledgeCouponProjection {
    public static func grant(historyID: String, termsVersion: String, termsText: String, state: String) -> RewardPledgeGrant? {
        guard (state == "AWARDED" || state == "GRANTED_UNREDEEMED"), !historyID.isEmpty, !termsVersion.isEmpty, !termsText.isEmpty else { return nil }
        return RewardPledgeGrant(awardID: historyID, termsVersion: termsVersion, termsText: termsText, state: "GRANTED_UNREDEEMED")
    }
}

public struct RewardPledgeMachine: Equatable {
    public private(set) var scope: RewardPledgeScope
    public private(set) var policy: RewardPledgePolicy
    public private(set) var unknowns: [RewardPledgeUnknown]
    public private(set) var grant: RewardPledgeGrant?
    public private(set) var draft: RewardPledgeVersion?
    public private(set) var frozen: RewardPledgeVersion?
    public private(set) var serviceCase: RewardPledgeServiceCase?
    public private(set) var confirmedKey: String?
    public private(set) var previewedStoreID: String?
    public private(set) var staffRoutes: [String]
    public private(set) var listRefreshed: Bool
    public private(set) var detailRefreshed: Bool
    public private(set) var consumedCodes: Set<String>

    public init(accountID: String, storeID: String, policy: RewardPledgePolicy = .unset, unknowns: [RewardPledgeUnknown] = []) {
        scope = RewardPledgeScope(accountID: accountID, storeID: storeID, generation: 1)
        self.policy = policy
        self.unknowns = unknowns.filter { $0.ownerID == accountID && $0.storeID == storeID }
        staffRoutes = []
        listRefreshed = false
        detailRefreshed = false
        consumedCodes = []
    }

    public mutating func applyPolicy(_ policy: RewardPledgePolicy) {
        self.policy = policy
        scope = RewardPledgeScope(accountID: scope.accountID, storeID: scope.storeID, generation: scope.generation &+ 1)
    }

    public static func restored(accountID: String, storeID: String, policy: RewardPledgePolicy, journal: [RewardPledgeUnknown]) -> RewardPledgeMachine {
        RewardPledgeMachine(accountID: accountID, storeID: storeID, policy: policy, unknowns: journal)
    }

    public mutating func replaceAccount(_ accountID: String, store storeID: String, journal: [RewardPledgeUnknown]) {
        scope = RewardPledgeScope(accountID: accountID, storeID: storeID, generation: scope.generation &+ 1)
        unknowns = journal.filter { $0.ownerID == accountID && $0.storeID == storeID }
        clearPresentation()
    }

    public mutating func bindStore(_ storeID: String, seen: RewardPledgeScope) -> Result<RewardPledgeScope, RewardPledgeFailure> {
        guard seen == scope, !storeID.isEmpty, !scope.accountID.isEmpty else { return .failure(.closed("store")) }
        guard scope.storeID.isEmpty || scope.storeID == storeID else { return .failure(.stale) }
        scope = RewardPledgeScope(accountID: scope.accountID, storeID: storeID, generation: scope.generation &+ 1)
        return .success(scope)
    }

    public mutating func beginQuery() -> RewardPledgeScope {
        scope = RewardPledgeScope(accountID: scope.accountID, storeID: scope.storeID, generation: scope.generation &+ 1)
        return scope
    }

    public func readTerms(serverRule: String?, serverLimit: String?, serverValidity: String?, eligibility: String?,
                          rewardScope: String?, beneficiary: String?, storeID: String?, serverQuota: Int?,
                          minorPrize: Bool, reviewRequired: Bool, clientComplete: Bool,
                          capabilities: SponsoredRewardCapabilities, seen: RewardPledgeScope) -> Result<RewardPledgeTerms, RewardPledgeFailure> {
        guard seen == scope else { return .failure(.stale) }
        guard !clientComplete else { return .failure(.closed("clientComplete")) }
        guard capabilities.cash == false, capabilities.random == false, capabilities.guaranteed == false else { return .failure(.closed("switches")) }
        guard capabilities.nonCash, policy.nonCashEnabled == true else { return .failure(.closed("nonCashEnabled")) }
        guard let rule = serverRule, let approvedRule = policy.ruleVersion, rule == approvedRule, !rule.isEmpty else { return .failure(.closed("ruleVersion")) }
        guard let validity = serverValidity, let approvedValidity = policy.validity, validity == approvedValidity, !validity.isEmpty else { return .failure(.closed("validity")) }
        guard let quota = serverQuota, let approvedQuota = policy.quota, quota == approvedQuota else { return .failure(.closed("quota")) }
        guard let limit = serverLimit, !limit.isEmpty else { return .failure(.closed("quota")) }
        guard let fact = eligibility, !fact.isEmpty, fact != "true" else { return .failure(.closed("eligibility")) }
        guard let rewardScope, !rewardScope.isEmpty, let beneficiary, beneficiary == scope.accountID, !beneficiary.isEmpty else { return .failure(.closed("owner")) }
        guard let storeID, !storeID.isEmpty, storeID == scope.storeID else { return .failure(.closed("store")) }
        if minorPrize, policy.minorEligible != true { return .failure(.closed("minorEligible")) }
        if reviewRequired, policy.antiAbuseReview == nil { return .failure(.closed("antiAbuseReview")) }
        return .success(RewardPledgeTerms(ruleVersion: rule, limitText: limit, validity: validity, eligibilityFact: fact,
                                          rewardScope: rewardScope, beneficiaryID: beneficiary, storeID: storeID, quota: quota))
    }

    public mutating func confirmClaim(_ terms: RewardPledgeTerms, seen: RewardPledgeScope) -> Result<RewardPledgeIntent, RewardPledgeFailure> {
        guard seen == scope, terms.beneficiaryID == scope.accountID, terms.storeID == scope.storeID else { return .failure(.stale) }
        let key = terms.businessKey
        let requestID = RewardPledgeIdentity.requestID(for: key)
        if let existing = unknowns.first(where: { $0.ownerID == scope.accountID && $0.businessKey == key }) {
            guard existing.requestID == requestID else { return .failure(.closed("requestID")) }
            confirmedKey = key
            return .success(existing.intent)
        }
        confirmedKey = key
        return .success(RewardPledgeIntent(ownerID: scope.accountID, storeID: scope.storeID, businessKey: key, requestID: requestID, kind: "claim"))
    }

    public mutating func recordUnknown(_ intent: RewardPledgeIntent, seen: RewardPledgeScope) -> Result<RewardPledgeUnknown, RewardPledgeFailure> {
        guard seen == scope, intent.ownerID == scope.accountID, intent.storeID == scope.storeID else { return .failure(.stale) }
        guard intent.requestID == RewardPledgeIdentity.requestID(for: intent.businessKey) else { return .failure(.closed("requestID")) }
        let row = RewardPledgeUnknown(ownerID: intent.ownerID, storeID: intent.storeID, businessKey: intent.businessKey, requestID: intent.requestID, kind: intent.kind)
        if let existing = unknowns.first(where: { $0.ownerID == row.ownerID && $0.businessKey == row.businessKey }) {
            guard existing.requestID == row.requestID else { return .failure(.closed("requestID")) }
            return .success(existing)
        }
        unknowns.append(row)
        return .success(row)
    }

    public func recoveryIntent(_ row: RewardPledgeUnknown, proposedRequestID: String, seen: RewardPledgeScope) -> Result<RewardPledgeIntent, RewardPledgeFailure> {
        guard seen == scope, row.ownerID == scope.accountID, row.storeID == scope.storeID else { return .failure(.stale) }
        guard proposedRequestID == row.requestID else { return .failure(.closed("requestID")) }
        guard let stored = unknowns.first(where: { $0.ownerID == row.ownerID && $0.businessKey == row.businessKey && $0.requestID == row.requestID }) else {
            return .failure(.closed("intent"))
        }
        guard stored.requestID == RewardPledgeIdentity.requestID(for: stored.businessKey) else { return .failure(.closed("requestID")) }
        return .success(stored.intent)
    }

    public mutating func acceptGrant(awardID: String, termsVersion: String, termsText: String, requestID: String, businessKey: String, seen: RewardPledgeScope) -> Result<RewardPledgeGrant, RewardPledgeFailure> {
        guard seen == scope, !awardID.isEmpty, !termsVersion.isEmpty, !termsText.isEmpty else { return .failure(.stale) }
        guard requestID == RewardPledgeIdentity.requestID(for: businessKey) else { return .failure(.closed("requestID")) }
        let known = unknowns.contains { $0.requestID == requestID && $0.ownerID == scope.accountID }
        guard confirmedKey == businessKey || known else { return .failure(.closed("confirm")) }
        let value = RewardPledgeGrant(awardID: awardID, termsVersion: termsVersion, termsText: termsText, state: "GRANTED_UNREDEEMED")
        grant = value
        unknowns.removeAll { $0.requestID == requestID && $0.ownerID == scope.accountID }
        listRefreshed = false
        detailRefreshed = false
        return .success(value)
    }

    public func showsFrozen(_ reward: NonCashReward) -> Bool {
        guard let grant, grant.state == "GRANTED_UNREDEEMED" else { return false }
        return reward.matchesPledgeRefresh(awardID: grant.awardID)
    }

    public mutating func markRefreshed(seen: RewardPledgeScope) -> Result<String, RewardPledgeFailure> {
        guard seen == scope, grant?.state == "GRANTED_UNREDEEMED" else { return .failure(.stale) }
        guard let path = RewardPledgeRoutes.listPath(policy.readSource) else { return .failure(.closed("readSource")) }
        listRefreshed = true
        detailRefreshed = true
        return .success(path)
    }

    public func refreshSource() -> Result<String, RewardPledgeFailure> {
        guard let path = RewardPledgeRoutes.listPath(policy.readSource) else { return .failure(.closed("readSource")) }
        return .success(path)
    }

    public mutating func saveDraft(pledgeID: String, quantityText: String, termsText: String, serverReserve: Int?, seen: RewardPledgeScope) -> Result<RewardPledgeVersion, RewardPledgeFailure> {
        guard seen == scope, !scope.storeID.isEmpty else { return .failure(.stale) }
        guard let evidence = policy.merchantEvidence, !evidence.isEmpty else { return .failure(.closed("merchantEvidence")) }
        guard let approvedReserve = policy.reserveShare, let serverReserve, serverReserve == approvedReserve else { return .failure(.closed("reserveShare")) }
        guard let approved = policy.quota, let typed = Int(quantityText), typed == approved else { return .failure(.closed("quota")) }
        guard !termsText.isEmpty, !pledgeID.isEmpty else { return .failure(.closed("validity")) }
        guard frozen?.status != "WITHDRAWN" else { return .failure(.terminal("WITHDRAWN")) }
        let version = (draft?.version ?? frozen?.version ?? 0) + 1
        let row = RewardPledgeVersion(pledgeID: pledgeID, version: version, status: "DRAFT", storeID: scope.storeID, quantityText: quantityText, termsText: termsText)
        draft = row
        return .success(row)
    }

    public mutating func submitDraft(seen: RewardPledgeScope) -> Result<RewardPledgeVersion, RewardPledgeFailure> {
        guard seen == scope, var row = draft, row.status == "DRAFT", row.storeID == scope.storeID else { return .failure(.stale) }
        guard policy.ruleVersion != nil else { return .failure(.closed("ruleVersion")) }
        guard policy.validity != nil else { return .failure(.closed("validity")) }
        row = RewardPledgeVersion(pledgeID: row.pledgeID, version: row.version, status: "SUBMITTED", storeID: row.storeID, quantityText: row.quantityText, termsText: row.termsText)
        draft = row
        return .success(row)
    }

    public mutating func freeze(serverVersion: Int, seen: RewardPledgeScope) -> Result<RewardPledgeVersion, RewardPledgeFailure> {
        guard seen == scope, let row = draft, row.status == "SUBMITTED", row.version == serverVersion else { return .failure(.stale) }
        let frozenRow = RewardPledgeVersion(pledgeID: row.pledgeID, version: row.version, status: "FROZEN", storeID: row.storeID, quantityText: row.quantityText, termsText: row.termsText)
        frozen = frozenRow
        draft = nil
        return .success(frozenRow)
    }

    public mutating func withdraw(seen: RewardPledgeScope) -> Result<RewardPledgeServiceCase, RewardPledgeFailure> {
        guard seen == scope, let row = frozen, row.status == "FROZEN" else { return .failure(.stale) }
        frozen = RewardPledgeVersion(pledgeID: row.pledgeID, version: row.version, status: "WITHDRAWN", storeID: row.storeID, quantityText: row.quantityText, termsText: row.termsText)
        let item = RewardPledgeServiceCase(caseID: row.pledgeID + ":WITHDRAWN", awardID: grant?.awardID ?? "", reason: "WITHDRAWN", readable: "Pledge withdrawn. Granted coupons stay issued.")
        serviceCase = item
        return .success(item)
    }

    public mutating func preview(permissionStore: String, seen: RewardPledgeScope) -> Result<RewardPledgeGrant, RewardPledgeFailure> {
        guard seen == scope, permissionStore == scope.storeID, let grant, grant.state == "GRANTED_UNREDEEMED" else { return .failure(.stale) }
        previewedStoreID = permissionStore
        return .success(grant)
    }

    public mutating func beginRedeem(explicit: Bool, historyID: String, serverCapacity: Int?, seen: RewardPledgeScope) -> Result<RewardPledgeIntent, RewardPledgeFailure> {
        guard seen == scope, explicit else { return .failure(.closed("confirm")) }
        guard previewedStoreID == scope.storeID else { return .failure(.stale) }
        guard let approved = policy.serviceCapacity, let serverCapacity, serverCapacity == approved else { return .failure(.closed("serviceCapacity")) }
        guard let current = grant, current.state == "GRANTED_UNREDEEMED", current.awardID == historyID else {
            return .failure(.terminal(grant?.state ?? "ABSENT"))
        }
        guard CityNodeRedemptionCode.acceptsPledgeRedeem(RewardPledgeRoutes.couponVerification) == false else { return .failure(.closed("cityNode")) }
        let key = RewardPledgeIdentity.businessKey(ruleVersion: current.termsVersion, eligibility: "redeem", beneficiary: scope.accountID, rewardScope: historyID)
        let requestID = RewardPledgeIdentity.requestID(for: key)
        if let existing = unknowns.first(where: { $0.businessKey == key }) {
            guard existing.requestID == requestID else { return .failure(.closed("requestID")) }
            return .failure(.closed("intent"))
        }
        staffRoutes = RewardPledgeRoutes.staffRedeem
        return .success(RewardPledgeIntent(ownerID: scope.accountID, storeID: scope.storeID, businessKey: key, requestID: requestID, kind: "redeem"))
    }

    public mutating func noteVerification(_ code: String, seen: RewardPledgeScope) -> Result<Void, RewardPledgeFailure> {
        guard seen == scope else { return .failure(.stale) }
        guard !consumedCodes.contains(code) else { return .failure(.closed("replay")) }
        consumedCodes.insert(code)
        return .success(())
    }

    public mutating func applyRedeem(requestID: String, businessKey: String, serverRedeemed: Bool, seen: RewardPledgeScope) -> Result<RewardPledgeGrant, RewardPledgeFailure> {
        guard seen == scope, var grant, grant.state == "GRANTED_UNREDEEMED" else { return .failure(.terminal(self.grant?.state ?? "ABSENT")) }
        guard requestID == RewardPledgeIdentity.requestID(for: businessKey) else { return .failure(.closed("requestID")) }
        guard serverRedeemed else {
            let intent = RewardPledgeIntent(ownerID: scope.accountID, storeID: scope.storeID, businessKey: businessKey, requestID: requestID, kind: "redeem")
            _ = recordUnknown(intent, seen: seen)
            return .failure(.closed("unknown"))
        }
        grant = RewardPledgeGrant(awardID: grant.awardID, termsVersion: grant.termsVersion, termsText: grant.termsText, state: "REDEEMED")
        self.grant = grant
        unknowns.removeAll { $0.requestID == requestID && $0.ownerID == scope.accountID }
        return .success(grant)
    }

    public mutating func expire(awardID: String, seen: RewardPledgeScope) -> Result<RewardPledgeServiceCase, RewardPledgeFailure> {
        guard seen == scope, var grant, grant.awardID == awardID, grant.state == "GRANTED_UNREDEEMED" else { return .failure(.stale) }
        grant = RewardPledgeGrant(awardID: grant.awardID, termsVersion: grant.termsVersion, termsText: grant.termsText, state: "EXPIRED")
        self.grant = grant
        let item = RewardPledgeServiceCase(caseID: awardID + ":EXPIRED", awardID: awardID, reason: "EXPIRED",
                                           readable: policy.returnToPool == nil ? "Expired. Return to pool is not approved." : "Expired. Stock return stays with W06.")
        serviceCase = item
        return .success(item)
    }

    public mutating func refuse(awardID: String, seen: RewardPledgeScope) -> Result<RewardPledgeServiceCase, RewardPledgeFailure> {
        guard seen == scope, policy.refusalPolicy != nil else { return .failure(.closed("refusalPolicy")) }
        guard var grant, grant.awardID == awardID, grant.state == "GRANTED_UNREDEEMED" else { return .failure(.stale) }
        grant = RewardPledgeGrant(awardID: grant.awardID, termsVersion: grant.termsVersion, termsText: grant.termsText, state: "REFUSED")
        self.grant = grant
        let item = RewardPledgeServiceCase(caseID: awardID + ":REFUSED", awardID: awardID, reason: "REFUSED", readable: "Redemption refused. The award was not consumed.")
        serviceCase = item
        return .success(item)
    }

    public func counts(asOf: String) -> Result<RewardPledgeCounts, RewardPledgeFailure> {
        guard !asOf.isEmpty else { return .failure(.closed("asOf")) }
        let state = grant?.state
        return .success(RewardPledgeCounts(
            grantedUnredeemed: state == "GRANTED_UNREDEEMED" ? 1 : 0,
            redeemed: state == "REDEEMED" ? 1 : 0,
            expired: state == "EXPIRED" ? 1 : 0,
            withdrawn: frozen?.status == "WITHDRAWN" ? 1 : 0,
            refused: state == "REFUSED" ? 1 : 0,
            version: frozen?.version ?? draft?.version ?? 0,
            asOf: asOf))
    }

    public func replenish() -> RewardPledgeFailure { policy.topUp == nil ? .closed("topUp") : .closed("W06") }

    public func mayOffer(_ item: SponsoredPoolItem, capabilities: SponsoredRewardCapabilities) -> Bool {
        item.pledgePresentable(capabilities)
    }

    public mutating func finishUnknown(requestID: String, seen: RewardPledgeScope) -> Result<Void, RewardPledgeFailure> {
        guard seen == scope else { return .failure(.stale) }
        guard unknowns.contains(where: { $0.requestID == requestID && $0.ownerID == scope.accountID }) else { return .failure(.closed("intent")) }
        unknowns.removeAll { $0.requestID == requestID && $0.ownerID == scope.accountID }
        return .success(())
    }

    public func persistedRows(existing: [RewardPledgeUnknown]) -> [RewardPledgeUnknown] {
        let kept = existing.filter { $0.ownerID != scope.accountID || $0.storeID != scope.storeID }
        return (kept + unknowns).sorted { $0.ownerID == $1.ownerID ? $0.businessKey < $1.businessKey : $0.ownerID < $1.ownerID }
    }

    private mutating func clearPresentation() {
        grant = nil; draft = nil; frozen = nil; serviceCase = nil; confirmedKey = nil
        previewedStoreID = nil; staffRoutes = []; listRefreshed = false; detailRefreshed = false; consumedCodes = []
    }
}

/// One row of `GET /api/rewards/noncash`. Subject exists only as `THEME:{id}:session:{sessionId}`.
public struct RewardPledgeAwardRow: Equatable, Identifiable, Sendable {
    public let awardId: String
    public let versionId: String
    public let ruleVersion: String
    public let rewardScope: String
    public let factRef: String
    public let state: String
    public let requestId: String
    public let historyId: String?
    public var id: String { awardId }
    public var themeSubjectID: String? {
        let parts = factRef.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "THEME", parts[2] == "session", !parts[1].isEmpty, !parts[3].isEmpty else { return nil }
        return parts[1]
    }
    public static func decodeList(_ data: Data) throws -> [RewardPledgeAwardRow] {
        guard data.count <= 1_048_576 else { throw APIError.malformedResponse }
        struct Envelope: Decodable { let code: Int; let data: [Wire] }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) } catch { throw APIError.malformedResponse }
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw RewardPledgeFailure.closed("http") }
        let rows = try envelope.data.map { try $0.row() }
        guard Set(rows.map(\.awardId)).count == rows.count else { throw APIError.malformedResponse }
        return rows
    }
    private struct Wire: Decodable {
        let awardId, versionId, ruleVersion, rewardScope, factRef, state, requestId: String
        let historyId: String?
        private enum CodingKeys: String, CodingKey {
            case awardId, versionId, ruleVersion, rewardScope, factRef, state, requestId, historyId
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            awardId = try c.decode(String.self, forKey: .awardId)
            versionId = try c.decode(String.self, forKey: .versionId)
            ruleVersion = try c.decode(String.self, forKey: .ruleVersion)
            rewardScope = try c.decode(String.self, forKey: .rewardScope)
            factRef = try c.decode(String.self, forKey: .factRef)
            state = try c.decode(String.self, forKey: .state)
            requestId = try c.decode(String.self, forKey: .requestId)
            if c.contains(.historyId), (try? c.decodeNil(forKey: .historyId)) == false {
                if let text = try? c.decode(String.self, forKey: .historyId) { historyId = text }
                else if let number = try? c.decode(Int64.self, forKey: .historyId) { historyId = String(number) }
                else { throw APIError.malformedResponse }
            } else { historyId = nil }
        }
        func row() throws -> RewardPledgeAwardRow {
            guard !awardId.isEmpty, !versionId.isEmpty, !requestId.isEmpty else { throw APIError.malformedResponse }
            return RewardPledgeAwardRow(awardId: awardId, versionId: versionId, ruleVersion: ruleVersion, rewardScope: rewardScope,
                                        factRef: factRef, state: state, requestId: requestId, historyId: historyId)
        }
    }
}

public struct RewardPledgeCaller: Equatable, Sendable {
    public let accountID: String
    public let epoch: UInt64
    public let region: String
    public let token: String
    public let read: Bool
    public let claim: Bool
    public let preview: Bool
    public let redeem: Bool
    public let draft: Bool
    public let freeze: Bool
    public let hold: Bool
    public let withdrawVersion: Bool
    public let expire: Bool
    public let returnPool: Bool
    public let support: Bool
    public let stats: Bool
    public init(accountID: String, epoch: UInt64, region: String, token: String, read: Bool, claim: Bool, preview: Bool, redeem: Bool,
                draft: Bool = false, freeze: Bool = false, hold: Bool = false, withdrawVersion: Bool = false,
                expire: Bool = false, returnPool: Bool = false, support: Bool = false, stats: Bool = false) {
        self.accountID = accountID; self.epoch = epoch; self.region = region; self.token = token
        self.read = read; self.claim = claim; self.preview = preview; self.redeem = redeem
        self.draft = draft; self.freeze = freeze; self.hold = hold; self.withdrawVersion = withdrawVersion
        self.expire = expire; self.returnPool = returnPool; self.support = support; self.stats = stats
    }
    public var anyOpen: Bool { read || claim || preview || redeem || draft || freeze || hold || withdrawVersion || expire || returnPool || support || stats }
}

public struct RewardPledgeEntry {
    public let client: RewardPledgeClient
    public let journalURL: URL
    public let current: @MainActor () -> RewardPledgeCaller?
    /// Existing published-coupon read. Closed when that approval is absent.
    public let coupons: @MainActor () async -> Result<[CouponDefinition], RewardPledgeFailure>
    public init(client: RewardPledgeClient, journalURL: URL, current: @escaping @MainActor () -> RewardPledgeCaller?,
                coupons: @escaping @MainActor () async -> Result<[CouponDefinition], RewardPledgeFailure> = { .failure(.closed("not open")) }) {
        self.client = client; self.journalURL = journalURL; self.current = current; self.coupons = coupons
    }
    public var accountID: String { current()?.accountID ?? "" }
}

public struct RewardPledgeServerBody: Equatable, Sendable {
    public let code: Int
    public let message: String
    public let fields: [String: String]
    public init(code: Int, message: String, fields: [String: String]) {
        self.code = code; self.message = message; self.fields = fields
    }
}

/// Calls ApiNonCashRewardController and ApiRewardPledgeController.
/// `open` is the grant for that call. A read grant does not open claim or redeem.
public struct RewardPledgeClient {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func awards(token: String, open: Bool, still: @MainActor () -> Bool) async throws -> [RewardPledgeAwardRow] {
        try RewardPledgeAwardRow.decodeList(try await fetch(try RewardPledgeRequests.list(baseURL: configuration.baseURL, token: token), open: open, still: still))
    }
    public func storeAwards(token: String, open: Bool, still: @MainActor () -> Bool) async throws -> [RewardPledgeAwardRow] {
        try RewardPledgeAwardRow.decodeList(try await fetch(try RewardPledgeRequests.storeAwards(baseURL: configuration.baseURL, token: token), open: open, still: still))
    }
    public func resolve(code: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.resolve(code: code, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func offer(versionID: String, subjectID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.offer(versionID: versionID, subjectID: subjectID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func claim(requestID: String, versionID: String, subjectID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.claim(requestID: requestID, versionID: versionID, subjectID: subjectID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func recover(requestID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.jsonRecover(requestID: requestID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func detail(awardID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.detail(awardID: awardID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func preview(awardID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.preview(awardID: awardID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func redeem(awardID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.redeem(awardID: awardID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func draft(_ supply: RewardPledgeRequests.Supply, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.draft(supply, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func submit(pledgeID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.submit(pledgeID: pledgeID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func confirm(pledgeID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.confirm(pledgeID: pledgeID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func readPledge(pledgeID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.readPledge(pledgeID: pledgeID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func freeze(pledgeID: String, ruleVersion: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.freeze(pledgeID: pledgeID, ruleVersion: ruleVersion, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func hold(versionID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.hold(versionID: versionID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func withdraw(versionID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.withdraw(versionID: versionID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func expire(awardID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.expire(awardID: awardID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func returnToPool(awardID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.returnToPool(awardID: awardID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func openCase(awardID: String, versionID: String, reason: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.openCase(awardID: awardID, versionID: versionID, reason: reason, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func readCase(caseID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.readCase(caseID: caseID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    public func stats(pledgeID: String, token: String, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        try await send(try RewardPledgeRequests.stats(pledgeID: pledgeID, baseURL: configuration.baseURL, token: token), open: open, still: still)
    }
    /// Preview must name the same request id and a coupon history before redeem is sent.
    public static func acceptedVoucher(preview: RewardPledgeServerBody, originalRequestID: String) -> Result<String, RewardPledgeFailure> {
        guard preview.code == 200 else { return .failure(.closed(preview.code == 403 ? "permission" : (preview.message.isEmpty ? "voucher" : preview.message))) }
        guard preview.fields["requestId"] == originalRequestID, !originalRequestID.isEmpty else { return .failure(.closed("requestID")) }
        guard let history = preview.fields["historyId"], !history.isEmpty else { return .failure(.closed("voucher")) }
        guard preview.fields["guaranteed"] != "true" else { return .failure(.closed("switches")) }
        let state = preview.fields["state"] ?? ""
        let use = preview.fields["useStatus"] ?? ""
        if use == "1" || state == "REDEEMED" { return .failure(.terminal("ALREADY_USED")) }
        if use == "2" || state == "EXPIRED" { return .failure(.terminal("EXPIRED")) }
        guard state == "AWARDED", use == "0", let award = preview.fields["awardId"], !award.isEmpty else {
            return .failure(.terminal(state.isEmpty ? "ABSENT" : state))
        }
        return .success(award)
    }
    private func fetch(_ request: URLRequest, open: Bool, still: @MainActor () -> Bool) async throws -> Data {
        guard open else { throw RewardPledgeFailure.closed("not open") }
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) }
        catch { throw RewardPledgeFailure.closed("unknown") }
        guard await MainActor.run(body: still) else { throw RewardPledgeFailure.stale }
        if status == 401 { throw APIError.unauthorized }
        return data
    }
    private func send(_ request: URLRequest, open: Bool, still: @MainActor () -> Bool) async throws -> RewardPledgeServerBody {
        let data = try await fetch(request, open: open, still: still)
        guard data.count <= 1_048_576, let body = RewardPledgeServerBody.decode(data) else { throw APIError.malformedResponse }
        if body.code == 401 { throw APIError.unauthorized }
        if body.code != 200 { throw RewardPledgeFailure.closed(body.message.isEmpty ? "http" : body.message) }
        return body
    }
}

private extension RewardPledgeRequests {
    static func jsonRecover(requestID: String, baseURL: URL, token: String) throws -> URLRequest {
        guard !requestID.isEmpty, requestID.count <= 128 else { throw RewardPledgeFailure.closed("requestID") }
        return try json(RewardPledgeRoutes.plannedIntentQuery, ["requestId": requestID], baseURL, token)
    }
}

private extension RewardPledgeServerBody {
    static func decode(_ data: Data) -> RewardPledgeServerBody? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = (object["code"] as? NSNumber)?.intValue ?? object["code"] as? Int else { return nil }
        let message = object["msg"] as? String ?? ""
        var fields: [String: String] = [:]
        if let data = object["data"] as? [String: Any] { flatten(data, into: &fields) }
        return RewardPledgeServerBody(code: code, message: message, fields: fields)
    }
    static func flatten(_ object: [String: Any], into fields: inout [String: String], prefix: String = "") {
        for (key, value) in object {
            let name = prefix.isEmpty ? key : prefix + "." + key
            if let child = value as? [String: Any] { flatten(child, into: &fields, prefix: name); continue }
            if let text = text(value) { fields[name] = text }
        }
    }
    static func text(_ value: Any) -> String? {
        if value is NSNull { return nil }
        if let text = value as? String { return text }
        if let number = value as? NSNumber {
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            let double = number.doubleValue
            if double.rounded() == double, double <= Double(Int64.max), double >= Double(Int64.min) { return String(number.int64Value) }
            return number.stringValue
        }
        return nil
    }
}
