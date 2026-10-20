import Foundation

/// Mini-program subpackageTools/exploration-export with utils/features/exploration-export.js.
/// Prepare a server snapshot, read every chunk in order, and only then offer one complete JSONL file.
public enum RoamExportContract {
    public static let format = "chengyin-exploration-export-v1"
    public static let defaultPageSize = 100
    static let longMax = "9223372036854775807"
    static func decimal(_ value: String, allowZero: Bool) -> Bool {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return false }
        if value == "0" { return allowZero }
        guard value.utf8.first != 48 else { return false }
        return value.utf8.count < longMax.utf8.count || (value.utf8.count == longMax.utf8.count && value <= longMax)
    }
    /// Numeric comparison of canonical decimal strings.
    static func compare(_ a: String, _ b: String) -> Int {
        if a.utf8.count != b.utf8.count { return a.utf8.count < b.utf8.count ? -1 : 1 }
        return a == b ? 0 : (a < b ? -1 : 1)
    }
    static func exportDate(_ value: String) -> Int64? {
        guard value >= "2000-01-01" else { return nil }
        return RoamShanghaiCalendar.parseDate(value)
    }
    /// 1–366 days, the server's per-export limit.
    public static func isValidRange(start: String, end: String) -> Bool {
        guard let a = exportDate(start), let b = exportDate(end), a < b else { return false }
        return b - a <= 366
    }
    static func isCursor(_ value: String) -> Bool {
        (40...512).contains(value.utf8.count) && value.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 95 }
    }
}

/// 近 30 天 / 今年 / 近一年 (not "all": one export covers at most 366 days). End is tomorrow, exclusive.
public struct RoamExportRangePreset: Equatable, Identifiable {
    public enum Kind: Int, CaseIterable { case last30Days, thisYear, lastYear }
    public let kind: Kind
    public let startDate: String
    public let endDateExclusive: String
    public var id: Int { kind.rawValue }
    public static func presets(now: Date) -> [RoamExportRangePreset] {
        let today = RoamShanghaiCalendar.dayNumber(now: now)
        let end = RoamShanghaiCalendar.dateText(dayNumber: today + 1)
        let year = RoamShanghaiCalendar.civil(dayNumber: today).year
        return [.init(kind: .last30Days, startDate: RoamShanghaiCalendar.dateText(dayNumber: today - 29), endDateExclusive: end),
                .init(kind: .thisYear, startDate: String(format: "%04d-01-01", year), endDateExclusive: end),
                .init(kind: .lastYear, startDate: RoamShanghaiCalendar.dateText(dayNumber: today - 365), endDateExclusive: end)]
    }
}

public struct RoamExportRequest: Equatable {
    public let startDate: String
    public let endDateExclusive: String
    public let pageSize: Int
    public init(startDate: String, endDateExclusive: String, pageSize: Int = RoamExportContract.defaultPageSize) {
        self.startDate = startDate; self.endDateExclusive = endDateExclusive; self.pageSize = pageSize
    }
    public func validate() throws {
        guard RoamExportContract.isValidRange(start: startDate, end: endDateExclusive), (1...100).contains(pageSize) else { throw APIError.invalidRequest }
    }
    var json: Data {
        Data(RoamOrderedJSON.Value.object([("startDate", .string(startDate)), ("endDateExclusive", .string(endDateExclusive)), ("pageSize", .int(Int64(pageSize)))]).text.utf8)
    }
}

public struct RoamExportSnapshot: Equatable {
    public let snapshotID: String
    public let startDate: String
    public let endDateExclusive: String
    public let asOfMs: Int64
    public let expiresAtMs: Int64
    public let upperRecordID: String
    public let expectedRows: Int
    public let pageSize: Int

