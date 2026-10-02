#if DEBUG
import SwiftUI

@MainActor private final class WalletFixtureState: ObservableObject {
    @Published var scope: WalletCommerceScope? = .init(namespace: "offline-fixture", accountID: 9001, epoch: UUID())
    private let failed: Bool
    init(failed: Bool) { self.failed = failed }
    lazy var reader: WalletCommerceReader = {
        let configuration = try! APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let service = WalletCommerceService(configuration: configuration, transport: WalletCommerceSyntheticTransport(fail: failed))
        return WalletCommerceReader(service: service) { [weak self] in
            guard let scope = self?.scope else { return nil }
            return (scope, "synthetic-token")
        }
    }()
}
/// Register only in the existing DEBUG --uitesting-module switch, never ordinary navigation.
@MainActor struct WalletCommerceFixtureHost: View {
    static var selected: Bool { ProcessInfo.processInfo.arguments.contains("--wallet-commerce-fixture") }
    @StateObject private var state: WalletFixtureState
    init() { _state = StateObject(wrappedValue: WalletFixtureState(failed: ProcessInfo.processInfo.arguments.contains("--wallet-failure"))) }
    var body: some View {
        NavigationStack {
            List {
                Text("Synthetic offline wallet fixture")
                NavigationLink("Assets") { WalletAssetsView(reader: state.reader) }.accessibilityIdentifier("wallet.fixture.assets")
                NavigationLink("Points") { WalletLedgerView(reader: state.reader, kind: .points) }.accessibilityIdentifier("wallet.fixture.points")
                NavigationLink("Cart") { WalletCartView(reader: state.reader) }.accessibilityIdentifier("wallet.fixture.cart")
                NavigationLink("Withdrawals") { WalletWithdrawalsView(reader: state.reader) }.accessibilityIdentifier("wallet.fixture.withdrawals")
            }.toolbar {
                Button("Sign out") { state.scope = nil }.accessibilityIdentifier("wallet.fixture.signOut")
            }
        }.id(state.scope)
    }
}
#endif
