import Foundation

/// Presentation-only precision. A calendar day does not imply a recorded midnight.
public struct ProfileInviteTimestamp: Equatable {
    public let date: Date
    public let includesTime: Bool
    public func displayTimeZone(_ deviceTimeZone: TimeZone) -> TimeZone {
        includesTime ? deviceTimeZone : TimeZone(secondsFromGMT: 0)!
    }
    public func monthKey(in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = displayTimeZone(timeZone)
        let fields = calendar.dateComponents([.year, .month], from: date)
        guard calendar.component(.era, from: date) == 1, let year = fields.year, (1...9999).contains(year),
              let month = fields.month else { return "" }
        return String(format: "%04d-%02d", year, month)
    }
}

/// Derived from one loaded invitation page. No reward date can assign its invitation month.
public struct ProfileInviteTimeline: Equatable {
    public struct Month: Equatable, Identifiable {
        public let id: String
        public var members: [SocialInvitedMember]
    }
    public let months: [Month]
    public init(members: [SocialInvitedMember]) {
        let sourceTimeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        var groups: [Month] = []
        for member in members {
            let key = Self.timestamp(member.createdAt)?.monthKey(in: sourceTimeZone) ?? ""
            if let index = groups.firstIndex(where: { $0.id == key }) { groups[index].members.append(member) }
            else { groups.append(.init(id: key, members: [member])) }
        }
        months = groups
    }
    public static func timestamp(_ raw: String?) -> ProfileInviteTimestamp? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 96 else { return nil }
        if (text.count == 10 || text.count == 13), text.utf8.allSatisfy({ (48...57).contains($0) }),
           let number = Double(text), number > 0 {
            return .init(date: Date(timeIntervalSince1970: number / (text.count == 13 ? 1000 : 1)), includesTime: true)
        }
        let pattern = #"^([0-9]{4})([-/])([0-9]{1,2})\2([0-9]{1,2})(?:[ T]([0-9]{1,2}):([0-9]{1,2})(?::([0-9]{1,2})(?:\.([0-9]{1,9}))?)?)?(Z|z|[+-][0-9]{2}:?[0-9]{2})?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func field(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        guard let year = field(1).flatMap(Int.init), let month = field(3).flatMap(Int.init),
              let day = field(4).flatMap(Int.init), (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let includesTime = field(5) != nil
        let hour = field(5).flatMap(Int.init) ?? 0, minute = field(6).flatMap(Int.init) ?? 0
        let second = field(7).flatMap(Int.init) ?? 0
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        var offset = includesTime ? 8 * 3600 : 0
        if let zone = field(9) {
            guard includesTime, field(2) == "-", field(3)?.count == 2, field(4)?.count == 2,
                  field(5)?.count == 2, field(6)?.count == 2,
                  field(7) == nil || field(7)?.count == 2 else { return nil }
            if zone.lowercased() == "z" { offset = 0 }
            else {
                let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
                guard let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)),
                      hours <= 23, minutes <= 59 else { return nil }
                offset = (hours * 3600 + minutes * 60) * (zone.first == "-" ? -1 : 1)
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let whole = calendar.date(from: parts) else { return nil }
        let checked = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: whole)
        guard checked.year == year, checked.month == month, checked.day == day,
              checked.hour == hour, checked.minute == minute, checked.second == second else { return nil }
        let fraction = field(8).flatMap { Double("0." + $0) } ?? 0
        let date = whole.addingTimeInterval(fraction - Double(offset))
        let resultYear = calendar.component(.year, from: date)
        guard date.timeIntervalSince1970.isFinite, calendar.component(.era, from: date) == 1,
              (1...9999).contains(resultYear) else { return nil }
        return .init(date: date, includesTime: includesTime)
    }
}
