import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact source request construction, separated from all dispatch policy. Constructing a
/// request does not send it. Never log the request body, token, code or provider parameters.
public enum OrderLifecycleRequestContract {
    public static func cancellation(review: OrderLifecycleReview, baseURL: URL, token: String) throws -> URLRequest {
        guard review.action == .cancel || review.action == .refund,
              OrderLifecycleCoordinator.isReviewable(review.action, detail: review.detail) else { throw APIError.invalidRequest }
        return try form(review.action.sourcePath, fields: ["id": String(review.detail.id)], baseURL: baseURL, token: token)
    }
    public static func paymentParameters(registrationID: Int, baseURL: URL, token: String) throws -> URLRequest {
        guard registrationID > 0 else { throw APIError.invalidRequest }
        return try form("api/registration/pay/app", fields: ["id": String(registrationID)], baseURL: baseURL, token: token)
    }
    public static func issueTicket(registrationID: Int, baseURL: URL, token: String) throws -> URLRequest {
        guard registrationID > 0 else { throw APIError.invalidRequest }
        return try form("api/verify/dyncode/issue", fields: ["registrationId": String(registrationID)], baseURL: baseURL, token: token)
    }
    public static func issueCoupon(historyID: Int, baseURL: URL, token: String) throws -> URLRequest {
        guard historyID > 0 else { throw APIError.invalidRequest }
        return try form("api/coupon/qr-token", fields: ["couponHistoryId": String(historyID)], baseURL: baseURL, token: token)
    }
    public static func verifyDynamicTicket(code: String, baseURL: URL, token: String) throws -> URLRequest {
        // Source: server derives type after HMAC verification; no client type field.
        try verify("api/registration/scan_dynamic_code", code: code, extra: [:], baseURL: baseURL, token: token)
    }
    public static func verifyCoupon(code: String, baseURL: URL, token: String) throws -> URLRequest {
        // The exact captured string is sent; the server selects token vs legacy coupon code.
        try verify("api/coupon/verification", code: code, extra: [:], baseURL: baseURL, token: token)
    }
    public static func verifyLegacyTicket(type: String, code: String, baseURL: URL, token: String) throws -> URLRequest {
        guard ["activity", "topic"].contains(type) else { throw APIError.invalidRequest }
        return try verify("api/registration/scan_qr_code", code: code, extra: ["type": type], baseURL: baseURL, token: token)
    }
    public static func verifyChoice(receipt: OrderVerificationReceipt, choiceID: Int, code: String, baseURL: URL, token: String) throws -> URLRequest {
        guard receipt.containsChoice(choiceID), let kind = receipt.choiceKind else { throw APIError.invalidRequest }
        let path = kind == .chapter ? "api/registration/scan_qr_code_chapter" : "api/registration/scan_qr_code_station"
        let key = kind == .chapter ? "chapterId" : "registrationMerchantId"
        return try verify(path, code: code, extra: [key: String(choiceID)], baseURL: baseURL, token: token)
    }
    private static func verify(_ path: String, code: String, extra: [String: String], baseURL: URL, token: String) throws -> URLRequest {
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidRequest }
        var fields = extra; fields["code"] = code
        return try form(path, fields: fields, baseURL: baseURL, token: token)
    }
    private static func form(_ path: String, fields: [String: String], baseURL: URL, token: String) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: baseURL.appendingPathComponent(path), fields: fields, token: token)
    }
}

/// Provider parameters are held privately and deliberately have no SDK/accessor/URL bridge.
/// This validates source-required field presence without fabricating signatures/defaults.
public struct OrderPaymentParameterMetadata: Decodable, Equatable {
    public let hasCompleteFields: Bool
    private struct Parameters: Decodable {
        let appId: String?; let partnerId: String?; let prepayId: String?; let packageValue: String?
        let nonceStr: String?; let timeStamp: Timestamp?; let sign: String?
    }
    private struct Timestamp: Decodable {
        let value: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let text = try? c.decode(String.self) { value = text }
            else if let integer = try? c.decode(Int64.self) { value = String(integer) }
            else { throw APIError.malformedResponse }
        }
    }
    enum CodingKeys: String, CodingKey { case payParams }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let p = try c.decode(Parameters.self, forKey: .payParams)
        hasCompleteFields = [p.appId, p.partnerId, p.prepayId, p.packageValue, p.nonceStr, p.timeStamp?.value, p.sign].allSatisfy { $0?.isEmpty == false } && (Int64(p.timeStamp?.value ?? "") ?? 0) > 0
    }
}
public struct OrderCouponPassMetadata: Decodable, Equatable {
    public let expiresIn: Int?
    public let useStatus: Int?
    public let startTime: String?
    public let endTime: String?
    public let couponName: String?
    // No token or remote QR image URL is retained or exposed.
}
public struct OrderCancellationResponse: Decodable, Equatable {
    public let message: String?
    public let observation: OrderCancellationObservation?
    enum CodingKeys: String, CodingKey { case msg, data }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try c.decodeIfPresent(String.self, forKey: .msg)
        observation = try c.decodeIfPresent(OrderCancellationObservation.self, forKey: .data)
    }
}

