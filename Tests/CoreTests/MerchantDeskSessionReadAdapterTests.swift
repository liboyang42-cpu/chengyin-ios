import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// The test supplies this configuration. The adapter does not choose a host, account, or approval.
private let sessionReadConfigurationURL = URL(string: "https://example.com/test")!

private final class LiveSupply: @unchecked Sendable {
    private let lock = NSLock()
    private var value: MerchantDeskSessionReadAdapter.Supply?
    init(_ value: MerchantDeskSessionReadAdapter.Supply?) { self.value = value }
    func get() -> MerchantDeskSessionReadAdapter.Supply? {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func set(_ value: MerchantDeskSessionReadAdapter.Supply?) {
        lock.lock(); defer { lock.unlock() }
        self.value = value
    }
}

private actor SessionReadTransport: HTTPTransport {
    var paths: [String] = []
    var authorizations: [String] = []
    var detailBodies: [Data] = []
    var receiptBodies: [Data] = []
    private var detailProductID: Int?
    private var receiptRequestID: String?
    private let listed: [Int]
    private let live: LiveSupply?
    private let switchOnReceipt: Bool
    init(listed: [Int], live: LiveSupply? = nil, switchOnReceipt: Bool = false) {
        self.listed = listed
        self.live = live
        self.switchOnReceipt = switchOnReceipt
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        paths.append(path)
        if let authorization = request.value(forHTTPHeaderField: "Authorization") {
            authorizations.append(authorization)
        }
        let json: String
        if path.hasSuffix("/access/me") {
            json = "{\"code\":200,\"data\":\(Self.access)}"
        } else if path.hasSuffix("/products/sku/save") {
            json = #"{"code":200,"data":{"skuId":44}}"#
        } else if path.hasSuffix("/products/detail") {
            if let body = request.httpBody { detailBodies.append(body) }
            let shown = detailProductID ?? sessionReadInteger(request.httpBody, key: "productId") ?? 0
            json = #"{"code":200,"data":{"productId":\#(shown),"editable":true,"skus":[]}}"#
        } else if path.hasSuffix("/receipt") {
            if let body = request.httpBody { receiptBodies.append(body) }
            if switchOnReceipt { live?.set(.init(accountID: 99, token: "other-token-value")) }
            let shown = receiptRequestID ?? sessionReadText(request.httpBody, key: "requestId") ?? ""
            json = #"{"code":200,"data":{"requestId":"\#(shown)","state":"NOT_FOUND"}}"#
        } else if path.hasSuffix("/products") {
            let rows = listed.map { #"{"productId":\#($0),"productName":"item"}"# }.joined(separator: ",")
            json = "{\"code\":200,\"data\":[\(rows)]}"
        } else {
            json = #"{"code":404,"msg":"missing","data":null}"#
        }
        return (Data(json.utf8), 200)
    }
    private static let access = #"{"active":true,"merchant":{"id":610,"name":"synthetic-shop"},"roleCode":"MERCHANT_OWNER","canManageOperators":false,"permissions":["merchant:basic:read","merchant:project:manage"]}"#
    func setDetailProductID(_ value: Int) { detailProductID = value }
    func setReceiptRequestID(_ value: String) { receiptRequestID = value }
}

private func sessionReadObject(_ data: Data?) -> MerchantBusinessObject? {
    guard let data else { return nil }
    return try? JSONDecoder().decode(MerchantBusinessValue.self, from: data).object
}

private func sessionReadInteger(_ data: Data?, key: String) -> Int? { sessionReadObject(data)?[key]?.integer }

private func sessionReadText(_ data: Data?, key: String) -> String? { sessionReadObject(data)?[key]?.string }

@MainActor final class MerchantDeskSessionReadAdapterTests: XCTestCase {
    private let token = "synthetic-token"
    private let accountID = 8
    private let requestID = "desk-req-01"

    private func adapter(_ transport: SessionReadTransport, live: LiveSupply? = nil,
                         token: String? = nil, accountID: Int? = nil) throws -> MerchantDeskSessionReadAdapter? {
        let token = token ?? self.token
        let accountID = accountID ?? self.accountID
        let gate = live ?? LiveSupply(.init(accountID: accountID, token: token))
        return MerchantDeskSessionReadAdapter(
            configuration: try .init(baseURL: sessionReadConfigurationURL),
            transport: transport,
            token: token,
            accountID: accountID,
            approval: nil,
            current: { gate.get() })
    }

    private func save() -> MerchantBusinessMutation {
        .saveSku(productID: 3, skuID: 44, name: "door", price: "88.00", stock: 2,
                 originalPrice: nil, pic: nil, bookable: false, slotMinutes: 60,
                 capacityPerSlot: 0, ruleVersion: nil)
    }

    func testListedIdOpensDetailAndSameRequestReceipt() async throws {
        let transport = SessionReadTransport(listed: [3, 9])
        let desk = try XCTUnwrap(try adapter(transport))
        let opened = try await desk.open(productID: 3, requestID: requestID)
        let row = try XCTUnwrap(opened)
        XCTAssertEqual(row.productID, 3)
        XCTAssertEqual(row.detail.object?["productId"]?.integer, 3)
        XCTAssertEqual(row.receipt?.object?["requestId"]?.string, requestID)
        let detailBody = await transport.detailBodies.first
        XCTAssertEqual(sessionReadInteger(detailBody, key: "productId"), 3)
        XCTAssertNil(sessionReadObject(detailBody)?["accountId"])
        let receiptBody = await transport.receiptBodies.first
        XCTAssertEqual(sessionReadText(receiptBody, key: "requestId"), requestID)
        XCTAssertNil(sessionReadObject(receiptBody)?["accountId"])
        let paths = await transport.paths
        XCTAssertEqual(paths, [
            "/test/api/merchant/access/me",
            "/test/api/merchant/desk/products",
            "/test/api/merchant/desk/products/detail",
            "/test/api/merchant/desk/receipt"
        ])
        let authorizations = await transport.authorizations
        XCTAssertEqual(authorizations, Array(repeating: token, count: 4))
    }

    func testUnlistedProductDoesNotOpenDetail() async throws {
        let transport = SessionReadTransport(listed: [3])
        let desk = try XCTUnwrap(try adapter(transport))
        let opened = try await desk.open(productID: 9, requestID: requestID)
        XCTAssertNil(opened)
        let paths = await transport.paths
        XCTAssertEqual(paths, [
            "/test/api/merchant/access/me",
            "/test/api/merchant/desk/products"
        ])
        XCTAssertFalse(paths.contains(where: { $0.hasSuffix("/products/detail") || $0.hasSuffix("/sku/save") }))
    }

    func testDetailCarryingAnotherProductIdIsNotReturned() async throws {
        let transport = SessionReadTransport(listed: [3])
        await transport.setDetailProductID(9)
        let desk = try XCTUnwrap(try adapter(transport))
        let opened = try await desk.open(productID: 3, requestID: requestID)
        XCTAssertNil(opened)
        let paths = await transport.paths
        XCTAssertFalse(paths.contains(where: { $0.hasSuffix("/receipt") || $0.hasSuffix("/sku/save") }))
    }

    func testReceiptCarryingAnotherRequestIdIsNotReturned() async throws {
        let transport = SessionReadTransport(listed: [3])
        await transport.setReceiptRequestID("desk-other1")
        let desk = try XCTUnwrap(try adapter(transport))
        let opened = try await desk.open(productID: 3, requestID: requestID)
        let row = try XCTUnwrap(opened)
        XCTAssertEqual(row.productID, 3)
        XCTAssertNil(row.receipt)
        let paths = await transport.paths
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("/receipt") }))
        XCTAssertFalse(paths.contains(where: { $0.hasSuffix("/sku/save") }))
    }

    func testNilApprovalDoesNotCallSave() async throws {
        let transport = SessionReadTransport(listed: [3])
        let desk = try XCTUnwrap(try adapter(transport))
        _ = try await desk.open(productID: 3, requestID: requestID)
        XCTAssertTrue(desk.saveStaysClosed(save(), merchantID: 610))
        let paths = await transport.paths
        XCTAssertFalse(paths.contains(where: { $0.hasSuffix("/sku/save") }))
        XCTAssertEqual(paths.count, 4)
    }

    func testAccountSwitchDropsTheReadAndDoesNotSave() async throws {
        let live = LiveSupply(.init(accountID: accountID, token: token))
        let transport = SessionReadTransport(listed: [3], live: live, switchOnReceipt: true)
        let desk = try XCTUnwrap(try adapter(transport, live: live))
        let opened = try await desk.open(productID: 3, requestID: requestID)
        XCTAssertNil(opened)
        let paths = await transport.paths
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("/receipt") }))
        XCTAssertFalse(paths.contains(where: { $0.hasSuffix("/sku/save") }))
    }

    func testMissingAccountOrTokenIsNotInvented() async throws {
        let missingAccount = SessionReadTransport(listed: [3])
        XCTAssertNil(try adapter(missingAccount, accountID: 0))
        let blankToken = SessionReadTransport(listed: [3])
        XCTAssertNil(try adapter(blankToken, token: " "))
        let otherAccount = LiveSupply(.init(accountID: 99, token: token))
        let switched = SessionReadTransport(listed: [3], live: otherAccount)
        XCTAssertNil(try adapter(switched, live: otherAccount))
        let absent = LiveSupply(nil)
        let unsigned = SessionReadTransport(listed: [3], live: absent)
        XCTAssertNil(try adapter(unsigned, live: absent))
        let paths = await missingAccount.paths + blankToken.paths + switched.paths + unsigned.paths
        XCTAssertTrue(paths.isEmpty)
    }
}
