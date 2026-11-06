import SwiftUI

/// Recovery remains reachable without the generic current-run snapshot. No submit/retry action.
@MainActor struct CityOrientationOriginalRecoveryView: View {
    @Bindable var model: CityOrientationOriginalRecoveryHost
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("cityOriginalRecovery.title").font(.headline)
            if let receipt=model.visibleReceipt {
                Text(LocalizedStringKey(receipt.succeeded ? "cityOriginalRecovery.applied" : "cityOriginalRecovery.failed"))
                if let message=receipt.message { Text(verbatim: message) }
            } else {
                switch model.phase {
                case .loading: ProgressView("cityOriginalRecovery.loading")
                case .approvalRequired: Text("cityOriginalRecovery.approval")
                case .unknown: Text("cityOriginalRecovery.unknown")
                case .unavailable: Text("cityOriginalRecovery.storage")
                case .settled: Text("cityOriginalRecovery.settled")
                default: Text("cityOriginalRecovery.unavailable")
                }
            }
            if let issue=model.issue { PlayExperienceIssueView(issue:issue) }
            if model.current && model.phase != .loading && model.phase != .settled {
                Button("cityOriginalRecovery.read") { Task { await model.load() } }
            }
            if model.canAcknowledge {
                Button("cityOriginalRecovery.acknowledge") { try? model.acknowledge() }
            }
        }
        .padding().privacySensitive().accessibilityIdentifier("cityOriginalRecovery")
        .task { await model.load() }
        .onDisappear { model.invalidate() }
    }
}
