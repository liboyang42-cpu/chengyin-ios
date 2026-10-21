import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read-only CITY fairness. 401, 403, 422, 503, and an empty body stay failures.
/// A null matureCount and denominator is no mature sample. None of those become a ratio.
public enum CityFairnessFailure: String, Equatable, Error, Sendable {
    case unauthorized, forbidden, notComputable, unavailable, malformed, unknown
}

public struct CityFairnessScope: Equatable, Sendable {
    public let boardID, regionID, seasonID, rulesVersion: String
    public init(boardID: String, regionID: String, seasonID: String, rulesVersion: String) throws {
        guard Self.token(boardID), Self.token(regionID), Self.token(seasonID), Self.token(rulesVersion) else { throw APIError.invalidRequest }
        self.boardID = boardID; self.regionID = regionID; self.seasonID = seasonID; self.rulesVersion = rulesVersion
    }
    static func token(_ value: String) -> Bool { value.range(of: "\\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\z", options: .regularExpression) != nil }
}

public struct CityFairnessMember: Equatable, Identifiable, Sendable {
    public let outingId: String
    public let actorId: Int64
    public let maturity, reason: String
    public let t0: Int64?
    public let newbieQueue, secondOutingId: String?
    public var id: String { "\(actorId):\(outingId)" }
}

public struct CityFairnessPage: Equatable, Sendable {
    public let matureCount, denominator: Int
    public let asOf: Int64
    public let metricVersion, formulaId: String
    public let factRevision: Int64?
    public let members: [CityFairnessMember]
    public let nextCursor: String?
    public var ratioText: String { "\(matureCount)/\(denominator)" }
}

public struct CityFairnessGap: Equatable, Sendable {
    public let asOf: Int64
    public let metricVersion: String?
    public let formulaId: String
    public let factRevision: Int64?
}

/// Detail fields that already exist on an outing class. The outing route itself is not in B4-1 yet.
public struct CityFairnessEvidence: Equatable, Sendable {
    public let outingId: String
    public let actorId: Int64
    public let maturity, reason: String
    public let t0: Int64?
    public let newbieQueue, secondOutingId: String?
}

public enum CityFairnessScreen: Equatable, Sendable {
    case blocked, loading
    case notComputable([String])
    case noMatureSample(CityFairnessGap)
    case unknown(String?)
    case mature(CityFairnessPage)
    case failed(CityFairnessFailure)
}

/// Revocable read lease. It is not issued by login, and it does not authorize a write.
@available(macOS 14.0, *)
@MainActor @Observable public final class CityFairnessReadApproval {
    public let context: RuntimeDependencyContext
    public let scope: CityFairnessScope
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    public var boardID: String { scope.boardID }
    public var regionID: String { scope.regionID }
    public var seasonID: String { scope.seasonID }
    public var rulesVersion: String { scope.rulesVersion }
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, scope: CityFairnessScope, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role), context.session.accountID > 0,
              AuthRequestBuilder.isValidToken(context.session.token),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.context = context; self.scope = scope; self.expiresAt = expiresAt
        expiryTask = Task { @MainActor [weak self] in
            let remaining = max(0, min(expiresAt.timeIntervalSinceNow, 86_400))
            do { if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }; try Task.checkCancellation() } catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    public func revoke() { isRevoked = true; expiryTask?.cancel(); expiryTask = nil }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(context, current)
    }
}

