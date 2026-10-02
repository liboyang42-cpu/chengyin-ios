import Foundation

public enum OrderLifecycleFailure: Error, Equatable {
    case unavailable, accessDenied, expiredReview, ineligible, alreadyAttempted, stale
    case response(code: Int, message: String?)
    case notDispatched
}

/// Source-backed reads only. No payment, cancellation, issuance or redemption dispatch API.
public struct OrderLifecycleService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func detail(id: Int, token: String) async throws -> OrderLifecycleDetail {
        guard id > 0 else { throw APIError.invalidRequest }
        let value: OrderLifecycleDetail = try await read("api/registration/info", fields: ["id": String(id)], token: token)
        guard value.id == id else { throw APIError.malformedResponse }
        return value
    }
    public func couponStatus(historyID: Int, token: String) async throws -> OrderCouponStatus {
        guard historyID > 0 else { throw APIError.invalidRequest }
        return try await read("api/coupon/status", fields: ["couponHistoryId": String(historyID)], token: token)
    }
    private func read<Value: Decodable>(_ path: String, fields: [String: String], token: String) async throws -> Value {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw OrderLifecycleFailure.accessDenied }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope: Envelope<Value>
        do { envelope = try JSONDecoder().decode(Envelope<Value>.self, from: data) }
        catch let error as APIError { throw error }
        catch let error as OrderLifecycleFailure { throw error }
        catch { throw APIError.malformedResponse }
        return envelope.data
    }
    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
        enum CodingKeys: String, CodingKey { case code, msg, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let code = try c.decode(Int.self, forKey: .code)
            if code == 401 { throw APIError.unauthorized }
            if code == 403 { throw OrderLifecycleFailure.accessDenied }
            if code == 410 { throw OrderLifecycleFailure.unavailable }
            guard code == 200 else { throw OrderLifecycleFailure.response(code: code, message: try? c.decode(String.self, forKey: .msg)) }
            data = try c.decode(Value.self, forKey: .data)
        }
    }
}

/// Session token never enters a review, UI, navigation identifier or fixture.
public struct OrderLifecycleSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
@MainActor public protocol OrderLifecycleReading: AnyObject {
    var accountID: Int? { get }
    var scope: UUID { get }
    var isConfigured: Bool { get }
    var isOfflineExample: Bool { get }
    func detail(id: Int) async throws -> OrderLifecycleDetail
}
@MainActor public final class OrderLifecycleSessionReader: OrderLifecycleReading {
    private let service: OrderLifecycleService?
    private let currentSession: () -> OrderLifecycleSession?
    private let onUnauthorized: (OrderLifecycleSession) -> Void
    private var previous: OrderLifecycleSession?
    private var stamp = UUID()
    public var accountID: Int? { currentSession()?.accountID }
    public var isConfigured: Bool { service != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let session = currentSession()
        if previous != session { previous = session; stamp = UUID() }
        return stamp
    }
    public init(service: OrderLifecycleService?, currentSession: @escaping () -> OrderLifecycleSession?, onUnauthorized: @escaping (OrderLifecycleSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        previous = currentSession()
    }
    public func detail(id: Int) async throws -> OrderLifecycleDetail {
        guard let session = currentSession() else { throw APIError.unauthorized }
        guard let service else { throw APIError.notConfigured }
        let captured = scope
        try Task.checkCancellation()
        do {
            let result = try await service.detail(id: id, token: session.token)
            guard !Task.isCancelled, scope == captured, currentSession() == session else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, scope == captured, currentSession() == session else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(session) }
            throw error
        }
    }
}
