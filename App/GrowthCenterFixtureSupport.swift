#if DEBUG
import SwiftUI

@MainActor final class GrowthCenterFixtureReader: GrowthCenterReading {
    enum Scenario: String { case content, empty, partialCenter, partialMileage, partialCompleted, partialRank, failure, unauthorized, guest, unconfigured, unranked, sessionChange, slowFilters }
    let scenario: Scenario
    private(set) var scope = UUID()
    private(set) var isAuthenticated: Bool
    var isConfigured: Bool { scenario != .unconfigured }
    var isOfflineExample: Bool { true }
    init(scenario: Scenario = .content) { self.scenario = scenario; isAuthenticated = scenario != .guest }
    func signOut() { isAuthenticated = false; scope = UUID() }
    private func check() throws {
        guard isAuthenticated else { throw APIError.unauthorized }
        if scenario == .unauthorized { throw APIError.unauthorized }
        if scenario == .unconfigured { throw APIError.notConfigured }
        if scenario == .failure { throw APIError.httpStatus(503) }
    }
    private struct Envelope<T: Decodable>: Decodable { let data: T }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(Envelope<T>.self, from: Data(json.utf8)).data
    }
    func overview() async throws -> GrowthCenterOverview {
        try check()
        let center = try decode(GrowthCenterRecord.self, scenario == .empty ? GrowthCenterSyntheticFixtures.emptyCenterJSON : GrowthCenterSyntheticFixtures.centerJSON)
        let progress = try decode(GrowthPlayProgress.self, scenario == .empty ? #"{"data":{"level":1,"totalCheckins":0,"totalMileage":0,"streakDays":0}}"# : GrowthCenterSyntheticFixtures.progressJSON)
        let completed = try decode([GrowthCompletedActivity].self, scenario == .empty ? #"{"data":[]}"# : GrowthCenterSyntheticFixtures.completedJSON)
        let rank = try await leaderboard(query: GrowthBoardQuery())
        return GrowthCenterOverview(center: scenario == .partialCenter ? .failure(.unavailable) : .content(center),
                                    progress: scenario == .partialMileage ? .failure(.network) : .content(progress),
                                    completed: scenario == .partialCompleted ? .failure(.failed) : .content(completed),
                                    rank: scenario == .partialRank ? .failure(.unavailable) : .content(rank))
    }
    func leaderboard(query: GrowthBoardQuery) async throws -> GrowthLeaderboard {
        try check()
        if scenario == .slowFilters {
            try await Task.sleep(nanoseconds: query.metric == .point ? 400_000_000 : 20_000_000)
        }
        var json = scenario == .empty ? GrowthCenterSyntheticFixtures.emptyBoardJSON : GrowthCenterSyntheticFixtures.boardJSON
        if scenario == .unranked { json = json.replacingOccurrences(of: #""rank":12"#, with: #""rank":null"#) }
        json = json.replacingOccurrences(of: #""metric":"point""#, with: "\"metric\":\"\(query.metric.rawValue)\"")
        json = json.replacingOccurrences(of: #""period":"total""#, with: "\"period\":\"\(query.period.rawValue)\"")
        if query.metric == .exp { json = json.replacingOccurrences(of: "Sample North", with: "Sample EXP North") }
        if query.period == .week { json = json.replacingOccurrences(of: "Sample South", with: "Sample weekly South") }
        return try decode(GrowthLeaderboard.self, json)
    }
}
@MainActor struct GrowthCenterFixtureHostView: View {
    @State private var reader: GrowthCenterFixtureReader
    @State private var revision = 0
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-growth-scenario")
        let raw = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        _reader = State(initialValue: GrowthCenterFixtureReader(scenario: raw.flatMap(GrowthCenterFixtureReader.Scenario.init(rawValue:)) ?? .content))
    }
    var body: some View {
        VStack(spacing: 0) {
            if reader.scenario == .sessionChange {
                Button("growth.fixture.signOut") { reader.signOut(); revision += 1 }
                    .accessibilityIdentifier("growth.fixture.signOut")
            }
            NavigationStack { GrowthCenterView(reader: reader) }.id(revision)
        }
    }
}
#endif
