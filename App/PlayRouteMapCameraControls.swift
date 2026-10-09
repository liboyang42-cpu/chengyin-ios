import SwiftUI

/// Plain controls remain usable without map tiles and at accessibility text sizes.
/// All menu choices come from the same safe projection as the map and stop list.
struct PlayRouteMapCameraControls: View {
    let presentation: PlayRouteMapPresentation
    let preview: PlayRouteMapPresentation.Stop?
    let issue: PlayRouteMapCamera.CameraIssue?
    let request: (PlayRouteMapCamera.Action) -> PlayRouteMapCamera.Gate.Request?
    let onFocus: (PlayRouteMapCamera.Gate.Request) -> Void
    let onOpen: (Int) -> Void
    var body: some View {
        // These controls share one List row. Keep each tap independent so a
        // sibling action cannot consume the selected action's one-shot ticket.
        VStack(alignment: .leading, spacing: 12) {
            Text("playRouteCamera.title").font(.headline).accessibilityAddTraits(.isHeader)
            Text("playRouteCamera.notice").font(.footnote).fixedSize(horizontal: false, vertical: true)
            focusButton(.overview, key: "playRouteCamera.overview", symbol: "map")
            focusButton(.current, key: "playRouteCamera.current", symbol: "scope")
            Menu {
                ForEach(presentation.stops.filter { $0.state != .locked }) { stop in
                    let choice = request(.preview(stop.id))
                    Button { if let choice { onFocus(choice) } } label: { name(stop) }
                        .disabled(choice == nil).accessibilityIdentifier("playRouteCamera.choice.\(stop.id)")
                }
            } label: {
                Label("playRouteCamera.choose", systemImage: "mappin.and.ellipse")
                    .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading)
            }.disabled(presentation.stops.allSatisfy { $0.state == .locked })
                .accessibilityIdentifier("playRouteCamera.choose")
            if let preview {
                VStack(alignment: .leading, spacing: 8) {
                    Text("playRouteCamera.preview").font(.caption.bold())
                    name(preview).font(.headline).accessibilityIdentifier("playRouteCamera.preview.name")
                    Label(LocalizedStringKey(preview.state.labelKey), systemImage: preview.state.symbol)
                    if let address = preview.address, !address.isEmpty { Text(verbatim: address).font(.footnote) }
                    if preview.coordinate == nil { Text("playRoute.noStopCoordinate").font(.footnote) }
                    if preview.canOpen {
                        Button("playRouteCamera.openTask") { onOpen(preview.id) }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                            .accessibilityIdentifier("playRouteCamera.openTask")
                    } else { Text("playRoute.useJourney").font(.footnote) }
                }.fixedSize(horizontal: false, vertical: true)
            }
            if let issue {
                Text(LocalizedStringKey(issue.labelKey)).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("playRouteCamera.issue")
            }
        }.buttonStyle(.borderless)
    }
    private func focusButton(_ action: PlayRouteMapCamera.Action, key: String, symbol: String) -> some View {
        let choice = request(action)
        return Button { if let choice { onFocus(choice) } } label: {
            Label(LocalizedStringKey(key), systemImage: symbol)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading)
        }.disabled(choice == nil).accessibilityIdentifier(key)
    }
    private func name(_ stop: PlayRouteMapPresentation.Stop) -> Text {
        if let name = stop.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Text(verbatim: name) }
        return Text("playRoute.unnamedStop")
    }
}
