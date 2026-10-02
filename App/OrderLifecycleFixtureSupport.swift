#if DEBUG
import SwiftUI

@MainActor final class OrderLifecycleFixtureReader: OrderLifecycleReading {
    enum Scenario: String { case pending, paid, refunding, refunded, expired, unknown, guest, failure, sessionChange, chapterChoice, stationChoice, emptyChoice }
    let scenario: Scenario
    var accountID: Int? = 9901
    private(set) var scope = UUID()
    var isConfigured: Bool { true }
    var isOfflineExample: Bool { true }
    init(scenario: Scenario) { self.scenario = scenario; if scenario == .guest { accountID = nil } }
    func replaceSession() { accountID = nil; scope = UUID() }
    func detail(id: Int) async throws -> OrderLifecycleDetail {
        guard accountID != nil else { throw APIError.unauthorized }
        if scenario == .failure { throw URLError(.notConnectedToInternet) }
        let raw: String
        switch scenario {
        case .paid: raw = OrderLifecycleSyntheticFixtures.paid
        case .refunding: raw = OrderLifecycleSyntheticFixtures.refunding
        case .refunded: raw = OrderLifecycleSyntheticFixtures.refunded
        case .expired: raw = #"{"id":9701,"registrationStatus":4,"paymentStatus":1,"verificationStatus":0}"#
        default: raw = OrderLifecycleSyntheticFixtures.pending
        }
        return try OrderLifecycleSyntheticFixtures.detail(raw)
    }
}
@MainActor private final class OrderLifecycleUnknownFixtureSimulator: OrderLifecycleFixtureSimulating {
    func simulate(_ review: OrderLifecycleReview) async throws -> OrderCancellationObservation { throw URLError(.timedOut) }
}
@MainActor struct OrderLifecycleFixtureHostView: View {
    private let reader: OrderLifecycleFixtureReader
    private let coordinator: OrderLifecycleCoordinator
    @State private var revision = 0
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let index = arguments.firstIndex(of: "--uitesting-order-lifecycle-scenario")
        let raw = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let scenario = raw.flatMap(OrderLifecycleFixtureReader.Scenario.init(rawValue:)) ?? .pending
        let reader = OrderLifecycleFixtureReader(scenario: scenario)
        self.reader = reader
        coordinator = scenario == .unknown ? OrderLifecycleCoordinator(reader: reader, fixtureSimulator: OrderLifecycleUnknownFixtureSimulator()) : OrderLifecycleCoordinator(reader: reader)
    }
    var body: some View {
        VStack(spacing: 0) {
            if reader.scenario == .sessionChange {
                Button("orderLifecycle.fixture.signOut") { reader.replaceSession(); coordinator.invalidateVisible(); revision += 1 }
                    .accessibilityIdentifier("orderLifecycle.fixture.signOut")
            }
            NavigationStack {
                if reader.scenario == .chapterChoice || reader.scenario == .stationChoice || reader.scenario == .emptyChoice {
                    let raw = reader.scenario == .chapterChoice ? OrderLifecycleSyntheticFixtures.chapterChoice : reader.scenario == .stationChoice ? OrderLifecycleSyntheticFixtures.stationChoice : #"{"code":500,"data":{"needChapterChoice":true}}"#
                    if let receipt = try? JSONDecoder().decode(OrderVerificationReceipt.self, from: Data(raw.utf8)) {
                        OrderVerificationPreviewView(receipt: receipt)
                    } else { Text("orderLifecycle.issue.malformed") }
                } else { OrderLifecycleView(id: 9701, coordinator: coordinator) }
            }.id(revision)
        }
    }
}
#endif
