import SwiftUI

@MainActor struct CityOnsiteTaskEntry: View {
    let board: CityReadBoard
    let factory: (@MainActor (CityReadBoard) -> CityOnsiteTaskController)?
    let arrivalFactory: (@MainActor (CityReadBoard) -> CityArrivalEvidenceController)?
    var body: some View {
        if let factory {
            NavigationLink { CityOnsiteTaskView(controller: factory(board), board: board, arrivalFactory: arrivalFactory) } label: {
                Label { Text("cityOnsite.entry", tableName: "CityOnsiteTask") } icon: { Image(systemName: "questionmark.circle") }
            }
        } else { Text("cityOnsite.status.disabled", tableName: "CityOnsiteTask") }
    }
}
@MainActor struct CityOnsiteTaskView: View {
    @State var controller: CityOnsiteTaskController
    let board: CityReadBoard
    let arrivalFactory: (@MainActor (CityReadBoard) -> CityArrivalEvidenceController)?
    @State private var selections: [String:String] = [:]
    @State private var visible = false
    @State private var readRequest = UUID()
    @Environment(\.scenePhase) private var scenePhase
    private let table = "CityOnsiteTask"
    private var interactive: Bool { visible && scenePhase == .active && controller.current }
    var body: some View {
        Form {
            Section {
                Text("cityOnsite.boundary", tableName: table)
                Text(LocalizedStringKey(controller.messageKey), tableName: table).accessibilityIdentifier("cityOnsite.status")
                Button { guard interactive else { return }; selections = [:]; readRequest = UUID() } label: { Text("cityOnsite.reload", tableName: table) }.disabled(controller.busy || !interactive)
            }
            Section {
                Text("cityOnsite.evidenceEntryHint", tableName: table)
                CityArrivalEvidenceEntry(board: board, factory: arrivalFactory)
            }
            if interactive, let value = controller.snapshot {
                if value.status == "JOIN_REQUIRED" { Text("cityOnsite.joinRequired", tableName: table) }
                if value.status == "TEAM_NOT_READY" { Text("cityOnsite.teamNotReady", tableName: table) }
                if let binding = value.binding {
                    Section {
                        Text(verbatim: binding.title)
                        row("cityOnsite.release", binding.rulesReleaseId)
                        row("cityOnsite.round", binding.rules.roundId)
                        if let team = value.teamId { row("cityOnsite.team", team) }
                        if let session = value.sessionId { row("cityOnsite.session", session) }
                        Text("cityOnsite.sharedAttempts", tableName: table)
                    } header: { Text("cityOnsite.frozen", tableName: table) }
                }
                if value.tasks.isEmpty && value.status != "JOIN_REQUIRED" { Text("cityOnsite.noTasks", tableName: table) }
                ForEach(value.tasks) { task in
                    Section {
                        row("cityOnsite.task", task.id)
                        row("cityOnsite.point", task.definition.pointId)
                        row("cityOnsite.acceptanceReason", task.definition.acceptanceReason)
                        Text(LocalizedStringKey(task.canAct ? "cityOnsite.eligible" : "cityOnsite.ineligible"), tableName: table)
                        if let evidence = task.evidence {
                            row("cityOnsite.evidence", evidence.evidenceId)
                            row("cityOnsite.evidenceExpires", evidence.expiresAt)
                        }
                        Text("cityOnsite.evidenceBoundary", tableName: table)
                        Text(verbatim: task.definition.question)
                        Text(LocalizedStringKey("cityOnsite.taskStatus." + task.status), tableName: table)
                        row("cityOnsite.attempts", "\(task.attempts) / \(task.definition.maxAttempts)")
                        if task.status == "NOT_ACCEPTED" {
                            Button { guard interactive else { return }; controller.prepare(task) } label: { Text("cityOnsite.accept", tableName: table) }.disabled(!controller.allows(task))
                        } else if task.status == "ACTIVE" {
                            Picker(selection: Binding(get: { selections[task.id] ?? "" }, set: { selections[task.id] = $0; controller.cancelConfirmation() })) {
                                Text("cityOnsite.chooseOption", tableName: table).tag("")
                                ForEach(task.definition.options) { option in Text(verbatim: option.label).tag(option.id) }
                            } label: { Text("cityOnsite.answer", tableName: table) }
                            .disabled(!controller.allows(task))
                            Button { guard interactive else { return }; controller.prepare(task, optionID: selections[task.id]) } label: { Text("cityOnsite.submit", tableName: table) }
                                .disabled(!controller.allows(task) || !task.definition.options.contains(where: { $0.id == selections[task.id] }))
                        }
                        if let result = task.result {
                            row("cityOnsite.result", result.resultId)
                            row("cityOnsite.request", result.requestId)
                            row("cityOnsite.completedAt", result.createdAt)
                            Text("cityOnsite.resultBoundary", tableName: table)
                            Button { readResult(result.resultId) } label: { Text("cityOnsite.readResult", tableName: table) }.disabled(controller.busy || !interactive)
                        }
                    } header: { Text(verbatim: task.definition.title) }
                }
            }
            if interactive, let result = controller.selectedResult {
                Section {
                    row("cityOnsite.result", result.resultId); row("cityOnsite.task", result.taskId)
                    row("cityOnsite.request", result.requestId); row("cityOnsite.acceptRequest", result.acceptRequestId)
                    row("cityOnsite.subject", String(result.memberId)); row("cityOnsite.point", result.pointId)
                    row("cityOnsite.merchant", String(result.merchantId)); row("cityOnsite.place", String(result.placeId))
                    row("cityOnsite.release", result.rulesReleaseId); row("cityOnsite.round", result.roundId)
                    row("cityOnsite.evidence", result.evidenceId); row("cityOnsite.evidenceChecked", result.evidenceCheckedAt)
                    row("cityOnsite.evidenceExpires", result.evidenceExpiresAt); row("cityOnsite.completedAt", result.createdAt)
                    Text(LocalizedStringKey("cityOnsite.taskStatus." + result.outcome), tableName: table)
                    Text("cityOnsite.historicalResultBoundary", tableName: table)
                    Button { controller.closeResult() } label: { Text("cityOnsite.closeResult", tableName: table) }.disabled(controller.busy)
                } header: { Text("cityOnsite.originalResult", tableName: table) }
            }
            if interactive, let id = controller.originalRequestID {
                Section {
                    row("cityOnsite.request", id.uuidString)
                    Text(LocalizedStringKey(controller.pendingRequestID == nil ? "cityOnsite.originalRequestHint" : "cityOnsite.pendingHint"), tableName: table)
                    Button { recoverOriginal() } label: { Text("cityOnsite.recover", tableName: table) }.disabled(controller.busy || !interactive)
                }
            }
            if interactive, let receipt = controller.receipt {
                Section {
                    row("cityOnsite.request", receipt.requestId)
                    Text(LocalizedStringKey(receipt.succeeded ? "cityOnsite.receiptRecorded" : "cityOnsite.receiptRejected"), tableName: table)
                    if let code = receipt.errorCode { row("cityOnsite.rejectionCode", code) }
                    if let result = receipt.result { Button { readResult(result.resultId) } label: { Text("cityOnsite.readResult", tableName: table) }.disabled(controller.busy || !interactive) }
                }
            }
        }
        .navigationTitle(Text("cityOnsite.title", tableName: table))
        .accessibilityIdentifier("cityOnsite.screen")
        .task(id: readRequest) {
            guard visible, scenePhase == .active, !Task.isCancelled else { return }
            await controller.load(activity: controller.activityID)
        }
        .onAppear { visible = true; controller.activate(); readRequest = UUID() }
        .onChange(of: controller.snapshot) { _, _ in selections = [:] }
        .onChange(of: scenePhase) { _, phase in
            controller.suspend(); selections = [:]
            if visible, phase == .active { controller.activate(); readRequest = UUID() }
        }
        .onChange(of: controller.current) { _, current in if !current { controller.invalidate(); selections = [:] } }
        .onDisappear { visible = false; controller.suspend(); selections = [:] }
        .sheet(item: Binding(get: { interactive ? controller.confirmation : nil }, set: { if $0 == nil { controller.cancelConfirmation() } })) { captured in
            NavigationStack {
                Form {
                    Text(LocalizedStringKey(captured.command.kind == .accept ? "cityOnsite.accept" : "cityOnsite.submit"), tableName: table)
                    Text(verbatim: captured.task.definition.title)
                    row("cityOnsite.release", captured.binding.rulesReleaseId)
                    row("cityOnsite.round", captured.binding.rules.roundId)
                    row("cityOnsite.attempts", "\(captured.task.attempts) / \(captured.task.definition.maxAttempts)")
                    if let option = captured.task.definition.options.first(where: { $0.id == captured.command.optionId }) { row("cityOnsite.answer", option.label) }
                    row("cityOnsite.evidence", captured.command.evidenceId)
                    if let evidence = captured.task.evidence { row("cityOnsite.evidenceExpires", evidence.expiresAt) }
                    row("cityOnsite.acceptanceReason", captured.task.definition.acceptanceReason)
                    Text("cityOnsite.confirmHint", tableName: table)
                    Button { guard interactive else { return }; Task { await controller.confirm(captured) } } label: { Text("cityOnsite.confirmNow", tableName: table) }.disabled(!interactive || !controller.canWrite)
                    Button { controller.cancelConfirmation() } label: { Text("cityOnsite.cancel", tableName: table) }
                }.navigationTitle(Text("cityOnsite.confirmTitle", tableName: table))
            }
        }
    }
    private func recoverOriginal() {
        guard interactive else { return }; let activity = controller.activityID
        Task { await controller.recover(activity: activity) }
    }
    private func readResult(_ id: String) {
        guard interactive else { return }; let activity = controller.activityID
        Task { await controller.readResult(id, activity: activity) }
    }
    private func row(_ key: String, _ value: String) -> some View { LabeledContent { Text(verbatim: value).textSelection(.enabled) } label: { Text(LocalizedStringKey(key), tableName: table) } }
}
