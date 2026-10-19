import Foundation

/// Mini pages/club/event-ops section order. Display only; every read and write keeps its own permission check.
public enum ClubOpsEventSection: String, CaseIterable, Hashable {
    case occurrence, roster, series, recurrence, capacity
}

public struct ClubOpsEventAccess: Equatable {
    public let scope: ClubGovernanceScope
    public let canManage: Bool
    public let canCheckin: Bool
    public init(permissions: ClubGovernancePermissions?, scope: ClubGovernanceScope) {
        self.scope = scope
        // Mini: manage comes from the club permission list; check-in only exists for one activity.
        canManage = permissions?.allows("club:activity:manage", scope: .init(clubID: scope.clubID)) == true
        canCheckin = (scope.activityID ?? 0) > 0 && permissions?.allows("club:event:checkin", scope: scope) == true
    }
    public var permitted: Bool { canManage || canCheckin }
    public var sections: [ClubOpsEventSection] {
        var result: [ClubOpsEventSection] = []
        if canManage && (scope.activityID ?? 0) > 0 { result.append(.occurrence) }
        if canCheckin { result.append(.roster) }
        if canManage { result += [.series, .recurrence, .capacity] }
        return result
    }
    /// Mini: "本场名册 · 仅核销权限可见" when the roster section is absent for a manager.
    public var rosterHiddenForManager: Bool { canManage && (scope.activityID ?? 0) > 0 && !canCheckin }
    /// E-07: a focused topic is moved first; no other topic is hidden.
    public static func focusFirst(_ rows: [ClubGovernanceValue], topicID: Int?) -> [ClubGovernanceValue] {
        guard let topicID, topicID > 0 else { return rows }
        return rows.filter { $0["id"].int == topicID } + rows.filter { $0["id"].int != topicID }
    }
}

