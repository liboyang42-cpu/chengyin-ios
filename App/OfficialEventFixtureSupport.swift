#if DEBUG
import SwiftUI

@MainActor final class OfficialFixtureReader: OfficialEventReading {
    enum Scenario: String {
        case content, empty, failure, retry, guest, unauthorized, noPermission, unconfigured, unavailable, paused, ended, unknown
    }
    let scenario: Scenario
    private(set) var scope = UUID()
    private(set) var isAuthenticated: Bool
    var isConfigured: Bool { scenario != .unconfigured }
    var isOfflineExample: Bool { true }
    private var attempts = 0
    init(scenario: Scenario = .content) { self.scenario = scenario; isAuthenticated = scenario != .guest }
    func becomeGuest() { isAuthenticated = false; scope = UUID() }
    func switchAccount() { isAuthenticated = true; scope = UUID() }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    private func check(privateRead: Bool = false) throws {
        if privateRead && !isAuthenticated { throw APIError.unauthorized }
        if scenario == .unconfigured { throw APIError.notConfigured }
        if scenario == .unauthorized { throw APIError.unauthorized }
        if scenario == .failure { throw APIError.httpStatus(503) }
        if scenario == .retry { attempts += 1; if attempts == 1 { throw APIError.httpStatus(503) } }
    }
    func events(city: String?) async throws -> [OfficialEvent] {
        try check()
        return scenario == .empty ? [] : try decode([OfficialEvent].self, OfficialEventSyntheticFixtures.eventsJSON)
    }
    func detail(id: Int) async throws -> OfficialEvent {
        try check()
        if scenario == .unavailable { throw OfficialReadFailure.unavailable }
        var json = OfficialEventSyntheticFixtures.eventJSON.replacingOccurrences(of: "\"id\":71", with: "\"id\":\(id)")
        if scenario == .paused { json = json.replacingOccurrences(of: "\"paused\":false", with: "\"paused\":true,\"pausedReason\":\"Synthetic pause reason\"") }
        if scenario == .ended { json = json.replacingOccurrences(of: "\"status\":3", with: "\"status\":5") }
        if scenario == .unknown { json = "{\"id\":\(id),\"title\":\"Synthetic incomplete facts\"}" }
        return try decode(OfficialEvent.self, json)
    }
    func myEvents() async throws -> [OfficialEvent] {
        try check(privateRead: true)
        return scenario == .empty ? [] : try decode([OfficialEvent].self, #"[{"id":71,"title":"Synthetic joined event","status":3,"signed":true}]"#)
    }
    func partyInbox() async throws -> [OfficialPartyInvite] {
        try check(privateRead: true)
        return scenario == .empty ? [] : try decode([OfficialPartyInvite].self, OfficialEventSyntheticFixtures.inboxJSON)
    }
    func canPublish() async throws -> Bool { isAuthenticated && scenario != .noPermission }
    func myPublished() async throws -> OfficialPublished {
        try check(privateRead: true)
        if scenario == .noPermission { throw OfficialReadFailure.noPublisherPermission }
        return try decode(OfficialPublished.self, scenario == .empty ? "{}" : OfficialEventSyntheticFixtures.publishedJSON)
    }
    func broadcastStats(id: Int) async throws -> OfficialBroadcastStats {
        try check(privateRead: true)
        if scenario == .unavailable { throw OfficialReadFailure.unavailable }
        return try decode(OfficialBroadcastStats.self, scenario == .empty ? "{}" : OfficialEventSyntheticFixtures.statsJSON)
    }
}
@MainActor struct OfficialFixtureHostView: View {
    @State private var reader: OfficialFixtureReader
    @State private var scope: UUID
    private let destination: String
    init() {
        let args = ProcessInfo.processInfo.arguments
        func argument(_ name: String) -> String? {
            guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        let value = OfficialFixtureReader(scenario: argument("--uitesting-official-scenario").flatMap(OfficialFixtureReader.Scenario.init(rawValue:)) ?? .content)
        _reader = State(initialValue: value); _scope = State(initialValue: value.scope)
        destination = argument("--uitesting-official-destination") ?? "browser"
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("official.fixtureGuest") { reader.becomeGuest(); scope = reader.scope }.accessibilityIdentifier("official.fixture.guest")
                Button("official.fixtureAccount") { reader.switchAccount(); scope = reader.scope }.accessibilityIdentifier("official.fixture.account")
            }.buttonStyle(.bordered).font(.caption).frame(minHeight: 44)
            Group {
                switch destination {
                case "detail": NavigationStack { OfficialEventDetailView(id: 71, reader: reader) }
                case "inbox": NavigationStack { OfficialInboxView(reader: reader) }
                case "published": NavigationStack { OfficialPublishedView(reader: reader) }
                case "stats": NavigationStack { OfficialBroadcastStatsView(id: 91, reader: reader) }
                default: OfficialEventsBrowserView(reader: reader)
                }
            }.id(scope)
        }
    }
}
#endif
