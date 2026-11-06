import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Local observation of the existing authenticated self-info response. Not a server receipt.
public struct MemberIdentityAvatarObservation: Equatable {
    public let accountID: Int, scope: UUID, readRevision: UUID
    public let originalURL: String
    public let requestStarted: ContinuousClock.Instant
    public init?(snapshot: MemberIdentitySnapshot, scope: UUID, readRevision: UUID,
                 requestStarted: ContinuousClock.Instant) {
        guard let id = snapshot.id, id > 0, let raw = snapshot.avatarSource,
              !raw.isEmpty, raw.utf8.count <= 8192 else { return nil }
        accountID = id; originalURL = raw; self.scope = scope; self.readRevision = readRevision
        self.requestStarted = requestStarted
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accountID == rhs.accountID && lhs.scope == rhs.scope && lhs.readRevision == rhs.readRevision
            && lhs.requestStarted == rhs.requestStarted && lhs.originalURL.utf8.elementsEqual(rhs.originalURL.utf8)
    }
}

/// Independent self identity-card purpose. Editor/media-list/QR grants are not accepted.
@MainActor @Observable public final class MemberIdentityAvatarApproval {
    public let revision = UUID(), context: RuntimeDependencyContext, viewerRevision: UInt64
    public let approvedOrigins: Set<String>, expiresAt: Date, clientDeadline: ContinuousClock.Instant
    public private(set) var revoked = false
    private final class WeakClient {
        weak var value: MemberIdentityAvatarReader?
        init(_ value: MemberIdentityAvatarReader) { self.value = value }
    }
    private var clients: [WeakClient] = []
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64,
                approvedOrigins: Set<String>, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        let now = Date(), duration = expiresAt.timeIntervalSince(now)
        guard context.market == .china, context.session.accountID > 0,
              context.role.utf8.elementsEqual(context.session.role.utf8),
              expiresAt.timeIntervalSince1970.isFinite, duration.isFinite, duration > 0,
              !approvedOrigins.isEmpty, approvedOrigins.allSatisfy(Self.validOrigin) else { throw RetainedImageFailure.disabled }
        self.context = context; self.viewerRevision = viewerRevision; self.approvedOrigins = approvedOrigins; self.expiresAt = expiresAt
        let seconds = min(duration, TimeInterval(Int64.max / 1_000_000_000))
        clientDeadline = ContinuousClock().now.advanced(by: .nanoseconds(Int64(seconds * 1_000_000_000)))
    }
    public func matches(_ value: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && ContinuousClock().now < clientDeadline
            && ContentDraftContextFence.matches(value, context)
            && value.session.role.utf8.elementsEqual(context.session.role.utf8)
    }
    static func validOrigin(_ text: String) -> Bool {
        guard let c = URLComponents(string: text), c.scheme == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil, c.path.isEmpty,
              c.port.map({ (1...65535).contains($0) }) ?? true else { return false }
        let canonical = "https://" + host.lowercased() + (c.port.map { ":\($0)" } ?? "")
        return text.utf8.elementsEqual(canonical.utf8)
    }
    func register(_ reader: MemberIdentityAvatarReader) {
        clients.removeAll { $0.value == nil }; clients.append(.init(reader))
        if revoked { reader.retire() }
    }
    public func revoke() {
        revoked = true; let values = clients; clients.removeAll(); values.forEach { $0.value?.retire() }
    }
}

@MainActor public final class MemberIdentityAvatarReader {
    private let approval: MemberIdentityAvatarApproval
    private let currentContext: () -> RuntimeDependencyContext?
    private let currentViewer: () -> UInt64?
    private let selected: () -> MemberIdentityAvatarApproval?
    private let member: any MemberHomeReading
    private let scope: UUID
    private let transport: any MemberIdentityAvatarDispatching
    private var retired = false, loaded = false
    private var authorization: MemberIdentityAvatarAuthorization?
    /// Synchronously removes already displayed pixels when the host or issuer retires this reader.
    public var onRetire: (() -> Void)?
    public init(approval: MemberIdentityAvatarApproval, currentContext: @escaping () -> RuntimeDependencyContext?,
                currentViewer: @escaping () -> UInt64?, selected: @escaping () -> MemberIdentityAvatarApproval?,
                member: any MemberHomeReading, transport: (any MemberIdentityAvatarDispatching)? = nil) {
        self.approval = approval; self.currentContext = currentContext; self.currentViewer = currentViewer
        self.selected = selected; self.member = member; scope = member.scope
        self.transport = transport ?? MemberIdentityAvatarTransport(); approval.register(self)
    }
    public var sourceRevision: UUID? { isConfigured ? approval.revision : nil }
    public var isConfigured: Bool {
        guard !retired else { return false }
        guard let context = currentContext(), approval.matches(context), selected() === approval,
              currentViewer() == approval.viewerRevision, member.scope == scope,
              member.isSignedIn, member.isConfigured else { retire(); return false }
        return true
    }
    public func retire() {
        guard !retired else { return }; retired = true
        let pending = authorization; authorization = nil; pending?.invalidate()
        let callback = onRetire; onRetire = nil; callback?()
    }
    /// A conservative local limit for potentially short-lived owner URLs. It is not a producer timestamp.
    public func deadline(for observation: MemberIdentityAvatarObservation) -> ContinuousClock.Instant {
        min(observation.requestStarted.advanced(by: .seconds(300)), approval.clientDeadline)
    }
    public func accepts(_ observation: MemberIdentityAvatarObservation) -> Bool {
        isConfigured && observation.accountID == approval.context.session.accountID && observation.scope == scope
            && observation.requestStarted <= ContinuousClock().now && ContinuousClock().now < deadline(for: observation)
    }
    public static func request(originalURL: String, origins: Set<String>) throws -> URLRequest {
        guard !originalURL.isEmpty, originalURL.utf8.count <= 8192,
              let url = URL(string: originalURL), originalURL.utf8.elementsEqual(url.absoluteString.utf8),
              RetainedImageOrigin.accepts(url, origins: origins) else { throw RetainedImageFailure.invalid }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }
    public func image(_ observation: MemberIdentityAvatarObservation,
                      currentObservation: @escaping () -> MemberIdentityAvatarObservation?) async throws -> Data {
        guard !loaded, accepts(observation), currentObservation() == observation else { throw RetainedImageFailure.disabled }
        let request = try Self.request(originalURL: observation.originalURL, origins: approval.approvedOrigins)
        let auth = MemberIdentityAvatarAuthorization(expected: request, current: { [weak self] in
            self?.accepts(observation) == true && currentObservation() == observation
        })
        loaded = true; authorization = auth
        defer { if authorization === auth { authorization = nil }; auth.invalidate() }
        try Task.checkCancellation()
        let bytes = try await transport.send(request, authorization: auth)
        try Task.checkCancellation()
        guard auth.didForward, auth.isCurrent, !bytes.isEmpty, bytes.count <= RetainedSelectedImage.maximumInputBytes else {
            throw RetainedImageFailure.stale
        }
        return bytes
    }
}