    struct Raw: Decodable {
        let format: String; let timeZone: String; let snapshotId: String; let startDate: String; let endDateExclusive: String
        let asOfMs: Int64; let expiresAtMs: Int64; let upperRecordId: String; let expectedRows: Int; let pageSize: Int
    }
    /// The client's `descriptor()` check.
    static func project(_ raw: Raw) throws -> RoamExportSnapshot {
        let hex = raw.snapshotId.utf8.count == 64 && raw.snapshotId.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
        guard raw.format == RoamExportContract.format, raw.timeZone == "Asia/Shanghai", hex,
              RoamExportContract.isValidRange(start: raw.startDate, end: raw.endDateExclusive),
              raw.asOfMs > 0, raw.asOfMs <= 9_007_199_254_740_991, raw.expiresAtMs == raw.asOfMs + RoamShanghaiCalendar.dayMilliseconds,
              RoamExportContract.decimal(raw.upperRecordId, allowZero: true), (0...1000).contains(raw.expectedRows), (1...100).contains(raw.pageSize),
              (raw.expectedRows == 0) == (raw.upperRecordId == "0") else { throw APIError.malformedResponse }
        return .init(snapshotID: raw.snapshotId, startDate: raw.startDate, endDateExclusive: raw.endDateExclusive, asOfMs: raw.asOfMs,
                     expiresAtMs: raw.expiresAtMs, upperRecordID: raw.upperRecordId, expectedRows: raw.expectedRows, pageSize: raw.pageSize)
    }
    var json: RoamOrderedJSON.Value {
        .object([("format", .string(RoamExportContract.format)), ("timeZone", .string("Asia/Shanghai")), ("snapshotId", .string(snapshotID)),
                 ("startDate", .string(startDate)), ("endDateExclusive", .string(endDateExclusive)), ("asOfMs", .int(asOfMs)),
                 ("expiresAtMs", .int(expiresAtMs)), ("upperRecordId", .string(upperRecordID)), ("expectedRows", .int(Int64(expectedRows))),
                 ("pageSize", .int(Int64(pageSize)))])
    }
    /// `chengyin-exploration-YYYYMMDD-YYYYMMDD.jsonl`
    public var fileName: String {
        "chengyin-exploration-" + startDate.replacingOccurrences(of: "-", with: "") + "-" + endDateExclusive.replacingOccurrences(of: "-", with: "") + ".jsonl"
    }
}

/// Resumable position. `changed` marks a server-reported source change: earlier parts are then incomplete.
public struct RoamExportCheckpoint: Equatable {
    public let snapshot: RoamExportSnapshot
    public let cursor: String?
    public let offset: Int
    public let lastRecordID: String?
    public let part: Int
    public let complete: Bool
    public let changed: Bool

    static func prepared(_ envelope: RoamPrivateEnvelope, request: RoamExportRequest) throws -> RoamExportCheckpoint {
        struct Raw: Decodable { let cursor: String }
        let snapshot = try RoamExportSnapshot.project(envelope.payload(RoamExportSnapshot.Raw.self))
        let cursor = try envelope.payload(Raw.self).cursor
        guard snapshot.startDate == request.startDate, snapshot.endDateExclusive == request.endDateExclusive,
              snapshot.pageSize == request.pageSize, RoamExportContract.isCursor(cursor) else { throw APIError.malformedResponse }
        return .init(snapshot: snapshot, cursor: cursor, offset: 0, lastRecordID: nil, part: 0, complete: false, changed: false)
    }
}

public struct RoamExportRecord: Equatable {
    public let recordID: String
    /// "yyyy-MM-ddTHH:mm:ss.SSS+08:00"
    public let completedAt: String
    public let routeVersion: String?
    public let elapsedSeconds: Int64?
    public let routeAvailable: Bool
    public let routeTitle: String?
    var json: RoamOrderedJSON.Value {
        .object([("type", .string("record")), ("recordId", .string(recordID)), ("completedAt", .string(completedAt)),
                 ("routeVersion", routeVersion.map { .string($0) } ?? .null), ("elapsedSeconds", elapsedSeconds.map { .int($0) } ?? .null),
                 ("routeAvailability", .string(routeAvailable ? "AVAILABLE" : "UNAVAILABLE")), ("routeTitle", routeTitle.map { .string($0) } ?? .null)])
    }
}

public struct RoamExportChunk: Equatable {
    public enum State: String { case more = "MORE", complete = "COMPLETE", sourceChanged = "SOURCE_CHANGED" }
    public let state: State
    public let items: [RoamExportRecord]
    /// Self-describing JSONL part: metadata line, records, footer. nil when the source changed.
    public let data: String?
    public let checkpoint: RoamExportCheckpoint
    public var restartRequired: Bool { state == .sourceChanged }
}

