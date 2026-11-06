import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mini-program subpackageTools/capsule, exploration-goals and exploration-export: owner-only private records.
/// Nothing here persists private content; pending requests live only in the session-scoped reader's memory.
public extension RoamShanghaiCalendar {
    static let dayMilliseconds: Int64 = 86_400_000
    /// Days since 1970-01-01 on the Asia/Shanghai wall clock.
    static func dayNumber(atMilliseconds ms: Int64) -> Int64 {
        let shifted = ms + Int64(offsetSeconds) * 1000
        return shifted >= 0 ? shifted / dayMilliseconds : (shifted - dayMilliseconds + 1) / dayMilliseconds
    }
    static func dayNumber(now: Date) -> Int64 { dayNumber(atMilliseconds: Int64((now.timeIntervalSince1970 * 1000).rounded(.down))) }
    /// Civil date for a day number (Howard Hinnant's days-to-civil), avoiding locale and calendar settings.
    static func civil(dayNumber: Int64) -> Day {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return Day(year: Int(yoe + era * 400 + (month <= 2 ? 1 : 0)), month: Int(month), day: Int(day))
    }
    static func dayNumber(year: Int, month: Int, day: Int) -> Int64 {
        let y = Int64(month <= 2 ? year - 1 : year)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let m = Int64(month)
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + Int64(day) - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
    static func dateText(dayNumber: Int64) -> String {
        let value = civil(dayNumber: dayNumber)
        return String(format: "%04d-%02d-%02d", value.year, value.month, value.day)
    }
    static func dateText(atMilliseconds ms: Int64) -> String { dateText(dayNumber: dayNumber(atMilliseconds: ms)) }
    /// Strict "yyyy-MM-dd" that round-trips through the civil calendar.
    static func parseDate(_ text: String) -> Int64? {
        let bytes = Array(text.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(text.prefix(4)), let month = Int(text.dropFirst(5).prefix(2)), let day = Int(text.suffix(2)),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        let number = dayNumber(year: year, month: month, day: day)
        return dateText(dayNumber: number) == text ? number : nil
    }
    /// Monday = 0 … Sunday = 6. 1970-01-01 was a Thursday.
    static func mondayIndex(dayNumber: Int64) -> Int64 { ((dayNumber + 3) % 7 + 7) % 7 }
}

/// Server request IDs share the mini-program grammar `[A-Za-z0-9_-]{16,64}`.
public enum RoamPrivateRequestID {
    public static func isValid(_ value: String) -> Bool {
        (16...64).contains(value.utf8.count) && value.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 95 }
    }
    /// One identifier per explicit review; the same value is reused for readback and exact retry.
    public static func make() -> String { "ios_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
    static func isCanonicalID(_ value: String) -> Bool {
        guard let first = value.utf8.first, first != 48, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return false }
        return value.utf8.count < 19 || (value.utf8.count == 19 && value <= "9223372036854775807")
    }
}

/// Write outcome classes. `rejected` means the server refused before applying; anything else stays unconfirmed.
public enum RoamPrivateWriteError: Error, Equatable {
    case rejected(String?)
    case outcomeUnknown
    case writesDisabled
    /// A different draft was offered while an earlier request is unconfirmed.
    case pendingMismatch
    case changedContext
    case invalidDraft
}

/// Minimal JSON writer with the mini-program's `JSON.stringify` byte layout (ordered keys, no spaces).
enum RoamOrderedJSON {
    indirect enum Value: Equatable {
        case string(String), int(Int64), bool(Bool), null, object([(String, Value)]), array([Value])
        static func == (lhs: Value, rhs: Value) -> Bool { lhs.text == rhs.text }
        var text: String {
            switch self {
            case .string(let value): return RoamOrderedJSON.quote(value)
            case .int(let value): return String(value)
            case .bool(let value): return value ? "true" : "false"
            case .null: return "null"
            case .object(let pairs): return "{" + pairs.map { RoamOrderedJSON.quote($0.0) + ":" + $0.1.text }.joined(separator: ",") + "}"
            case .array(let values): return "[" + values.map(\.text).joined(separator: ",") + "]"
            }
        }
    }
    static func quote(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }
}

/// Envelope `{code,msg,data}` of the archive AjaxResult. `data` stays raw so each contract decodes strictly.
struct RoamPrivateEnvelope {
    let code: Int
    let message: String?
    let raw: Data
    let hasData: Bool
    static func parse(_ data: Data) throws -> RoamPrivateEnvelope {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? Int else { throw APIError.malformedResponse }
        let payload = object["data"]
        let present = payload != nil && !(payload is NSNull)
        return .init(code: code, message: object["msg"] as? String, raw: data, hasData: present)
    }
    func payload<T: Decodable>(_ type: T.Type) throws -> T {
        do { return try JSONDecoder().decode(RoamPrivateDataWrapper<T>.self, from: raw).data } catch { throw APIError.malformedResponse }
    }
}
private struct RoamPrivateDataWrapper<T: Decodable>: Decodable { let data: T }

// MARK: 时光胶囊 — api/capsules/*

public enum RoamCapsuleState: String, Equatable { case locked = "LOCKED", open = "OPEN", deleted = "DELETED" }

public struct RoamCapsule: Equatable, Identifiable {
    public let id: String
    public let state: RoamCapsuleState
    public let unlockAtMs: Int64?
    public let createdAtMs: Int64?
    /// Only an OPEN capsule carries its body and signed photo URL; LOCKED and DELETED never do.
    public let body: String?
    public let photoURL: String?
    public var unlockDateText: String? { unlockAtMs.map(RoamShanghaiCalendar.dateText(atMilliseconds:)) }
    public var createdDateText: String? { createdAtMs.map(RoamShanghaiCalendar.dateText(atMilliseconds:)) }
    /// Ceiling days until unlock, never negative (mini-program `daysLeft`).
    public func daysLeft(now: Date) -> Int {
        guard let unlockAtMs else { return 0 }
        let remaining = unlockAtMs - Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        guard remaining > 0 else { return 0 }
        return Int((remaining + RoamShanghaiCalendar.dayMilliseconds - 1) / RoamShanghaiCalendar.dayMilliseconds)
    }

