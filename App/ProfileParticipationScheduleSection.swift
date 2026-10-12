import SwiftUI

/// Local clock ticks only. This neither starts reads nor enables the blocked participation reader.
struct ProfileParticipationScheduleSection: View {
    private let schedule: ProfileParticipationSchedule
    init(start: String?, end: String?) { schedule = .init(start: start, end: end) }
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { clock in
            ProfileParticipationScheduleContent(presentation: schedule.presentation(now: clock.date))
        }
    }
}
struct ProfileParticipationScheduleContent: View {
    let presentation: ProfileParticipationSchedule.Presentation
    var body: some View {
        if let range = presentation.range {
            Section("profile.participationSchedule.title") {
                if let days = presentation.reminderDays {
                    Label("profile.participationSchedule.soon", systemImage: "clock.badge.exclamationmark")
                        .accessibilityIdentifier("profile.participationSchedule.soon")
                    LabeledContent("profile.participationSchedule.days") {
                        Text(verbatim: String(days)).monospacedDigit()
                            .accessibilityIdentifier("profile.participationSchedule.days")
                    }
                }
                Text(verbatim: range).accessibilityIdentifier("profile.participationSchedule.range")
                Text("profile.participationSchedule.clockNote").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
