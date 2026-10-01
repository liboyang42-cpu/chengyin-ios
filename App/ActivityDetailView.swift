import SwiftUI
import MapKit

@MainActor
struct ActivityDetailView: View {
    let id: Int
    let reader: any ActivityReading
    var playReaderForActivity: ((Int)->PlaySessionReader)? = nil
    var registrationEnabled=false
    @State private var showsRegistration=false
    @State private var access: ActivityDetailAccess?
    @State private var loading=false
    @State private var failed=false
    @State private var generation=0
    var body: some View {
        // Group with nil access produces EmptyView, which cannot host the initial task.
        // Keep one concrete root for the task and navigation title through every state.
        ZStack {
            if loading { ProgressView("activity.loading") }
            else if failed {
                ContentUnavailableView {
                    Label {
                        Text("activity.loadFailed").accessibilityIdentifier("activity.detail.error")
                    } icon: { Image(systemName:"wifi.exclamationmark") }
                } actions: {
                    Button("action.retry") { Task { await load() } }
                        .accessibilityIdentifier("activity.detail.retry")
                }
            } else if let access {
                switch access {
                case .clubRequired(_,let message):
                    ContentUnavailableView {
                        Label {
                            Text("activity.clubRequired").accessibilityIdentifier("activity.detail.clubGate")
                        } icon: { Image(systemName:"lock") }
                    } description: {
                        if let message, !message.isEmpty { Text(message) }
                        else { Text("activity.clubRequiredHint") }
                    }
                case .allowed(let detail):
                    detailContent(detail)
                }
            } else { ProgressView("activity.loading") }
        }
        .appNavigationTitle("activity.details")
        .navigationBarTitleDisplayMode(.inline)
        .task(id:id) { await load() }
        .sheet(isPresented:$showsRegistration) {
            if let access,case .allowed(let detail)=access { SessionRegistrationSheet(activity:detail) }
        }
    }
    private func detailContent(_ detail:ActivityDetail) -> some View {
        List {
            Section {
                Text(detail.summary.name).font(.title2.bold())
                    .accessibilityIdentifier("activity.detail.name")
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
                            .accessibilityElement(children:.combine)
                            .accessibilityIdentifier("activity.ticket.price.\(ticket.id)")
                        if ticket.isSoldOut {
                            Text("activity.soldOut").foregroundStyle(.secondary)
                                .accessibilityIdentifier("activity.ticket.soldOut.\(ticket.id)")
                        } else if ticket.remainingInventory == nil {
                            Text("activity.inventoryUnknown").font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("activity.ticket.inventoryUnknown.\(ticket.id)")
                        }
                    }.padding(.vertical,4)
                }
            }
            if let playReaderForActivity {
                Section {
                    NavigationLink { PlaySessionView(reader:playReaderForActivity(id)) } label: {
                        Label("play.openSession",systemImage:"figure.walk")
                    }.accessibilityIdentifier("activity.openPlay")
                }
            }
            if registrationEnabled {
                Section {
                    Button("registration.form.title") { showsRegistration=true }
                        .accessibilityIdentifier("activity.openRegistration")
                }
            }
            Section {
                Text("activity.registrationPending").foregroundStyle(.secondary)
                    .accessibilityIdentifier("activity.detail.readOnly")
            }
        }
        .accessibilityIdentifier("activity.detail.content")
    }
    @MainActor private func load() async {
        generation += 1
        let operation=generation
        loading=true;failed=false
        defer { if generation == operation { loading=false } }
        do {
            let result=try await reader.activityDetail(id:id)
            if generation == operation { access=result }
        }
        catch is CancellationError { }
        catch { if generation == operation { failed=true } }
    }
}
