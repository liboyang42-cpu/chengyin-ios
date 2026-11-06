import SwiftUI

@MainActor struct CityNeutralTaskEntry: View {
    let board: CityReadBoard
    let factory: (@MainActor (CityReadBoard) -> CityNeutralTaskController)?
    var body: some View {
        if let factory {
            NavigationLink { CityNeutralTaskView(controller: factory(board)) } label: {
                Label { Text("cityNeutral.entry", tableName: "CityNeutralTask") } icon: { Image(systemName: "questionmark.circle") }
            }
        } else { Text("cityNeutral.status.disabled", tableName: "CityNeutralTask") }
    }
}
@MainActor struct CityNeutralTaskView: View {
    @State var controller: CityNeutralTaskController
    @State private var selections: [String:String] = [:]
    @State private var originalResult: CityNeutralTaskResultRecoveryController?
    @Environment(\.scenePhase) private var scenePhase
    private let table = "CityNeutralTask"
    var body: some View {
        Form {
            Section {
                Text("cityNeutral.boundary", tableName: table)
                Text(LocalizedStringKey(controller.messageKey), tableName: table).accessibilityIdentifier("cityNeutral.status")
                Button { selections = [:]; Task { await controller.load() } } label: { Text("cityNeutral.reload", tableName: table) }.disabled(controller.busy)
            }
            if controller.current, scenePhase == .active, let value = controller.snapshot {
                if value.status == "JOIN_REQUIRED" { Text("cityNeutral.joinRequired", tableName: table) }
                if value.status == "TEAM_NOT_READY" { Text("cityNeutral.teamNotReady", tableName: table) }
                if let binding = value.binding {
                    Section {
                        Text(verbatim: binding.title)
                        row("cityNeutral.release", binding.rulesReleaseId)
                        row("cityNeutral.round", binding.rules.roundId)
                        if let team = value.teamId { row("cityNeutral.team", team) }
                        if let session = value.sessionId { row("cityNeutral.session", session) }
                        Text("cityNeutral.sharedAttempts", tableName: table)
                    } header: { Text("cityNeutral.frozen", tableName: table) }
                }
                if value.tasks.isEmpty && value.status != "JOIN_REQUIRED" { Text("cityNeutral.noTasks", tableName: table) }
                ForEach(value.tasks) { task in
                    Section {
                        row("cityNeutral.task", task.id)
                        Text(verbatim: task.definition.question)
                        Text(LocalizedStringKey("cityNeutral.taskStatus." + task.status), tableName: table)
                        row("cityNeutral.attempts", "\(task.attempts) / \(task.definition.maxAttempts)")
                        if task.status == "NOT_ACCEPTED" {
                            Button { controller.prepare(task) } label: { Text("cityNeutral.accept", tableName: table) }.disabled(!controller.allows(task))
                        } else if task.status == "ACTIVE" {
                            Picker(selection: Binding(get: { selections[task.id] ?? "" }, set: { selections[task.id] = $0; controller.cancelConfirmation() })) {
                                Text("cityNeutral.chooseOption", tableName: table).tag("")
                                ForEach(task.definition.options) { option in Text(verbatim: option.label).tag(option.id) }
                            } label: { Text("cityNeutral.answer", tableName: table) }
                            .disabled(!controller.allows(task))
                            Button { controller.prepare(task, optionID: selections[task.id]) } label: { Text("cityNeutral.submit", tableName: table) }
                                .disabled(!controller.allows(task) || !task.definition.options.contains(where: { $0.id == selections[task.id] }))
                        }
                        if let result = task.result {
                            row("cityNeutral.result", result.resultId)
                            row("cityNeutral.request", result.requestId)
                            row("cityNeutral.completedAt", result.createdAt)
                            Text("cityNeutral.resultBoundary", tableName: table)
                        }
                    } header: { Text(verbatim: task.definition.title) }
                }
            }
            if controller.current, scenePhase == .active, let id = controller.pendingRequestID {
                Section {
                    row("cityNeutral.request", id.uuidString)
                    Text("cityNeutral.pendingHint", tableName: table)
                    Button { Task { await controller.recover() } } label: { Text("cityNeutral.recover", tableName: table) }.disabled(controller.busy || !controller.current)
                }
            }
            if controller.current, scenePhase == .active, let receipt = controller.receipt {
                Section {
                    row("cityNeutral.request", receipt.requestId)
                    Text(LocalizedStringKey(receipt.succeeded ? "cityNeutral.receiptRecorded" : "cityNeutral.receiptRejected"), tableName: table)
                    if receipt.task != nil {
                        Button { originalResult = controller.makeResultRecoveryController() } label: {
                            Text("cityNeutralResult.open", tableName: "CityNeutralTaskResultRecovery")
                        }.accessibilityIdentifier("cityNeutral.result.open")
                    }
                }
            }
        }
        .navigationTitle(Text("cityNeutral.title", tableName: table))
        .accessibilityIdentifier("cityNeutral.screen")
        .task { await controller.load() }
        .onChange(of: controller.current) { _, current in if !current { controller.invalidate(); selections = [:]; originalResult = nil } }
        .onChange(of: controller.snapshot) { _, _ in selections = [:] }
        .onChange(of: scenePhase) { _, phase in controller.invalidate(); selections = [:]; if phase == .active { Task { await controller.load() } } }
        .onDisappear {
            if originalResult != nil { controller.suspendForResult() } else { controller.invalidate() }
            selections = [:]
        }
        // Keep the destination independent of receipt rows cleared by parent disappearance.
        .navigationDestination(isPresented: Binding(get: { originalResult != nil }, set: { if !$0 { originalResult = nil } })) {
            if let originalResult { CityNeutralTaskResultRecoveryView(controller: originalResult) }
        }
        .sheet(item: Binding(get: { controller.current && scenePhase == .active ? controller.confirmation : nil }, set: { if $0 == nil { controller.cancelConfirmation() } })) { captured in
            NavigationStack {
                Form {
                    Text(LocalizedStringKey(captured.command.kind == .accept ? "cityNeutral.accept" : "cityNeutral.submit"), tableName: table)
                    Text(verbatim: captured.task.definition.title)
                    row("cityNeutral.release", captured.binding.rulesReleaseId)
                    row("cityNeutral.round", captured.binding.rules.roundId)
                    row("cityNeutral.attempts", "\(captured.task.attempts) / \(captured.task.definition.maxAttempts)")
                    if let option = captured.task.definition.options.first(where: { $0.id == captured.command.optionId }) { row("cityNeutral.answer", option.label) }
                    Text("cityNeutral.confirmHint", tableName: table)
                    Button { Task { await controller.confirm(captured) } } label: { Text("cityNeutral.confirmNow", tableName: table) }.disabled(!controller.canWrite)
                    Button { controller.cancelConfirmation() } label: { Text("cityNeutral.cancel", tableName: table) }
                }.navigationTitle(Text("cityNeutral.confirmTitle", tableName: table))
            }
        }
    }
    private func row(_ key: String, _ value: String) -> some View { LabeledContent { Text(verbatim: value).textSelection(.enabled) } label: { Text(LocalizedStringKey(key), tableName: table) } }
}
