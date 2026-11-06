import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityAcquisitionError: Error, Equatable { case disabled, stale, malformed, unknown, server(Int, String) }
public enum CityAcquisitionAction: String, Codable { case quote = "QUOTE", confirm = "CONFIRM" }

/// Independent reviewed deployment grant. Login, player role and board visibility never create it.
@available(macOS 14.0, *) @MainActor @Observable public final class CityAcquisitionApproval {
    public let context: RuntimeDependencyContext
    public let regionID: String
    public let allowsWrite: Bool
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, regionID: String, allowsWrite: Bool = false, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role), context.session.accountID > 0, context.role == context.session.role,
              AuthRequestBuilder.isValidToken(context.session.token), CityReadRoute.validID(regionID),
              expiresAt > Date(), expiresAt.timeIntervalSinceNow <= 86400 else { throw CityAcquisitionError.disabled }
        self.context = context; self.regionID = regionID; self.allowsWrite = allowsWrite; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ live: RuntimeDependencyContext) -> Bool { !revoked && Date() < expiresAt && ContentDraftContextFence.matches(context, live) && context.session == live.session && live.role == live.session.role }
}

public struct CityAcquisitionCandidate: Decodable, Equatable, Identifiable {
    public let instanceId, taskId, pointId, eligibility: String
    public let pointCost, actionCost, maxHoldingsPerTeam, termSeconds: Int?
    public let evidenceAcceptance: String?
    public var id: String { instanceId }
}
public struct CityAcquisitionQuote: Decodable, Equatable, Identifiable {
    public let quoteId, confirmRequestId, quoteHash, beneficiaryTeamId, sessionId, regionId, boardId, seasonId, roundId, pointId, contentHash, policyHash, taskInstanceId, taskResultId, evidenceId, evidenceAssurance, evidenceAcceptanceReason, createdAt, expiresAt, mode, releasePolicy, termPolicy, pausePolicy, rewardPolicy: String
    public let payerMemberId, releaseId, merchantId, placeId, teamVersion, budgetVersion, pointVersion, merchantVersion, platformVersion, pointsBalanceAtQuote: Int64
    public let pointCost, actionCost, maxHoldingsPerTeam, termSeconds, actionsRemainingAtQuote: Int
    public let writeApproved, expired: Bool
    public var id: String { quoteId }
    public var unexpired: Bool { !expired && (CityAcquisitionDates.parse(expiresAt).map { Date() < $0 } ?? false) }
}
public struct CityAcquisitionTitle: Decodable, Equatable, Identifiable {
    public let titleId, regionId, boardId, seasonId, pointId, ownerTeamId, contentHash, acquiredAt, status: String
    public let releaseId, pointVersion: Int64
    public let titleRetained, transferAllowed, serviceFeesAvailable: Bool
    public let payerMemberId, pointsBefore, pointsAfter, budgetVersion: Int64?
    public let requestId, quoteId, sessionId, roundId, taskResultId, evidenceId, pointsBusinessKey, policyHash: String?
    public let pointCost, actionCost, actionsBefore, actionsAfter, termSeconds: Int?
    public var id: String { titleId }
}
public struct CityAcquisitionSnapshot: Decodable, Equatable {
    public let contract, regionId, status: String
    public let memberId: Int64
    public let writeApproved: Bool
    public let binding: CityAcquisitionBinding?
    public let teamId: String?
    public let candidates: [CityAcquisitionCandidate]
    public let ownership, ownTitles: [CityAcquisitionTitle]
}
public struct CityAcquisitionCommand: Codable, Equatable {
    public let requestId, regionId: String
    public let kind: CityAcquisitionAction
    public let instanceId, quoteId, quoteHash: String?
    public let confirmed: Bool?
    public init(id: UUID, region: String, instanceID: String) { requestId = id.uuidString; regionId = region; kind = .quote; instanceId = instanceID; quoteId = nil; quoteHash = nil; confirmed = nil }
    public init(quote: CityAcquisitionQuote) { requestId = quote.confirmRequestId; regionId = quote.regionId; kind = .confirm; instanceId = nil; quoteId = quote.quoteId; quoteHash = quote.quoteHash; confirmed = true }
}
public struct CityAcquisitionReceipt: Equatable { public let requestId: String; public let succeeded: Bool; public let errorCode: String?; public let quote: CityAcquisitionQuote?; public let title: CityAcquisitionTitle? }
private enum CityAcquisitionDates {
    static func parse(_ value: String) -> Date? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
}
/// Exact self-funded acquisition routes. A CITY read/onsite grant never authorizes these writes.
@available(macOS 14.0, *) @MainActor public struct CityAcquisitionRoute {
    public let write: Bool
    public let regionID: String?
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpBodyStream == nil, let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.fragment == nil, parts.user == nil, parts.password == nil else { return nil }
        let prefix = baseURL.appendingPathComponent("api/city-game/acquisition").absoluteString
        if request.httpMethod == "GET", request.httpBody == nil {
            if let items = parts.queryItems, items.count == 1, items[0].name == "regionId", let region = items[0].value, CityReadRoute.validID(region), ["state", "titles"].contains(url.lastPathComponent) {
                var canonical = URLComponents(string: prefix + "/" + url.lastPathComponent)!; canonical.queryItems = [.init(name: "regionId", value: region)]
                guard canonical.url == url else { return nil }; write = false; regionID = region; return
            }
            if parts.query == nil, let id = UUID(uuidString: url.lastPathComponent), url.absoluteString == prefix + "/request/" + id.uuidString { write = false; regionID = nil; return }
            if parts.query == nil, Self.serverID(url.lastPathComponent), url.absoluteString == prefix + "/quote/" + url.lastPathComponent { write = false; regionID = nil; return }
        }
        if request.httpMethod == "POST", url.absoluteString == prefix + "/command", parts.query == nil,
           request.value(forHTTPHeaderField: "Content-Type") == "application/json", let data = request.httpBody, data.count <= 2048,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String:Any], let command = try? JSONDecoder().decode(CityAcquisitionCommand.self, from: data) {
            let keys: Set<String> = command.kind == .quote ? ["requestId", "kind", "regionId", "instanceId"] : ["requestId", "kind", "regionId", "quoteId", "quoteHash", "confirmed"]
            guard Set(object.keys) == keys, UUID(uuidString: command.requestId)?.uuidString == command.requestId, CityReadRoute.validID(command.regionId) else { return nil }
            if command.kind == .quote { guard Self.serverID(command.instanceId ?? ""), command.quoteId == nil, command.quoteHash == nil, command.confirmed == nil else { return nil } }
            else { guard Self.serverID(command.quoteId ?? ""), Self.hash(command.quoteHash ?? ""), command.confirmed == true, command.instanceId == nil else { return nil } }
            write = true; regionID = command.regionId; return
        }
        return nil
    }
    static func serverID(_ id: String) -> Bool { UUID(uuidString: id)?.uuidString.lowercased() == id }
    static func hash(_ value: String) -> Bool { value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
}
@available(macOS 14.0, *) @MainActor public final class CityAcquisitionTransport: HTTPTransport {
    private let approval: CityAcquisitionApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext) -> CityAcquisitionApproval?
    public init(approval: CityAcquisitionApproval, underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?, selected: @escaping (RuntimeDependencyContext) -> CityAcquisitionApproval?) {
        self.approval = approval; self.underlying = underlying; self.current = current; self.selected = selected
    }
    public func isCurrent() -> Bool { guard let live = current(), approval.matches(live), let selected = selected(live) else { return false }; return selected.revision == approval.revision && selected.matches(live) }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent(), !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Authorization") == approval.context.session.token,
              let route = CityAcquisitionRoute(request: request, baseURL: approval.context.baseURL),
              route.regionID == nil || route.regionID == approval.regionID, !route.write || approval.allowsWrite else { throw CityAcquisitionError.disabled }
        let result = try await underlying.send(request)
        try Task.checkCancellation(); guard isCurrent() else { throw CityAcquisitionError.stale }; return result
    }
}

