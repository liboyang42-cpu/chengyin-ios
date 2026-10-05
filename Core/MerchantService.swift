import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Merchant reads only. Server authorization remains mandatory on every endpoint.
/// No service method changes enrollment, orders, verification, refunds, money or projects.
public struct MerchantService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }

    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
        enum CodingKeys: String, CodingKey { case code, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let code = try c.decode(Int.self, forKey: .code)
            if code == 401 { throw APIError.unauthorized }
            if code == 403 { throw MerchantReadError.accessDenied }
            guard code == 200 else { throw APIError.businessCode(code) }
            data = try c.decode(Value.self, forKey: .data)
        }
    }
    private struct Rows<Value: Decodable>: Decodable {
        let values: [Value]
        enum CodingKeys: String, CodingKey { case rows }
        init(from decoder: Decoder) throws {
            if let array = try? decoder.singleValueContainer().decode([Value].self) { values = array }
            else { values = try decoder.container(keyedBy: CodingKeys.self).decode([Value].self, forKey: .rows) }
        }
    }
    private enum Body { case none, json([String: Int]), form([String: String]) }
    private func post<Value: Decodable>(_ path: String, body: Body = .none, token: String) async throws -> Value {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        let url = configuration.baseURL.appendingPathComponent(path)
        var request: URLRequest
        switch body {
        case .form(let fields):
            request = try AuthRequestBuilder.makeFormRequest(url: url, fields: fields, token: token)
        case .none, .json:
            request = try AuthRequestBuilder.makeFormRequest(url: url, fields: [:], token: token, includesBody: false)
            if case .json(let fields) = body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            }
        }
        let (data, status) = try await transport.send(request)
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw MerchantReadError.accessDenied }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        do { return try JSONDecoder().decode(Envelope<Value>.self, from: data).data }
        catch let error as APIError { throw error }
        catch let error as MerchantReadError { throw error }
        catch { throw APIError.malformedResponse }
    }
    public func access(token: String) async throws -> MerchantAccess {
        try await post("api/merchant/access/me", token: token)
    }
    public func dashboard(access: MerchantAccess, token: String) async throws -> MerchantDashboard {
        guard access.canReadDashboard else { throw MerchantReadError.accessDenied }
        return try await post("api/merchant/dashboard", token: token)
    }
    public func todo(access: MerchantAccess, token: String) async throws -> MerchantTodo {
        guard access.isOwner else { throw MerchantReadError.accessDenied }
        return try await post("api/merchant/todo-summary", token: token)
    }
    public func events(access: MerchantAccess, token: String) async throws -> [MerchantEvent] {
        guard access.isOwner else { throw MerchantReadError.accessDenied }
        // Unlike dashboard/todo, Flutter _rows sends a JSON object here.
        return try await post("api/merchant/events", body: .json([:]), token: token)
    }
    public func orders(access: MerchantAccess, filter: MerchantOrderFilter = .init(), token: String) async throws -> [MerchantOrder] {
        guard access.allows(.orders) else { throw MerchantReadError.accessDenied }
        var fields: [String: Int] = [:]
        if let status = filter.status { fields["status"] = status.rawValue }
        if let aftersale = filter.aftersaleStatus { fields["aftersaleStatus"] = aftersale.rawValue }
        // Do not send mmsMerchantId; the server binds the signed-in seller.
        let rows: Rows<MerchantOrder> = try await post("api/merchant/orders", body: .json(fields), token: token)
        return rows.values
    }
    public func projects(access: MerchantAccess, token: String) async throws -> MerchantProjectPage {
        guard access.allows(.projects) else { throw MerchantReadError.accessDenied }
        // Source API exposes one first page only. Do not invent pagination behavior.
        return try await post("api/project/my", body: .form([
            "type": "all", "state": "all", "ownerType": "all", "scope": "MERCHANT", "pageNum": "1", "pageSize": "200"
        ]), token: token)
    }
}
