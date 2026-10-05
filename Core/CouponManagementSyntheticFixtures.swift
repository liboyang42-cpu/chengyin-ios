import Foundation

public enum CouponManagementSyntheticFixtures {
    public static let published = Data(#"{"code":200,"data":[{"id":710,"name":"Synthetic gift coupon","description":"Example only","couponType":0,"status":1,"publishCount":20,"receiveCount":3,"useCount":1,"startTime":"2026-10-01 09:30:00","endTime":"2026-10-31 18:45:00","amount":null,"currency":null,"perLimit":null},{"id":711,"name":"Synthetic stopped coupon","couponType":3,"status":4,"publishCount":null,"receiveCount":null,"useCount":null},{"id":712,"name":"Synthetic unknown status","status":99}]}"#.utf8)
    public static func draft() -> CouponManagementDraft {
        var value = CouponManagementDraft(); value.name = "Synthetic gift coupon"; value.quantity = "20"; value.couponType = 0
        value.startTime = Date(timeIntervalSince1970: 1_800_000_000); value.endTime = Date(timeIntervalSince1970: 1_800_086_400)
        return value
    }
}
