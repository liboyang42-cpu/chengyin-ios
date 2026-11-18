#if DEBUG
import SwiftUI
import Observation

/// Synthetic UI-test transport for F03 letter pools. It never opens a connection or
/// grants a production capability. The neutral answer lives only in this fixture.
@MainActor @Observable final class PlayKitHangmanFixtureTransport: HTTPTransport {
    var writes = 0
    var lastPayload = ""
    private var version = 1
    private var solved = false
    private var filled: [Int: String] = [:]
    private var questionAttempts = 0
    private var questionPassed = false
    private var replay: [Data: Data] = [:]
    private let question: Bool
    init(question: Bool) { self.question = question }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        if request.url?.path.hasSuffix("/action") == true {
            guard let body = request.httpBody else { throw PlayExperienceError.invalidAction }
            if let prior = replay[body] { return (prior, 200) }
            let value = try JSONDecoder().decode(PlayWireValue.self, from: body)
            guard value["version"].integer == version else { throw PlayExperienceError.invalidAction }
            if question {
                guard value["action"].text == "SUBMIT_QA", let input = value["payload"]["input"].text else { throw PlayExperienceError.invalidAction }
                questionAttempts += 1; questionPassed = input == "甲乙"; lastPayload = input
            } else {
                guard value["action"].text == "SUBMIT_HANGMAN", let slots = value["payload"]["slots"].object else { throw PlayExperienceError.invalidAction }
                for (key, character) in slots { if let index = Int(key), let text = character.text { filled[index] = text } }
                solved = filled[0] == "A" && filled[1] == "B" && filled[3] == "C"
                lastPayload = slots.keys.sorted().map { $0 + "=" + (slots[$0]?.text ?? "") }.joined(separator: ",")
            }
            writes += 1; version += 1
            let result = try response(); replay[body] = result
            return (result, 200)
        }
        return (try response(), 200)
    }
    private func response() throws -> Data {
        let kit: PlayWireValue
        if question {
            kit = .object(["qa": .object([
                "question": .string("Sample station question"), "mode": .string("TYPE"),
                "attempts": .int(questionAttempts), "finished": .bool(questionPassed), "passed": .bool(questionPassed),
                "letterPool": .object(["chars": .array(["丙", "甲", "丁", "乙"].map(PlayWireValue.string)), "answerLength": .int(2), "removed": .int(0)])
            ])])
        } else {
            func open(_ index: Int) -> PlayWireValue {
                if let character = filled[index] { return .object(["i": .int(index), "ch": .string(character), "kind": .string("FILLED")]) }
                return .object(["i": .int(index), "kind": .string("BLANK")])
            }
            kit = .object(["hangman": .object([
                "title": .string("Sample station word"), "length": .int(5), "blankCount": .int(3), "caseSensitive": .bool(false),
                "solved": .bool(solved), "display": .string("__-_D"), "inputMode": .string("pool"),
                "pool": .array(["C", "X", "A", "Y", "B"].map(PlayWireValue.string)), "poolRemoved": .int(0),
                "slots": .array([open(0), open(1), .object(["i": .int(2), "ch": .string("-"), "kind": .string("SEPARATOR")]), open(3),
                                 .object(["i": .int(4), "ch": .string("D"), "kind": .string("PREFILLED")])])
            ])])
        }
        let done = question ? questionPassed : solved
        let state: PlayWireValue = .object(["sessionId": .int(1), "activityId": .int(41), "topicId": .int(71), "nodeId": .int(701), "version": .int(version), "status": .string("RUNNING"), "readyForBase": .bool(done), "playKit": kit])
        return try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": state]))
    }
}

@MainActor struct PlayKitHangmanFixtureHost: View {
    @State private var model: PlayAdvancedCoordinator
    @State private var transport: PlayKitHangmanFixtureTransport
    private let question: Bool
    init() {
        let args = ProcessInfo.processInfo.arguments
        let question = args.contains("--letter-pool-question")
        let transport = PlayKitHangmanFixtureTransport(question: question)
        let session = try! PlayExperienceSession(accountID: 1, epoch: 1, namespace: "synthetic-letter-pool", token: "synthetic-token")
        let service = PlayExperienceService(configuration: try! APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport, enabled: [.reads, .advanced])
        _transport = State(initialValue: transport)
        _model = State(initialValue: PlayAdvancedCoordinator(activityID: 41, topicID: 71, nodeID: 701, service: service, currentSession: { session }))
        self.question = question
    }
    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: String(transport.writes)).accessibilityIdentifier("letterPool.fixture.writes")
            Text(verbatim: transport.lastPayload).accessibilityIdentifier("letterPool.fixture.payload")
            NavigationStack {
                ScrollView { PlayKitInlineHost(model: model, kind: question ? .qa : .hangman).padding() }
            }
        }.task { await model.start() }
    }
}
#endif
