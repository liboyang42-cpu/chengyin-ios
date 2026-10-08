import Foundation

/// P101 actItem is shared by the result list and selected map object.
/// A linked topic changes the point label, never the activity detail route or pin ID.
public struct SearchMapActivityPresentation: Equatable {
    public enum PointKind: String, Equatable { case activity, topic }
    public let activityID: Int
    public let linkedTopicID: Int?
    public let categoryNames: [String]
    public let address: String?
    public let starts: SearchMapActivityTime
    public let ends: SearchMapActivityTime
    public var pointKind: PointKind { linkedTopicID == nil ? .activity : .topic }
    public var pointLabelKey: String { "mapActivity.point." + pointKind.rawValue }
    public var primaryDestination: SearchMapDestination { .activity(activityID) }
    public var relatedDestination: SearchMapDestination? { linkedTopicID.map { .topic($0) } }

    public init(_ activity: ActivitySummary) {
        activityID = activity.id; linkedTopicID = activity.linkedTopicID
        categoryNames = activity.categoryNames
        // Source actItem displays address, not a place name relabeled as an address.
        address = Self.nonblank(activity.address)
        starts = SearchMapActivityTime(activity.startDate)
        ends = SearchMapActivityTime(activity.endDate)
    }
    private static func nonblank(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

/// PublicActivityListVO uses yyyy-MM-dd HH:mm:ss Date and ApplicationConfig pins
/// Jackson to Asia/Shanghai. Event start/end are ordinary times, not sign-up deadlines.
/// Date-only records retain their calendar day and never gain a fabricated instant.
public enum SearchMapActivityTime: Equatable {
    case calendarDay(String)
    case instant(Date)
    case unknown

    public init(_ raw: String?) {
        guard let raw else { self = .unknown; return }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil {
            let formatter = Self.formatter(format: "yyyy-MM-dd", timeZone: TimeZone(secondsFromGMT: 0)!)
            guard let date = formatter.date(from: value), formatter.string(from: date) == value else { self = .unknown; return }
            self = .calendarDay(value)
        } else if value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil,
                  let sourceZone = TimeZone(identifier: "Asia/Shanghai") {
            let formatter = Self.formatter(format: "yyyy-MM-dd HH:mm:ss", timeZone: sourceZone)
            guard let date = formatter.date(from: value), formatter.string(from: date) == value else { self = .unknown; return }
            self = .instant(date)
        } else { self = .unknown }
    }

    /// Explicit zone argument makes phone-zone changes and DST crossings testable.
    public func display(phoneTimeZone: TimeZone) -> String? {
        switch self {
        case .calendarDay(let value): return value
        case .instant(let date):
            return Self.formatter(format: "yyyy-MM-dd HH:mm:ss XXX", timeZone: phoneTimeZone).string(from: date)
        case .unknown: return nil
        }
    }
    private static func formatter(format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone; formatter.dateFormat = format; formatter.isLenient = false
        return formatter
    }
}
