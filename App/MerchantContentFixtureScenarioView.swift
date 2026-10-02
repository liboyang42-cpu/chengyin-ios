#if DEBUG
import SwiftUI

@MainActor final class MerchantContentFixtureEnvironment: ObservableObject {
    @Published var revision = 0
    var session: MerchantContentSession? = try? .init(accountID: 1, epoch: 1, storageScope: "offline-merchant-content-fixture", token: "fixture-token")
    let transport = MerchantContentFixtureTransport()
    lazy var service = MerchantContentService(configuration: try? APIConfiguration(baseURL: URL(string: "https://merchant-content.example")!), transport: transport, currentSession: { [weak self] in self?.session }, journal: MerchantContentMemoryPendingStorage(), execution: .injectedOfflineHarness)
    init() {
        transport.denied = ProcessInfo.processInfo.arguments.contains("--merchant-content-denied")
        transport.unknownWrite = ProcessInfo.processInfo.arguments.contains("--merchant-content-unknown")
        transport.failReads = ProcessInfo.processInfo.arguments.contains("--merchant-content-failure")
    }
    func signOut() { session = nil; revision += 1 }
    func recover() { transport.failReads = false; revision += 1 }
}
@MainActor struct MerchantContentFixtureScenarioView: View {
    @StateObject private var environment = MerchantContentFixtureEnvironment()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("merchant.content.fixtureSignOut") { environment.signOut() }.accessibilityIdentifier("merchant.content.fixture.signOut")
                Button("merchant.content.fixtureRecover") { environment.recover() }.accessibilityIdentifier("merchant.content.fixture.recover")
            }.font(.caption).padding(8)
            NavigationStack { MerchantContentHomeView(service: environment.service, topicID: 70) }.id(environment.revision)
            Text("merchant.content.fixtureBanner").font(.footnote).padding(6).background(.regularMaterial)
        }
    }
}
#endif
