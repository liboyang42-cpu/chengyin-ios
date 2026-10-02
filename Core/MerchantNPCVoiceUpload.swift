import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// PublishApi.uploadFile: multipart file + fileType=m4a, code=200, top-level url.
/// Not ShopNPC voice-chat and not an invented media-registration endpoint.
@MainActor public final class MerchantNPCVoiceUpload: MerchantNPCVoiceUploading {
    private let configuration: APIConfiguration
    private let limits: MerchantNPCVoiceConfiguration
    private let transport: any HTTPTransport
    private let approval: OperationEndpointApproval?
    private let enabled: Bool
    private let currentScope: () -> MerchantNPCScope?
    private let token: () -> String?
    private let grants: () -> MerchantNPCGrants
    public var destination: String { configuration.baseURL.appendingPathComponent("api/common/uploadOSS").absoluteString }
    /// Default production seam is bounded and independently OFF. Test doubles may be injected;
    /// approved activation must retain ResponseLimitedHTTPTransport and independent voice grants.
    public init(configuration: APIConfiguration, limits: MerchantNPCVoiceConfiguration, transport: any HTTPTransport = ResponseLimitedHTTPTransport(), enabled: Bool = false, approval: OperationEndpointApproval? = nil, currentScope: @escaping () -> MerchantNPCScope?, token: @escaping () -> String?, grants: @escaping () -> MerchantNPCGrants = { .init() }) {
        self.configuration = configuration; self.limits = limits; self.transport = transport; self.enabled = enabled; self.approval = approval; self.currentScope = currentScope; self.token = token; self.grants = grants
    }
    public func upload(_ clip: MerchantNPCVoiceClip, index: Int, scope: MerchantNPCScope) async throws -> MerchantNPCMediaReference {
        let policy = grants()
        guard enabled, policy.resourceAllowed, policy.voiceCloning, approval?.allows(configuration: configuration, namespace: scope.namespace, accountID: scope.accountID, path: "api/common/uploadOSS") == true else { throw MerchantNPCFailure.disabled }
        guard currentScope() == scope, (0..<5).contains(index), let credential = token(), AuthRequestBuilder.isValidToken(credential) else { throw MerchantNPCFailure.staleScope }
        try limits.validate(clip)
        let boundary = "MerchantVoice-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"fileType\"\r\n\r\nm4a\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"sample-\(index + 1).m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8)
        body.append(clip.bytes); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/common/uploadOSS"))
        request.httpMethod = "POST"; request.httpBody = body; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(credential, forHTTPHeaderField: "Authorization")
        try Task.checkCancellation()
        guard currentScope() == scope, token() == credential, grants() == policy else { throw MerchantNPCFailure.staleScope }
        let response: (Data, Int)
        do { response = try await transport.send(request) } catch { throw MerchantNPCFailure.unknownOutcome }
        guard !Task.isCancelled, currentScope() == scope, token() == credential, grants() == policy, response.1 == 200, response.0.count <= 1024 * 1024,
              let json = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any], json["code"] as? Int == 200,
              let raw = json["url"] as? String, let url = URL(string: raw) else { throw MerchantNPCFailure.unknownOutcome }
        do { return try .init(scope: scope, selectionID: clip.id, kind: .voiceSample(index: index), url: url, approvedHosts: limits.approvedHosts) }
        catch { throw MerchantNPCFailure.unknownOutcome }
    }
}
