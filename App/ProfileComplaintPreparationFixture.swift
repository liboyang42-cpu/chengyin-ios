#if DEBUG
import SwiftUI

/// Synthetic fixtures only. No transport, persistent store, account access, or grants.
@MainActor final class ProfileComplaintPreparationFixtureReader: ObservableObject, CoopFlowReading {
    @Published var session: CoopFlowSession? = try? .init(accountID: 41, epoch: 1, token: "synthetic-complaint-token")
    var calls = 0
    let scenario: String
    init(scenario: String) {
        self.scenario = scenario
        if scenario == "guest" { session = nil }
    }
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        guard resource == .complaintTopics else { throw APIError.notConfigured }
        calls += 1
        if scenario == "failure" && calls == 1 { throw APIError.httpStatus(503) }
        if scenario == "refreshFailure" && calls == 2 { throw APIError.httpStatus(503) }
        if scenario == "unauthorized" { throw APIError.unauthorized }
        if scenario == "unavailable" { throw APIError.notConfigured }
        if scenario == "empty" || (scenario == "becomesEmpty" && calls > 1) { return .array([]) }
        if scenario == "malformed" { return .array([.object(["registrationId": .id(71)])]) }
        return .array([
            .object(["topicId": .id(71), "topicName": .string("Synthetic city topic"), "registrationId": .id(987)]),
            .object(["topicId": .id(72), "topicName": .string("Synthetic second topic")])
        ])
    }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw APIError.notConfigured }
}
@MainActor struct ProfileComplaintPreparationFixtureView: View {
    @StateObject private var reader: ProfileComplaintPreparationFixtureReader
    init(scenario: String) { _reader = StateObject(wrappedValue: .init(scenario: scenario)) }
    var body: some View {
        NavigationStack {
            ProfileComplaintPreparationView(reader: reader, isCurrent: { reader.session != nil })
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Synthetic sign out") { reader.session = nil }
                            .accessibilityIdentifier("profile.complaint.fixture.signOut")
                    }
                }
        }
    }
}
#endif
