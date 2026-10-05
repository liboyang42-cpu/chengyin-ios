import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

enum WorkshopOwnedTestData {
    static func item(_ id: String = "synthetic-claim", stored: String = "ACTIVE", status: String = "ACTIVE", publication: String = "LISTED") -> [String: Any] {
        ["claimId": id, "acquisition": "FREE", "buyerKind": "INDIVIDUAL", "acquiredAt": "2026-10-04T00:00:00Z",
         "validUntil": "2026-11-04T00:00:00.123456Z", "storedStatus": stored, "status": status, "publicationStatus": publication]
    }
    static func header(_ enabled: Bool = true) -> [String: Any] {
        ["schema": "workshop-owned-v1", "scope": "FREE_INDIVIDUAL_ONLY", "availability": enabled ? "FREE_CLAIMS_ONLY" : "NOT_ENABLED",
         "purchasedLibraryStatus": "NOT_AVAILABLE", "contentUseStatus": "UNAVAILABLE", "checkedAt": "2026-10-05T00:00:00.123456789Z"]
    }
    static func page(items: [[String: Any]] = [WorkshopOwnedTestData.item()], enabled: Bool = true, more: Bool = false) -> [String: Any] {
        var value = header(enabled); value["items"] = items; value["hasMore"] = more; return value
    }
    static func detail(item: [String: Any]? = WorkshopOwnedTestData.item(), enabled: Bool = true) -> [String: Any] {
        var value = header(enabled); value["item"] = item as Any? ?? NSNull(); return value
    }
    static func decode<T: Decodable>(_ object: Any, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    static func response(_ object: Any) throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: ["code": 200, "data": object]), 200)
    }
    static func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player", realm: String = "synthetic", token: String = "synthetic") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://workshop-read.example/native")!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: realm, token: token))
    }
}
