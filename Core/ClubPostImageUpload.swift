import Combine
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact identity and target context for a Club Community post image selection/upload draft.
public struct ClubPostImageUploadContext: Equatable, Sendable {
    public let accountID: Int
    public let epoch: UInt64
    public let namespace: String
    public let clubID: Int
    public let postID: Int?

    public init(
        accountID: Int,
        epoch: UInt64,
        namespace: String,
        clubID: Int,
        postID: Int? = nil
    ) throws {
        let trimmedNamespace = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard accountID > 0,
              clubID > 0,
              !trimmedNamespace.isEmpty,
              postID == nil || (postID ?? 0) > 0 else {
            throw ClubPostImageUploadFailure.notConfigured
        }
        self.accountID = accountID
        self.epoch = epoch
        self.namespace = trimmedNamespace
        self.clubID = clubID
        self.postID = postID
    }
}

/// Club-post-specific image upload contract.
/// Never reuses profile, merchant, review, or project upload approvals. Default issuance is nil.
public struct ClubPostImageUploadApproval: Equatable, Sendable {
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int
    public let clubID: Int
    public let approvedOrigins: Set<String>
    public let nativePicker: Bool
    public let maximumImages: Int
    public let maximumBytesPerImage: Int

    public init(
        baseURL: URL,
        namespace: String,
        accountID: Int,
        clubID: Int,
        approvedOrigins: Set<String>,
        nativePicker: Bool = false,
        maximumImages: Int = 9,
        maximumBytesPerImage: Int = RetainedSelectedImage.maximumBytes
    ) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        let trimmedNamespace = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard accountID > 0,
              clubID > 0,
              !trimmedNamespace.isEmpty,
              !approvedOrigins.isEmpty,
              (1...9).contains(maximumImages),
              (1...RetainedSelectedImage.maximumBytes).contains(maximumBytesPerImage),
              approvedOrigins.allSatisfy({ origin in
                  guard let url = URL(string: origin),
                        url.scheme == "https",
                        let host = url.host?.lowercased(),
                        host != "fixture.invalid",
                        !host.hasSuffix(".invalid"),
                        url.path.isEmpty || url.path == "/" else {
                      return false
                  }
                  return RetainedImageOrigin.accepts(url.appendingPathComponent("probe.jpg"), origins: [origin])
              }) else {
            throw APIError.invalidConfiguration
        }
        self.baseURL = baseURL
        self.namespace = trimmedNamespace
        self.accountID = accountID
        self.clubID = clubID
        self.approvedOrigins = approvedOrigins
        self.nativePicker = nativePicker
        self.maximumImages = maximumImages
        self.maximumBytesPerImage = maximumBytesPerImage
    }

    public func matches(baseURL: URL, context: ClubPostImageUploadContext) -> Bool {
        self.baseURL == baseURL
            && namespace.utf8.elementsEqual(context.namespace.utf8)
            && accountID == context.accountID
            && clubID == context.clubID
    }
}

public enum ClubPostImageUploadFailure: Error, Equatable, Sendable {
    case notConfigured
    case changedContext
    case invalidImage
    case limitReached
    case invalidResponse
    case outcomeUnknown
    case alreadyAttempted
}

/// Validates remote image references returned for Club Community post attachments.
/// Rejects `;` and `,` delimiters (used by `ClubCommunityReview` wire framing), non-HTTPS URLs,
/// `fixture.invalid` synthetic URLs, and any origin outside `approvedOrigins`.
public enum ClubPostImageReferenceValidator {
    public static func isValidReference(_ reference: String, approvedOrigins: Set<String>) -> Bool {
        guard !reference.isEmpty,
              reference.utf16.count <= 2000,
              reference.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }),
              !reference.contains(";"),
              !reference.contains(","),
              let url = URL(string: reference),
              url.scheme == "https",
              let host = url.host?.lowercased(),
              host != "fixture.invalid",
              !host.hasSuffix(".invalid") else {
            return false
        }
        return RetainedImageOrigin.accepts(url, origins: approvedOrigins)
    }
}

