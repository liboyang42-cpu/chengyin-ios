import SwiftUI
import UIKit

@MainActor struct PlayDirectorView: View {
    @Bindable var model: PlayDirectorCoordinator
    @State private var editor: PlayDirectorAction?
    var body: some View {
        List {
            Section {
                LabeledContent("playx.state") { PlayRuntimePhaseText(phase: model.phase) }
                Button("playx.refresh") { Task { await model.load() } }.disabled(model.phase == "submitting")
                if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
                if model.phase == "unknown" {
                    Text("playx.unknown.body")
                    Button("playx.reconcile") { Task { await model.recover() } }
                    Button("playx.retryExact") { Task { await model.retryExact() } }
                }
            }
            if let projection = model.projection {
                Section("playx.director.readiness") {
                    LabeledContent("playx.state") { Text(verbatim: projection.status) }
                    LabeledContent("playx.advanced.version") { Text(verbatim: String(projection.revision)) }
                    let readiness = projection.club["readiness"]
                    if let ready = readiness["readyStations"].integer, let required = readiness["requiredStations"].integer {
                        LabeledContent("playx.director.stationProgress") { Text(verbatim: "\(ready) / \(required)") }
                    } else { Text("playx.director.unknownCounts") }
                    ForEach(Array((readiness["blockers"].array ?? []).enumerated()), id: \.offset) { _, blocker in if let text = blocker.text { Text(verbatim: text) } }
                }
                Section("playx.director.actions") {
                    ForEach(PlayDirectorAction.allCases.filter { projection.availableActions.contains($0.rawValue) }) { action in
                        Button(LocalizedStringKey("playx.director.action." + action.rawValue)) { editor = action }
                            .disabled(model.phase != "ready" || (action == .start && !projection.canStart))
                            .accessibilityIdentifier("playx.director.action.\(action.rawValue)")
                    }
                }
                Section("playx.director.stations") {
                    ForEach(Array(projection.stations.enumerated()), id: \.offset) { _, station in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: station["nodeName"].text ?? station["stationName"].text ?? station["name"].text ?? "—").font(.headline)
                            if let status = station["status"].text { Text(verbatim: status) }
                            if let reason = station["pauseReason"].text ?? station["blockedReason"].text ?? station["issue"].text { Text(verbatim: reason) }
                            if let eta = station["resumeEta"].text { LabeledContent("playx.player.resumeETA") { Text(verbatim: eta) } }
                            if let count = station["pendingVerificationCount"].integer { LabeledContent("playx.director.pendingCount") { Text(verbatim: String(count)) } }
                        }
                    }
                }
                Section("playx.director.teams") {
                    ForEach(Array(projection.teams.enumerated()), id: \.offset) { _, team in
                        VStack(alignment: .leading) {
                            Text(verbatim: team["name"].text ?? team["teamName"].text ?? "—").font(.headline)
                            if let completed = team["completedNodes"].integer, let total = team["totalNodes"].integer { Text(verbatim: "\(completed) / \(total)") }
                            if let stuck = team["blockedReason"].text ?? team["issue"].text { Text(verbatim: stuck) }
                            if let event = team["recentEvent"]["action"].text { Text(verbatim: event).font(.caption) }
                        }
                    }
                }
                Section("playx.director.roles") {
                    ForEach(Array(projection.roles.enumerated()), id: \.offset) { _, role in
                        LabeledContent { Text(verbatim: role["roleName"].text ?? role["roleLabel"].text ?? "—") } label: { Text(verbatim: role["memberName"].text ?? role["name"].text ?? "—") }
                    }
                }
                Section("playx.director.broadcasts") {
                    ForEach(Array((projection.club["broadcasts"].array ?? []).enumerated()), id: \.offset) { _, broadcast in
                        VStack(alignment: .leading) {
                            if let content = broadcast["content"].text { Text(verbatim: content) }
                            if let status = broadcast["receiptStatus"].text ?? broadcast["status"].text { Text(verbatim: status).font(.caption) }
                            if let count = broadcast["recipientCount"].integer { LabeledContent("playx.director.recipients") { Text(verbatim: String(count)) } }
                        }
                    }
                }
                Section("playx.director.submissions") {
                    Text("playx.director.noEvidence").font(.footnote)
                    ForEach(Array(projection.submissions.enumerated()), id: \.offset) { _, submission in
                        VStack(alignment: .leading) {
                            Text(verbatim: submission["nodeName"].text ?? "—")
                            if let status = submission["status"].text { Text(verbatim: status) }
                            if let reason = submission["decisionReason"].text { Text(verbatim: reason) }
                        }
                    }
                }
                Section("playx.director.recap") {
                    if let recap = try? PlayDirectorRecap.normalize(projection.club["recap"]) {
                        if let generated = recap["generatedAt"].text { Text(verbatim: generated) }
                        ForEach(Array((recap["metrics"].array ?? []).enumerated()), id: \.offset) { _, metric in
                            if let label = metric["label"].text, let value = metric["value"].integer {
                                LabeledContent { Text(verbatim: "\(value) \(metric["unit"].text ?? "")") } label: { Text(verbatim: label) }
                            }
                        }
                        if recap["exportAvailable"].bool == true {
                            Button("playx.director.copyRecap") { Task { if let export = await model.exportRecap() { UIPasteboard.general.string = export } } }
                                .disabled(model.phase != "ready").accessibilityIdentifier("playx.director.copyRecap")
                        }
                    } else { Text("playx.director.recapPending") }
                }
            }
        }.privacySensitive().navigationTitle("playx.director.title").accessibilityIdentifier("playx.director.view")
            .task { await model.load() }
            .sheet(item: $editor) { action in
                if let projection = model.projection {
                    NavigationStack { PlayDirectorCommandEditor(projection: projection, action: action) { command in editor = nil; Task { await model.submit(command) } } }
                }
            }
    }
}
@MainActor private struct PlayDirectorCommandEditor: View {
    let projection: PlayDirectorProjection
    let action: PlayDirectorAction
    let submit: (PlayDirectorCommand) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var teamID = 0
    @State private var memberID = 0
    @State private var sourceMemberID = 0
    @State private var roleCode = ""
    @State private var nodeID = 0
    @State private var chapterID = 0
    @State private var submissionID = 0
    @State private var targetType = "ALL"
    @State private var content = ""
    @State private var reason = ""
    @State private var resumeETA = ""
    @State private var planCode = ""
    @State private var visible = false
    @State private var draft: PlayDirectorCommand?
    @State private var confirm = false
    @State private var invalid = false
    var body: some View {
        Form {
            Section {
                Text(LocalizedStringKey("playx.director.action." + action.rawValue)).font(.headline)
                Text("playx.director.commandNotice").font(.footnote)
                if action == .broadcast {
                    Picker("playx.director.target", selection: $targetType) {
                        Text("playx.director.target.all").tag("ALL"); Text("playx.director.target.team").tag("TEAM"); Text("playx.director.target.role").tag("ROLE")
                    }
                    TextField("playx.lead.text", text: $content, axis: .vertical)
                }
                if action == .assign || action == .takeover || (action == .broadcast && targetType == "TEAM") {
                    idPicker("playx.director.team", rows: projection.teams, idKey: "teamId", labelKeys: ["name", "teamName"], selection: $teamID)
                }
                if action == .assign || (action == .broadcast && targetType == "ROLE") {
                    Picker("playx.director.role", selection: $roleCode) {
                        Text("playx.choose").tag("")
                        ForEach(Array(projection.roleOptions.enumerated()), id: \.offset) { _, role in
                            if let code = PlayDirectorProjection.roleCode(role) { Text(verbatim: role["roleName"].text ?? role["label"].text ?? code).tag(code) }
                        }
                    }
                }
                if action == .assign || action == .takeover {
                    let members = projection.roles.filter { $0["teamId"].integer == teamID }
                    if action == .takeover {
                        idPicker("playx.director.sourceMember", rows: members.filter { ($0["confirmationStatus"].text ?? $0["status"].text) == "CONFIRMED" }, idKey: "memberId", labelKeys: ["memberName", "name"], selection: $sourceMemberID)
                    }
                    idPicker("playx.director.member", rows: action == .takeover ? members.filter { (PlayDirectorProjection.roleCode($0) ?? "").isEmpty } : members, idKey: "memberId", labelKeys: ["memberName", "name"], selection: $memberID)
                }
                if action == .pause || action == .resume {
                    idPicker("playx.director.station", rows: projection.stations, idKey: "nodeId", labelKeys: ["nodeName", "stationName", "name"], selection: $nodeID)
                }
                if action == .unlock { idPicker("playx.director.chapter", rows: projection.chapterOptions, idKey: "chapterId", labelKeys: ["title"], selection: $chapterID) }
                if action == .reject { idPicker("playx.director.submission", rows: projection.submissions.filter { $0["status"].text == "PENDING" }, idKey: "submissionId", labelKeys: ["nodeName"], selection: $submissionID) }
                if [.takeover, .unlock, .pause, .reject].contains(action) { TextField("playx.director.reason", text: $reason, axis: .vertical) }
                if action == .pause {
                    TextField("playx.player.resumeETA", text: $resumeETA)
                    Text("playx.director.etaNotice").font(.caption)
                    let plans = projection.stations.first { $0["nodeId"].integer == nodeID }?["fallbackPlanOptions"].array ?? []
                    Picker("playx.director.fallback", selection: $planCode) {
                        Text("playx.director.noFallback").tag("")
                        ForEach(Array(plans.enumerated()), id: \.offset) { _, plan in if let code = plan["planCode"].text { Text(verbatim: code).tag(code) } }
                    }
                }
                if action == .visibility { Toggle("playx.director.showLeaderboard", isOn: $visible) }
            }
            Section {
                if invalid { Text("playx.director.invalid").foregroundStyle(.red) }
                Button("playx.review") { prepare() }.accessibilityIdentifier("playx.director.review")
            }
        }.navigationTitle("playx.director.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("playx.cancel") { dismiss() }.accessibilityIdentifier("playx.director.cancelEditor") } }
            .confirmationDialog("playx.review", isPresented: $confirm, titleVisibility: .visible) {
                Button("playx.submit") { if let draft { submit(draft) } }
            } message: { Text(LocalizedStringKey(action == .finish ? "playx.director.finishNotice" : action == .broadcast ? "playx.director.broadcastNotice" : "playx.director.commandNotice")) }
    }
    private func idPicker(_ key: String, rows: [PlayWireValue], idKey: String, labelKeys: [String], selection: Binding<Int>) -> some View {
        Picker(LocalizedStringKey(key), selection: selection) {
            Text("playx.choose").tag(0)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if let id = row[idKey].integer { Text(verbatim: labelKeys.compactMap { row[$0].text }.first ?? "#\(id)").tag(id) }
            }
        }
    }
    private func prepare() {
        var payload: [String: PlayWireValue] = [:]
        switch action {
        case .prepare, .start, .finish, .resume: break
        case .assign: payload = ["teamId": .int(teamID), "assignments": .array([.object(["memberId": .int(memberID), "roleCode": .string(roleCode)])])]
        case .takeover: payload = ["teamId": .int(teamID), "sourceMemberId": .int(sourceMemberID), "targetMemberId": .int(memberID), "reason": .string(reason)]
        case .broadcast:
            payload = ["targetType": .string(targetType), "content": .string(content)]
            if targetType == "TEAM" { payload["targetId"] = .int(teamID) }
            if targetType == "ROLE" { payload["roleCode"] = .string(roleCode) }
        case .unlock: payload = ["chapterId": .int(chapterID), "reason": .string(reason)]
        case .visibility: payload = ["visible": .bool(visible)]
        case .pause:
            payload = ["reasonCode": .string("ONSITE"), "reason": .string(reason), "resumeEta": .string(resumeETA)]
            if !planCode.isEmpty, let plan = projection.stations.first(where: { $0["nodeId"].integer == nodeID })?["fallbackPlanOptions"].array?.first(where: { $0["planCode"].text == planCode }) {
                payload["fallbackPlanCode"] = .string(planCode); payload["fallbackPlanVersion"] = plan["version"]
            }
        case .reject: payload = ["submissionId": .int(submissionID), "reasonCode": .string("ONSITE_REJECT"), "reason": .string(reason)]
        }
        do {
            let command = try PlayDirectorCommand(activityID: projection.activityID, nodeID: [.pause, .resume].contains(action) ? nodeID : nil,
                expectedRevision: projection.revision, action: action, payload: payload)
            guard projection.allows(command) else { throw PlayExperienceError.invalidAction }; draft = command; confirm = true; invalid = false
        } catch { invalid = true }
    }
}
