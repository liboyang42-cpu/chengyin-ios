import SwiftUI

private struct MapPublicLayerCallerKey: EnvironmentKey {
    static let defaultValue: MapPublicLayerCaller? = nil
}
extension EnvironmentValues {
    var mapPublicLayerCaller: MapPublicLayerCaller? {
        get { self[MapPublicLayerCallerKey.self] }
        set { self[MapPublicLayerCallerKey.self] = newValue }
    }
}

/// Bbox is typed. The caller turns its center into the manual area. No device fix.
@MainActor struct MapPublicLayerCallerView: View {
    @Environment(\.colorScheme) private var colorScheme
    let caller: MapPublicLayerCaller
    @State private var minLat = ""
    @State private var maxLat = ""
    @State private var minLng = ""
    @State private var maxLng = ""
    @State private var layers = "roam_poi,store,activity"
    @State private var limit = "50"

    var body: some View {
        let theme = MapVisualHostBridge.resolveTheme(systemIsDark: colorScheme == .dark)
        let projected = (try? caller.project(theme: theme)) ?? []
        List {
            Section {
                field("mapPublic.minLat", $minLat)
                field("mapPublic.maxLat", $maxLat)
                field("mapPublic.minLng", $minLng)
                field("mapPublic.maxLng", $maxLng)
                field("mapPublic.layers", $layers)
                field("mapPublic.limit", $limit)
                Button { Task { await load() } } label: { Text(verbatim: "Load").frame(minHeight: 44) }
                    .disabled(caller.loading || caller.accountID == nil)
                    .accessibilityIdentifier("mapPublic.load")
                if caller.session?.complete == false {
                    Button { Task { await caller.nextPage() } } label: { Text(verbatim: "Next").frame(minHeight: 44) }
                        .disabled(caller.loading)
                        .accessibilityIdentifier("mapPublic.next")
                }
            }
            if let failure = caller.failure {
                Section { Text(verbatim: failure.rawValue).accessibilityIdentifier("mapPublic.failure") }
            }
            Section {
                ForEach(caller.ready, id: \.key) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: projected.first { $0.key == item.key }?.title ?? item.title)
                        if MapPublicLayerCaller.detail(for: item) != nil {
                            Button { Task { await caller.openDetail(item) } } label: { Text(verbatim: "Detail").frame(minHeight: 44) }
                                .accessibilityIdentifier("mapPublic.detail.\(item.key.type.rawValue).\(item.key.id)")
                        }
                    }
                    .accessibilityIdentifier("mapPublic.row.\(item.key.type.rawValue).\(item.key.id)")
                }
            }
            if let detail = caller.detail {
                Section {
                    Text(verbatim: detail.text).accessibilityIdentifier("mapPublic.detailText")
                    Button { Task { await caller.returned() } } label: { Text(verbatim: "Return").frame(minHeight: 44) }
                        .accessibilityIdentifier("mapPublic.return")
                }
            }
        }
        .onDisappear { caller.abandon() }
    }

    private func field(_ id: String, _ value: Binding<String>) -> some View {
        TextField(text: value) { Text(verbatim: id) }
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier(id)
    }

    private func load() async {
        guard let viewer = caller.accountID, let limit = Int(limit) else { return }
        let names = layers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        await caller.submit(.init(viewerID: viewer, minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng, layers: names, limit: limit))
    }
}
