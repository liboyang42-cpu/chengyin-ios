import SwiftUI
import MapKit

@MainActor struct WalkingNavigationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: WalkingNavigationCoordinator?
    @State private var showsSteps = false
    @AccessibilityFocusState private var stepsFocused: Bool
    let reference: WalkingTargetReference
    let factory: NativeWalkingNavigationFactory
    var offline = false
    var onOpenVerification: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            mapContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // This reduces the map's safe area; it never paints over Apple attribution.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ScrollView {
                        if let model {
                            ActiveDestinationSummary(phase: model.phase, target: model.target, route: model.route, progress: model.progress) {
                                actions(model)
                            }
                        } else {
                            ContentUnavailableView("walking.error.unavailable", systemImage: "figure.walk")
                                .accessibilityIdentifier("walking.unavailable")
                        }
                    }
                    .frame(maxHeight: geometry.size.height * (typeSize.isAccessibilitySize ? 0.72 : 0.54))
                    .background(.regularMaterial)
                    .accessibilityIdentifier("walking.summary")
                }
        }
        .appNavigationTitle("walking.title")
        .sheet(isPresented: $showsSteps, onDismiss: { stepsFocused = model?.route != nil }) {
            NavigationStack {
                if let model { WalkingStepsDetail(model: model) }
            }
            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            if model == nil { model = factory.make(reference: reference) }
            model?.setForeground(scenePhase == .active)
            while !Task.isCancelled {
                model?.synchronize()
                if scenePhase == .active { await model?.update() }
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
        .onChange(of: model?.phase) { _, _ in
            if model?.route == nil { showsSteps = false }
        }
        .onChange(of: scenePhase) { _, value in model?.setForeground(value == .active) }
        .onDisappear { showsSteps = false; model?.pause() }
    }

    @ViewBuilder private var mapContent: some View {
        if let route = model?.route {
            if offline {
                Label("walking.offlineFixture", systemImage: "map")
                    .accessibilityIdentifier("walking.fixtureMap")
            } else {
                Map {
                    MapPolyline(coordinates: route.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(.blue, lineWidth: 5)
                    if let target = model?.target {
                        Marker(target.title, coordinate: .init(latitude: target.coordinate.point.latitude, longitude: target.coordinate.point.longitude))
                    }
                }.mapStyle(.standard(pointsOfInterest: .excludingAll))
            }
        } else {
            ContentUnavailableView("walking.mapPending", systemImage: "map", description: Text("walking.safety"))
        }
    }

    @ViewBuilder private func actions(_ model: WalkingNavigationCoordinator) -> some View {
        if model.route != nil {
            Button("walking.steps") { showsSteps = true }
                .buttonStyle(.bordered).frame(minHeight: 44)
                .accessibilityIdentifier("walking.steps.open").accessibilityFocused($stepsFocused)
        }
        if model.phase == .nearDestination, let onOpenVerification {
            Button("walking.openVerification", action: onOpenVerification)
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
        }
        if model.phase.mayStart {
            Button { Task { await model.start() } } label: {
                Text(LocalizedStringKey(model.phase == .ready ? "walking.start" : "walking.resume"))
            }.buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("walking.start")
        }
        if model.phase.mayPause {
            Button("walking.pause") { model.pause() }
                .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("walking.pause")
        }
        Button("walking.cancel") { model.cancel() }
            .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("walking.cancel")
    }
}

/// Reads the live coordinator instead of retaining a route snapshot after invalidation.
@MainActor private struct WalkingStepsDetail: View {
    @Environment(\.dismiss) private var dismiss
    let model: WalkingNavigationCoordinator
    #if DEBUG
    @Environment(\.walkingFixtureScopeExpiry) private var expireFixtureScope
    #endif
    var body: some View {
        List {
            if let route = model.route {
                Section("walking.destinationDetails") {
                    if let target = model.target {
                        Text(verbatim: target.title).font(.headline)
                        if let address = target.address { Text(verbatim: address) }
                        if let businessTime = target.businessTime { LabeledContent("walking.businessTime", value: businessTime) }
                    }
                    LabeledContent("walking.routeDistance") { WalkingDistanceText(meters: route.distanceMeters) }
                    if let seconds = route.etaSeconds { LabeledContent("walking.routeETA") { WalkingDurationText(seconds: seconds) } }
                    if let accuracy = model.accuracyMeters { LabeledContent("walking.accuracy") { WalkingDistanceText(meters: accuracy) } }
                }
                Section("walking.steps") {
                    ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                        VStack(alignment: .leading, spacing: 6) {
                            if model.progress?.stepIndex == index { Label("walking.nextStep", systemImage: "arrow.turn.up.right").font(.caption) }
                            Text(verbatim: step.instruction).fixedSize(horizontal: false, vertical: true)
                            WalkingDistanceText(meters: step.distanceMeters).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("walking.step.\(index)")
                    }
                }
                if let provider = route.provider {
                    Section("walking.providerDetails") {
                        Text(verbatim: provider.attribution).accessibilityIdentifier("walking.provider")
                        ForEach(Array(provider.advisoryNotices.enumerated()), id: \.offset) { _, notice in Text(verbatim: notice) }
                    }
                }
            }
            Section {
                Text("walking.safety")
                Text("walking.arrivalBoundary")
                Text("walking.foregroundOnly")
            }.font(.footnote)
        }.accessibilityIdentifier("walking.steps.list")
            .appNavigationTitle("walking.steps")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("walking.closeSteps") { dismiss() }.accessibilityIdentifier("walking.steps.close")
                }
                #if DEBUG
                if let expireFixtureScope {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Expire synthetic scope", action: expireFixtureScope)
                            .accessibilityIdentifier("walking.fixture.expireScope")
                    }
                }
                #endif
            }
    }
}
