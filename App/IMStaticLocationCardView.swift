import SwiftUI
import MapKit

struct IMStaticLocationCardView: View {
    let place: IMStaticLocation
    @State private var showMap=false
    var body: some View {
        VStack(alignment:.leading,spacing:Theme.Space.s2) {
            Label(place.name,systemImage:"mappin.and.ellipse").font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
            if !place.address.isEmpty { Text(verbatim:place.address).fixedSize(horizontal: false, vertical: true) }
            if showMap {
                Map(initialPosition:.region(MKCoordinateRegion(
                    center:CLLocationCoordinate2D(latitude:place.lat,longitude:place.lng),
                    span:MKCoordinateSpan(latitudeDelta:0.01,longitudeDelta:0.01)))) {
                    Marker(place.name,coordinate:CLLocationCoordinate2D(latitude:place.lat,longitude:place.lng))
                }.frame(height:180).allowsHitTesting(false)
            } else {
                // The map service only sees this place once the person asks for the map.
                Button { showMap=true } label: { Label("d7.imLocationCard.showMap", systemImage: "map") }
            }
        }.font(Theme.Font.body).privacySensitive().onDisappear { showMap=false }
    }
}
