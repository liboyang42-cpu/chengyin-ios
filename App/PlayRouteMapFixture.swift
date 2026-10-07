#if DEBUG
import SwiftUI

/// Synthetic host. Only the explicit review-cancellation scenario enables
/// completion review; there are no device providers or live transports.
@MainActor private final class PlayRouteMapFixtureOwner {
    var accountID = 9101
    var epoch: UInt64 = 1
    var revision = 0
    var session: PlayExperienceSession? {
        try? .init(accountID: accountID, epoch: epoch, namespace: "synthetic-route-map", token: "synthetic")
    }
}
@MainActor struct PlayRouteMapFixtureHostView: View {
    let scenario: String
    @State private var owner: PlayRouteMapFixtureOwner
    @State private var model: PlayExperienceCoordinator
    @State private var recorder: PlayRecoveryRecordingTransport
    init(scenario: String) {
        self.scenario = scenario
        let owner = PlayRouteMapFixtureOwner(), recorder = PlayRecoveryRecordingTransport()
        recorder.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(Self.document(scenario: scenario, accountID: owner.accountID, revision: 0)), 200)
        let capabilities: Set<PlayExperienceCapability> = scenario == "routeMapReview" ? [.reads, .classicCompletion] : [.reads]
        let service = PlayExperienceService(configuration: try! APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: recorder, enabled: capabilities)
        _owner = State(initialValue: owner); _recorder = State(initialValue: recorder)
        _model = State(initialValue: PlayExperienceCoordinator(scope: .activity(41), service: service, recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.session }))
    }
    var body: some View {
        NavigationStack {
            PlayExperienceView(model: model)
        }
        .safeAreaInset(edge: .bottom) {
            Menu {
                Button("Synthetic refresh") { reload(switchOwner: false) }.accessibilityIdentifier("playRoute.fixture.read")
                Button("Synthetic account switch") { reload(switchOwner: true) }.accessibilityIdentifier("playRoute.fixture.account")
            } label: { Label("Synthetic route controls", systemImage: "ellipsis.circle").frame(minHeight: 44) }
                .font(.caption).dynamicTypeSize(.large)
                .accessibilityIdentifier("playRoute.fixture.controls")
        }
    }
    private func reload(switchOwner: Bool) {
        owner.revision += 1
        if switchOwner { owner.accountID = 9102; owner.epoch += 1; model.invalidate() }
        recorder.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(Self.document(scenario: scenario, accountID: owner.accountID, revision: owner.revision)), 200)
        Task { await model.load() }
    }
    private static func document(scenario: String, accountID: Int, revision: Int) -> String {
        let name = accountID == 9101 ? (revision == 0 ? "Synthetic current stop" : "Synthetic refreshed stop") : "Synthetic second-account stop"
        let coordinates = (scenario == "routeMapMissing" || scenario == "routeMapFocusMissingCurrent") ? "" : ",\"latitude\":31.23,\"longitude\":121.47"
        if scenario == "routeMapFocusPolar" {
            return #"{"topicId":71,"mode":1,"playable":true,"registered":true,"nodes":[{"nodeId":701,"name":"Synthetic polar stop","done":false,"latitude":89,"longitude":10}]}"#
        }
        let completedCoordinates = scenario == "routeMapMissing" ? "" : ",\"latitude\":31.231,\"longitude\":121.471"
        return """
        {"topicId":71,"mode":1,"playable":true,"registered":true,"total":4,"doneCount":1,
         "nodes":[
          {"nodeId":700,"name":"Synthetic completed stop","done":true\(completedCoordinates)},
          {"nodeId":701,"name":"\(name)","done":false,"description":"Synthetic current story","validationMethod":1,"question":"Synthetic question"\(coordinates)},
          {"nodeId":702,"name":"Locked spoiler name","done":false,"locked":true,"storyText":"Locked spoiler story","address":"Locked spoiler address","latitude":31.232,"longitude":121.472},
          {"nodeId":703,"name":"Hidden spoiler name","done":false,"routeNodeState":"HIDDEN","latitude":31.233,"longitude":121.473,"storyText":"Hidden spoiler story"}]
        }
        """
    }
}
#endif
