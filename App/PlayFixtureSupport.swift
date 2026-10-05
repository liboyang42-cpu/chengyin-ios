#if DEBUG
import SwiftUI

/// Explicit offline route only. All names, IDs, answers and receipts are synthetic.
/// Uses the production decoder/reader with an in-memory transport, never URLSession.
enum PlayFixtureScenario: String {
    case success, choice, empty, error, expired, passRequired, registrationRequired
    case locked, terminal, unavailable, unknown, branch, media, advanced, loading
    case readbackError, uncertainAnswer, unconfigured, freeExploration
    static var selected: Self {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--uitesting-play-scenario"), args.indices.contains(index + 1) else { return .success }
        return Self(rawValue: args[index + 1]) ?? .success
    }
}

@MainActor
private final class PlayFixtureState {
    let scenario: PlayFixtureScenario
    var epoch: UInt64 = 1
    var accountID = 9001
    var signedIn = true
    var done: Set<Int> = []
    var submitted = false
    init(_ scenario: PlayFixtureScenario) { self.scenario = scenario }
    var credentials: PlayReadSession? {
        guard signedIn else { return nil }
        return try? PlayReadSession(accountID: accountID, epoch: epoch, token: "synthetic-play-token")
    }
    func response(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        if scenario == .loading { try await Task.sleep(nanoseconds: 15_000_000_000) }
        func envelope(_ object: [String: Any], status: Int = 200) throws -> (Data, Int) {
            (try JSONSerialization.data(withJSONObject: object), status)
        }
        if scenario == .expired { return try envelope(["code": 401, "msg": "Synthetic expired session"], status: 401) }
        if scenario == .error || (scenario == .readbackError && submitted && request.httpMethod == "GET") {
            return try envelope(["code": 503, "msg": "Synthetic service failure"], status: 503)
        }
        if scenario == .passRequired { return try envelope(["code": "402", "msg": "Synthetic missing or expired pass"]) }
        if scenario == .freeExploration, request.url?.path.hasSuffix("/nodes") == true {
            return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.mode2), 200)
        }
        if request.url?.path.hasSuffix("/answer") == true {
            submitted = true
            if scenario == .uncertainAnswer { throw URLError(.timedOut) }
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            let id = body.contains("name=\"nodeId\"\r\n\r\n702\r\n") ? 702 : 701
            done.insert(id)
            return try envelope(["code": "200", "data": ["nodeId": id, "firstTime": true,
                "done": done.count, "total": 2, "completed": done.count == 2, "xp": 9]])
        }
        let isBranch = scenario == .branch || scenario == .terminal
        let route: [String: Any] = ["routeMode": "BRANCH_GRAPH", "sessionId": 501,
            "status": scenario == .terminal ? "COMPLETED" : "ACTIVE", "version": 2,
            "nodeStates": ["701": scenario == .terminal ? "COMPLETED" : "PLAYABLE",
                           "702": scenario == .terminal ? "COMPLETED" : "DISCOVERED_LOCKED", "703": "HIDDEN"],
            "lockReasons": ["702": "Synthetic branch requirement"]]
        if request.url?.path.hasSuffix("/route-state") == true { return try envelope(["code": 200, "data": route]) }
        var first: [String: Any] = ["nodeId": 701, "name": "Fixture courtyard", "address": "Synthetic address",
            "done": done.contains(701) || scenario == .terminal, "arrived": true, "locked": scenario == .locked,
            "validationMethod": scenario == .choice ? 3 : 1, "needScan": false, "needGps": false,
            "gameTitle": "Fixture observation task", "duration": 5, "question": "Enter a synthetic answer for this offline task",
            "description": "Synthetic node description", "storyText": "A quiet courtyard is the setting for this fixture.",
            "ruleInstructions": "Read the task. Enter your own test response. Tap Submit.", "chapterId": 81,
            "businessTime": "Synthetic hours", "openStatus": "Synthetic open status"]
        if scenario == .choice { first["options"] = ["A": "Synthetic first choice", "B": "Synthetic second choice"] }
        if scenario == .media { first["questionAudio"] = "fixture-unloaded-audio" }
        if scenario == .advanced { first["advancedConfigJson"] = ["timer": ["enabled": true]] }
        if done.contains(701) { first["xp"] = 9 }
        let second: [String: Any] = ["nodeId": 702, "name": "Fixture garden", "done": done.contains(702) || scenario == .terminal,
            "locked": !done.contains(701), "validationMethod": 3, "arrived": true,
            "question": "Choose a synthetic path", "options": ["A": "Courtyard path", "B": "Garden path"],
            "lockReason": "Complete the first fixture task", "unlockAfterNodeId": 701]
        var rows = [first, second]
        if isBranch { rows.append(["nodeId": 703, "name": "Hidden synthetic node", "done": false]) }
        if scenario == .empty { rows = [] }
        var result: [String: Any] = ["topicId": 71, "topicName": "Offline journey · account \(accountID)",
            "topicDesc": "Synthetic route used only to verify the native session flow.",
            "mode": 1, "playable": scenario != .unavailable, "registered": scenario != .registrationRequired,
            "total": rows.isEmpty ? 0 : 2, "doneCount": scenario == .terminal ? 2 : done.count, "nodes": rows,
            "chapters": [["chapterId": 81, "name": "Fixture first chapter"]]]
        if scenario == .unknown { result.removeValue(forKey: "playable") }
        if scenario == .unavailable { result["timeNote"] = "Synthetic session is outside its playable window" }
        if isBranch { result["routeState"] = route }
        return try envelope(["code": "200", "data": result])
    }
}

