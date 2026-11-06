import SwiftUI

/// Localized rendering of source official-inbox/official-mine facts. Unknown values keep
/// the source's explicit "待确认" wording; nothing is inferred.
enum OfficialPrivateFactsText {
    static func window(_ value: OfficialServiceWindow) -> Text {
        switch value {
        case .unbounded: return Text("official.w206.window.unbounded")
        case let .range(start, end): return Text("official.w206.window.range \(bound(start)) \(bound(end))")
        }
    }
    private static func bound(_ value: OfficialServiceWindow.Bound) -> Text {
        switch value {
        case .open: return Text("official.w206.window.open")
        case let .time(month, day, hour, minute):
            let clock = String(format: "%02d:%02d", hour, minute)
            return Text("official.w206.window.time \(month) \(day) \(clock)")
        case .text(let text): return Text(verbatim: text)
        }
    }
    static func broadcastLine(_ facts: OfficialPublishedBroadcastFacts) -> Text {
        let mode: Text
        switch facts.mode {
        case .together: mode = Text("official.w206.broadcast.together")
        case .separate: mode = Text("official.w206.broadcast.separate")
        case .unknown: mode = Text("official.w206.broadcast.modeUnknown")
        }
        var audience = Text("official.w206.broadcast.audienceUnknown")
        if let roles = facts.audience, !roles.isEmpty {
            audience = roles.enumerated().reduce(Text(verbatim: "")) { result, item in
                (item.offset == 0 ? result : result + Text(verbatim: " / ")) + audienceName(item.element)
            }
        }
        let city = facts.city.map { Text(verbatim: $0) } ?? Text("official.w206.broadcast.scopeUnknown")
        return Text("official.w206.broadcast.line \(mode) \(audience) \(city)")
    }
    private static func audienceName(_ role: OfficialAudience) -> Text {
        switch role {
        case .player: return Text("official.w206.audience.player")
        case .club: return Text("official.w206.audience.club")
        case .merchant: return Text("official.w206.audience.merchant")
        }
    }
    static func broadcastStatusKey(_ status: OfficialPublishedBroadcastFacts.Status) -> LocalizedStringKey {
        switch status {
        case .draft: return "official.w206.broadcast.status.draft"
        case .pending: return "official.w206.broadcast.status.pending"
        case .sent: return "official.w206.broadcast.status.sent"
        case .withdrawn: return "official.w206.broadcast.status.withdrawn"
        case .unknown: return "official.w206.broadcast.status.unknown"
        }
    }
}
