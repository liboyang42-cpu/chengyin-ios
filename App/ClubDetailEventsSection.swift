import SwiftUI

/// Events-tab summary for the existing club detail. It reuses the read-only
/// `ClubEventCalendarReadModel` (access/me preflight + `.topics` read) and never opens a new
/// transport or write path. Its own state is isolated from the other tabs: a failure or empty
/// result here does not affect posts/overview/manage. The calendar link is the only destination;
/// activity rows open through the existing `ClubEventCalendarView` destinations.
@MainActor struct ClubDetailEventsSection: View {
    let club: ClubRecord
    let identity: ClubReadIdentity
    let governance: ClubGovernanceContext
    var reader: (any ClubReading)? = nil
    @StateObject private var model = ClubEventCalendarReadModel()
    private var readContext: ClubGovernanceReadContext {
        .init(operation: .topics, scope: .init(clubID: club.id), identity: identity,
              viewerRevision: governance.viewerRevision, authorizationGeneration: governance.access.authorizationGeneration,
              accessIdentity: ObjectIdentifier(governance.access))
    }
    private var summary: ClubDetailEventsSummary {
        let accepted = model.accepted(readContext, access: governance.access)
        return .init(overview: accepted ? model.activityOverview : nil, failure: model.failure, loading: model.loading)
    }
    var body: some View {
        Section {
            switch summary.state {
            case .loading:
                ProgressView().accessibilityIdentifier("club.detail.events.loading")
            case .failed(let key):
                Text(LocalizedStringKey(key)).foregroundStyle(.secondary).accessibilityIdentifier("club.detail.events.error")
            case .empty:
                Text("club.calendar.noEvents").foregroundStyle(.secondary).accessibilityIdentifier("club.detail.events.empty")
            case .loaded(let current, let ended, let upcoming):
                LabeledContent("club.activityList.current") { Text(current, format: .number) }
                    .accessibilityIdentifier("club.detail.events.currentCount")
                LabeledContent("club.activityList.ended") { Text(ended, format: .number) }
                    .accessibilityIdentifier("club.detail.events.endedCount")
                ForEach(upcoming) { row in
                    if let name = row.name { Text(verbatim: name) } else { Text("club.calendar.untitled") }
                }
            }
            NavigationLink {
                ClubEventCalendarView(clubID: club.id, identity: identity, governance: governance, reportClub: club, reportReader: reader)
            } label: { Label("club.calendar.title", systemImage: "calendar") }
                .accessibilityIdentifier("club.calendar.open")
        }
        // Keyed by club + identity + authorization so a switch discards the previous club's result first.
        .task(id: readContext) {
            model.invalidate(); model.resume()
            await model.load(readContext, access: governance.access)
        }
        .onDisappear { model.suspend() }
    }
}
