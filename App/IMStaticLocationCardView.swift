import SwiftUI
import MapKit

struct IMStaticLocationCardView: View {
    let place: IMStaticLocation
    @State private var showMap=false
    var body: some View {
        VStack(alignment:.leading,spacing:Theme.Space.s2) {
            Label(place.name,systemImage:"mappin.and.ellipse").font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
            if !place.address.isEmpty { Text(verbatim:place.address).fixedSize(horizontal: false, vertical: true) }
            Text(verbatim:"WGS84 · \(place.lat), \(place.lng)").font(Theme.Font.label).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text("静态大致地点，非实时位置；四位坐标，不提供导航。").font(Theme.Font.label)
            if showMap {
                Map(initialPosition:.region(MKCoordinateRegion(
                    center:CLLocationCoordinate2D(latitude:place.lat,longitude:place.lng),
                    span:MKCoordinateSpan(latitudeDelta:0.01,longitudeDelta:0.01)))) {
                    Marker(place.name,coordinate:CLLocationCoordinate2D(latitude:place.lat,longitude:place.lng))
                }.frame(height:180).allowsHitTesting(false)
            } else {
                Text("查看地图会向系统地图服务提供此地点；不会读取你的设备位置。").font(Theme.Font.label)
                Button("同意并查看地点地图") { showMap=true }
            }
        }.font(Theme.Font.body).privacySensitive().onDisappear { showMap=false }
    }
}
