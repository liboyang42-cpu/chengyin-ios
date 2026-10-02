#if DEBUG
import SwiftUI

@MainActor final class RoamExperienceFixtureReader: RoamExperienceReading {
    enum Scenario: String { case content, empty, failure, historyCorrupt, active, incomplete, missing, unauthorized, unconfigured, pageFailure, sessionChange }
    let scenario: Scenario
    private var signedOut = false
    private var epoch: UInt64 = 1
    private let scope = try! RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/synthetic-roam")!, accountID: 900)
    var identity: RoamExperienceIdentity? { signedOut || scenario == .unauthorized ? nil : RoamExperienceIdentity(scope: scope, epoch: epoch) }
    var isConfigured: Bool { scenario != .unconfigured }
    var isOfflineExample: Bool { true }
    init(scenario: Scenario = .content) { self.scenario = scenario }
    func signOut() { signedOut = true; epoch += 1 }
    private func check() throws {
        guard identity != nil else { throw APIError.unauthorized }
        if !isConfigured { throw APIError.notConfigured }
        if scenario == .failure { throw APIError.httpStatus(503) }
    }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }
    func history() throws -> [RoamHistoryRecord] {
        try check()
        if scenario == .historyCorrupt { throw RoamExperienceFailure.historyUnreadable }
        return try decode([RoamHistoryRecord].self, scenario == .empty ? "[]" : RoamExperienceSyntheticFixtures.history)
    }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact {
        try check()
        let json: String
        switch scenario {
        case .active: json = RoamExperienceSyntheticFixtures.active
        case .incomplete: json = RoamExperienceSyntheticFixtures.incomplete
        case .missing, .empty: json = RoamExperienceSyntheticFixtures.missing
        default: json = RoamExperienceSyntheticFixtures.settled
        }
        return try decode(RoamSessionFact.self, json)
    }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage {
        try check()
        if scenario == .pageFailure && page > 1 { throw APIError.httpStatus(503) }
        if scenario == .empty { return try decode(RoamAlbumPage.self, "{\"list\":[],\"total\":0,\"pageNum\":\(page),\"pageSize\":\(pageSize)}") }
        var json = RoamExperienceSyntheticFixtures.album
        if scenario == .pageFailure { json = json.replacingOccurrences(of: "\"total\":3", with: "\"total\":21") }
        return try decode(RoamAlbumPage.self, json)
    }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage {
        try check(); return try decode(RoamTileMemoryPage.self, scenario == .empty ? #"{"tiles":[],"nextAfterId":0,"hasMore":false}"# : RoamExperienceSyntheticFixtures.tiles)
    }
    func shopBadge() async throws -> RoamShopBadge? {
        try check(); return scenario == .empty ? nil : try decode(RoamShopBadge.self, RoamExperienceSyntheticFixtures.badge)
    }
}
@MainActor struct RoamExperienceFixtureHostView: View {
    static var selected: Bool { ProcessInfo.processInfo.arguments.contains("--uitesting-roam-experience") }
    @State private var reader: RoamExperienceFixtureReader
    @State private var revision = 0
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-roam-experience-scenario")
        let raw = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        _reader = State(initialValue: RoamExperienceFixtureReader(scenario: raw.flatMap(RoamExperienceFixtureReader.Scenario.init(rawValue:)) ?? .content))
    }
    var body: some View {
        VStack(spacing: 0) {
            if reader.scenario == .sessionChange {
                Button("roam.experience.fixtureSignOut") { reader.signOut(); revision += 1 }
                    .accessibilityIdentifier("roam.experience.fixture.signOut")
            }
            NavigationStack { RoamExperienceHubView(reader: reader) }.id(revision)
        }
    }
}
#endif
