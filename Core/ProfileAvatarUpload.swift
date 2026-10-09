import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ProfileAvatarFailure: Error, Equatable {
    case disabled, stale, invalid, notSent, rejected, unknown, storage
}
/// A separately supplied deployment/account approval. Constructing it enables nothing.
public struct ProfileAvatarApproval: Equatable {
    public let id: UUID
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int
    public let approvedOrigins: Set<String>
    public let nativePicker: Bool
    public init(baseURL: URL, namespace: String, accountID: Int, approvedOrigins: Set<String> = [], nativePicker: Bool = false, id: UUID = UUID()) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard accountID > 0, !namespace.isEmpty, namespace.utf8.count <= 4096 else { throw ProfileAvatarFailure.invalid }
        self.id = id; self.baseURL = baseURL; self.namespace = namespace; self.accountID = accountID
        self.approvedOrigins = approvedOrigins; self.nativePicker = nativePicker
    }
}
public struct ProfileAvatarCredentials: Equatable {
    public let session: ProfileEditSession
    public let namespace: String
    fileprivate let token: String
    public init(session: ProfileEditSession, namespace: String, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token), token.utf8.elementsEqual(session.token.utf8), !namespace.isEmpty else { throw ProfileAvatarFailure.invalid }
        self.session = session; self.namespace = namespace; self.token = token
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session == rhs.session && lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8) && lhs.token.utf8.elementsEqual(rhs.token.utf8)
    }
}
public struct ProfileAvatarScope: Equatable {
    public let identity: ProfileReadIdentity
    public let viewerRevision: UInt64
    public let realm: String
    public let namespace: String
    public let approvalID: UUID
    public let editorID: UUID
    public let lifetimeID: UUID
}
public enum ProfileAvatarExact {
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func strings(_ values: [String]) -> Data {
        var bytes = Data()
        for value in values { let part = Data(value.utf8); bytes.append(Data("\(part.count):".utf8)); bytes.append(part) }
        return bytes
    }
    public static func snapshot(_ value: ProfileEditSnapshot) -> String {
        hash(strings([String(value.id), value.nickname, value.introduction, value.avatar, value.wechat, value.casePics, value.tagIds]))
    }
    public static func draft(_ value: ProfileEditDraft) -> String {
        hash(strings([value.name, value.introduction, value.routePreferenceIDs.map { "selected:" + $0.map(String.init).joined(separator: ",") } ?? "preserve",
                      value.avatarReplacement?.id.uuidString ?? "no-avatar-change"]))
    }
}
public struct ProfileAvatarTarget: Equatable {
    public let id: UUID
    public let scope: ProfileAvatarScope
    public let snapshotHash: String
    public let draftHash: String
    public let draftRevision: UInt64
    public init(scope: ProfileAvatarScope, snapshot: ProfileEditSnapshot, draft: ProfileEditDraft, draftRevision: UInt64) throws {
        guard snapshot.id == scope.identity.accountID, draft.avatarReplacement == nil else { throw ProfileAvatarFailure.stale }
        id = UUID(); self.scope = scope; snapshotHash = ProfileAvatarExact.snapshot(snapshot)
        draftHash = ProfileAvatarExact.draft(draft); self.draftRevision = draftRevision
    }
    public func matches(snapshot: ProfileEditSnapshot, draft: ProfileEditDraft, revision: UInt64) -> Bool {
        snapshot.id == scope.identity.accountID && snapshotHash == ProfileAvatarExact.snapshot(snapshot) &&
            draftHash == ProfileAvatarExact.draft(draft) && draftRevision == revision
    }
}
/// Final forwarding capability. A conforming transport invokes forward at its actual
/// synchronous request-start boundary, after any suspensions. No generic HTTP fallback.
@MainActor public final class ProfileAvatarDispatchAuthorization {
    private let request: URLRequest
    private let validity: () -> Bool
    public private(set) var didForward = false
    init(request: URLRequest, validity: @escaping () -> Bool) { self.request = request; self.validity = validity }
    public func forward(_ request: URLRequest, start: () throws -> Void) throws {
        guard !didForward, self.request == request, !Task.isCancelled, validity() else { throw ProfileAvatarFailure.notSent }
        didForward = true
        try start() // No await between final validation and the adapter's request start.
    }
    func isCurrent() -> Bool { !Task.isCancelled && validity() }
}
@MainActor public protocol ProfileAvatarDispatching: AnyObject {
    var isConfigured: Bool { get }
    func send(_ request: URLRequest, authorization: ProfileAvatarDispatchAuthorization) async throws -> (Data, Int)
}
/// Only the scoped upload client mints this reference. It proves one acknowledged
/// upload, never server acceptance of the profile or immutable ownership/version.
public struct ProfileAvatarUploadReceipt: Equatable {
    public let id: UUID
    public let target: ProfileAvatarTarget
    public let selectedDigest: String
    public let reference: String
    fileprivate init(id: UUID, target: ProfileAvatarTarget, selectedDigest: String, reference: String) {
        self.id = id; self.target = target; self.selectedDigest = selectedDigest; self.reference = reference
    }
}
/// A typed, explicitly staged replacement; callers cannot construct one from a URL.
public struct ProfileAvatarReplacement: Equatable {
    public let receipt: ProfileAvatarUploadReceipt
    public var id: UUID { receipt.id }
    public var reference: String { receipt.reference }
    private let current: @MainActor () -> Bool
    fileprivate init(receipt: ProfileAvatarUploadReceipt, current: @escaping @MainActor () -> Bool) { self.receipt = receipt; self.current = current }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.receipt == rhs.receipt }
    @MainActor public func permits(session: ProfileEditSession, snapshot: ProfileEditSnapshot) -> Bool {
        current() && receipt.target.scope.identity == session.identity && receipt.target.scope.viewerRevision == session.viewerRevision &&
            receipt.target.snapshotHash == ProfileAvatarExact.snapshot(snapshot)
    }
}
extension ProfileAvatarUploadReceipt {
    @MainActor func stage(current: @escaping @MainActor () -> Bool) -> ProfileAvatarReplacement { .init(receipt: self, current: current) }
}
/// Exact Mini avatar route: multipart file plus bizType=image_1_1. Missing approval,
/// credentials or checked transport is disabled. This type creates no URLSession.
@MainActor public final class ProfileAvatarUploadClient {
    public static let path = "api/common/uploadOSS"
    private let configuration: APIConfiguration
    private let approval: ProfileAvatarApproval?
    private let transport: (any ProfileAvatarDispatching)?
    private let credentials: () -> ProfileAvatarCredentials?
    private let currentApproval: () -> ProfileAvatarApproval?
    public init(configuration: APIConfiguration, approval: ProfileAvatarApproval? = nil,
                transport: (any ProfileAvatarDispatching)? = nil,
                credentials: @escaping () -> ProfileAvatarCredentials? = { nil },
                currentApproval: @escaping () -> ProfileAvatarApproval? = { nil }) {
        self.configuration = configuration; self.approval = approval; self.transport = transport
        self.credentials = credentials; self.currentApproval = currentApproval
    }
    public func scope(session: ProfileEditSession, editorID: UUID, lifetimeID: UUID) -> ProfileAvatarScope? {
        guard let approval, currentApproval() == approval, transport?.isConfigured == true,
              approval.baseURL == configuration.baseURL, approval.accountID == session.identity.accountID,
              !approval.approvedOrigins.isEmpty, let current = credentials(), current.session == session,
              current.namespace.utf8.elementsEqual(approval.namespace.utf8) else { return nil }
        return .init(identity: session.identity, viewerRevision: session.viewerRevision, realm: configuration.baseURL.absoluteString,
                     namespace: approval.namespace, approvalID: approval.id, editorID: editorID, lifetimeID: lifetimeID)
    }
    public func isCurrent(_ scope: ProfileAvatarScope) -> Bool {
        guard let current = credentials() else { return false }
        return self.scope(session: current.session, editorID: scope.editorID, lifetimeID: scope.lifetimeID) == scope
    }
    public func permitsPicker(_ scope: ProfileAvatarScope) -> Bool { isCurrent(scope) && approval?.nativePicker == true }
    public func permitsReference(_ value: String, scope: ProfileAvatarScope) -> Bool {
        guard isCurrent(scope), !value.isEmpty, value.utf8.count <= 8192,
              value.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }), let url = URL(string: value) else { return false }
        return RetainedImageOrigin.accepts(url, origins: approval?.approvedOrigins ?? [])
    }
    public func upload(_ image: RetainedSelectedImage, target: ProfileAvatarTarget, attemptID: UUID,
                       ownerCurrent: @escaping () -> Bool) async throws -> ProfileAvatarUploadReceipt {
        guard image.width == image.height, isCurrent(target.scope), let transport, let original = credentials(),
              ownerCurrent(), !Task.isCancelled else { throw ProfileAvatarFailure.notSent }
        let boundary = "ProfileAvatar-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\nimage_1_1\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(image.jpeg); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(Self.path))
        request.httpMethod = "POST"; request.httpBody = body; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue(original.token, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let authorization = ProfileAvatarDispatchAuthorization(request: request) { [weak self] in
            guard let self else { return false }
            return self.credentials() == original && self.isCurrent(target.scope) && ownerCurrent()
        }
        let result: (Data, Int)
        do { result = try await transport.send(request, authorization: authorization) }
        catch { throw authorization.didForward ? ProfileAvatarFailure.unknown : ProfileAvatarFailure.notSent }
        guard authorization.didForward, authorization.isCurrent(), result.0.count <= 64 * 1024 else {
            throw authorization.didForward ? ProfileAvatarFailure.unknown : ProfileAvatarFailure.notSent
        }
        // Only explicit 4xx rejection is safe to release; malformed/5xx responses are unknown.
        let row = try? ApprovedTopicReleaseWire.envelope(result.0)
        if (400..<500).contains(result.1), row?["code"]?.integer != 200 { throw ProfileAvatarFailure.rejected }
        guard result.1 == 200, row?["code"]?.integer == 200, let reference = row?["url"]?.text,
              permitsReference(reference, scope: target.scope) else { throw ProfileAvatarFailure.unknown }
        return .init(id: attemptID, target: target, selectedDigest: ProfileAvatarExact.hash(image.jpeg), reference: reference)
    }
}
