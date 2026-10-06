import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Existing legacy story-media upload only. The response is a URL reference, not asset ownership,
/// immutable byte/version evidence, a review decision, or a W02 release dependency.
public struct ProjectStoryImageUploadApproval: Equatable {
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int
    public let approvedOrigins: Set<String>
    public let nativePicker: Bool
    public init(baseURL: URL, namespace: String, accountID: Int,
                approvedOrigins: Set<String> = [], nativePicker: Bool = false) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard accountID > 0, !namespace.isEmpty else { throw APIError.invalidConfiguration }
        self.baseURL = baseURL; self.namespace = namespace; self.accountID = accountID
        self.approvedOrigins = approvedOrigins; self.nativePicker = nativePicker
    }
    public func matches(configuration: APIConfiguration, session: ProjectEditSession) -> Bool {
        baseURL == configuration.baseURL && namespace == session.storageNamespace &&
            accountID == session.accountID && !approvedOrigins.isEmpty
    }
}

public struct ProjectStoryImageCredentials: Equatable {
    public let session: ProjectEditSession
    fileprivate let token: String
    public init(session: ProjectEditSession, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.session = session; self.token = token
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session == rhs.session && lhs.token.utf8.elementsEqual(rhs.token.utf8)
    }
}

public enum ProjectStoryImageFailure: Error, Equatable {
    case notConfigured, changedContext, invalidResponse, outcomeUnknown, persistenceUnavailable
}

public struct ProjectStoryUploadedImage: Equatable, Sendable {
    public let attemptID: UUID
    public let ownerKey: String
    public let reference: String
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.attemptID == rhs.attemptID && lhs.ownerKey.utf8.elementsEqual(rhs.ownerKey.utf8) &&
            lhs.reference.utf8.elementsEqual(rhs.reference.utf8)
    }
    fileprivate init(attemptID: UUID, ownerKey: String, reference: String) {
        self.attemptID = attemptID; self.ownerKey = ownerKey; self.reference = reference
    }
    static func restore(attemptID: UUID, ownerKey: String, reference: String) throws -> Self {
        guard !ownerKey.isEmpty, let url = URL(string: reference), let host = url.host else { throw ProjectStoryImageFailure.invalidResponse }
        let origin = "https://" + host.lowercased() + (url.port.map { ":\($0)" } ?? "")
        guard validReference(reference, origins: [origin]) else { throw ProjectStoryImageFailure.invalidResponse }
        // Historical local fact only; a fresh source capability must still permit this origin at apply.
        return .init(attemptID: attemptID, ownerKey: ownerKey, reference: reference)
    }
    static func validReference(_ raw: String, origins: Set<String>) -> Bool {
        guard !raw.isEmpty, raw.utf8.count <= 8192, raw.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }),
              let url = URL(string: raw) else { return false }
        return RetainedImageOrigin.accepts(url, origins: origins)
    }
}

@MainActor public protocol ProjectStoryImageUploading: AnyObject {
    func isCurrent(session: ProjectEditSession) -> Bool
    func permitsPicker(session: ProjectEditSession) -> Bool
    func permitsReference(_ reference: String, session: ProjectEditSession) -> Bool
    func upload(_ image: RetainedSelectedImage, attemptID: UUID, session: ProjectEditSession) async throws -> ProjectStoryUploadedImage
}

/// Matches Mini app.chooseImage → upload-client exactly: file plus bizType=image_free.
/// Its default response transport and independent deployment/account approval are both off.
@MainActor public final class ProjectStoryImageUploadClient: ProjectStoryImageUploading {
    public static let path = "api/common/uploadOSS"
    private let configuration: APIConfiguration
    private let approval: ProjectStoryImageUploadApproval?
    private let transport: any HTTPTransport
    private let credentials: () -> ProjectStoryImageCredentials?
    private let currentApproval: () -> ProjectStoryImageUploadApproval?
    public init(configuration: APIConfiguration, approval: ProjectStoryImageUploadApproval? = nil,
                transport: any HTTPTransport = ResponseLimitedHTTPTransport(maximumResponseBytes: 64 * 1024),
                credentials: @escaping () -> ProjectStoryImageCredentials?,
                currentApproval: @escaping () -> ProjectStoryImageUploadApproval?) {
        self.configuration = configuration; self.approval = approval; self.transport = transport
        self.credentials = credentials; self.currentApproval = currentApproval
    }
    public func isCurrent(session: ProjectEditSession) -> Bool {
        guard let approval, currentApproval() == approval, credentials()?.session == session else { return false }
        return approval.matches(configuration: configuration, session: session)
    }
    public func permitsPicker(session: ProjectEditSession) -> Bool {
        isCurrent(session: session) && approval?.nativePicker == true
    }
    public func permitsReference(_ reference: String, session: ProjectEditSession) -> Bool {
        isCurrent(session: session) && ProjectStoryUploadedImage.validReference(reference, origins: approval?.approvedOrigins ?? [])
    }
    private func check(_ original: ProjectStoryImageCredentials) throws {
        try Task.checkCancellation()
        guard credentials() == original, isCurrent(session: original.session) else { throw ProjectStoryImageFailure.changedContext }
    }
    public func upload(_ image: RetainedSelectedImage, attemptID: UUID, session: ProjectEditSession) async throws -> ProjectStoryUploadedImage {
        guard isCurrent(session: session), let original = credentials(), original.session == session else { throw ProjectStoryImageFailure.notConfigured }
        try check(original)
        let boundary = "ProjectStoryImage-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\nimage_free\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"story.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(image.jpeg); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(Self.path))
        request.httpMethod = "POST"; request.httpBody = body; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue(original.token, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (bytes, status) = try await transport.send(request)
        try check(original)
        if status == 401 { throw APIError.unauthorized }
        guard status == 200, bytes.count <= 64 * 1024 else { throw ProjectStoryImageFailure.outcomeUnknown }
        let row = try ApprovedTopicReleaseWire.envelope(bytes)
        if row["code"]?.integer == 401 { throw APIError.unauthorized }
        guard row["code"]?.integer == 200, let reference = row["url"]?.text,
              permitsReference(reference, session: session) else { throw ProjectStoryImageFailure.invalidResponse }
        // Preserve the exact returned reference bytes. Never derive a content digest from this URL.
        return .init(attemptID: attemptID, ownerKey: session.ownerKey, reference: reference)
    }
}
