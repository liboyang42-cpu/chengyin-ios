import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Concrete authenticated bridge for the merchant-row JSON contract only.
/// Endpoint approval and provider/legal/media capabilities are independent and default off.
@MainActor public final class MerchantNPCAuthenticatedTransport: MerchantNPCHTTPTransport {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let enabled: Bool
    private let scope: (PublicMerchantRowID) -> MerchantNPCScope?
    private let token: () -> String?
    private let grants: () -> MerchantNPCGrants
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Bool = false,
                currentScope: @escaping (PublicMerchantRowID) -> MerchantNPCScope?,
                token: @escaping () -> String?, grants: @escaping () -> MerchantNPCGrants = { .init() }) {
        self.configuration = configuration; self.transport = transport; self.enabled = enabled
        scope = currentScope; self.token = token; self.grants = grants
    }
    public func perform(_ input: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
        guard enabled else { throw MerchantNPCFailure.disabled }
        guard scope(input.scope.merchantRowID) == input.scope, let credential = token(), AuthRequestBuilder.isValidToken(credential) else { throw MerchantNPCFailure.staleScope }
        let policy = grants()
        guard input.method == "POST", input.body.count <= 128 * 1024,
              let fields = try? JSONSerialization.jsonObject(with: input.body) as? [String: Any] else { throw MerchantNPCFailure.invalid }
        let expected: Set<String>
        switch input.path {
        case "/api/ai/npc/merchant-chat":
            guard policy.chatAllowed, fields["bizId"] as? Int == input.scope.merchantRowID.rawValue else { throw MerchantNPCFailure.disabled }
            expected = ["requestId", "bizId", "message"]
        case "/api/merchant/npc/voice/script":
            guard policy.resourceAllowed else { throw MerchantNPCFailure.disabled }; expected = []
        case "/api/merchant/npc/voice/enroll":
            guard policy.resourceAllowed, policy.voiceCloning else { throw MerchantNPCFailure.disabled }; expected = ["sampleUrls", "requestId"]
        case "/api/merchant/npc/voice/revoke":
            guard policy.resourceAllowed else { throw MerchantNPCFailure.disabled }; expected = ["requestId"]
        case "/api/merchant/npc/avatar/generate":
            guard policy.resourceAllowed else { throw MerchantNPCFailure.disabled }; expected = ["imageUrl", "style"]
        default: throw MerchantNPCFailure.invalid
        }
        guard Set(fields.keys) == expected else { throw MerchantNPCFailure.invalid }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(String(input.path.dropFirst())))
        request.httpMethod = "POST"; request.httpBody = input.body; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credential, forHTTPHeaderField: "Authorization")
        try Task.checkCancellation()
        guard scope(input.scope.merchantRowID) == input.scope, token() == credential, grants() == policy else { throw MerchantNPCFailure.staleScope }
        let result: (Data, Int)
        do { result = try await transport.send(request) } catch { throw MerchantNPCFailure.unknownOutcome }
        guard !Task.isCancelled, scope(input.scope.merchantRowID) == input.scope, token() == credential,
              grants() == policy, result.0.count <= 1024 * 1024 else { throw MerchantNPCFailure.unknownOutcome }
        let envelope = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any]
        guard result.1 != 401, envelope?["code"] as? Int != 401 else { throw MerchantNPCFailure.unknownOutcome }
        return .init(status: result.1, body: result.0)
    }
}
