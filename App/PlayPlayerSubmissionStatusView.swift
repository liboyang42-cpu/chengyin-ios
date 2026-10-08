import SwiftUI

/// Matches the mini-program's inline “本站任务” submission readback. Only a
/// pending record displays its verification number; evidence-only is distinct.
struct PlayPlayerSubmissionStatusView: View {
    let state: PlayPlayerSubmissionState
    var body: some View {
        Group {
            switch state {
            case .none: EmptyView()
            case .unconfirmed:
                Text("playerSubmission.unconfirmed").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("playerSubmission.unconfirmed")
            case .record(let record):
                VStack(alignment: .leading, spacing: 8) {
                    Label(LocalizedStringKey(record.status.titleKey), systemImage: symbol(record.status))
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("playerSubmission.status." + record.status.rawValue.lowercased())
                    if record.status == .pending {
                        LabeledContent("playerSubmission.number", value: String(record.submissionID))
                            .font(.footnote).accessibilityIdentifier("playerSubmission.number")
                    }
                    if record.status == .rejected, let reason = record.rejectionReason {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("playerSubmission.reason").font(.caption)
                            Text(verbatim: reason).font(.footnote)
                        }.accessibilityIdentifier("playerSubmission.reason")
                    }
                    if record.status == .recorded {
                        Text("playerSubmission.recordedNotice").font(.footnote).foregroundStyle(.secondary)
                    }
                }.fixedSize(horizontal: false, vertical: true)
            }
        }.privacySensitive().accessibilityElement(children: .contain)
            .accessibilityIdentifier("playerSubmission.readback")
    }
    private func symbol(_ status: PlayPlayerSubmissionRecord.Status) -> String {
        switch status {
        case .pending: return "clock"
        case .approved: return "checkmark.circle"
        case .rejected: return "exclamationmark.bubble"
        case .recorded: return "doc.text"
        }
    }
}
