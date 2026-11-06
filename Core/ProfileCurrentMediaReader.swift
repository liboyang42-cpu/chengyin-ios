import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Distinct purposes; contact QR does not inherit reviewed avatar/work authority.
public enum ProfileCurrentMediaKind: String, Hashable, CaseIterable { case avatar, caseImage, contactQR }

@MainActor @Observable public final class ProfileSavedMediaReadApproval {
    public let revision = UUID(), context: RuntimeDependencyContext, viewerRevision: UInt64
    public let kind: ProfileCurrentMediaKind, approvedOrigins: Set<String>, expiresAt: Date
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64, kind: ProfileCurrentMediaKind,
                approvedOrigins: Set<String>, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.role.utf8.elementsEqual(context.session.role.utf8),
              !approvedOrigins.isEmpty, approvedOrigins.allSatisfy(Self.validOrigin),
              expiresAt.timeIntervalSince1970.isFinite, expiresAt > Date() else { throw RetainedImageFailure.disabled }
        self.context = context; self.viewerRevision = viewerRevision; self.kind = kind
        self.approvedOrigins = approvedOrigins; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && ContentDraftContextFence.matches(current, context)
            && current.session.role.utf8.elementsEqual(context.session.role.utf8)
    }
    static func validOrigin(_ origin: String) -> Bool {
        guard let c = URLComponents(string: origin), c.scheme == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil, c.path.isEmpty,
              c.port.map({ (1...65535).contains($0) }) ?? true else { return false }
        let canonical = "https://" + host.lowercased() + (c.port.map { ":\($0)" } ?? "")
        return origin.utf8.elementsEqual(canonical.utf8)
    }
}

public enum ProfileSavedMediaExact {
    /// Includes display-only snapshot fields too. Never logs/serializes the signed URL.
    public static func snapshot(_ value: ProfileEditSnapshot) -> String {
        var fields = [ProfileAvatarExact.snapshot(value)]
        switch value.phoneDisplay {
        case .unavailable: fields.append("phone-unavailable")
        case .unbound: fields.append("phone-unbound")
        case .masked(let text): fields += ["phone-masked", text]
        }
        for key in value.preferenceNames.keys.sorted() { fields += [String(key), value.preferenceNames[key]!] }
        return ProfileAvatarExact.hash(ProfileAvatarExact.strings(fields))
    }
}
public struct ProfileCurrentMediaReadKey: Hashable {
    public let identity: ProfileReadIdentity, viewerRevision: UInt64, approvalRevision: UUID, readerRevision: UUID
    public let kind: ProfileCurrentMediaKind, originalIndex: Int, sourceDigest: String, snapshotDigest: String
}

/// One exact selected lease and purpose. No arbitrary image URL, upload or profile writer.
@MainActor @Observable public final class ProfileCurrentMediaReader {
    private let approval: ProfileSavedMediaReadApproval
    private let currentContext: () -> RuntimeDependencyContext?
    private let currentSession: () -> ProfileEditSession?
    private let selected: () -> ProfileSavedMediaReadApproval?
    private let transport: any ProfileSavedMediaDispatching
    private let readerRevision = UUID()
    private var retired = false
    private var active: [UUID: ProfileSavedMediaReadAuthorization] = [:]
    public init(approval: ProfileSavedMediaReadApproval, currentContext: @escaping () -> RuntimeDependencyContext?,
                currentSession: @escaping () -> ProfileEditSession?, selected: @escaping () -> ProfileSavedMediaReadApproval?,
                transport: (any ProfileSavedMediaDispatching)? = nil) {
        self.approval = approval; self.currentContext = currentContext; self.currentSession = currentSession
        self.selected = selected; self.transport = transport ?? ProfileSavedMediaURLSessionTransport()
    }
    public func retire() {
        retired = true; let pending = Array(active.values); active.removeAll()
        pending.forEach { $0.invalidate() }
    }
    public var isConfigured: Bool {
        guard !retired else { return false }
        guard selected() === approval, let c = currentContext(), approval.matches(c), let s = currentSession(),
              s.identity.accountID == c.session.accountID, s.identity.epoch == c.session.epoch,
              s.token.utf8.elementsEqual(c.session.token.utf8), s.viewerRevision == approval.viewerRevision else {
            retire(); return false
        }
        return true
    }
    public var kind: ProfileCurrentMediaKind { approval.kind }
    public var sourceRevision: UUID? { isConfigured ? approval.revision : nil }
    public static func sources(snapshot: ProfileEditSnapshot, kind: ProfileCurrentMediaKind) -> [String] {
        switch kind {
        case .avatar: return snapshot.avatar.isEmpty ? [] : [snapshot.avatar]
        case .caseImage: return ProfileCasePortfolio(casePics: snapshot.casePics).images
        case .contactQR: return snapshot.wechat.isEmpty ? [] : [snapshot.wechat]
        }
    }
    public func key(snapshot: ProfileEditSnapshot, kind: ProfileCurrentMediaKind, originalIndex: Int,
                    identity: ProfileReadIdentity?, viewerRevision: UInt64?) -> ProfileCurrentMediaReadKey? {
        guard isConfigured, kind == approval.kind, let session = currentSession(),
              identity == session.identity, viewerRevision == session.viewerRevision,
              snapshot.id == session.identity.accountID else { return nil }
        let sources = Self.sources(snapshot: snapshot, kind: kind)
        guard sources.indices.contains(originalIndex) else { return nil }
        let source = sources[originalIndex]
        guard source.utf8.count <= 8192, let url = URL(string: source),
              source.utf8.elementsEqual(url.absoluteString.utf8),
              RetainedImageOrigin.accepts(url, origins: approval.approvedOrigins) else { return nil }
        return .init(identity: session.identity, viewerRevision: session.viewerRevision, approvalRevision: approval.revision, readerRevision: readerRevision,
                     kind: kind, originalIndex: originalIndex, sourceDigest: ProfileAvatarExact.hash(Data(source.utf8)),
                     snapshotDigest: ProfileSavedMediaExact.snapshot(snapshot))
    }
    public func image(snapshot: ProfileEditSnapshot, key: ProfileCurrentMediaReadKey,
                      currentSnapshot: @escaping () -> ProfileEditSnapshot?) async throws -> Data {
        let current: () -> Bool = { [weak self] in
            guard let self, self.key(snapshot: snapshot, kind: key.kind, originalIndex: key.originalIndex,
                                    identity: key.identity, viewerRevision: key.viewerRevision) == key,
                  let value = currentSnapshot(), ProfileSavedMediaExact.snapshot(value) == key.snapshotDigest else { return false }
            return true
        }
        guard current() else { throw RetainedImageFailure.disabled }
        let raw = Self.sources(snapshot: snapshot, kind: key.kind)[key.originalIndex]
        guard let url = URL(string: raw) else { throw RetainedImageFailure.invalid }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let authorization = ProfileSavedMediaReadAuthorization(expected: request, current: current)
        let operation = UUID(); active[operation] = authorization
        defer { active.removeValue(forKey: operation); authorization.invalidate() }
        try Task.checkCancellation()
        let bytes = try await transport.send(request, authorization: authorization)
        try Task.checkCancellation()
        guard authorization.didForward, authorization.isCurrent, !bytes.isEmpty,
              bytes.count <= RetainedSelectedImage.maximumInputBytes else { throw RetainedImageFailure.invalid }
        return bytes
    }
}
