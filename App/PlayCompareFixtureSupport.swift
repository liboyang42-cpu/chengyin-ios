#if DEBUG
import SwiftUI
import Observation

/// Synthetic UI-test transport. It never opens a connection or grants a production capability.
@MainActor @Observable final class PlayCompareFixtureTransport: HTTPTransport {
    var writes = 0
    private var version = 1
    private var attempts = 0
    private var marked: [String] = []
    private var correct = false
    private var replay: [Data: Data] = [:]
    private let unknown: Bool
    init(unknown: Bool) { self.unknown = unknown }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        if request.url?.path.hasSuffix("/action") == true {
            guard let body = request.httpBody else { throw PlayExperienceError.invalidAction }
            if let prior = replay[body] { return (prior, 200) }
            let value = try JSONDecoder().decode(PlayWireValue.self, from: body)
            guard value["action"].text == "SUBMIT_COMPARE", value["version"].integer == version else { throw PlayExperienceError.invalidAction }
            writes += 1; version += 1; attempts += 1
            marked = (value["payload"]["marked"].array ?? []).compactMap(\.text)
            correct = Set(marked) == ["left_gate", "right_gate"]
            let result = try response(); replay[body] = result
            if unknown { throw URLError(.timedOut) }
            return (result, 200)
        }
        if request.url?.path.hasSuffix("/state") == true && !unknown { version += 1 }
        return (try response(), 200)
    }
    private func response() throws -> Data {
        func item(_ id: String, _ time: String, _ text: String) -> PlayWireValue { .object(["id": .string(id), "time": .string(time), "text": .string(text)]) }
        let done = correct || attempts >= 2
        let compare: PlayWireValue = .object([
            "prompt": .string("Mark the changed event in both records."), "maxAttempts": .int(2), "attempts": .int(attempts), "remainingAttempts": .int(max(0, 2 - attempts)),
            "finished": .bool(done), "passed": .bool(correct), "lastCorrect": .bool(correct), "lastMarked": .array(marked.map(PlayWireValue.string)),
            "left": .object(["label": .string("Original record"), "items": .array([item("left_gate", "09:00", "The gate opened."), item("left_bell", "10:00", "The bell rang.")])]),
            "right": .object(["label": .string("Revised record"), "items": .array([item("right_gate", "09:00", "The gate stayed closed."), item("right_bell", "10:00", "The bell rang.")])])
        ])
        let state: PlayWireValue = .object(["sessionId": .int(1), "activityId": .int(41), "topicId": .int(71), "nodeId": .int(701), "version": .int(version), "status": .string("RUNNING"), "readyForBase": .bool(done), "playKit": .object(["compare": compare])])
        return try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": state]))
    }
}

@MainActor struct PlayCompareFixtureHost: View {
    @State private var model: PlayAdvancedCoordinator
    @State private var transport: PlayCompareFixtureTransport
    private let inline: Bool
    init() {
        let args = ProcessInfo.processInfo.arguments
        let transport = PlayCompareFixtureTransport(unknown: args.contains("--compare-unknown"))
        let session = try! PlayExperienceSession(accountID: 1, epoch: 1, namespace: "synthetic-compare", token: "synthetic-token")
        let service = PlayExperienceService(configuration: try! APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport, enabled: [.reads, .advanced])
        _transport = State(initialValue: transport)
        _model = State(initialValue: PlayAdvancedCoordinator(activityID: 41, topicID: 71, nodeID: 701, service: service, currentSession: { session }))
        inline = args.contains("--compare-inline")
    }
    var body: some View {
        NavigationStack {
            VStack {
                Text(verbatim: String(transport.writes)).accessibilityIdentifier("compare.fixture.writes")
                if inline {
                    ScrollView { PlayKitInlineHost(model: model, kind: .compare).padding() }
                } else { PlayAdvancedView(model: model, onReady: { _ in }) }
            }.task { await model.start() }
        }
    }
}
#endif
