import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mini-program roam passport read tools (subpackageTools/anniversary, monthly-recap).
/// Read-only private memories: no writes, rewards, AI or location. Times are Asia/Shanghai wall clock.
public enum RoamShanghaiCalendar {
    public static let offsetSeconds = 8 * 3600
    public struct Day: Equatable { public let year: Int; public let month: Int; public let day: Int }
    public static func day(atMilliseconds ms: Int64) -> Day {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offsetSeconds)!
        let parts = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
        return Day(year: parts.year!, month: parts.month!, day: parts.day!)
    }
    public static func today(now: Date = Date()) -> Day { day(atMilliseconds: Int64(now.timeIntervalSince1970 * 1000)) }
    /// "yyyy-MM" of the Shanghai month containing `now`.
    public static func month(now: Date = Date()) -> String { let d = today(now: now); return monthText(d.year, d.month) }
    public static func monthText(_ year: Int, _ month: Int) -> String { String(format: "%04d-%02d", year, month) }
    public static func shift(_ month: String, by delta: Int) -> String? {
        guard let (year, value) = parseMonth(month) else { return nil }
        let index = year * 12 + (value - 1) + delta
        guard index >= 0 else { return nil }
        return monthText(index / 12, index % 12 + 1)
    }
    public static func parseMonth(_ text: String) -> (Int, Int)? {
        let pieces = text.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 2, pieces[0].count == 4, pieces[1].count == 2,
              pieces.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(pieces[0]), let month = Int(pieces[1]), (1...12).contains(month) else { return nil }
        return (year, month)
    }
    public static func isValidMonthDay(month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        let lengths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] // Leap day allowed for an explicit selection.
        return day <= lengths[month - 1]
    }
    /// Strict wall-clock text "yyyy-MM-dd HH:mm:ss" with optional ".SSS".
    public struct WallTime: Equatable { public let year, month, day, hour, minute: Int }
    public static func wallTime(_ text: String, requireMilliseconds: Bool) -> WallTime? {
        let bytes = Array(text.utf8)
        guard bytes.count == (requireMilliseconds ? 23 : 19) else { return nil }
        let digits: Set<Int> = requireMilliseconds ? Set([0,1,2,3,5,6,8,9,11,12,14,15,17,18,20,21,22]) : Set([0,1,2,3,5,6,8,9,11,12,14,15,17,18])
        let separators: [Int: UInt8] = requireMilliseconds ? [4: 45, 7: 45, 10: 32, 13: 58, 16: 58, 19: 46] : [4: 45, 7: 45, 10: 32, 13: 58, 16: 58]
        for (index, byte) in bytes.enumerated() {
            if digits.contains(index) { guard (48...57).contains(byte) else { return nil } }
            else { guard separators[index] == byte else { return nil } }
        }
        func number(_ range: Range<Int>) -> Int { Int(String(decoding: bytes[range], as: UTF8.self))! }
        let value = WallTime(year: number(0..<4), month: number(5..<7), day: number(8..<10), hour: number(11..<13), minute: number(14..<16))
        guard (1...12).contains(value.month), value.hour < 24, value.minute < 60, number(17..<19) < 60 else { return nil }
        let lengths = [31, (value.year % 4 == 0 && value.year % 100 != 0) || value.year % 400 == 0 ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard value.day >= 1, value.day <= lengths[value.month - 1] else { return nil }
        return value
    }
}

/// Backend Long identifiers may arrive as JSON strings or numbers; both must be canonical positive integers.
struct RoamToolID: Decodable, Equatable {
    let text: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { text = value }
        else if let value = try? container.decode(Int64.self) { text = String(value) }
        else { throw APIError.malformedResponse }
        guard let parsed = Int64(text), parsed > 0, String(parsed) == text else { throw APIError.malformedResponse }
    }
}

// MARK: 那年今日 — GET api/exploration-anniversary

