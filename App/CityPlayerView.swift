import SwiftUI
import MapKit

/// Official CITY read surface is separate from manual POI search and has no write controls.
struct SessionCityPlayerView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        CityPlayerView(reader: session.makeCityPlayerReader()).id(session.cityPlayerReadIdentity)
    }
}
struct CityPlayerView: View {
    @State var reader: CityPlayerReader
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
                    Text(snapshot.board.title).font(.title2)
                    Text(lifecycle(snapshot.board.lifecycle))
                    Text(membership(snapshot.membership))
                    if let points = snapshot.points {
                        if points.isEmpty { Text("city.read.points.empty") }
                        else {
                            Map {
                                ForEach(points) { point in
                                    Annotation(point.title, coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)) {
                                        Image(systemName: point.mine ? "flag.fill" : "mappin.circle.fill")
                                            .accessibilityLabel(Text(point.title))
                                    }
                                }
                            }
                            .mapStyle(QuestifyMapAppearance.baseStyle)
                            .frame(height: 280)
                            ForEach(points) { point in
                                HStack { Text(point.title); Spacer(); if point.mine { Text("city.read.point.mine") } }
                            }
                        }
                    } else { Text("city.read.points.unavailable") }
                }
                if reader.isConfigured { Button("action.retry") { Task { await reader.load() } } }
            }.padding()
        }
        .appNavigationTitle("city.read.title")
        .accessibilityIdentifier("city.read.screen")
        .task { await reader.load() }
        .onDisappear { reader.cancel() }
    }
    private func membership(_ status: CityMembership) -> LocalizedStringKey {
        switch status { case .joined: return "city.read.joined"; case .notJoined: return "city.read.notJoined"; case .unavailable: return "city.read.participation.unavailable" }
    }
    private func lifecycle(_ value: String) -> LocalizedStringKey {
        switch value { case "OPEN": return "city.read.open"; case "FROZEN": return "city.read.frozen"; default: return "city.read.closed" }
    }
}
