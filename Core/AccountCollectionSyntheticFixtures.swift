#if DEBUG
import Foundation

/// Entirely synthetic records. No contact details, production hosts, credentials, or portraits.
public enum AccountCollectionSyntheticFixtures {
    public static let favoritesJSON = #"{"code":200,"data":{"rows":[{"id":301,"name":"Sample riverside route","description":"Offline synthetic favorite","addressName":"Sample waterfront"},{"id":302,"name":"Sample old town route","addressName":"Sample town"}]}}"#
    public static let couponsJSON = #"{"code":200,"data":[{"id":701,"couponId":801,"couponName":"Sample weekend benefit","couponDescription":"Present your eligible benefit through the supported redemption flow","useStatus":0,"startTime":"2026-01-01 00:00:00","endTime":"2030-12-31 23:59:59","getTime":"2026-09-01 10:00:00"},{"id":702,"couponId":802,"couponName":"Sample used benefit","note":"Sample historical benefit","useStatus":1,"startTime":"2025-01-01","endTime":"2026-12-31","useTime":"2026-09-20 08:00:00"},{"id":703,"couponId":803,"couponName":"Sample expired benefit","useStatus":2,"endTime":"2025-12-31"},{"id":704,"couponId":804,"couponName":"Sample invalid benefit","useStatus":3},{"id":705,"couponId":805,"couponName":"Sample unknown benefit","useStatus":99},{"id":706,"couponId":806,"couponName":"Sample future benefit","useStatus":0,"startTime":"2099-01-01","endTime":"2099-12-31"}]}"#
}

#endif
