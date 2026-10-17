#if DEBUG
import SwiftUI

@MainActor private final class WalletFixtureState: ObservableObject {
    @Published var scope: WalletCommerceScope? = .init(namespace: "offline-fixture", accountID: 9001, epoch: UUID())
    private let failed: Bool
    init(failed: Bool) { self.failed = failed }
    lazy var reader: WalletCommerceReader = {
        let configuration = try! APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let service = WalletCommerceService(configuration: configuration,
            transport: WalletAssetFixtureTransport(failed: failed, arguments: ProcessInfo.processInfo.arguments))
        return WalletCommerceReader(service: service) { [weak self] in
            guard let scope = self?.scope else { return nil }
            return (scope, "synthetic-token")
        }
    }()
}
/// Test-only asset read outcomes; all other fixture routes keep their original transport.
private actor WalletAssetFixtureTransport: HTTPTransport {
    let fallback: WalletCommerceSyntheticTransport
    let arguments: [String]
    private var reads = 0
    init(failed: Bool, arguments: [String]) {
        fallback = WalletCommerceSyntheticTransport(fail: failed); self.arguments = arguments
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard request.url?.path == "/api/wallet/stages" else { return try await fallback.send(request) }
        reads += 1
        if arguments.contains("--wallet-assets-denied") { throw APIError.notConfigured }
        if arguments.contains("--wallet-assets-recover"), reads == 1 { throw APIError.httpStatus(503) }
        let knownZero = arguments.contains("--wallet-assets-known-zero")
        let recovering = arguments.contains("--wallet-assets-recover")
        let unknownNonzero = arguments.contains("--wallet-assets-unknown-nonzero")
        let returnRefresh = arguments.contains("--wallet-assets-return-refresh")
        if knownZero || recovering || unknownNonzero || returnRefresh {
            let amount = knownZero || (returnRefresh && reads == 1) ? 0 : 7
            let known = unknownNonzero ? "false" : "true"
            let json = "{\"code\":200,\"data\":{\"pendingSettlement\":\(amount),\"disputed\":\(amount),\"withdrawable\":\(amount),\"complaintPeriod\":[{\"availableDate\":\"2026-10-08\",\"amount\":\(amount)}],\"amountsKnown\":\(known)}}"
            return (Data(json.utf8), 200)
        }
        return try await fallback.send(request)
    }
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
                NavigationLink("Bank withdrawal") { BankWithdrawalView(reader: state.reader) }.accessibilityIdentifier("wallet.fixture.bankWithdrawal")
                NavigationLink("Withdrawals") { WalletWithdrawalsView(reader: state.reader) }.accessibilityIdentifier("wallet.fixture.withdrawals")
            }.toolbar {
                Button("Sign out") { state.scope = nil }.accessibilityIdentifier("wallet.fixture.signOut")
            }
        }.id(state.scope)
    }
}
#endif
