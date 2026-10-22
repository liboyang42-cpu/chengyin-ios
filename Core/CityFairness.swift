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
    public let queryID: String
    public let matureCount, denominator: Int
    public let asOf: Int64
    public let metricVersion, formulaId: String
    public let factRevision: Int64?
    public let members: [CityFairnessMember]
    public let nextCursor: String?
    public let showsRatio: Bool
    public let missing: [String]
    public let coverage: CityFairnessCoverageReport?
    public var ratioText: String { "\(matureCount)/\(denominator)" }
}

public enum CityFairnessOutingReason: Equatable, Sendable {
    case firstOuting, secondOuting, insideDelta, afterHorizon, beforeT0, notEffective, unknown
    public init(_ raw: String) {
        switch raw {
        case "first-outing": self = .firstOuting
        case "second-outing": self = .secondOuting
        case "inside-delta": self = .insideDelta
        case "after-horizon": self = .afterHorizon
        case "before-t0": self = .beforeT0
        case "not-effective": self = .notEffective
        default: self = .unknown
        }
    }
}

public struct CityFairnessOwnOuting: Equatable, Identifiable, Sendable {
    public let outingId: String
    public let t0: Int64?
    public let valid, inWindow: Bool
    public let reason: CityFairnessOutingReason
    public let maturity: String
    public let metricVersion: String?
    public let factRevision: Int64?
    public var id: String { outingId }
}

public struct CityFairnessOutingPage: Equatable, Sendable {
    public let queryID: String
    public let asOf: Int64
    public let metricVersion: String?
    public let factRevision: Int64?
    public let maturity: String
    public let t0: Int64?
    public let outings: [CityFairnessOwnOuting]
    public let nextCursor: String?
    public let missing: [String]
    public let coverage: CityFairnessCoverageReport?
    /// Cohort N/D stays on the report. This page never carries a ratio; immature members still keep their rows.
    public var showsRatio: Bool { maturity == "MATURE" }
}

public struct CityFairnessCoverageItem: Equatable, Identifiable, Sendable {
    public enum State: Equatable, Sendable { case unknown, missing, count(Int) }
    public let source: String
    public let state: State
    public var id: String { source }
}

/// Provisional until hengyin publishes docs/contracts/w20-fairness-samples. Absent coverage is unknown, not zero.
public struct CityFairnessCoverageReport: Equatable, Sendable, Decodable {
    public let items: [CityFairnessCoverageItem]
    public init(items: [CityFairnessCoverageItem]) { self.items = items }
    public init(from decoder: Decoder) throws {
        let items: [CityFairnessCoverageItem]
        if var list = try? decoder.unkeyedContainer() {
            var decoded: [CityFairnessCoverageItem] = []
            while !list.isAtEnd {
                if let name = try? list.decode(String.self) {
                    guard CityFairnessRoute.validText(name, limit: 160) else { throw CityFairnessFailure.malformed }
                    decoded.append(CityFairnessCoverageItem(source: name, state: .unknown))
                } else {
                    decoded.append(try list.decode(Row.self).item())
                }
            }
            items = decoded
        } else {
            let map = try decoder.container(keyedBy: DynamicKey.self)
            var decoded: [CityFairnessCoverageItem] = []
            for key in map.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
                guard CityFairnessRoute.validText(key.stringValue, limit: 160) else { throw CityFairnessFailure.malformed }
                if try map.decodeNil(forKey: key) {
                    decoded.append(CityFairnessCoverageItem(source: key.stringValue, state: .unknown))
                } else if let count = try? map.decode(Int.self, forKey: key) {
                    guard (0...1_000_000).contains(count) else { throw CityFairnessFailure.malformed }
                    decoded.append(CityFairnessCoverageItem(source: key.stringValue, state: .count(count)))
                } else if let text = try? map.decode(String.self, forKey: key) {
                    switch text {
                    case "UNKNOWN": decoded.append(CityFairnessCoverageItem(source: key.stringValue, state: .unknown))
                    case "MISSING": decoded.append(CityFairnessCoverageItem(source: key.stringValue, state: .missing))
                    default: throw CityFairnessFailure.malformed
                    }
                } else { throw CityFairnessFailure.malformed }
            }
            items = decoded
        }
        guard Set(items.map(\.source)).count == items.count else { throw CityFairnessFailure.malformed }
        self.items = items
    }
    private struct DynamicKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }
    private struct Row: Decodable {
        let source, name, state, status: String?
        let count: Int?
        func item() throws -> CityFairnessCoverageItem {
            guard let source = source ?? name, CityFairnessRoute.validText(source, limit: 160) else { throw CityFairnessFailure.malformed }
            let label = state ?? status
            if label == "UNKNOWN" || (label == nil && count == nil) { return CityFairnessCoverageItem(source: source, state: .unknown) }
            if label == "MISSING" { return CityFairnessCoverageItem(source: source, state: .missing) }
            if let count, label == nil || label == "PRESENT" {
                guard (0...1_000_000).contains(count) else { throw CityFairnessFailure.malformed }
                return CityFairnessCoverageItem(source: source, state: .count(count))
            }
            throw CityFairnessFailure.malformed
        }
    }
}

