#if DEBUG
import SwiftUI

/// Local synthetic schedule only. Production participation reads remain disabled.
struct ProfileParticipationScheduleFixtureHost: View {
    private let schedule: ProfileParticipationSchedule
    @State private var now: Date
    @State private var alternateZone = false
    init(scenario: String = "near") {
        let start: String?, end: String?
        switch scenario {
        case "far": start = "2026-10-15 09:00:00"; end = "2026-10-15 18:00:00"
        case "sameDay": start = "2026-10-11 09:00:00"; end = "2026-10-11 18:00:00"
        case "missing": start = nil; end = "2026-10-13 18:00:00"
        case "reversed": start = "2026-10-13 09:00:00"; end = "2026-10-12 18:00:00"
        default: start = "2026-10-13 09:00:00"; end = "2026-10-13 18:00:00"
        }
        schedule = .init(start: start, end: end)
        _now = State(initialValue: OrderLifecycleTime.date("2026-10-11 00:01:00")!)
    }
    var body: some View {
        NavigationStack {
            List {
                Text("Synthetic local schedule; production participation reads remain blocked.")
                    .accessibilityIdentifier("profile.participationScheduleFixture.notice")
                ProfileParticipationScheduleContent(presentation: schedule.presentation(now: now))
                Button("Advance to exact start") { now = OrderLifecycleTime.date("2026-10-13 09:00:00")! }
                    .accessibilityIdentifier("profile.participationScheduleFixture.advance")
                Button("Change synthetic display zone") { alternateZone.toggle() }
                    .accessibilityIdentifier("profile.participationScheduleFixture.zone")
            }.environment(\.timeZone, TimeZone(identifier: alternateZone ? "America/New_York" : "Pacific/Honolulu")!)
        }
    }
}
#endif
