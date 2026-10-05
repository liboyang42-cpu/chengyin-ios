#if DEBUG
import SwiftUI
import Observation

@MainActor struct NativeVerificationFixtureView: View {
    @State private var transport: NativeVerificationFixtureTransport
    @State private var flow: NativeVerificationWorkflow?
    init(scenario: String) {
        let transport = NativeVerificationFixtureTransport(unknown: scenario == "unknown")
        _transport = State(initialValue: transport)
        if let configuration = try? APIConfiguration(baseURL: URL(string: "https://verification.test")!),
           let session = try? MerchantBusinessSession(accountID: 9, epoch: 1, token: "synthetic-token") {
            let service = MerchantBusinessService(configuration: configuration, readTransport: transport, testingMutationTransport: transport)
            let reader = MerchantBusinessSessionReader(service: service, currentSession: { session })
            let journal = MerchantBusinessMemoryIntentStore()
            let coordinator = MerchantRedemptionCoordinator(service: service, journal: journal, currentSession: { session })
            // This fixture exercises acknowledgement/cancellation, not wall-clock expiry.
            // Simulator animation stalls must not age its synthetic review. Production
            // keeps Date.init; NativeVerificationTests advances time to verify expiry.
            let fixtureNow = Date(timeIntervalSince1970: 1_800_000_000)
            _flow = State(initialValue: NativeVerificationWorkflow(reader: reader, journal: journal,
                redemption: coordinator, now: { fixtureNow }))
        } else { _flow = State(initialValue: nil) }
    }
    var body: some View {
        VStack {
            Text("verification.fixture").font(.caption)
            Text(verbatim: String(transport.mutationCount)).accessibilityIdentifier("verification.fixtureCount")
            NavigationStack {
                if let flow {
                    NativeVerificationView(flow: flow, records: {
                        AnyView(Text("verification.fixtureRecords").navigationTitle("verification.records").accessibilityIdentifier("verification.fixtureRecords"))
                    })
                }
            }
        }
    }
}
@MainActor @Observable private final class NativeVerificationFixtureTransport: MerchantBusinessTestTransport {
    let unknown: Bool
    var mutationCount = 0
    init(unknown: Bool) { self.unknown = unknown }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        if request.url?.path == "/api/merchant/access/me" {
            return (Data(("{\"code\":200,\"data\":" + MerchantBusinessSyntheticFixtures.access + "}").utf8), 200)
        }
        mutationCount += 1
        if unknown { throw URLError(.timedOut) }
        return (Data(#"{"code":200,"msg":"Synthetic acknowledged","data":{}}"#.utf8), 200)
    }
}
#endif
