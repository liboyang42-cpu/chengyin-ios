import SwiftUI

/// Only the still-owned original create has a retry action. Editing/deleting an
/// uncertain result keeps the existing read-only inspection path.
struct ParticipantOriginalCreateRetrySection: View {
    @ObservedObject var model: ParticipantFormModel
    @Environment(\.scenePhase) private var scenePhase
    let onRecovered: () -> Void
    var body: some View {
        if let original = model.originalCreateRetry, model.ownsOriginalCreateRetry {
            Section {
                Text("participant.recovery.hint", tableName: "ProfileParticipantRecovery")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent { Text(verbatim: original.fullName) } label: { Text("participant.recovery.name", tableName: "ProfileParticipantRecovery") }
                LabeledContent { Text(verbatim: original.maskedPhone) } label: { Text("participant.recovery.phone", tableName: "ProfileParticipantRecovery") }
                LabeledContent { Text(verbatim: String(original.requestID.uuidString.prefix(8))) } label: { Text("participant.recovery.request", tableName: "ProfileParticipantRecovery") }
                Button {
                    guard scenePhase == .active else { return }
                    Task { if await model.retryOriginalCreate() { onRecovered() } }
                } label: { Text("participant.recovery.retry", tableName: "ProfileParticipantRecovery") }
                .disabled(scenePhase != .active || !model.canRetryOriginalCreate)
                .accessibilityIdentifier("participant.form.retryOriginalCreate")
                Text("participant.recovery.retention", tableName: "ProfileParticipantRecovery")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("participant.recovery.title", tableName: "ProfileParticipantRecovery") }
            .privacySensitive()
        }
    }
}