    struct Raw: Decodable {
        let id: RoamToolID; let state: String
        let unlockAtMs: Int64?; let createdAtMs: Int64?
        let body: String?; let photoUrl: String?
    }
    /// The mini-program `redact`: unknown states are unconfirmed; content is dropped unless OPEN.
    static func project(_ raw: Raw) throws -> RoamCapsule {
        guard let state = RoamCapsuleState(rawValue: raw.state) else { throw APIError.malformedResponse }
        let open = state == .open
        return .init(id: raw.id.text, state: state, unlockAtMs: raw.unlockAtMs, createdAtMs: raw.createdAtMs,
                     body: open ? raw.body : nil, photoURL: open ? raw.photoUrl.flatMap { $0.isEmpty ? nil : $0 } : nil)
    }
    static func decode(_ envelope: RoamPrivateEnvelope) throws -> RoamCapsule { try project(envelope.payload(Raw.self)) }
}

public struct RoamCapsulePage: Equatable {
    public static let limit = 20
    public let items: [RoamCapsule]
    public let hasMore: Bool
    public let nextBeforeID: String?
    static func decode(_ envelope: RoamPrivateEnvelope) throws -> RoamCapsulePage {
        struct Raw: Decodable { let items: [RoamCapsule.Raw]; let hasMore: Bool; let nextBeforeId: RoamToolID? }
        let value = try envelope.payload(Raw.self)
        guard value.items.count <= limit, value.hasMore == (value.nextBeforeId != nil), !value.hasMore || !value.items.isEmpty else { throw APIError.malformedResponse }
        let items = try value.items.map(RoamCapsule.project)
        guard Set(items.map(\.id)).count == items.count else { throw APIError.malformedResponse }
        return .init(items: items, hasMore: value.hasMore, nextBeforeID: value.nextBeforeId?.text)
    }
}

/// Unlock presets of the mini-program composer; dates are Shanghai calendar days.
public struct RoamCapsuleUnlockOption: Equatable, Identifiable {
    public enum Preset: Int, CaseIterable { case month = 30, halfYear = 182, year = 365 }
    public let preset: Preset
    public let date: String
    public var id: Int { preset.rawValue }
    public static func options(now: Date) -> [RoamCapsuleUnlockOption] {
        let ms = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        return Preset.allCases.map { .init(preset: $0, date: RoamShanghaiCalendar.dateText(atMilliseconds: ms + Int64($0.rawValue) * RoamShanghaiCalendar.dayMilliseconds)) }
    }
    /// Earliest selectable custom day: tomorrow in Shanghai.
    public static func minimumDate(now: Date) -> String { RoamShanghaiCalendar.dateText(dayNumber: RoamShanghaiCalendar.dayNumber(now: now) + 1) }
}

public struct RoamCapsuleDraft: Equatable {
    public static let bodyLimit = 4000
    public let requestID: String
    public let body: String
    /// Always empty on iOS until a reviewed owner-photo upload exists; the field is kept for the wire contract.
    public let photoURL: String
    public let unlockDate: String
    public init(requestID: String = RoamPrivateRequestID.make(), body: String, photoURL: String = "", unlockDate: String) {
        self.requestID = requestID; self.body = body; self.photoURL = photoURL; self.unlockDate = unlockDate
    }
    /// Server rules: text ≤ 4000, some content, a valid day after today and within ten years (3660 days).
    public func validate(now: Date) throws {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RoamPrivateRequestID.isValid(requestID), !trimmed.isEmpty, trimmed.utf16.count <= Self.bodyLimit,
              photoURL.utf16.count <= 4096, let day = RoamShanghaiCalendar.parseDate(unlockDate) else { throw RoamPrivateWriteError.invalidDraft }
        let today = RoamShanghaiCalendar.dayNumber(now: now)
        guard day > today, day <= today + 3660 else { throw RoamPrivateWriteError.invalidDraft }
    }
    var json: Data {
        Data(RoamOrderedJSON.Value.object([("requestId", .string(requestID)), ("body", .string(body)), ("photoUrl", .string(photoURL)), ("unlockDate", .string(unlockDate))]).text.utf8)
    }
}
