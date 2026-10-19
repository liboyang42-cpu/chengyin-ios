import SwiftUI

/// Source mycanyu/mycanyuinfo presentation pieces. Display only; no reads or writes start here.
struct ParticipationStatusBadge: View {
    let status: ParticipationStatus
    let detail: Bool
    var body: some View {
        ParticipationTag(key: status.labelKey, tone: status.tone(detail: detail))
            .accessibilityIdentifier("playerJourney.status")
    }
}

struct ParticipationTag: View {
    let key: String
    let tone: ParticipationStatus.Tone
    private var color: Color {
        switch tone {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }
    var body: some View {
        Text(LocalizedStringKey(key)).font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Header card: name, 距离路线开始还剩N天 (1–3 Shanghai calendar days) or the full date range,
/// mode and status badges, then the description.
struct ParticipationDetailHeader: View {
    let detail: ParticipationDetail
    var body: some View {
        let record = detail.record
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    if let name = record.name { Text(verbatim: name).font(.headline) }
                    else { Text("playerJourney.parity.unknownTopic").font(.headline) }
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: Date(), by: 60)) { clock in
                        ParticipationScheduleBadge(presentation: ProfileParticipationSchedule(
                            start: record.order.ownerStartDate, end: record.order.ownerEndDate).presentation(now: clock.date))
                    }
                }
                HStack(spacing: 6) {
                    ParticipationTag(key: record.modeKey, tone: record.isFreeExplore ? .success : .info)
                        .accessibilityIdentifier("playerJourney.mode")
                    ParticipationStatusBadge(status: record.participationStatus(), detail: true)
                }
                if let description = detail.description {
                    Text(verbatim: description).font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 4)
        }
    }
}

struct ParticipationScheduleBadge: View {
    let presentation: ProfileParticipationSchedule.Presentation
    var body: some View {
        if let days = presentation.reminderDays {
            Text("playerJourney.parity.countdown \(days)").font(.caption.bold()).foregroundStyle(.red)
                .accessibilityIdentifier("playerJourney.countdown")
        } else if let range = presentation.range {
            Text(verbatim: range).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .accessibilityIdentifier("playerJourney.dateRange")
        }
    }
}

struct ParticipationIssueView: View {
    let issue: ParticipationLoadIssue
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(issue.titleKey)).font(.headline).accessibilityIdentifier("playerJourney.issue")
            if issue.kind == .failed {
                if let message = issue.serverMessage { Text(verbatim: message) }
                else { Text(LocalizedStringKey(issue.fallbackKey)) }
            }
            Button("action.retry", action: retry)
        }
    }
}
