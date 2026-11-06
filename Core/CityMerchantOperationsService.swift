import Foundation
import CoreFoundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityMerchantOperationError: Error, Equatable { case disabled, stale, malformed, server(Int, String), unknown }

/// Exact GET-original-request rejection. Only errors emitted by the original stored
/// merchant work are recognized; transport failures and unbound generic errors are not receipts.
public struct CityMerchantOriginalRejection: Error, Equatable {
    public let requestID: UUID
    public let code: Int
    public let reason: String
    static func matches(code: Int, reason: String) -> Bool {
        switch code {
        case 400: return ["OBJECT_SCOPE", "REASON_REQUIRED"].contains(reason)
        case 409: return ["PUBLISHED_MERCHANT_RELATION_UNAVAILABLE", "VERSION_CONFLICT", "APPROVAL_CHANGED",
                          "PENDING_REVIEW", "INVALID_STATE"].contains(reason)
        default: return false
        }
    }
}

/// Reviewed deployment lease, not merchant authority or proof that any CITY runtime exists.
@available(macOS 14.0, *) @MainActor @Observable public final class CityMerchantOperationsApproval {
    public let context: RuntimeDependencyContext
    public let regionID: String
    public let revision = UUID()
    public let expiresAt: Date
    public let allowsIntent: Bool
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, regionID: String, allowsIntent: Bool = false, expiresAt: Date, now: Date = Date()) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.role == "merchant", context.session.accountID > 0,
              AuthRequestBuilder.isValidToken(context.session.token), Self.safeID(regionID),
              expiresAt > now, expiresAt.timeIntervalSince(now) <= 86400 else { throw CityMerchantOperationError.disabled }
        self.context = context; self.regionID = regionID; self.allowsIntent = allowsIntent; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ value: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !revoked && now < expiresAt && ContentDraftContextFence.matches(context, value)
    }
    public static func safeID(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$", options: .regularExpression) != nil }
}

public struct CityMerchantSnapshot: Decodable, Equatable {
    public let merchantId: String
    public let version: Int64
    public let status: String
    public let effectiveState: String
    public let kind: String?
    public let requestId: String?
    public let originalRequestId: String?
    public let approvalHash: String?
    public let availability: String?
    public let runtimeApplied: Bool
    public let relation: CityMerchantRelation?
    public var available: Bool { availability == "AVAILABLE" && relation != nil && approvalHash?.count == 64 }
    public var pendingReview: Bool { status == "IN_REVIEW" || status == "APPROVED" }
}
public struct CityMerchantRelation: Decodable, Equatable {
    public let regionId: String
    public let boardId: String
    public let seasonId: String
    public let rulesReleaseId: String
    public let pointIds: [String]
}
public enum CityMerchantIntent: String, CaseIterable, Identifiable { case pause = "PAUSE_MERCHANT", restore = "RESTORE"; public var id: String { rawValue } }

/// Only this exact three-route contract is admitted. No staff, rules, fees or asset routes.
@available(macOS 14.0, *) @MainActor public struct CityMerchantRoute {
    public enum Kind: Equatable { case availability, intent, receipt }
    public let kind: Kind
    public let regionID: String?
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpBodyStream == nil, let url = request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil, parts.password == nil, parts.fragment == nil else { return nil }
        let prefix = baseURL.appendingPathComponent("api/city-game/merchant/operations").absoluteString
        if request.httpMethod == "GET", request.httpBody == nil, let query = parts.queryItems, query.count == 1,
           query[0].name == "regionId", let region = query[0].value, CityMerchantOperationsApproval.safeID(region) {
            var canonical = URLComponents(string: prefix + "/availability")!; canonical.queryItems = [.init(name: "regionId", value: region)]
            guard canonical.url == url else { return nil }; kind = .availability; regionID = region; return
        }
        if request.httpMethod == "GET", request.httpBody == nil, parts.query == nil,
           url.absoluteString.hasPrefix(prefix + "/request/"),
           let id = UUID(uuidString: url.lastPathComponent), url.absoluteString == prefix + "/request/" + id.uuidString {
            kind = .receipt; regionID = nil; return
        }
        if request.httpMethod == "POST", url.absoluteString == prefix + "/intent", parts.query == nil,
           request.value(forHTTPHeaderField: "Content-Type") == "application/json", let data = request.httpBody,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           Set(object.keys) == ["requestId", "expectedVersion", "regionId", "kind", "reason", "approvalHash"],
           let id = object["requestId"] as? String, UUID(uuidString: id)?.uuidString == id,
           let region = object["regionId"] as? String, CityMerchantOperationsApproval.safeID(region),
           let choice = object["kind"] as? String, CityMerchantIntent(rawValue: choice) != nil,
           let reason = object["reason"] as? String, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.utf16.count <= 500,
           let hash = object["approvalHash"] as? String, hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
           let version = object["expectedVersion"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
           version.int64Value >= 0, version.int64Value <= 9_007_199_254_740_991, version.doubleValue == Double(version.int64Value) {
            kind = .intent; regionID = region; return
        }
        return nil
    }
}

