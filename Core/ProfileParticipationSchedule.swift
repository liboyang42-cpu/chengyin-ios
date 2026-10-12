import Foundation

/// P117 local display only. Never decides registration, cancellation or refund eligibility.
public struct ProfileParticipationSchedule: Equatable {
    public struct Presentation: Equatable {
        public let range: String?
        public let reminderDays: Int?
    }
    private let start: Date?
    private let end: Date?
    private let range: String?
    public init(start rawStart: String?, end rawEnd: String?) {
        guard let start = OrderLifecycleTime.date(rawStart), let end = OrderLifecycleTime.date(rawEnd),
              start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              end >= start else {
            self.start = nil; self.end = nil; range = nil; return
        }
        self.start = start; self.end = end
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy.MM.dd"
        range = formatter.string(from: start) + " - " + formatter.string(from: end)
    }
    public func presentation(now: Date = Date()) -> Presentation {
        guard let start, let end, let range else { return .init(range: nil, reminderDays: nil) }
        guard now.timeIntervalSince1970.isFinite, now < start, now <= end else {
            return .init(range: range, reminderDays: nil)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.startOfDay(for: now), startDay = calendar.startOfDay(for: start)
        let days = calendar.dateComponents([.day], from: today, to: startDay).day
        let reminder = days.flatMap { (1...3).contains($0) ? $0 : nil }
        return .init(range: range, reminderDays: reminder)
    }
}
