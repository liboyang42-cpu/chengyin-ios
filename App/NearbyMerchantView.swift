import SwiftUI

private struct CooperationNearbyDestinationKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> AnyView)? = nil
}
extension EnvironmentValues {
    var cooperationNearbyDestination: (@MainActor () -> AnyView)? {
        get { self[CooperationNearbyDestinationKey.self] }
        set { self[CooperationNearbyDestinationKey.self] = newValue }
    }
}
@MainActor struct SessionNearbyMerchantsView: View {
    @ObservedObject var session: AppSession
    var body: some View {
        Group {
            if let model = session.nearbyMerchantCoordinator {
                NearbyMerchantView(model: model, publicMerchant: session.publicMerchantHomeContext)
            } else { Text("coopflow.nearby.unavailable") }
        }.id(session.sessionRevision).privacySensitive()
    }
}
@MainActor struct NearbyMerchantView: View {
    @Bindable var model: NearbyMerchantCoordinator
    var publicMerchant = PublicMerchantHomeContext()
    @State private var purposeAccepted = false
    @State private var operation: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            Section {
                Text("nearbyMerchant.purpose")
                Toggle("nearbyMerchant.consent", isOn: $purposeAccepted).disabled(model.isBusy)
                Button("nearbyMerchant.search") { operation = Task { await model.search(purposeAccepted: purposeAccepted) } }
                    .disabled(!purposeAccepted || !model.available || model.isBusy)
                    .accessibilityIdentifier("nearbyMerchant.search")
                if !model.available { Text("coopflow.nearby.unavailable") }
                if model.isBusy { ProgressView("cooperation.loading") }
                if model.phase == .locationFailed { Text("nearbyMerchant.locationFailed") }
                if model.phase == .failed { Text("coopflow.read.failed") }
            }
            if model.phase == .ready {
                Section {
                    if model.rows.isEmpty { Text("coopflow.empty") }
                    ForEach(model.rows) { row in
                        if let memberID = row.memberID, let owner = PublicMerchantOwnerID(memberID) {
                            NavigationLink { PublicMerchantHomeView(target: .ownerMemberID(owner), context: publicMerchant) } label: { card(row) }
                        } else { VStack(alignment: .leading) { card(row); Text("nearbyMerchant.unlisted").font(.footnote) } }
                    }
                }
            }
        }.navigationTitle("coopflow.nearby").accessibilityIdentifier("nearbyMerchant.list")
            .onDisappear { cancel() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { cancel() } }
    }
    private func cancel() { operation?.cancel(); operation = nil; model.cancel(); purposeAccepted = false }
    private func card(_ row: NearbyMerchantRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: row.name).font(.headline)
            if let address = row.address { Text(verbatim: address).font(.subheadline) }
            if let distance = row.distance { Text("\(distance, specifier: "%.0f") m").font(.caption) }
        }
    }
}
