import SwiftUI

@MainActor struct CityNeutralTaskResultRecoveryView: View {
    @State var controller: CityNeutralTaskResultRecoveryController
    @Environment(\.scenePhase) private var scenePhase
    private let table = "CityNeutralTaskResultRecovery"
    var body: some View {
        Form {
            Section {
                Text(LocalizedStringKey(controller.messageKey), tableName: table)
                if controller.current, scenePhase == .active { row("cityNeutralResult.request", controller.requestID.uuidString) }
                Text("cityNeutralResult.boundary", tableName: table)
                Button { Task { await controller.load() } } label: {
                    Text("cityNeutralResult.refresh", tableName: table)
                }.disabled(controller.busy || !controller.current)
            }
            if controller.current, scenePhase == .active, let task = controller.task {
                Section {
                    Text(verbatim: task.definition.title)
                    row("cityNeutralResult.task", task.id)
                    if let instance = task.instanceId { row("cityNeutralResult.instance", instance) }
                    Text(LocalizedStringKey("cityNeutralResult.status." + task.status), tableName: table)
                    row("cityNeutralResult.attempts", "\(task.attempts) / \(task.definition.maxAttempts)")
                    Text("cityNeutralResult.zeroEffects", tableName: table)
                    if let result = task.result {
                        row("cityNeutralResult.result", result.resultId)
                        row("cityNeutralResult.completedAt", result.createdAt)
                    }
                }
            }
        }
        .navigationTitle(Text("cityNeutralResult.title", tableName: table))
        .accessibilityIdentifier("cityNeutral.result.screen")
        .task { await controller.load() }
        .onDisappear { controller.invalidate() }
        .onChange(of: controller.current) { _, current in if !current { controller.invalidate() } }
        .onChange(of: scenePhase) { _, phase in
            controller.invalidate()
            if phase == .active { Task { await controller.load() } }
        }
    }
    private func row(_ key: String, _ value: String) -> some View {
        LabeledContent { Text(verbatim: value).textSelection(.enabled) } label: { Text(LocalizedStringKey(key), tableName: table) }
    }
}