@available(macOS 14.0, *) @MainActor public final class CityAcquisitionService {
    public let approval: CityAcquisitionApproval
    public let transport: CityAcquisitionTransport
    public init(approval: CityAcquisitionApproval, transport: CityAcquisitionTransport) { self.approval = approval; self.transport = transport }
    private struct EnvelopeStatus: Decodable { let code: Int }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let errorCode: String?; let data: T? }
    private struct ReceiptData: Decodable { let requestId, requestStatus: String; let contract, effectsStatus: String?; let quote: CityAcquisitionQuote?; let title: CityAcquisitionTitle? }
    private struct QuoteData: Decodable { let contract: String; let quote: CityAcquisitionQuote }
    private struct TitlesData: Decodable { let contract, regionId: String; let memberId: Int64; let titles: [CityAcquisitionTitle] }
    public func state() async throws -> CityAcquisitionSnapshot {
        let (data, status) = try await execute("state", query: [.init(name: "regionId", value: approval.regionID)])
        let e = try JSONDecoder().decode(Envelope<CityAcquisitionSnapshot>.self, from: data)
        guard status == 200, e.code == 200, let value = e.data else { throw CityAcquisitionError.server(status, e.errorCode ?? "UNAVAILABLE") }
        try validate(value); return value
    }
    public func titles() async throws -> [CityAcquisitionTitle] {
        let (data, status) = try await execute("titles", query: [.init(name: "regionId", value: approval.regionID)])
        let e = try JSONDecoder().decode(Envelope<TitlesData>.self, from: data)
        guard status == 200, e.code == 200, let value = e.data, value.contract == "CITY_ACQUISITION_V1", value.memberId == Int64(approval.context.session.accountID), value.regionId == approval.regionID, value.titles.count <= 200, Set(value.titles.map(\.id)).count == value.titles.count else { throw CityAcquisitionError.server(status, e.errorCode ?? "UNAVAILABLE") }
        for title in value.titles { try validate(title, personal: true) }; return value.titles
    }
    public func quote(_ id: String) async throws -> CityAcquisitionQuote {
        guard CityAcquisitionRoute.serverID(id) else { throw CityAcquisitionError.malformed }
        let (data, status) = try await execute("quote/" + id); let e = try JSONDecoder().decode(Envelope<QuoteData>.self, from: data)
        guard status == 200, e.code == 200, let value = e.data, value.contract == "CITY_ACQUISITION_V1", value.quote.quoteId == id else { throw CityAcquisitionError.server(status, e.errorCode ?? "UNAVAILABLE") }
        try validate(value.quote); return value.quote
    }
    public func submit(_ command: CityAcquisitionCommand) async throws { _ = try await execute("command", body: JSONEncoder().encode(command)) }
    public func receipt(_ id: UUID) async throws -> CityAcquisitionReceipt {
        let (data, status) = try await execute("request/" + id.uuidString); let e = try JSONDecoder().decode(Envelope<ReceiptData>.self, from: data)
        guard status != 403 else { throw CityAcquisitionError.server(403, e.errorCode ?? "FORBIDDEN") }
        guard let value = e.data, value.requestId == id.uuidString, value.requestStatus == "COMPLETE", e.code == status else { throw CityAcquisitionError.unknown }
        if status == 200 {
            guard value.contract == "CITY_ACQUISITION_V1", (value.quote == nil) != (value.title == nil) else { throw CityAcquisitionError.malformed }
            if let q = value.quote { try validate(q); guard value.effectsStatus == "NOT_EXECUTED" else { throw CityAcquisitionError.malformed } }
            if let t = value.title { try validate(t, personal: true); guard t.requestId == id.uuidString, value.effectsStatus == "COMMITTED" else { throw CityAcquisitionError.malformed } }
        } else {
            guard (400...499).contains(status), value.quote == nil, value.title == nil,
                  value.contract == nil || value.contract == "CITY_ACQUISITION_V1",
                  value.effectsStatus == nil || value.effectsStatus == "NOT_EXECUTED",
                  let code = e.errorCode, !code.isEmpty else { throw CityAcquisitionError.unknown }
        }
        return .init(requestId: value.requestId, succeeded: status == 200, errorCode: e.errorCode, quote: value.quote, title: value.title)
    }
    func validate(_ value: CityAcquisitionSnapshot) throws {
        guard value.contract == "CITY_ACQUISITION_V1", value.memberId == Int64(approval.context.session.accountID), value.regionId == approval.regionID,
              ["AVAILABLE", "JOIN_REQUIRED"].contains(value.status), value.candidates.count <= 50, value.ownership.count <= 200, value.ownTitles.count <= 200, Set(value.ownTitles.map(\.id)).count == value.ownTitles.count,
              Set(value.candidates.map(\.id)).count == value.candidates.count, Set(value.ownership.map(\.pointId)).count == value.ownership.count else { throw CityAcquisitionError.malformed }
        for t in value.ownTitles { try validate(t, personal: true) }
        if value.status == "JOIN_REQUIRED" { guard !value.writeApproved, value.teamId == nil, value.binding == nil, value.candidates.isEmpty, value.ownership.isEmpty else { throw CityAcquisitionError.malformed }; return }
        guard let b = value.binding, b.valid, b.regionId == approval.regionID, let team = value.teamId, CityAcquisitionRoute.serverID(team) else { throw CityAcquisitionError.malformed }
        for c in value.candidates {
            guard CityAcquisitionRoute.serverID(c.id), CityReadRoute.validID(c.taskId), CityReadRoute.validID(c.pointId), !c.eligibility.isEmpty else { throw CityAcquisitionError.malformed }
            if c.eligibility == "QUOTE_AVAILABLE" { guard c.evidenceAcceptance == "MERCHANT_ATTESTED", [c.pointCost,c.actionCost,c.maxHoldingsPerTeam,c.termSeconds].allSatisfy({ ($0 ?? 0) > 0 && ($0 ?? Int.max) <= 2_147_483_647 }) else { throw CityAcquisitionError.malformed } }
        }
        for t in value.ownership { try validate(t, personal: false); guard t.boardId == b.boardId, t.seasonId == b.seasonId else { throw CityAcquisitionError.malformed } }
    }
    func validate(_ q: CityAcquisitionQuote) throws {
        guard [q.quoteId,q.beneficiaryTeamId,q.sessionId,q.taskInstanceId,q.taskResultId,q.evidenceId].allSatisfy(CityAcquisitionRoute.serverID),
              UUID(uuidString: q.confirmRequestId)?.uuidString == q.confirmRequestId, [q.quoteHash,q.contentHash,q.policyHash].allSatisfy(CityAcquisitionRoute.hash),
              [q.regionId,q.boardId,q.seasonId,q.roundId,q.pointId].allSatisfy(CityReadRoute.validID), q.regionId == approval.regionID,
              q.payerMemberId == Int64(approval.context.session.accountID), [q.releaseId,q.merchantId,q.placeId,q.teamVersion].allSatisfy({ $0 > 0 && $0 <= 9_007_199_254_740_991 }),
              [q.budgetVersion,q.pointVersion,q.merchantVersion,q.platformVersion,q.pointsBalanceAtQuote].allSatisfy({ $0 >= 0 && $0 <= 9_007_199_254_740_991 }),
              [q.pointCost,q.actionCost,q.maxHoldingsPerTeam,q.termSeconds].allSatisfy({ $0 > 0 && $0 <= 2_147_483_647 }), q.pointsBalanceAtQuote >= Int64(q.pointCost), q.actionsRemainingAtQuote >= q.actionCost,
              q.mode == "TASK_ACTOR_SELF_PAY_FOR_ORIGINAL_TEAM_UNOWNED_ONLY", q.releasePolicy == "CURRENT_FROZEN_RELEASE_ONLY", q.evidenceAssurance == "MERCHANT_ATTESTED", !q.evidenceAcceptanceReason.isEmpty,
              q.termPolicy == "RETAIN_TITLE_PENDING_REVIEW", q.pausePolicy == "FREEZE_TERM_REVIEW_BEFORE_RESUME", q.rewardPolicy == "NONE",
              let created = CityAcquisitionDates.parse(q.createdAt), let expiry = CityAcquisitionDates.parse(q.expiresAt), expiry > created else { throw CityAcquisitionError.malformed }
    }
    func validate(_ t: CityAcquisitionTitle, personal: Bool) throws {
        guard [t.titleId,t.ownerTeamId].allSatisfy(CityAcquisitionRoute.serverID), [t.regionId,t.boardId,t.seasonId,t.pointId].allSatisfy(CityReadRoute.validID), t.regionId == approval.regionID,
              CityAcquisitionRoute.hash(t.contentHash), t.releaseId > 0, t.pointVersion > 0, t.titleRetained, !t.transferAllowed, !t.serviceFeesAvailable,
              ["ACTIVE_TERM","TERM_REVIEW_REQUIRED","PAUSED_TERM_FROZEN","SOURCE_UNAVAILABLE_TITLE_RETAINED"].contains(t.status), CityAcquisitionDates.parse(t.acquiredAt) != nil else { throw CityAcquisitionError.malformed }
        if !personal { guard t.payerMemberId == nil, t.requestId == nil, t.evidenceId == nil, t.pointsBusinessKey == nil else { throw CityAcquisitionError.malformed }; return }
        guard t.payerMemberId == Int64(approval.context.session.accountID), let request = t.requestId, UUID(uuidString: request)?.uuidString == request,
              [t.quoteId,t.sessionId,t.taskResultId,t.evidenceId].allSatisfy({ CityAcquisitionRoute.serverID($0 ?? "") }), CityReadRoute.validID(t.roundId ?? ""), CityAcquisitionRoute.hash(t.policyHash ?? ""),
              t.pointsBusinessKey == "CITY:ACQUIRE:" + t.id, let cost = t.pointCost, cost > 0, let before = t.pointsBefore, let after = t.pointsAfter, before >= 0, before <= 9_007_199_254_740_991, after >= 0, after <= before, before-after == Int64(cost),
              let actionCost = t.actionCost, actionCost > 0, let actionsBefore = t.actionsBefore, let actionsAfter = t.actionsAfter, actionsBefore >= 0, actionsBefore <= 1_000_000, actionsAfter >= 0, actionsAfter <= actionsBefore, actionsBefore-actionsAfter == actionCost,
              (t.budgetVersion ?? 0) > 0, (t.termSeconds ?? 0) > 0 else { throw CityAcquisitionError.malformed }
    }
    private func execute(_ path: String, query: [URLQueryItem]? = nil, body: Data? = nil) async throws -> (Data, Int) {
        var parts = URLComponents(url: approval.context.baseURL.appendingPathComponent("api/city-game/acquisition/" + path), resolvingAgainstBaseURL: false)!; parts.queryItems = query
        var request = URLRequest(url: parts.url!); request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let result = try await transport.send(request)
        if result.1 == 401 { throw APIError.unauthorized }
        if result.1 == 403 { throw CityAcquisitionError.server(403, "FORBIDDEN") }
        guard result.0.count <= 524288 else { throw CityAcquisitionError.malformed }
        let header = try? JSONDecoder().decode(EnvelopeStatus.self, from: result.0)
        if header?.code == 401 { throw APIError.unauthorized }
        if header?.code == 403 { throw CityAcquisitionError.server(403, "FORBIDDEN") }
        return result
    }
}