public struct ClubPostUploadedImage: Equatable, Identifiable {
    public var id: UUID { attemptID }
    public let attemptID: UUID
    public let context: ClubPostImageUploadContext
    public let reference: String
    public let image: RetainedSelectedImage

    public init(
        attemptID: UUID,
        context: ClubPostImageUploadContext,
        reference: String,
        image: RetainedSelectedImage
    ) {
        self.attemptID = attemptID
        self.context = context
        self.reference = reference
        self.image = image
    }
}

@MainActor
public protocol ClubPostImageUploading: AnyObject {
    func isConfigured(for context: ClubPostImageUploadContext) -> Bool
    func permitsPicker(for context: ClubPostImageUploadContext) -> Bool
    func permittedReference(_ uploaded: ClubPostUploadedImage, for context: ClubPostImageUploadContext) -> String?
    func upload(
        _ image: RetainedSelectedImage,
        attemptID: UUID,
        context: ClubPostImageUploadContext
    ) async throws -> ClubPostUploadedImage
}

@MainActor
public final class ClubPostImageDisabledUploader: ClubPostImageUploading {
    public init() {}
    public func isConfigured(for context: ClubPostImageUploadContext) -> Bool { false }
    public func permitsPicker(for context: ClubPostImageUploadContext) -> Bool { false }
    public func permittedReference(_ uploaded: ClubPostUploadedImage, for context: ClubPostImageUploadContext) -> String? { nil }
    public func upload(
        _ image: RetainedSelectedImage,
        attemptID: UUID,
        context: ClubPostImageUploadContext
    ) async throws -> ClubPostUploadedImage {
        throw ClubPostImageUploadFailure.notConfigured
    }
}

/// Real HTTP multipart upload client for Club Community post images.
/// Requires an explicit `ClubPostImageUploadApproval` matching the active account, epoch, namespace, and club.
@MainActor
public final class ClubPostImageUploadClient: ClubPostImageUploading {
    nonisolated public static let path = "api/common/uploadOSS"
    nonisolated public static let businessType = "club_post_image"

    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let currentContext: () -> ClubPostImageUploadContext?
    private let currentToken: () -> String?
    private let currentApproval: () -> ClubPostImageUploadApproval?
    private var attempts: Set<UUID> = []

    public init(
        configuration: APIConfiguration,
        transport: any HTTPTransport = ResponseLimitedHTTPTransport(maximumResponseBytes: 64 * 1024),
        currentContext: @escaping () -> ClubPostImageUploadContext?,
        currentToken: @escaping () -> String?,
        currentApproval: @escaping () -> ClubPostImageUploadApproval?
    ) {
        self.configuration = configuration
        self.transport = transport
        self.currentContext = currentContext
        self.currentToken = currentToken
        self.currentApproval = currentApproval
    }

    public func isConfigured(for context: ClubPostImageUploadContext) -> Bool {
        guard let liveContext = currentContext(),
              liveContext == context,
              let token = currentToken(),
              AuthRequestBuilder.isValidToken(token),
              let approval = currentApproval() else {
            return false
        }
        return approval.matches(baseURL: configuration.baseURL, context: context)
    }

    public func permitsPicker(for context: ClubPostImageUploadContext) -> Bool {
        guard isConfigured(for: context), let approval = currentApproval() else { return false }
        return approval.nativePicker
    }

    public func permittedReference(_ uploaded: ClubPostUploadedImage, for context: ClubPostImageUploadContext) -> String? {
        guard uploaded.context == context,
              isConfigured(for: context),
              let approval = currentApproval(),
              ClubPostImageReferenceValidator.isValidReference(
                  uploaded.reference,
                  approvedOrigins: approval.approvedOrigins
              ) else {
            return nil
        }
        return uploaded.reference
    }

