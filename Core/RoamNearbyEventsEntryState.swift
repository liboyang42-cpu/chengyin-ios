import Foundation
import Observation

/// A manual search centre is query context, not a device fix or permission to locate.
public struct RoamNearbyEventsEntryScope: Equatable {
    public let readerID: ObjectIdentifier
    public let readKey: String
    public let area: RoamSearchArea
    @MainActor public init?(reader: any RoamEntryNearbyReading) {
        guard reader.isSignedIn, reader.isConfigured, let area = reader.searchArea else { return nil }
        readerID = ObjectIdentifier(reader); readKey = reader.readKey; self.area = area
    }
}

/// Keeps the source's topic-first destination, while fencing the exact tapped card.
public struct RoamNearbyEventsEntrySelection: Identifiable {
    public let id = UUID()
    public let card: RoamEntryActivityCard
    private let origin: RoamNearbyEventsEntryScope
    public init(card: RoamEntryActivityCard, scope: RoamNearbyEventsEntryScope) {
        self.card = card; origin = scope
    }
    public func mayRemainOpen(in scope: RoamNearbyEventsEntryScope?) -> Bool { origin == scope }
}

/// The optional team read is not the activity read. Failure must not fabricate an empty team list.
public enum RoamNearbyEventsTeamReadState: Equatable {
    case notRequested, loading, loaded, failed
}

/// The entry peek's existing reads, with one generation across both activity and team responses.
/// No retained cards are exposed after a refresh, missing centre, account change or revoked read.
@MainActor @Observable public final class RoamNearbyEventsEntryState {
    public private(set) var state: RoamEntryPeekState = .loading
    public private(set) var loadedScope: RoamNearbyEventsEntryScope?
    public private(set) var readID = UUID()
    public private(set) var teamState: RoamNearbyEventsTeamReadState = .notRequested
    private var generation = 0
    public init() {}

    public func visibleState(reader: any RoamEntryNearbyReading) -> RoamEntryPeekState {
        guard reader.isSignedIn else { return .login }
        guard reader.isConfigured, reader.searchArea != nil else { return .unavailable }
        guard loadedScope == RoamNearbyEventsEntryScope(reader: reader) else { return .loading }
        return state
    }

    public func selection(card: RoamEntryActivityCard, rendered: RoamNearbyEventsEntryScope?, readID: UUID,
                          reader: any RoamEntryNearbyReading) -> RoamNearbyEventsEntrySelection? {
        guard readID == self.readID, let rendered, rendered == loadedScope, rendered == RoamNearbyEventsEntryScope(reader: reader),
              case .loaded(let cards) = state, cards.contains(card) else { return nil }
        return .init(card: card, scope: rendered)
    }

    public func visibleTeamState(reader: any RoamEntryNearbyReading) -> RoamNearbyEventsTeamReadState {
        guard loadedScope != nil, loadedScope == RoamNearbyEventsEntryScope(reader: reader) else { return .notRequested }
        return teamState
    }

    public func cancel() { generation += 1; readID = UUID(); loadedScope = nil; state = .loading; teamState = .notRequested }

    public func load(reader: any RoamEntryNearbyReading,
                     teams: ((RoamSearchArea) async -> [NearbyTeam]?)? = nil) async {
        guard !Task.isCancelled else { return }
        cancel(); let ticket = generation
        guard let captured = RoamNearbyEventsEntryScope(reader: reader) else { return }
        func current() -> Bool {
            !Task.isCancelled && ticket == generation && captured == RoamNearbyEventsEntryScope(reader: reader)
        }
        do {
            let rows = try await reader.entryNearby()
            guard current() else { return }
            // Publish the independently successful activity read before the optional team await.
            // Zero displayed counts here mean no team facts have been added, not a successful read.
            loadedScope = captured; state = .init(activities: rows, teams: [])
            if let teams, !rows.isEmpty {
                teamState = .loading
                let result = await teams(captured.area)
                guard current() else {
                    if ticket == generation { cancel() }
                    return
                }
                guard let result else { teamState = .failed; return }
                // Enrichment replaces the rendered cards. Retire closures from the earlier snapshot.
                readID = UUID(); teamState = .loaded
                state = .init(activities: rows, teams: result)
            }
        } catch is CancellationError {
        } catch {
            guard current() else { return }
            loadedScope = captured; state = .init(error: error)
        }
    }
}
