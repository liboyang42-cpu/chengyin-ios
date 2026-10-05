import SwiftUI

@MainActor struct PlayAdvancedTeamControls: View {
    @Bindable var model: PlayAdvancedCoordinator
    let surfaceID: UUID
    @State private var review: PlayAdvancedTeamReview?
    @State private var reviewIssue = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
        VStack(alignment: .leading, spacing: 16) {
            if let team = model.teamProjection {
                LabeledContent("advancedTeam.progress") { Text("\(team.completedUnits) / \(team.requiredTurns)").monospacedDigit() }
                LabeledContent("advancedTeam.turnIndex") { Text(verbatim: String(team.turnIndex + 1)) }
                LabeledContent("advancedTeam.myRole") {
                    if let role = team.myRole { Text(verbatim: team.roleLabel(role)) }
                    else { Text("advancedTeam.unassigned") }
                }
                Text(team.assignment == "AUTO" ? "advancedTeam.auto" : team.isLeader ? "advancedTeam.leader" : "advancedTeam.leaderOnly").font(.footnote)
                ForEach(team.members) { member in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: member.name).font(.headline)
                        if team.isLeader {
                            if let role = member.roleID { Text(verbatim: team.roleLabel(role)) }
                            else { Text("advancedTeam.unassigned") }
                        }
                        if team.isLeader && team.assignment == "LEADER" {
                            ForEach(team.roles) { role in
                                Button { prepare(.assign(memberID: member.id, roleID: role.id)) } label: {
                                    Text(verbatim: role.label)
                                }.disabled(!model.canTeamInteract || !team.canAssign(memberID: member.id, roleID: role.id))
                                    .accessibilityIdentifier("advancedTeam.assign.\(member.id).\(role.id)")
                            }
                        }
                    }
                }
                if team.completedUnits >= team.requiredTurns { Text("advancedTeam.turnsRecorded") }
                else {
                    Button("advancedTeam.complete") { prepare(.completeUnit) }
                        .buttonStyle(.borderedProminent).disabled(!model.canTeamInteract || !team.canRequestUnit)
                        .accessibilityIdentifier("advancedTeam.complete")
                }
                Text("advancedTeam.serverTurn").font(.footnote)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let state = model.state, let remaining = state.remainingSeconds(nowMilliseconds: Int64(context.date.timeIntervalSince1970 * 1000)), remaining == 0 {
                        Text("advancedTeam.expired").accessibilityIdentifier("advancedTeam.expired")
                    }
                }
            } else { Text("advancedTeam.unavailable") }
            if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
            if reviewIssue { Text("advancedTeam.reviewChanged").accessibilityIdentifier("advancedTeam.reviewChanged") }
        }
        }.accessibilityIdentifier("advancedTeam.controls")
        .sheet(item: $review) { captured in
            NavigationStack {
                Form {
                    Section("advancedTeam.review") {
                        if let member = captured.memberName { LabeledContent("advancedTeam.member", value: member) }
                        if let role = captured.roleLabel { LabeledContent("advancedTeam.role", value: role) }
                        Text(captured.action == .completeUnit ? "advancedTeam.complete" : "advancedTeam.assign")
                        Text("advancedTeam.serverTurn")
                        LabeledContent("playkit.version") { Text(verbatim: String(captured.version)) }
                        Button("playkit.confirm") {
                            review = nil
                            Task { await model.submitTeamReview(captured) }
                        }.disabled(!model.canTeamInteract || model.state?.version != captured.version)
                            .accessibilityIdentifier("advancedTeam.confirm")
                    }
                }.navigationTitle("advancedTeam.review")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("playkit.cancel") { review = nil } } }
            }.privacySensitive()
        }
        .onChange(of: model.state?.version) { _, _ in review = nil }
        .onChange(of: model.isCurrent) { _, current in if !current { review = nil } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { review = nil } }
        .onDisappear { review = nil }
    }
    private func prepare(_ action: PlayAdvancedTeamReview.Action) {
        do { review = try model.reviewTeamAction(action, surfaceID: surfaceID); reviewIssue = false }
        catch { review = nil; reviewIssue = true }
    }
}

@MainActor struct PlayAdvancedLeaderboardView: View {
    @Bindable var model: PlayAdvancedCoordinator
    let surfaceID: UUID
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let metric = model.leaderboardMetric {
                Text(metric == .elapsed ? "advancedBoard.elapsed" : metric == .units ? "advancedBoard.units" : "advancedBoard.score").font(.headline)
                Text("advancedBoard.scope").font(.footnote)
                if model.leaderboardPhase == "loading" { ProgressView("advancedBoard.loading") }
                else if model.leaderboardPhase == "failed" { Text("advancedBoard.failed").accessibilityIdentifier("advancedBoard.failed") }
                else if model.leaderboardPhase == "ready" && model.leaderboard.isEmpty { Text("advancedBoard.empty").accessibilityIdentifier("advancedBoard.empty") }
                ForEach(Array(model.leaderboard.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(verbatim: String(row["rank"].integer ?? 0)).monospacedDigit()
                        Text(verbatim: row["displayName"].text ?? "")
                        Spacer()
                        if metric == .elapsed {
                            Text("\(row["elapsedSeconds"].integer ?? 0) s").monospacedDigit()
                        } else { Text(verbatim: String(row[metric == .units ? "completedUnits" : "score"].integer ?? 0)).monospacedDigit() }
                    }
                }
                Button("playx.refresh") { Task { await model.loadAdvancedLeaderboard(surfaceID: surfaceID) } }
                    .disabled(model.leaderboardPhase == "loading")
                    .accessibilityIdentifier("advancedBoard.refresh")
            } else { Text("advancedBoard.unavailable") }
        }.privacySensitive().accessibilityIdentifier("advancedBoard.view")
    }
}


/// Inline stories must expose the same shared mechanics, including combinations
/// with no standalone PlayKit kind. Distinct identity fences fallback navigation.
@MainActor struct PlayAdvancedInlineTeamHost: View {
    @Bindable var model: PlayAdvancedCoordinator
    @State private var surfaceID = UUID()
    @State private var surfaceVisible = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.state?.isMultiplayer == true {
                GroupBox("playx.advanced.roles") { PlayAdvancedTeamControls(model: model, surfaceID: surfaceID) }
            }
            if model.state?.config["leaderboard"]["enabled"].bool == true {
                GroupBox("advancedBoard.title") { PlayAdvancedLeaderboardView(model: model, surfaceID: surfaceID) }
            }
        }.accessibilityIdentifier("advancedTeam.inlineHost")
        .onAppear { surfaceVisible = true; model.beginTeamSurface(id: surfaceID) }
        .task(id: model.state?.version) { await model.loadAdvancedLeaderboard(surfaceID: surfaceID) }
        .onDisappear { surfaceVisible = false; model.endTeamSurface(id: surfaceID) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.endTeamSurface(id: surfaceID) }
            else if phase == .active && surfaceVisible { model.beginTeamSurface(id: surfaceID); Task { await model.loadAdvancedLeaderboard(surfaceID: surfaceID) } }
        }
    }
}
