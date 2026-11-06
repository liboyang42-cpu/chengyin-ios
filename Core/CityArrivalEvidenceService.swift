import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityArrivalEvidenceError: Error, Equatable { case disabled, stale, malformed, unknown, server(Int, String) }
public enum CityArrivalAudience: Equatable { case player(regionID: String), merchant(merchantID: Int64) }
public enum CityArrivalAction: String, Codable { case issue = "ISSUE", submit = "SUBMIT", confirm = "CONFIRM", reject = "REJECT" }
@available(macOS 14.0, *) @MainActor @Observable public final class CityArrivalEvidenceApproval {
    public let context: RuntimeDependencyContext
    public let audience: CityArrivalAudience
    public let allowsWrite: Bool
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, audience: CityArrivalAudience, allowsWrite: Bool = false, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role), context.session.accountID > 0, context.session.role == context.role,
              AuthRequestBuilder.isValidToken(context.session.token), expiresAt > Date(), expiresAt.timeIntervalSinceNow <= 86400 else { throw CityArrivalEvidenceError.disabled }
        switch audience { case .player(let region): guard CityReadRoute.validID(region) else { throw CityArrivalEvidenceError.disabled }
        case .merchant(let merchant): guard merchant > 0 && merchant <= 9_007_199_254_740_991 else { throw CityArrivalEvidenceError.disabled } }
        self.context = context; self.audience = audience; self.allowsWrite = allowsWrite; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ live: RuntimeDependencyContext) -> Bool { !revoked && Date() < expiresAt && ContentDraftContextFence.matches(context, live) && context.session == live.session && live.session.role == live.role }
}
public struct CityArrivalPlaceRef: Codable, Equatable { public let domain, source, id: String }
public struct CityArrivalPolicy: Codable, Equatable {
    public let pointId, method, assurance, assuranceReason, evidenceScope, effectsPolicy, renewalPolicy: String
    public let placeRef: CityArrivalPlaceRef
    public let challengeTtlSeconds, evidenceTtlSeconds, maxChallenges: Int
    var valid: Bool { CityReadRoute.validID(pointId) && placeRef.domain == "POI" && placeRef.source == "roam_poi" && Int64(placeRef.id).map({ $0 > 0 && $0 <= 9_007_199_254_740_991 && String($0) == placeRef.id }) == true &&
        method == "SERVER_CHALLENGE_MEMBER_SUBMIT_STAFF_CONFIRM" && assurance == "MERCHANT_ATTESTED" && !assuranceReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && assuranceReason.count <= 500 &&
        evidenceScope == "MEMBER_POINT_TEAM_ROUND" && effectsPolicy == "EVIDENCE_ONLY_NO_AUTOMATIC_EFFECTS" && renewalPolicy == "NO_REISSUE_AFTER_EVIDENCE" &&
        (1...86400).contains(challengeTtlSeconds) && (1...86400).contains(evidenceTtlSeconds) && (1...1_000_000).contains(maxChallenges) }
}
public struct CityArrivalChallenge: Codable, Equatable, Identifiable {
    public let challengeId, requestId, pointId, teamId, sessionId, contentHash, state, expiresAt, regionId, boardId, seasonId, roundId, rulesReleaseId, policyHash: String
    public let pointTitle: String?
    public let memberId, merchantId, placeId, releaseId, version: Int64
    public let ordinal: Int
    public var id: String { challengeId }
}
public struct CityArrivalProof: Codable, Equatable, Identifiable {
    public let evidenceId, challengeId, requestId, teamId, sessionId, pointId, contentHash, assurance, reason, reviewerRole, createdAt, expiresAt, timeStatus, currentTaskEligibility, effectsStatus, regionId, boardId, seasonId, roundId, rulesReleaseId, policyHash: String
    public let memberId, merchantId, placeId, releaseId, reviewerMemberId: Int64
    public var id: String { evidenceId }
}
public struct CityArrivalPoint: Decodable, Equatable, Identifiable {
    public let pointId, title, availability: String
    public let merchantId, placeId: Int64
    public let rules: CityArrivalPolicy
    public let attemptVersion: Int64
    public let canIssue: Bool
    public let challenge: CityArrivalChallenge?
    public let evidence: CityArrivalProof?
    public var id: String { pointId }
}
public struct CityArrivalPlayerSnapshot: Decodable, Equatable {
    public let contract, status: String
    public let scope, teamId, sessionId, effectsStatus, taskEligibility: String?
    public let teamVersion: Int64?
    public let binding: CityArrivalEvidenceBinding?
    public let writeApproved: Bool
    public let points: [CityArrivalPoint]
}
public struct CityArrivalMerchantSnapshot: Decodable, Equatable {
    public let contract, role: String
    public let merchantId, ownerMemberId: Int64
    public let writeApproved: Bool
    public let pending: [CityArrivalChallenge]
}
public struct CityArrivalCommand: Codable, Equatable {
    public let requestId: String
    public let kind: CityArrivalAction
    public let expectedVersion: Int64
    public let regionId, teamId, pointId, contentHash, challengeId, displayCode, reason: String?
    public let releaseId, expectedTeamVersion: Int64?
    public init(id: UUID, binding: CityArrivalEvidenceBinding, team: String, teamVersion: Int64, point: CityArrivalPoint) {
        requestId = id.uuidString; kind = .issue; expectedVersion = point.attemptVersion
        regionId = binding.regionId; teamId = team; pointId = point.pointId; contentHash = binding.contentHash; releaseId = binding.releaseId; expectedTeamVersion = teamVersion
        challengeId = nil; displayCode = nil; reason = nil
    }
    public init(id: UUID, kind: CityArrivalAction, challenge: CityArrivalChallenge, code: String, reason: String? = nil) {
        requestId = id.uuidString; self.kind = kind; expectedVersion = challenge.version; challengeId = challenge.challengeId; displayCode = code; self.reason = reason
        regionId = nil; teamId = nil; pointId = nil; contentHash = nil; releaseId = nil; expectedTeamVersion = nil
    }
}
public struct CityArrivalReceipt: Equatable {
    public let requestId: String
    public let succeeded: Bool
    public let challenge: CityArrivalChallenge?
    public let evidence: CityArrivalProof?
    public let displayCode: String?
}
@available(macOS 14.0, *) @MainActor public struct CityArrivalEvidenceRoute {
    public let write: Bool
    public init?(request: URLRequest, baseURL: URL, audience: CityArrivalAudience) {
        guard request.httpBodyStream == nil, let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.fragment == nil, parts.user == nil, parts.password == nil else { return nil }
        let prefix = baseURL.appendingPathComponent("api/city-game/arrival-evidence").absoluteString
        if request.httpMethod == "GET", request.httpBody == nil {
            if case .player(let region) = audience {
                var expected = URLComponents(string: prefix + "/state")!; expected.queryItems = [.init(name: "regionId", value: region)]
                if url == expected.url { write = false; return }
            }
            if case .merchant = audience, url.absoluteString == prefix + "/merchant", parts.query == nil { write = false; return }
            let id = url.lastPathComponent
            if parts.query == nil, (CityReadRoute.validID(id) && url.absoluteString == prefix + "/request/" + id) || (Self.serverID(id) && url.absoluteString == prefix + "/evidence/" + id) { write = false; return }
        }
        guard request.httpMethod == "POST", url.absoluteString == prefix + "/command", parts.query == nil, request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let data = request.httpBody, data.count <= 4096, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let command = try? JSONDecoder().decode(CityArrivalCommand.self, from: data),
              UUID(uuidString: command.requestId)?.uuidString == command.requestId, command.expectedVersion >= 0, command.expectedVersion <= 9_007_199_254_740_991 else { return nil }
        let keys: Set<String>
        switch command.kind {
        case .issue:
            keys = ["requestId", "kind", "regionId", "teamId", "pointId", "releaseId", "contentHash", "expectedTeamVersion", "expectedVersion"]
            guard case .player(let region) = audience, command.regionId == region, let team = command.teamId, Self.serverID(team), let point = command.pointId, CityReadRoute.validID(point),
                  let release = command.releaseId, release > 0, release <= 9_007_199_254_740_991, let version = command.expectedTeamVersion, version > 0, version <= 9_007_199_254_740_991,
                  let hash = command.contentHash, hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
        case .submit:
            keys = ["requestId", "kind", "challengeId", "expectedVersion", "displayCode"]
            guard case .player = audience, let id = command.challengeId, Self.serverID(id), let code = command.displayCode, Self.validCode(code) else { return nil }
        case .confirm, .reject:
            keys = ["requestId", "kind", "challengeId", "expectedVersion", "displayCode", "reason"]
            guard case .merchant = audience, let id = command.challengeId, Self.serverID(id), let code = command.displayCode, (command.kind == .reject ? code.isEmpty : Self.validCode(code)),
                  let reason = command.reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.utf16.count <= 500 else { return nil }
        }
        guard Set(object.keys) == keys else { return nil }; write = true
    }
    static func serverID(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value }
    static func validCode(_ value: String) -> Bool { value.range(of: "^[A-F0-9]{32}$", options: .regularExpression) != nil }
}
@available(macOS 14.0, *) @MainActor public final class CityArrivalEvidenceTransport: HTTPTransport {
    private let approval: CityArrivalEvidenceApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext, CityArrivalAudience) -> CityArrivalEvidenceApproval?
    public init(approval: CityArrivalEvidenceApproval, underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?, selected: @escaping (RuntimeDependencyContext, CityArrivalAudience) -> CityArrivalEvidenceApproval?) { self.approval = approval; self.underlying = underlying; self.current = current; self.selected = selected }
    public func isCurrent() -> Bool { guard let live = current(), approval.matches(live), let selected = selected(live, approval.audience) else { return false }; return selected.revision == approval.revision && selected.audience == approval.audience && selected.matches(live) }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation(); guard isCurrent(), !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Authorization") == approval.context.session.token,
              let route = CityArrivalEvidenceRoute(request: request, baseURL: approval.context.baseURL, audience: approval.audience), !route.write || approval.allowsWrite else { throw CityArrivalEvidenceError.disabled }
        let result = try await underlying.send(request); try Task.checkCancellation(); guard isCurrent() else { throw CityArrivalEvidenceError.stale }; return result
    }
}
@available(macOS 14.0, *) @MainActor public final class CityArrivalEvidenceService {
    public let approval: CityArrivalEvidenceApproval
    public let transport: CityArrivalEvidenceTransport
    public let board: CityReadBoard?
    public init(approval: CityArrivalEvidenceApproval, transport: CityArrivalEvidenceTransport, board: CityReadBoard?) { self.approval = approval; self.transport = transport; self.board = board }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let errorCode: String?; let data: T? }
    private struct AuthorizationHeader: Decodable { let code: Int }
    private struct ReceiptData: Decodable { let requestId, requestStatus: String; let challenge: CityArrivalChallenge?; let evidence: CityArrivalProof?; let displayCode: String? }
    private struct EvidenceData: Decodable { let contract, currentTaskEligibility, effectsStatus: String; let evidence: CityArrivalProof }
    public func player() async throws -> CityArrivalPlayerSnapshot {
        guard case .player(let region) = approval.audience, let board else { throw CityArrivalEvidenceError.disabled }
        let value: CityArrivalPlayerSnapshot = try await read("state", query: [.init(name: "regionId", value: region)])
        guard value.contract == "CITY_ARRIVAL_EVIDENCE_V1", value.points.count <= 200 else { throw CityArrivalEvidenceError.malformed }
        if value.status == "JOIN_REQUIRED" { guard !value.writeApproved, value.binding == nil, value.points.isEmpty else { throw CityArrivalEvidenceError.malformed }; return value }
        guard ["NOT_CONFIGURED", "TEAM_NOT_READY", "READY"].contains(value.status), value.scope == "CITY", let binding = value.binding, binding.valid,
              binding.regionId == region, binding.boardId == board.boardId, binding.seasonId == board.seasonId, let team = value.teamId, CityArrivalEvidenceRoute.serverID(team),
              let version = value.teamVersion, version > 0, version <= 9_007_199_254_740_991, value.effectsStatus == "NOT_EXECUTED", value.taskEligibility == "NOT_EVALUATED",
              value.status == "READY" || !value.writeApproved, Set(value.points.map { $0.id }).count == value.points.count else { throw CityArrivalEvidenceError.malformed }
        if value.status == "READY" { guard let session = value.sessionId, CityArrivalEvidenceRoute.serverID(session) else { throw CityArrivalEvidenceError.malformed } }
        for point in value.points {
            guard point.rules.valid, point.rules.pointId == point.pointId, String(point.placeId) == point.rules.placeRef.id, point.merchantId > 0,
                  point.attemptVersion >= 0, point.attemptVersion <= Int64(point.rules.maxChallenges), !point.canIssue || value.writeApproved && value.status == "READY" && point.availability == "AVAILABLE" && point.evidence == nil else { throw CityArrivalEvidenceError.malformed }
            if let challenge = point.challenge { try validate(challenge); guard challenge.memberId == Int64(approval.context.session.accountID), challenge.regionId == region, challenge.boardId == binding.boardId, challenge.seasonId == binding.seasonId, challenge.roundId == binding.rules.roundId, challenge.rulesReleaseId == binding.rulesReleaseId, challenge.pointId == point.id, challenge.teamId == team, challenge.sessionId == value.sessionId, challenge.releaseId == binding.releaseId, challenge.contentHash == binding.contentHash, challenge.merchantId == point.merchantId, challenge.placeId == point.placeId, Int64(challenge.ordinal) == point.attemptVersion else { throw CityArrivalEvidenceError.malformed } }
            if let evidence = point.evidence { try validate(evidence); guard evidence.memberId == Int64(approval.context.session.accountID), evidence.regionId == region, evidence.boardId == binding.boardId, evidence.seasonId == binding.seasonId, evidence.roundId == binding.rules.roundId, evidence.rulesReleaseId == binding.rulesReleaseId, evidence.pointId == point.id, evidence.teamId == team, evidence.sessionId == value.sessionId, evidence.releaseId == binding.releaseId, evidence.contentHash == binding.contentHash, evidence.merchantId == point.merchantId, evidence.placeId == point.placeId else { throw CityArrivalEvidenceError.malformed } }
        }
        return value
    }
    public func merchant() async throws -> CityArrivalMerchantSnapshot {
        guard case .merchant(let merchant) = approval.audience else { throw CityArrivalEvidenceError.disabled }
        let value: CityArrivalMerchantSnapshot = try await read("merchant")
        guard value.contract == "CITY_ARRIVAL_EVIDENCE_V1", value.merchantId == merchant, value.ownerMemberId > 0, ["MERCHANT_OWNER", "MERCHANT_MANAGER", "MERCHANT_CHECKIN"].contains(value.role), value.pending.count <= 100,
              Set(value.pending.map { $0.id }).count == value.pending.count else { throw CityArrivalEvidenceError.malformed }
        for row in value.pending { try validate(row); guard row.merchantId == merchant, row.state == "SUBMITTED", row.memberId != Int64(approval.context.session.accountID) else { throw CityArrivalEvidenceError.malformed } }; return value
    }
    public func submit(_ command: CityArrivalCommand) async throws { _ = try await execute("command", body: JSONEncoder().encode(command)) }
    public func receipt(_ id: String) async throws -> CityArrivalReceipt {
        guard CityReadRoute.validID(id) else { throw CityArrivalEvidenceError.malformed }
        let (data, status) = try await execute("request/" + id); let envelope = try JSONDecoder().decode(Envelope<ReceiptData>.self, from: data)
        guard status != 403 else { throw CityArrivalEvidenceError.server(403, envelope.errorCode ?? "FORBIDDEN") }
        guard let value = envelope.data, value.requestId == id, value.requestStatus == "COMPLETE", envelope.code == status else { throw CityArrivalEvidenceError.unknown }
        if status == 200 {
            guard value.challenge != nil || value.evidence != nil else { throw CityArrivalEvidenceError.malformed }
            if let challenge = value.challenge { try validate(challenge); try validateAudience(member: challenge.memberId, merchant: challenge.merchantId, region: challenge.regionId) }
            if let evidence = value.evidence { try validate(evidence); try validateAudience(member: evidence.memberId, merchant: evidence.merchantId, region: evidence.regionId) }
            if let code = value.displayCode { guard case .player = approval.audience, CityArrivalEvidenceRoute.validCode(code), value.challenge?.memberId == Int64(approval.context.session.accountID), value.challenge?.requestId == id else { throw CityArrivalEvidenceError.malformed } }
        }
        return .init(requestId: id, succeeded: status == 200, challenge: value.challenge, evidence: value.evidence, displayCode: value.displayCode)
    }
    public func code(for current: CityArrivalChallenge) async throws -> String {
        let value = try await receipt(current.requestId)
        guard value.succeeded, let original = value.challenge, original.id == current.id, original.teamId == current.teamId, original.sessionId == current.sessionId,
              original.memberId == current.memberId, original.releaseId == current.releaseId, original.contentHash == current.contentHash, let code = value.displayCode else { throw CityArrivalEvidenceError.malformed }; return code
    }
    public func evidence(_ id: String) async throws -> CityArrivalProof {
        guard CityArrivalEvidenceRoute.serverID(id) else { throw CityArrivalEvidenceError.malformed }
        let value: EvidenceData = try await read("evidence/" + id)
        guard value.contract == "CITY_ARRIVAL_EVIDENCE_V1", value.currentTaskEligibility == "NOT_EVALUATED", value.effectsStatus == "NOT_EXECUTED", value.evidence.id == id else { throw CityArrivalEvidenceError.malformed }
        try validate(value.evidence)
        switch approval.audience { case .player(let region): guard value.evidence.memberId == Int64(approval.context.session.accountID), value.evidence.regionId == region else { throw CityArrivalEvidenceError.malformed }
        case .merchant(let merchant): guard value.evidence.merchantId == merchant else { throw CityArrivalEvidenceError.malformed } }
        return value.evidence
    }
    private func validateAudience(member: Int64, merchant: Int64, region: String) throws {
        switch approval.audience {
        case .player(let expected): guard member == Int64(approval.context.session.accountID), region == expected else { throw CityArrivalEvidenceError.malformed }
        case .merchant(let expected): guard merchant == expected else { throw CityArrivalEvidenceError.malformed }
        }
    }
    private func validate(_ value: CityArrivalChallenge) throws {
        guard CityArrivalEvidenceRoute.serverID(value.id), CityReadRoute.validID(value.requestId), CityReadRoute.validID(value.pointId), CityArrivalEvidenceRoute.serverID(value.teamId), CityArrivalEvidenceRoute.serverID(value.sessionId),
              [value.memberId, value.merchantId, value.placeId, value.releaseId, value.version].allSatisfy({ $0 > 0 && $0 <= 9_007_199_254_740_991 }), (1...1_000_000).contains(value.ordinal),
              [value.regionId, value.boardId, value.seasonId, value.roundId, value.rulesReleaseId].allSatisfy(CityReadRoute.validID), value.policyHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil, value.contentHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil, ["ISSUED", "SUBMITTED", "CONFIRMED", "REJECTED", "EXPIRED"].contains(value.state), date(value.expiresAt) != nil else { throw CityArrivalEvidenceError.malformed }
    }
    private func validate(_ value: CityArrivalProof) throws {
        guard CityArrivalEvidenceRoute.serverID(value.id), CityArrivalEvidenceRoute.serverID(value.challengeId), CityReadRoute.validID(value.requestId), CityArrivalEvidenceRoute.serverID(value.teamId), CityArrivalEvidenceRoute.serverID(value.sessionId), CityReadRoute.validID(value.pointId),
              [value.memberId, value.merchantId, value.placeId, value.releaseId, value.reviewerMemberId].allSatisfy({ $0 > 0 && $0 <= 9_007_199_254_740_991 }), value.memberId != value.reviewerMemberId,
              [value.regionId, value.boardId, value.seasonId, value.roundId, value.rulesReleaseId].allSatisfy(CityReadRoute.validID), value.policyHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil, value.contentHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil, value.assurance == "MERCHANT_ATTESTED", !value.reason.isEmpty, value.reason.utf16.count <= 500,
              ["MERCHANT_OWNER", "MERCHANT_MANAGER", "MERCHANT_CHECKIN"].contains(value.reviewerRole), let start = date(value.createdAt), let end = date(value.expiresAt), end > start,
              ["WITHIN_WINDOW", "EXPIRED"].contains(value.timeStatus), value.currentTaskEligibility == "NOT_EVALUATED", value.effectsStatus == "NOT_EXECUTED" else { throw CityArrivalEvidenceError.malformed }
    }
    private func date(_ value: String) -> Date? { let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
    private func read<T: Decodable>(_ path: String, query: [URLQueryItem]? = nil) async throws -> T {
        let (data, status) = try await execute(path, query: query); let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard status == 200, envelope.code == 200, let value = envelope.data else { throw CityArrivalEvidenceError.server(status, envelope.errorCode ?? "UNAVAILABLE") }; return value
    }
    private func execute(_ path: String, query: [URLQueryItem]? = nil, body: Data? = nil) async throws -> (Data, Int) {
        var parts = URLComponents(url: approval.context.baseURL.appendingPathComponent("api/city-game/arrival-evidence/" + path), resolvingAgainstBaseURL: false)!; parts.queryItems = query
        var request = URLRequest(url: parts.url!); request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body; request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let result = try await transport.send(request)
        if result.1 == 401 { throw APIError.unauthorized }
        if result.1 == 403 { throw CityArrivalEvidenceError.server(403, "FORBIDDEN") }
        guard result.0.count <= 524288 else { throw CityArrivalEvidenceError.malformed }
        // An authorization denial wins over malformed optional payload fields.
        if (200..<300).contains(result.1),
           let header = try? JSONDecoder().decode(AuthorizationHeader.self, from: result.0) {
            if header.code == 401 { throw APIError.unauthorized }
            if header.code == 403 { throw CityArrivalEvidenceError.server(403, "FORBIDDEN") }
        }
        return result
    }
}