extension RoamExportChunk {
    private struct Raw: Decodable {
        struct Row: Decodable {
            let recordId: String; let completedAt: String; let routeAvailability: String
            let routeVersion: String?; let elapsedSeconds: Int64?; let routeTitle: String?
        }
        let cursor: String; let offset: Int; let items: [Row]; let complete: Bool
        let state: String; let nextCursor: String?; let emittedRows: Int
    }
    /// Strict page check against the original checkpoint (the client's `next()`); any drift is unconfirmed.
    static func decode(_ envelope: RoamPrivateEnvelope, original: RoamExportCheckpoint) throws -> RoamExportChunk {
        let snapshot = try RoamExportSnapshot.project(envelope.payload(RoamExportSnapshot.Raw.self))
        let value = try envelope.payload(Raw.self)
        guard snapshot == original.snapshot, value.cursor == original.cursor, value.offset == original.offset,
              value.items.count <= snapshot.pageSize, let state = State(rawValue: value.state) else { throw APIError.malformedResponse }
        if state == .sourceChanged {
            guard !value.complete, value.nextCursor == nil, value.items.isEmpty, value.emittedRows == original.offset else { throw APIError.malformedResponse }
            let changed = RoamExportCheckpoint(snapshot: snapshot, cursor: original.cursor, offset: original.offset, lastRecordID: original.lastRecordID,
                                               part: original.part, complete: false, changed: true)
            return .init(state: .sourceChanged, items: [], data: nil, checkpoint: changed)
        }
        var last = original.lastRecordID
        let items: [RoamExportRecord] = try value.items.map { row in
            let record = try project(row, snapshot: snapshot)
            // Strictly descending record IDs within and across chunks: no duplicates, no reordering.
            if let last, RoamExportContract.compare(record.recordID, last) >= 0 { throw APIError.malformedResponse }
            last = record.recordID
            return record
        }
        let emitted = original.offset + items.count
        guard value.emittedRows == emitted, emitted <= snapshot.expectedRows else { throw APIError.malformedResponse }
        if value.complete {
            guard state == .complete, value.nextCursor == nil, emitted == snapshot.expectedRows else { throw APIError.malformedResponse }
        } else {
            guard state == .more, let next = value.nextCursor, RoamExportContract.isCursor(next), next != original.cursor,
                  items.count == snapshot.pageSize, emitted < snapshot.expectedRows else { throw APIError.malformedResponse }
        }
        let part = original.part + 1
        let metadata = RoamOrderedJSON.Value.object([("type", .string("metadata")), ("format", .string(RoamExportContract.format)),
                                                     ("snapshot", snapshot.json), ("part", .int(Int64(part))), ("offset", .int(Int64(original.offset)))])
        let footer = RoamOrderedJSON.Value.object([("type", .string("footer")), ("part", .int(Int64(part))), ("emittedRows", .int(Int64(emitted))),
                                                   ("expectedRows", .int(Int64(snapshot.expectedRows))), ("complete", .bool(value.complete))])
        let lines = [metadata.text] + items.map(\.json.text) + [footer.text]
        let checkpoint = RoamExportCheckpoint(snapshot: snapshot, cursor: value.nextCursor, offset: emitted, lastRecordID: last,
                                              part: part, complete: value.complete, changed: false)
        return .init(state: state, items: items, data: lines.joined(separator: "\n") + "\n", checkpoint: checkpoint)
    }
    private static func project(_ row: Raw.Row, snapshot: RoamExportSnapshot) throws -> RoamExportRecord {
        guard RoamExportContract.decimal(row.recordId, allowZero: false), RoamExportContract.compare(row.recordId, snapshot.upperRecordID) <= 0,
              let completed = completedMilliseconds(row.completedAt), completed <= snapshot.asOfMs else { throw APIError.malformedResponse }
        let day = String(row.completedAt.prefix(10))
        guard day >= snapshot.startDate, day < snapshot.endDateExclusive else { throw APIError.malformedResponse }
        if let version = row.routeVersion { guard RoamExportContract.decimal(version, allowZero: true) else { throw APIError.malformedResponse } }
        if let seconds = row.elapsedSeconds { guard seconds >= 0, seconds <= 9_007_199_254_740_991 else { throw APIError.malformedResponse } }
        let available: Bool
        switch row.routeAvailability {
        case "AVAILABLE": available = true
        case "UNAVAILABLE": available = false; guard row.routeTitle == nil else { throw APIError.malformedResponse }
        default: throw APIError.malformedResponse
        }
        return .init(recordID: row.recordId, completedAt: row.completedAt, routeVersion: row.routeVersion, elapsedSeconds: row.elapsedSeconds,
                     routeAvailable: available, routeTitle: row.routeTitle)
    }
    /// "yyyy-MM-ddTHH:mm:ss.SSS+08:00" that names a real Shanghai instant.
    static func completedMilliseconds(_ text: String) -> Int64? {
        let bytes = Array(text.utf8)
        guard bytes.count == 29, bytes[10] == 84, String(decoding: bytes[23...], as: UTF8.self) == "+08:00",
              let wall = RoamShanghaiCalendar.wallTime(String(decoding: bytes[0..<23], as: UTF8.self).replacingOccurrences(of: "T", with: " "), requireMilliseconds: true),
              let day = RoamShanghaiCalendar.parseDate(String(decoding: bytes[0..<10], as: UTF8.self)),
              let seconds = Int64(String(decoding: bytes[17..<19], as: UTF8.self)),
              let millis = Int64(String(decoding: bytes[20..<23], as: UTF8.self)) else { return nil }
        let local = ((day * 24 + Int64(wall.hour)) * 60 + Int64(wall.minute)) * 60 + seconds
        return (local - Int64(RoamShanghaiCalendar.offsetSeconds)) * 1000 + millis
    }
}

/// The finished file. Offered only once every chunk was read and the content has not expired (24 h after snapshot).
public struct RoamExportFile: Equatable {
    public let fileName: String
    public let content: String
    public let expiresAtMs: Int64
    public let rows: Int
    public func isExpired(now: Date) -> Bool { Int64((now.timeIntervalSince1970 * 1000).rounded(.down)) >= expiresAtMs }
}
