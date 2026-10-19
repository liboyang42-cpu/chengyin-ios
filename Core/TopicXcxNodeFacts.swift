import Foundation

/// Second-pass rules from mini-program `pages/topic/index`: node intro templates, session chips and node card footers.
public extension TopicXcxFacts {
    /// Source 节点介绍: every node template across chapters, in route order, first occurrence of an id only.
    static func nodeTemplates(_ topic: TopicDetail) -> [TopicTemplate] {
        var seen = Set<Int>()
        return topic.chapters.flatMap(\.nodes).compactMap(\.template).filter { $0.id > 0 && seen.insert($0.id).inserted }
    }
    /// Source minutes label: `0`, the value, or `--` when missing.
    static func templateMinutes(_ template: TopicTemplate) -> String { template.duration.map(String.init) ?? "--" }

    /// Source session-picker chip from `startDate`: weekday (0 = Sunday), `M.D`, and `HH:mm` unless it is 00:00.
    struct SessionChip: Equatable { public let weekday: Int; public let monthDay: String; public let time: String? }
    static func sessionChip(_ startDate: String?) -> SessionChip? {
        guard let raw = startDate, let date = SquareXcxTime.date(raw.count == 10 ? raw + " 00:00:00" : raw) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let c = calendar.dateComponents([.weekday, .month, .day, .hour, .minute], from: date)
        guard let weekday = c.weekday, let month = c.month, let day = c.day, let hour = c.hour, let minute = c.minute else { return nil }
        let time = hour == 0 && minute == 0 ? nil : String(format: "%02d:%02d", hour, minute)
        return .init(weekday: weekday - 1, monthDay: "\(month).\(day)", time: time)
    }

    /// Source node card foot: `{first merchant}（{node}）` or the node name, plus `等 N 家` when more than one merchant.
    struct NodeFoot: Equatable { public let merchant: String?; public let node: String; public let merchantCount: Int }
    static func nodeFoot(_ node: TopicNode) -> NodeFoot {
        let names = node.merchants.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return .init(merchant: names.first, node: node.name, merchantCount: names.count)
    }
}
