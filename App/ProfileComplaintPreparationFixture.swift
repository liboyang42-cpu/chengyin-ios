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
    var progressCalls = 0
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        if resource == .complaintProgress { return try progress() }
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
    /// Separate counter: progress reads never shift the selector failure scenarios above.
    private func progress() throws -> CoopFlowJSON {
        progressCalls += 1
        if scenario == "progressDenied" { throw CoopFlowFailure.server(403, nil) }
        if scenario == "unauthorized" { throw APIError.unauthorized }
        if scenario == "empty" { return .array([]) }
        return .array([
            .object(["id": .id(5), "topicId": .id(71), "topicName": .string("Synthetic city topic"), "status": .id(2),
                     "statusText": .string("处理中"), "reason": .string("Synthetic reason"), "handleNote": .string("Synthetic note")]),
            .object(["id": .id(6), "topicId": .id(72), "topicName": .string("Synthetic second topic"), "status": .id(0),
                     "statusText": .string("已受理"), "reason": .string("Synthetic second reason")])
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
