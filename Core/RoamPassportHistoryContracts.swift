import Foundation

/// Exact public c6 passport projection. Separate from local settled-history storage and all writers.
/// P-7 track is optional display-only data; missing or malformed geometry never becomes a route.
public enum RoamPassportHistoryContract {
    public static let pageLimit = 30
    public static let maximumCount: Int64 = 9_007_199_254_740_991 // Number.isSafeInteger

    /// Preserve Java Long IDs as decimal strings, never through Double/JavaScript rounding.
    public static func isSessionID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 19, (49...57).contains(bytes[0]),
              bytes.allSatisfy({ (48...57).contains($0) }) else { return false }
        return bytes.count < 19 || value <= "9223372036854775807"
    }
    static func precedes(_ value: String, _ previous: String) -> Bool {
        value.utf8.count == previous.utf8.count ? value < previous : value.utf8.count < previous.utf8.count
    }
    static func count<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) throws -> Int64? {
        let value = try container.decodeIfPresent(Int64.self, forKey: key)
        if let value, value < 0 || value > maximumCount { throw APIError.malformedResponse }
        return value
    }
    public static func page(_ data: Data, before: String? = nil) throws -> RoamPassportHistoryPage {
        if let before, !isSessionID(before) { throw APIError.invalidRequest }
        do {
            let page = try JSONDecoder().decode(RoamPassportHistoryPage.self, from: data)
            try page.validate(before: before)
            return page
        } catch let error as APIError { throw error }
        catch { throw APIError.malformedResponse }
    }
    public static func record(_ data: Data, sessionID: String) throws -> RoamPassportHistoryFact {
        guard isSessionID(sessionID) else { throw APIError.invalidRequest }
        do {
            let record = try JSONDecoder().decode(RoamPassportHistoryFact.self, from: data)
            guard record.sessionID == sessionID else { throw APIError.malformedResponse }
            return record
        } catch let error as APIError { throw error }
        catch { throw APIError.malformedResponse }
    }
}

public struct RoamPassportHistoryFact: Decodable, Equatable, Identifiable {
    public let sessionID: String
    public var id: String { "server:" + sessionID }
    public let startedAt: Int64?
    public let finishedAt: Int64?
    public let distanceM: Int64?
    public let shops: Int64?
    public let track: [RoamHistoryPoint]
    public var distanceKM: Double? { distanceM.map { Double($0) / 1000 } }
    public var durationSeconds: Int64? {
        guard let startedAt, let finishedAt, finishedAt >= startedAt else { return nil }
        return (finishedAt - startedAt) / 1000
    }
    public var timestamp: Int64 {
        if let finishedAt, finishedAt > 0 { return finishedAt }
        return startedAt ?? 0
    }
    enum CodingKeys: String, CodingKey { case sessionId, startedAt, finishedAt, distanceM, shops, track }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionId)
        guard RoamPassportHistoryContract.isSessionID(sessionID) else { throw APIError.malformedResponse }
        startedAt = try RoamPassportHistoryContract.count(c, .startedAt)
        finishedAt = try RoamPassportHistoryContract.count(c, .finishedAt)
        distanceM = try RoamPassportHistoryContract.count(c, .distanceM)
        shops = try RoamPassportHistoryContract.count(c, .shops)
        // Original mini serverTrack rejects the entire malformed optional track. It does not
        // manufacture geometry from counts, timestamps, POIs, or another session.
        if let pairs = try? c.decode([[Double]].self, forKey: .track),
           pairs.allSatisfy({ $0.count == 2 && RoamCoordinate(latitude: $0[0], longitude: $0[1]) != nil }) {
            track = pairs.map { RoamHistoryPoint(coordinate: RoamCoordinate(latitude: $0[0], longitude: $0[1])!) }
        } else { track = [] }
    }
}

public struct RoamPassportHistoryPage: Decodable, Equatable {
    public let items: [RoamPassportHistoryFact]
    public let hasMore: Bool
    public let nextBefore: String?
    enum CodingKeys: String, CodingKey { case items, hasMore, nextBefore }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([RoamPassportHistoryFact].self, forKey: .items)
        hasMore = try c.decode(Bool.self, forKey: .hasMore)
        // The original ignores a terminal cursor entirely; it is not a next-page authority.
        if hasMore { nextBefore = try c.decode(String.self, forKey: .nextBefore) }
        else { nextBefore = nil }
        try validate(before: nil)
    }
    func validate(before: String?) throws {
        guard items.count <= RoamPassportHistoryContract.pageLimit else { throw APIError.malformedResponse }
        var previous = before
        for item in items {
            if let previous, !RoamPassportHistoryContract.precedes(item.sessionID, previous) {
                throw APIError.malformedResponse
            }
            previous = item.sessionID
        }
        if hasMore, items.isEmpty || nextBefore != items.last?.sessionID { throw APIError.malformedResponse }
    }
}

/// Server totals are decoded independently; local legacy records must not be added to them.
public struct RoamPassportServerSummary: Decodable, Equatable {
    public let trips: Int64
    public let distanceM: Int64?
    public let days: Int64?
    public let shops: Int64?
    enum CodingKeys: String, CodingKey { case trips, distanceM, days, shops }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let trips = try RoamPassportHistoryContract.count(c, .trips) else { throw APIError.malformedResponse }
        self.trips = trips
        distanceM = try RoamPassportHistoryContract.count(c, .distanceM)
        days = try RoamPassportHistoryContract.count(c, .days)
        shops = try RoamPassportHistoryContract.count(c, .shops)
    }
}
