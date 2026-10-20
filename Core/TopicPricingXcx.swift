import Foundation

/// Display rules ported from mini-program `pages/topic/pricing` and `pages/topic/pricing/partner`.
/// Presentation only; the confirm write stays in the dormant `PublisherLifecycleCoordinator` review.
public enum TopicPricingXcx {
    private static func ceilInt(_ value: Decimal) -> Int {
        var input = value, output = Decimal()
        NSDecimalRound(&output, &input, 0, .up)
        return NSDecimalNumber(decimal: output).intValue
    }
    /// Source starting final price: `ceil(floor)`.
    public static func initialPrice(floor: Decimal) -> Int { ceilInt(floor) }
    /// Source slider maximum: max(ceil(floor)+100, ceil(floor*2), reference ? ceil(reference*1.5) : 0).
    public static func sliderMax(floor: Decimal, reference: Decimal?) -> Int {
        max(ceilInt(floor) + 100, ceilInt(floor * 2), reference.map { ceilInt($0 * Decimal(string: "1.5")!) } ?? 0)
    }
    public enum Delta: Equatable { case above(percent: Int), notAbove }
    /// Source delta vs. the city reference: round((value-ref)/ref*100); only shown with a positive reference and samples.
    public static func delta(price: Decimal, reference: Decimal?, sampleSize: Int?) -> Delta? {
        guard let reference, reference > 0, (sampleSize ?? 0) > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: (price - reference) / reference * 100).doubleValue
        let percent = Int(ratio.rounded())
        return percent > 0 ? .above(percent: percent) : .notAbove
    }
    public enum Terms: Equatable {
        case chapterPerk, chapterTraffic, chapterRevshare(fee: String?)
        case share(rate: String?), fixed(fee: String?), traffic
    }
    /// Source lineup terms text: chapter supply rows by `termsMode`, otherwise by `shareMode`.
    public static func terms(_ row: PublisherLineup) -> Terms {
        switch row.termsMode?.uppercased() {
        case "PERK"?: return .chapterPerk
        case "TRAFFIC"?: return .chapterTraffic
        case "REVSHARE"?: return .chapterRevshare(fee: twoDecimals(row.fixedFee))
        default: break
        }
        switch row.mode {
        case 1: return .share(rate: row.shareRate)
        case 2: return .fixed(fee: row.fixedFee)
        default: return .traffic
        }
    }
    public static func twoDecimals(_ raw: String?) -> String? {
        guard let raw, let value = Decimal(string: raw), !value.isNaN else { return nil }
        return String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }
    public enum Blocker: Equatable { case teamSize, phase, belowFloor }
    /// Source confirm gating: guided needs a team size > 0, the server must allow confirmation, price ≥ floor.
    public static func blocker(guided: Bool, teamSize: Int?, canConfirm: Bool?, price: Decimal?, floor: Decimal) -> Blocker? {
        if guided && (teamSize ?? 0) <= 0 { return .teamSize }
        if canConfirm == false { return .phase }
        guard let price, !price.isNaN, price >= floor else { return .belowFloor }
        return nil
    }
    /// Lineup rows tied to a chapter open the merchant project view; others open the partner terms page.
    public static func opensChapterProject(_ row: PublisherLineup) -> Bool { row.chapterID != nil }

    public enum LineupRowTarget: Equatable, Sendable {
        case chapterProject(topicID: Int, chapterID: Int, partnerID: Int)
        case partnerTerms(topicID: Int, partnerType: String, partnerID: Int)
    }

    public static let lineupLockedNote = "阵容已锁定，点开可查该合作方在本主题中的结算条款。"
    public static let partnerLockedNote = "阵容已锁定，以下为该合作方在本主题中的结算条款。"

    public static func lockedNote(forPartnerDetail: Bool = false) -> String {
        forPartnerDetail ? partnerLockedNote : lineupLockedNote
    }

    public static func rowTarget(topicID: Int, row: PublisherLineup) -> LineupRowTarget? {
        guard topicID > 0, row.partnerID > 0 else { return nil }
        if let chapterID = row.chapterID, chapterID > 0 {
            return .chapterProject(topicID: topicID, chapterID: chapterID, partnerID: row.partnerID)
        }
        let partnerType = row.type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partnerType.isEmpty else { return nil }
        return .partnerTerms(topicID: topicID, partnerType: partnerType, partnerID: row.partnerID)
    }
}
