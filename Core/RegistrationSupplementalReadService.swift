import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Three existing read-only POST routes. No default transport/configuration, payment,
/// polling, retry, create, cancellation, capability grants or persistent data.
public struct RegistrationSupplementalReadService {
    let configuration: APIConfiguration
    private let transport: any HTTPTransport

    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    public func paymentReadiness(token: String) async throws -> RegistrationPaymentReadinessSnapshot {
        let value: RegistrationPaymentReadinessSnapshot? = try await read(
            path: "api/registration/payment-readiness", fields: [:], token: token)
        guard let value else { throw APIError.malformedResponse }
        return value
    }

    /// The backend ignores member_id and uses the authenticated principal. Never send
    /// an account selector. Empty success means no joined registration, not a lost order.
    /// This route is not an original create receipt and must not clear a pending create.
    public func joinedRegistration(accountID: Int, token: String) async throws -> OrderLifecycleDetail? {
        guard accountID > 0 else { throw APIError.invalidRequest }
        let value: OrderLifecycleDetail? = try await read(
            path: "api/registration/join_info", fields: [:], token: token)
        if let value, value.memberID != accountID { throw APIError.malformedResponse }
        return value
    }

    /// Server-side owner/club/MerchantPermission checks decide access. Client role names
    /// are not used as permission, and these counts are never checkout eligibility.
    public func countsByDate(scope: RegistrationCountScope, token: String) async throws -> [RegistrationDailyCount] {
        let value: [RegistrationDailyCount]? = try await read(path: "api/registration/count_by_date",
            fields: ["owner_type": String(scope.kind.rawValue), "owner_id": String(scope.ownerID)], token: token)
        guard let value, Set(value.map(\.participateDate)).count == value.count else {
            throw APIError.malformedResponse
        }
        return value
    }

    private func read<Value: Decodable>(path: String, fields: [String: String], token: String) async throws -> Value? {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        let request = try AuthRequestBuilder.makeFormRequest(
            url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        do {
            return try JSONDecoder().decode(Envelope<Value>.self, from: data).data
        } catch let failure as RegistrationResponseFailure {
            throw failure
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.malformedResponse
        }
    }

    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value?
        private enum CodingKeys: String, CodingKey { case code, msg, data }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let numericCode = try? values.decode(Int.self, forKey: .code)
            let stringCode = try? values.decode(String.self, forKey: .code)
            let code = numericCode ?? stringCode.flatMap(Int.init)
            if code == 401 { throw APIError.unauthorized }
            guard code == 200 else {
                throw RegistrationResponseFailure(code: code, message: try? values.decode(String.self, forKey: .msg))
            }
            // AjaxResult.success() intentionally has no data for an absent join_info.
            // The other two methods require data after decoding this envelope.
            data = try values.decodeIfPresent(Value.self, forKey: .data)
        }
    }
}
