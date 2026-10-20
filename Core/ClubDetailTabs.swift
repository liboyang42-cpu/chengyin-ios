import Foundation

/// Mini-program `pages/club/detail` view tabs: posts / events / overview are public,
/// manage is appended only for governors or a scoped access/me grant.
public enum ClubDetailTab: String, CaseIterable, Identifiable, Sendable {
    case posts, events, overview, manage
    public var id: String { rawValue }
    public static let publicTabs: [ClubDetailTab] = [.posts, .events, .overview]
}

/// Projection of `/api/club/access/me` that only decides manage-tab visibility.
/// `nil` means the access read is loading or failed; the legacy owner/admin flags
/// from `/api/club/detail` still govern the tab, matching `revokeClubAccess`.
public struct ClubDetailManageGrant: Equatable, Sendable {
    /// Permissions that each open a manage-tab tool in the mini-program.
    public static let managePermissions: Set<String> = [
        "club:write", "club:member:approve", "club:member:manage", "club:content:manage",
        "club:role:manage", "club:notify:send", "club:activity:manage", "club:event:operate",
        "club:event:checkin", "club:finance:read",
    ]
    public let clubID: Int
    public let allowsManage: Bool
    public init(clubID: Int, permissions: Set<String>, hasEventScope: Bool) {
        self.clubID = clubID
        allowsManage = hasEventScope || !permissions.isDisjoint(with: Self.managePermissions)
    }
    public init(_ permissions: ClubGovernancePermissions) {
        self.init(clubID: permissions.clubID, permissions: permissions.active ? permissions.permissions : [],
                  hasEventScope: permissions.active && !permissions.eventAccesses.isEmpty)
    }
}

public struct ClubDetailTabPolicy: Equatable, Sendable {
    public let clubID: Int
    public let isOwner: Bool
    public let isJoined: Bool
    public let viewerIsAdmin: Bool
    public let grant: ClubDetailManageGrant?

    public init(clubID: Int, isOwner: Bool, isJoined: Bool, viewerIsAdmin: Bool, grant: ClubDetailManageGrant? = nil) {
        self.clubID = clubID; self.isOwner = isOwner; self.isJoined = isJoined; self.viewerIsAdmin = viewerIsAdmin
        // A grant for another club never widens this club's tabs.
        self.grant = grant?.clubID == clubID ? grant : nil
    }

    public init(club: ClubRecord, grant: ClubDetailManageGrant? = nil) {
        self.init(clubID: club.id, isOwner: club.isOwner, isJoined: club.isJoined, viewerIsAdmin: club.viewerIsAdmin, grant: grant)
    }

    /// `canGovern`: owner or legacy role=1 administrator from the detail payload.
    public var canGovern: Bool { isOwner || viewerIsAdmin }
    public var canUseManageTab: Bool { canGovern || grant?.allowsManage == true }
    public var tabs: [ClubDetailTab] { canUseManageTab ? ClubDetailTab.publicTabs + [.manage] : ClubDetailTab.publicTabs }
    /// Owners and members land on posts; guests (including merchant viewers) on overview.
    public var defaultTab: ClubDetailTab { isOwner || isJoined ? .posts : .overview }

    /// Initial tab after the detail read. A `manage` deep-link intent is honored only once
    /// the server has confirmed the viewer may use it; otherwise the public default wins.
    public func initialTab(requested: ClubDetailTab?) -> ClubDetailTab {
        if let requested, tabs.contains(requested) { return requested }
        return defaultTab
    }

    /// Re-validates a selection after detail or access changes (role revoked, account switch).
    public func resolve(_ selection: ClubDetailTab?) -> ClubDetailTab {
        guard let selection, tabs.contains(selection) else { return defaultTab }
        return selection
    }

    /// `switchTab`: idempotent, and the manage tab cannot be opened by an event when gated.
    public func select(_ tab: ClubDetailTab, from current: ClubDetailTab) -> ClubDetailTab {
        tabs.contains(tab) ? tab : current
    }
}
