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
        // Each control is its own List row, so a sibling action cannot consume
        // the selected action's one-shot ticket and no control is stacked in a card.
        Group {
            focusButton(.overview, key: "playRouteCamera.overview", symbol: "map")
            focusButton(.current, key: "playRouteCamera.current", symbol: "scope")
            Menu {
                ForEach(presentation.stops.filter { $0.state != .locked }) { stop in
                    let choice = request(.preview(stop.id))
                    Button { if let choice { onFocus(choice) } } label: { name(stop) }
                        .disabled(choice == nil).accessibilityIdentifier("playRouteCamera.choice.\(stop.id)")
                }
            } label: {
                controlLabel("playRouteCamera.choose", symbol: "mappin.and.ellipse")
            }.disabled(presentation.stops.allSatisfy { $0.state == .locked })
                .accessibilityIdentifier("playRouteCamera.choose")
            if let preview {
                VStack(alignment: .leading, spacing: 4) {
                    Text("playRouteCamera.preview").font(.caption.bold()).foregroundStyle(.secondary)
                    name(preview).font(.headline).accessibilityIdentifier("playRouteCamera.preview.name")
                    Label(LocalizedStringKey(preview.state.labelKey), systemImage: preview.state.symbol).font(.subheadline)
                    if let address = preview.address, !address.isEmpty { Text(verbatim: address).font(.footnote) }
                    if preview.coordinate == nil { Text("playRoute.noStopCoordinate").font(.footnote) }
                    if !preview.canOpen { Text("playRoute.useJourney").font(.footnote) }
                }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .contain)
                if preview.canOpen {
                    Button("playRouteCamera.openTask") { onOpen(preview.id) }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                        .accessibilityIdentifier("playRouteCamera.openTask")
                }
            }
            if let issue {
                Text(LocalizedStringKey(issue.labelKey)).font(.footnote)
                    .accessibilityIdentifier("playRouteCamera.issue")
            }
        }.buttonStyle(.borderless)
    }
    private func focusButton(_ action: PlayRouteMapCamera.Action, key: String, symbol: String) -> some View {
        let choice = request(action)
        return Button { if let choice { onFocus(choice) } } label: {
            controlLabel(key, symbol: symbol)
        }.disabled(choice == nil).accessibilityIdentifier(key)
    }
    /// A native Label wraps at every Dynamic Type size instead of clipping.
    private func controlLabel(_ key: String, symbol: String) -> some View {
        Label(LocalizedStringKey(key), systemImage: symbol)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
    private func name(_ stop: PlayRouteMapPresentation.Stop) -> Text {
        if let name = stop.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Text(verbatim: name) }
        return Text("playRoute.unnamedStop")
    }
}
