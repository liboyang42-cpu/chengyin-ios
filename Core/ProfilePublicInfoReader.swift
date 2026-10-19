import Foundation
import Observation

/// Public metadata is loaded by the existing service. No private account or invitation request.
@MainActor @Observable public final class ProfilePublicInfoReader: SocialAccountReading {
    public let target: ProfilePublicInfoTarget
    private let service: SocialAccountService?
    private let deployment: URL?
    private let selectAccess: (RuntimeDependencyContext) -> ProfilePublicInfoReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var observedAccess: UUID?
    private var revision: UInt64 = 0
    private var retentionRevision: UInt64 = 0
    private var readGeneration = UUID()
    public private(set) var hasAppeared = false
    private var presented = false
    private var foreground = false
    public init(target: ProfilePublicInfoTarget, configuration: APIConfiguration?, transport: any HTTPTransport,
                access: @escaping (RuntimeDependencyContext) -> ProfilePublicInfoReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.target = target; deployment = configuration?.baseURL
        service = configuration.map { SocialAccountService(configuration: $0, transport: transport) }
        selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    public var identity: SocialAccountIdentity {
        .init(accountID: target.context.session.accountID, epoch: target.context.session.epoch, role: target.context.role)
    }
    public var isCurrent: Bool { target.isCurrent }
    public var presentationRevision: UInt64 { _ = currentAccess(); return revision }
    /// Retaining an author-feed snapshot never extends the underlying read grant.
    /// Header visibility/read-generation and its presentation revision remain independent.
    public var authorPostsRetentionIdentity: ProfilePublicInfoRetentionIdentity? {
        guard let access = currentAccess(), service != nil else { return nil }
        return .init(targetID: target.id, memberID: target.memberID, viewerRevision: target.viewerRevision,
            approvalID: access.revision, revision: retentionRevision)
    }
    public var isConfigured: Bool { currentAccess() != nil && service != nil }
    public var isOfflineExample: Bool { false }
    public var isVisible: Bool { presented && foreground }
    private func currentAccess() -> ProfilePublicInfoReadAccess? {
        let value: ProfilePublicInfoReadAccess?
        if target.isCurrent,
           deployment?.absoluteString.utf8.elementsEqual(target.context.baseURL.absoluteString.utf8) == true,
           let selected = selectAccess(target.context), selected.matches(target.context) { value = selected }
        else { value = nil }
        if observedAccess != value?.revision {
            observedAccess = value?.revision; revision &+= 1; retentionRevision &+= 1; readGeneration = UUID()
        }
        return value
    }
    public func appear(foreground: Bool) {
        guard !presented || self.foreground != foreground else { return }
        if hasAppeared { revision &+= 1 }
        hasAppeared = true; presented = true; self.foreground = foreground; readGeneration = UUID()
    }
    public func disappear() { presented = false; readGeneration = UUID() }
    public func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value; readGeneration = UUID()
        if presented && value { revision &+= 1 }
    }
    /// A covered editor keeps its context. Only a current visible user's refresh changes the UI key.
    public func requestRefresh() {
        guard isVisible, isConfigured, target.isCurrent else { return }
        revision &+= 1; readGeneration = UUID()
    }
    public func publicProfile(memberID: Int) async throws -> SocialPublicProfile {
        guard memberID == target.memberID else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        guard isVisible, target.isCurrent else { throw CancellationError() }
        guard let selected = currentAccess(), let service else { throw APIError.notConfigured }
        let generation = readGeneration
        func valid() -> Bool {
            !Task.isCancelled && isVisible && target.isCurrent && currentAccess() === selected && readGeneration == generation
        }
        do {
            let profile = try await service.profile(memberID: memberID, token: target.context.session.token)
            guard valid() else { throw CancellationError() }
            guard profile.id == memberID else { throw APIError.malformedResponse }
            return profile
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(target.context) }
            throw error
        }
    }
    public func informationList() async throws -> [SocialInformation] { throw APIError.notConfigured }
    public func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
    public func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
}


/// Exact retained target and approval issuance, without credentials or new permission.
public struct ProfilePublicInfoRetentionIdentity: Hashable {
    public let targetID: UUID
    public let memberID: Int
    public let viewerRevision: UInt64
    public let approvalID: UUID
    public let revision: UInt64
}