@available(macOS 14.0, *) extension CityAcquisitionQuote {
    /// Expiry/write availability may change; every originally quoted term must remain exact.
    func hasSameImmutableTerms(as original: Self) -> Bool {
        [quoteId, confirmRequestId, quoteHash, beneficiaryTeamId, sessionId, regionId, boardId, seasonId, roundId, pointId, contentHash, policyHash, taskInstanceId, taskResultId, evidenceId, evidenceAssurance, evidenceAcceptanceReason, createdAt, expiresAt, mode, releasePolicy, termPolicy, pausePolicy, rewardPolicy].enumerated().allSatisfy { index, value in
            value.utf8.elementsEqual([original.quoteId, original.confirmRequestId, original.quoteHash, original.beneficiaryTeamId, original.sessionId, original.regionId, original.boardId, original.seasonId, original.roundId, original.pointId, original.contentHash, original.policyHash, original.taskInstanceId, original.taskResultId, original.evidenceId, original.evidenceAssurance, original.evidenceAcceptanceReason, original.createdAt, original.expiresAt, original.mode, original.releasePolicy, original.termPolicy, original.pausePolicy, original.rewardPolicy][index].utf8)
        } &&
        [payerMemberId, releaseId, merchantId, placeId, teamVersion, budgetVersion, pointVersion, merchantVersion, platformVersion, pointsBalanceAtQuote] == [original.payerMemberId, original.releaseId, original.merchantId, original.placeId, original.teamVersion, original.budgetVersion, original.pointVersion, original.merchantVersion, original.platformVersion, original.pointsBalanceAtQuote] &&
        [pointCost, actionCost, maxHoldingsPerTeam, termSeconds, actionsRemainingAtQuote] == [original.pointCost, original.actionCost, original.maxHoldingsPerTeam, original.termSeconds, original.actionsRemainingAtQuote]
    }
}