public struct RoamAnniversaryQuery: Equatable {
    /// nil month/day = "today" by the archive contract.
    public let month: Int?
    public let day: Int?
    public let limit: Int
    public let cursor: String?
    public let referenceYear: Int?
    public init(month: Int? = nil, day: Int? = nil, limit: Int = 20, cursor: String? = nil, referenceYear: Int? = nil) {
        self.month = month; self.day = day; self.limit = limit; self.cursor = cursor; self.referenceYear = referenceYear
    }
    public func validate() throws {
        guard (month == nil) == (day == nil), (1...50).contains(limit) else { throw APIError.invalidRequest }
        if let month, let day, !RoamShanghaiCalendar.isValidMonthDay(month: month, day: day) { throw APIError.invalidRequest }
        if let cursor, !RoamAnniversaryPage.isValidCursor(cursor) { throw APIError.invalidRequest }
    }
    var fields: [String: String] {
        var result = ["limit": String(limit)]
        if let month, let day { result["month"] = String(month); result["day"] = String(day) }
        if let cursor { result["cursor"] = cursor }
        return result
    }
}

public struct RoamAnniversaryMemory: Equatable, Identifiable {
    public let id: String
    public let topicID: String
    public let title: String?
    /// Shanghai wall time "yyyy-MM-dd HH:mm:ss.SSS"; display uses minutes only.
    public let completedAt: String
    public let year: Int
    public let yearsAgo: Int
    public var completedMinuteText: String { String(completedAt.prefix(16)) }
}

public struct RoamAnniversaryPage: Equatable {
    public let month: Int
    public let day: Int
    public let referenceYear: Int
    public let asOfMs: Int64
    public let items: [RoamAnniversaryMemory]
    public let hasMore: Bool
    public let nextCursor: String?

    static func isValidCursor(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 95 }
    }
    private struct Raw: Decodable {
        struct Item: Decodable { let id: RoamToolID; let topicId: RoamToolID; let title: String?; let completedAt: String; let year: Int; let yearsAgo: Int }
        let month: Int; let day: Int; let referenceYear: Int; let timeZone: String; let asOfMs: Int64
        let items: [Item]; let hasMore: Bool; let nextCursor: String?
        let leapDayRule: String; let coverage: String; let metadataMode: String
    }
    /// Mirrors the mini-program client projection: any mismatch is an unconfirmed response, never partially shown.
    /// `boundary` is the last item of the previous page when reading a continuation.
    public static func decode(_ data: Data, query: RoamAnniversaryQuery, boundary: RoamAnniversaryMemory? = nil) throws -> RoamAnniversaryPage {
        struct Envelope: Decodable { let data: Raw }
        let value: Raw
        do { value = try JSONDecoder().decode(Envelope.self, from: data).data } catch { throw APIError.malformedResponse }
        guard value.timeZone == "Asia/Shanghai", value.leapDayRule == "EXACT_MONTH_DAY_ONLY",
              value.coverage == "RECORDED_OWN_COMPLETED_SESSIONS_WITH_CURRENT_VISIBLE_ROUTE", value.metadataMode == "CURRENT_ROUTE_METADATA",
              RoamShanghaiCalendar.isValidMonthDay(month: value.month, day: value.day),
              (2000...9999).contains(value.referenceYear), value.asOfMs >= 0, value.items.count <= query.limit else { throw APIError.malformedResponse }
        if value.hasMore {
            guard let next = value.nextCursor, isValidCursor(next), value.items.count == query.limit, next != query.cursor else { throw APIError.malformedResponse }
        } else { guard value.nextCursor == nil else { throw APIError.malformedResponse } }
        let today = RoamShanghaiCalendar.day(atMilliseconds: value.asOfMs)
        guard today.year == value.referenceYear else { throw APIError.malformedResponse }
        if let month = query.month, let day = query.day { guard value.month == month, value.day == day else { throw APIError.malformedResponse } }
        else { guard value.month == today.month, value.day == today.day else { throw APIError.malformedResponse } }
        if let year = query.referenceYear { guard value.referenceYear == year else { throw APIError.malformedResponse } }
        var seen = Set<String>(); var previous = boundary
        let items: [RoamAnniversaryMemory] = try value.items.map { item in
            guard let wall = RoamShanghaiCalendar.wallTime(item.completedAt, requireMilliseconds: true), !seen.contains(item.id.text),
                  item.year == wall.year, item.year < value.referenceYear, wall.month == value.month, wall.day == value.day,
                  item.yearsAgo == value.referenceYear - item.year else { throw APIError.malformedResponse }
            if let previous {
                // Newest first; equal timestamps ordered by descending id.
                let order = previous.completedAt > item.completedAt || (previous.completedAt == item.completedAt && greater(previous.id, item.id.text))
                guard order else { throw APIError.malformedResponse }
            }
            let memory = RoamAnniversaryMemory(id: item.id.text, topicID: item.topicId.text, title: item.title, completedAt: item.completedAt, year: item.year, yearsAgo: item.yearsAgo)
            seen.insert(item.id.text); previous = memory
            return memory
        }
        return RoamAnniversaryPage(month: value.month, day: value.day, referenceYear: value.referenceYear, asOfMs: value.asOfMs,
                                   items: items, hasMore: value.hasMore, nextCursor: value.nextCursor)
    }
    private static func greater(_ a: String, _ b: String) -> Bool { a.count != b.count ? a.count > b.count : a > b }
}

