import Foundation

public struct ShopNPCHTTPRequest {
    public let path: String
    public let method: String
    public let contentType: String
    public let body: Data
    public let scope: ShopNPCScope
}
public struct ShopNPCHTTPResponse {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) { self.status = status; self.body = body }
}
/// Inject the app's authenticated, production-write-gated transport. Never a bare upload client.
@MainActor public protocol ShopNPCHTTPTransport {
    func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse
    /// Local authority read only. Restoring a view must never transmit a request.
    func validateResume(scope: ShopNPCScope, grants: ShopNPCGrants) throws
}
public extension ShopNPCHTTPTransport {
    /// A transport without an authoritative session source cannot restore private content.
    func validateResume(scope: ShopNPCScope, grants: ShopNPCGrants) throws { throw ShopNPCFailure.disabled }
}
@MainActor public struct ShopNPCHTTPClient {
    private let transport: any ShopNPCHTTPTransport
    public init(transport: any ShopNPCHTTPTransport) { self.transport = transport }
    public func validateResume(scope: ShopNPCScope, grants: ShopNPCGrants) throws {
        try transport.validateResume(scope: scope, grants: grants)
    }
    public func text(_ message: String, requestID: UUID, scope: ShopNPCScope) async throws -> ShopNPCReply {
        struct Body: Encodable { let requestId: String; let nodeId: Int; let message: String }
        let bytes = try JSONEncoder().encode(Body(requestId: requestID.uuidString, nodeId: scope.nodeID.rawValue, message: message))
        return try await dispatch(path: "/api/ai/npc/shop-chat", type: "application/json", body: bytes, scope: scope, voice: false)
    }
    public func voice(_ clip: ShopNPCVoiceClip, requestID: UUID, scope: ShopNPCScope) async throws -> ShopNPCReply {
        let boundary = "ShopNPC-\(UUID().uuidString)"
        var data = Data()
        func append(_ value: String) { data.append(Data(value.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voice.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n")
        data.append(clip.bytes)
        append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"nodeId\"\r\n\r\n\(scope.nodeID.rawValue)")
        append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"requestId\"\r\n\r\n\(requestID.uuidString)\r\n--\(boundary)--\r\n")
        return try await dispatch(path: "/api/ai/npc/voice-chat", type: "multipart/form-data; boundary=\(boundary)", body: data, scope: scope, voice: true)
    }
    private func dispatch(path: String, type: String, body: Data, scope: ShopNPCScope, voice: Bool) async throws -> ShopNPCReply {
        let response: ShopNPCHTTPResponse
        do { response = try await transport.perform(.init(path: path, method: "POST", contentType: type, body: body, scope: scope)) }
        catch let failure as ShopNPCFailure where failure == .disabled || failure == .stale || failure == .invalid { throw failure }
        catch { throw ShopNPCFailure.unknownOutcome }
        if response.status == 429 { throw ShopNPCFailure.rateLimited }
        guard (200..<300).contains(response.status) else { throw ShopNPCFailure.unknownOutcome }
        return try ShopNPCReply.decode(response.body, voice: voice)
    }
}
