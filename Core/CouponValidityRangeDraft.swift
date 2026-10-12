import Foundation

/// A local pair of validity dates. It never changes eligibility, publishes or writes a coupon.
public struct CouponValidityRangeDraft: Equatable {
    public var startTime: Date?
    public var endTime: Date?
    public init(startTime: Date?, endTime: Date?) {
        self.startTime = startTime; self.endTime = endTime
    }
    public init(_ draft: CouponManagementDraft) {
        self.init(startTime: draft.startTime, endTime: draft.endTime)
    }
    public var blocker: String? {
        guard let start = startTime, let end = endTime else { return "couponManagement.datesRequired" }
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              let wireStart = CouponValidityTime.parse(CouponValidityTime.wire(start)),
              let wireEnd = CouponValidityTime.parse(CouponValidityTime.wire(end)), wireEnd > wireStart else {
            return "couponManagement.dateOrder"
        }
        return nil
    }
    public func applying(to current: CouponManagementDraft) throws -> CouponManagementDraft {
        guard blocker == nil else { throw CouponManagementError.invalid }
        var result = current
        result.startTime = startTime; result.endTime = endTime
        return result
    }
}
