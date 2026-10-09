import SwiftUI

/// Read-only metadata, not a template-detail link. The separate myinfo grant is
/// not inherited from seeing an activity's included template list.
struct ActivityAssociatedPlaysSection: View {
    let plays: [ActivityAssociatedPlay]
    var body: some View {
        if !plays.isEmpty {
            Section("activityAssociated.title") {
                // Preserve returned order/repetitions; no ID or inferred schedule
                // is used to merge different associations into one template.
                ForEach(Array(plays.enumerated()), id: \.offset) { index, play in
                    ActivityAssociatedPlayRow(play: play)
                        .questifyCardListRow()
                        .accessibilityIdentifier("activityAssociated.row.\(index)")
                }
                Text("activityAssociated.readOnly").font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.accessibilityIdentifier("activityAssociated.section")
        }
    }
}

struct ActivityAssociatedPlayRow: View {
    let play: ActivityAssociatedPlay
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = play.title { Text(verbatim: title).font(.headline) }
            else { Text("activityAssociated.untitled").font(.headline) }
            LabeledContent("activityAssociated.players") {
                if let players = play.players { Text(verbatim: players) }
                else { Text("activityAssociated.playersUnknown") }
            }
            LabeledContent("activityAssociated.durationMinutes") {
                if let duration = play.durationMinutes { Text(duration, format: .number) }
                else { Text("activityAssociated.durationUnknown") }
            }
        }.fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .questifyCardSurface()
    }
}
