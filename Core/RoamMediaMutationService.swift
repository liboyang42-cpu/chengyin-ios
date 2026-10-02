import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A separate purpose-bound boundary. Read authorization or a camera grant never grants writes.
@MainActor public protocol RoamMediaMutationExecuting {
    var enabled: Bool { get }
    var scope: RetainedImageScope? { get }
    func execute(_ mutation: RoamExperienceMutation) async throws -> Data
}
@MainActor public struct RoamMediaMutationService: RoamMediaMutationExecuting {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let approvedImageOrigins: Set<String>
    private let approval: OperationEndpointApproval?
    private let currentScope: () -> RetainedImageScope?
    private let token: () -> String?
    public let enabled: Bool
    public var scope: RetainedImageScope? { currentScope() }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Bool = false,
                approval: OperationEndpointApproval? = nil, approvedImageOrigins: Set<String> = [], currentScope: @escaping () -> RetainedImageScope?, token: @escaping () -> String?) {
        self.configuration = configuration; self.transport = transport; self.enabled = enabled
        self.approvedImageOrigins = approvedImageOrigins; self.approval = approval; self.currentScope = currentScope; self.token = token
    }
    public func execute(_ mutation: RoamExperienceMutation) async throws -> Data {
        guard enabled else { throw RetainedImageFailure.disabled }
        guard let captured = scope, let namespace = captured.namespace,
              captured.realm == configuration.baseURL.absoluteString,
              let credential = token(), AuthRequestBuilder.isValidToken(credential) else { throw RetainedImageFailure.stale }
        switch mutation {
        case .createStamp(let picture, _, _):
            guard captured.destination == .stamp, let url = URL(string: picture), RetainedImageOrigin.accepts(url, origins: approvedImageOrigins) else { throw RetainedImageFailure.invalid }
        case .completeNode(let id, _, _, _, _):
            guard captured.destination == .roamPoster(poiID: id) else { throw RetainedImageFailure.invalid }
        default: throw RetainedImageFailure.invalid
        }
        guard approval?.allows(configuration: configuration, namespace: namespace, accountID: captured.accountID, path: mutation.path) == true else { throw RetainedImageFailure.disabled }
        let request = try mutation.request(configuration: configuration, token: credential)
        try Task.checkCancellation()
        let (bytes, status) = try await transport.send(request)
        guard !Task.isCancelled, scope == captured, token() == credential else { throw RetainedImageFailure.unknown }
        guard (200..<300).contains(status), bytes.count <= 1024 * 1024 else { throw RetainedImageFailure.unknown }
        struct Status: Decodable { let code: Int }
        guard let envelope = try? JSONDecoder().decode(Status.self, from: bytes) else { throw RetainedImageFailure.unknown }
        if envelope.code != 200 { throw RetainedImageFailure.rejected(envelope.code, nil) }
        return bytes
    }
}
