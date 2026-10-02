import SwiftUI

@MainActor struct SearchRoutePreviewView: View {
    let origin: RoamCoordinate
    let destination: RoamCoordinate
    let name: String
    let scope: UUID
    var offline = false
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var planner: (any SearchRoutePlanning)? = nil
    @State private var mode = SearchRouteMode.walking
    @State private var route: SearchRoutePreview?
    @State private var failed = false
    @State private var gate = SearchMapQueryGate()
    private var request: SearchRouteRequest { SearchRouteRequest(origin: origin, destination: destination, mode: mode) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(verbatim: name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                PlatformExternalMapHost(destination: .init(name: name, latitude: destination.latitude, longitude: destination.longitude), scope: scope, makeModel: makeExternalMaps)
                Text("searchMap.routeOriginDisclosure").font(.footnote).foregroundStyle(.secondary)
                Picker("searchMap.routeMode", selection: $mode) {
                    ForEach(SearchRouteMode.allCases, id: \.self) { Text(LocalizedStringKey("searchMap.mode." + $0.rawValue)).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("searchMap.route.mode")
                if let route {
                    SearchMapCanvas(area: RoamSearchArea(coordinate: origin, label: ""),
                        pins: [SearchMapPin(id: "destination", title: name, coordinate: destination, symbol: "mappin")],
                        polyline: route.coordinates, offline: offline)
                    Text(LocalizedStringKey(route.isStraightLine ? "searchMap.straightLine" : "searchMap.roadRoute")).font(.headline)
                        .accessibilityIdentifier("searchMap.route.kind")
                    LabeledContent("searchMap.distance") { Text(Measurement(value: route.distanceMeters, unit: UnitLength.meters), format: .measurement(width: .abbreviated)) }
                    if let eta = route.etaSeconds { LabeledContent("searchMap.etaMinutes") { Text(max(1, (eta / 60).rounded()), format: .number.precision(.fractionLength(0))) } }
                    if route.isStraightLine { Text("searchMap.straightLineNotice").font(.footnote).accessibilityIdentifier("searchMap.route.fallback") }
                    if mode == .transit { Text("searchMap.transitNotice").font(.footnote) }
                    ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top) {
                            Text(verbatim: "\(index + 1)")
                            Text(verbatim: step.instruction).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text(Measurement(value: step.distanceMeters, unit: UnitLength.meters), format: .measurement(width: .abbreviated))
                        }
                    }
                } else if failed { SearchMapIssue(key: "searchMap.routeFailed") { Task { await load() } } }
                else { ProgressView("searchMap.loading") }
                Text("searchMap.routeBoundary").font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.appNavigationTitle("searchMap.routePreview")
            .task(id: request) { await load() }
            .onDisappear { gate.invalidate() }
    }
    private func load() async {
        let requested = request, ticket = gate.begin(scope: scope)
        route = nil; failed = false
        do {
            let value: SearchRoutePreview
            if let planner { value = try await planner.preview(requested) }
            else { value = .straightLine(requested) }
            guard gate.accepts(ticket, scope: scope), request == requested else { return }
            route = value
        } catch {
            guard gate.accepts(ticket, scope: scope), request == requested else { return }
            failed = true
        }
    }
}
