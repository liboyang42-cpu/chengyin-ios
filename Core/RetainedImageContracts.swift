import Foundation

public enum RetainedImageFailure: Error, Equatable {
    case disabled, invalid, stale, reviewRequired, unknown
    case rejected(Int, String?)
}
/// No IM identity crosses this boundary. Field + account + epoch + entity bind each image.
public struct RetainedImageScope: Equatable {
    public enum Destination: Equatable {
        case publicReview(merchantRowID: Int, registrationID: Int)
        case merchant(merchantRowID: Int, field: MerchantImageField)
    }
    public let accountID: Int
    public let epoch: UUID
    public let realm: String
    public let namespace: String?
    public let resourceID: Int?
    public let accessRevision: UUID?
    public let destination: Destination
    public init(accountID: Int, epoch: UUID, realm: String, destination: Destination, accessRevision: UUID? = nil, resourceID: Int? = nil, namespace: String? = nil) throws {
        guard accountID > 0, let base = URL(string: realm), base.scheme == "https", base.host != nil,
              base.user == nil, base.password == nil else { throw RetainedImageFailure.invalid }
        switch destination {
        case .publicReview(let merchant, let registration): guard merchant > 0, registration > 0 else { throw RetainedImageFailure.invalid }
        case .merchant(let merchant, _): guard merchant > 0 else { throw RetainedImageFailure.invalid }
        }
        self.accountID = accountID; self.epoch = epoch; self.realm = realm; self.destination = destination; self.accessRevision = accessRevision; self.resourceID = resourceID; self.namespace = namespace
    }
}
public enum MerchantImageField: String, Equatable { case logo, coverImage, gallery, avatar, imgUrl }
/// Constructed only by the native decode/redraw adapter (or @testable tests).
public struct RetainedSelectedImage: Equatable {
    public static let maximumInputBytes = 20 * 1024 * 1024
    public static let maximumBytes = 8 * 1024 * 1024
    public static let maximumDimension = 4096
    public let id: UUID
    public let jpeg: Data
    public let width: Int
    public let height: Int
    init(jpeg: Data, width: Int, height: Int, id: UUID = UUID()) throws {
        guard !jpeg.isEmpty, jpeg.count <= Self.maximumBytes, jpeg.starts(with: [255, 216, 255]),
              (1...Self.maximumDimension).contains(width), (1...Self.maximumDimension).contains(height) else { throw RetainedImageFailure.invalid }
        self.id = id; self.jpeg = jpeg; self.width = width; self.height = height
    }
}
public struct RetainedImageUploadReview: Equatable, Identifiable {
    public let id: UUID
    public let scope: RetainedImageScope
    public let selection: RetainedSelectedImage
    public init(scope: RetainedImageScope, selection: RetainedSelectedImage) { id = UUID(); self.scope = scope; self.selection = selection }
}
/// Only the scoped HTTP uploader can mint this proof. A bare URL is never upload evidence.
public struct RetainedUploadedImage: Equatable, Identifiable {
    public let id: UUID
    public let scope: RetainedImageScope
    public let url: URL
    fileprivate init(review: RetainedImageUploadReview, url: URL) { id = review.selection.id; scope = review.scope; self.url = url }
}
public enum RetainedImageOrigin {
    public static func accepts(_ url: URL, origins: Set<String>) -> Bool {
        guard url.scheme == "https", let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil, !url.path.isEmpty, url.path != "/" else { return false }
        let origin = "https://" + host.lowercased() + (url.port.map { ":\($0)" } ?? "")
        return origins.contains(origin)
    }
}
@MainActor public protocol RetainedImageUploading {
    var isConfigured: Bool { get }
    var scope: RetainedImageScope? { get }
    func upload(_ review: RetainedImageUploadReview) async throws -> RetainedUploadedImage
}
@MainActor public struct DisabledRetainedImageUploader: RetainedImageUploading {
    public let isConfigured = false
    public let scope: RetainedImageScope? = nil
    public init() {}
    public func upload(_ review: RetainedImageUploadReview) async throws -> RetainedUploadedImage { throw RetainedImageFailure.disabled }
}
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
/// Legacy uploadOSS: multipart `file`; top-level code/msg/url. No invented media ID/receipt.
@MainActor public struct RetainedImageHTTPUploader: RetainedImageUploading {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let currentScope: () -> RetainedImageScope?
    private let token: () -> String?
    private let enabled: Bool
    private let approvedOrigins: Set<String>
    public var scope: RetainedImageScope? { currentScope() }
    public var isConfigured: Bool { enabled && !approvedOrigins.isEmpty }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Bool = false,
                approvedOrigins: Set<String> = [], currentScope: @escaping () -> RetainedImageScope?, token: @escaping () -> String?) {
        self.configuration = configuration; self.transport = transport; self.enabled = enabled
        self.approvedOrigins = approvedOrigins; self.currentScope = currentScope; self.token = token
    }
    public func upload(_ review: RetainedImageUploadReview) async throws -> RetainedUploadedImage {
        guard isConfigured else { throw RetainedImageFailure.disabled }
        guard currentScope() == review.scope, review.scope.realm == configuration.baseURL.absoluteString,
              let auth = token(), AuthRequestBuilder.isValidToken(auth) else { throw RetainedImageFailure.stale }
        let boundary = "retained-image-" + UUID().uuidString
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/common/uploadOSS"))
        request.httpMethod = "POST"; request.timeoutInterval = 30; request.httpShouldHandleCookies = false
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(review.selection.jpeg); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); request.httpBody = body
        try Task.checkCancellation()
        do {
            let (data, status) = try await transport.send(request)
            guard currentScope() == review.scope, token() == auth, !Task.isCancelled, data.count <= 1024 * 1024 else { throw RetainedImageFailure.unknown }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            if (200..<500).contains(status), envelope.code != 200 { throw RetainedImageFailure.rejected(envelope.code, envelope.msg) }
            guard (200..<300).contains(status), envelope.code == 200, let raw = envelope.url,
                  let url = URL(string: raw), RetainedImageOrigin.accepts(url, origins: approvedOrigins) else { throw RetainedImageFailure.unknown }
            return RetainedUploadedImage(review: review, url: url)
        } catch let error as RetainedImageFailure { throw error }
        catch { throw RetainedImageFailure.unknown }
    }
    private struct Envelope: Decodable { let code: Int; let msg: String?; let url: String? }
}
@MainActor public final class RetainedImageUploadCoordinator {
    public enum State: Equatable { case idle, reviewing(RetainedImageUploadReview), uploading, uploaded(RetainedUploadedImage), unknown, failed(RetainedImageFailure) }
    public private(set) var state: State = .idle
    public let uploader: any RetainedImageUploading
    private var generation = 0
    private var acknowledgedAttempt: UUID?
    public var changed: (() -> Void)?
    private let journal: any ImageUploadJournal
    public init(uploader: any RetainedImageUploading, journal: (any ImageUploadJournal)? = nil) {
        self.uploader = uploader; self.journal = journal ?? UnavailableImageUploadJournal()
        if let scope = uploader.scope {
            do { if let entry = try self.journal.entry(for: ImageUploadTarget(scope: scope)), !entry.phase.permitsNewSelection { state = .unknown } }
            catch { state = .unknown }
        }
    }
    public var locked: Bool { switch state { case .uploading, .unknown: return true; default: return false } }
    public func prepare(_ image: RetainedSelectedImage, scope: RetainedImageScope) {
        guard !locked, uploader.isConfigured, uploader.scope == scope else { return }
        do { if let value = try self.journal.entry(for: ImageUploadTarget(scope: scope)), !value.phase.permitsNewSelection { state = .unknown; changed?(); return } }
        catch { state = .unknown; changed?(); return }
        state = .reviewing(.init(scope: scope, selection: image)); changed?()
    }
    public func confirm(_ review: RetainedImageUploadReview) async {
        guard state == .reviewing(review), uploader.scope == review.scope else { return }
        let target: ImageUploadTarget
        do {
            try Task.checkCancellation()
            target = try ImageUploadTarget(scope: review.scope)
            try journal.begin(target: target, attemptID: review.id)
        } catch { state = .unknown; changed?(); return }
        let stamp = generation; state = .uploading; changed?()
        do {
            let image = try await uploader.upload(review)
            guard stamp == generation, uploader.scope == review.scope, image.scope == review.scope, !Task.isCancelled else { state = .unknown; changed?(); return }
            // Acknowledgement proves upload only, never application to the local draft.
            // Keep metadata locked on relaunch: URL/proof is intentionally memory-only.
            try journal.record(target: target, attemptID: review.id, phase: .acknowledged)
            acknowledgedAttempt = review.id
            state = .uploaded(image)
        } catch let error as RetainedImageFailure {
            guard stamp == generation else { return }
            if case .rejected = error {
                do { try journal.record(target: target, attemptID: review.id, phase: .rejected); state = .failed(error) }
                catch { state = .unknown }
            } else { state = .unknown }
        } catch { if stamp == generation { state = .unknown } }
        changed?()
    }
    /// Runs one synchronous, proof-checked local consumer. This is NOT server publication.
    /// A process death between local edit and this durable transition remains fail-closed.
    @discardableResult public func applyLocally(_ image: RetainedUploadedImage, consume: (RetainedUploadedImage) -> Bool) -> Bool {
        guard case .uploaded(let current) = state, current == image, uploader.scope == image.scope,
              let attempt = acknowledgedAttempt else { return false }
        guard consume(image) else { return false }
        do {
            try journal.record(target: ImageUploadTarget(scope: image.scope), attemptID: attempt, phase: .locallyApplied)
            acknowledgedAttempt = nil; state = .idle; changed?(); return true
        } catch { state = .unknown; changed?(); return false }
    }
    /// Unknown writes stay locked. No retry or fabricated reconciliation endpoint.
    public func clear() { generation += 1; state = locked ? .unknown : .idle; changed?() }
}
