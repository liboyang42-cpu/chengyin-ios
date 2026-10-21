import SwiftUI

/// Reform plan v9 §20 map-as-entry hub, §12.2 legend and §21 sharing explainer.
/// Presentation only: existing entries call back to the host; pending entries stay disabled.
/// Nothing here requests location permission, reads a fix or calls a sharing endpoint.
struct MapCoreEntryHubView: View {
    let manifest: MapVisualStyleManifest
    let onOpen: (MapCoreEntry) -> Void
    var publicLayers: MapPublicLayerCaller? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsSharingExplainer = false
    init(manifest: MapVisualStyleManifest = .candidate, onOpen: @escaping (MapCoreEntry) -> Void, publicLayers: MapPublicLayerCaller? = nil) {
        self.manifest = manifest; self.onOpen = onOpen; self.publicLayers = publicLayers
    }
    private var appearance: MapAppearance { .resolve(systemIsDark: colorScheme == .dark) }

    var body: some View {
        List {
            Section {
                ForEach(MapCoreEntry.allCases, id: \.self) { entry in
                    Button { onOpen(entry) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label { MapCoreEntryText.title(entry) } icon: { Image(systemName: entry.symbolName) }
                            MapCoreEntryText.availability(entry.availability).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .disabled(entry.availability != .existing)
                    .accessibilityIdentifier("mapCore.entry.\(entry.rawValue)")
                }
            } header: { Text("mapCore.entries.title", tableName: "MapCoreEntry") } footer: { Text("mapCore.entries.footer", tableName: "MapCoreEntry") }
            if let publicLayers {
                Section {
                    NavigationLink { MapPublicLayerCallerView(caller: publicLayers) } label: {
                        Text(verbatim: "Public layers").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("mapPublic.entry")
                }
            }

            Section {
                ForEach(MapMarkerVisualState.allCases, id: \.self) { state in
                    HStack(spacing: 12) {
                        Image(systemName: state.symbolName)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(swatch(for: state), lineWidth: state.strokeWidth))
                            .accessibilityHidden(true)
                        MapCoreEntryText.state(state)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("mapCore.legend.\(state.rawValue)")
                }
            } header: { Text("mapCore.legend.title", tableName: "MapCoreEntry") } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("mapCore.legend.footer", tableName: "MapCoreEntry")
                    if manifest.approval == .candidate {
                        Text("mapCore.legend.candidate", tableName: "MapCoreEntry").accessibilityIdentifier("mapCore.legend.candidate")
                    }
                }
            }

            Section {
                LabeledContent {
                    Text("mapCore.share.off", tableName: "MapCoreEntry")
                } label: { Text("mapCore.share.status", tableName: "MapCoreEntry") }
                .accessibilityIdentifier("mapCore.share.status")
                Text("mapCore.share.permissionIsNotSharing", tableName: "MapCoreEntry").font(.caption)
                Button { showsSharingExplainer = true } label: {
                    Text("mapCore.share.explain", tableName: "MapCoreEntry").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("mapCore.share.explain")
            } header: { Text("mapCore.share.title", tableName: "MapCoreEntry") }
        }
        .navigationTitle(Text("mapCore.title", tableName: "MapCoreEntry"))
        .sheet(isPresented: $showsSharingExplainer) {
            NavigationStack { LocationShareExplainerView() }
        }
    }
    private func swatch(for state: MapMarkerVisualState) -> Color {
        let role: MapSemanticRole = [.completed, .locked, .unavailable].contains(state) ? .completedUnavailable : .currentTargetRoute
        let token = manifest.color(role, appearance)
        return Color(red: token.red, green: token.green, blue: token.blue, opacity: token.opacity)
    }
}

/// Explains every disclosure the future consent needs (W13.5). Start stays disabled while
/// `LocationShareFeature.preciseGrantEnabled` is false; acknowledgements are kept in memory only.
struct LocationShareExplainerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = LocationShareDraft()
    var body: some View {
        Form {
            Section {
                ForEach(LocationShareDisclosure.allCases, id: \.self) { item in
                    Toggle(isOn: Binding(get: { draft.acknowledged.contains(item) }, set: { if $0 { draft.acknowledge(item) } else { draft.withdraw(item) } })) {
                        MapCoreEntryText.disclosure(item)
                    }
                    .accessibilityIdentifier("mapCore.share.disclosure.\(item.rawValue)")
                }
            } footer: { Text("mapCore.share.disclosureFooter", tableName: "MapCoreEntry") }
            Section {
                Button {} label: { Text("mapCore.share.start", tableName: "MapCoreEntry") }
                    .disabled(true)
                    .accessibilityIdentifier("mapCore.share.start")
                Text("mapCore.share.unavailable", tableName: "MapCoreEntry").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("mapCore.share.unavailable")
            }
        }
        .navigationTitle(Text("mapCore.share.title", tableName: "MapCoreEntry"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Text("mapCore.close", tableName: "MapCoreEntry") }.accessibilityIdentifier("mapCore.share.close")
            }
        }
    }
}

