import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An HTTP failure remains distinct from an AjaxResult business failure, without losing
/// a supplied server code/message. In particular, HTTP 401 is not a retry instruction.
public struct RegistrationHTTPFailure: Error, Equatable {
    public let statusCode: Int
    public let response: RegistrationResponseFailure?
}

/// A narrow readback of `/api/registration/info`, not an order-detail or payment verdict.
/// Missing statuses remain unknown; future/unknown numeric values are preserved.
public struct RegistrationStatusSnapshot: Decodable, Equatable {
    public let registrationID: Int
    public let registrationNo: String?
    public let registrationStatus: Int?
    public let paymentStatus: Int?
    public let verificationStatus: Int?

    private enum CodingKeys: String, CodingKey {
        case id, registrationNo, registrationStatus, paymentStatus, verificationStatus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        registrationID = try c.decode(Int.self, forKey: .id)
        guard registrationID > 0 else { throw APIError.malformedResponse }
        registrationNo = try c.decodeIfPresent(String.self, forKey: .registrationNo)
        registrationStatus = try c.decodeIfPresent(Int.self, forKey: .registrationStatus)
        paymentStatus = try c.decodeIfPresent(Int.self, forKey: .paymentStatus)
        verificationStatus = try c.decodeIfPresent(Int.self, forKey: .verificationStatus)
    }
}

/// Source-aligned activity registration operations. Each method sends at most one request.
/// This layer does not obtain consent, refresh credentials, execute payment, poll, retry,
/// create replacement intents, or interpret a create response as completed registration.
/// Use the existing no-redirect URLSessionTransport for real requests; injected transports
/// must also avoid redirects and retries. There is deliberately no default configuration.
public struct RegistrationService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport

    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    public func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote {
        let request = try jsonRequest("api/registration/quote", value: selection, token: token)
        return try await execute(request)
    }

    /// The caller must retain the exact intent across uncertain outcomes. Calling this
    /// method does not re-quote, alter its signature, or generate another request ID.
    /// A transport failure can leave an order created on the server; it is not proof of failure.
    public func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult {
        let request = try jsonRequest("api/registration/create", value: intent, token: token)
        return try await execute(request)
    }

    /// One explicit read for a known registration ID. This cannot reconcile an unknown ID
    /// after a create timeout; no lookup-by-requestId contract has been established here.
    public func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot {
        guard registrationID > 0, AuthRequestBuilder.isValidToken(token) else {
            throw APIError.invalidRequest
        }
        let request = try AuthRequestBuilder.makeFormRequest(
            url: configuration.baseURL.appendingPathComponent("api/registration/info"),
            fields: ["id": String(registrationID)], token: token
        )
        let snapshot: RegistrationStatusSnapshot = try await execute(request)
        guard snapshot.registrationID == registrationID else { throw APIError.malformedResponse }
        return snapshot
    }

    private func jsonRequest<Value: Encodable>(_ path: String, value: Value, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        request.httpBody = try encoder.encode(value)
        return request
    }

    private func execute<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(status) else {
            let envelope = try? JSONDecoder().decode(HTTPFailureEnvelope.self, from: data)
            throw RegistrationHTTPFailure(statusCode: status, response: envelope?.failure)
        }
        do {
            return try JSONDecoder().decode(RegistrationResponse<Value>.self, from: data).data
        } catch let failure as RegistrationResponseFailure {
            throw failure
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.malformedResponse
        }
    }

    /// Do not attempt to decode success data from a non-2xx response or discard its
    /// envelope because its data is malformed. Unknown/absent code and message stay nil.
    private struct HTTPFailureEnvelope: Decodable {
        let failure: RegistrationResponseFailure?
        private enum CodingKeys: String, CodingKey { case code, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let numericCode = try? c.decode(Int.self, forKey: .code)
            let stringCode = try? c.decode(String.self, forKey: .code)
            let code = numericCode ?? stringCode.flatMap(Int.init)
            let message = try? c.decode(String.self, forKey: .msg)
            failure = code != nil || message != nil
                ? RegistrationResponseFailure(code: code, message: message) : nil
        }
    }
}