/// Dormant source-backed adapter. Normal initialization cannot dispatch anything, even if
/// passed a real HTTP transport. A DEBUG-only initializer admits offline fixture transports.
/// It is intentionally not wired into AppSession, coordinator, scanner, or payment SDK.
public struct OrderLifecycleDormantAdapter {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private var fixtureOnly = false
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    #if DEBUG
    public init(fixtureConfiguration: APIConfiguration, fixtureTransport: any HTTPTransport) {
        self.configuration = fixtureConfiguration; self.transport = fixtureTransport; fixtureOnly = true
    }
    #endif
    public var isProductionDispatchEnabled: Bool { false }
    private func requireFixture() throws {
        #if DEBUG
        guard fixtureOnly else { throw OrderLifecycleFailure.notDispatched }
        #else
        throw OrderLifecycleFailure.notDispatched
        #endif
    }
    public func cancellation(_ review: OrderLifecycleReview, token: String) async throws -> OrderCancellationResponse {
        try requireFixture()
        let request = try OrderLifecycleRequestContract.cancellation(review: review, baseURL: configuration.baseURL, token: token)
        let data = try await execute(request)
        return try JSONDecoder().decode(OrderCancellationResponse.self, from: data)
    }
    public func paymentParameters(registrationID: Int, token: String) async throws -> OrderPaymentParameterMetadata {
        try requireFixture()
        return try await value(OrderLifecycleRequestContract.paymentParameters(registrationID: registrationID, baseURL: configuration.baseURL, token: token))
    }
    public func issueTicket(registrationID: Int, token: String) async throws -> OrderPassMetadata {
        try requireFixture()
        return try await value(OrderLifecycleRequestContract.issueTicket(registrationID: registrationID, baseURL: configuration.baseURL, token: token))
    }
    public func issueCoupon(historyID: Int, token: String) async throws -> OrderCouponPassMetadata {
        try requireFixture()
        return try await value(OrderLifecycleRequestContract.issueCoupon(historyID: historyID, baseURL: configuration.baseURL, token: token))
    }
    public func verifyLegacy(type: String, code: String, token: String) async throws -> OrderVerificationReceipt {
        try requireFixture()
        return try await receipt(OrderLifecycleRequestContract.verifyLegacyTicket(type: type, code: code, baseURL: configuration.baseURL, token: token))
    }
    public func verifyChoice(receipt: OrderVerificationReceipt, choiceID: Int, code: String, token: String) async throws -> OrderVerificationReceipt {
        try requireFixture()
        return try await self.receipt(OrderLifecycleRequestContract.verifyChoice(receipt: receipt, choiceID: choiceID, code: code, baseURL: configuration.baseURL, token: token))
    }
    public func verifyDynamicTicket(code: String, token: String) async throws -> OrderVerificationReceipt {
        try requireFixture()
        return try await receipt(OrderLifecycleRequestContract.verifyDynamicTicket(code: code, baseURL: configuration.baseURL, token: token))
    }
    public func verifyCoupon(code: String, token: String) async throws -> OrderVerificationReceipt {
        try requireFixture()
        return try await receipt(OrderLifecycleRequestContract.verifyCoupon(code: code, baseURL: configuration.baseURL, token: token))
    }
    private func receipt(_ request: URLRequest) async throws -> OrderVerificationReceipt {
        let data = try await execute(request, permitChoiceBusinessCode: true)
        return try JSONDecoder().decode(OrderVerificationReceipt.self, from: data)
    }
    private struct DataEnvelope<Value: Decodable>: Decodable { let data: Value }
    private func value<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        try JSONDecoder().decode(DataEnvelope<Value>.self, from: await execute(request)).data
    }
    private func execute(_ request: URLRequest, permitChoiceBusinessCode: Bool = false) async throws -> Data {
        try requireFixture(); try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw OrderLifecycleFailure.accessDenied }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        struct Status: Decodable { let code: Int; let msg: String? }
        let envelope = try JSONDecoder().decode(Status.self, from: data)
        if envelope.code == 401 { throw APIError.unauthorized }
        if envelope.code == 403 { throw OrderLifecycleFailure.accessDenied }
        if envelope.code == 410 { throw OrderLifecycleFailure.unavailable }
        if !permitChoiceBusinessCode && envelope.code != 200 { throw OrderLifecycleFailure.response(code: envelope.code, message: envelope.msg) }
        return data
    }
}
