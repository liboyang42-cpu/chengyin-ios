import Foundation

public enum ObjectBadgePresentation {
    public static func track(category: String) -> Int {
        switch category {
        case "CREATE": return 1
        case "ORGANIZE": return 2
        case "CONNECT": return 3
        case "CO_CREATE", "CO-CREATE", "COCREATE": return 4
        default: return 0
        }
    }
    public static func style(medal: ProfileMedal) -> String {
        medal.isAchievement || medal.style.isEmpty ? "glow" : medal.style
    }
    /// Backend naive dates are China calendar dates, never device-local dates.
    public static func date(_ value: String?) -> String? {
        guard let value else { return nil }
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2})(\.\d{1,3})?(Z|[+-]\d{2}:?\d{2})?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        func part(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: s) else { return nil }; return String(s[range])
        }
        guard let year = part(1).flatMap(Int.init), let month = part(2).flatMap(Int.init), let day = part(3).flatMap(Int.init), year > 0 else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let hour = part(4).flatMap(Int.init) ?? 0, minute = part(5).flatMap(Int.init) ?? 0, second = part(6).flatMap(Int.init) ?? 0
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let naive = calendar.date(from: components) else { return nil }
        let checked = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: naive)
        guard checked.year == year, checked.month == month, checked.day == day,
              checked.hour == hour, checked.minute == minute, checked.second == second else { return nil }
        var date = naive
        if let zone = part(8) {
            var seconds = 0
            if zone != "Z" {
                let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
                guard let h = Int(digits.prefix(2)), let m = Int(digits.suffix(2)), h <= 23, m <= 59 else { return nil }
                seconds = (h * 3600 + m * 60) * (zone.hasPrefix("-") ? -1 : 1)
            }
            date = naive.addingTimeInterval(TimeInterval(8 * 3600 - seconds))
        }
        let output = DateFormatter(); output.calendar = calendar; output.timeZone = calendar.timeZone
        output.locale = Locale(identifier: "en_US_POSIX"); output.dateFormat = "yyyy-MM-dd"
        return output.string(from: date)
    }
}