public struct CityFairnessRoute: Equatable {
    public enum Kind: String { case report = "fairness/report", outing = "fairness/outing" }
    public let kind: Kind
    public let scope: CityFairnessScope
    public let queryID: String?
    public let asOf: Int64?
    public let cursor: String?
    public let outingID: String?
    public var boardID: String { scope.boardID }
    public var regionID: String { scope.regionID }
    public var seasonID: String { scope.seasonID }
    public var rulesVersion: String { scope.rulesVersion }
    public init(report scope: CityFairnessScope, queryID: String, asOf: Int64, cursor: String? = nil) throws {
        guard Self.validQuery(queryID), Self.validStamp(asOf), cursor.map(Self.validCursor) != false else { throw APIError.invalidRequest }
        kind = .report; self.scope = scope; self.queryID = queryID; self.asOf = asOf; self.cursor = cursor; outingID = nil
    }
    public init(outing scope: CityFairnessScope, outingID: String) throws {
        guard Self.validID(outingID) else { throw APIError.invalidRequest }
        kind = .outing; self.scope = scope; queryID = nil; asOf = nil; cursor = nil; self.outingID = outingID
    }
    public func request(baseURL: URL, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        let configuration = try APIConfiguration(baseURL: baseURL)
        let parts = kind == .report ? ["api", "city-game", "fairness", "report"] : ["api", "city-game", "fairness", "outing"]
        let url = parts.reduce(configuration.baseURL) { $0.appendingPathComponent($1) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        var fields = ["boardId": scope.boardID, "regionId": scope.regionID, "seasonId": scope.seasonID, "rulesVersion": scope.rulesVersion]
        if let queryID { fields["queryId"] = queryID }
        if let asOf { fields["asOf"] = String(asOf) }
        if let cursor { fields["cursor"] = cursor }
        if let outingID { fields["outingId"] = outingID }
        components.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
        guard let requestURL = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json", let url = request.url, url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems,
              items.count == Set(items.map(\.name)).count else { return nil }
        var values: [String: String] = [:]
        for item in items { guard let value = item.value else { return nil }; values[item.name] = value }
        guard values["accountId"] == nil, let board = values["boardId"], let region = values["regionId"],
              let season = values["seasonId"], let rules = values["rulesVersion"],
              let scope = try? CityFairnessScope(boardID: board, regionID: region, seasonID: season, rulesVersion: rules) else { return nil }
        let configuration = try? APIConfiguration(baseURL: baseURL)
        let root = configuration?.baseURL ?? baseURL
        let report = ["api", "city-game", "fairness", "report"].reduce(root) { $0.appendingPathComponent($1) }.path
        let outing = ["api", "city-game", "fairness", "outing"].reduce(root) { $0.appendingPathComponent($1) }.path
        if url.path == report {
            let keys = Set(values.keys)
            let allowed: Set<String> = ["asOf", "boardId", "queryId", "regionId", "rulesVersion", "seasonId"]
            guard keys == allowed || keys == allowed.union(["cursor"]),
                  let query = values["queryId"], Self.validQuery(query),
                  let asOf = values["asOf"].flatMap(Int64.init), Self.validStamp(asOf),
                  values["cursor"].map(Self.validCursor) != false else { return nil }
            kind = .report; self.scope = scope; queryID = query; self.asOf = asOf; cursor = values["cursor"]; outingID = nil
        } else if url.path == outing {
            guard Set(values.keys) == ["boardId", "outingId", "regionId", "rulesVersion", "seasonId"], Self.validID(values["outingId"] ?? "") else { return nil }
            kind = .outing; self.scope = scope; queryID = nil; asOf = nil; cursor = nil; outingID = values["outingId"]
        } else { return nil }
        guard let canonical = try? self.request(baseURL: baseURL, token: "synthetic-token"),
              canonical.url?.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) == true else { return nil }
    }
    static func validID(_ value: String) -> Bool { value.range(of: "\\A[A-Za-z0-9][A-Za-z0-9_-]{0,95}\\z", options: .regularExpression) != nil }
    static func validQuery(_ value: String) -> Bool { value.range(of: "\\A[A-Za-z0-9._-]{1,64}\\z", options: .regularExpression) != nil }
    static func validCursor(_ value: String) -> Bool { value.range(of: "\\A[0-9]{1,9}\\z", options: .regularExpression) != nil }
    static func validStamp(_ value: Int64) -> Bool { (0...253_402_300_799_000).contains(value) }
    static func validText(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= limit && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

public enum CityFairnessWire {
    public static let formulaId = "city-fairness-cohort-v1"
    public static func page(data: Data, status: Int, scope: CityFairnessScope) throws -> CityFairnessScreen {
        if status == 401 { throw CityFairnessFailure.unauthorized }
        if status == 403 { throw CityFairnessFailure.forbidden }
        if status == 422 { return .notComputable(missing(data)) }
        if status == 503 { throw CityFairnessFailure.unavailable }
        if status == 400 || status == 409 { throw CityFairnessFailure.malformed }
        guard (200..<300).contains(status), !data.isEmpty else { throw CityFairnessFailure.malformed }
        let envelope = try decoded(data)
        if envelope.code == 401 { throw CityFairnessFailure.unauthorized }
        if envelope.code == 403 { throw CityFairnessFailure.forbidden }
        if envelope.code == 422 { return .notComputable(clean(envelope.data?.missing)) }
        if envelope.code == 503 { throw CityFairnessFailure.unavailable }
        guard envelope.code == 200, let payload = envelope.data else { throw CityFairnessFailure.malformed }
        return try screen(payload, scope: scope)
    }
    public static func evidence(data: Data, status: Int, outingID: String) throws -> CityFairnessEvidence {
        if status == 401 { throw CityFairnessFailure.unauthorized }
        if status == 403 { throw CityFairnessFailure.forbidden }
        if status == 422 { throw CityFairnessFailure.notComputable }
        if status == 503 { throw CityFairnessFailure.unavailable }
        guard (200..<300).contains(status), !data.isEmpty else { throw CityFairnessFailure.malformed }
        let envelope = try decoded(data)
        if envelope.code == 401 { throw CityFairnessFailure.unauthorized }
        if envelope.code == 403 { throw CityFairnessFailure.forbidden }
        if envelope.code == 422 { throw CityFairnessFailure.notComputable }
        if envelope.code == 503 { throw CityFairnessFailure.unavailable }
        guard envelope.code == 200, let payload = envelope.data, let row = detail(payload, outingID: outingID),
              let member = member(row) else { throw CityFairnessFailure.malformed }
        return CityFairnessEvidence(outingId: member.outingId, actorId: member.actorId, maturity: member.maturity, reason: member.reason, t0: member.t0, newbieQueue: member.newbieQueue, secondOutingId: member.secondOutingId)
    }

    private static func screen(_ payload: Payload, scope: CityFairnessScope) throws -> CityFairnessScreen {
        guard payload.formulaId == formulaId, payload.boardId == scope.boardID, payload.regionId == scope.regionID,
              payload.seasonId == scope.seasonID, payload.rulesVersion == scope.rulesVersion else { throw CityFairnessFailure.malformed }
        if payload.status == "NOT_COMPUTABLE" { return .notComputable(clean(payload.missing)) }
        guard payload.status == "COMPUTABLE" else { throw CityFairnessFailure.unknown }
        if payload.status == "COMPUTABLE", payload.matureCount == nil, payload.denominator == nil {
            guard payload.maturity == "NO_MATURE_SAMPLE", let asOf = stamp(payload.asOf) else { throw CityFairnessFailure.malformed }
            return .noMatureSample(CityFairnessGap(asOf: asOf, metricVersion: try version(payload.metricVersion), formulaId: formulaId, factRevision: try revision(payload.factRevision)))
        }
        guard payload.maturity == "COUNTED", let matureCount = payload.matureCount, let denominator = payload.denominator,
              denominator > 0, matureCount >= 0, matureCount <= denominator, matureCount <= 1_000_000, denominator <= 1_000_000,
              let asOf = stamp(payload.asOf), let metricVersion = try version(payload.metricVersion),
              let rows = payload.outingClasses, rows.count <= 10_000 else { throw CityFairnessFailure.malformed }
        let factRevision = try revision(payload.factRevision)
        let members = try rows.map { row -> CityFairnessMember in
            guard let member = member(row) else { throw CityFairnessFailure.malformed }
            return member
        }
        guard Set(members.map(\.actorId)).count == members.count else { throw CityFairnessFailure.malformed }
        let cursor = try cursor(payload.nextCursor)
        return .mature(CityFairnessPage(matureCount: matureCount, denominator: denominator, asOf: asOf, metricVersion: metricVersion, formulaId: formulaId, factRevision: factRevision, members: members, nextCursor: cursor))
    }
    private static func detail(_ payload: Payload, outingID: String) -> MemberRow? {
        if let rows = payload.outingClasses, let match = rows.first(where: { $0.outingId == outingID }) { return match }
        guard payload.outingId == outingID, let actorId = payload.actorId, let maturity = payload.maturity, let reason = payload.reason else { return nil }
        return MemberRow(outingId: outingID, actorId: actorId, maturity: maturity, reason: reason, t0: payload.t0, newbieQueue: payload.newbieQueue, secondOutingId: payload.secondOutingId)
    }
    private static func member(_ row: MemberRow) -> CityFairnessMember? {
        guard CityFairnessRoute.validID(row.outingId), row.actorId > 0, CityFairnessRoute.validText(row.maturity, limit: 64),
              CityFairnessRoute.validText(row.reason, limit: 64), stamp(row.t0) != nil || row.t0 == nil,
              row.newbieQueue.map({ CityFairnessRoute.validText($0, limit: 64) }) != false,
              row.secondOutingId.map(CityFairnessRoute.validID) != false else { return nil }
        return CityFairnessMember(outingId: row.outingId, actorId: row.actorId, maturity: row.maturity, reason: row.reason, t0: row.t0, newbieQueue: row.newbieQueue, secondOutingId: row.secondOutingId)
    }
    private static func missing(_ data: Data) -> [String] {
        guard let envelope = try? decoded(data) else { return [] }
        return clean(envelope.data?.missing)
    }
    private static func clean(_ values: [String]?) -> [String] {
        guard let values, values.count <= 32, values.allSatisfy({ CityFairnessRoute.validText($0, limit: 160) }) else { return [] }
        return values
    }
    private static func version(_ value: String?) throws -> String? {
        if value == nil { return nil }
        guard let value, CityFairnessRoute.validText(value, limit: 64) else { throw CityFairnessFailure.malformed }
        return value
    }
    private static func stamp(_ value: Int64?) -> Int64? { value.flatMap { CityFairnessRoute.validStamp($0) ? $0 : nil } }
    private static func revision(_ value: Int64?) throws -> Int64? {
        if value == nil { return nil }
        guard let value, value >= 0 else { throw CityFairnessFailure.malformed }
        return value
    }
    private static func cursor(_ value: String?) throws -> String? {
        if value == nil { return nil }
        guard let value, CityFairnessRoute.validCursor(value) else { throw CityFairnessFailure.malformed }
        return value
    }
    private static func decoded(_ data: Data) throws -> Envelope {
        do { return try JSONDecoder().decode(Envelope.self, from: data) } catch { throw CityFairnessFailure.malformed }
    }

    private struct Envelope: Decodable { let code: Int; let data: Payload? }
    private struct MemberRow: Decodable {
        let outingId: String
        let actorId: Int64
        let maturity, reason: String
        let t0: Int64?
        let newbieQueue, secondOutingId: String?
    }
    private struct Payload: Decodable {
        let status, maturity, formulaId: String?
        let boardId, regionId, seasonId, rulesVersion: String?
        let matureCount, denominator: Int?
        let asOf, factRevision, actorId, t0: Int64?
        let metricVersion, nextCursor, outingId, reason, newbieQueue, secondOutingId: String?
        let missing: [String]?
        let outingClasses: [MemberRow]?
    }
}

@available(macOS 14.0, *)
@MainActor @Observable public final class CityFairnessReader {
    public private(set) var screen: CityFairnessScreen = .blocked
    public private(set) var refreshing = false
    public private(set) var evidence: CityFairnessEvidence?
    public private(set) var evidenceFailure: CityFairnessFailure?
    public private(set) var refreshFailure: CityFairnessFailure?
    private let approval: CityFairnessReadApproval?
    private let transport: any HTTPTransport
    private let isCurrent: () -> Bool
    private let onUnauthorized: () -> Void
    private let queryID = UUID().uuidString
    private var pinnedAsOf: Int64?
    private var generation = UUID()
    private var evidenceGeneration = UUID()
    private var page: CityFairnessPage?
    @ObservationIgnored private var task: Task<Void, Never>?
    public var isConfigured: Bool {
        guard let approval else { return false }
        return approval.matches(approval.context) && isCurrent()
    }
    public init(approval: CityFairnessReadApproval?, transport: any HTTPTransport, isCurrent: @escaping () -> Bool, onUnauthorized: @escaping () -> Void = {}) {
        self.approval = approval; self.transport = transport; self.isCurrent = isCurrent; self.onUnauthorized = onUnauthorized
    }
    deinit { task?.cancel() }
    public func restoreSameQuery() async { await reload(cursor: nil, preserve: true) }
    public func refresh() async { await reload(cursor: nil, preserve: true) }
    public func nextPage() async {
        guard let page, let cursor = page.nextCursor else { return }
        await reload(cursor: cursor, preserve: true)
    }
    public func loadEvidence(_ outingID: String) async {
        guard CityFairnessRoute.validID(outingID) else { evidence = nil; evidenceFailure = .malformed; return }
        let stamp = UUID(); evidenceGeneration = stamp
        evidence = nil; evidenceFailure = nil
        guard let approval, approval.matches(approval.context), isCurrent() else { evidenceFailure = .malformed; return }
        do {
            let route = try CityFairnessRoute(outing: approval.scope, outingID: outingID)
            let request = try route.request(baseURL: approval.context.baseURL, token: approval.context.session.token)
            let (data, status) = try await transport.send(request)
            guard evidenceGeneration == stamp, approval.matches(approval.context), isCurrent() else { return }
            evidence = try CityFairnessWire.evidence(data: data, status: status, outingID: outingID)
        } catch {
            guard evidenceGeneration == stamp else { return }
            evidenceFailure = Self.failure(error)
            if evidenceFailure == .unauthorized, isCurrent() { onUnauthorized() }
        }
    }
    public func clearEvidence() { evidenceGeneration = UUID(); evidence = nil; evidenceFailure = nil }

    private func reload(cursor: String?, preserve: Bool) async {
        guard !Task.isCancelled else { return }
        let stamp = UUID(); generation = stamp; task?.cancel()
        guard let approval, approval.matches(approval.context), isCurrent() else {
            page = nil; screen = .blocked; refreshing = false; refreshFailure = nil; return
        }
        refreshFailure = nil
        if page == nil || !preserve { screen = .loading }
        refreshing = page != nil
        let job = Task { @MainActor in await self.fetch(stamp: stamp, cursor: cursor) }
        task = job
        await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
        if generation == stamp { task = nil }
    }
    private func fetch(stamp: UUID, cursor: String?) async {
        guard let approval else { return }
        do {
            let route = try CityFairnessRoute(report: approval.scope, queryID: queryID, asOf: pinnedStamp(), cursor: cursor)
            let request = try route.request(baseURL: approval.context.baseURL, token: approval.context.session.token)
            let (data, status) = try await transport.send(request)
            guard generation == stamp, approval.matches(approval.context), isCurrent(), !Task.isCancelled else { return }
            let decoded = try CityFairnessWire.page(data: data, status: status, scope: approval.scope)
            if let cursor {
                guard case .mature(let incoming) = decoded, let current = page,
                      incoming.matureCount == current.matureCount, incoming.denominator == current.denominator,
                      incoming.metricVersion == current.metricVersion, incoming.formulaId == current.formulaId else { throw CityFairnessFailure.malformed }
                var seen = Set(current.members.map(\.id))
                let added = incoming.members.filter { seen.insert($0.id).inserted }
                let merged = CityFairnessPage(matureCount: current.matureCount, denominator: current.denominator, asOf: incoming.asOf, metricVersion: current.metricVersion, formulaId: current.formulaId, factRevision: current.factRevision, members: current.members + added, nextCursor: incoming.nextCursor)
                page = merged
                screen = .mature(merged)
            } else {
                if case .mature(let incoming) = decoded { page = incoming } else { page = nil }
                screen = decoded
            }
            refreshing = false
        } catch {
            guard generation == stamp else { return }
            let failure = Self.failure(error)
            if failure == .unauthorized || failure == .notComputable {
                page = nil; refreshFailure = nil; screen = .failed(failure)
                if failure == .unauthorized, isCurrent(), !Task.isCancelled { onUnauthorized() }
            } else if page == nil { screen = .failed(failure) }
            else { refreshFailure = failure }
            refreshing = false
        }
    }
    /// ponytail: first client clock is reused as asOf so refresh reads that snapshot back. A new cutoff needs a new reader.
    private func pinnedStamp() -> Int64 {
        if let pinnedAsOf { return pinnedAsOf }
        let now = Int64((Date().timeIntervalSince1970 * 1000).rounded())
        let pinned = CityFairnessRoute.validStamp(now) ? now : 0
        pinnedAsOf = pinned
        return pinned
    }
    private static func failure(_ error: Error) -> CityFairnessFailure {
        if let failure = error as? CityFairnessFailure { return failure }
        if let api = error as? APIError {
            if api == .unauthorized || api == .httpStatus(401) { return .unauthorized }
            if api == .httpStatus(403) { return .forbidden }
            if api == .httpStatus(422) { return .notComputable }
            if api == .httpStatus(503) { return .unavailable }
        }
        return .malformed
    }
}
