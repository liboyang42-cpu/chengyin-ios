import Foundation

/// Namespaced identity prevents an activity and a route sharing an integer from colliding.
public enum HomeFeedDestination: Hashable { case activity(Int), topic(Int) }
public enum HomeFeedKind: String, CaseIterable, Hashable { case topics, activities }
public enum HomeFeedSection: String, CaseIterable, Hashable { case recommended, nearby, upcoming }
public struct HomeFeedQuery: Hashable {
    public var kind: HomeFeedKind
    public var keyword: String
    public var categoryID: Int?
    public var pageSize: Int
    public init(kind: HomeFeedKind = .topics, keyword: String = "", categoryID: Int? = nil, pageSize: Int = 10) {
        self.kind = kind; self.keyword = keyword; self.categoryID = categoryID; self.pageSize = pageSize
    }
}
public enum HomeFeedItem: Equatable, Identifiable {
    case activity(ActivitySummary), topic(TopicSummary)
    public var id: HomeFeedDestination {
        switch self { case .activity(let a): return .activity(a.id); case .topic(let t): return .topic(t.id) }
    }
    public var name: String { switch self { case .activity(let a): return a.name; case .topic(let t): return t.name } }
    public var imageURL: String? { switch self { case .activity(let a): return a.imageURL; case .topic(let t): return t.imageURL } }
    public var introduction: String? { switch self { case .activity(let a): return a.description; case .topic(let t): return t.introduction } }
    public var amount: Decimal? { switch self { case .activity(let a): return a.minimumAmount; case .topic(let t): return t.minimumAmount } }
    /// These verified list contracts provide no currency. Never derive it from device locale.
    public var currencyCode: String? { nil }
    public var startDate: String? { switch self { case .activity(let a): return a.startDate; case .topic(let t): return t.startDate } }
    public var place: String? {
        switch self { case .activity(let a): return homeFeedNonempty(a.addressName) ?? homeFeedNonempty(a.address)
        case .topic(let t): return homeFeedNonempty(t.addressName) }
    }
    public var isBeta: Bool { if case .topic(let t) = self { return t.betaFlag == 1 }; return false }
    public func isLive(at now: Date, sourceTimeZone: TimeZone? = nil) -> Bool {
        guard case .activity = self, let start = HomeFeedDate.parse(startDate, sourceTimeZone: sourceTimeZone) else { return false }
        return start <= now
    }
}
public struct HomeFeedPage: Equatable {
    public let items: [HomeFeedItem]
    public let number: Int
    public let size: Int
    public var hasMore: Bool { items.count >= size }
    public init(items: [HomeFeedItem], number: Int, size: Int) { self.items = items; self.number = number; self.size = size }
}
public struct HomeFeedPagination {
    public private(set) var items: [HomeFeedItem] = []
    public private(set) var nextPage = 1
    public private(set) var hasMore = true
    public init() {}
    public mutating func accept(_ page: HomeFeedPage) throws {
        guard page.number == nextPage, page.size > 0 else { throw APIError.invalidRequest }
        var seen = Set(items.map(\.id))
        items += page.items.filter { seen.insert($0.id).inserted }
        hasMore = page.hasMore && nextPage < Int.max
        if nextPage < Int.max { nextPage += 1 }
    }
}
private func homeFeedNonempty(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return value
}

/// Matches the retained home_activity_live.dart wire contract, including strict calendar checks.
public enum HomeFeedDate {
    public static func parse(_ raw: String?, sourceTimeZone: TimeZone? = nil) -> Date? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"^(\d{10}|\d{13})$"#, options: .regularExpression) != nil,
           let number = Double(text), number > 0 {
            return Date(timeIntervalSince1970: text.count == 13 ? number / 1000 : number)
        }
        let pattern = #"^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2})(\.\d{1,9})?)?)?([zZ]|[+-]\d{2}:?\d{2})?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String? { Range(match.range(at: i), in: text).map { String(text[$0]) } }
        let values = (1...6).map { Int(group($0) ?? "0") ?? 0 }
        var offset: Int?
        if let zone = group(8) {
            guard group(4) != nil else { return nil }
            if zone.lowercased() == "z" { offset = 0 }
            else {
                let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
                guard let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)), hours <= 23, minutes <= 59 else { return nil }
                offset = (hours * 3600 + minutes * 60) * (zone.first == "-" ? -1 : 1)
            }
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: values[0], month: values[1], day: values[2], hour: values[3], minute: values[4], second: values[5])
        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard check.year == values[0], check.month == values[1], check.day == values[2], check.hour == values[3], check.minute == values[4], check.second == values[5] else { return nil }
        if let offset { return date.addingTimeInterval(-Double(offset) + (Double(group(7) ?? "0") ?? 0)) }
        guard let sourceTimeZone else { return nil }
        calendar.timeZone = sourceTimeZone
        guard let localDate = calendar.date(from: components) else { return nil }
        let localCheck = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: localDate)
        guard localCheck.year == values[0], localCheck.month == values[1], localCheck.day == values[2], localCheck.hour == values[3], localCheck.minute == values[4], localCheck.second == values[5] else { return nil }
        return localDate
    }
}
