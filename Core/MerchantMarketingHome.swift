import Foundation

/// Source `pages/merchant/utils/merchant-aggregate.js` normalizeMarketingHome/normalizeMarketingAnalytics.
/// The page asks `api/merchant/marketing-home?windowDays=30` and shows absolute event counts only:
/// the stages are independent counts, never adjacent funnel steps, so no conversion rate is derived.
public struct MerchantMarketingHome: Equatable {
    public static let windowDays = 30
    public struct Recruiting: Equatable { public let count: Int, openCount: Int, shownCount: Int?, hasMoreOpen: Bool }
    public struct Coupons: Equatable { public let couponCount: Int, couponTotal: Int, received: Int, verified: Int }
    public struct Content: Equatable { public let topicCount: Int, freeExploreCount: Int, activityCount: Int }
    public struct Stage: Equatable { public let code: String, label: String, currentCount: Int, previousCount: Int }
    public struct Touchpoint: Equatable { public let code: String, label: String, eventCount: Int }
    public struct Analytics: Equatable {
        public let windowDays: Int, previousStart: Int64, currentStart: Int64, endExclusive: Int64
        public let stages: [Stage], touchpoints: [Touchpoint]
        public func stage(_ code: String) -> Stage? { stages.first { $0.code == code } }
    }
    public static let stageCodes = ["BROWSE", "SIGNUP", "PAYMENT", "VERIFY", "REFUND_APPLY"]
    public static let touchpointCodes = ["IN_APP_TOPIC", "IN_APP_ACTIVITY", "UNATTRIBUTED"]

    public let recruiting: Recruiting, coupons: Coupons, content: Content
    /// Nil means the analytics block failed validation; the page then shows its own retry row.
    public let analytics: Analytics?

    public init(_ raw: MerchantMarketingValue) throws {
        let r = raw["recruiting"], c = raw["coupons"], t = raw["content"]
        guard r.object != nil, c.object != nil, t.object != nil, r["items"].array != nil,
              let count = Self.count(r["count"]), let couponCount = Self.count(c["couponCount"]),
              let received = Self.count(c["received"]), let verified = Self.count(c["verified"]),
              let topics = Self.count(t["topicCount"]), let explore = Self.count(t["freeExploreCount"]),
              let activities = Self.count(t["activityCount"]) else { throw MerchantMarketingFailure.malformed }
        // Older servers omit openCount/shownCount/couponTotal; fall back to the previous meaning.
        recruiting = Recruiting(count: count, openCount: Self.count(r["openCount"]) ?? count,
                                shownCount: Self.count(r["shownCount"]), hasMoreOpen: r["hasMoreOpen"].isTrue)
        coupons = Coupons(couponCount: couponCount, couponTotal: Self.count(c["couponTotal"]) ?? couponCount,
                          received: received, verified: verified)
        content = Content(topicCount: topics, freeExploreCount: explore, activityCount: activities)
        analytics = Self.analytics(raw["analytics"])
    }

