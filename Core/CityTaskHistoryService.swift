import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityTaskHistoryError: Error, Equatable { case disabled, stale, malformed, server(Int, String) }

/// A separately reviewed, read-only lease. It never grants task execution or location sharing.
@available(macOS 14.0, *) @MainActor @Observable public final class CityTaskHistoryApproval {
    public let context: RuntimeDependencyContext
    public let regionID: String
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, regionID: String, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role), context.session.accountID > 0, context.role == context.session.role,
              AuthRequestBuilder.isValidToken(context.session.token), CityReadRoute.validID(regionID), expiresAt > Date(),
              expiresAt.timeIntervalSinceNow <= 86400 else { throw CityTaskHistoryError.disabled }
        self.context = context; self.regionID = regionID; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ live: RuntimeDependencyContext) -> Bool { !revoked && Date() < expiresAt && ContentDraftContextFence.matches(context, live) && context.session == live.session && live.role == live.session.role }
}
public struct CityTaskHistoryItem: Codable, Equatable, Identifiable {
    public let instanceId, regionId, boardId, seasonId, roundId, teamId, sessionId, taskId, pointId, rulesReleaseId, contentHash, taskHash, status, acceptRequestId, acceptedAt, evidenceId, arrivalAssurance, effectsStatus: String
    public let memberId, releaseId, version: Int64
    public let attempts, maxAttempts: Int
    public let title: String?
    public var id: String { instanceId }
}
public struct CityTaskHistoryAttempt: Codable, Equatable, Identifiable {
    public let attemptId, requestId, optionId, createdAt, evidenceCheckedAt: String
    public let attemptNumber: Int
    public let passed: Bool
    public var id: String { attemptId }
}
public struct CityTaskHistoryPage: Decodable, Equatable {
    public let contract, scope, regionId, readAt, currentQualification: String
    public let memberId: Int64
    public let readOnly: Bool
    public let pageSize: Int
    public let items: [CityTaskHistoryItem]
    public let nextBeforeInstanceId: String?
}
public struct CityTaskHistoryDetail: Decodable, Equatable {
    public let contract, scope, regionId, readAt, currentQualification: String
    public let memberId: Int64
    public let readOnly: Bool
    public let instance: CityTaskHistoryItem
    public let attempts: [CityTaskHistoryAttempt]
    public let result: CityOnsiteTaskResult?
}
public struct CityTaskHistoryReceipt: Equatable {
    public let requestID, status: String
    public let httpStatus: Int
    public let errorCode: String?
    public let result: CityOnsiteTaskResult?
}
@available(macOS 14.0, *) @MainActor public struct CityTaskHistoryRoute {
    public let regionID: String
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.fragment == nil, parts.user == nil, parts.password == nil, let query = parts.queryItems,
              let first = query.first, first.name == "regionId", let region = first.value, CityReadRoute.validID(region) else { return nil }
        let prefix = baseURL.appendingPathComponent("api/city-game/task-history").absoluteString
        guard url.absoluteString.hasPrefix(prefix) else { return nil }
        let path = String(url.absoluteString.prefix { $0 != "?" }.dropFirst(prefix.count))
        if path.isEmpty {
            guard query.count == 1 || query.count == 2 && query[1].name == "beforeInstanceId" && Self.serverID(query[1].value ?? "") else { return nil }
        } else {
            let bits = path.split(separator: "/", omittingEmptySubsequences: false)
            guard query.count == 1, bits.count == 3 || bits.count == 5, bits[0].isEmpty, bits[1] == "instance", Self.serverID(String(bits[2])) else { return nil }
            if bits.count == 5 { guard bits[3] == "request", CityReadRoute.validID(String(bits[4])) else { return nil } }
        }
        var canonical = URLComponents(string: prefix + path)!; canonical.queryItems = query
        guard canonical.url == url else { return nil }; regionID = region
    }
    static func serverID(_ id: String) -> Bool { id.range(of: "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$", options: .regularExpression) != nil }
}
@available(macOS 14.0, *) @MainActor public final class CityTaskHistoryTransport: HTTPTransport {
    private let approval: CityTaskHistoryApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext) -> CityTaskHistoryApproval?
    public init(approval: CityTaskHistoryApproval, underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?, selected: @escaping (RuntimeDependencyContext) -> CityTaskHistoryApproval?) {
        self.approval = approval; self.underlying = underlying; self.current = current; self.selected = selected
    }
    public func isCurrent() -> Bool { guard let live = current() else { return false }; return approval.matches(live) && selected(live)?.revision == approval.revision }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent(), !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Authorization") == approval.context.session.token,
              let route = CityTaskHistoryRoute(request: request, baseURL: approval.context.baseURL), route.regionID == approval.regionID else { throw CityTaskHistoryError.disabled }
        let response = try await underlying.send(request)
        try Task.checkCancellation(); guard isCurrent() else { throw CityTaskHistoryError.stale }; return response
    }
}
@available(macOS 14.0, *) @MainActor public final class CityTaskHistoryService {
    public let approval: CityTaskHistoryApproval
    public let transport: CityTaskHistoryTransport
    public init(approval: CityTaskHistoryApproval, transport: CityTaskHistoryTransport) { self.approval = approval; self.transport = transport }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let errorCode: String?; let data: T? }
    private struct ReceiptData: Decodable { let requestId, requestStatus: String; let result: CityOnsiteTaskResult? }
    public func page(before: String? = nil) async throws -> CityTaskHistoryPage {
        if let before, !CityTaskHistoryRoute.serverID(before) { throw CityTaskHistoryError.malformed }
        let response = try await execute("", before: before)
        let value: CityTaskHistoryPage = try decode(response)
        try validateBase(value.contract, value.scope, value.regionId, value.memberId, value.readAt, value.readOnly, value.currentQualification)
        guard value.pageSize == 20, value.items.count <= 20, Set(value.items.map(\.id)).count == value.items.count,
              value.items.allSatisfy({ $0.id != before }) else { throw CityTaskHistoryError.malformed }
        for item in value.items { try validateItem(item) }
        if let cursor = value.nextBeforeInstanceId { guard value.items.count == 20, cursor == value.items.last?.id else { throw CityTaskHistoryError.malformed } }
        return value
    }
    public func detail(_ id: String) async throws -> CityTaskHistoryDetail {
        guard CityTaskHistoryRoute.serverID(id) else { throw CityTaskHistoryError.malformed }
        let value: CityTaskHistoryDetail = try decode(await execute("/instance/" + id))
        try validateBase(value.contract, value.scope, value.regionId, value.memberId, value.readAt, value.readOnly, value.currentQualification)
        try validateItem(value.instance)
        guard value.instance.id == id, value.attempts.count == value.instance.attempts,
              Set(value.attempts.map(\.id)).count == value.attempts.count, Set(value.attempts.map(\.requestId)).count == value.attempts.count else { throw CityTaskHistoryError.malformed }
        for (offset, attempt) in value.attempts.enumerated() {
            guard CityTaskHistoryRoute.serverID(attempt.id), CityReadRoute.validID(attempt.requestId), CityReadRoute.validID(attempt.optionId),
                  attempt.requestId != value.instance.acceptRequestId, attempt.attemptNumber == offset + 1,
                  Self.date(attempt.createdAt) != nil, Self.date(attempt.evidenceCheckedAt) != nil,
                  !attempt.passed || offset == value.attempts.count - 1 && value.instance.status == "PASSED" else { throw CityTaskHistoryError.malformed }
        }
        if value.instance.status == "ACTIVE" { guard value.result == nil else { throw CityTaskHistoryError.malformed } }
        else { guard let result = value.result, result.requestId == value.attempts.last?.requestId else { throw CityTaskHistoryError.malformed }; try validateResult(result, item: value.instance) }
        return value
    }
    public func receipt(_ requestID: String, in detail: CityTaskHistoryDetail) async throws -> CityTaskHistoryReceipt {
        guard requestID == detail.instance.acceptRequestId || detail.attempts.contains(where: { $0.requestId == requestID }) else { throw CityTaskHistoryError.malformed }
        let response = try await execute("/instance/" + detail.instance.id + "/request/" + requestID)
        let envelope = try JSONDecoder().decode(Envelope<ReceiptData>.self, from: response.0)
        guard envelope.code == response.1, let data = envelope.data, data.requestId == requestID,
              data.requestStatus == "COMPLETE" || data.requestStatus == "UNKNOWN" && response.1 == 202 else { throw CityTaskHistoryError.malformed }
        if let result = data.result { try validateResult(result, item: detail.instance); guard result.requestId == requestID else { throw CityTaskHistoryError.malformed } }
        return .init(requestID: data.requestId, status: data.requestStatus, httpStatus: response.1, errorCode: envelope.errorCode, result: data.result)
    }
    private func validateBase(_ contract: String, _ scope: String, _ region: String, _ member: Int64, _ readAt: String, _ readOnly: Bool, _ qualification: String) throws {
        guard contract == "CITY_PERSONAL_TASK_HISTORY_V1", scope == "OWN_ONSITE_TASKS_ONLY", region == approval.regionID,
              member == Int64(approval.context.session.accountID), readOnly, qualification == "NOT_EVALUATED", Self.date(readAt) != nil else { throw CityTaskHistoryError.malformed }
    }
    private func validateItem(_ item: CityTaskHistoryItem) throws {
        guard [item.id, item.teamId, item.sessionId, item.evidenceId].allSatisfy(CityTaskHistoryRoute.serverID),
              [item.regionId, item.boardId, item.seasonId, item.roundId, item.taskId, item.pointId, item.rulesReleaseId, item.acceptRequestId].allSatisfy(CityReadRoute.validID),
              item.regionId == approval.regionID, item.memberId == Int64(approval.context.session.accountID), item.releaseId > 0, item.releaseId <= 9_007_199_254_740_991,
              [item.contentHash, item.taskHash].allSatisfy(Self.hash), item.version == Int64(item.attempts) + 1,
              (1...20).contains(item.maxAttempts), (0...item.maxAttempts).contains(item.attempts), ["ACTIVE", "PASSED", "EXHAUSTED"].contains(item.status),
              item.status != "ACTIVE" || item.attempts < item.maxAttempts, item.status != "PASSED" || item.attempts > 0,
              item.status != "EXHAUSTED" || item.attempts == item.maxAttempts, Self.date(item.acceptedAt) != nil,
              item.title == nil || !(item.title?.isEmpty ?? true) && (item.title?.count ?? 0) <= 160,
              item.arrivalAssurance == "MERCHANT_ATTESTED", item.effectsStatus == "NOT_EXECUTED" else { throw CityTaskHistoryError.malformed }
    }
    private func validateResult(_ r: CityOnsiteTaskResult, item: CityTaskHistoryItem) throws {
        guard r.instanceId == item.id, r.memberId == item.memberId, r.regionId == item.regionId, r.boardId == item.boardId, r.seasonId == item.seasonId,
              r.roundId == item.roundId, r.teamId == item.teamId, r.sessionId == item.sessionId, r.taskId == item.taskId, r.pointId == item.pointId,
              r.evidenceId == item.evidenceId, r.acceptRequestId == item.acceptRequestId, r.releaseId == item.releaseId, r.rulesReleaseId == item.rulesReleaseId,
              r.contentHash == item.contentHash, r.taskHash == item.taskHash, r.outcome == item.status, r.attemptNumber == item.attempts,
              CityTaskHistoryRoute.serverID(r.resultId), CityReadRoute.validID(r.requestId), Self.hash(r.evidencePolicyHash),
              r.merchantId > 0, r.placeId > 0, r.merchantId <= 9_007_199_254_740_991, r.placeId <= 9_007_199_254_740_991,
              r.verifier == "NATIVE_OBJECTIVE_QA_PICK_V1", r.arrivalAssurance == "MERCHANT_ATTESTED", r.effectsStatus == "NOT_EXECUTED",
              Self.date(r.createdAt) != nil, let checked = Self.date(r.evidenceCheckedAt), let expiry = Self.date(r.evidenceExpiresAt), checked < expiry else { throw CityTaskHistoryError.malformed }
    }
    private func decode<T: Decodable>(_ response: (Data, Int)) throws -> T {
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: response.0)
        guard response.1 == 200, envelope.code == 200, let value = envelope.data else { throw CityTaskHistoryError.server(response.1, envelope.errorCode ?? "UNAVAILABLE") }; return value
    }
    private func execute(_ path: String, before: String? = nil) async throws -> (Data, Int) {
        var parts = URLComponents(string: approval.context.baseURL.appendingPathComponent("api/city-game/task-history").absoluteString + path)!
        parts.queryItems = [.init(name: "regionId", value: approval.regionID)]
        if let before { parts.queryItems?.append(.init(name: "beforeInstanceId", value: before)) }
        var request = URLRequest(url: parts.url!); request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await transport.send(request)
        if response.1 == 401 { throw APIError.unauthorized }
        if response.1 == 403 { throw CityTaskHistoryError.server(403, "FORBIDDEN") }
        guard response.0.count <= 262144 else { throw CityTaskHistoryError.malformed }; return response
    }
    private static func hash(_ text: String) -> Bool { text.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
    private static func date(_ text: String) -> Date? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: text) ?? ISO8601DateFormatter().date(from: text) }
}
