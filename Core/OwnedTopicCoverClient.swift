import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OwnedTopicCoverOperation: String, Hashable, Sendable { case readCurrent, upload, select, status, readAsset }
/// Independently reviewed author-only deployment/account capability. Login and a reference never construct it.
public struct OwnedTopicCoverApproval: Equatable {
    public let baseURL: URL, namespace: String, accountID: Int
    public let operations: Set<OwnedTopicCoverOperation>
    public let nativePicker: Bool
    public init(baseURL: URL, namespace: String, accountID: Int, operations: Set<OwnedTopicCoverOperation> = [], nativePicker: Bool = false) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard !namespace.isEmpty, accountID > 0 else { throw APIError.invalidConfiguration }
        self.baseURL = baseURL; self.namespace = namespace; self.accountID = accountID; self.operations = operations; self.nativePicker = nativePicker
    }
    public func permits(_ operation: OwnedTopicCoverOperation, configuration: APIConfiguration, session: ProjectEditSession) -> Bool {
        baseURL == configuration.baseURL && namespace == session.storageNamespace && accountID == session.accountID && operations.contains(operation)
    }
}
public struct OwnedTopicCoverCredentials: Equatable {
    public let session: ProjectEditSession
    fileprivate let token: String
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.session == rhs.session && Data(lhs.token.utf8) == Data(rhs.token.utf8) }
    public init(session: ProjectEditSession, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.session = session; self.token = token
    }
}
@MainActor public protocol OwnedTopicCoverServing: AnyObject {
    func isCurrent(session: ProjectEditSession) -> Bool
    func permits(_ operation: OwnedTopicCoverOperation, session: ProjectEditSession) -> Bool
    func permitsNativePicker(session: ProjectEditSession) -> Bool
    func current(topicID: Int, session: ProjectEditSession) async throws -> OwnedTopicCoverCurrent
    func upload(_ selection: RetainedSelectedImage, session: ProjectEditSession) async throws -> OwnedTopicCoverAsset
    func select(_ command: OwnedTopicCoverSelectionCommand, session: ProjectEditSession) async throws -> OwnedTopicCoverSelectionReceipt
    func status(_ command: OwnedTopicCoverSelectionCommand, session: ProjectEditSession) async throws -> OwnedTopicCoverSelectionReceipt
    func content(_ asset: OwnedTopicCoverAsset, session: ProjectEditSession) async throws -> Data
}

