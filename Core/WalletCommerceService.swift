import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Known source read contracts only. No default endpoint, token, provider or live factory.
public struct WalletCommerceService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private var boundScope: WalletCommerceScope?
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    func bound(to scope: WalletCommerceScope) -> Self {
        var copy = self; copy.boundScope = scope; return copy
    }
    public func pointsTasks(token: String) async throws -> [WalletPointsTask] {
        let rows = try decodeData([WalletPointsTask].self, await send(path: "api/points/result_list", fields: [:], token: token))
        guard rows.allSatisfy({ $0.id > 0 }) else { throw APIError.malformedResponse }
        return rows.filter(\.isEarnTask)
    }
    public func withdrawalBalance(memberID: Int, token: String) async throws -> WithdrawalBalance {
        guard memberID > 0, boundScope.map({ $0.accountID == memberID }) ?? true else { throw APIError.invalidRequest }
        return try decodeData(WithdrawalBalance.self, await send(path: "api/user/info", fields: ["member_id": String(memberID)], token: token))
    }
    public func stages(token: String) async throws -> WalletFundsStages {
        let data = try await send(path: "api/wallet/stages", fields: [:], token: token, json: true)
        return try decodeData(WalletFundsStages.self, data)
    }
    public func ledger(_ kind: WalletLedgerKind, page: Int = 1, pageSize: Int = 20, changeType: Int? = nil, token: String) async throws -> WalletPage<WalletLedgerRow> {
        guard page > 0, (1...200).contains(pageSize), changeType == nil || changeType == 1 || changeType == 2 else { throw APIError.invalidRequest }
        var fields: [String: String] = [:]
        let path: String; let paged: Bool
        switch kind {
        case .balance: path = "api/balance/list"; paged = false
        case .assetPoints: path = "api/points/list"; paged = false
        case .points: path = "api/user/points/list"; paged = true
        case .income(let filter):
            path = "api/user/balance/list"; paged = true
            if !filter.rawValue.isEmpty { fields["eventType"] = filter.rawValue }
        }
        if paged { fields["pageNum"] = String(page); fields["pageSize"] = String(pageSize) }
        // Both points endpoints ignore server direction filtering. Income uses eventType.
        if kind == .balance, let changeType { fields["change_type"] = String(changeType) }
        if !paged && page != 1 { throw APIError.invalidRequest }
        let data = try await send(path: path, fields: fields, token: token)
        let result: WalletPage<WalletLedgerRow>
        if paged {
            result = try table(data, page: page, pageSize: pageSize, topRowsFallback: kind == .points)
        } else {
            result = WalletPage(rows: try decodeData([WalletLedgerRow].self, data), total: nil, page: nil, pageSize: nil)
        }
        guard result.rows.allSatisfy({ $0.id > 0 }) else { throw APIError.malformedResponse }
        return result
    }
    public func products(merchantID: Int? = nil, sortType: Int = 0, keyword: String? = nil, token: String) async throws -> WalletPage<WalletProduct> {
        guard (0...4).contains(sortType) else { throw APIError.invalidRequest }
        var fields = ["sort_type": String(sortType)]
        if let merchantID, merchantID > 0 { fields["merchant_id"] = String(merchantID) }
        if let keyword, !keyword.isEmpty { fields["keyword"] = keyword }
        let page: WalletPage<WalletProduct> = try table(await send(path: "api/product/list", fields: fields, token: token))
        guard page.rows.allSatisfy({ Self.validProduct($0) }) else { throw APIError.malformedResponse }
        return page
    }
    public func product(id: Int, token: String) async throws -> WalletProduct {
        guard id > 0 else { throw APIError.invalidRequest }
        let value = try decodeData(WalletProduct.self, await send(path: "api/product/info", fields: ["id": String(id)], token: token))
        guard value.id == id, Self.validProduct(value) else { throw APIError.malformedResponse }; return value
    }
    public func cart(token: String) async throws -> WalletPage<WalletCartItem> {
        let page: WalletPage<WalletCartItem> = try table(await send(path: "api/cart/list", fields: [:], token: token))
        try validateCart(page.rows); return page
    }
    public func checkout(cartIDs: [Int], token: String) async throws -> WalletCheckoutPreview {
        let ids = try WalletCommerceCommand.cartIDs(cartIDs)
        let value = try decodeData(WalletCheckoutPreview.self, await send(path: "api/cart/settlement", fields: ["cartids": ids], token: token))
        if let rows = value.productList { try validateCart(rows) }
        let amounts = [value.productAmount, value.productWeight, value.deliveryFee, value.taxFee, value.totalAmount, value.pointBalance].compactMap { $0 }
        guard amounts.allSatisfy({ $0.value >= 0 }), value.productQuantity.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
        return value
    }
    public func withdrawals(token: String) async throws -> WalletPage<WalletWithdrawalRecord> {
        // Source list() sends no body and exposes no page arguments. Preserve that limit.
        let bytes = try await send(path: "api/withdrawal/list", fields: [:], token: token, body: false)
        let e = try JSONDecoder().decode(WithdrawalEnvelope.self, from: bytes)
        return WalletPage(rows: e.rows, total: e.total, page: nil, pageSize: nil)
    }
    private static func validProduct(_ product: WalletProduct) -> Bool {
        product.id > 0 && (product.price.map { $0.value >= 0 } ?? true) &&
        (product.stock.map { $0 >= 0 } ?? true) && (product.skuList ?? []).allSatisfy {
            $0.id > 0 && ($0.price.map { $0.value >= 0 } ?? true) && ($0.stock.map { $0 >= 0 } ?? true)
        }
    }
    private func validateCart(_ rows: [WalletCartItem]) throws {
        guard rows.allSatisfy({ $0.id > 0 && $0.productId > 0 && $0.skuId > 0 && $0.quantity > 0 && ($0.price.map { $0.value >= 0 } ?? true) }) else { throw APIError.malformedResponse }
    }
    private func send(path: String, fields: [String: String], token: String, json: Bool = false, body: Bool = true) async throws -> Data {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token, includesBody: body && !json)
        if json { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = Data("{}".utf8) }
        try Task.checkCancellation()
        let response: (Data, Int)
        if let approved = transport as? WalletCommerceApprovedReadTransport {
            guard let boundScope else { throw WalletCommerceSafetyError.staleSession }
            response = try await approved.send(request, scope: boundScope, token: token)
        } else { response = try await transport.send(request) }
        let (data, status) = response
        try Task.checkCancellation()
        try Self.validateEnvelope(data, status: status)
        return data
    }
    static func validateEnvelope(_ data: Data, status: Int) throws {
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope = try JSONDecoder().decode(Status.self, from: data)
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw APIError.businessCode(envelope.code) }
        // Raw server messages are deliberately not logged or surfaced (may contain personal data).
    }
    private struct Status: Decodable { let code: Int }
    private struct DataEnvelope<T: Decodable>: Decodable { let data: T }
    private func decodeData<T: Decodable>(_ type: T.Type, _ bytes: Data) throws -> T {
        try JSONDecoder().decode(DataEnvelope<T>.self, from: bytes).data
    }
    private struct Table<Row: Decodable>: Decodable {
        let rows: [Row]
        let total: Int?
        enum CodingKeys: String, CodingKey { case rows, total }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rows = try c.decode([Row].self, forKey: .rows)
            total = (try? c.decode(Int.self, forKey: .total)) ?? (try? c.decode(String.self, forKey: .total)).flatMap(Int.init)
            guard total.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
        }
    }
    private struct TopTable<Row: Decodable>: Decodable { let rows: [Row] }
    private func table<Row: Decodable>(_ bytes: Data, page: Int? = nil, pageSize: Int? = nil, topRowsFallback: Bool = false) throws -> WalletPage<Row> {
        do {
            let t = try decodeData(Table<Row>.self, bytes)
            return WalletPage(rows: t.rows, total: t.total, page: page, pageSize: pageSize)
        } catch {
            guard topRowsFallback else { throw error }
            let t = try JSONDecoder().decode(TopTable<Row>.self, from: bytes)
            return WalletPage(rows: t.rows, total: nil, page: page, pageSize: pageSize)
        }
    }
    private struct WithdrawalEnvelope: Decodable {
        let rows: [WalletWithdrawalRecord]
        let total: Int?
        enum CodingKeys: String, CodingKey { case data }
        struct ListTable: Decodable { let list: [WalletWithdrawalRecord]; let total: Int? }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let list = try? c.decode([WalletWithdrawalRecord].self, forKey: .data) { rows = list; total = nil }
            else if let table = try? c.decode(Table<WalletWithdrawalRecord>.self, forKey: .data) { rows = table.rows; total = table.total }
            else { let table = try c.decode(ListTable.self, forKey: .data); rows = table.list; total = table.total }
        }
    }
}
