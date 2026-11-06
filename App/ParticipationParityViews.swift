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
        Text(LocalizedStringKey(key)).font(.caption.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Header card: name, 距离路线开始还剩N天 (1–3 Shanghai calendar days) or the full date range,
/// mode and status badges, then the description.
struct ParticipationDetailHeader: View {
    let detail: ParticipationDetail
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let record = detail.record
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                (typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.s2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Space.s3))) {
                    Group {
                        if let name = record.name { Text(verbatim: name) }
                        else { Text("playerJourney.parity.unknownTopic") }
                    }
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    TimelineView(.periodic(from: Date(), by: 60)) { clock in
                        ParticipationScheduleBadge(presentation: ProfileParticipationSchedule(
                            start: record.order.ownerStartDate, end: record.order.ownerEndDate).presentation(now: clock.date))
                    }
                }
                (typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.s2))
                    : AnyLayout(HStackLayout(spacing: Theme.Space.s2))) {
                    ParticipationTag(key: record.modeKey, tone: record.isFreeExplore ? .success : .info)
                        .accessibilityIdentifier("playerJourney.mode")
                    ParticipationStatusBadge(status: record.participationStatus(), detail: true)
                }
                if let description = detail.description {
                    Text(verbatim: description).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.vertical, 4)
        }
    }
}

struct ParticipationScheduleBadge: View {
    let presentation: ProfileParticipationSchedule.Presentation
    var body: some View {
        if let days = presentation.reminderDays {
            Text("playerJourney.parity.countdown \(days)").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("playerJourney.countdown")
        } else if let range = presentation.range {
            Text(verbatim: range).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("playerJourney.dateRange")
        }
    }
}

struct ParticipationIssueView: View {
    let issue: ParticipationLoadIssue
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Label(LocalizedStringKey(issue.titleKey), systemImage: issue.kind == .signIn ? "lock" : "exclamationmark.circle")
                .font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("playerJourney.issue")
            if issue.kind == .failed {
                if let message = issue.serverMessage { Text(verbatim: message) }
                else { Text(LocalizedStringKey(issue.fallbackKey)) }
            }
            Button("action.retry", action: retry)
                .modifier(G01JourneyActionStyle())
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, Theme.Space.s3)
    }
}