/// Literal catalog keys only, so the structural checker can verify every key in the table.
enum MapCoreEntryText {
    static func title(_ entry: MapCoreEntry) -> Text {
        switch entry {
        case .cityOrienteering: Text("mapCore.entry.cityOrienteering", tableName: "MapCoreEntry")
        case .freeExploration: Text("mapCore.entry.freeExploration", tableName: "MapCoreEntry")
        case .merchantSideQuests: Text("mapCore.entry.merchantSideQuests", tableName: "MapCoreEntry")
        case .placeInfo: Text("mapCore.entry.placeInfo", tableName: "MapCoreEntry")
        case .personalFog: Text("mapCore.entry.personalFog", tableName: "MapCoreEntry")
        case .sharedLocation: Text("mapCore.entry.sharedLocation", tableName: "MapCoreEntry")
        case .cityOperation: Text("mapCore.entry.cityOperation", tableName: "MapCoreEntry")
        }
    }
    static func availability(_ value: MapCoreEntry.Availability) -> Text {
        switch value {
        case .existing: Text("mapCore.availability.existing", tableName: "MapCoreEntry")
        case .pendingBackend: Text("mapCore.availability.pendingBackend", tableName: "MapCoreEntry")
        case .pendingDecision: Text("mapCore.availability.pendingDecision", tableName: "MapCoreEntry")
        }
    }
    static func state(_ state: MapMarkerVisualState) -> Text {
        switch state {
        case .standard: Text("mapCore.state.standard", tableName: "MapCoreEntry")
        case .interactive: Text("mapCore.state.interactive", tableName: "MapCoreEntry")
        case .selected: Text("mapCore.state.selected", tableName: "MapCoreEntry")
        case .active: Text("mapCore.state.active", tableName: "MapCoreEntry")
        case .completed: Text("mapCore.state.completed", tableName: "MapCoreEntry")
        case .locked: Text("mapCore.state.locked", tableName: "MapCoreEntry")
        case .unavailable: Text("mapCore.state.unavailable", tableName: "MapCoreEntry")
        case .inReview: Text("mapCore.state.inReview", tableName: "MapCoreEntry")
        }
    }
    static func disclosure(_ item: LocationShareDisclosure) -> Text {
        switch item {
        case .audience: Text("mapCore.disclosure.audience", tableName: "MapCoreEntry")
        case .precision: Text("mapCore.disclosure.precision", tableName: "MapCoreEntry")
        case .duration: Text("mapCore.disclosure.duration", tableName: "MapCoreEntry")
        case .foregroundOnly: Text("mapCore.disclosure.foregroundOnly", tableName: "MapCoreEntry")
        case .stopAnytime: Text("mapCore.disclosure.stopAnytime", tableName: "MapCoreEntry")
        case .alreadySeenCannotBeRecalled: Text("mapCore.disclosure.alreadySeen", tableName: "MapCoreEntry")
        }
    }
}

#if DEBUG
/// Offline fixture: synthetic host callbacks only; no session, reader, location or network.
struct MapCoreEntryFixtureHost: View {
    @State private var opened: MapCoreEntry?
    var body: some View {
        NavigationStack {
            MapCoreEntryHubView { opened = $0 }
                .safeAreaInset(edge: .bottom) {
                    Text(verbatim: opened?.rawValue ?? "none")
                        .font(.caption.monospaced()).padding(8)
                        .accessibilityIdentifier("mapCore.fixture.opened")
                }
        }
    }
}
#endif