    public func upload(
        _ image: RetainedSelectedImage,
        attemptID: UUID,
        context: ClubPostImageUploadContext
    ) async throws -> ClubPostUploadedImage {
        try Task.checkCancellation()
        guard isConfigured(for: context),
              let capturedApproval = currentApproval(),
              let capturedToken = currentToken(),
              AuthRequestBuilder.isValidToken(capturedToken) else {
            throw ClubPostImageUploadFailure.notConfigured
        }
        guard !image.jpeg.isEmpty,
              image.jpeg.starts(with: [255, 216, 255]),
              image.jpeg.count <= capturedApproval.maximumBytesPerImage,
              (1...RetainedSelectedImage.maximumDimension).contains(image.width),
              (1...RetainedSelectedImage.maximumDimension).contains(image.height) else {
            throw ClubPostImageUploadFailure.invalidImage
        }
        guard attempts.insert(attemptID).inserted else {
            throw ClubPostImageUploadFailure.alreadyAttempted
        }

        let boundary = "ClubPostImage-" + UUID().uuidString
        var body = Data(
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\n\(Self.businessType)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"club-post.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8
        )
        body.append(image.jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(Self.path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue(capturedToken, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let data: Data
        let status: Int
        do {
            (data, status) = try await transport.send(request)
        } catch {
            try Task.checkCancellation()
            guard isConfigured(for: context),
                  currentApproval() == capturedApproval,
                  currentToken() == capturedToken else {
                throw ClubPostImageUploadFailure.changedContext
            }
            throw ClubPostImageUploadFailure.outcomeUnknown
        }

        try Task.checkCancellation()
        guard isConfigured(for: context),
              currentApproval() == capturedApproval,
              currentToken() == capturedToken else {
            throw ClubPostImageUploadFailure.changedContext
        }
        guard status == 200, data.count <= 64 * 1024 else {
            throw ClubPostImageUploadFailure.outcomeUnknown
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? Int else {
            throw ClubPostImageUploadFailure.invalidResponse
        }
        let rawReference = (object["url"] as? String)
            ?? ((object["data"] as? [String: Any])?["url"] as? String)
            ?? (object["data"] as? String)
        guard code == 200,
              let reference = rawReference?.trimmingCharacters(in: .whitespacesAndNewlines),
              ClubPostImageReferenceValidator.isValidReference(
                  reference,
                  approvedOrigins: capturedApproval.approvedOrigins
              ) else {
            throw ClubPostImageUploadFailure.invalidResponse
        }
        return ClubPostUploadedImage(
            attemptID: attemptID,
            context: context,
            reference: reference,
            image: image
        )
    }
}

/// Manages selected local images and uploaded image references for a Club Community post composer.
/// Preserves existing text draft state on picker return, never auto-submits a post, and invalidates
/// immediately if account, epoch, or club context changes.
@MainActor
public final class ClubPostImageDraftController: ObservableObject {
    public static let maximumImages = 9

    private let uploader: any ClubPostImageUploading
    private let currentContext: () -> ClubPostImageUploadContext?
    private var boundContext: ClubPostImageUploadContext?
    private var generation: UInt64 = 0

    @Published public private(set) var localCandidates: [RetainedSelectedImage] = []
    @Published public private(set) var uploadedReferences: [String] = []
    @Published public private(set) var previewsByReference: [String: RetainedSelectedImage] = [:]
    @Published public private(set) var isUploading: Bool = false
    @Published public private(set) var statusKey: String?
    /// Selecting or uploading an image never triggers post creation/update submission.
    public let didAutoSubmit: Bool = false

    public init(
        uploader: (any ClubPostImageUploading)? = nil,
        currentContext: @escaping () -> ClubPostImageUploadContext?
    ) {
        self.uploader = uploader ?? ClubPostImageDisabledUploader()
        self.currentContext = currentContext
    }

    public var totalImageCount: Int {
        uploadedReferences.count + localCandidates.count
    }

    public var canAddMoreImages: Bool {
        totalImageCount < Self.maximumImages && !isUploading
    }

    public func bind(context: ClubPostImageUploadContext?, initialReferences: [String] = []) {
        if boundContext != context {
            invalidate()
            boundContext = context
        }
        if uploadedReferences.isEmpty && !initialReferences.isEmpty {
            uploadedReferences = Array(
                initialReferences
                    .filter { !$0.isEmpty && !$0.contains(";") && !$0.contains(",") }
                    .prefix(Self.maximumImages)
            )
        }
    }

    public func invalidate() {
        generation &+= 1
        boundContext = nil
        localCandidates = []
        uploadedReferences = []
        previewsByReference = [:]
        isUploading = false
        statusKey = nil
    }

    public func validateCurrentContext() -> ClubPostImageUploadContext? {
        guard let live = currentContext() else {
            invalidate()
            return nil
        }
        if let boundContext, boundContext != live {
            invalidate()
            return nil
        }
        if boundContext == nil {
            boundContext = live
        }
        return live
    }

    /// Stages a user-selected image from the native picker.
    /// - When the upload contract is not configured, retains the selected image as a local draft candidate
    ///   and surfaces an explicit status key without making any network request.
    /// - When the upload contract is configured, uploads and verifies the returned reference before
    ///   appending it to `uploadedReferences`.
    /// - Never modifies composer text or auto-submits the post.
    @discardableResult
    public func stageSelectedImage(_ image: RetainedSelectedImage) async -> Bool {
        guard let context = validateCurrentContext() else {
            statusKey = "club.community.actionUnavailable"
            return false
        }
        guard totalImageCount < Self.maximumImages else {
            statusKey = "club.community.imageLimitReached"
            return false
        }
        guard !image.jpeg.isEmpty,
              image.jpeg.starts(with: [255, 216, 255]),
              image.jpeg.count <= RetainedSelectedImage.maximumBytes,
              (1...RetainedSelectedImage.maximumDimension).contains(image.width),
              (1...RetainedSelectedImage.maximumDimension).contains(image.height) else {
            statusKey = "club.community.invalidImage"
            return false
        }

        // If upload contract is not configured, retain locally as a draft candidate without network I/O.
        guard uploader.isConfigured(for: context) else {
            localCandidates.append(image)
            statusKey = "club.community.imageUploadUnconfiguredLocalDraft"
            return true
        }

        generation &+= 1
        let ticket = generation
        isUploading = true
        statusKey = nil

        do {
            let uploaded = try await uploader.upload(image, attemptID: UUID(), context: context)
            guard !Task.isCancelled,
                  ticket == generation,
                  let live = validateCurrentContext(),
                  live == context,
                  let verified = uploader.permittedReference(uploaded, for: live) else {
                if currentContext() != context {
                    invalidate()
                } else {
                    isUploading = false
                    statusKey = "club.community.actionUnavailable"
                }
                return false
            }
            isUploading = false
            guard uploadedReferences.count < Self.maximumImages else {
                statusKey = "club.community.imageLimitReached"
                return false
            }
            uploadedReferences.append(verified)
            previewsByReference[verified] = image
            statusKey = nil
            return true
        } catch {
            guard ticket == generation else { return false }
            if currentContext() != context {
                invalidate()
                return false
            }
            isUploading = false
            statusKey = "club.community.actionUnavailable"
            return false
        }
    }

    public func removeUploadedReference(at index: Int) {
        guard uploadedReferences.indices.contains(index) else { return }
        let removed = uploadedReferences.remove(at: index)
        if !uploadedReferences.contains(removed) {
            previewsByReference.removeValue(forKey: removed)
        }
    }

    public func removeLocalCandidate(id: UUID) {
        localCandidates.removeAll { $0.id == id }
    }

    /// Cancels any in-flight upload without discarding existing uploaded references or local candidates.
    public func cancelCurrentUpload() {
        generation &+= 1
        isUploading = false
        statusKey = "club.community.imageUploadCancelled"
    }

    /// Replaces a staged local candidate in place without altering other candidates or composer text.
    @discardableResult
    public func replaceLocalCandidate(id: UUID, with image: RetainedSelectedImage) -> Bool {
        guard validateCurrentContext() != nil,
              let index = localCandidates.firstIndex(where: { $0.id == id }) else {
            statusKey = "club.community.actionUnavailable"
            return false
        }
        guard !image.jpeg.isEmpty,
              image.jpeg.starts(with: [255, 216, 255]),
              image.jpeg.count <= RetainedSelectedImage.maximumBytes,
              (1...RetainedSelectedImage.maximumDimension).contains(image.width),
              (1...RetainedSelectedImage.maximumDimension).contains(image.height) else {
            statusKey = "club.community.invalidImage"
            return false
        }
        localCandidates[index] = image
        statusKey = "club.community.imageUploadUnconfiguredLocalDraft"
        return true
    }

    /// Replaces an uploaded reference at `index` only after the replacement upload succeeds and passes
    /// origin/reference validation under the unchanged context. If cancelled or failed, the previous
    /// reference at `index` remains intact.
    @discardableResult
    public func replaceUploadedReference(at index: Int, with image: RetainedSelectedImage) async -> Bool {
        guard let context = validateCurrentContext(),
              uploadedReferences.indices.contains(index),
              uploader.isConfigured(for: context) else {
            statusKey = "club.community.actionUnavailable"
            return false
        }
        guard !image.jpeg.isEmpty,
              image.jpeg.starts(with: [255, 216, 255]),
              image.jpeg.count <= RetainedSelectedImage.maximumBytes,
              (1...RetainedSelectedImage.maximumDimension).contains(image.width),
              (1...RetainedSelectedImage.maximumDimension).contains(image.height) else {
            statusKey = "club.community.invalidImage"
            return false
        }

        generation &+= 1
        let ticket = generation
        isUploading = true
        statusKey = nil

        do {
            let uploaded = try await uploader.upload(image, attemptID: UUID(), context: context)
            guard !Task.isCancelled,
                  ticket == generation,
                  let live = validateCurrentContext(),
                  live == context,
                  uploadedReferences.indices.contains(index),
                  let verified = uploader.permittedReference(uploaded, for: live) else {
                if currentContext() != context {
                    invalidate()
                } else if ticket == generation {
                    isUploading = false
                    statusKey = "club.community.actionUnavailable"
                }
                return false
            }
            isUploading = false
            let previous = uploadedReferences[index]
            uploadedReferences[index] = verified
            if !uploadedReferences.contains(previous) {
                previewsByReference.removeValue(forKey: previous)
            }
            previewsByReference[verified] = image
            statusKey = nil
            return true
        } catch {
            guard ticket == generation else { return false }
            if currentContext() != context {
                invalidate()
                return false
            }
            isUploading = false
            statusKey = "club.community.actionUnavailable"
            return false
        }
    }
}

/// Exact composition-root route recognizer for `ClubPostImageUploadClient` (`POST api/common/uploadOSS`
/// with `ClubPostImage-` multipart boundary and `bizType=club_post_image`).
public struct ClubPostImageUploadCompositionRoute: Equatable, Sendable {
    public init?(request: URLRequest, baseURL: URL) {
        guard Self.matches(request, baseURL: baseURL) else {
            return nil
        }
    }

    public static func matches(_ request: URLRequest, baseURL: URL) -> Bool {
        guard request.httpMethod?.uppercased() == "POST",
              let url = request.url,
              url == baseURL.appendingPathComponent(ClubPostImageUploadClient.path),
              let contentType = request.value(forHTTPHeaderField: "Content-Type"),
              contentType.hasPrefix("multipart/form-data; boundary=ClubPostImage-"),
              let body = request.httpBody else {
            return false
        }
        let marker = Data("Content-Disposition: form-data; name=\"bizType\"\r\n\r\n\(ClubPostImageUploadClient.businessType)\r\n".utf8)
        return body.range(of: marker) != nil
    }
}
