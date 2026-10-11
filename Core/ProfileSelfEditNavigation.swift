import Foundation
import Observation

/// Local navigation identity only. Never credentials, mutation permission, or saved-profile data.
public struct ProfileSelfEditContext: Hashable {
    public let memberID: Int
    public let reader: ObjectIdentifier
    public let viewer: SocialAccountIdentity
    public let readerRevision: UInt64
    public let coordinator: ObjectIdentifier
    public let editorIdentity: ProfileReadIdentity
    public let editorRevision: UInt64?
    public init?(memberID: Int, reader: AnyObject, viewer: SocialAccountIdentity, readerRevision: UInt64,
                 readerConfigured: Bool, coordinator: AnyObject, editorIdentity: ProfileReadIdentity?,
                 editorRevision: UInt64?, editorConfigured: Bool, isCurrent: Bool) {
        guard isCurrent, readerConfigured, editorConfigured, memberID > 0,
              viewer.accountID == memberID, let editorIdentity, editorIdentity.accountID == memberID else { return nil }
        self.memberID = memberID; self.reader = ObjectIdentifier(reader); self.viewer = viewer
        self.readerRevision = readerRevision; self.coordinator = ObjectIdentifier(coordinator)
        self.editorIdentity = editorIdentity; self.editorRevision = editorRevision
    }
}
public struct ProfileSelfEditTicket: Identifiable, Hashable {
    public let id: UUID
    public let context: ProfileSelfEditContext
    fileprivate init(context: ProfileSelfEditContext) { id = UUID(); self.context = context }
}
/// Returning never means Saved. It requests a fresh read through the existing public reader,
/// including after cancel/discard; no draft is copied into the public projection.
@MainActor @Observable public final class ProfileSelfEditNavigation {
    public private(set) var ticket: ProfileSelfEditTicket?
    public private(set) var refreshID = UUID()
    public init() {}
    @discardableResult public func open(_ context: ProfileSelfEditContext?) -> ProfileSelfEditTicket? {
        guard ticket == nil, let context else { return nil }
        let next = ProfileSelfEditTicket(context: context); ticket = next; return next
    }
    public func isCurrent(_ proposed: ProfileSelfEditTicket, context: ProfileSelfEditContext?) -> Bool {
        ticket == proposed && context == proposed.context
    }
    /// Compare exact presentation ID so a delayed pop cannot retire a newer editor.
    @discardableResult public func finish(_ id: UUID, context: ProfileSelfEditContext?) -> Bool {
        guard let value = ticket, value.id == id else { return false }
        ticket = nil
        guard context == value.context else { return false }
        refreshID = UUID(); return true
    }
}
