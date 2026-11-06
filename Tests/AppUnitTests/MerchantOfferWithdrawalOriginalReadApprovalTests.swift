import Foundation
import XCTest
@testable import Questify

final class MerchantOfferWithdrawalOriginalReadApprovalTests: XCTestCase {
    private func context(epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://withdraw.example.test/")!, role: "merchant",
              session: try .init(accountID: 7, epoch: epoch, namespace: "test", token: "synthetic-token", role: "merchant"))
    }
    func testApprovalDoesNotSurviveSessionEpochChange() throws {
        let c = try context(); let grant = try MerchantOfferWithdrawalOriginalReadApproval(context: c, merchantID: 31, ownerID: 9)
        XCTAssertTrue(grant.matches(c)); XCTAssertFalse(try grant.matches(context(epoch: 2)))
    }
    func testPermissionUsesOriginalAccessShapeAndRejectsConflictingOptionalIdentity() throws {
        let grant = try MerchantOfferWithdrawalOriginalReadApproval(context: context(), merchantID: 31, ownerID: 9)
        func access(actor: Int?, owner: Int?, permission: Bool) throws -> MerchantAccess {
            var object: [String: Any] = ["active": true, "merchant": ["id": 31], "roleCode": "MERCHANT_MANAGER",
                "permissions": permission ? ["merchant:coop:manage"] : []]
            object["principalMemberId"] = actor; object["ownerMemberId"] = owner
            return try JSONDecoder().decode(MerchantAccess.self, from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertTrue(try grant.accepts(access(actor: 7, owner: 9, permission: true)))
        XCTAssertTrue(try grant.accepts(access(actor: nil, owner: nil, permission: true)))
        XCTAssertFalse(try grant.accepts(access(actor: 8, owner: 9, permission: true)))
        XCTAssertFalse(try grant.accepts(access(actor: 7, owner: 10, permission: true)))
        XCTAssertFalse(try grant.accepts(access(actor: 7, owner: 9, permission: false)))
    }
    @MainActor func testExactGETRoutesOnly() throws {
        let api = try APIConfiguration(baseURL: URL(string: "https://withdraw.example.test/")!)
        let uuid = "11111111-1111-4111-8111-111111111111"
        func request(_ suffix: String) -> URLRequest { URLRequest(url: URL(string: "https://withdraw.example.test/api/merchant/offer-withdrawal/request/" + suffix)!) }
        let original = request("result?merchantId=31&offerId=4&requestId=" + uuid)
        XCTAssertTrue(MerchantOfferWithdrawalOriginalReadTransport.accepts(original, api: api, merchantID: 31))
        XCTAssertFalse(MerchantOfferWithdrawalOriginalReadTransport.accepts(original, api: api, merchantID: 32))
        var post = original; post.httpMethod = "POST"
        XCTAssertFalse(MerchantOfferWithdrawalOriginalReadTransport.accepts(post, api: api, merchantID: 31))
        XCTAssertFalse(MerchantOfferWithdrawalOriginalReadTransport.accepts(request("withdraw?merchantId=31&offerId=4"), api: api, merchantID: 31))
        XCTAssertFalse(MerchantOfferWithdrawalOriginalReadTransport.accepts(request("result?merchantId=31&offerId=4&requestId=" + uuid + "&offerId=5"), api: api, merchantID: 31))
        XCTAssertFalse(MerchantOfferWithdrawalOriginalReadTransport.accepts(request("result?merchantId=31&offerId=4&requestId=not-a-uuid"), api: api, merchantID: 31))
    }
}
