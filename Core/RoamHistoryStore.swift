import Foundation

public struct RoamHistoryPoint: Codable, Equatable {
    public let lat: Double
    public let lng: Double
    public var coordinate: RoamCoordinate { RoamCoordinate(latitude: lat, longitude: lng)! }
    public init(coordinate: RoamCoordinate) { lat = coordinate.latitude; lng = coordinate.longitude }
    enum CodingKeys: String, CodingKey { case lat, lng }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let lat = c.roamNumber(.lat), let lng = c.roamNumber(.lng),
              RoamCoordinate(latitude: lat, longitude: lng) != nil else { throw RoamExperienceFailure.historyUnreadable }
        self.lat = lat; self.lng = lng
    }
}
public struct RoamHistoryPlace: Codable, Equatable {
    public let id: Int?
    public let name: String
    public let cat: String?
    public let lat: Double
    public let lng: Double
    public var point: RoamHistoryPoint { RoamHistoryPoint(coordinate: RoamCoordinate(latitude: lat, longitude: lng)!) }
    enum CodingKeys: String, CodingKey { case id, name, cat, lat, lng }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let lat = c.roamNumber(.lat), let lng = c.roamNumber(.lng),
              RoamCoordinate(latitude: lat, longitude: lng) != nil else { throw RoamExperienceFailure.historyUnreadable }
        self.lat = lat; self.lng = lng
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        cat = try c.decodeIfPresent(String.self, forKey: .cat)
    }
}
public struct RoamHistoryRecord: Codable, Equatable, Identifiable {
    public var id: Int64 { ts }
    public let ts: Int64
    /// Native-only deduplication provenance. Legacy Flutter records may not contain this field.
    public let serverSessionID: Int?
    public let zone: String?
    public let date: String?
    public let dateLine: String?
    public let distance: Double?
    public let explorePct: Int?
    public let shops: Int?
    public let time: String?
    public let durSec: Int?
    public let photos: [String]
    public let pois: [RoamHistoryPlace]
    public let track: [RoamHistoryPoint]
    public let medal: String?
    public let shopMedalName: String?
    public var durationText: String? {
        if let time, !time.isEmpty { return time }
        guard let durSec else { return nil }
        return String(format: "%02d:%02d", durSec / 60, durSec % 60)
    }
    public var recordedAt: Date? { ts > 0 ? Date(timeIntervalSince1970: Double(ts) / 1000) : nil }
    public var meaningfulZone: String? {
        guard let zone, !zone.isEmpty, zone != "这片街区" else { return nil }; return zone
    }
    enum CodingKeys: String, CodingKey {
        case ts, serverSessionID, zone, date, dateLine, distance, explorePct, shops, time, durSec, photos, pois, track, medal, shopMedalName
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let timestamp = c.roamNumber(.ts), timestamp >= Double(Int64.min), timestamp < Double(Int64.max) else {
            throw RoamExperienceFailure.historyUnreadable
        }
        ts = Int64(timestamp)
        serverSessionID = try c.decodeIfPresent(Int.self, forKey: .serverSessionID)
        zone = try c.roamText(.zone); date = try c.roamText(.date); dateLine = try c.roamText(.dateLine)
        // Missing data remains missing. It must never render as a measured zero.
        distance = c.roamNumber(.distance)
        explorePct = try c.decodeIfPresent(Int.self, forKey: .explorePct)
        shops = try c.decodeIfPresent(Int.self, forKey: .shops)
        time = try c.roamText(.time); durSec = try c.decodeIfPresent(Int.self, forKey: .durSec)
        pois = try c.decodeIfPresent([RoamHistoryPlace].self, forKey: .pois) ?? []
        track = try c.decodeIfPresent([RoamHistoryPoint].self, forKey: .track) ?? []
        photos = try c.decodeIfPresent([RoamLegacyPhoto].self, forKey: .photos)?.map(\.value).filter { !$0.isEmpty } ?? []
        medal = try c.roamText(.medal); shopMedalName = try c.roamText(.shopMedalName)
        guard (distance ?? 0) >= 0, (durSec ?? 0) >= 0, (shops ?? 0) >= 0,
              (serverSessionID ?? 1) > 0 else { throw RoamExperienceFailure.historyUnreadable }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ts, forKey: .ts); try c.encodeIfPresent(serverSessionID, forKey: .serverSessionID)
        try c.encodeIfPresent(zone, forKey: .zone); try c.encodeIfPresent(date, forKey: .date); try c.encodeIfPresent(dateLine, forKey: .dateLine)
        try c.encodeIfPresent(distance, forKey: .distance); try c.encodeIfPresent(explorePct, forKey: .explorePct)
        try c.encodeIfPresent(shops, forKey: .shops); try c.encodeIfPresent(time, forKey: .time); try c.encodeIfPresent(durSec, forKey: .durSec)
        try c.encode(photos, forKey: .photos); try c.encode(pois, forKey: .pois); try c.encode(track, forKey: .track)
        try c.encodeIfPresent(medal, forKey: .medal); try c.encodeIfPresent(shopMedalName, forKey: .shopMedalName)
    }
}
private struct RoamLegacyPhoto: Decodable {
    let value: String
    enum CodingKeys: String, CodingKey { case path, url }
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) { value = text; return }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decodeIfPresent(String.self, forKey: .path) ?? c.decodeIfPresent(String.self, forKey: .url) ?? ""
    }
}
public struct RoamHistorySummary: Equatable {
    public let trips: Int
    public let knownKilometers: Double?
    public let tripsWithDistance: Int
    public let knownShops: Int?
    public let tripsWithShops: Int
    public init(_ records: [RoamHistoryRecord]) {
        trips = records.count
        let distance = records.compactMap(\.distance).reduce(0, +)
        knownKilometers = distance.isFinite ? distance : nil
        tripsWithDistance = records.compactMap(\.distance).count
        var sum: Int? = 0
        for value in records.compactMap(\.shops) {
            guard let current = sum else { break }
            let result = current.addingReportingOverflow(value)
            sum = result.overflow ? nil : result.partialValue
        }
        knownShops = sum
        tripsWithShops = records.compactMap(\.shops).count
    }
}
/// Includes deployment URL and market as well as account. Epoch is excluded for same-account recovery;
/// every reader still gates operations by its current epoch separately. No credentials are persisted.
public struct RoamHistoryScope: Codable, Equatable, Hashable {
    public let market: String
    public let deployment: String
    public let accountID: Int
    public let namespace: String
    public init(market: String, deployment: URL, accountID: Int, namespace: String = "standalone") throws {
        guard ["cn", "us"].contains(market.lowercased()), accountID > 0, !namespace.isEmpty else { throw APIError.invalidRequest }
        _ = try APIConfiguration(baseURL: deployment)
        self.market = market.lowercased(); self.deployment = deployment.absoluteString; self.accountID = accountID; self.namespace = namespace
    }
    public var storageKey: String {
        let raw = [namespace, market, deployment, String(accountID)].map { "\($0.utf8.count):\($0)" }.joined()
        return "roam-history-v1-" + Data(raw.utf8).base64EncodedString()
    }
}
/// Storage must provide atomic replacement. Implementations may throw on locked/unavailable storage.
@MainActor public protocol RoamHistoryDataStoring: AnyObject {
    func read(key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
}
@MainActor public final class RoamHistoryStore {
    private let storage: any RoamHistoryDataStoring
    private let currentScope: () -> RoamHistoryScope?
    private struct Envelope: Codable { let version: Int; let scope: RoamHistoryScope; let records: [RoamHistoryRecord] }
    public init(storage: any RoamHistoryDataStoring, currentScope: @escaping () -> RoamHistoryScope?) {
        self.storage = storage; self.currentScope = currentScope
    }
    public var scope: RoamHistoryScope? { currentScope() }
    public func readAll() throws -> [RoamHistoryRecord] {
        guard let scope = currentScope() else { throw APIError.unauthorized }
        do {
            guard let data = try storage.read(key: scope.storageKey) else { return [] }
            guard data.count <= 2_000_000 else { throw RoamExperienceFailure.historyUnreadable }
            let value = try JSONDecoder().decode(Envelope.self, from: data)
            guard value.records.count <= 50, Set(value.records.map(\.ts)).count == value.records.count else { throw RoamExperienceFailure.historyUnreadable }
            guard value.version == 1, value.scope == scope, currentScope() == scope else { throw RoamExperienceFailure.scopeMismatch }
            return value.records
        } catch let error as RoamExperienceFailure { throw error }
        catch { throw RoamExperienceFailure.historyUnreadable }
    }
    public func find(timestamp: Int64) throws -> RoamHistoryRecord? { try readAll().first { $0.ts == timestamp } }
    /// Do not call from local rehearsal. Only a complete, matching settlement fact can enter history.
    /// Failure keeps the previous durable bytes intact; the caller must retain its unsaved receipt.
    public func prependSettled(_ record: RoamHistoryRecord, fact: RoamSessionFact) throws {
        guard let scope = currentScope() else { throw APIError.unauthorized }
        guard fact.hasCompleteSettlement, let sessionID = fact.sessionID, record.serverSessionID == sessionID,
              record.shops == fact.result?.sessionShops, record.medal == fact.result?.medal,
              record.shopMedalName == fact.result?.shopMedal?.name else {
            throw RoamExperienceFailure.incompleteSettlement
        }
        var records = try readAll()
        records.removeAll { $0.ts == record.ts || $0.serverSessionID == sessionID }
        records.insert(record, at: 0); records = Array(records.prefix(50))
        let data = try JSONEncoder().encode(Envelope(version: 1, scope: scope, records: records))
        guard currentScope() == scope else { throw RoamExperienceFailure.scopeMismatch }
        do { try storage.write(data, key: scope.storageKey) }
        catch { throw RoamExperienceFailure.historyWriteFailed }
    }
}