private final class PlayFixtureTransport: HTTPTransport {
    private let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}

@MainActor
final class PlayFixtureReader: PlayReading {
    private let state: PlayFixtureState
    private var reader: PlaySessionReader
    var scope: PlaySessionScope { reader.scope }
    var identity: PlayReadIdentity? { reader.identity }
    var isConfigured: Bool { reader.isConfigured }
    var canSubmitAnswer: Bool { reader.canSubmitAnswer }
    var supportsAnswerSubmission: Bool { reader.supportsAnswerSubmission }
    init(_ scenario: PlayFixtureScenario = .success) {
        let state = PlayFixtureState(scenario)
        self.state = state; self.reader = Self.makeReader(state)
    }
    private static func makeReader(_ state: PlayFixtureState) -> PlaySessionReader {
        let service = (try? APIConfiguration(baseURL: URL(string: "https://example.com/play-fixture/")!)).map {
            PlayService(configuration: $0, transport: PlayFixtureTransport { request in try await state.response(request) })
        }
        return PlaySessionReader(scope: .activity(41), service: state.scenario == .unconfigured ? nil : service,
            answersEnabled: true, currentSession: { state.credentials }, onUnauthorized: { captured in
                if state.credentials == captured { state.signedIn = false; state.epoch &+= 1 }
            })
    }
    func switchAccount() {
        state.epoch &+= 1; state.accountID = state.accountID == 9001 ? 9002 : 9001
        state.signedIn = true; state.done.removeAll(); state.submitted = false
        reader = Self.makeReader(state)
    }
    func playSession() async throws -> PlaySnapshot { try await reader.playSession() }
    func submitAnswer(nodeID: Int, answer: String) async throws -> PlayAnswerReceipt { try await reader.submitAnswer(nodeID: nodeID, answer: answer) }
}

@MainActor
struct PlayFixtureHostView: View {
    private let reader: PlayFixtureReader
    @State private var revision = 0
    init(scenario: PlayFixtureScenario = .selected) { reader = PlayFixtureReader(scenario) }
    var body: some View {
        VStack(spacing: 0) {
            Text("play.fixture.notice").font(.caption.bold()).padding(8)
                .frame(maxWidth: .infinity).background(.yellow.opacity(0.2))
                .accessibilityIdentifier("play.fixture.notice")
            NavigationStack {
                PlaySessionView(reader: reader)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("play.fixture.switch") { reader.switchAccount(); revision += 1 }
                                .accessibilityIdentifier("play.fixture.switch")
                        }
                    }
            }.id(revision)
        }
    }
}
#endif
