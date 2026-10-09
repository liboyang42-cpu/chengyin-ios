import Foundation

/// city-node/list applications are RoamPoi rows: their `id` is the cancellation poiId.
/// This mapping is restricted to this scoped response, never a general application-ID alias.
public struct MerchantCityClaimWithdrawal: Equatable, Sendable {
    public let poiID: Int
    public let name: String?

    public init?(row: MerchantContentValue, snapshot: MerchantContentSnapshot) {
        guard snapshot.query == .city, snapshot.access.allows(.projects),
              let merchantID = snapshot.access.merchantID, merchantID > 0,
              let poiID = row["id"].safeInteger, poiID > 0,
              row["applicationType"].safeInteger == 2, row["auditStatus"].safeInteger == 0,
              row["merchantId"] == .null,
              row["poiId"] == .null || row["poiId"].safeInteger == poiID,
              row["applicantMerchantId"] == .null || row["applicantMerchantId"].safeInteger == merchantID,
              let rows = snapshot.value["applications"].array,
              rows.filter({ $0["id"].integer == poiID || $0["poiId"].integer == poiID }).count == 1,
              rows.contains(row) else { return nil }
        self.poiID = poiID; name = row["name"].text
    }

    public init?(poiID: Int, snapshot: MerchantContentSnapshot) {
        guard let row = snapshot.value["applications"].array?.first(where: { $0["id"].safeInteger == poiID }) else { return nil }
        self.init(row: row, snapshot: snapshot)
    }
}
