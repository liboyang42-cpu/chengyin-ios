import SwiftUI

@MainActor struct SearchRoutePreviewView: View {
    @Environment(\.walkingNavigationFactory) private var walkingFactory
    let origin: RoamCoordinate
    let destination: RoamCoordinate
    let name: String
    let scope: UUID
    var navigationReference: WalkingTargetReference? = nil
    var offline = false
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var planner: (any SearchRoutePlanning)? = nil
    @State private var activePlanner: (any SearchRoutePlanning)?
    @State private var route: SearchRoutePreview?
    @State private var failed = false
    @State private var gate = SearchMapQueryGate()
    private var request: SearchRouteRequest { SearchRouteRequest(origin: origin, destination: destination, mode: .walking) }
    private struct LoadIdentity: Hashable {
        let request: SearchRouteRequest
        let scope: UUID
        let reference: WalkingTargetReference?
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(verbatim: name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                PlatformExternalMapHost(destination: .init(name: name, latitude: destination.latitude, longitude: destination.longitude), scope: scope, makeModel: makeExternalMaps)
                Text("searchMap.routeOriginDisclosure").font(.footnote).foregroundStyle(.secondary)
                Text("searchMap.mode.walking").font(.headline)
                if let navigationReference, let walkingFactory, walkingFactory.available {
                    NavigationLink {
                        WalkingNavigationView(reference: navigationReference, factory: walkingFactory, offline: offline)
                    } label: { Label("walking.title", systemImage: "figure.walk") }
                        .accessibilityIdentifier("walking.open")
                }
                if let route {
                    SearchMapCanvas(area: RoamSearchArea(coordinate: origin, label: ""),
                        pins: [SearchMapPin(id: "destination", title: name, coordinate: destination, symbol: "mappin")],
                        polyline: route.coordinates, offline: offline)
                    Text("searchMap.roadRoute").font(.headline)
                        .accessibilityIdentifier("searchMap.route.kind")
                    LabeledContent("searchMap.distance") { Text(Measurement(value: route.distanceMeters, unit: UnitLength.meters), format: .measurement(width: .abbreviated)) }
                    if let eta = route.etaSeconds { LabeledContent("searchMap.etaMinutes") { Text(max(1, (eta / 60).rounded()), format: .number.precision(.fractionLength(0))) } }
                    ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top) {
                            Text(verbatim: "\(index + 1)")
                            Text(verbatim: step.instruction).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text(Measurement(value: step.distanceMeters, unit: UnitLength.meters), format: .measurement(width: .abbreviated))
                        }
                    }
                } else if failed { SearchMapIssue(key: "walking.previewUnavailable") { Task { await load() } } }
                else { ProgressView("searchMap.loading") }
                Text("searchMap.routeBoundary").font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.appNavigationTitle("searchMap.routePreview")
            .task(id: LoadIdentity(request: request, scope: scope, reference: navigationReference)) { await load() }
            .onDisappear { gate.invalidate(); activePlanner?.cancel(); activePlanner = nil; route = nil }
    }
    private func load() async {
        activePlanner?.cancel()
        activePlanner = planner ?? navigationReference.flatMap { walkingFactory?.makePreviewPlanner(reference: $0) }
        let requested = request, reference = navigationReference, ticket = gate.begin(scope: scope)
        route = nil; failed = false
        do {
            let value: SearchRoutePreview
            if let activePlanner { value = try await activePlanner.preview(requested) }
            else { throw WalkingNavigationFailure.unavailable }
            guard !value.isStraightLine else { throw WalkingNavigationFailure.noRoute }
            guard gate.accepts(ticket, scope: scope), request == requested, navigationReference == reference else { return }
            route = value
        } catch {
            guard gate.accepts(ticket, scope: scope), request == requested, navigationReference == reference else { return }
            failed = true
        }
    }
}
