import Foundation
import Combine

@MainActor public protocol ClubWelcomeSeenStoring {
    func hasSeen(accountID: Int, clubID: Int, namespace: String) throws -> Bool
    func markSeen(accountID: Int, clubID: Int, namespace: String) throws
}
/// Local actor+club presentation preference only. It confers no membership or rights.
@MainActor public final class ClubWelcomeDefaults: ClubWelcomeSeenStoring {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(accountID: Int, clubID: Int, namespace: String) throws -> String {
        guard accountID > 0, clubID > 0, !namespace.isEmpty else { throw APIError.invalidRequest }
        return "club_welcome_seen_v1_" + Data("\(namespace.utf8.count):\(namespace):\(accountID):\(clubID)".utf8).base64EncodedString()
    }
    public func hasSeen(accountID: Int, clubID: Int, namespace: String) throws -> Bool {
        let key = try key(accountID: accountID, clubID: clubID, namespace: namespace)
        guard let value = defaults.object(forKey: key) else { return false }
        guard let seen = value as? Bool else { throw APIError.malformedResponse }; return seen
    }
    public func markSeen(accountID: Int, clubID: Int, namespace: String) throws {
        let key = try key(accountID: accountID, clubID: clubID, namespace: namespace)
        defaults.set(true, forKey: key)
        guard defaults.bool(forKey: key) else { throw APIError.malformedResponse }
    }
}
public struct ClubMemberWelcome: Identifiable, Equatable {
    public let id: UUID
    public let identity: ClubReadIdentity
    public let club: ClubRecord
    public let role: String?
    public let namespace: String
    public var postingKey: String {
        switch club.memberPostAllowed {
        case true: return "welcome.posts.allowed"
        case false: return "welcome.posts.read"
        case nil: return "welcome.posts.unknown"
        }
    }
    public var eventsKey: String {
        if role == "merchant" { return "welcome.events.merchant" }
        return club.prioritySignupEnabled == true ? "welcome.events.priority" : "welcome.events.normal"
    }

}
/// Fresh joined detail drives both direct-join readback and first re-entry after approval.
/// A pending request alone never triggers welcome. Paid membership is unrelated.
@MainActor public final class ClubWelcomePresentation: ObservableObject {
    @Published public private(set) var presentation: ClubMemberWelcome?
    private let seen: any ClubWelcomeSeenStoring
    public init(seen: (any ClubWelcomeSeenStoring)? = nil) { self.seen = seen ?? ClubWelcomeDefaults() }
    public func consider(club: ClubRecord, identity: ClubReadIdentity, namespace: String?, role: String?, active: Bool) {
        guard active, let namespace, !namespace.isEmpty, let actor = identity.accountID, actor > 0,
              club.isJoined, !club.isOwner, !club.viewerIdentityUnavailable else { presentation = nil; return }
        if let current = presentation {
            guard current.identity == identity, current.club.id == club.id, current.namespace == namespace else { presentation = nil; return }
            // Always render fresh note/settings; do not preserve stale privileges in an open sheet.
            presentation = .init(id: current.id, identity: identity, club: club, role: role, namespace: namespace); return
        }
        do { guard try !seen.hasSeen(accountID: actor, clubID: club.id, namespace: namespace) else { return } }
        catch { return } // Source suppresses auto-presentation if the seen read fails.
        presentation = .init(id: UUID(), identity: identity, club: club, role: role, namespace: namespace)
        // Source records on opening; a storage write failure can show again next entry.
        try? seen.markSeen(accountID: actor, clubID: club.id, namespace: namespace)
    }
    public func dismiss(_ id: UUID) { if presentation?.id == id { presentation = nil } }
    public func clear() { presentation = nil }
}
