import SwiftUI

/// Official CITY read surface is separate from manual POI search and has no write controls.
struct SessionCityPlayerView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        CityPlayerView(reader: session.makeCityPlayerReader()).id(session.cityPlayerReadIdentity)
    }
}
struct CityPlayerView: View {
    @State var reader: CityPlayerReader
    @State private var selection: CityPointSelection?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch reader.state {
                case .unavailable:
                    ContentUnavailableView("city.read.unavailable", systemImage: "building.2", description: Text("city.read.unavailable.hint"))
                case .loading: ProgressView("city.read.loading")
                case .notPublished:
                    ContentUnavailableView("city.read.notPublished", systemImage: "building.2")
                case .available(let snapshot):
                    Text(verbatim: snapshot.board.title).font(.title2)
                    Text(lifecycle(snapshot.board.lifecycle))
                    Text(membership(snapshot.membership))
                    if let context = reader.pointMapContext {
                        if context.points.isEmpty { Text("city.read.points.empty") }
                        else { pointContent(context) }
                    } else { Text("city.read.points.unavailable") }
                }
                if reader.isConfigured { Button("action.retry") { selection = nil; Task { await reader.load() } } }
            }.padding()
        }
        .appNavigationTitle("city.read.title")
        .accessibilityIdentifier("city.read.screen")
        .task { await reader.load() }
        .onChange(of: reader.pointMapContext) { _, _ in selection = nil }
        .onDisappear { selection = nil; reader.cancel() }
    }
    @ViewBuilder private func pointContent(_ context: CityPointMapContext) -> some View {
        let selected = selection?.point(in: reader.pointMapContext)
        let pins = context.points.compactMap { point -> SearchMapPin? in
            guard let coordinate = RoamCoordinate(latitude: point.latitude, longitude: point.longitude) else { return nil }
            return SearchMapPin(id: point.pointId, title: point.title, coordinate: coordinate, symbol: symbol(point))
        }
        if let first = pins.sorted(by: { $0.id < $1.id }).first {
            let fit = MapMarkerDensity.fit(pins.map { .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) })
            let center = fit.flatMap { RoamCoordinate(latitude: $0.latitude, longitude: $0.longitude) } ?? first.coordinate
            // QuestifyDensityMap uses QuestifyMapAppearance.baseStyle and only the
            // supplied visible points. Camera movement never performs a read.
            QuestifyDensityMap(area: .init(coordinate: center, label: context.snapshot.board.title),
                pins: pins, selectedID: selected?.pointId, mapHeight: 280,
                initialSpan: fit.map { min(180, max($0.latitudeSpan, $0.longitudeSpan)) } ?? 0.04,
                interactionID: context.readID, pinIdentifierPrefix: "city.read.pin.",
                pinHint: { id in
                    if let point = context.points.first(where: { $0.pointId == id }) { return Text(ownStatus(point)) }
                    return Text("")
                }, onSelect: { id in select(id, rendered: context) })
                .id(context.readID)
                .accessibilityIdentifier("city.read.map")
        }
        if let renderedSelection = selection, let point = selected {
            VStack(alignment: .leading, spacing: 8) {
                Text("city.read.point.selected").font(.headline)
                Label {
                    Text(verbatim: point.title).fixedSize(horizontal: false, vertical: true)
                } icon: { Image(systemName: symbol(point)) }
                Text(ownStatus(point)).fixedSize(horizontal: false, vertical: true)
                Text("city.read.point.readOnly").font(.footnote).fixedSize(horizontal: false, vertical: true)
                Button("city.read.point.clear") {
                    guard selection?.id == renderedSelection.id,
                          renderedSelection.point(in: reader.pointMapContext) != nil else { return }
                    selection = nil
                }.frame(minHeight: 44).accessibilityIdentifier("city.read.point.clear")
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("city.read.point.card.\(point.pointId)")
        }
        Text("city.read.points.list").font(.headline)
        ForEach(context.points) { point in
            Button { select(point.pointId, rendered: context) } label: {
                HStack(alignment: .top, spacing: 12) {
                    QuestifyMapPinSymbol(symbol: symbol(point), selected: selected?.pointId == point.pointId)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: point.title).fixedSize(horizontal: false, vertical: true)
                        Text(ownStatus(point)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: point.title) + Text(verbatim: ", ") + Text(ownStatus(point)))
                .accessibilityHint(Text("city.read.point.selectHint"))
                .accessibilityAddTraits(selected?.pointId == point.pointId ? .isSelected : [])
                .accessibilityIdentifier("city.read.point.select.\(point.pointId)")
        }
    }
    private func select(_ id: String, rendered: CityPointMapContext) {
        guard let next = CityPointSelection(pointID: id, rendered: rendered, current: reader.pointMapContext) else { return }
        selection = next
    }
    private func symbol(_ point: CityReadPoint) -> String { point.mine ? "flag.fill" : "mappin.circle.fill" }
    private func ownStatus(_ point: CityReadPoint) -> LocalizedStringKey {
        point.mine ? "city.read.point.mine" : "city.read.point.notMine"
    }
    private func membership(_ status: CityMembership) -> LocalizedStringKey {
        switch status { case .joined: return "city.read.joined"; case .notJoined: return "city.read.notJoined"; case .unavailable: return "city.read.participation.unavailable" }
    }
    private func lifecycle(_ value: String) -> LocalizedStringKey {
        switch value { case "OPEN": return "city.read.open"; case "FROZEN": return "city.read.frozen"; default: return "city.read.closed" }
    }
}