/// Uses only runtime producer paths. JSON and byte transports must be bounded/no-redirect in production.
@MainActor public final class OwnedTopicCoverClient: OwnedTopicCoverServing {
    public static let currentPath = "api/topic/cover/selection/current"
    public static let uploadPath = "api/topic/cover/upload"
    public static let selectPath = "api/topic/cover/selection"
    public static let statusPath = "api/topic/cover/selection/status"
    public static let maximumContentBytes = 10 * 1024 * 1024
    private let configuration: APIConfiguration
    private let approval: OwnedTopicCoverApproval?
    private let jsonTransport: any HTTPTransport, imageTransport: any HTTPTransport
    private let credentials: () -> OwnedTopicCoverCredentials?
    private let currentApproval: () -> OwnedTopicCoverApproval?
    public init(configuration: APIConfiguration, approval: OwnedTopicCoverApproval? = nil,
                jsonTransport: any HTTPTransport, imageTransport: any HTTPTransport,
                currentCredentials: @escaping () -> OwnedTopicCoverCredentials?, currentApproval: @escaping () -> OwnedTopicCoverApproval?) {
        self.configuration = configuration; self.approval = approval; self.jsonTransport = jsonTransport; self.imageTransport = imageTransport
        credentials = currentCredentials; self.currentApproval = currentApproval
    }
    public func isCurrent(session: ProjectEditSession) -> Bool {
        guard let approval, let current = credentials(), current.session == session, currentApproval() == approval else { return false }
        return approval.baseURL == configuration.baseURL && approval.namespace == session.storageNamespace && approval.accountID == session.accountID
    }
    public func permits(_ operation: OwnedTopicCoverOperation, session: ProjectEditSession) -> Bool {
        isCurrent(session: session) && approval?.permits(operation, configuration: configuration, session: session) == true
    }
    public func permitsNativePicker(session: ProjectEditSession) -> Bool { permits(.upload, session: session) && approval?.nativePicker == true }
    private func capture(_ operation: OwnedTopicCoverOperation, session: ProjectEditSession) throws -> OwnedTopicCoverCredentials {
        try Task.checkCancellation()
        guard permits(operation, session: session), let current = credentials(), current.session == session else { throw OwnedTopicCoverFailure.notConfigured }
        return current
    }
    private func check(_ original: OwnedTopicCoverCredentials, operation: OwnedTopicCoverOperation) throws {
        try Task.checkCancellation()
        guard credentials() == original, permits(operation, session: original.session) else { throw OwnedTopicCoverFailure.changedContext }
    }
    private func get(path: String, query: [URLQueryItem], token: String) throws -> URLRequest {
        guard var url = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
        url.queryItems = query
        guard let target = url.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: target); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    private func decode(_ bytes: Data, status: Int, mutation: Bool = false) throws -> ProjectEditJSON {
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw OwnedTopicCoverFailure.forbidden }
        if status == 409 { throw OwnedTopicCoverFailure.outcomeUnknown }
        guard bytes.count <= 64 * 1024 else { throw OwnedTopicCoverFailure.invalidResponse }
        guard (200..<300).contains(status) else { throw mutation ? OwnedTopicCoverFailure.outcomeUnknown : .unavailable }
        let envelope = try ApprovedTopicReleaseWire.envelope(bytes)
        if envelope["code"]?.integer == 401 { throw APIError.unauthorized }
        guard envelope["code"]?.integer == 200, let value = envelope["data"] else { throw mutation ? OwnedTopicCoverFailure.outcomeUnknown : .invalidResponse }
        return value
    }
    public func current(topicID: Int, session: ProjectEditSession) async throws -> OwnedTopicCoverCurrent {
        guard topicID > 0 else { throw OwnedTopicCoverFailure.invalidResponse }
        let original = try capture(.readCurrent, session: session)
        let request = try get(path: Self.currentPath, query: [.init(name: "topicId", value: String(topicID))], token: original.token)
        let (bytes, status) = try await jsonTransport.send(request); try check(original, operation: .readCurrent)
        return try .decode(decode(bytes, status: status), topicID: topicID, owner: session.accountID)
    }
    public func upload(_ selection: RetainedSelectedImage, session: ProjectEditSession) async throws -> OwnedTopicCoverAsset {
        let original = try capture(.upload, session: session)
        guard !selection.jpeg.isEmpty, selection.jpeg.count <= RetainedSelectedImage.maximumBytes else { throw OwnedTopicCoverFailure.invalidResponse }
        let boundary = "Cover-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"cover.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(selection.jpeg); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(Self.uploadPath)); request.httpMethod = "POST"
        request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(original.token, forHTTPHeaderField: "Authorization"); request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"); request.httpBody = body
        let (bytes, status) = try await jsonTransport.send(request); try check(original, operation: .upload)
        // The producer sanitizes again. Only its exact subsequent content read can prove its output bytes.
        return try .decode(decode(bytes, status: status, mutation: true), owner: session.accountID)
    }
    private func selection(_ command: OwnedTopicCoverSelectionCommand, session: ProjectEditSession, operation: OwnedTopicCoverOperation) async throws -> OwnedTopicCoverSelectionReceipt {
        guard command.asset.ownerMemberID == session.accountID, command.topicID > 0 else { throw OwnedTopicCoverFailure.invalidResponse }
        let original = try capture(operation, session: session)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(command.fields)
        guard body.count <= 2048 else { throw OwnedTopicCoverFailure.invalidResponse }
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: operation == .select ? Self.selectPath : Self.statusPath, body: body, token: original.token)
        let (bytes, status) = try await jsonTransport.send(request); try check(original, operation: operation)
        return try .decode(decode(bytes, status: status, mutation: operation == .select), command: command)
    }
    public func select(_ command: OwnedTopicCoverSelectionCommand, session: ProjectEditSession) async throws -> OwnedTopicCoverSelectionReceipt { try await selection(command, session: session, operation: .select) }
    public func status(_ command: OwnedTopicCoverSelectionCommand, session: ProjectEditSession) async throws -> OwnedTopicCoverSelectionReceipt { try await selection(command, session: session, operation: .status) }
    public func content(_ asset: OwnedTopicCoverAsset, session: ProjectEditSession) async throws -> Data {
        guard asset.ownerMemberID == session.accountID else { throw OwnedTopicCoverFailure.forbidden }
        let original = try capture(.readAsset, session: session)
        let request = try get(path: asset.contentPath, query: [.init(name: "sourceVersion", value: asset.sourceVersion), .init(name: "contentHash", value: asset.contentHash)], token: original.token)
        let (bytes, status) = try await imageTransport.send(request); try check(original, operation: .readAsset)
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw OwnedTopicCoverFailure.forbidden }
        guard status == 200, !bytes.isEmpty, bytes.count <= Self.maximumContentBytes,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == asset.contentHash else { throw OwnedTopicCoverFailure.invalidResponse }
        return bytes
    }
}
