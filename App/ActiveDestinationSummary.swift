import SwiftUI

/// A presentation-only composition of existing authorized data. It owns no request,
/// location permission, selection, navigation progress, or completion state.
struct ActiveDestinationSummary<Actions: View>: View {
    let phase: WalkingNavigationCoordinator.Phase
    let target: AuthorizedWalkingTarget?
    let route: SearchRoutePreview?
    let progress: WalkingNavigationProgress?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                if phase.isPreparing { ProgressView().accessibilityHidden(true) }
                Text(LocalizedStringKey(phase.statusKey)).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("walking.status")
            }
            if let target {
                Text(verbatim: target.title).font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("walking.destination")
                if let address = target.address { Text(verbatim: address).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            }
            if let route, let progress {
                if let stepIndex = progress.stepIndex, route.steps.indices.contains(stepIndex) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("walking.nextStep").font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: route.steps[stepIndex].instruction)
                            .font(.headline).fixedSize(horizontal: false, vertical: true)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("walking.nextInstruction")
                }
                LabeledContent("walking.remaining") { WalkingDistanceText(meters: progress.remainingMeters) }
                if let seconds = progress.remainingSeconds {
                    LabeledContent("walking.remainingETA") { WalkingDurationText(seconds: seconds) }
                }
                ProgressView(value: progress.fraction).accessibilityLabel(Text("walking.progress"))
                Text("walking.estimateNotice").font(.caption).foregroundStyle(.secondary)
            }
            if phase == .nearDestination {
                Text("walking.arrivalBoundary").font(.footnote)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("walking.arrivalBoundary")
            }
            actions()
            Text("walking.foregroundOnly").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WalkingDistanceText: View {
    let meters: Double
    var body: some View {
        Text(Measurement(value: meters, unit: UnitLength.meters), format: .measurement(width: .abbreviated))
    }
}
struct WalkingDurationText: View {
    let seconds: Double
    var body: some View {
        // Include localized units; a bare number must never stand in for an ETA.
        Text(Duration.seconds(max(60, seconds)), format: .units(allowed: [.minutes], width: .abbreviated))
    }
}
