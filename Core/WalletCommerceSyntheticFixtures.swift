import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Offline only; all IDs and financial values are invented test data. Never a live factory.
public struct WalletCommerceSyntheticTransport: HTTPTransport {
    public let fail: Bool
    public init(fail: Bool = false) { self.fail = fail }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        if fail { return (Data(#"{"code":503}"#.utf8), 503) }
        let payload: String
        switch request.url?.path {
        case "/api/wallet/stages": payload = #"{"pendingSettlement":"12.30","disputed":2,"withdrawable":0,"complaintPeriod":[{"availableDate":"2026-10-08","amount":"4.50"}],"amountsKnown":false}"#
        case "/api/balance/list": payload = #"[{"id":1,"changeBalance":"5.00","changeType":2,"changeReason":"Synthetic debit"},{"id":2,"changeType":1,"changeReason":"Synthetic missing amount"}]"#
        case "/api/points/list": payload = #"[{"id":3,"changePoints":-7,"afterPoints":40,"changeReason":"Synthetic points"}]"#
        case "/api/user/points/list": payload = #"{"rows":[{"id":3,"changePoints":-7,"afterPoints":40,"changeReason":"Synthetic points"}],"total":1}"#
        case "/api/user/balance/list": payload = #"{"rows":[{"id":4,"changeBalance":"8.50","changeType":1,"eventType":4,"changeReason":"Synthetic withdrawal rejection return"}],"total":1}"#
        case "/api/product/list": payload = #"{"rows":[{"id":10,"productName":"Synthetic postcard","price":8,"stock":null}],"total":1}"#
        case "/api/product/info": payload = #"{"id":10,"productName":"Synthetic postcard","price":8,"stock":null,"skuList":[{"id":11,"skuName":"Synthetic variant","price":8,"stock":null}]}"#
        case "/api/cart/list": payload = #"{"rows":[{"id":20,"productId":10,"skuId":11,"quantity":1,"productName":"Synthetic postcard","price":8}],"total":1}"#
        case "/api/cart/settlement": payload = #"{"productAmount":8,"deliveryFee":0,"taxFee":0,"totalAmount":"8.1","pointBalance":40,"productList":[{"id":20,"productId":10,"skuId":11,"quantity":1,"price":8}],"address":{"id":30,"mobilePhone":"TEST-0000"}}"#
        case "/api/withdrawal/list": payload = #"{"rows":[{"id":40,"amount":5,"status":1,"bankAccount":"SYNTHETIC-1234"},{"id":41,"amount":6,"status":2}],"total":2}"#
        case "/api/points/result_list": payload = #"[{"id":50,"status":1,"eventType":1,"title":"Synthetic rule","description":"Offline fixture only","value":5,"pointsNum":2},{"id":51,"status":1,"eventType":14,"title":"Excluded spend rule"}]"#
        default: throw APIError.invalidRequest // No mutation success is fabricated by UI fixtures.
        }
        return (Data(("{\"code\":200,\"data\":" + payload + "}").utf8), 200)
    }
}
