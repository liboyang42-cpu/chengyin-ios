#if DEBUG
import SwiftUI

@MainActor private final class PlayExperienceFixtureState {
    var epoch: UInt64 = 1
    var accountID = 9001
    var done = false
    var normalRecorder: PlayRecoveryRecordingTransport?
    var circleRecords: [PlayWireValue] = []
    var tagRevoked = false
    var tagConfirmed = false
    private var retainedDestinations: [String: AnyObject] = [:]
    func retained<Model: AnyObject>(_ key: String, make: () -> Model) -> Model {
        let scoped = "\(accountID):\(epoch):" + key
        if let existing = retainedDestinations[scoped] as? Model { return existing }
        let model = make(); retainedDestinations[scoped] = model; return model
    }
    let scenario: String
    init(scenario: String) { self.scenario = scenario }
    var session: PlayExperienceSession? { try? .init(accountID: accountID, epoch: epoch, namespace: "synthetic-play-cn", token: "synthetic-token") }
    func response(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        if path.hasSuffix("/nodes") {
            if scenario == "referenceUnknownTotal" {
                return (PlayExperienceSyntheticFixtures.envelope(#"{"topicId":71,"topicName":"Synthetic phase-only journey / 测试旅程","mode":1,"playable":true,"registered":true,"nodes":[{"nodeId":701,"name":"Synthetic task / 测试任务","done":false}]}"#), 200)
            }
            if scenario == "referenceComplete" { return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.complete), 200) }
            if scenario == "referenceFailure" { throw PlayExperienceError.malformed }
            if scenario == "preference" {
                let json: PlayWireValue = .object(["topicId": .int(71), "topicName": .string("Synthetic preference journey"), "mode": .int(1), "playable": .bool(true), "registered": .bool(true), "nodes": .array([.object(["nodeId": .int(701), "name": .string("Synthetic preference station"), "done": .bool(done), "validationMethod": .int(6)])])])
                return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": json])), 200)
            }
            if scenario == "sensor", !done {
                return (PlayExperienceSyntheticFixtures.envelope(#"{"topicId":71,"topicName":"Synthetic stillness","mode":1,"playable":true,"registered":true,"nodes":[{"nodeId":701,"name":"Synthetic sensor station","done":false,"validationMethod":7,"sensorType":"still","sensorConfig":{"durationSec":1,"tolerance":0.02}}]}"#), 200)
            }
            let raw = scenario == "mode2" ? PlayExperienceSyntheticFixtures.mode2 : scenario == "branch" && !done ? PlayExperienceSyntheticFixtures.branch : done ? PlayExperienceSyntheticFixtures.complete : PlayExperienceSyntheticFixtures.classic
            return (PlayExperienceSyntheticFixtures.envelope(raw), 200)
        }
        if path.hasSuffix("/route-state") { return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.route), 200) }
        if path.hasSuffix("/answer") || path.hasSuffix("/sensor-result") {
            if scenario == "unknown" { throw URLError(.timedOut) }
            done = true; return (PlayExperienceSyntheticFixtures.envelope(#"{"nodeId":701,"firstTime":true,"xp":9,"completed":true}"#), 200)
        }
        if path.hasSuffix("/preference/701") {
            return (PlayExperienceSyntheticFixtures.envelope(#"{"nodeId":701,"steps":[{"key":"FIRST","type":"single","title":"Synthetic preference question","options":[{"key":"A","text":"Synthetic first option"},{"key":"B","text":"Synthetic second option"}]}],"inheritedTags":[]}"#), 200)
        }
        if path.hasSuffix("/preference/701/submit") {
            done = true
            normalRecorder?.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.complete), 200)
            if let recorder = normalRecorder { recorder.responses.merge(recorder.afterCompletion) { _, new in new } }
            return (PlayExperienceSyntheticFixtures.envelope(#"{"evaluation":{"resultCode":"SYNTHETIC","title":"Synthetic result","body":"Synthetic suggestion","nextStep":"Synthetic next step","nextStepDays":7},"progress":{"nodeId":701,"xp":3},"pendingTag":{"id":81,"tagCode":"SYNTHETIC","tagValue":"Synthetic tag","status":0},"tagDisclosure":{"purpose":"Synthetic personalization only","recipientLabel":"Synthetic journey service","revocable":true},"availableTagValues":["Synthetic tag","Synthetic other tag"]}"#), 200)
        }
        if path.hasSuffix("/tag/81/confirm") {
            tagConfirmed = true
            return (PlayExperienceSyntheticFixtures.envelope(#"{"id":81,"tagCode":"SYNTHETIC","tagValue":"Synthetic tag","status":1}"#), 200)
        }
        if path.hasSuffix("/tag/81/revoke") {
            tagRevoked = true
            return (PlayExperienceSyntheticFixtures.envelope(#"{"id":81,"tagValue":"Synthetic tag","status":"REVOKED"}"#), 200)
        }
        if path.hasSuffix("/play/os/71") {
            return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": .object(["topicId": .int(71), "tags": .array([.object(["id": .int(81), "tagValue": .string("Synthetic tag"), "status": .string(tagRevoked ? "REVOKED" : "ACTIVE")])]), "actions7Days": .array([.string("Synthetic next-week action")])])])), 200)
        }
        if path.hasSuffix("/ending") { return (PlayExperienceSyntheticFixtures.envelope(done ? #"{"opener":"Synthetic ending","fragments":[{"step":1,"nodeId":701,"name":"Synthetic courtyard","text":"Your synthetic route has been read back."}]}"# : #"{"opener":"","fragments":[]}"#), 200) }
        if path.hasSuffix("/leaderboard") { return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.board), 200) }
        if path.hasSuffix("/team-progress") { return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.lead), 200) }
        if path.hasSuffix("/hint/unlock") { return (PlayExperienceSyntheticFixtures.envelope(#"{"hint1":"Synthetic hint","hint2":"","cost":2}"#), 200) }
        if path.hasSuffix("/run-session") { return (PlayExperienceSyntheticFixtures.envelope(#"{"runState":"PAUSED","savedAt":1000,"elapsedSeconds":12}"#), 200) }
        if path.contains("/run-session/") || path.contains("/club/lead/") { return (PlayExperienceSyntheticFixtures.envelope("null"), 200) }
        if path.hasSuffix("/advanced/start") || path.hasSuffix("/advanced/state") { return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.advanced), 200) }
        if path.hasSuffix("/advanced/action") {
            var raw = try PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.advanced).object!
            raw["version"] = .int(3); raw["readyForBase"] = .bool(true)
            return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": .object(raw)])), 200)
        }
        if path.hasSuffix("/game/session/view") { return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.player), 200) }
        if path.hasSuffix("/offers") { return (PlayExperienceSyntheticFixtures.envelope(#"[{"id":1,"candidateCode":"A","candidateName":"Synthetic shop A"},{"id":2,"candidateCode":"B","candidateName":"Synthetic shop B"},{"id":3,"candidateCode":"C","candidateName":"Synthetic shop C"}]"#), 200) }
        if path.hasSuffix("/circle-theme/session") || path.hasSuffix("/session/join") { return (PlayExperienceSyntheticFixtures.envelope(#"{"id":801}"#), 200) }
        if path.hasSuffix("/801/card") {
            return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": .object(["sessionId": .int(801), "themeCode": .string("FITNESS"), "records": .array(circleRecords), "answers": .array([])])])), 200)
        }
        if path.hasSuffix("/session/record"), let body = request.httpBody {
            let json = try JSONDecoder().decode(PlayWireValue.self, from: body)
            circleRecords.append(.object(["offerId": json["offerId"], "candidateName": .string("Synthetic recorded shop"), "note": json["note"]]))
            return (PlayExperienceSyntheticFixtures.envelope("{}"), 200)
        }
        throw PlayExperienceError.unsupported
    }
}
private final class PlayExperienceFixtureTransport: HTTPTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
@MainActor struct PlayExperienceFixtureHostView: View {
    @State private var state: PlayExperienceFixtureState
    @State private var model: PlayExperienceCoordinator
    @State private var service: PlayExperienceService
    @State private var revision = 0
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-play-experience-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "classic"
        let state = PlayExperienceFixtureState(scenario: scenario); _state = State(initialValue: state)
        let service = PlayExperienceService(configuration: try! APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: PlayExperienceFixtureTransport { try await state.response($0) }, enabled: scenario == "disabled" ? [] : [.reads, .runPersistence, .classicCompletion, .hints, .leader, .advanced, .playerCommands, .circle, .preference, .tags])
        _service = State(initialValue: service)
        // The normal completion/run fixture uses a final scripted recorder with no network.
        let recorder = PlayRecoveryRecordingTransport(); state.normalRecorder = recorder
        let initial = scenario == "mode2" ? PlayExperienceSyntheticFixtures.mode2 : scenario == "branch" ? PlayExperienceSyntheticFixtures.branch : scenario == "referenceComplete" ? PlayExperienceSyntheticFixtures.complete : PlayExperienceSyntheticFixtures.classic
        recorder.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(initial), 200)
        if scenario == "referenceUnknownTotal" { recorder.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"topicId":71,"topicName":"Synthetic phase-only journey / 测试旅程","mode":1,"playable":true,"registered":true,"nodes":[{"nodeId":701,"name":"Synthetic task / 测试任务","done":false}]}"#), 200) }
        if scenario == "preference" { recorder.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"topicId":71,"mode":1,"playable":true,"registered":true,"nodes":[{"nodeId":701,"name":"Synthetic preference station","done":false,"validationMethod":6}]}"#), 200) }
        if scenario == "sensor" { recorder.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"topicId":71,"topicName":"Synthetic stillness","mode":1,"playable":true,"registered":true,"nodes":[{"nodeId":701,"name":"Synthetic sensor station","done":false,"validationMethod":7,"sensorType":"still","sensorConfig":{"durationSec":1,"tolerance":0.02}}]}"#), 200) }
        if scenario == "referenceFailure" { recorder.responses["/fixture/api/play/nodes"] = .failure(.malformed) }
        recorder.responses["/fixture/api/play/route-state"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.route), 200)
        for path in ["answer", "sensor-result", "checkin", "photo", "arrive"] { recorder.responses["/fixture/api/play/" + path] = scenario == "unknown" ? .failure(.unknownResult) : .reply(PlayExperienceSyntheticFixtures.envelope(#"{"nodeId":701,"firstTime":true,"xp":9,"completed":true}"#), 200) }
        recorder.afterCompletion["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.complete), 200)
        recorder.responses["/fixture/api/play/run-session"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"runState":"PAUSED","savedAt":1000,"elapsedSeconds":12}"#), 200)
        for path in ["run-session/save", "run-session/clear"] { recorder.responses["/fixture/api/play/" + path] = .reply(PlayExperienceSyntheticFixtures.envelope("null"), 200) }
        recorder.responses["/fixture/api/play/ending"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"opener":"","fragments":[]}"#), 200)
        recorder.afterCompletion["/fixture/api/play/ending"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"opener":"Synthetic ending","fragments":[{"step":1,"nodeId":701,"name":"Synthetic courtyard","text":"Your synthetic route has been read back."}]}"#), 200)
        recorder.responses["/fixture/api/play/leaderboard"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.board), 200)
        recorder.responses["/fixture/api/club/lead/team-progress"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.lead), 200)
        for action in PlayLeadAction.allCases { recorder.responses["/fixture/api/club/lead/" + action.rawValue] = .reply(PlayExperienceSyntheticFixtures.envelope("null"), 200) }
        recorder.responses["/fixture/api/play/hint/unlock"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"hint1":"Synthetic hint","hint2":"","cost":2}"#), 200)
        let normalService = PlayExperienceService(configuration: try! APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: recorder, enabled: service.enabled)
        _model = State(initialValue: PlayExperienceCoordinator(scope: .activity(41), service: normalService, recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { state.session }))
    }
    var body: some View {
        if state.scenario.hasPrefix("routeMap") {
            PlayRouteMapFixtureHostView(scenario: state.scenario)
        } else {
        NavigationStack {
            PlayExperienceView(model: model,
                advancedModel: { nodeID in
                    guard let lifetime = model.makeInteractionLifetime() else { return nil }
                    let retained: PlayAdvancedCoordinator = state.retained("advanced:\(nodeID)") { PlayAdvancedCoordinator(activityID: 41, topicID: 71, nodeID: nodeID, service: service.bound(to: lifetime), currentSession: { state.session }) }
                    return retained
                },
                motionModel: { nodeID, configuration in
                    PlayStillnessCoordinator(configuration: configuration,
                        provider: PlaySyntheticMotionProvider(samples: (0...20).map { .init(x: 0, y: 0, z: 1, timestamp: Double($0) / 10) }),
                        currentContext: { state.session.flatMap { try? PlayDeviceContext(session: $0, scope: .activity(41), nodeID: nodeID) } })
                },
                preferenceModel: { nodeID in
                    guard let lifetime = model.makeInteractionLifetime() else { return nil }
                    let retained: PlayPreferenceCoordinator = state.retained("preference:\(nodeID)") { PlayPreferenceCoordinator(scope: .activity(41), nodeID: nodeID, service: service.bound(to: lifetime), currentSession: { state.session }) }
                    return retained
                },
                summaryModel: { topicID in state.retained("summary:\(topicID)") { PlayOperatingSummaryCoordinator(topicID: topicID, service: service, currentSession: { state.session }) } },
                playerModel: state.retained("player") { PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { state.session }) },
                circleModel: state.retained("circle") { PlayCircleCoordinator(topicID: 71, service: service, currentSession: { state.session }) })
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("playx.fixture.switch") { state.epoch += 1; state.accountID = 9002; model.invalidate(); revision += 1 }
                            .accessibilityIdentifier("playx.fixture.switch")
                    }
                }
        }.id(revision)
        }
    }
}
#endif
