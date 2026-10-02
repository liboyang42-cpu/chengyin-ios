#if DEBUG
import SwiftUI

@MainActor private final class MerchantMarketingFixtureStore: ObservableObject {
    var session: MerchantMarketingScope? = try! MerchantMarketingScope(namespace: "synthetic-cn", accountID: 700, epoch: 1, token: "synthetic-token")
    let transport: MerchantMarketingFixtureTransport
    let locks = MerchantPredictionMemoryLocks()
    lazy var service = MerchantMarketingService(configuration: try! APIConfiguration(baseURL: URL(string: "https://merchant-marketing.example")!), transport: transport,
        gates: .init(reads: true, insight: true, settlement: true), locks: locks, currentSession: { [weak self] in self?.session })
    lazy var model = MerchantMarketingCoordinator(service: service)
    init(scenario: String) { transport = MerchantMarketingFixtureTransport(scenario: scenario) }
    func signOut() { session = nil; model.sessionChanged() }
}
@MainActor struct MerchantMarketingFixtureHost: View {
    @StateObject private var store: MerchantMarketingFixtureStore
    let initialSurface: MerchantMarketingCoordinator.Surface
    init(scenario: String = "normal", initialSurface: MerchantMarketingCoordinator.Surface = .dashboard) {
        _store = StateObject(wrappedValue: MerchantMarketingFixtureStore(scenario: scenario)); self.initialSurface = initialSurface
    }
    var body: some View {
        NavigationStack {
            MerchantMarketingView(model: store.model, initialSurface: initialSurface)
                .safeAreaInset(edge: .top) { Text("merchantMarketing.synthetic").font(.caption).accessibilityIdentifier("merchantMarketing.synthetic") }
                .toolbar { ToolbarItem(placement: .bottomBar) { Button("merchantMarketing.fixtureSignOut") { store.signOut() }.accessibilityIdentifier("merchantMarketing.fixtureSignOut") } }
        }
    }
}
#endif
