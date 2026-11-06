import Foundation

/// Source pages/merchant/marketing/ai-insight/index.js _buildValueCard: "比上期 ±N 位玩家" only when the
/// previous period has a positive count and differs; a missing previous value is not zero.
public enum MerchantInsightParity {
    public static let emptyStateCTATitle = "去合作中心看看"
    public static let unknownFactText = "数据待同步"

    public struct EmptyGuidancePresentation: Equatable, Sendable {
        public let showsGuidance: Bool
        public let ctaTitle: String?
        public init(showsGuidance: Bool, ctaTitle: String?) {
            self.showsGuidance = showsGuidance
            self.ctaTitle = ctaTitle
        }
    }

    public static func visitorDelta(_ facts: MerchantMarketingValue) -> Int? {
        func count(_ value: MerchantMarketingValue) -> Int? {
            guard case .number = value, let n = value.integer, n >= 0 else { return nil }
            return n
        }
        guard let current = count(facts["attribution"]["visitors"]), let previous = count(facts["attribution"]["prevVisitors"]),
              previous > 0, current != previous else { return nil }
        return current - previous
    }

    public static func emptyGuidance(isEmpty: Bool, canOpenCoopCenter: Bool = true) -> EmptyGuidancePresentation {
        guard isEmpty else { return .init(showsGuidance: false, ctaTitle: nil) }
        return .init(showsGuidance: true, ctaTitle: canOpenCoopCenter ? emptyStateCTATitle : nil)
    }

    public static func emptyCTATitle(isEmpty: Bool, canOpenCoopCenter: Bool = true) -> String? {
        emptyGuidance(isEmpty: isEmpty, canOpenCoopCenter: canOpenCoopCenter).ctaTitle
    }

    public static func factValueText(_ raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "-", trimmed != "--", trimmed != "—" else {
            return unknownFactText
        }
        return trimmed
    }

    public static func factIntText(_ value: Int?) -> String {
        guard let value, value >= 0 else { return unknownFactText }
        return String(value)
    }
}
