import SwiftUI

@MainActor final class TeamScreenModel: ObservableObject {
    let coordinator: TeamCoordinator
    @Published private(set) var running = false
    init(_ coordinator: TeamCoordinator) { self.coordinator = coordinator }
    func run(_ operation: () async -> Void) async {
        guard !running else { return }; running = true
        await operation(); running = false
    }
    func prepare(_ action: TeamAction) { coordinator.prepare(action); objectWillChange.send() }
    func cancel() { coordinator.cancelReview(); objectWillChange.send() }
    func leave() { coordinator.leaveScreen(); objectWillChange.send() }
    var reviewBinding: Binding<TeamReview?> { Binding(get: { self.coordinator.review }, set: { if $0 == nil { self.cancel() } }) }
    var actionLocked: Bool { running || coordinator.busy || coordinator.pending != nil || coordinator.writeState == .simulated || coordinator.writeState == .acknowledged || coordinator.writeState == .blocked }
}
@MainActor struct TeamNotice: View {
    // Capture value inputs for SwiftUI's child-view diff. The coordinator is not
    // Observable, so retaining only its reference leaves notices stale after writes,
    // invalid links and sign-out even when the parent model publishes a redraw.
    let canSimulate: Bool
    let messageKey: String?
    let hasPending: Bool
    init(coordinator: TeamCoordinator) {
        canSimulate = coordinator.canSimulate
        messageKey = coordinator.messageKey
        hasPending = coordinator.pending != nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canSimulate { Label("team.fixtureNotice", systemImage: "testtube.2").accessibilityIdentifier("team.fixtureNotice") }
            Text("team.writesDisabled")
            if let key = messageKey {
                Label(LocalizedStringKey(key), systemImage: hasPending ? "exclamationmark.triangle" : "info.circle")
                    .accessibilityIdentifier("team.message")
            }
        }.font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
struct TeamCard: View {
    let team: OwnedTeam
    var body: some View {
        QuestifyImageEntityCard(imageSource: nil, title: team.title, fallbackTitle: "team.untitled", fallbackSymbol: "person.3", minimumHeight: 220) {
            Label(LocalizedStringKey(team.status.key), systemImage: "person.2")
            if let joined = team.joinedCount, let max = team.maxMembers {
                QuestifyImageEntityMetadata(label: "team.members.count", value: "\(joined) / \(max)", systemImage: "person.2.fill")
            } else { Text("team.members.unknown") }
            Text(LocalizedStringKey(team.joinMode.key))
        }
    }
}
struct TeamMemberRow: View {
    let member: TeamMember
    var remove: (() -> Void)?
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.crop.circle.fill").font(.title).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if member.name.isEmpty { Text("team.member.unnamed") } else { Text(verbatim: member.name).fixedSize(horizontal: false, vertical: true) }
                Text(member.isCaptain ? "team.member.captain" : member.role == 0 ? "team.member.player" : "team.member.unknownRole").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let remove { Button("team.remove", role: .destructive, action: remove).frame(minHeight: 44).accessibilityIdentifier("team.remove.\(member.id)") }
        }.padding(.vertical, 8)
    }
}
@MainActor struct TeamReviewSheet: View {
    @ObservedObject var model: TeamScreenModel
    let review: TeamReview
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(LocalizedStringKey(review.action.key)).font(.title2.bold())
                    if let detail = review.detail {
                        Text(verbatim: detail.team.title).font(.headline)
                        Text(verbatim: "#\(detail.team.id)").font(.caption).foregroundStyle(.secondary)
                    }
                    if case .remove(_, let memberID) = review.action, let member = review.detail?.members.first(where: { $0.id == memberID }) {
                        Text(verbatim: member.name).font(.headline)
                    }
                    if case .create(let context, let size, let inviteOnly) = review.action {
                        Text(verbatim: context.title).font(.headline)
                        LabeledContent("team.size") { Text(verbatim: "\(size)") }
                        Text(inviteOnly ? "team.mode.invitation" : "team.mode.public")
                    }
                    Text(LocalizedStringKey(review.action.consequenceKey)).fixedSize(horizontal: false, vertical: true)
                    TeamNotice(coordinator: model.coordinator)
                    Button(LocalizedStringKey(model.coordinator.canSimulate ? "team.simulate" : "team.confirmLive")) {
                        Task { await model.run { await model.coordinator.confirm(review) }; dismiss() }
                    }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                        .disabled(!model.coordinator.canSubmit || model.running)
                        .accessibilityIdentifier("team.review.confirm")
                    if case .disband(let teamID) = review.action {
                        Button("team.leaveInstead") { model.prepare(.leave(teamID: teamID)) }
                            .frame(minHeight: 44).disabled(model.running).accessibilityIdentifier("team.review.leaveInstead")
                    }
                    Button("team.cancel") { model.cancel(); dismiss() }.frame(minHeight: 44).disabled(model.running)
                        .accessibilityIdentifier("team.review.cancel")
                }.padding()
            }.appNavigationTitle("team.review")
                .interactiveDismissDisabled(model.running)
        }
    }
}
struct TeamInvitePreview: View {
    let team: OwnedTeam
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("team.invitation") {
                    Text(verbatim: team.title)
                    if let code = team.inviteCode, TeamLookup.validInvite(code) { Text(verbatim: code).accessibilityIdentifier("team.invite.code") }
                    else { Text("team.invite.unavailable") }
                    Text("team.invite.previewOnly").font(.footnote).foregroundStyle(.secondary)
                }
            }.appNavigationTitle("team.invitePreview")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("team.close") { dismiss() }.accessibilityIdentifier("team.invite.close") } }
        }
    }
}
