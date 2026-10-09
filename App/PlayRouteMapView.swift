import SwiftUI
import MapKit

/// Supplementary map for the personal orientation runtime. It never requests
/// location, directions or a new capability; all actions use the existing node host.
@MainActor struct PlayRouteMapView: View {
    @Bindable var model: PlayExperienceCoordinator
    let nodeDestination: (Int) -> AnyView
    @State private var selected: PlayRouteMapDestination?
    @State private var showMap = true
    @State private var cameraControlsExpanded = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var cameraGate = PlayRouteMapCamera.Gate()
    @State private var cameraPreview: PlayRouteMapCamera.Preview?
    @State private var cameraIssue: PlayRouteMapCamera.CameraIssue?
    #if DEBUG
    @State private var cameraWitness = "none"
    #endif
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let context = model.interactionContext
        List {
            if !model.unresolved, let context, let snapshot = model.snapshot,
               let presentation = PlayRouteMapPresentation(snapshot: snapshot) {
                Section {
                    Text("playRoute.explanation").font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("playRoute.explanation")
                    if let id = presentation.currentNodeID,
                       let current = presentation.stops.first(where: { $0.id == id }) {
                        Label("playRoute.current", systemImage: "flag.fill").font(.headline)
                        stopName(current)
                        Button("playRoute.openCurrent") { choose(id, snapshot: snapshot, context: context) }
                            .accessibilityIdentifier("playRoute.openCurrent")
                    } else { Text("playRoute.noCurrent").accessibilityIdentifier("playRoute.noCurrent") }
                }
                Section {
                    Button(cameraControlsExpanded ? LocalizedStringKey("playRouteCamera.hideControls") : LocalizedStringKey("playRouteCamera.showControls")) { cameraControlsExpanded.toggle() }
                        .frame(minHeight: 44).accessibilityIdentifier("playRouteCamera.controls")
                    if cameraControlsExpanded { cameraControls(presentation, snapshot: snapshot, context: context) }
                }
                if !presentation.mappedStops.isEmpty {
                    Section("playRoute.map") {
                        Button(showMap ? LocalizedStringKey("playRoute.hideMap") : LocalizedStringKey("playRoute.showMap")) { showMap.toggle() }
                            .frame(minHeight: 44).accessibilityIdentifier("playRoute.toggleMap")
                        if showMap {
                            map(presentation, snapshot: snapshot, context: context)
                                .frame(height: typeSize.isAccessibilitySize ? 240 : 320)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                } else {
                    Section { Text("playRoute.noCoordinates").accessibilityIdentifier("playRoute.noCoordinates") }
                }
                Section("playRoute.list") {
                    if presentation.stops.isEmpty { Text("playRoute.empty").accessibilityIdentifier("playRoute.empty") }
                    ForEach(presentation.stops) { stop in
                        if stop.canOpen {
                            Button { choose(stop.id, snapshot: snapshot, context: context) } label: { stopLabel(stop) }
                                .accessibilityIdentifier("playRoute.stop.\(stop.id)")
                                .accessibilityHint(Text("playRoute.openHint"))
                        } else {
                            stopLabel(stop).accessibilityElement(children: .combine)
                                .accessibilityIdentifier("playRoute.stop.\(stop.id)")
                        }
                    }
                }
            } else {
                Section {
                    Text("playRoute.unavailable").accessibilityIdentifier("playRoute.unavailable")
                    if model.phase == .loading { ProgressView("playx.loading") }
                }
            }
            Section {
                Button("playx.refresh") { selected = nil; Task { await model.load() } }
                    .disabled(!model.available || model.phase == .loading || model.phase == .submitting)
                    .accessibilityIdentifier("playRoute.refresh")
                Button("playRoute.back") { selected = nil; dismiss() }
                    .accessibilityIdentifier("playRoute.back")
            }
        }
        .privacySensitive().appNavigationTitle(key: "playRoute.title")
        .navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("playRoute.screen")
        .navigationDestination(item: $selected) { choice in
            let nodeID = choice.nodeID(in: model)
            Group {
                if let nodeID {
                    nodeDestination(nodeID)
                } else { Text("playRoute.unavailable").accessibilityIdentifier("playRoute.selectionUnavailable") }
            }
            // The map is covered while its task is pushed. Observe retirement on
            // the visible destination too, including a read retired before mount.
            .onChange(of: nodeID, initial: true) { _, _ in
                choice.retireSelectionIfNeeded(&selected, in: model)
            }
        }
        .onChange(of: context) { _, _ in clearRetiredSelection() }
        .onChange(of: model.snapshot) { _, _ in clearRetiredSelection() }
        .onChange(of: model.phase) { _, _ in clearRetiredSelection() }
        .onChange(of: cameraRead) { _, _ in resetCamera() }
        .onAppear { cameraGate.appear() }
        .onDisappear { cameraGate.disappear(); cameraPreview = nil; cameraIssue = nil }
    }
    private var cameraRead: PlayRouteMapCamera.Read? {
        guard !model.unresolved else { return nil }
        return .init(snapshot: model.snapshot, context: model.interactionContext)
    }
    private func resetCamera() {
        cameraGate.invalidate(); cameraPreview = nil; cameraIssue = nil; cameraPosition = .automatic
        #if DEBUG
        cameraWitness = "none"
        #endif
    }
    private func cameraControls(_ presentation: PlayRouteMapPresentation, snapshot: PlaySnapshot, context: PlayInteractionContext) -> some View {
        let read = PlayRouteMapCamera.Read(snapshot: snapshot, context: context)
        let renderedGate = cameraGate
        return PlayRouteMapCameraControls(presentation: presentation,
            preview: cameraPreview?.resolve(current: cameraRead), issue: cameraRead == read ? cameraIssue : nil,
            request: { renderedGate.request($0, read: read) }, onFocus: focus,
            onOpen: { choose($0, snapshot: snapshot, context: context) })
    }
    private func focus(_ request: PlayRouteMapCamera.Gate.Request) {
        guard let decision = cameraGate.consume(request, current: cameraRead) else { return }
        cameraControlsExpanded = true
        cameraPreview = decision.preview; cameraIssue = decision.issue
        if let fit = decision.fit {
            cameraPosition = .region(.init(center: .init(latitude: fit.latitude, longitude: fit.longitude),
                span: .init(latitudeDelta: fit.latitudeSpan, longitudeDelta: fit.longitudeSpan)))
            showMap = true
        }
        #if DEBUG
        let action: String
        switch decision.action {
        case .overview: action = "overview"
        case .current: action = "current"
        case .preview(let id): action = "preview:\(id)"
        }
        cameraWitness = action + (decision.fit == nil ? ";camera=unchanged" : ";camera=fitted")
        #endif
    }
    private func clearRetiredSelection() {
        if let selected, selected.nodeID(in: model) == nil { self.selected = nil }
    }
    private func choose(_ id: Int, snapshot: PlaySnapshot, context: PlayInteractionContext) {
        guard !model.unresolved, model.interactionContext == context, model.snapshot == snapshot,
              let choice = PlayRouteMapDestination(nodeID: id, model: model),
              choice.nodeID(in: model) != nil else { return }
        selected = choice
    }
    private func map(_ presentation: PlayRouteMapPresentation, snapshot: PlaySnapshot, context: PlayInteractionContext) -> some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            ForEach(presentation.segments) { segment in
                MapPolyline(coordinates: [coordinate(segment.start), coordinate(segment.end)])
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
            }
            ForEach(presentation.mappedStops) { stop in
                if let location = stop.coordinate {
                    Annotation("", coordinate: coordinate(location)) {
                        let request = cameraGate.request(.preview(stop.id), read: .init(snapshot: snapshot, context: context))
                        let inspecting = cameraPreview?.resolve(current: cameraRead)?.id == stop.id
                        Button { if let request { focus(request) } } label: {
                            VStack(spacing: 3) {
                                Image(systemName: stop.state.symbol).font(.title2)
                                Text(verbatim: String(stop.order)).font(.caption.bold())
                            }.foregroundStyle(stop.state == .current ? Color.white : Color.primary)
                                .frame(minWidth: 44, minHeight: 44)
                                .padding(4).background(stop.state == .current ? Color.accentColor : Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(inspecting ? Color.primary : Color.clear, lineWidth: 2))
                        }.buttonStyle(.plain).disabled(request == nil)
                            .accessibilityLabel(stopName(stop) + Text(verbatim: ", ") + Text(LocalizedStringKey(stop.state.labelKey)))
                            .accessibilityIdentifier("playRoute.pin.\(stop.id)")
                            .accessibilityAddTraits(inspecting ? .isSelected : [])
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .accessibilityIdentifier("playRoute.map")
        #if DEBUG
        .accessibilityValue(Text(verbatim: cameraWitness))
        #endif
        .id(context.lifetimeIdentity)
    }
    private func coordinate(_ value: PlayRouteMapPresentation.Coordinate) -> CLLocationCoordinate2D {
        .init(latitude: value.latitude, longitude: value.longitude)
    }
    private func stopName(_ stop: PlayRouteMapPresentation.Stop) -> Text {
        if stop.state == .locked { return Text("playRoute.lockedStop") }
        if let name = stop.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Text(verbatim: name) }
        return Text("playRoute.unnamedStop")
    }
    private func stopLabel(_ stop: PlayRouteMapPresentation.Stop) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            stopName(stop).font(.headline)
            Label(LocalizedStringKey(stop.state.labelKey), systemImage: stop.state.symbol).font(.subheadline)
            if let address = stop.address, !address.isEmpty { Text(verbatim: address).font(.footnote) }
            if stop.state != .locked && stop.coordinate == nil { Text("playRoute.noStopCoordinate").font(.footnote).foregroundStyle(.secondary) }
            if stop.state == .available || stop.state == .unknown { Text("playRoute.useJourney").font(.footnote).foregroundStyle(.secondary) }
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 4)
    }
}

