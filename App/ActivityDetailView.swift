import SwiftUI
import MapKit

struct ActivityDetailView: View {
    let id: Int
    @EnvironmentObject private var session: AppSession
    @State private var access: ActivityDetailAccess?
    @State private var loading=false
    @State private var failed=false
    @State private var generation=0
    var body: some View {
        Group {
            if loading { ProgressView("activity.loading") }
            else if failed {
                ContentUnavailableView {
                    Label("activity.loadFailed",systemImage:"wifi.exclamationmark")
                } actions: { Button("action.retry") { Task { await load() } } }
            } else if let access {
                switch access {
                case .clubRequired(_,let message):
                    ContentUnavailableView {
                        Label("activity.clubRequired",systemImage:"lock")
                    } description: {
                        if let message, !message.isEmpty { Text(message) }
                        else { Text("activity.clubRequiredHint") }
                    }
                case .allowed(let detail):
                    detailContent(detail)
                }
            }
        }
        .navigationTitle("activity.details")
        .navigationBarTitleDisplayMode(.inline)
        .task(id:id) { await load() }
    }
    private func detailContent(_ detail:ActivityDetail) -> some View {
        List {
            Section {
                Text(detail.summary.name).font(.title2.bold())
                if let text=detail.summary.description, !text.isEmpty { Text(text) }
                if let date=detail.summary.startDate { Label(date,systemImage:"calendar") }
                if let address=detail.summary.addressName ?? detail.summary.address { Label(address,systemImage:"mappin") }
            }
            if detail.summary.hasValidCoordinates,
               let latitude=detail.summary.latitude, let longitude=detail.summary.longitude {
                Section("activity.location") {
                    let coordinate=CLLocationCoordinate2D(latitude:latitude,longitude:longitude)
                    Map(initialPosition:.region(MKCoordinateRegion(center:coordinate,span:MKCoordinateSpan(latitudeDelta:0.01,longitudeDelta:0.01)))) {
                        Marker(detail.summary.name,coordinate:coordinate)
                    }.frame(height:220)
                        .accessibilityLabel(Text("activity.location"))
                }
            }
            Section("activity.tickets") {
                if detail.tickets.isEmpty { Text("activity.noTickets").foregroundStyle(.secondary) }
                ForEach(detail.tickets) { ticket in
                    VStack(alignment:.leading,spacing:8) {
                        Text(ticket.name).font(.headline)
                        AmountLabel(amount:ticket.price)
                        if ticket.isSoldOut { Text("activity.soldOut").foregroundStyle(.secondary) }
                        else if ticket.remainingInventory == nil { Text("activity.inventoryUnknown").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical,4)
                }
            }
            Section { Text("activity.registrationPending").foregroundStyle(.secondary) }
        }
    }
    @MainActor private func load() async {
        generation += 1
        let operation=generation
        loading=true;failed=false
        defer { if generation == operation { loading=false } }
        do {
            let result=try await session.activityDetail(id:id)
            if generation == operation { access=result }
        }
        catch is CancellationError { }
        catch { if generation == operation { failed=true } }
    }
}
