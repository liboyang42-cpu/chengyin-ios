import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityCurrentSnapshotFailure: Error, Equatable {
    case disabled, invalidQuery, staleSession, unverified, expired, unavailable(status: Int)
}

/// Exact bounded current-read query. No GPS acquisition, cursor, sync or action fields.
public struct CityCurrentSnapshotQuery: Equatable {
    public let regionID: String
    public let boardID: String
    public let seasonID: String
    public let rulesReleaseID: String
    public let revision: Int64
    public let south: String
    public let west: String
    public let north: String
    public let east: String
    public let datum: String
    public let zoom: Int
    public let layers: [String]
    public let limit: Int
    public init(regionID: String, boardID: String, seasonID: String, rulesReleaseID: String, revision: Int64,
                south: String, west: String, north: String, east: String, datum: String, zoom: Int, layers: [String], limit: Int) throws {
        guard [regionID, boardID, seasonID, rulesReleaseID].allSatisfy(Self.isID), (0...9_007_199_254_740_991).contains(revision),
              let s = Self.coordinate(south), let w = Self.coordinate(west), let n = Self.coordinate(north), let e = Self.coordinate(east),
              Self.bounded(s, w, n, e, span: Decimal(string: "0.5")!), ["WGS84", "GCJ02"].contains(datum),
              (0...22).contains(zoom), (1...50).contains(limit), !layers.isEmpty, layers == layers.sorted(),
              Set(layers).count == layers.count, Set(layers).isSubset(of: ["MERCHANT", "POI", "PLATFORM_VIRTUAL"]) else {
            throw CityCurrentSnapshotFailure.invalidQuery
        }
        self.regionID = regionID; self.boardID = boardID; self.seasonID = seasonID; self.rulesReleaseID = rulesReleaseID; self.revision = revision
        self.south = south; self.west = west; self.north = north; self.east = east; self.datum = datum; self.zoom = zoom; self.layers = layers; self.limit = limit
    }
    fileprivate static func isID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        func alnum(_ b: UInt8) -> Bool { (48...57).contains(b) || (65...90).contains(b) || (97...122).contains(b) }
        return !bytes.isEmpty && bytes.count <= 96 && alnum(bytes[0]) && bytes.allSatisfy { alnum($0) || $0 == 45 || $0 == 95 }
    }
    fileprivate static func coordinate(_ value: String) -> Decimal? {
        guard value.range(of: "^-?(?:0|[1-9][0-9]{0,2})(?:\\.[0-9]{1,12})?$", options: .regularExpression) == (value.startIndex..<value.endIndex) else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }
    fileprivate static func bounded(_ s: Decimal, _ w: Decimal, _ n: Decimal, _ e: Decimal, span: Decimal) -> Bool {
        s < n && w < e && s >= -85 && n <= 85 && w >= -180 && e <= 180 && n - s <= span && e - w <= span
    }
    fileprivate var items: [URLQueryItem] {
        [("regionId", regionID), ("boardId", boardID), ("seasonId", seasonID), ("rulesReleaseId", rulesReleaseID), ("revision", String(revision)),
         ("south", south), ("west", west), ("north", north), ("east", east), ("datum", datum), ("zoom", String(zoom)),
         ("layers", layers.joined(separator: ",")), ("limit", String(limit))].map { .init(name: $0.0, value: $0.1) }
    }
}

public struct CityCurrentSnapshotScope: Equatable {
    public let session: CityOriginalReceiptSession
    public let query: CityCurrentSnapshotQuery
    private let credential: String
    public init(market: RegionalMarket, baseURL: URL, namespace: String, accountID: Int, epoch: UInt64, token: String, query: CityCurrentSnapshotQuery) throws {
        session = try .init(market: market, baseURL: baseURL, namespace: namespace, accountID: accountID, epoch: epoch, token: token)
        self.query = query; credential = token
    }
    fileprivate var token: String { credential }
}

@MainActor public final class CityCurrentSnapshotReadGrant {
    public let scope: CityCurrentSnapshotScope
    public private(set) var isRevoked = false
    public init(scope: CityCurrentSnapshotScope) { self.scope = scope }
    public func revoke() { isRevoked = true }
}