// MARK: 月度回顾 — GET api/monthly-recap

public enum RoamRecapKind: String, CaseIterable, Identifiable {
    case routes, places, stamps
    public var id: String { rawValue }
}

public struct RoamMonthlyRecapQuery: Equatable {
    public let month: String
    public let kind: RoamRecapKind
    public let beforeID: String?
    public let limit = 20
    public init(month: String, kind: RoamRecapKind = .routes, beforeID: String? = nil) {
        self.month = month; self.kind = kind; self.beforeID = beforeID
    }
    public func validate(currentMonth: String) throws {
        guard let (year, _) = RoamShanghaiCalendar.parseMonth(month), (2000...9998).contains(year), month <= currentMonth else { throw APIError.invalidRequest }
        if let beforeID { guard let value = Int64(beforeID), value > 0, String(value) == beforeID else { throw APIError.invalidRequest } }
    }
    var fields: [String: String] {
        var result = ["month": month, "kind": kind.rawValue, "limit": String(limit)]
        if let beforeID { result["beforeId"] = beforeID }
        return result
    }
}

public struct RoamRecapCounts: Equatable, Decodable {
    public let routes: Int; public let places: Int; public let stamps: Int
}

public struct RoamRecapRecord: Equatable, Identifiable {
    public let id: String
    public let title: String
    /// Shanghai wall time "yyyy-MM-dd HH:mm:ss".
    public let occurredAt: String
    public let dayOfMonth: Int
    public let monthOfYear: Int
    /// "M/d" as the mini-program list shows.
    public var dateText: String { "\(monthOfYear)/\(dayOfMonth)" }
}

public struct RoamRecapWeek: Equatable, Identifiable {
    public let index: Int
    public let count: Int
    public let isMax: Bool
    public var id: Int { index }
}

public struct RoamMonthlyRecapPage: Equatable {
    public let month: String
    public let kind: RoamRecapKind
    public let counts: RoamRecapCounts
    public let items: [RoamRecapRecord]
    public let hasMore: Bool
    public let nextBeforeID: String?

    /// Weekly columns exist only once every record of the month has been read (no invented partial chart).
    public var weeks: [RoamRecapWeek] {
        guard !hasMore, !items.isEmpty else { return [] }
        var counts = [0, 0, 0, 0, 0]
        for item in items { counts[min(4, (item.dayOfMonth - 1) / 7)] += 1 }
        let top = counts.max() ?? 0
        return counts.enumerated().map { RoamRecapWeek(index: $0.offset + 1, count: $0.element, isMax: top > 0 && $0.element == top) }
    }