/// Dedicated composition-approved transport. Credentials are never followed through redirects (underlying URLSessionTransport).
@available(macOS 14.0, *) @MainActor public final class CityMerchantOperationsTransport: HTTPTransport {
    private let approval: CityMerchantOperationsApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: @MainActor (RuntimeDependencyContext) -> CityMerchantOperationsApproval?
    public init(approval: CityMerchantOperationsApproval, underlying: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, selected: @escaping @MainActor (RuntimeDependencyContext) -> CityMerchantOperationsApproval?) {
        self.approval = approval; self.underlying = underlying; self.current = current; self.selected = selected
    }
    public func isCurrent() -> Bool {
        guard let context = current(), approval.matches(context), let live = selected(context) else { return false }
        return live.revision == approval.revision && live.matches(context)
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent(), request.value(forHTTPHeaderField: "Authorization") == approval.context.session.token,
              let route = CityMerchantRoute(request: request, baseURL: approval.context.baseURL),
              route.regionID == nil || route.regionID == approval.regionID,
              route.kind != .intent || approval.allowsIntent else { throw CityMerchantOperationError.disabled }
        let result = try await underlying.send(request)
        try Task.checkCancellation()
        guard isCurrent() else { throw CityMerchantOperationError.stale }
        return result
    }
}

@available(macOS 14.0, *) @MainActor public final class CityMerchantOperationsService {
    public let approval: CityMerchantOperationsApproval
    public let transport: CityMerchantOperationsTransport
    public init(approval: CityMerchantOperationsApproval, transport: CityMerchantOperationsTransport) { self.approval = approval; self.transport = transport }
    public func availability() async throws -> CityMerchantSnapshot {
        var parts = URLComponents(url: approval.context.baseURL.appendingPathComponent("api/city-game/merchant/operations/availability"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [.init(name: "regionId", value: approval.regionID)]
        return try await execute(url: parts.url!)
    }
    public func submit(id: UUID, version: Int64, kind: CityMerchantIntent, reason: String, approvalHash: String) async throws -> CityMerchantSnapshot {
        let body = try JSONSerialization.data(withJSONObject: ["requestId":id.uuidString,"expectedVersion":version,"regionId":approval.regionID,"kind":kind.rawValue,"reason":reason,"approvalHash":approvalHash], options: [.sortedKeys])
        return try await execute(url: approval.context.baseURL.appendingPathComponent("api/city-game/merchant/operations/intent"), body: body)
    }
    public func receipt(id: UUID) async throws -> CityMerchantSnapshot {
        let value = try await execute(url: approval.context.baseURL.appendingPathComponent("api/city-game/merchant/operations/request/" + id.uuidString), originalRequestID: id)
        guard value.requestId == id.uuidString, value.originalRequestId == id.uuidString,
              value.status != "NONE" else { throw CityMerchantOperationError.malformed }
        return value
    }
    private struct Envelope: Decodable { let code: Int; let errorCode: String? }
    private struct Success: Decodable { let data: CityMerchantSnapshot }
    private func execute(url: URL, body: Data? = nil, originalRequestID: UUID? = nil) async throws -> CityMerchantSnapshot {
        var request = URLRequest(url: url); request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, status) = try await transport.send(request)
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw CityMerchantOperationError.server(403, "NO_AUTHORITY") }
        guard data.count <= 256 * 1024, let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw CityMerchantOperationError.malformed }
        if envelope.code == 401 { throw APIError.unauthorized }
        guard status == 200, envelope.code == 200 else {
            if envelope.errorCode == "UNKNOWN" { throw CityMerchantOperationError.unknown }
            if let originalRequestID, body == nil, status == envelope.code, let reason = envelope.errorCode,
               CityMerchantOriginalRejection.matches(code: status, reason: reason) {
                throw CityMerchantOriginalRejection(requestID: originalRequestID, code: status, reason: reason)
            }
            throw CityMerchantOperationError.server(envelope.code, envelope.errorCode ?? "UNAVAILABLE")
        }
        let value = try JSONDecoder().decode(Success.self, from: data).data
        guard Int64(value.merchantId).map({ $0 > 0 }) == true, value.version >= 0, !value.runtimeApplied,
              ["NONE","IN_REVIEW","APPROVED","REJECTED","APPLIED"].contains(value.status),
              ["INHERIT","PAUSED","RESTORED"].contains(value.effectiveState) else { throw CityMerchantOperationError.malformed }
        if let relation = value.relation {
            guard relation.regionId == approval.regionID, !relation.pointIds.isEmpty,
                  [relation.boardId, relation.seasonId, relation.rulesReleaseId].allSatisfy(CityMerchantOperationsApproval.safeID),
                  relation.pointIds.allSatisfy(CityMerchantOperationsApproval.safeID) else { throw CityMerchantOperationError.malformed }
        }
        return value
    }
}
