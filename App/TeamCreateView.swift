import SwiftUI

/// Present only from an activity registration, never a nearby-team, route-ticket or club ID.
@MainActor struct TeamCreateView: View {
    let activityID: Int
    @StateObject private var model: TeamScreenModel
    @State private var size = 2
    @State private var inviteOnly = false
    init(activityID: Int, coordinator: TeamCoordinator) { self.activityID = activityID; _model = StateObject(wrappedValue: TeamScreenModel(coordinator)) }
    var body: some View {
        Form {
            Section { TeamNotice(coordinator: model.coordinator) }
            if model.running { ProgressView("team.loading") }
            if let context = model.coordinator.creation {
                Section("team.create.activity") { Text(verbatim: context.title) }
                Section("team.create.settings") {
                    Picker("team.size", selection: $size) { ForEach(context.sizes, id: \.self) { Text(verbatim: "\($0)").tag($0) } }
                        .accessibilityIdentifier("team.create.size")
                    Toggle("team.invitationOnly", isOn: $inviteOnly).accessibilityIdentifier("team.create.inviteOnly")
                    Text(inviteOnly ? "team.create.privateHelp" : "team.create.publicHelp").font(.footnote).foregroundStyle(.secondary)
                }.disabled(model.actionLocked)
                Section {
                    Text("team.create.consequence").fixedSize(horizontal: false, vertical: true)
                    Button("team.create.review") { model.prepare(.create(context: context, size: size, inviteOnly: inviteOnly)) }
                        .frame(minHeight: 44).disabled(model.actionLocked).accessibilityIdentifier("team.create.review")
                }
            }
            if model.coordinator.pending != nil {
                Button("team.checkOutcome") { Task { await model.run { await model.coordinator.checkOutcome() } } }
                    .disabled(model.running || !model.coordinator.canSimulate).accessibilityIdentifier("team.checkOutcome")
            }
        }.appNavigationTitle("team.create")
            .task { await model.run { await model.coordinator.loadCreation(ownerID: activityID) } }
            .sheet(item: model.reviewBinding) { TeamReviewSheet(model: model, review: $0) }
            .onDisappear { model.leave() }
    }
}
