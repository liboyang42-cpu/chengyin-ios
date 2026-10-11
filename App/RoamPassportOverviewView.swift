import SwiftUI

/// Same-page P005 passport header. Existing Hub links below remain the only history/album routes.
@MainActor struct RoamPassportOverviewView: View {
    let phase: RoamPassportOverviewState.Phase
    let retry: () -> Void
    var body: some View {
        Section("roam.passport.title") {
            switch phase {
            case .unloaded:
                ProgressView("roam.loading").accessibilityIdentifier("roam.passport.loading")
            case .failed(let error):
                RoamExperienceIssue(error: error, retry: retry)
                    .accessibilityIdentifier("roam.passport.error")
            case .loaded(let summary):
                LabeledContent("roam.experience.trips", value: String(summary.trips))
                    .accessibilityIdentifier("roam.passport.trips")
                LabeledContent("roam.passport.shopVisits") {
                    if let shops = summary.knownShopVisits { Text(shops, format: .number) }
                    else { Text("roam.passport.unknown") }
                }.accessibilityIdentifier("roam.passport.shops")
                LabeledContent("roam.passport.activeDays") {
                    if let days = summary.activeDays { Text(days, format: .number) }
                    else { Text("roam.passport.unknown") }
                }.accessibilityIdentifier("roam.passport.days")
                LabeledContent("roam.experience.knownDistance") {
                    if let distance = summary.knownKilometers {
                        Text(distance, format: .number.precision(.fractionLength(1))) + Text(verbatim: " km")
                    } else { Text("roam.passport.unknown") }
                }.accessibilityIdentifier("roam.passport.distance")
                if summary.trips == 0 {
                    Text("roam.experience.historyEmpty").foregroundStyle(.secondary)
                        .accessibilityIdentifier("roam.passport.empty")
                } else if summary.hasPartialMetrics {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("roam.passport.partial")
                        LabeledContent("roam.passport.distanceCoverage", value: "\(summary.tripsWithDistance)/\(summary.trips)")
                        LabeledContent("roam.passport.shopsCoverage", value: "\(summary.tripsWithShops)/\(summary.trips)")
                        LabeledContent("roam.passport.dateCoverage", value: "\(summary.tripsWithDate)/\(summary.trips)")
                    }.font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("roam.passport.partial")
                }
                Text("roam.passport.localOnly").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("roam.passport.counting").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityIdentifier("roam.passport.overview")
    }
}
