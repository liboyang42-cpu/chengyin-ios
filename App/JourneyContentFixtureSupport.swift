#if DEBUG
import SwiftUI

private final class JourneyFixtureHTTP: HTTPTransport {
    let scenario: String
    init(scenario: String) { self.scenario = scenario }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        if scenario == "probeFailure" { throw URLError(.notConnectedToInternet) }
        if scenario == "unknown", path.hasSuffix("/roll") { throw URLError(.networkConnectionLost) }
        let json: String
        if path.hasSuffix("/encounter"), scenario.hasPrefix("role") {
            let role: String
            switch scenario {
            case "roleA": role = #"{"role":"A","otherRoleLabel":"Other character","views":[{"roleId":"A","title":"Synthetic A clue","body":"Only A may see this","items":[{"label":"Detail","text":"A detail"}]}]}"#
            case "roleB": role = #"{"role":"B","otherRoleLabel":"Other character","views":[{"roleId":"B","title":"Synthetic B clue","body":"Only B may see this","items":[]}]}"#
            case "roleSolo": role = #"{"role":"SOLO","views":[{"roleId":"A","title":"Synthetic A clue","body":"A half","items":[]},{"roleId":"B","title":"Synthetic B clue","body":"B half","items":[]}]}"#
            case "roleMissing": role = #"{"roleMissing":true,"views":[]}"#
            default: role = #"{"role":"A","views":[{"roleId":"A","title":"Must not render A","body":"Private A"},{"roleId":"B","title":"Must not render B","body":"Private B"}]}"#
            }
            json = #"{"code":200,"data":{"nodeId":701,"runId":101,"stateVersion":1,"allowedActions":[],"roleView":"# + role + "}}"
        } else if path.hasSuffix("/encounter") {
            json = #"{"code":200,"data":{"allowedActions":["check"],"check":{"checkId":"fixture-check","skill":"Observation","tier":"medium","advantage":true,"mods":[{"label":"Synthetic torch","value":2,"held":true}]}}}"#
        } else if path.hasSuffix("/settle") {
            json = #"{"code":200,"data":{"settled":true,"rerolled":false,"success":false,"dice":[7],"kept":7,"total":9,"hp":5,"luck":1,"text":"Synthetic server narrative","failCostLabel":"Synthetic server cost"}}"#
        } else {
            json = #"{"code":200,"data":{"settled":false,"rerolled":false,"success":false,"dice":[7],"kept":7,"total":9,"hp":5,"luck":1}}"#
        }
        return (Data(json.utf8), 200)
    }
}
@MainActor struct JourneyContentFixtureHostView: View {
    @State private var model: JourneyCheckCoordinator
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-journey-scenario")
        let scenario = index.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "default"
        let http = JourneyFixtureHTTP(scenario: scenario)
        let owner = try! PlayExperienceSession(accountID: 9001, epoch: 1, namespace: "journey-fixture", token: "synthetic-token")
        let service = JourneyContentService(configuration: try! APIConfiguration(baseURL: URL(string: "https://fixture.example")!), transport: http,
                                            readsEnabled: scenario != "disabled", checksEnabled: scenario != "disabled")
        _model = State(initialValue: JourneyCheckCoordinator(scope: .topic(71), topicID: 71, nodeID: 701, service: service, currentSession: { owner }))
    }
    var body: some View {
        NavigationStack {
            List {
                PlayJourneyCheckView(model: model, nodeDone: false)
                Button("Main task remains available") {}.accessibilityIdentifier("journey.fixture.mainTask")
            }.navigationTitle("journey.check.title")
                .modifier(JourneyCheckReviewPresentation(model: model))
                .task { await model.probe(nodeDone: false); await model.roleContent.load() }
                .onDisappear { model.roleContent.close() }
        }
    }
}
#endif
