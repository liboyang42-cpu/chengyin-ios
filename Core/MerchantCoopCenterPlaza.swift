import Foundation

/// Source pages/merchant/coop-center: tabs 官方活动 / 广场, default 广场; `tab=official` selects the other.
public enum MerchantCoopCenterTab: String, CaseIterable, Identifiable, Equatable {
    case official, plaza
    public var id: String { rawValue }
    public init(sourceTab: String?) { self = sourceTab == "official" ? .official : .plaza }
}

public enum MerchantCoopCenterFailure: Error, Equatable { case malformed }

public struct MerchantCoopCenterMonthDay: Equatable, Hashable {
    public let month: Int, day: Int
    public init(month: Int, day: Int) { self.month = month; self.day = day }
}

/// Mirrors utils/datetime.js toTimestamp + chinaParts: strict instants, China (+08:00) calendar.
public enum MerchantCoopCenterTime {
    static let chinaOffset: Int64 = 8 * 3600
    private static let maxMilliseconds = 8_640_000_000_000_000.0
    public static func instant(_ value: MerchantContentValue) -> Date? {
        switch value {
        case .integer(let v):
            guard v != 0 else { return nil }
            return milliseconds(Double(v) * (v > 0 && String(v).count == 10 ? 1000 : 1))
        case .decimal(let d):
            let n = NSDecimalNumber(decimal: d).doubleValue
            guard n.isFinite, n != 0 else { return nil }
            let tenDigitSeconds = n >= 1_000_000_000 && n < 10_000_000_000 && n.rounded() == n
            return milliseconds(tenDigitSeconds ? n * 1000 : n)
        case .string(let raw): return instant(text: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }
    public static func monthDay(_ date: Date) -> MerchantCoopCenterMonthDay {
        let seconds = Int64((date.timeIntervalSince1970).rounded(.down)) + chinaOffset
        let days = seconds >= 0 ? seconds / 86_400 : -((-seconds + 86_399) / 86_400)
        let civil = civilFromDays(days)
        return .init(month: civil.month, day: civil.day)
    }
    private static func milliseconds(_ ms: Double) -> Date? {
        guard ms.isFinite, abs(ms) <= maxMilliseconds else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
    private static func groups(_ pattern: String, _ text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
    private static func instant(text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        if groups(#"^\d{10}$"#, text) != nil, let n = Double(text) { return milliseconds(n * 1000) }
        if groups(#"^\d{13}$"#, text) != nil, let n = Double(text) { return milliseconds(n) }
        if groups(#"([zZ]|[+-]\d\d:?\d\d)$"#, text) != nil {
            guard let g = groups(#"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?(Z|[+-]\d\d:?\d\d)$"#, text),
                  let fields = civil(g), let zone = g[7], let offset = offsetSeconds(zone) else { return nil }
            return milliseconds(Double(epochSeconds(fields) - offset) * 1000)
        }
        guard let g = groups(#"^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.\d{1,9})?)?)?$"#, text),
              let fields = civil(g) else { return nil }
        return milliseconds(Double(epochSeconds(fields) - chinaOffset) * 1000)
    }
    private struct Civil { let year: Int64, month: Int, day: Int, hour: Int, minute: Int, second: Int }
    private static func civil(_ g: [String?]) -> Civil? {
        func n(_ i: Int) -> Int? { g.indices.contains(i) ? g[i].flatMap { Int($0) } : nil }
        guard let y = n(1), let mo = n(2), let d = n(3) else { return nil }
        let h = n(4) ?? 0, mi = n(5) ?? 0, s = n(6) ?? 0
        guard (1...12).contains(mo) else { return nil }
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        let maxDay = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mo - 1]
        guard (1...maxDay).contains(d), (0...23).contains(h), (0...59).contains(mi), (0...59).contains(s) else { return nil }
        return Civil(year: Int64(y), month: mo, day: d, hour: h, minute: mi, second: s)
    }
    private static func offsetSeconds(_ zone: String) -> Int64? {
        if zone.uppercased() == "Z" { return 0 }
        let digits = zone.dropFirst().filter { $0 != ":" }
        guard digits.count == 4, let hh = Int64(digits.prefix(2)), let mm = Int64(digits.suffix(2)) else { return nil }
        return (zone.hasPrefix("-") ? -1 : 1) * (hh * 3600 + mm * 60)
    }
    private static func epochSeconds(_ c: Civil) -> Int64 {
        daysFromCivil(year: c.year, month: Int64(c.month), day: Int64(c.day)) * 86_400
            + Int64(c.hour * 3600 + c.minute * 60 + c.second)
    }
    // Howard Hinnant's proleptic Gregorian conversions; independent of the device time zone.
    private static func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
    private static func civilFromDays(_ value: Int64) -> (month: Int, day: Int) {
        let z = value + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (Int(month), Int(day))
    }
}

/// One plaza route card (稿 234:276). Display facts only; never an application or acceptance.
public struct MerchantCoopCenterRoute: Equatable, Identifiable {
    public enum Mode: Equatable { case cityOrienteering, freeExploration }
    public enum TermsMode: String, CaseIterable, Equatable { case perk = "PERK", revshare = "REVSHARE", traffic = "TRAFFIC" }
    public enum Terms: Equatable {
        case none
        /// `amount` is the published floor (PERK perkMinValue) or ceiling (REVSHARE maxPerHeadFee).
        case single(TermsMode, amount: String?)
        case mixed([TermsMode])
    }
    public enum Deadline: Equatable { case open(MerchantCoopCenterMonthDay), closed }
    public enum Seat: Equatable { case full, remaining(String, tight: Bool) }
    public let id: String
    /// Positive numeric topic id for the chapter-recruitment detail; nil keeps 看详情 inert.
    public let topicID: Int?
    public let title: String
    public let cover: String?
    public let mode: Mode?
    public let start: MerchantCoopCenterMonthDay?
    public let end: MerchantCoopCenterMonthDay?
    public let city: String?
    public let stationCount: String?
    public let terms: Terms
    public let deadline: Deadline?
    public let seat: Seat?
    /// Source: `start && end && start !== end ? start – end : start`.
    public var dateRange: (MerchantCoopCenterMonthDay, MerchantCoopCenterMonthDay?)? {
        guard let start else { return nil }
        if let end, end != start { return (start, end) }
        return (start, nil)
    }

    /// Returns nil when the source would drop the item (`id` or `name` missing).
    public init?(_ item: MerchantContentValue, now: Date) {
        guard item.object != nil, let id = Self.present(item["id"]), let title = Self.present(item["name"]) else { return nil }
        self.id = id
        topicID = item["id"].integer.flatMap { $0 > 0 ? $0 : nil }
            ?? Int(id.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0 > 0 ? $0 : nil }
        self.title = title
        cover = item["imgUrl"].text.flatMap { $0.isEmpty ? nil : $0 }
        switch Self.number(item["productType"]) { case 1: mode = .cityOrienteering; case 2: mode = .freeExploration; default: mode = nil }
        start = MerchantCoopCenterTime.instant(item["startDate"]).map(MerchantCoopCenterTime.monthDay)
        end = MerchantCoopCenterTime.instant(item["endDate"]).map(MerchantCoopCenterTime.monthDay)
        city = Self.present(item["cityKeyword"])
        stationCount = Self.truthy(item["locationCount"])
        let modes = (item["termsModes"].array ?? []).compactMap { $0.text.flatMap(TermsMode.init(rawValue:)) }
        if modes.count == 1, let mode = modes.first {
            switch mode {
            case .perk: terms = .single(.perk, amount: Self.amount(item["perkMinValue"]))
            case .revshare: terms = .single(.revshare, amount: Self.amount(item["maxPerHeadFee"]))
            case .traffic: terms = .single(.traffic, amount: nil)
            }
        } else { terms = modes.isEmpty ? .none : .mixed(modes) }
        let primary = item["recruitDeadline"]
        let deadlineSource = Self.falsy(primary) ? item["merchantSignUpEndDate"] : primary
        if let instant = MerchantCoopCenterTime.instant(deadlineSource) {
            deadline = instant > now ? .open(MerchantCoopCenterTime.monthDay(instant)) : .closed
        } else { deadline = nil }
        if let remaining = Self.decimal(item["remainingMerchantCount"]) {
            seat = remaining <= 0 ? .full : .remaining(NSDecimalNumber(decimal: remaining).stringValue, tight: remaining == 1)
        } else { seat = nil }
    }
    /// Source hasValue: non-blank string or number, shown as sent.
    static func present(_ value: MerchantContentValue) -> String? {
        switch value {
        case .string(let v): return v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : v
        case .integer, .decimal: return value.display
        default: return nil
        }
    }
    private static func truthy(_ value: MerchantContentValue) -> String? {
        switch value {
        case .string(let v): return v.isEmpty ? nil : v
        case .integer(let v): return v == 0 ? nil : String(v)
        case .decimal(let v): return v == 0 ? nil : value.display
        default: return nil
        }
    }
    private static func falsy(_ value: MerchantContentValue) -> Bool {
        switch value {
        case .null: return true
        case .string(let v): return v.isEmpty
        case .integer(let v): return v == 0
        case .decimal(let v): return v == 0
        case .bool(let v): return !v
        default: return false
        }
    }
    /// Source `value != null` → printed as sent.
    private static func amount(_ value: MerchantContentValue) -> String? {
        switch value {
        case .string(let v): return v
        case .integer, .decimal: return value.display
        default: return nil
        }
    }
    private static func number(_ value: MerchantContentValue) -> Int? {
        switch value {
        case .integer(let v): return v
        case .string(let v): return Int(v.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }
    /// Strict finite number (integer, decimal or numeric string); everything else is absent.
    static func decimal(_ value: MerchantContentValue) -> Decimal? {
        switch value {
        case .integer(let v): return Decimal(v)
        case .decimal(let v): return v
        case .string(let raw):
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty, v.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil else { return nil }
            return Decimal(string: v, locale: Locale(identifier: "en_US_POSIX"))
        default: return nil
        }
    }
}

/// marketing-home projection with the source normalizeMarketingHome contract.
public struct MerchantCoopCenterPlaza: Equatable {
    public struct Scope: Equatable { public let openCount: Int, shownCount: Int }
    public let routes: [MerchantCoopCenterRoute]
    /// Present only when the server says open opportunities were truncated (CU-M-133).
    public let scope: Scope?
    public init(home: MerchantContentValue, now: Date) throws {
        let recruiting = home["recruiting"], coupons = home["coupons"], content = home["content"]
        guard home.object != nil, recruiting.object != nil, coupons.object != nil, content.object != nil,
              let items = recruiting["items"].array,
              Self.hasCount(recruiting, "count"),
              Self.hasCount(coupons, "couponCount"), Self.hasCount(coupons, "received"), Self.hasCount(coupons, "verified"),
              Self.hasCount(content, "topicCount"), Self.hasCount(content, "freeExploreCount"), Self.hasCount(content, "activityCount")
        else { throw MerchantCoopCenterFailure.malformed }
        routes = items.compactMap { MerchantCoopCenterRoute($0, now: now) }
        if recruiting["hasMoreOpen"] == .bool(true) {
            let open = Self.hasCount(recruiting, "openCount") ? Self.count(recruiting["openCount"]) : Self.count(recruiting["count"])
            let shown = Self.hasCount(recruiting, "shownCount") ? Self.count(recruiting["shownCount"]) : items.count
            scope = .init(openCount: open, shownCount: shown)
        } else { scope = nil }
    }
    static func hasCount(_ source: MerchantContentValue, _ key: String) -> Bool {
        guard let object = source.object, let value = object[key] else { return false }
        if case .bool = value { return true }
        guard let n = MerchantCoopCenterRoute.decimal(value) else { return false }
        return n >= 0
    }
    static func count(_ value: MerchantContentValue) -> Int {
        if case .bool(let v) = value { return v ? 1 : 0 }
        guard let n = MerchantCoopCenterRoute.decimal(value), n >= 0 else { return 0 }
        var source = n, rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .down)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
