import SwiftUI
import MapKit

@MainActor struct WalkingNavigationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: WalkingNavigationCoordinator?
    let reference: WalkingTargetReference
    let factory: NativeWalkingNavigationFactory
    var offline = false
    var onOpenVerification: (() -> Void)? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("walking.foregroundOnly").font(.footnote).foregroundStyle(.secondary)
                if let model {
                    Text(LocalizedStringKey(status(model.phase))).font(.headline)
                        .accessibilityIdentifier("walking.status")
                    if let target = model.target {
                        Text(verbatim: target.title).font(.title2.bold()).accessibilityIdentifier("walking.destination")
                        if let address = target.address { Text(verbatim: address) }
                        if let businessTime = target.businessTime { LabeledContent("walking.businessTime", value: businessTime) }
                    }
                    if let route = model.route {
                        if offline { Label("walking.offlineFixture", systemImage: "map").accessibilityIdentifier("walking.fixtureMap") }
                        else {
                            Map {
                                MapPolyline(coordinates: route.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                                    .stroke(.blue, lineWidth: 5)
                                if let target = model.target {
                                    Marker(target.title, coordinate: .init(latitude: target.coordinate.point.latitude, longitude: target.coordinate.point.longitude))
                                }
                            }.mapStyle(.standard(pointsOfInterest: .excludingAll)).frame(height: 260)
                        }
                        if let provider = route.provider {
                            Text(verbatim: provider.attribution).font(.caption).accessibilityIdentifier("walking.provider")
                            ForEach(Array(provider.advisoryNotices.enumerated()), id: \.offset) { _, notice in Text(verbatim: notice).font(.footnote) }
                        }
                        LabeledContent("walking.routeDistance") { distance(route.distanceMeters) }
                        if let seconds = route.etaSeconds { LabeledContent("walking.routeETA") { minutes(seconds) } }
                        if let progress = model.progress {
                            ProgressView(value: progress.fraction).accessibilityLabel(Text("walking.progress"))
                            LabeledContent("walking.remaining") { distance(progress.remainingMeters) }
                            if let seconds = progress.remainingSeconds { LabeledContent("walking.remainingETA") { minutes(seconds) } }
                            Text("walking.estimateNotice").font(.caption)
                        }
                        ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top) {
                                Image(systemName: model.progress?.stepIndex == index ? "arrow.turn.up.right" : "circle")
                                Text(verbatim: step.instruction).fixedSize(horizontal: false, vertical: true)
                                Spacer(); distance(step.distanceMeters)
                            }.accessibilityIdentifier("walking.step.\(index)")
                        }
                    }
                    if let accuracy = model.accuracyMeters { LabeledContent("walking.accuracy") { distance(accuracy) } }
                    if model.phase == .nearDestination {
                        Text("walking.arrivalBoundary").accessibilityIdentifier("walking.arrivalBoundary")
                        if let onOpenVerification {
                            Button("walking.openVerification", action: onOpenVerification).buttonStyle(.borderedProminent)
                        }
                    }
                    if mayStart(model.phase) {
                        Button { Task { await model.start() } } label: { Text(LocalizedStringKey(model.phase == .ready ? "walking.start" : "walking.resume")) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("walking.start")
                    }
                    if model.phase != .ready && model.phase != .cancelled {
                        Button("walking.pause") { model.pause() }.buttonStyle(.bordered).accessibilityIdentifier("walking.pause")
                    }
                    Button("walking.cancel") { model.cancel() }.buttonStyle(.bordered).accessibilityIdentifier("walking.cancel")
                } else { Text("walking.error.unavailable").accessibilityIdentifier("walking.unavailable") }
                Text("walking.safety").font(.footnote)
                Text("walking.arrivalBoundary").font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.appNavigationTitle("walking.title")
            .task {
                if model == nil { model = factory.make(reference: reference) }
                while !Task.isCancelled {
                    model?.synchronize()
                    if scenePhase == .active { await model?.update() }
                    do { try await Task.sleep(for: .seconds(3)) } catch { break }
                }
            }
            .onChange(of: scenePhase) { _, value in model?.setForeground(value == .active) }
            .onDisappear { model?.pause() }
    }
    private func distance(_ value: Double) -> some View {
        Text(Measurement(value: value, unit: UnitLength.meters), format: .measurement(width: .abbreviated))
    }
    private func minutes(_ value: Double) -> some View {
        Text(max(1, (value / 60).rounded(.up)), format: .number.precision(.fractionLength(0)))
    }
    private func mayStart(_ phase: WalkingNavigationCoordinator.Phase) -> Bool {
        switch phase {
        case .ready, .paused, .cancelled: return true
        case .failed(let failure): return failure != .staleContext
        default: return false
        }
    }
    private func status(_ phase: WalkingNavigationCoordinator.Phase) -> String {
        switch phase {
        case .ready: return "walking.ready"
        case .authorizing: return "walking.authorizing"
        case .locating: return "walking.locating"
        case .routing: return "walking.routing"
        case .navigating: return "walking.navigating"
        case .nearDestination: return "walking.nearDestination"
        case .paused: return "walking.paused"
        case .cancelled: return "walking.cancelled"
        case .failed(let failure): return "walking.error." + failure.rawValue
        }
    }
}
