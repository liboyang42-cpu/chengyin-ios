import Foundation

/// Mini-program pages/searchmap presentation rules that need no network, location or write.
/// Copy keys only; every count and date comes from already-read rows.

/// `pages/roam/node-level-style.js`: levels clamp to 1...4; a missing level renders as 1.
public struct SearchMapNodeLevelStyle: Equatable {
    public let level: Int
    public let glyph: String
    public let symbol: String
    public let labelKey: String
    public let size: Double
    public static func resolve(_ raw: Int?) -> SearchMapNodeLevelStyle {
        switch max(1, min(4, raw ?? 1)) {
        case 2: return .init(level: 2, glyph: "◆", symbol: "diamond.fill", labelKey: "searchMap.w208.level.featured", size: 38)
        case 3: return .init(level: 3, glyph: "★", symbol: "star.fill", labelKey: "searchMap.w208.level.official", size: 42)
        case 4: return .init(level: 4, glyph: "⬟", symbol: "shield.fill", labelKey: "searchMap.w208.level.themeRoute", size: 46)
        default: return .init(level: 1, glyph: "●", symbol: "circle.fill", labelKey: "searchMap.w208.level.standard", size: 34)
        }
    }
}

public enum SearchMapPinPresentation {
    /// Activities linked to a topic are 主题点位 in the mini-program callout and use the topic icon.
    public static func activitySymbol(linkedTopicID: Int?) -> String { linkedTopicID != nil ? "flag.fill" : "calendar" }
    public static func isTopicPoint(linkedTopicID: Int?) -> Bool { linkedTopicID != nil }
    /// `name || merchantName || '商家节点'`; nil means use the localized fallback.
    public static func merchantTitle(name: String, merchantName: String?) -> String? {
        let primary = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty { return primary }
        let merchant = (merchantName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return merchant.isEmpty ? nil : merchant
    }
}

/// The bottom capsule over the map: 附近活动 / 没能加载出来 / 这一带还没有活动 / 查看全部 N 个结果.
public enum SearchMapResultCapsule: Equatable {
    case loading, failed, empty
    case results(total: Int, listOnly: Int)
    public static func resolve(loading: Bool, failed: Bool, rows: Int, listOnly: Int) -> SearchMapResultCapsule {
        if loading { return .loading }
        if failed && rows == 0 { return .failed }
        if rows == 0 { return .empty }
        return .results(total: rows, listOnly: max(0, min(listOnly, rows)))
    }
    public var key: String {
        switch self {
        case .loading: return "searchMap.w208.capsule.loading"
        case .failed: return "searchMap.w208.capsule.failed"
        case .empty: return "searchMap.w208.capsule.empty"
        case .results: return "searchMap.w208.capsule.results"
        }
    }
    /// Only a non-empty, settled result opens the all-results sheet; failure retries instead.
    public var opensSheet: Bool { if case .results = self { return true }; return false }
}

/// Mini-program date choice: 今天 / 明天 / 选择日期 are mutually exclusive.
public enum SearchMapDateChoice: String, CaseIterable, Equatable {
    case today, tomorrow, custom
    public var key: String { "searchMap.w208.date.\(rawValue)" }
    /// Derived from the concrete draft bounds, never stored separately, so reopening is stable.
    public static func current(_ draft: SearchMapDateFilterDraft, now: Date = Date(), timeZone: TimeZone = .current) -> SearchMapDateChoice? {
        let start = draft.startDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = draft.endDate.trimmingCharacters(in: .whitespacesAndNewlines)
        if start.isEmpty && end.isEmpty { return nil }
        for (choice, preset) in [(SearchMapDateChoice.today, SearchMapDatePreset.today), (.tomorrow, .tomorrow)] {
            var probe = draft
            if (try? probe.select(preset, now: now, timeZone: timeZone)) != nil, probe.startDate == start, probe.endDate == end { return choice }
        }
        return .custom
    }
}

/// Mini-program price inputs: 0...1000, with a distinct message for the edited bound.
public enum SearchMapPriceBound: Equatable { case minimum, maximum }
public enum SearchMapPriceRule {
    public static let range: ClosedRange<Double> = 0...1000
    public static func messageKey(minimum: String, maximum: String, edited: SearchMapPriceBound) -> String? {
        func value(_ text: String) -> Double? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : Double(trimmed)
        }
        guard let low = value(minimum), let high = value(maximum), low.isFinite, high.isFinite, low >= high else { return nil }
        return edited == .minimum ? "searchMap.w208.price.minNotBelowMax" : "searchMap.w208.price.maxNotAboveMin"
    }
}

/// Connectivity banner. Only network state and the time of the last settled load are inputs;
/// a fixture/offline example is a separate, unrelated label.
public enum SearchMapOfflineBanner: Equatable {
    case none
    case noCache
    case cached(Date)
    public static func resolve(online: Bool, lastLoaded: Date?, hasResults: Bool) -> SearchMapOfflineBanner {
        guard !online else { return .none }
        guard hasResults, let lastLoaded else { return .noCache }
        return .cached(lastLoaded)
    }
    public var key: String? {
        switch self {
        case .none: return nil
        case .noCache: return "searchMap.w208.offline.noCache"
        case .cached: return "searchMap.w208.offline.cached"
        }
    }
    /// Reconnect triggers one refresh of retained results, never a new area or location read.
    public static func shouldRefreshOnReconnect(wasOnline: Bool, isOnline: Bool, hasResults: Bool) -> Bool {
        !wasOnline && isOnline && hasResults
    }
}
