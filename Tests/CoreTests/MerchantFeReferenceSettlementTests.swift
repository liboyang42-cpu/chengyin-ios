import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class FeReferenceHTTPFake: HTTPTransport {
    var requests: [URLRequest] = []
    var response = "{\"code\":200}"
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(response.utf8), 200) }
}

/// F11 「自由探索结算（参考）」: read-only reference rows; ¥0.00 when there is no data.
@MainActor final class MerchantFeReferenceSettlementTests: XCTestCase {
    private let sample = #"""
    {"groups":[{"activityId":801,"activityTitle":"示例场次","payerName":"示例主办方","openAmount":"24.00","settledAmount":0,
      "rows":[{"id":1,"chapterName":"示例站点","merchantName":"示例店铺","supplierKind":"MERCHANT","basis":"PERK_REDEEMED","quantity":3,"unitAmount":8,"amount":"24","status":"OPEN","statusText":null,"voucherNo":null,"settledAt":null},
              {"id":2,"chapterName":"示例站点二","supplierKind":"AUTHOR","basis":"PERK_REDEEMED","quantity":1,"amount":0,"status":"SETTLED_OFFLINE","statusText":"作者自营，无需结算"},
              {"id":3,"chapterName":"示例站点三","merchantName":"示例店铺","basis":"REVSHARE_HEAD","quantity":2,"unitAmount":"5.5","amount":11,"status":"FUTURE"}]}],
     "totalOpenAmount":24,"totalSettledAmount":null}
    """#
    private func list(_ text: String) throws -> FeReferenceSettlementList {
        try FeReferenceSettlementList(JSONDecoder().decode(CoopFlowJSON.self, from: Data(text.utf8)))
    }
    func testDecodesGroupsRowsAndDecimalAmounts() throws {
        let value = try list(sample)
        XCTAssertEqual(value.groups.count, 1)
        let group = try XCTUnwrap(value.groups.first)
        XCTAssertEqual(group.activityID, 801); XCTAssertEqual(group.openAmountText, "¥24.00"); XCTAssertEqual(group.settledAmountText, "¥0.00")
        XCTAssertEqual(group.rows.map(\.id), [1, 2, 3])
        XCTAssertEqual(group.rows[0].status, .open); XCTAssertEqual(group.rows[0].basis, .perkRedeemed)
        XCTAssertEqual(group.rows[0].amountText, "¥24.00"); XCTAssertEqual(group.rows[0].unitAmountText, "¥8.00")
        XCTAssertTrue(group.rows[1].isAuthorSelfSupply); XCTAssertEqual(group.rows[1].statusTitle(zh: true), "作者自营，无需结算")
        XCTAssertNil(group.rows[2].status); XCTAssertEqual(group.rows[2].unitAmountText, "¥5.50")
        XCTAssertEqual(value.totalOpenText, "¥24.00"); XCTAssertEqual(value.totalSettledText, "¥0.00")
    }
    func testMissingMoneyDisplaysZero() throws {
        XCTAssertEqual(FeReferenceMoney.display(nil), "¥0.00")
        XCTAssertEqual(FeReferenceMoney.display(Decimal(string: "1.005")), "¥1.01")
        let empty = try list(#"{"groups":[]}"#)
        XCTAssertTrue(empty.isEmpty); XCTAssertEqual(empty.totalOpenText, "¥0.00")
        XCTAssertEqual(FeReferenceSettlementList().totalSettledText, "¥0.00")
    }
    func testMalformedShapesAreRejected() {
        XCTAssertThrowsError(try list(#"{"groups":{}}"#))
        XCTAssertThrowsError(try list(#"{"groups":[{"activityId":0,"rows":[]}]}"#))
        XCTAssertThrowsError(try list(#"{"groups":[{"activityId":1,"rows":[{"id":0}]}]}"#))
        XCTAssertThrowsError(try list("[]"))
    }
    func testSettleOnlyOpenMerchantRowsAndDisputeOnlyOpen() throws {
        let value = try list(sample)
        let settleable = FeReferencePayerActions.settleable(value)
        XCTAssertEqual(settleable.map(\.id), [1])
        let request = try FeReferenceSettleRequest(rows: settleable, voucherNo: " V-001 ", note: "")
        XCTAssertEqual(request.body, .object(["ids": .array([.id(1)]), "voucherNo": .string("V-001")]))
        XCTAssertThrowsError(try FeReferenceSettleRequest(rows: value.groups[0].rows))
        XCTAssertThrowsError(try FeReferenceSettleRequest(rows: []))
        let dispute = try FeReferenceDisputeRequest(row: value.groups[0].rows[0], note: "数量不符")
        XCTAssertEqual(dispute.body, .object(["id": .id(1), "note": .string("数量不符")]))
        XCTAssertThrowsError(try FeReferenceDisputeRequest(row: value.groups[0].rows[1], note: "x"))
        XCTAssertThrowsError(try FeReferenceDisputeRequest(row: value.groups[0].rows[0], note: " "))
    }
    func testQueries() throws {
        XCTAssertEqual(FeReferenceMerchantQuery(status: .open).queryItems, [URLQueryItem(name: "status", value: "OPEN")])
        XCTAssertTrue(FeReferenceMerchantQuery().queryItems.isEmpty)
        XCTAssertEqual(try FeReferencePayerQuery(activityID: 801).queryItems, [URLQueryItem(name: "activityId", value: "801")])
        XCTAssertThrowsError(try FeReferencePayerQuery(activityID: 0))
    }
    func testDormantGrantsNeverSendAndGrantedReadUsesGET() async throws {
        let transport = FeReferenceHTTPFake()
        let session = PublishingSession(namespace: "fixture-cn", accountID: 7, epoch: UUID(), role: "member", region: .china)
        let credentials = try PublishingCredentials(session: session, token: "synthetic-token")
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let dormant = FeReferenceSettlementHTTP(configuration: config, transport: transport, credentials: { credentials })
        XCTAssertFalse(dormant.canRead); XCTAssertFalse(dormant.canSettle); XCTAssertFalse(dormant.canDispute)
        let rows = FeReferencePayerActions.settleable(try list(sample))
        let settleRequest = try FeReferenceSettleRequest(rows: rows)
        let outcome = await dormant.settle(settleRequest)
        XCTAssertEqual(outcome, .notSent)
        do { _ = try await dormant.merchantList(); XCTFail("dormant read") } catch { XCTAssertEqual(error as? CoopFlowFailure, .disabled) }
        XCTAssertTrue(transport.requests.isEmpty)
        let reads = try OperationEndpointApproval(baseURL: config.baseURL, namespace: "fixture-cn", accountID: 7, paths: FeReferenceSettlementRoute.readPaths)
        let granted = FeReferenceSettlementHTTP(configuration: config, transport: transport, grants: .init(reads: reads), credentials: { credentials })
        transport.response = #"{"code":200,"data":{"groups":[],"totalOpenAmount":0,"totalSettledAmount":0}}"#
        let value = try await granted.merchantList(.init(status: .disputed))
        XCTAssertTrue(value.isEmpty)
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/api/fe/reference-settlement/merchant")
        XCTAssertEqual(request.url?.query, "status=DISPUTED")
        XCTAssertFalse(granted.canSettle)
    }
}
