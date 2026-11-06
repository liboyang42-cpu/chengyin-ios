#if DEBUG
import SwiftUI

/// Offline w2-05 withdrawal parity fixture, reached only from the DEBUG wallet fixture host.
/// Scenario: `--withdrawal-parity=<rows|empty|denied|unauthorized|failure>`. All values invented.
@MainActor struct WithdrawalParityFixtureHost: View {
    @State private var reader: WalletCommerceReader = {
        let scope = WalletCommerceScope(namespace: "offline-fixture", accountID: 9002, epoch: UUID())
        let configuration = try! APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let service = WalletCommerceService(configuration: configuration, transport: WithdrawalParityFixtureTransport(scenario: Self.scenario))
        return WalletCommerceReader(service: service) { (scope: scope, token: "synthetic-token") }
    }()
    static var scenario: String {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--withdrawal-parity=") }.map { String($0.dropFirst("--withdrawal-parity=".count)) } ?? "rows"
    }
    var body: some View {
        List {
            NavigationLink("Withdrawal application") { WithdrawalSupportLandingView(reader: reader) }
                .accessibilityIdentifier("withdrawal.parity.apply")
            NavigationLink("Withdrawal records") { WithdrawalHistoryView(reader: reader) }
                .accessibilityIdentifier("withdrawal.parity.history")
        }.navigationTitle("Withdrawal parity fixture")
    }
}

private struct WithdrawalParityFixtureTransport: HTTPTransport {
    let scenario: String
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        switch request.url?.path {
        case "/api/withdrawal/list":
            switch scenario {
            case "empty": return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
            case "denied": return (Data(#"{"code":403}"#.utf8), 200)
            case "unauthorized": return (Data(#"{"code":401}"#.utf8), 200)
            case "failure": return (Data(#"{"code":500}"#.utf8), 200)
            default:
                return (Data(#"{"code":200,"data":[{"id":50,"status":0,"receivedAmount":12.3,"createTime":"2026-10-01 10:00:00"},{"id":51,"status":1,"receivedAmount":8,"createTime":"2026-09-20 09:30:00"},{"id":52,"status":2,"receivedAmount":5.5},{"id":53,"status":3},{"id":54}]}"#.utf8), 200)
            }
        case "/api/user/info": return (Data(#"{"code":200,"data":{"balance":"12.30"}}"#.utf8), 200)
        case "/api/wallet/stages":
            return (Data(#"{"code":200,"data":{"pendingSettlement":0,"disputed":0,"withdrawable":0,"complaintPeriod":[],"amountsKnown":true}}"#.utf8), 200)
        default: return (Data(#"{"code":404}"#.utf8), 404)
        }
    }
}
#endif
