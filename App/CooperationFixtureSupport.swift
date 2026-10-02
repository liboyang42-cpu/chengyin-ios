#if DEBUG
import SwiftUI

@MainActor final class CooperationFixtureReader: ObservableObject, CooperationReading {
    enum Scenario: String { case content, empty, failure, partial, partialEmpty, noClub, forbidden, unavailable, refreshed, guest, unconfigured, loading, sessionChange }
    let scenario: Scenario
    @Published private var signedIn = true
    private var stamp = UUID()
    private var detailReads = 0
    var scope: UUID { stamp }
    var isAuthenticated: Bool { signedIn && scenario != .guest }
    var isConfigured: Bool { scenario != .unconfigured }
    var isOfflineExample: Bool { true }
    init(scenario: Scenario = .content) { self.scenario = scenario }
    func signOut() { stamp = UUID(); signedIn = false }
    private func check() async throws {
        if scenario == .loading { try await Task.sleep(for: .seconds(60)) }
        guard isAuthenticated else { throw APIError.unauthorized }
        guard isConfigured else { throw APIError.notConfigured }
        if scenario == .failure { throw APIError.httpStatus(503) }
        try Task.checkCancellation()
    }
    func inbox(direction: CooperationDirection) async throws -> CooperationInbox {
        try await check()
        let empty = scenario == .empty || scenario == .partialEmpty
        let invites: CooperationInvites = try decode(empty ? #"{"code":200,"data":{"sent":[],"received":[]}}"# : CooperationSyntheticFixtures.invitationsJSON)
        let applies: [CooperationApplication] = try decode(empty ? #"{"code":200,"data":[]}"# : direction == .received ? CooperationSyntheticFixtures.receivedApplicationsJSON : CooperationSyntheticFixtures.sentApplicationsJSON)
        let registrations: CooperationSection<CooperationRegistrations>?
        if direction == .sent { registrations = nil }
        else if scenario == .partial || scenario == .partialEmpty { registrations = .failure(.server("Sample candidate source unavailable")) }
        else { registrations = .content(try decode(empty ? #"{"code":200,"data":{"rows":[],"hasMore":false}}"# : CooperationSyntheticFixtures.registrationsJSON)) }
        return CooperationInbox(direction: direction, invitations: .content(invites), applications: .content(applies), registrations: registrations)
    }
    func detail(key: CooperationInviteKey) async throws -> CooperationInviteDetail {
        try await check()
        guard scenario != .unavailable else { throw CooperationReadFailure.unavailable }
        detailReads += 1
        var json = CooperationSyntheticFixtures.invitationsJSON
        if scenario == .refreshed && detailReads > 1 {
            json = json.replacingOccurrences(of: "Sample receiving partner", with: "Sample updated partner")
                .replacingOccurrences(of: "\"status\":0,\"message\"", with: "\"status\":3,\"message\"")
        }
        let list: CooperationInvites = try decode(json)
        guard let row = list.rows(key.direction).first(where: { $0.id == key.id }) else { throw CooperationReadFailure.unavailable }
        return CooperationInviteDetail(row: row, occupancy: list.occupancy(for: row))
    }
    func pool() async throws -> CooperationPool {
        try await check()
        return try decode(scenario == .noClub ? #"{"code":200,"data":{"hasClub":false,"rows":[]}}"# : scenario == .empty ? #"{"code":200,"data":{"hasClub":true,"rows":[]}}"# : CooperationSyntheticFixtures.poolJSON)
    }
    func candidates(topicID: Int) async throws -> CooperationCandidates {
        try await check()
        if scenario == .forbidden { throw CooperationReadFailure.forbidden(message: "仅主题发布者可查看候选池") }
        return try decode(scenario == .empty ? #"{"code":200,"data":{"clubApplies":[],"registrations":[]}}"# : CooperationSyntheticFixtures.candidatesJSON)
    }
    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(CooperationFixtureEnvelope<T>.self, from: Data(json.utf8)).data
    }
}
private struct CooperationFixtureEnvelope<T: Decodable>: Decodable { let data: T }

@MainActor struct CooperationFixtureHostView: View {
    @StateObject private var reader: CooperationFixtureReader
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-cooperation-scenario")
        let raw = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        _reader = StateObject(wrappedValue: CooperationFixtureReader(scenario: raw.flatMap(CooperationFixtureReader.Scenario.init(rawValue:)) ?? .content))
    }
    var body: some View {
        Group {
            switch reader.scenario {
            case .forbidden: NavigationStack { CooperationCandidatesView(topicID: 301, reader: reader) }
            case .noClub: NavigationStack { CooperationPoolView(reader: reader) }
            case .unavailable, .refreshed: NavigationStack { CooperationInviteDetailView(key: CooperationInviteKey(id: 71, direction: .received), reader: reader) }
            default: CooperationBrowserView(reader: reader)
            }
        }
        .id(reader.scope)
        .safeAreaInset(edge: .bottom) {
            if reader.scenario == .sessionChange && reader.isAuthenticated {
                Button("cooperation.fixture.signOut") { reader.signOut() }
                    .accessibilityIdentifier("cooperation.fixture.signOut").padding().background(.regularMaterial)
            }
        }
    }
}
#endif