/// Fixed Asia/Shanghai display clock, matching mini utils/datetime.js chinaParts.
public enum ClubOpsEventClock {
    public static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!
    static func isChinese(_ locale: Locale) -> Bool { locale.identifier.lowercased().hasPrefix("zh") }
    static func parts(_ date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar.dateComponents([.month, .day, .weekday, .hour, .minute], from: date)
    }
    static func pad(_ value: Int?) -> String { let number = value ?? 0; return number < 10 ? "0\(number)" : String(number) }
    static func localized(_ date: Date, template: String, locale: Locale) -> String {
        let formatter = DateFormatter(); formatter.locale = locale
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        formatter.calendar = calendar; formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
    /// "M月d日 周X HH:mm" (zh) or the locale's month/day/weekday/24h time.
    public static func occurrenceText(_ value: ClubGovernanceValue, locale: Locale) -> String? {
        guard let date = ClubOccurrenceClock.instant(value) else { return nil }
        guard isChinese(locale) else { return localized(date, template: "MMMdEEEHHmm", locale: locale) }
        let p = parts(date), week = ["日", "一", "二", "三", "四", "五", "六"]
        let weekday = week[max(0, min(6, (p.weekday ?? 1) - 1))]
        return "\(p.month ?? 0)月\(p.day ?? 0)日 周\(weekday) \(pad(p.hour)):\(pad(p.minute))"
    }
    /// "M月d日 HH:mm" (zh) or the locale's month/day/24h time.
    public static func momentText(_ raw: String?, locale: Locale) -> String? {
        guard let raw, let date = ClubOccurrenceClock.instant(.string(raw)) else { return nil }
        guard isChinese(locale) else { return localized(date, template: "MMMdHHmm", locale: locale) }
        let p = parts(date)
        return "\(p.month ?? 0)月\(p.day ?? 0)日 \(pad(p.hour)):\(pad(p.minute))"
    }
    /// Mini correctionWindowText range; nil when neither bound parses.
    public static func correctionRange(start: String?, end: String?, locale: Locale) -> String? {
        let from = momentText(start, locale: locale), to = momentText(end, locale: locale)
        if let from, let to { return from + " – " + to }
        return from ?? to
    }
}

public enum ClubOpsEventAttendance {
    /// Mini: "标记到场" on registered/noShow sends arrived=true; "更正未到" on arrived sends false; waitlist has none.
    public static func arrivedTarget(_ bucket: ClubRosterBucket) -> Bool? {
        switch bucket { case .registered, .noShow: return true; case .arrived: return false; case .waitlist: return nil }
    }
}

public enum ClubOpsEventOccurrenceBadge: Equatable { case cancelled, editable, lockReason(String), locked }
public enum ClubOpsEventOccurrenceMeta: Equatable { case refunded(Int), cancelled, signupsPending, noSignups, signups(Int, locked: Bool) }
/// Mini occurrenceRow: unknown counts never read as zero and never as editable.
public struct ClubOpsEventOccurrenceCopy: Equatable {
    public let badge: ClubOpsEventOccurrenceBadge
    public let meta: ClubOpsEventOccurrenceMeta
    public init(row: ClubSeriesOccurrenceRow) {
        let editable = row.editable == true
        if row.cancelled { badge = .cancelled }
        else if editable { badge = .editable }
        else if let reason = row.lockReason { badge = .lockReason(reason) }
        else { badge = .locked }
        if row.cancelled { meta = row.refundedCount.map { .refunded($0) } ?? .cancelled }
        else if let count = row.signupCount { meta = count == 0 ? .noSignups : .signups(count, locked: !editable) }
        else { meta = .signupsPending }
    }
}

public enum ClubOpsEventSeriesSuffix: Equatable {
    case firstDate(month: Int, day: Int), topic(Int), series(Int)
}
public struct ClubOpsEventSeriesRow: Equatable, Identifiable {
    public let id: Int
    public let topicID: Int
    public let topicName: String?
    public let recurrence: String
    public let waitlistEnabled: Bool?
    public internal(set) var suffix: [ClubOpsEventSeriesSuffix] = []
}
/// Mini decorateSeriesRows: only colliding labels deepen, first date → topic → series id.
public struct ClubOpsEventSeriesList: Equatable {
    public let rows: [ClubOpsEventSeriesRow]
    public init(value: ClubGovernanceValue, topicNames: [Int: String] = [:]) {
        let base: [(ClubOpsEventSeriesRow, String?)] = (value.array ?? []).compactMap { row in
            guard let id = row["id"].int, id > 0, let topic = row["topicId"].int, topic > 0 else { return nil }
            let name = topicNames[topic]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = (row["futureDates"].array ?? []).compactMap(\.string)
                .filter { $0.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil }.sorted().first
            return (ClubOpsEventSeriesRow(id: id, topicID: topic, topicName: name?.isEmpty == false ? name : nil,
                                          recurrence: row["recurrenceType"].string ?? "", waitlistEnabled: row["waitlistEnabled"].bool), first)
        }
        func label(_ row: ClubOpsEventSeriesRow) -> String {
            (row.topicName ?? "#\(row.topicID)") + "|" + row.recurrence + "|" + row.suffix.map { "\($0)" }.joined(separator: ",")
        }
        func unique(_ list: [ClubOpsEventSeriesRow]) -> Bool { Set(list.map(label)).count == list.count }
        let plain = base.map(\.0)
        guard !unique(plain) else { rows = plain; return }
        var counts: [String: Int] = [:]
        for row in plain { counts[label(row), default: 0] += 1 }
        let levels: [(ClubOpsEventSeriesRow, String?) -> ClubOpsEventSeriesSuffix?] = [
            { _, first in
                guard let first, let month = Int(first.dropFirst(5).prefix(2)), let day = Int(first.suffix(2)) else { return nil }
                return .firstDate(month: month, day: day)
            },
            { row, _ in .topic(row.topicID) },
            { row, _ in .series(row.id) }
        ]
        for depth in 0..<levels.count {
            let suffixed: [ClubOpsEventSeriesRow] = base.map { item in
                var row = item.0
                guard counts[label(row)] ?? 0 > 1 else { return row }
                var parts: [ClubOpsEventSeriesSuffix] = []
                for level in levels[0...depth] { if let part = level(item.0, item.1), !parts.contains(part) { parts.append(part) } }
                row.suffix = parts
                return row
            }
            if unique(suffixed) { rows = suffixed; return }
        }
        rows = plain
    }
}

public enum ClubOpsEventOccurrenceState: Equatable { case active, cancelled(reason: String?) }
public enum ClubOpsEventRefundSummary: String, Equatable { case notRequired, manualReview, acceptedWithManualReview, accepted, pending }
public enum ClubOpsEventNotificationSummary: String, Equatable { case notRequired, queued }
public enum ClubOpsEventCancellation {
    /// Mini normalizeCancellationState: any contradiction fails closed (nil = not shown as either state).
    public static func state(_ value: ClubGovernanceValue, activityID: Int?) -> ClubOpsEventOccurrenceState? {
        guard let activityID, activityID > 0, value["activityId"].int == activityID,
              let cancelled = value["activityCancelled"].bool, case .integer(let publish) = value["publishStatus"] else { return nil }
        switch value["occurrenceStatus"].string {
        case "CANCELLED":
            guard cancelled, publish == 0 else { return nil }
            let reason = value["cancelReason"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .cancelled(reason: reason?.isEmpty == false ? reason : nil)
        case "ACTIVE":
            guard !cancelled, publish == 1 else { return nil }
            return .active
        default: return nil
        }
    }
    public static func refund(_ receipt: ClubGovernanceValue) -> ClubOpsEventRefundSummary {
        switch receipt["refundStatus"].string ?? "" {
        case "NOT_REQUIRED": return .notRequired
        case "MANUAL_REVIEW_REQUIRED": return .manualReview
        case "ACCEPTED_WITH_MANUAL_REVIEW": return .acceptedWithManualReview
        case "ACCEPTED", "REFUND_REQUESTED", "ALREADY_ACCEPTED": return .accepted
        default: return .pending
        }
    }
    public static func notifications(_ receipt: ClubGovernanceValue) -> ClubOpsEventNotificationSummary {
        receipt["registeredNotificationStatus"].string == "NOT_REQUIRED" && receipt["waitlistNotificationStatus"].string == "NOT_REQUIRED" ? .notRequired : .queued
    }
}

/// Field-specific copies of the authoritative command ranges (the command still validates).
public enum ClubOpsEventInput {
    static func trimmed(_ raw: String) -> String { raw.trimmingCharacters(in: .whitespacesAndNewlines) }
    public static func capacityInvalid(_ raw: String) -> Bool {
        let text = trimmed(raw); guard !text.isEmpty else { return false }
        guard let value = Int(text) else { return true }; return !(1...10000).contains(value)
    }
    public static func offerInvalid(_ raw: String) -> Bool {
        guard let value = Int(trimmed(raw)) else { return true }; return !(5...1440).contains(value)
    }
    public static func cancelReasonInvalid(_ raw: String) -> Bool { !(2...255).contains(trimmed(raw).utf16.count) }
    public static func correctionReasonInvalid(_ raw: String) -> Bool { trimmed(raw).utf16.count < 2 }
}
