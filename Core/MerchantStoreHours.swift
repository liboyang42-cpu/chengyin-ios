import Foundation

/// Store-local clock values, never dates or device-timezone conversions.
public struct MerchantStoreHours: Equatable {
    public var days: Set<Int> = Set(0...6)
    public var startMinutes = 600
    public var endMinutes = 1320
    private static let labels = ["一", "二", "三", "四", "五", "六", "日"]
    public init() {}
    public init?(wireValue: String) {
        let pattern = "^周(?:一至周日|[一二三四五六日](?:、[一二三四五六日])*) ([01][0-9]|2[0-3]):[0-5][0-9]-(?:次日)?([01][0-9]|2[0-3]):[0-5][0-9]$"
        guard wireValue.utf16.count <= 255,
              let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: wireValue, range: NSRange(wireValue.startIndex..., in: wireValue)),
              match.range.length == wireValue.utf16.count else { return nil }
        let parts = wireValue.components(separatedBy: " ")
        let times = parts[1].replacingOccurrences(of: "次日", with: "").components(separatedBy: "-")
        func minutes(_ text: String) -> Int {
            let pieces = text.components(separatedBy: ":")
            return (Int(pieces[0]) ?? 0) * 60 + (Int(pieces[1]) ?? 0)
        }
        startMinutes = minutes(times[0]); endMinutes = minutes(times[1])
        guard startMinutes != endMinutes, (endMinutes < startMinutes) == wireValue.contains("次日") else { return nil }
        days = parts[0] == "周一至周日" ? Set(0...6) : Set(Self.labels.indices.filter { parts[0].contains(Self.labels[$0]) })
    }
    public var overnight: Bool { endMinutes < startMinutes }
    public var blocker: String? {
        guard !days.isEmpty, days.isSubset(of: Set(0...6)),
              (0..<1440).contains(startMinutes), (0..<1440).contains(endMinutes),
              startMinutes != endMinutes else { return "merchant.operations.hoursInvalid" }
        return nil
    }
    public func wireValue() throws -> String {
        guard blocker == nil else { throw APIError.invalidRequest }
        let dayText = days.count == 7 ? "周一至周日" : "周" + days.sorted().map { Self.labels[$0] }.joined(separator: "、")
        return dayText + " " + Self.clock(startMinutes) + "-" + (overnight ? "次日" : "") + Self.clock(endMinutes)
    }
    public static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
}
