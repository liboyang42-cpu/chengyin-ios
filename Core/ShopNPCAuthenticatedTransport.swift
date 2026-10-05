import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ephemeral host binding. Credentials never appear in the public conversation scope.
public struct ShopNPCHostSession: Equatable {
    public let scope: ShopNPCScope
    let token: String
    public init(scope: ShopNPCScope, token: String) throws {
        guard scope.valid, AuthRequestBuilder.isValidToken(token) else { throw ShopNPCFailure.stale }
        self.scope = scope; self.token = token
    }
}

/// Concrete central-HTTP adapter. Both production dispatch and all policy grants default OFF.
/// There is no unauthenticated fallback, retry, alternate endpoint, or media provider.
@MainActor public final class ShopNPCAuthenticatedHTTPTransport: ShopNPCHTTPTransport {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let productionWritesEnabled: Bool
    private let currentSession: () -> ShopNPCHostSession?
    private let currentGrants: () -> ShopNPCGrants
    private let onUnauthorized: (ShopNPCHostSession) -> Void
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                productionWritesEnabled: Bool = false,
                currentSession: @escaping () -> ShopNPCHostSession?,
                currentGrants: @escaping () -> ShopNPCGrants = { .init() },
                onUnauthorized: @escaping (ShopNPCHostSession) -> Void = { _ in }) {
        self.configuration = configuration; self.transport = transport
        self.productionWritesEnabled = productionWritesEnabled; self.currentSession = currentSession
        self.currentGrants = currentGrants; self.onUnauthorized = onUnauthorized
    }
    public func perform(_ input: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse {
        guard productionWritesEnabled else { throw ShopNPCFailure.disabled }
        guard let captured = currentSession(), captured.scope == input.scope else { throw ShopNPCFailure.stale }
        let grants = currentGrants()
        let voice = input.path == "/api/ai/npc/voice-chat"
        guard input.method == "POST", input.path == "/api/ai/npc/shop-chat" || voice,
              !input.body.isEmpty, input.body.count <= 3 * 1024 * 1024 else { throw ShopNPCFailure.invalid }
        guard voice ? grants.voiceAllowed : grants.textAllowed else { throw ShopNPCFailure.disabled }
        if voice {
            guard input.contentType.hasPrefix("multipart/form-data; boundary=ShopNPC-") else { throw ShopNPCFailure.invalid }
        } else {
            guard input.contentType == "application/json",
                  let fields = try? JSONSerialization.jsonObject(with: input.body) as? [String: Any],
                  Set(fields.keys) == Set(["requestId", "nodeId", "message"]),
                  let node = fields["nodeId"] as? Int, node == captured.scope.nodeID.rawValue,
                  let requestID = fields["requestId"] as? String, UUID(uuidString: requestID) != nil,
                  let message = fields["message"] as? String,
                  !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ShopNPCFailure.invalid }
        }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(String(input.path.dropFirst())))
        request.httpMethod = "POST"; request.httpBody = input.body
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue(captured.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(input.contentType, forHTTPHeaderField: "Content-Type")
        try Task.checkCancellation()
        // Revalidate the authenticated account, role, node and access revision immediately before dispatch.
        guard currentSession() == captured, currentGrants() == grants else { throw ShopNPCFailure.stale }
        let bytes: Data, status: Int
        do { (bytes, status) = try await transport.send(request) }
        catch { throw ShopNPCFailure.unknownOutcome }
        try Task.checkCancellation()
        guard currentSession() == captured, currentGrants() == grants else { throw ShopNPCFailure.unknownOutcome }
        let envelope = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        if status == 401 || (envelope?["code"] as? Int) == 401 {
            onUnauthorized(captured); throw ShopNPCFailure.unknownOutcome
        }
        return .init(status: status, body: bytes)
    }
}
