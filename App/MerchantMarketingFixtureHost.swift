#if DEBUG
import SwiftUI

@MainActor private final class MerchantMarketingFixtureStore: ObservableObject {
    var session: MerchantMarketingScope? = try! MerchantMarketingScope(namespace: "synthetic-cn", accountID: 700, epoch: 1, token: "synthetic-token")
    @Published private(set) var settlementCount = 0
    let transport: MerchantMarketingFixtureTransport
    let locks = MerchantPredictionMemoryLocks()
    lazy var service = MerchantMarketingService(configuration: try! APIConfiguration(baseURL: URL(string: "https://merchant-marketing.example")!), transport: transport,
        gates: .init(reads: true, insight: true, settlement: true), locks: locks, currentSession: { [weak self] in self?.session })
    lazy var model = MerchantMarketingCoordinator(service: service)
    init(scenario: String) {
        transport = MerchantMarketingFixtureTransport(scenario: scenario)
        transport.beforeReply = { [weak self] request in
            if request.url?.path == "/api/merchant/predict/settle" { self?.settlementCount += 1 }
        }
    }
    func signOut() { session = nil; model.sessionChanged() }
}
@MainActor struct MerchantMarketingFixtureHost: View {
    @StateObject private var store: MerchantMarketingFixtureStore
    let initialSurface: MerchantMarketingCoordinator.Surface
    init(scenario: String = "normal", initialSurface: MerchantMarketingCoordinator.Surface = .dashboard) {
        _store = StateObject(wrappedValue: MerchantMarketingFixtureStore(scenario: scenario)); self.initialSurface = initialSurface
    }
    var body: some View {
        VStack(spacing: 0) {
            // Synthetic controls must not overlay a production List row's tap target.
            HStack {
                Button("merchantMarketing.fixtureSignOut") { store.signOut() }.accessibilityIdentifier("merchantMarketing.fixtureSignOut")
                Spacer()
                Text(verbatim: String(store.settlementCount)).accessibilityIdentifier("merchantMarketing.fixtureSettlementCount")
            }.padding(.horizontal).frame(minHeight: 44)
            NavigationStack {
                MerchantMarketingView(model: store.model, initialSurface: initialSurface)
                    .safeAreaInset(edge: .top) { Text("merchantMarketing.synthetic").font(.caption).accessibilityIdentifier("merchantMarketing.synthetic")
                        .modifier(AccessibilityFixtureEnvironmentValue()) }
            }
        }.modifier(AccessibilityFixtureOptions())
    }
}
#endif
