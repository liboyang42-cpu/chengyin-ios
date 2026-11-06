import Foundation

/// A request-entry predicate, NOT membership/access authorization. Fixed58 detail
/// does not expose club status or participation-ban authority. Those facts are
/// decided only by the authenticated original /members and /leaderboard readers.
public enum ClubPublicRosterEligibility {
    public static func mayRequest(_ club: ClubRecord, identity: ClubReadIdentity) -> Bool {
        (identity.accountID ?? 0) > 0 && club.id > 0 && !club.viewerIdentityUnavailable && club.explicitJoinPolicy == 0
    }
}

/// Dedicated public-roster read capability; never grants access/me, customer data,
/// member reports, mutations, phone/contact fields, or paid-member features.
public struct ClubPublicRosterApproval: Equatable {
    public let identity: ClubReadIdentity
    public let baseURL: URL
    public let revision: UUID
    public init(identity: ClubReadIdentity, baseURL: URL, revision: UUID) {
        self.identity = identity; self.baseURL = baseURL; self.revision = revision
    }
}

public enum ClubPublicRosterMode: String, CaseIterable, Equatable, Hashable {
    case members, composite, mileage, pace, duration
}