    private struct Raw: Decodable {
        struct Item: Decodable { let id: RoamToolID; let title: String?; let occurredAt: String }
        let month: String; let kind: String; let counts: RoamRecapCounts
        let items: [Item]; let hasMore: Bool; let nextBeforeId: RoamToolID?
    }
    public static func decode(_ data: Data, query: RoamMonthlyRecapQuery) throws -> RoamMonthlyRecapPage {
        struct Envelope: Decodable { let data: Raw }
        let value: Raw
        do { value = try JSONDecoder().decode(Envelope.self, from: data).data } catch { throw APIError.malformedResponse }
        guard value.month == query.month, value.kind == query.kind.rawValue, value.items.count <= query.limit,
              value.counts.routes >= 0, value.counts.places >= 0, value.counts.stamps >= 0,
              let (year, month) = RoamShanghaiCalendar.parseMonth(query.month) else { throw APIError.malformedResponse }
        if value.hasMore { guard value.nextBeforeId != nil, !value.items.isEmpty else { throw APIError.malformedResponse } }
        else { guard value.nextBeforeId == nil else { throw APIError.malformedResponse } }
        var seen = Set<String>()
        var items: [RoamRecapRecord] = []
        for item in value.items {
            guard let wall = RoamShanghaiCalendar.wallTime(item.occurredAt, requireMilliseconds: false),
                  wall.year == year, wall.month == month else { throw APIError.malformedResponse }
            // Same-page duplicates are collapsed exactly as the mini-program client does.
            guard seen.insert(item.id.text).inserted else { continue }
            items.append(RoamRecapRecord(id: item.id.text, title: item.title ?? "", occurredAt: item.occurredAt, dayOfMonth: wall.day, monthOfYear: wall.month))
        }
        return RoamMonthlyRecapPage(month: value.month, kind: query.kind, counts: value.counts, items: items,
                                    hasMore: value.hasMore, nextBeforeID: value.nextBeforeId?.text)
    }
}

// MARK: Reading

@MainActor public protocol RoamPassportToolsReading: AnyObject {
    var identity: RoamExperienceIdentity? { get }
    var isConfigured: Bool { get }
    var isOfflineExample: Bool { get }
    func anniversary(_ query: RoamAnniversaryQuery, boundary: RoamAnniversaryMemory?) async throws -> RoamAnniversaryPage
    func monthlyRecap(_ query: RoamMonthlyRecapQuery) async throws -> RoamMonthlyRecapPage
}

/// Source-backed GETs only; callers inject an approved deployment, transport and session token.
public struct RoamPassportToolsService {
    public static let paths = ["api/exploration-anniversary", "api/monthly-recap"]
    public let deployment: URL
    private let transport: any HTTPTransport
    private let now: () -> Date
    public init(configuration: APIConfiguration, transport: any HTTPTransport, now: @escaping () -> Date = Date.init) {
        deployment = configuration.baseURL; self.transport = transport; self.now = now
    }
    public func anniversary(_ query: RoamAnniversaryQuery, boundary: RoamAnniversaryMemory? = nil, token: String) async throws -> RoamAnniversaryPage {
        try query.validate()
        return try RoamAnniversaryPage.decode(await get(Self.paths[0], fields: query.fields, token: token), query: query, boundary: boundary)
    }
    public func monthlyRecap(_ query: RoamMonthlyRecapQuery, token: String) async throws -> RoamMonthlyRecapPage {
        try query.validate(currentMonth: RoamShanghaiCalendar.month(now: now()))
        return try RoamMonthlyRecapPage.decode(await get(Self.paths[1], fields: query.fields, token: token), query: query)
    }
    private func get(_ path: String, fields: [String: String], token: String) async throws -> Data {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        guard var parts = URLComponents(url: deployment.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        parts.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
        guard let url = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        struct Status: Decodable { let code: Int }
        guard let envelope = try? JSONDecoder().decode(Status.self, from: data) else { throw APIError.malformedResponse }
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw APIError.businessCode(envelope.code) }
        return data
    }
}