/// The existing task temporarily withdraws command context during review/submission.
/// Preserve its already-open presentation through those phases, without granting
/// any command authority. A new read, owner, scope or mode still retires the page.
struct PlayRouteMapDestination: Hashable, Identifiable {
    let id: UUID
    private let choice: PlayRouteMapSelection
    private let owner: PlayExperiencePresentationKey
    private let coordinator: PlayExperienceCoordinator
    private let snapshot: PlaySnapshot
    private let openedNodeID: Int
    @MainActor init?(nodeID: Int, model: PlayExperienceCoordinator) {
        guard !model.unresolved, let snapshot = model.snapshot,
              let choice = PlayRouteMapSelection(nodeID: nodeID, snapshot: snapshot, context: model.interactionContext) else { return nil }
        id = choice.id; self.choice = choice; coordinator = model; owner = PlayExperiencePresentationKey(model: model)
        self.snapshot = snapshot; openedNodeID = nodeID
    }
    @MainActor func nodeID(in model: PlayExperienceCoordinator) -> Int? {
        guard coordinator === model, owner == PlayExperiencePresentationKey(model: model), model.snapshot == snapshot else { return nil }
        if model.phase == .reviewing || model.phase == .submitting { return openedNodeID }
        guard !model.unresolved else { return nil }
        return choice.resolve(snapshot: model.snapshot, context: model.interactionContext)
    }
    @MainActor func retireSelectionIfNeeded(_ selected: inout Self?, in model: PlayExperienceCoordinator) {
        // A queued callback from a disappearing destination cannot pop a newer
        // selection, even when both destinations open the same node ID.
        guard selected?.id == id, nodeID(in: model) == nil else { return }
        selected = nil
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
