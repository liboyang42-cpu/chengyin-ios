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
    @State private var publicHomeSelection: NearbyMerchantCoordinator.PublicHomeSelection?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            Section {
                Text("nearbyMerchant.purpose")
                Toggle("nearbyMerchant.consent", isOn: $purposeAccepted)
                Button("nearbyMerchant.search") { operation = Task { await model.search(purposeAccepted: purposeAccepted) } }
                    .disabled(!purposeAccepted || !model.available || model.isBusy)
                    .accessibilityIdentifier("nearbyMerchant.search")
                if !model.available { Text("coopflow.nearby.unavailable") }
                if model.isBusy { ProgressView("cooperation.loading") }
                if model.phase == .locationFailed { Text("nearbyMerchant.locationFailed") }
                if model.phase == .failed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("cooperation.nearby.failed").font(.headline)
                        Text("cooperation.nearby.failed.detail").font(.footnote).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("cooperation.nearby.failed")
                }
            }
            if model.phase == .ready {
                Section {
                    if model.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("cooperation.nearby.empty").font(.headline)
                            Text("cooperation.nearby.empty.detail").font(.footnote).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("cooperation.nearby.empty")
                    }
                    ForEach(model.rows) { row in
                        if model.publicHomeSelection(rowID: row.id) != nil {
                            Button {
                                publicHomeSelection = model.publicHomeSelection(rowID: row.id)
                            } label: { card(row) }
                                .accessibilityIdentifier("nearbyMerchant.open.\(row.id)")
                        } else {
                            VStack(alignment: .leading) {
                                card(row); Text("nearbyMerchant.unlisted").font(.footnote)
                                // Source: unregistered leads with a server-released phone offer "电话联系" (system dialer only).
                                if let phone = row.callablePhone, let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                                    Link(destination: url) { Label("cooperation.nearby.call", systemImage: "phone") }
                                        .buttonStyle(.bordered).accessibilityIdentifier("cooperation.nearby.call.\(row.id)")
                                }
                            }
                        }
                    }
                }
            }
        }.appNavigationTitle("cooperation.nearby.title").accessibilityIdentifier("nearbyMerchant.list")
            .sheet(item: $publicHomeSelection) { selection in
                NavigationStack {
                    Group {
                        if model.isCurrent(selection), purposeAccepted {
                            PublicMerchantHomeView(target: selection.target, context: publicMerchant)
                        } else { Text("merchant.publicHome.unavailable") }
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("action.close") {
                                guard publicHomeSelection?.id == selection.id else { return }
                                publicHomeSelection = nil
                            }
                                .accessibilityIdentifier("nearbyMerchant.closeHome")
                        }
                    }
                }
            }
            // A sheet leaves the browser mounted; exiting the browser always retires it.
            .onDisappear { cancel() }
            .onChange(of: purposeAccepted) { _, accepted in if !accepted { cancel() } }
            .onChange(of: scenePhase) { _, phase in if phase == .background { cancel() } }
            .onChange(of: model.available) { _, available in if !available { cancel() } }
    }
    private func cancel() {
        operation?.cancel(); operation = nil; publicHomeSelection = nil
        model.cancel(); purposeAccepted = false
    }
    private func card(_ row: NearbyMerchantRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: row.name).font(.headline)
            if let address = row.address { Text(verbatim: address).font(.subheadline) }
            if let distance = row.distance { Text("\(distance, specifier: "%.0f") m").font(.caption) }
        }
    }
}
