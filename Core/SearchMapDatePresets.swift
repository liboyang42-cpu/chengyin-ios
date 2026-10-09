import Foundation

public enum SearchMapDatePreset: Int { case today = 0, tomorrow = 1 }

/// Sheet-local text, separate from the applied query. Only Apply returns new bounds.
public struct SearchMapDateFilterDraft: Equatable {
    public var startDate: String
    public var endDate: String

    public init(filter: GlobalSearchQuery) {
        startDate = filter.startDate ?? ""
        endDate = filter.endDate ?? ""
    }

    /// Like the mini-program, resolve the phone's Gregorian day when tapped.
    /// Store concrete YYYY-MM-DD bounds; reopening or refreshing never moves them.
    public mutating func select(_ preset: SearchMapDatePreset, now: Date = Date(),
                                timeZone: TimeZone = .current) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(byAdding: .day, value: preset.rawValue, to: now) else {
            throw APIError.invalidRequest
        }
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard parts.era == 1, let year = parts.year, (1...9999).contains(year),
              let month = parts.month, let day = parts.day else { throw APIError.invalidRequest }
        let value = String(format: "%04d-%02d-%02d", year, month, day)
        startDate = value
        endDate = value
    }

    public func applying(to filter: GlobalSearchQuery) throws -> GlobalSearchQuery {
        func optional(_ value: String) -> String? {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        var result = filter
        result.startDate = optional(startDate)
        result.endDate = optional(endDate)
        try result.validate()
        return result
    }
}
