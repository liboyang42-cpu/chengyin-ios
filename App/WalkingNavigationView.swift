import SwiftUI
import MapKit

@MainActor struct WalkingNavigationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: WalkingNavigationCoordinator?
    @State private var showsSteps = false
    // Explicit controls adjust the camera within one authorized scope. Same-scope
    // refresh preserves manual pan; a privacy boundary discards the old viewport.
    @State private var cameraPosition: MapCameraPosition = WalkingNavigationView.neutralCamera
    @State private var cameraGate = WalkingMapCamera.Gate()
    @State private var retainedCameraScope: WalkingMapCamera.Scope?
    #if DEBUG
    @State private var cameraAction = "none"
    #endif
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
            .dynamicTypeSize(typeSize)
            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            if model == nil { model = factory.make(reference: reference) }
            model?.setForeground(scenePhase == .active)
            while !Task.isCancelled {
                model?.synchronize()
                synchronizeCamera()
                if scenePhase == .active { await model?.update() }
                synchronizeCamera()
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
        .onChange(of: model?.phase) { _, _ in
            if model?.route == nil { showsSteps = false }
        }
        .onChange(of: model?.cameraSnapshot) { _, _ in cameraGate.invalidate() }
        .onChange(of: model?.cameraScope) { _, _ in synchronizeCamera() }
        .onChange(of: scenePhase) { _, value in model?.setForeground(value == .active) }
        .onDisappear { cameraGate.invalidate(); showsSteps = false; model?.pause(); synchronizeCamera() }
    }

    @ViewBuilder private var mapContent: some View {
        if offline {
            if let model, isCameraScopeCurrent(model), model.cameraSnapshot != nil {
                Label("walking.offlineFixture", systemImage: "map")
                    .accessibilityIdentifier("walking.fixtureMap")
                    #if DEBUG
                    .accessibilityValue(Text(verbatim: "cameraAction=\(cameraAction)"))
                    #endif
            } else {
                ContentUnavailableView("walking.mapPending", systemImage: "map", description: Text("walking.safety"))
            }
        } else if let model, isCameraScopeCurrent(model) {
            // A map first appears only after an already-authorized route is supplied.
            // Keep the same map only during authorized same-scope refresh. A lost
            // scope unmounts it immediately, even before the next synchronization tick.
            Map(position: $cameraPosition) {
                if let snapshot = model.cameraSnapshot {
                    let route = snapshot.route
                    let target = snapshot.target
                    MapPolyline(coordinates: route.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(QuestifyMapAppearance.routeCasing, lineWidth: 9)
                    MapPolyline(coordinates: route.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(QuestifyMapAppearance.route, lineWidth: 5)
                    Marker(target.title, coordinate: .init(latitude: target.coordinate.point.latitude, longitude: target.coordinate.point.longitude))
                }
            }.mapStyle(QuestifyMapAppearance.baseStyle)
                .mapControls {
                    MapCompass().mapControlVisibility(.visible)
                    MapScaleView()
                }
                .id(retainedCameraScope?.id)
                .accessibilityIdentifier("walkingCamera.map")
        } else {
            ContentUnavailableView("walking.mapPending", systemImage: "map", description: Text("walking.safety"))
        }
    }

    private static var neutralCamera: MapCameraPosition {
        .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                  span: MKCoordinateSpan(latitudeDelta: 150, longitudeDelta: 360)))
    }
    private func isCameraScopeCurrent(_ model: WalkingNavigationCoordinator) -> Bool {
        guard let current = model.cameraScope else { return false }
        return current.id == retainedCameraScope?.id
    }
    private func synchronizeCamera() {
        model?.synchronizeCameraScope()
        let current = model?.cameraScope
        if current?.id != retainedCameraScope?.id {
            cameraGate.invalidate()
            // This is a privacy reset while the prior map is unmounted, never a
            // recenter of the same authorized map after a refresh or manual pan.
            cameraPosition = Self.neutralCamera
            #if DEBUG
            cameraAction = "none"
            #endif
        }
        retainedCameraScope = current
    }

    private func cameraControl(_ model: WalkingNavigationCoordinator, action: WalkingMapCamera.Action) -> some View {
        let request = cameraGate.request(action, snapshot: model.cameraSnapshot)
        let key = action == .route ? "walkingCamera.showRoute" : "walkingCamera.showTarget"
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                // Query the live coordinator at action time, even before a scope-change
                // render arrives. Old buttons cannot focus a revoked or replaced route.
                guard isCameraScopeCurrent(model) else { synchronizeCamera(); return }
                guard let request, let fit = cameraGate.consume(request, current: model.cameraSnapshot) else {
                    synchronizeCamera(); return
                }
                cameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: fit.latitude, longitude: fit.longitude),
                    span: MKCoordinateSpan(latitudeDelta: fit.latitudeSpan, longitudeDelta: fit.longitudeSpan)))
                #if DEBUG
                cameraAction = action == .route ? "route" : "target"
                #endif
            } label: {
                Label(LocalizedStringKey(key), systemImage: action == .route ? "point.topleft.down.to.point.bottomright.curvepath" : "scope")
                    .fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(.bordered).frame(minHeight: 44)
                .disabled(request == nil)
                .accessibilityHint(Text("walkingCamera.focusHint"))
                .accessibilityIdentifier(key)
            if request == nil {
                Text("walkingCamera.unavailable").font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func actions(_ model: WalkingNavigationCoordinator) -> some View {
        if isCameraScopeCurrent(model), model.cameraSnapshot != nil {
            cameraControl(model, action: .route)
            cameraControl(model, action: .target)
        }
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
    @Environment(\.dynamicTypeSize) private var typeSize
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
            #if DEBUG
            .accessibilityValue(Text(verbatim: typeSize == .accessibility5 ? "dynamicTypeSize=accessibility5" : "dynamicTypeSize=other"))
            #endif
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