    /// Source hasCount/count: present, non-empty, finite and non-negative; fractional values floor.
    static func count(_ value: MerchantMarketingValue) -> Int? {
        guard let number = value.decimal, number >= 0, number < Double(Int.max) else { return nil }
        if case .string(let text) = value, text.isEmpty { return nil }
        return Int(number.rounded(.down))
    }
    private static func whole(_ value: MerchantMarketingValue) -> Int? {
        guard case .number(let v) = value, v.isFinite, v >= 0, v.rounded() == v, v < 9_007_199_254_740_992 else { return nil }
        return Int(v)
    }
    private static func epoch(_ value: MerchantMarketingValue) -> Int64? {
        guard case .number(let v) = value, v.isFinite, v.rounded() == v, abs(v) < 9_007_199_254_740_992 else { return nil }
        return Int64(v)
    }
    static func analytics(_ raw: MerchantMarketingValue) -> Analytics? {
        let window = raw["window"], points = raw["touchpoints"]
        guard raw["semantics"].text == "INDEPENDENT_EVENT_COUNTS", case .number(let days) = raw["windowDays"], days == 7 || days == 30,
              window["timezone"].text == "Asia/Shanghai", window["basis"].text == "COMPLETE_CALENDAR_DAYS",
              let stages = raw["stages"].array, stages.count == stageCodes.count,
              points["coverage"].text == "PARTIAL", points["attributed"] == .bool(false),
              let items = points["items"].array, items.count == touchpointCodes.count,
              let previous = epoch(window["previousStartInclusive"]), let current = epoch(window["currentStartInclusive"]),
              let end = epoch(window["endExclusive"]) else { return nil }
        let day: Int64 = 86_400_000, offset: Int64 = 8 * 3_600_000, span = Int64(days) * day
        guard current - previous == span, end - current == span,
              [previous, current, end].allSatisfy({ ($0 + offset) % day == 0 }) else { return nil }
        var parsed: [Stage] = []
        for (code, row) in zip(stageCodes, stages) {
            guard row["code"].text == code, case .string(let label) = row["label"],
                  !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let now = whole(row["currentCount"]), let before = whole(row["previousCount"]) else { return nil }
            if before == 0 { guard row["changeRate"] == .null else { return nil } }
            else {
                guard let rate = row["changeRate"].decimal,
                      abs(rate - Double(now - before) / Double(before)) <= 0.00011 else { return nil }
            }
            parsed.append(Stage(code: code, label: label.trimmingCharacters(in: .whitespacesAndNewlines), currentCount: now, previousCount: before))
        }
        var touchpoints: [Touchpoint] = []
        for (code, row) in zip(touchpointCodes, items) {
            guard row["code"].text == code, case .string(let label) = row["label"],
                  !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let events = whole(row["eventCount"]) else { return nil }
            touchpoints.append(Touchpoint(code: code, label: label.trimmingCharacters(in: .whitespacesAndNewlines), eventCount: events))
        }
        return Analytics(windowDays: Int(days), previousStart: previous, currentStart: current, endExclusive: end, stages: parsed, touchpoints: touchpoints)
    }

    /// Source _resolveMarketingDataState: empty only when every business count is an explicit zero.
    public var isAllZero: Bool {
        let values = [recruiting.count, coupons.couponCount, coupons.couponTotal, coupons.received, coupons.verified,
                      content.topicCount, content.freeExploreCount, content.activityCount] + (analytics?.stages.map(\.currentCount) ?? [])
        return !values.contains { $0 > 0 }
    }
    /// Source buildCouponCard: the deck exists while any coupon exists, even when none is currently live.
    public var hasCouponDeck: Bool { coupons.couponCount > 0 || coupons.couponTotal > 0 }
    public var couponGhosts: Int { coupons.couponCount > 2 ? 2 : (coupons.couponCount > 0 ? 1 : 0) }
    /// "领取后核销 N%" is the only rate on the page: same coupon batch, so the ratio is defined.
    public var verifiedAfterReceivePercent: Int? {
        guard coupons.received > 0 else { return nil }
        return Int((Double(coupons.verified) / Double(coupons.received) * 100).rounded())
    }
    public enum HeroSubtitle: Equatable { case noSignup, noVerification, verified(String) }
    public var heroValue: String { Self.compact(analytics?.stage("SIGNUP")?.currentCount ?? 0) }
    public var heroSubtitle: HeroSubtitle {
        let signup = analytics?.stage("SIGNUP"), verify = analytics?.stage("VERIFY")
        if signup == nil && verify == nil { return .noSignup }
        guard let verify else { return .noVerification }
        return .verified(Self.compact(verify.currentCount))
    }
    /// Source _compact: numbers at or above 10,000 become "x.x万"; numbers never render as a dash.
    public static func compact(_ value: Int) -> String {
        guard value >= 10_000 else { return String(value) }
        let tenths = (Double(value) / 1000).rounded() / 10
        return (tenths.rounded() == tenths ? String(Int(tenths)) : String(tenths)) + "万"
    }
}