/// Synthetic offline data for previews and UI tests. Never a real account's memories.
@MainActor public final class RoamPassportToolsFixtureReader: RoamPassportToolsReading {
    public enum Scenario: String { case content, empty, failure, unauthorized }
    public let scenario: Scenario
    private let scope = try! RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/synthetic-roam")!, accountID: 900)
    /// Fixed synthetic "now": 2026-10-19 12:00 Asia/Shanghai.
    public static let asOfMs: Int64 = 1_792_382_400_000
    public init(scenario: Scenario = .content) { self.scenario = scenario }
    public var identity: RoamExperienceIdentity? { scenario == .unauthorized ? nil : RoamExperienceIdentity(scope: scope, epoch: 1) }
    public var isConfigured: Bool { true }
    public var isOfflineExample: Bool { true }
    private func check() throws {
        guard identity != nil else { throw APIError.unauthorized }
        if scenario == .failure { throw APIError.httpStatus(503) }
    }
    public func anniversary(_ query: RoamAnniversaryQuery, boundary: RoamAnniversaryMemory?) async throws -> RoamAnniversaryPage {
        try check(); try query.validate()
        let today = RoamShanghaiCalendar.day(atMilliseconds: Self.asOfMs)
        let month = query.month ?? today.month, day = query.day ?? today.day
        let stamp = { (year: Int, time: String) in String(format: "%04d-%02d-%02d ", year, month, day) + time }
        // Newest first, matching the archive ordering; one complete page.
        let items = scenario == .content ? [
            #"{"id":"31","topicId":"7001","title":"老城墙夜行","completedAt":"\#(stamp(2025, "19:42:10.120"))","year":2025,"yearsAgo":1}"#,
            #"{"id":"12","topicId":"7002","title":"滨江骑行路线","completedAt":"\#(stamp(2023, "09:05:00.000"))","year":2023,"yearsAgo":3}"#,
        ] : []
        let json = #"{"code":200,"data":{"month":\#(month),"day":\#(day),"referenceYear":\#(today.year),"timeZone":"Asia/Shanghai","asOfMs":\#(Self.asOfMs),"items":[\#(items.joined(separator: ","))],"hasMore":false,"nextCursor":null,"leapDayRule":"EXACT_MONTH_DAY_ONLY","coverage":"RECORDED_OWN_COMPLETED_SESSIONS_WITH_CURRENT_VISIBLE_ROUTE","metadataMode":"CURRENT_ROUTE_METADATA"}}"#
        return try RoamAnniversaryPage.decode(Data(json.utf8), query: query, boundary: boundary)
    }
    public func monthlyRecap(_ query: RoamMonthlyRecapQuery) async throws -> RoamMonthlyRecapPage {
        try check()
        try query.validate(currentMonth: RoamShanghaiCalendar.month(now: Date(timeIntervalSince1970: TimeInterval(Self.asOfMs) / 1000)))
        let titles: [RoamRecapKind: [(String, Int)]] = [.routes: [("老城墙夜行", 3), ("滨江骑行路线", 9), ("梧桐街区漫步", 10)],
                                                        .places: [("转角咖啡", 4)], .stamps: [("城市签", 17)]]
        let rows = scenario == .content ? (titles[query.kind] ?? []) : []
        let items = rows.enumerated().map { index, row in
            #"{"id":"\#(100 - index)","objectId":"\#(500 + index)","title":"\#(row.0)","occurredAt":"\#(query.month)-\#(String(format: "%02d", row.1)) 10:00:00"}"#
        }
        let counts = scenario == .content ? #"{"routes":3,"places":1,"stamps":1}"# : #"{"routes":0,"places":0,"stamps":0}"#
        let json = #"{"code":200,"data":{"month":"\#(query.month)","kind":"\#(query.kind.rawValue)","timeZone":"Asia/Shanghai","generatedAtMs":\#(Self.asOfMs),"counts":\#(counts),"items":[\#(items.joined(separator: ","))],"hasMore":false,"nextBeforeId":null}}"#
        return try RoamMonthlyRecapPage.decode(Data(json.utf8), query: query)
    }
}