/// As-of read only. Not an ordered event stream or CityGameSnapshot adapter.
public struct CityCurrentSnapshot: Decodable, Equatable {
    public let contract: String
    public let scope: String
    public let mode: String
    public let deltaStatus: String
    public let deltaReason: String
    public let board: Board
    public let boardVersion: Int64
    public let membership: String
    public let participation: Participation?
    public let points: [Point]
    public let mapRead: MapRead
    public let viewport: Bounds
    public let datum: String
    public let zoom: Int
    public let layers: [String]
    public let complete: Bool
    public let capturedAtMillis: Int64
    public let validUntilMillis: Int64?
    public let grantsNavigation: Bool
    public let grantsAction: Bool
    public struct Board: Decodable, Equatable {
        public let gameId: String
        public let boardId: String
        public let regionId: String
        public let seasonId: String
        public let rulesReleaseId: String
        public let rulesHash: String
        public let lifecycle: String
        public let title: String
        public let revision: Int64
    }
    public struct Participation: Decodable, Equatable {
        public let participationId: String
        public let membershipVersion: Int64
    }
    public struct Bounds: Decodable, Equatable {
        public let south: Decimal
        public let west: Decimal
        public let north: Decimal
        public let east: Decimal
        fileprivate func bounded(_ span: Decimal) -> Bool { CityCurrentSnapshotQuery.bounded(south, west, north, east, span: span) }
    }
    public struct MapRead: Decodable, Equatable {
        public let contract: String
        public let datum: String
        public let initialViewport: Bounds
        public let initialZoom: Int
        public let maxViewportSpanDegrees: Decimal
        public let minZoom: Int
        public let maxZoom: Int
        public let pageSize: Int
        public let maxPages: Int
    }
    public struct Point: Decodable, Equatable {
        public let pointId: String
        public let title: String
        public let latitude: Decimal
        public let longitude: Decimal
        public let domain: String
        public let datum: String
        public let collectedAt: String
        public let coordinateAssurance: String
        public let availability: String
        public let merchantVersion: Int64
        public let platformVersion: Int64
        public let mine: Bool
        public let ownership: String
        public let grantsNavigation: Bool
        public let grantsAction: Bool
    }
    func validate(_ q: CityCurrentSnapshotQuery, now: Int64) throws {
        func require(_ value: Bool) throws { if !value { throw CityCurrentSnapshotFailure.unverified } }
        try require(contract == "CITY_CURRENT_SNAPSHOT_V1" && scope == "CITY" && mode == "CURRENT_SNAPSHOT"
                    && deltaStatus == "DELTAS_UNAVAILABLE" && deltaReason == "AUTHORIZATION_LIFETIME_UNAVAILABLE")
        try require(complete && !grantsNavigation && !grantsAction && capturedAtMillis > 0)
        if let deadline = validUntilMillis {
            try require(deadline > capturedAtMillis)
            if now >= deadline { throw CityCurrentSnapshotFailure.expired }
        }
        try require(board.regionId == q.regionID && board.boardId == q.boardID && board.seasonId == q.seasonID
                    && board.rulesReleaseId == q.rulesReleaseID && board.revision == q.revision && boardVersion == q.revision)
        try require(CityCurrentSnapshotQuery.isID(board.gameId) && board.lifecycle == "FROZEN" && board.rulesHash.utf8.count == 64 && board.rulesHash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
        try require(datum == q.datum && zoom == q.zoom && layers == q.layers)
        try require(viewport.south == CityCurrentSnapshotQuery.coordinate(q.south) && viewport.west == CityCurrentSnapshotQuery.coordinate(q.west)
                    && viewport.north == CityCurrentSnapshotQuery.coordinate(q.north) && viewport.east == CityCurrentSnapshotQuery.coordinate(q.east))
        let m = mapRead
        try require(m.contract == "CITY_BOUNDED_MAP_V1" && m.datum == datum && m.maxViewportSpanDegrees > 0 && m.maxViewportSpanDegrees <= Decimal(string: "0.5")!)
        try require(m.minZoom >= 0 && m.maxZoom <= 22 && m.minZoom <= m.maxZoom && (m.minZoom...m.maxZoom).contains(m.initialZoom) && (m.minZoom...m.maxZoom).contains(zoom))
        try require(m.initialViewport.bounded(m.maxViewportSpanDegrees) && viewport.bounded(m.maxViewportSpanDegrees) && m.pageSize == 50 && m.maxPages == 4)
        if let p = participation {
            try require(membership == "JOINED" && CityCurrentSnapshotQuery.isID(p.participationId) && p.membershipVersion > 0)
        } else { try require(membership == "NOT_JOINED") }
        try require(points.count <= 200 && Set(points.map(\.pointId)).count == points.count && points.map(\.pointId) == points.map(\.pointId).sorted())
        for p in points {
            try require(CityCurrentSnapshotQuery.isID(p.pointId) && layers.contains(p.domain) && p.datum == datum && p.coordinateAssurance == "PLATFORM_REVIEWED_METADATA")
            try require(p.latitude >= viewport.south && p.latitude <= viewport.north && p.longitude >= viewport.west && p.longitude <= viewport.east)
            try require(["AVAILABLE", "PAUSED", "UNAVAILABLE"].contains(p.availability) && ["NOT_EVALUATED", "UNOWNED", "OUR_TEAM", "OTHER_TEAM", "RETAINED_REVIEW"].contains(p.ownership))
            try require(p.merchantVersion >= 0 && p.platformVersion >= 0 && !p.grantsNavigation && !p.grantsAction)
            try require(p.ownership != "OUR_TEAM" || p.mine)
            // RETAINED_REVIEW may still be ours. Never derive ownership/permission from a colour.
            let seconds = ISO8601DateFormatter()
            seconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let time = seconds.date(from: p.collectedAt) ?? ISO8601DateFormatter().date(from: p.collectedAt)
            guard let time else { throw CityCurrentSnapshotFailure.unverified }
            try require(time.timeIntervalSince1970 * 1000 <= Double(capturedAtMillis))
        }
    }
}

@MainActor public final class CityCurrentSnapshotReader {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let currentScope: () -> CityCurrentSnapshotScope?
    private let grant: () -> CityCurrentSnapshotReadGrant?
    private let now: () -> Int64
    public init(configuration: APIConfiguration, transport: any HTTPTransport, currentScope: @escaping () -> CityCurrentSnapshotScope?,
                grant: @escaping () -> CityCurrentSnapshotReadGrant? = { nil }, now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.configuration = configuration; self.transport = transport; self.currentScope = currentScope; self.grant = grant; self.now = now
    }
    public func read(_ scope: CityCurrentSnapshotScope) async throws -> CityCurrentSnapshot {
        guard let issued = grant(), !issued.isRevoked, issued.scope == scope else { throw CityCurrentSnapshotFailure.disabled }
        func check() throws {
            try Task.checkCancellation()
            guard currentScope() == scope && configuration.baseURL == scope.session.baseURL else { throw CityCurrentSnapshotFailure.staleSession }
            guard grant() === issued && !issued.isRevoked else { throw CityCurrentSnapshotFailure.disabled }
        }
        try check()
        var url = URLComponents(url: configuration.baseURL.appendingPathComponent("api/city-game/state/snapshot"), resolvingAgainstBaseURL: false)
        url?.queryItems = scope.query.items
        guard let target = url?.url else { throw CityCurrentSnapshotFailure.invalidQuery }
        var request = URLRequest(url: target)
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue(scope.token, forHTTPHeaderField: "Authorization")
        let response: (Data, Int)
        do { response = try await transport.send(request) }
        catch { try check(); throw CityCurrentSnapshotFailure.unverified }
        try check()
        guard response.1 == 200 else { throw CityCurrentSnapshotFailure.unavailable(status: response.1) }
        guard response.0.count <= 1_048_576, let header = try? JSONDecoder().decode(Header.self, from: response.0) else { throw CityCurrentSnapshotFailure.unverified }
        guard header.code == 200 else { throw CityCurrentSnapshotFailure.unavailable(status: header.code) }
        guard header.errorCode == nil || header.errorCode == "", let envelope = try? JSONDecoder().decode(Envelope.self, from: response.0) else { throw CityCurrentSnapshotFailure.unverified }
        try envelope.data.validate(scope.query, now: now()); try check()
        return envelope.data
    }
    private struct Header: Decodable { let code: Int; let errorCode: String? }
    private struct Envelope: Decodable { let data: CityCurrentSnapshot }
}