public enum CityFairnessReportRead: Equatable, Sendable {
    case screen(CityFairnessScreen)
    case discard
}

public enum CityFairnessOutingRead: Equatable, Sendable {
    case page(CityFairnessOutingPage)
    case discard
}

public struct CityFairnessGap: Equatable, Sendable {
    public let asOf: Int64
    public let metricVersion: String?
    public let formulaId: String
    public let factRevision: Int64?
    public let missing: [String]
    public let coverage: CityFairnessCoverageReport?
}

public enum CityFairnessScreen: Equatable, Sendable {
    case blocked, loading
    case notComputable([String], CityFairnessCoverageReport?)
    case noMatureSample(CityFairnessGap)
    case unknown(String?, CityFairnessCoverageReport?)
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
    public var boardID: String { scope.boardID }
    public var regionID: String { scope.regionID }
    public var seasonID: String { scope.seasonID }
    public var rulesVersion: String { scope.rulesVersion }
    public init(report scope: CityFairnessScope, queryID: String, asOf: Int64, cursor: String? = nil) throws {
        guard Self.validQuery(queryID), Self.validStamp(asOf), cursor.map(Self.validCursor) != false else { throw APIError.invalidRequest }
        kind = .report; self.scope = scope; self.queryID = queryID; self.asOf = asOf; self.cursor = cursor
    }
    public init(outing scope: CityFairnessScope, queryID: String, asOf: Int64, cursor: String? = nil) throws {
        guard Self.validQuery(queryID), Self.validStamp(asOf), cursor.map(Self.validCursor) != false else { throw APIError.invalidRequest }
        kind = .outing; self.scope = scope; self.queryID = queryID; self.asOf = asOf; self.cursor = cursor
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
        let keys = Set(values.keys)
        let allowed: Set<String> = ["asOf", "boardId", "queryId", "regionId", "rulesVersion", "seasonId"]
        guard values["outingId"] == nil, keys == allowed || keys == allowed.union(["cursor"]),
              let query = values["queryId"], Self.validQuery(query),
              let asOf = values["asOf"].flatMap(Int64.init), Self.validStamp(asOf),
              values["cursor"].map(Self.validCursor) != false else { return nil }
        queryID = query; self.asOf = asOf; cursor = values["cursor"]
        if url.path == report { kind = .report; self.scope = scope }
        else if url.path == outing { kind = .outing; self.scope = scope }
        else { return nil }
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
    /// HTTPTransport.send returns (Data, Int), so this response header is not readable there.
    public static let candidateHeader = "X-Chengyin-Candidate"
    public static let candidateValue = "city-fairness"
    public static func report(data: Data, status: Int, scope: CityFairnessScope, accountID: Int, queryID: String, asOf: Int64, cursor requestedCursor: String?) throws -> CityFairnessReportRead {
        switch try open(data, status: status) {
        case .notComputable(let missing): return .screen(.notComputable(missing, coverage(from: data)))
        case .envelope(let envelope):
            guard let payload = envelope.data else { throw CityFairnessFailure.malformed }
            guard owned(payload, accountID: accountID, queryID: queryID, asOf: asOf, scope: scope) else { return .discard }
            return .screen(try screen(payload, accountID: accountID, queryID: queryID, requestedCursor: requestedCursor))
        }
    }
    public static func ownOutings(data: Data, status: Int, scope: CityFairnessScope, accountID: Int, queryID: String, asOf: Int64, cursor requestedCursor: String?) throws -> CityFairnessOutingRead {
        switch try open(data, status: status) {
        case .notComputable: throw CityFairnessFailure.notComputable
        case .envelope(let envelope):
            guard let payload = envelope.data else { throw CityFairnessFailure.malformed }
            guard owned(payload, accountID: accountID, queryID: queryID, asOf: asOf, scope: scope) else { return .discard }
            return .page(try outingPage(payload, queryID: queryID, requestedCursor: requestedCursor))
        }
    }

    private static let unavailableTables: Set<String> = ["city_fairness_parameter", "city_fairness_event", "city_fairness_read"]
    private static func open(_ data: Data, status: Int) throws -> Opened {
        if status == 401 { if let code = errorCode(data), code != "UNAUTHORIZED" { throw CityFairnessFailure.malformed }; throw CityFairnessFailure.unauthorized }
        if status == 403 { if let code = errorCode(data), code != "scope-rejected" { throw CityFairnessFailure.malformed }; throw CityFairnessFailure.forbidden }
        if status == 422 { return .notComputable(missing(data)) }
        if status == 503 { guard let code = errorCode(data), unavailableTables.contains(code) else { throw CityFairnessFailure.malformed }; throw CityFairnessFailure.unavailable }
        if status == 400 { if let code = errorCode(data), !["queryId", "cursor", "asOf"].contains(code) { throw CityFairnessFailure.malformed }; throw CityFairnessFailure.malformed }
        if status == 409 { if let code = errorCode(data), code != "query-conflict" { throw CityFairnessFailure.malformed }; throw CityFairnessFailure.malformed }
        guard status == 200, !data.isEmpty else { throw CityFairnessFailure.malformed }
        let envelope = try decoded(data)
        guard envelope.code == status, envelope.candidate, envelope.msg == "操作成功" else { throw CityFairnessFailure.malformed }
        return .envelope(envelope)
    }
    private static func screen(_ payload: Payload, accountID: Int, queryID: String, requestedCursor: String?) throws -> CityFairnessScreen {
        guard try sameCursor(requestedCursor, payload.cursor) else { throw CityFairnessFailure.malformed }
        if payload.maturity == "UNKNOWN" || payload.status == "UNKNOWN" { return .unknown(nil, payload.coverage) }
        guard payload.formulaId == formulaId else { throw CityFairnessFailure.malformed }
        if payload.status == "NOT_COMPUTABLE" { return .notComputable(clean(payload.missing), payload.coverage) }
        guard payload.status == "COMPUTABLE" else { throw CityFairnessFailure.unknown }
        let gaps = clean(payload.missing)
        if payload.matureCount == nil, payload.denominator == nil {
            guard payload.maturity == "NO_MATURE_SAMPLE", let asOf = stamp(payload.asOf) else { throw CityFairnessFailure.malformed }
            return .noMatureSample(CityFairnessGap(asOf: asOf, metricVersion: try version(payload.metricVersion), formulaId: formulaId, factRevision: try revision(payload.factRevision), missing: gaps, coverage: payload.coverage))
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
        let own = Int64(accountID)
        let showsRatio = members.allSatisfy { $0.actorId == own }
        let visible = showsRatio ? members : members.filter { $0.actorId == own }
        return .mature(CityFairnessPage(queryID: queryID, matureCount: matureCount, denominator: denominator, asOf: asOf, metricVersion: metricVersion, formulaId: formulaId, factRevision: factRevision, members: visible, nextCursor: try cursor(payload.nextCursor), showsRatio: showsRatio, missing: gaps, coverage: payload.coverage))
    }
    private static func outingPage(_ payload: Payload, queryID: String, requestedCursor: String?) throws -> CityFairnessOutingPage {
        if payload.status == "NOT_COMPUTABLE" { throw CityFairnessFailure.notComputable }
        guard try sameCursor(requestedCursor, payload.cursor) else { throw CityFairnessFailure.malformed }
        guard payload.status == "COMPUTABLE", let asOf = stamp(payload.asOf), let maturity = payload.maturity, CityFairnessRoute.validText(maturity, limit: 64),
              let rows = payload.outings, rows.count <= 10_000, Set(rows.map(\.outingId)).count == rows.count else { throw CityFairnessFailure.malformed }
        if let formula = payload.formulaId, formula != formulaId { throw CityFairnessFailure.malformed }
        let factRevision = try revision(payload.factRevision)
        let metricVersion = try version(payload.metricVersion)
        let outings = try rows.map { row -> CityFairnessOwnOuting in
            guard CityFairnessRoute.validID(row.outingId), stamp(row.t0) != nil || row.t0 == nil,
                  CityFairnessRoute.validText(row.maturity, limit: 64),
                  row.metricVersion == payload.metricVersion, row.factRevision == payload.factRevision else { throw CityFairnessFailure.malformed }
            return CityFairnessOwnOuting(outingId: row.outingId, t0: row.t0, valid: row.valid, inWindow: row.inWindow, reason: CityFairnessOutingReason(row.reason), maturity: row.maturity, metricVersion: metricVersion, factRevision: factRevision)
        }
        return CityFairnessOutingPage(queryID: queryID, asOf: asOf, metricVersion: metricVersion, factRevision: factRevision, maturity: maturity, t0: stamp(payload.t0), outings: outings, nextCursor: try cursor(payload.nextCursor), missing: clean(payload.missing), coverage: payload.coverage)
    }
    private static func owned(_ payload: Payload, accountID: Int, queryID: String, asOf: Int64, scope: CityFairnessScope) -> Bool {
        payload.accountId == accountID && payload.queryId == queryID && payload.asOf == asOf
            && payload.boardId == scope.boardID && payload.regionId == scope.regionID
            && payload.seasonId == scope.seasonID && payload.rulesVersion == scope.rulesVersion
    }
    private static func member(_ row: MemberRow) -> CityFairnessMember? {
        guard CityFairnessRoute.validID(row.outingId), row.actorId > 0, CityFairnessRoute.validText(row.maturity, limit: 64),
              CityFairnessRoute.validText(row.reason, limit: 64), stamp(row.t0) != nil || row.t0 == nil,
              row.newbieQueue.map({ CityFairnessRoute.validText($0, limit: 64) }) != false,
              row.secondOutingId.map(CityFairnessRoute.validID) != false else { return nil }
        return CityFairnessMember(outingId: row.outingId, actorId: row.actorId, maturity: row.maturity, reason: row.reason, t0: row.t0, newbieQueue: row.newbieQueue, secondOutingId: row.secondOutingId)
    }
    private static func missing(_ data: Data) -> [String] { clean((try? decoded(data))?.data?.missing) }
    private static func coverage(from data: Data) -> CityFairnessCoverageReport? { (try? decoded(data))?.data?.coverage }
    private static func errorCode(_ data: Data) -> String? { (try? decoded(data))?.data?.errorCode }
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
    /// First page only: a nil request and a "0" echo are the same offset. Later cursors stay exact.
    private static func sameCursor(_ requested: String?, _ echoed: String?) throws -> Bool {
        let left = try cursor(requested)
        let right = try cursor(echoed)
        if left == right { return true }
        return (left == nil || left == "0") && (right == nil || right == "0")
    }
    private static func decoded(_ data: Data) throws -> Envelope {
        do { return try JSONDecoder().decode(Envelope.self, from: data) } catch { throw CityFairnessFailure.malformed }
    }

    private enum Opened { case envelope(Envelope), notComputable([String]) }
    private struct Envelope: Decodable { let code: Int; let msg: String; let data: Payload?; let candidate: Bool }
    private struct MemberRow: Decodable {
        let outingId: String
        let actorId: Int64
        let maturity, reason: String
        let t0: Int64?
        let newbieQueue, secondOutingId: String?
    }
    private struct OwnRow: Decodable {
        let outingId: String
        let t0: Int64?
        let valid, inWindow: Bool
        let reason, maturity: String
        let metricVersion: String?
        let factRevision: Int64?
    }
    private struct Payload: Decodable {
        let accountId: Int?
        let queryId, status, maturity, formulaId, metricVersion, nextCursor, errorCode: String?
        let boardId, regionId, seasonId, rulesVersion: String?
        let matureCount, denominator: Int?
        let cursor: String?
        let asOf, factRevision, t0: Int64?
        let missing: [String]?
        let outingClasses: [MemberRow]?
        let outings: [OwnRow]?
        let readBack: Bool?
        let coverage: CityFairnessCoverageReport?
    }
}

@available(macOS 14.0, *)
@MainActor @Observable public final class CityFairnessReader {
    public private(set) var screen: CityFairnessScreen = .blocked
    public private(set) var refreshing = false
    public private(set) var outingPage: CityFairnessOutingPage?
    public private(set) var outingFailure: CityFairnessFailure?
    public private(set) var outingBlocked = false
    public private(set) var outingRefreshing = false
    public private(set) var refreshFailure: CityFairnessFailure?
    private let approval: CityFairnessReadApproval?
    private let transport: any HTTPTransport
    private let isCurrent: () -> Bool
    private let onUnauthorized: () -> Void
    /// ponytail: queryId and asOf live on this reader. Restart restore is unsupported.
    public static let restartRestoreSupported = false
    private let queryID = UUID().uuidString
    private var pinnedAsOf: Int64?
    private var foreground = true
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
    public func setForeground(_ active: Bool) {
        guard foreground != active else { return }
        foreground = active
        if !active {
            generation = UUID(); evidenceGeneration = UUID(); refreshing = false; outingRefreshing = false
        }
    }
    public func restoreSameQuery() async { await reload(cursor: nil, preserve: true) }
    public func refresh() async { await reload(cursor: nil, preserve: true) }
    public func nextPage() async {
        guard let page, let cursor = page.nextCursor else { return }
        await reload(cursor: cursor, preserve: true)
    }
    public func loadOutings() async { await reloadOutings(cursor: nil) }
    public func nextOutings() async {
        guard let outingPage, let cursor = outingPage.nextCursor else { return }
        await reloadOutings(cursor: cursor)
    }
    public func clearOutings() { evidenceGeneration = UUID(); outingPage = nil; outingFailure = nil; outingBlocked = false; outingRefreshing = false }

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
            let asOf = pinnedStamp()
            let route = try CityFairnessRoute(report: approval.scope, queryID: queryID, asOf: asOf, cursor: cursor)
            let request = try route.request(baseURL: approval.context.baseURL, token: approval.context.session.token)
            let (data, status) = try await transport.send(request)
            guard foreground, generation == stamp, approval.matches(approval.context), isCurrent(), !Task.isCancelled else { return }
            switch try CityFairnessWire.report(data: data, status: status, scope: approval.scope, accountID: approval.context.session.accountID, queryID: queryID, asOf: asOf, cursor: cursor) {
            case .discard:
                if page == nil { screen = .blocked }
            case .screen(let decoded):
                if let cursor {
                    guard case .mature(let incoming) = decoded, let current = page,
                          sameSnapshot(incoming.queryID, incoming.asOf, incoming.metricVersion, incoming.factRevision, current),
                          incoming.matureCount == current.matureCount, incoming.denominator == current.denominator,
                          incoming.showsRatio == current.showsRatio else { refreshing = false; return }
                    var seen = Set(current.members.map(\.id))
                    let added = incoming.members.filter { seen.insert($0.id).inserted }
                    let merged = CityFairnessPage(queryID: current.queryID, matureCount: current.matureCount, denominator: current.denominator, asOf: current.asOf, metricVersion: current.metricVersion, formulaId: current.formulaId, factRevision: current.factRevision, members: current.members + added, nextCursor: incoming.nextCursor, showsRatio: current.showsRatio, missing: current.missing, coverage: current.coverage)
                    page = merged
                    screen = .mature(merged)
                } else {
                    if case .mature(let incoming) = decoded { page = incoming } else { page = nil }
                    screen = decoded
                }
            }
            refreshing = false
        } catch {
            guard generation == stamp else { return }
            let failure = Self.failure(error)
            if failure == .unauthorized || failure == .notComputable || failure == .forbidden {
                page = nil; refreshFailure = nil; screen = .failed(failure)
                if failure == .unauthorized, isCurrent(), !Task.isCancelled { onUnauthorized() }
            } else if page == nil { screen = .failed(failure) }
            else { refreshFailure = failure }
            refreshing = false
        }
    }
    private func reloadOutings(cursor: String?) async {
        let stamp = UUID(); evidenceGeneration = stamp
        guard let approval, approval.matches(approval.context), isCurrent() else {
            outingPage = nil; outingFailure = nil; outingBlocked = true; outingRefreshing = false; return
        }
        outingFailure = nil
        outingRefreshing = outingPage != nil
        let asOf = pinnedStamp()
        do {
            let route = try CityFairnessRoute(outing: approval.scope, queryID: queryID, asOf: asOf, cursor: cursor)
            let request = try route.request(baseURL: approval.context.baseURL, token: approval.context.session.token)
            let (data, status) = try await transport.send(request)
            guard foreground, evidenceGeneration == stamp, approval.matches(approval.context), isCurrent() else { return }
            switch try CityFairnessWire.ownOutings(data: data, status: status, scope: approval.scope, accountID: approval.context.session.accountID, queryID: queryID, asOf: asOf, cursor: cursor) {
            case .discard:
                if outingPage == nil { outingBlocked = true }
            case .page(let incoming):
                if let cursor, let current = outingPage {
                    guard sameSnapshot(incoming.queryID, incoming.asOf, incoming.metricVersion, incoming.factRevision, current) else { outingRefreshing = false; return }
                    var seen = Set(current.outings.map(\.id))
                    let added = incoming.outings.filter { seen.insert($0.id).inserted }
                    outingPage = CityFairnessOutingPage(queryID: current.queryID, asOf: current.asOf, metricVersion: current.metricVersion, factRevision: current.factRevision, maturity: current.maturity, t0: current.t0, outings: current.outings + added, nextCursor: incoming.nextCursor, missing: current.missing, coverage: current.coverage)
                } else if cursor == nil {
                    outingPage = incoming
                }
                outingBlocked = false
            }
            outingRefreshing = false
        } catch {
            guard evidenceGeneration == stamp else { return }
            let failure = Self.failure(error)
            if failure == .unauthorized || failure == .forbidden { outingPage = nil; if failure == .unauthorized, isCurrent() { onUnauthorized() } }
            outingFailure = failure
            outingBlocked = false
            outingRefreshing = false
        }
    }
    private func sameSnapshot(_ queryID: String, _ asOf: Int64, _ metricVersion: String?, _ factRevision: Int64?, _ current: CityFairnessPage) -> Bool {
        queryID == current.queryID && asOf == current.asOf && metricVersion == current.metricVersion && factRevision == current.factRevision
    }
    private func sameSnapshot(_ queryID: String, _ asOf: Int64, _ metricVersion: String?, _ factRevision: Int64?, _ current: CityFairnessOutingPage) -> Bool {
        queryID == current.queryID && asOf == current.asOf && metricVersion == current.metricVersion && factRevision == current.factRevision
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
