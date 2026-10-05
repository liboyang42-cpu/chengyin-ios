#if DEBUG
import Foundation

/// Synthetic IDs and names only; no tokens, payment parameters, signatures or scannable code.
public enum OrderLifecycleSyntheticFixtures {
    public static let pending = #"{"id":9701,"ownerType":2,"ownerId":9801,"registrationNo":"SAMPLE-ORDER-9701","registrationStatus":1,"paymentStatus":1,"verificationStatus":0,"payableAmount":39.5,"ticketName":"Sample ticket","purchaseKind":1,"createTime":"2026-10-01 12:00:00","payExpireTime":"2026-10-01 12:20:00","cmsActivity":{"name":"Sample native order","memberId":9901,"teamMode":2,"teamMaxMembers":4,"startDate":"2099-10-02 10:00:00","endDate":"2099-10-02 12:00:00"}}"#
    public static let paid = #"{"id":9701,"ownerType":2,"ownerId":9801,"registrationNo":"SAMPLE-ORDER-9701","registrationStatus":2,"paymentStatus":2,"verificationStatus":0,"payableAmount":39.5,"purchaseKind":3,"createTime":"2026-10-01 12:00:00","paymentTime":"2026-10-01 12:01:00","cmsActivity":{"name":"Sample native order","memberId":9901,"teamMode":2,"teamMaxMembers":4,"startDate":"2099-10-02 10:00:00","endDate":"2099-10-02 12:00:00"},"refundInfo":{"refundable":true,"reason":"Sample server refund policy","deadline":"2099-10-01 18:00:00"},"entitlements":[{"id":9711,"status":0,"chapterId":9721,"chapterName":"Sample chapter"}]}"#
    public static let refunding = #"{"id":9701,"registrationStatus":3,"paymentStatus":2,"verificationStatus":0,"payableAmount":39.5,"refundApplication":{"status":0,"payoutStatus":5,"refundAmount":39.5,"updateTime":"2026-10-01 12:02:00"},"cmsActivity":{"name":"Sample refund under review"}}"#
    public static let refunded = #"{"id":9701,"registrationStatus":3,"paymentStatus":2,"verificationStatus":0,"refundApplication":{"status":1,"payoutStatus":4,"refundAmount":39.5,"payoutTime":"2026-10-01 12:03:00"}}"#
    public static let chapterChoice = #"{"code":500,"msg":"Sample chapter selection required","data":{"needChapterChoice":true,"chapterIds":[9721,9722],"chapters":[{"id":9721,"name":"Sample garden"},{"id":9722,"name":"Sample riverside"}]}}"#
    public static let stationChoice = #"{"code":500,"data":{"needStationChoice":true,"stations":[{"registrationMerchantId":9731,"id":9999,"name":"Sample station"}]}}"#
    public static func detail(_ json: String = pending) throws -> OrderLifecycleDetail { try JSONDecoder().decode(OrderLifecycleDetail.self, from: Data(json.utf8)) }
}
#endif
