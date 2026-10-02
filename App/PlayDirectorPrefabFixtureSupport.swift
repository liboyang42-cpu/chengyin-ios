#if DEBUG
import SwiftUI

@MainActor private final class PlayDirectorPrefabFixtureState {
    let scenario: String
    let session: PlayExperienceSession
    var revision = 2
    var arrived = false
    var done = false
    var lastCommand: PlayWireValue?
    init(scenario: String) {
        self.scenario = scenario
        session = try! PlayExperienceSession(accountID: 9001, epoch: 1, namespace: "synthetic-play-extension", token: "synthetic-token")
    }
    func response(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        func envelope(_ raw: PlayWireValue) throws -> (Data, Int) { (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": raw])), 200) }
        if path.hasSuffix("/game/session/view") {
            let raw = try PlayExperienceSyntheticFixtures.wire(#"{"perspective":"CLUB","activityId":41,"sessionId":501,"revision":2,"status":"RUNNING","availableActions":["FINISH","ASSIGN_ROLES","TAKEOVER_ROLE","BROADCAST","UNLOCK_CHAPTER","SET_LEADERBOARD_VISIBILITY","CLUB_STATION_PAUSE","CLUB_STATION_RESUME","CLUB_REJECT_SUBMISSION"],"club":{"readiness":{"requiredStations":1,"readyStations":1,"teamsReady":true},"stations":[{"nodeId":701,"nodeName":"Synthetic station","status":"ACTIVE","pendingVerificationCount":1,"fallbackPlanOptions":[{"planCode":"INDOOR","version":1}]}],"teams":[{"teamId":61,"name":"Synthetic team","completedNodes":0,"totalNodes":1,"memberCount":2}],"roles":[{"teamId":61,"memberId":9001,"memberName":"Synthetic lead","roleCode":"OBSERVER","roleName":"Observer","confirmationStatus":"CONFIRMED"},{"teamId":61,"memberId":9002,"memberName":"Synthetic participant","roleCode":"","confirmationStatus":"JOINED"}],"roleOptions":[{"roleCode":"OBSERVER","roleName":"Observer"}],"chapterOptions":[{"chapterId":81,"title":"Synthetic next chapter","unlocked":false,"unlockable":true}],"leaderboardVisible":false,"submissions":[{"submissionId":91,"teamId":61,"nodeName":"Synthetic station","status":"PENDING"}],"broadcasts":[]}}"#)
            var fields = raw.object!; fields["revision"] = .int(revision)
            return try envelope(.object(fields))
        }
        if path.hasSuffix("/game/session/command"), let body = request.httpBody {
            let command = try JSONDecoder().decode(PlayWireValue.self, from: body); lastCommand = command; revision += 1
            return try envelope(.object(["activityId": command["activityId"], "requestId": command["requestId"], "action": command["action"], "outcome": .string("APPLIED"), "receiptId": .int(301), "revision": .int(revision)]))
        }
        if path.hasSuffix("/nodes") {
            return try envelope(.object(["topicId": .int(71), "topicName": .string("预制人生 · Synthetic"), "mode": .int(1), "registered": .bool(true), "playable": .bool(true),
                "nodes": .array([.object(["nodeId": .int(701), "name": .string("Synthetic exhibition hall"), "address": .string("Synthetic address"), "done": .bool(done), "arrived": .bool(arrived), "validationMethod": .int(2), "imgUrl": done ? .string("https://example.com/synthetic-hall.jpg") : .null])])]))
        }
        if path.hasSuffix("/arrive") { arrived = true; return try envelope(.object(["nodeId": .int(701)])) }
        if path.hasSuffix("/photo") { done = true; return try envelope(.object(["nodeId": .int(701)])) }
        if path.hasSuffix("/uploadOSS") { return (Data(#"{"code":200,"url":"https://example.com/synthetic-hall.jpg"}"#.utf8), 200) }
        throw PlayExperienceError.unsupported
    }
}
private final class PlayDirectorPrefabFixtureTransport: HTTPTransport {
    let action: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ action: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.action = action }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await action(request) }
}
@MainActor private final class PlayPrefabFixtureStorage: TemplateAuthoringStorage {
    var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { values[key] = data }
    func remove(_ key: String) throws { values.removeValue(forKey: key) }
}
@MainActor struct PlayDirectorPrefabFixtureHostView: View {
    let scenario: String
    @State private var director: PlayDirectorCoordinator
    @State private var prefab: PlayPrefabRuntimeCoordinator
    init(scenario: String) {
        self.scenario = scenario
        let state = PlayDirectorPrefabFixtureState(scenario: scenario)
        let service = PlayExperienceService(configuration: try! APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: PlayDirectorPrefabFixtureTransport { try await state.response($0) }, enabled: [.reads, .directorCommands, .classicCompletion, .mediaUpload])
        _director = State(initialValue: PlayDirectorCoordinator(activityID: 41, service: service, currentSession: { state.session }))
        let store = PlayPrefabRuntimeStore(storage: PlayPrefabFixtureStorage())
        var record = PlayPrefabRuntimeRecord(owner: PlayPrefabRuntimeStore.owner(state.session), scopeComponent: PlayPrefabRuntimeStore.scope(.activity(41)))
        if scenario == "prefabBoot" { record.story.scene = .boot }
        try? store.save(record, session: state.session, scope: .activity(41))
        let provider = PlaySyntheticDeviceProvider(supported: [.photo, .location]) { kind, _ in
            if kind == .location { return .location(121, 31, coordinateSystem: "GCJ02") }
            return .photo(Data([1,2,3]), mimeType: "image/jpeg")
        }
        _prefab = State(initialValue: PlayPrefabRuntimeCoordinator(scope: .activity(41), service: service, provider: provider, store: store, currentSession: { state.session }))
    }
    var body: some View {
        NavigationStack {
            if scenario == "director" { PlayDirectorView(model: director) }
            else { PlayPrefabRuntimeView(model: prefab, dice: { [4, 5] }) }
        }
    }
}
#endif
