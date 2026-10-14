import Foundation
import Observation

@MainActor @Observable public final class ProfileGuideListReader: SocialAccountReading {
    public let context: RuntimeDependencyContext
    public let viewerRevision: UInt64
    private let service: SocialAccountService?
    private let current: () -> Bool
    private let selectAccess: (RuntimeDependencyContext) -> ProfileGuideReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var retired = false
    private var observedAccess: UUID?
    private var revision: UInt64 = 0
    private var receipt = UUID()
    private var readGeneration = UUID()
    private var accepted: [Int: SocialInformation] = [:]
    private var presented = false, foreground = false
    public private(set) var hasAppeared = false
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64, service: SocialAccountService?,
                current: @escaping () -> Bool, access: @escaping (RuntimeDependencyContext) -> ProfileGuideReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.context = context; self.viewerRevision = viewerRevision; self.service = service
        self.current = current; selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    public var identity: SocialAccountIdentity { .init(accountID: context.session.accountID, epoch: context.session.epoch, role: context.role) }
    public var isOfflineExample: Bool { false }
    public var isCurrent: Bool {
        guard !retired else { return false }
        guard current() else { retire(); return false }
        return true
    }
    public var isVisible: Bool { presented && foreground }
    public var presentationRevision: UInt64 { _ = activeAccess(); return revision }
    public var isConfigured: Bool { activeAccess() != nil && service != nil }
    private func activeAccess() -> ProfileGuideReadAccess? {
        let selected = isCurrent ? selectAccess(context) : nil
        let value = selected?.matches(context) == true ? selected : nil
        if observedAccess != value?.revision {
            observedAccess = value?.revision; revision &+= 1; receipt = UUID(); readGeneration = UUID(); accepted.removeAll()
        }
        return value
    }
    public func appear(foreground: Bool) {
        guard !presented || self.foreground != foreground else { return }
        if hasAppeared { revision &+= 1 }
        presented = true; self.foreground = foreground; hasAppeared = true; readGeneration = UUID()
    }
    public func disappear() { presented = false; readGeneration = UUID() }
    public func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value; readGeneration = UUID()
        if presented && value { revision &+= 1 }
    }
    public func refresh() {
        guard isVisible, isConfigured else { return }
        revision &+= 1; receipt = UUID(); readGeneration = UUID(); accepted.removeAll()
    }
    public func retire() { retired = true; presented = false; receipt = UUID(); readGeneration = UUID(); accepted.removeAll() }
    public func informationList() async throws -> [SocialInformation] {
        try Task.checkCancellation()
        guard isCurrent, isVisible else { throw CancellationError() }
        guard let selected = activeAccess(), let service else { throw APIError.notConfigured }
        receipt = UUID(); accepted.removeAll()
        let captured = receipt, generation = readGeneration
        func valid() -> Bool {
            !Task.isCancelled && isVisible && isCurrent && activeAccess() === selected && receipt == captured && readGeneration == generation
        }
        do {
            let rows = try await service.informationList(token: context.session.token)
            guard valid() else { throw CancellationError() }
            guard Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
            accepted = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            return rows
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(context) }
            throw error
        }
    }
    public func select(_ row: SocialInformation) -> ProfileGuideArticleSelection? {
        guard isVisible, isConfigured, row.isUsable, accepted[row.id] == row else { return nil }
        let captured = receipt
        return ProfileGuideArticleSelection(row: row, context: context, viewerRevision: viewerRevision, current: { [weak self] in
            guard let self, self.isCurrent, self.isConfigured else { return false }
            return self.receipt == captured && self.accepted[row.id] == row
        })
    }
    public func publicProfile(memberID: Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
    public func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
    public func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
}

@MainActor @Observable public final class ProfileGuideArticleReader: SocialAccountReading {
    public let selection: ProfileGuideArticleSelection
    private let service: SocialAccountService?
    private let access: (RuntimeDependencyContext) -> ProfileGuideReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var presented = false, foreground = false
    private var generation = UUID()
    private var observedAccess: UUID?
    private var revision: UInt64 = 0
    public private(set) var hasAppeared = false
    public init(selection: ProfileGuideArticleSelection, service: SocialAccountService?,
                access: @escaping (RuntimeDependencyContext) -> ProfileGuideReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.selection = selection; self.service = service; self.access = access; self.onUnauthorized = onUnauthorized
    }
    public var identity: SocialAccountIdentity { .init(accountID: selection.context.session.accountID, epoch: selection.context.session.epoch, role: selection.context.role) }
    public var isOfflineExample: Bool { false }
    public var isVisible: Bool { presented && foreground }
    public var presentationRevision: UInt64 { _ = activeAccess(); return revision }
    public var isConfigured: Bool { activeAccess() != nil && service != nil }
    private func activeAccess() -> ProfileGuideReadAccess? {
        let selected = selection.isCurrent ? access(selection.context) : nil
        let value = selected?.matches(selection.context) == true ? selected : nil
        if observedAccess != value?.revision { observedAccess = value?.revision; revision &+= 1; generation = UUID() }
        return value
    }
    public func appear(foreground: Bool) {
        guard selection.isCurrent else { return }
        guard !presented || self.foreground != foreground else { return }
        presented = true; self.foreground = foreground; hasAppeared = true; generation = UUID()
    }
    public func disappear() { presented = false; generation = UUID(); selection.retire() }
    public func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value; generation = UUID()
        if presented && value { revision &+= 1 }
    }
    public func information(id: Int) async throws -> SocialInformation {
        guard id == selection.row.id else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        guard selection.isCurrent, isVisible else { throw CancellationError() }
        guard let selected = activeAccess(), let service else { throw APIError.notConfigured }
        let captured = generation
        func valid() -> Bool { !Task.isCancelled && isVisible && selection.isCurrent && activeAccess() === selected && generation == captured }
        do {
            let row = try await service.information(id: id, token: selection.context.session.token)
            guard valid() else { throw CancellationError() }
            return row
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(selection.context) }
            throw error
        }
    }
    public func publicProfile(memberID: Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
    public func informationList() async throws -> [SocialInformation] { throw APIError.notConfigured }
    public func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
}
