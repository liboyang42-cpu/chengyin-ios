import Foundation

/// Presentation state for the club-detail events tab summary. Pure projection of an already
/// authorized `ClubActivityOverview` read: loading / empty / failure / loaded never mix, and a
/// result belonging to another club or read context is rejected rather than shown.
public struct ClubDetailEventsSummary: Equatable {
    public enum State: Equatable {
        case loading
        case failed(localizationKey: String)
        case empty
        case loaded(current: Int, ended: Int, upcoming: [ClubActivityRow])
    }
    public static let upcomingLimit = 3
    public let state: State

    public init(state: State) { self.state = state }

    /// `overview` must be the accepted read for the current club/account; callers pass nil when the
    /// context changed (club switch, account switch) so stale rows cannot leak into another club.
    public init(overview: ClubActivityOverview?, failure: ClubGovernanceFailure?, loading: Bool = true) {
        if let failure { state = .failed(localizationKey: failure.localizationKey) }
        else if let overview {
            state = overview.rows.isEmpty ? .empty
                : .loaded(current: overview.current.count, ended: overview.ended.count,
                          upcoming: Array(overview.current.prefix(Self.upcomingLimit)))
        } else { state = .loading }
    }
}
