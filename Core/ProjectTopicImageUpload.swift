import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Existing Mini professional-topic fields. These are not story/owned-cover grants.
public enum ProjectTopicImageField: String, Hashable { case cover, gallery }
public extension ProjectTopicImageField {
    var businessType: String { self == .cover ? "image_3_4" : "image_16_9" }
    var widthUnits: Int { self == .cover ? 3 : 16 }
    var heightUnits: Int { self == .cover ? 4 : 9 }
}
public struct ProjectTopicImageUploadApproval: Equatable {
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int
    public let fields: Set<ProjectTopicImageField>
    public let approvedOrigins: Set<String>
    public let policy: ProjectTopicMediaPolicy
    public let nativePicker: Bool
    /// All local limits and upload destinations must be explicitly reviewed. No defaults enable this capability.
    public init(baseURL: URL, namespace: String, accountID: Int, fields: Set<ProjectTopicImageField>,
                approvedOrigins: Set<String>, policy: ProjectTopicMediaPolicy, nativePicker: Bool = false) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard accountID > 0, !namespace.isEmpty, !fields.isEmpty, !approvedOrigins.isEmpty,
              policy.maximumItems == 1, policy.kinds.count == 1,
              policy.kinds[0].kind == .image, policy.kinds[0].mimeTypes == ["image/jpeg"] else { throw APIError.invalidConfiguration }
        self.baseURL = baseURL; self.namespace = namespace; self.accountID = accountID; self.fields = fields
        self.approvedOrigins = approvedOrigins; self.policy = policy; self.nativePicker = nativePicker
    }
    public func matches(configuration: APIConfiguration, session: ProjectEditSession) -> Bool {
        baseURL == configuration.baseURL && namespace.utf8.elementsEqual(session.storageNamespace.utf8) && accountID == session.accountID
    }
}
public struct ProjectTopicImageCredentials: Equatable {
    public let session: ProjectEditSession
    fileprivate let token: String
    public init(session: ProjectEditSession, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.session = session; self.token = token
    }
    public static func == (a: Self, b: Self) -> Bool { a.session == b.session && a.token.utf8.elementsEqual(b.token.utf8) }
}
public enum ProjectTopicImageFailure: Error, Equatable { case notConfigured, changedContext, invalidImage, invalidResponse, outcomeUnknown, alreadyAttempted }
/// A legacy URL reply, not immutable asset ownership, moderation or publication proof.
public struct ProjectTopicUploadedImage: Equatable {
    public let attemptID: UUID
    public let context: ProjectTopicMediaContext
    public let field: ProjectTopicImageField
    public let reference: String
    fileprivate init(attemptID: UUID, context: ProjectTopicMediaContext, field: ProjectTopicImageField, reference: String) {
        self.attemptID = attemptID; self.context = context; self.field = field; self.reference = reference
    }
}
@MainActor public protocol ProjectTopicImageUploading: AnyObject {
    func isCurrent(context: ProjectTopicMediaContext, field: ProjectTopicImageField) -> Bool
    func policy(context: ProjectTopicMediaContext, field: ProjectTopicImageField) -> ProjectTopicMediaPolicy?
    func permitsPicker(context: ProjectTopicMediaContext, field: ProjectTopicImageField) -> Bool
    func permittedURL(_ receipt: ProjectTopicUploadedImage, context: ProjectTopicMediaContext, field: ProjectTopicImageField) -> String?
    func upload(_ image: RetainedSelectedImage, attemptID: UUID, context: ProjectTopicMediaContext,
                field: ProjectTopicImageField) async throws -> ProjectTopicUploadedImage
}
@MainActor public final class ProjectTopicImageUploadClient: ProjectTopicImageUploading {
    public static let path = "api/common/uploadOSS"
    private let configuration: APIConfiguration
    private let approval: ProjectTopicImageUploadApproval?
    private let transport: any HTTPTransport
    private let credentials: () -> ProjectTopicImageCredentials?
    private let currentApproval: () -> ProjectTopicImageUploadApproval?
    private var attempts: Set<UUID> = []
    public init(configuration: APIConfiguration, approval: ProjectTopicImageUploadApproval? = nil,
                transport: any HTTPTransport = ResponseLimitedHTTPTransport(maximumResponseBytes: 64 * 1024),
                credentials: @escaping () -> ProjectTopicImageCredentials?, currentApproval: @escaping () -> ProjectTopicImageUploadApproval?) {
        self.configuration = configuration; self.approval = approval; self.transport = transport
        self.credentials = credentials; self.currentApproval = currentApproval
    }
    public func isCurrent(context: ProjectTopicMediaContext, field: ProjectTopicImageField) -> Bool {
        guard context.owner == .personal, context.publishMode == "pro", context.editScope == .full,
              let approval, currentApproval() == approval, approval.fields.contains(field),
              credentials()?.session == context.session else { return false }
        return approval.matches(configuration: configuration, session: context.session)
    }
    public func policy(context: ProjectTopicMediaContext, field: ProjectTopicImageField) -> ProjectTopicMediaPolicy? {
        isCurrent(context: context, field: field) ? approval?.policy : nil
    }
    public func permitsPicker(context: ProjectTopicMediaContext, field: ProjectTopicImageField) -> Bool {
        isCurrent(context: context, field: field) && approval?.nativePicker == true
    }
    private func validReference(_ reference: String, field: ProjectTopicImageField) -> Bool {
        guard !reference.isEmpty, reference.utf16.count <= (field == .cover ? 255 : 2000),
              reference.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }), let url = URL(string: reference),
              field != .gallery || (!reference.contains(",") && !reference.contains(";")) else { return false }
        return RetainedImageOrigin.accepts(url, origins: approval?.approvedOrigins ?? [])
    }
    public func permittedURL(_ receipt: ProjectTopicUploadedImage, context: ProjectTopicMediaContext, field: ProjectTopicImageField) -> String? {
        guard receipt.context == context, receipt.field == field, isCurrent(context: context, field: field),
              validReference(receipt.reference, field: field) else { return nil }
        return receipt.reference
    }
    private func check(_ original: ProjectTopicImageCredentials, context: ProjectTopicMediaContext, field: ProjectTopicImageField) throws {
        try Task.checkCancellation()
        guard credentials() == original, isCurrent(context: context, field: field) else { throw ProjectTopicImageFailure.changedContext }
    }
    public func upload(_ image: RetainedSelectedImage, attemptID: UUID, context: ProjectTopicMediaContext,
                       field: ProjectTopicImageField) async throws -> ProjectTopicUploadedImage {
        guard let policy = policy(context: context, field: field), let original = credentials(), original.session == context.session else { throw ProjectTopicImageFailure.notConfigured }
        try check(original, context: context, field: field)
        let limit = policy.kinds[0]
        guard !image.jpeg.isEmpty, UInt64(image.jpeg.count) <= min(policy.maximumTotalBytes, limit.maximumBytes),
              image.width > 0, image.height > 0, UInt64(image.width) <= limit.maximumWidth, UInt64(image.height) <= limit.maximumHeight,
              UInt64(image.width) <= limit.maximumPixels / UInt64(image.height),
              image.width * field.heightUnits == image.height * field.widthUnits else { throw ProjectTopicImageFailure.invalidImage }
        guard attempts.insert(attemptID).inserted else { throw ProjectTopicImageFailure.alreadyAttempted }
        let boundary = "ProjectTopicImage-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\n\(field.businessType)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"topic.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(image.jpeg); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(Self.path))
        request.httpMethod = "POST"; request.httpBody = body; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue(original.token, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let bytes: Data, status: Int
        do { (bytes, status) = try await transport.send(request) }
        catch { try check(original, context: context, field: field); throw ProjectTopicImageFailure.outcomeUnknown }
        try check(original, context: context, field: field)
        if status == 401 { throw APIError.unauthorized }
        guard status == 200, bytes.count <= 64 * 1024 else { throw ProjectTopicImageFailure.outcomeUnknown }
        guard let row = try? ApprovedTopicReleaseWire.envelope(bytes) else { throw ProjectTopicImageFailure.invalidResponse }
        if row["code"]?.integer == 401 { throw APIError.unauthorized }
        guard row["code"]?.integer == 200, let reference = row["url"]?.text, validReference(reference, field: field) else { throw ProjectTopicImageFailure.invalidResponse }
        return .init(attemptID: attemptID, context: context, field: field, reference: reference)
    }
}
