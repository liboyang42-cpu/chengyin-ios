import SwiftUI

/// Session-picker sheet for a topic. It only displays the activities already
/// loaded with the topic and forwards a chosen, real `activity.id` to the
/// host-injected activity destination (the existing activity detail and its
/// sign-up flow). It performs no request and no enrollment itself.
@MainActor
struct TopicSessionSelectionView: View {
    let detail: TopicDetail
    let scope: UUID
    var activityDestination: ((Int) -> AnyView)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var flow = TopicSessionSelectionFlow()
    @State private var path: [Int] = []

    private var resolution: TopicSessionSelectionResolution {
        TopicSessionSelectionResolution.resolve(activities: detail.activities, hasDestination: activityDestination != nil)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                switch resolution {
                case .missingData:
                    Text("topic.sessionSelection.missingData")
                        .accessibilityIdentifier("topic.sessionSelection.missingData")
                case .empty:
                    Text("topic.sessionSelection.empty")
                        .accessibilityIdentifier("topic.sessionSelection.empty")
                case .destinationUnavailable(let activities):
                    Text("topic.sessionSelection.destinationUnavailable")
                        .accessibilityIdentifier("topic.sessionSelection.destinationUnavailable")
                    ForEach(activities) { activity in activityRow(activity) }
                case .ready(let activities):
                    ForEach(activities) { activity in
                        Button {
                            if let selected = flow.select(activityID: activity.id, hasDestination: activityDestination != nil) {
                                path.append(selected)
                            }
                        } label: {
                            activityRow(activity)
                        }
                        .accessibilityIdentifier("topic.sessionSelection.activity.\(activity.id)")
                    }
                }
                if !detail.tickets.isEmpty {
                    Section("topic.tickets") {
                        Text("topic.sessionSelection.ticketDependency")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("topic.sessionSelection.ticketDependency")
                        ForEach(Array(detail.tickets.enumerated()), id: \.offset) { _, ticket in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: ticket.name).font(.headline)
                                TopicPrice(value: ticket.price, label: "topic.price")
                                if let start = ticket.startTime { LabeledContent("topic.start", value: start) }
                                if let end = ticket.endTime { LabeledContent("topic.end", value: end) }
                            }
                        }
                    }
                }
            }
            .appNavigationTitle("topic.sessionSelection.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("topic.sessionSelection.close") { flow.close(); dismiss() }
                        .accessibilityIdentifier("topic.sessionSelection.close")
                }
            }
            .navigationDestination(for: Int.self) { activityID in
                if let activityDestination {
                    activityDestination(activityID)
                } else {
                    Text("topic.sessionSelection.destinationUnavailable")
                }
            }
        }
        .accessibilityIdentifier("topic.sessionSelection")
        .onAppear { flow.open(scope: scope, activityIDs: resolution.activities.map(\.id)) }
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty { flow.returnedFromActivity() }
        }
        .onChange(of: scope) { _, newScope in
            if flow.scopeChanged(to: newScope) { dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, flow.isPresented { flow.backgrounded(); dismiss() }
        }
    }

    private func activityRow(_ activity: TopicActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: activity.name).font(.headline)
            if let address = activity.addressName { Text(verbatim: address) }
            if let start = activity.startDate { LabeledContent("topic.start", value: start) }
            if let end = activity.endDate { LabeledContent("topic.end", value: end) }
        }
    }
}
