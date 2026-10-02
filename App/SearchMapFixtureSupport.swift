#if DEBUG
import SwiftUI

@MainActor final class SearchMapFixtureReader: SearchMapReading {
    enum Scenario: String { case content, empty, partial, guest, failure, retry, unauthorized, unconfigured, delayed, cityFallback }
    let scenario: Scenario
    var scope = UUID()
    var isAuthenticated: Bool
    var isConfigured: Bool { scenario != .unconfigured }
    var isOfflineExample: Bool { true }
    private var searches = 0
    init(scenario: Scenario = .content) { self.scenario = scenario; isAuthenticated = scenario != .guest }
    func becomeGuest() { isAuthenticated = false; scope = UUID() }
    func switchAccount() { isAuthenticated = true; scope = UUID() }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    private func check() throws {
        if !isConfigured { throw APIError.notConfigured }
        if scenario == .failure { throw APIError.httpStatus(503) }
        if scenario == .unauthorized { throw APIError.unauthorized }
    }
    func categories() async throws -> [DiscoveryCategory] { try check(); return try decode([DiscoveryCategory].self, SearchMapSyntheticFixtures.categories) }
    func search(_ query: GlobalSearchQuery) async throws -> GlobalSearchResults {
        try check(); try query.validate(); searches += 1
        if scenario == .retry && searches == 1 { throw APIError.httpStatus(503) }
        if scenario == .delayed { try await Task.sleep(for: .milliseconds(query.keyword == "old" ? 1500 : 30)) }
        if scenario == .empty || query.keyword == "missing" { return GlobalSearchResults(rows: []) }
        let kinds = GlobalSearchKind.allCases.filter { (isAuthenticated || $0 != .club) && (scenario != .partial || $0 != .merchant) }
        let rows = kinds.map { kind in GlobalSearchRow(kind: kind, sourceID: 71, title: "Synthetic \(kind.rawValue)", detail: "Offline \(query.keyword)") }
        return GlobalSearchResults(rows: rows, failedKinds: scenario == .partial ? [.merchant] : [], gatedKinds: isAuthenticated ? [] : [.club])
    }
    func citySearch(_ query: CityNodeSearchQuery) async throws -> CityNodeSearchResults {
        try check()
        if scenario == .empty { return CityNodeSearchResults(activities: [], nodes: []) }
        let activities = try decode([ActivitySummary].self, SearchMapSyntheticFixtures.activities).filter {
            query.filter.matches(kind: .activity, date: $0.startDate, price: $0.minimumAmount.map { NSDecimalNumber(decimal: $0).doubleValue })
        }
        return CityNodeSearchResults(activities: activities,
            nodes: isAuthenticated && scenario != .partial ? try decode([SearchMapCityNode].self, SearchMapSyntheticFixtures.cityNodes) : [],
            nodeFailure: !isAuthenticated ? .unauthorized : (scenario == .partial ? .unavailable : nil))
    }
    func nearby(area: RoamSearchArea) async throws -> SearchMapNearbyResults {
        try check()
        return SearchMapNearbyResults(nodes: scenario == .empty ? [] : try decode([RoamRouteNode].self, SearchMapSyntheticFixtures.nearby),
            city: scenario == .cityFallback ? .init(manualInputRequired: true, reason: "MAP_RATE_LIMITED") : .init(city: "Synthetic city"))
    }
    func cityNode(id: Int) async throws -> SearchMapCityNode {
        try check(); guard isAuthenticated else { throw APIError.unauthorized }
        let values = try decode([SearchMapCityNode].self, SearchMapSyntheticFixtures.cityNodes)
        guard let node = values.first(where: { $0.id == id }) else { throw APIError.malformedResponse }; return node
    }
    func merchant(id: Int) async throws -> RoamMerchantDetail {
        try check(); let value = try decode(RoamMerchantDetail.self, SearchMapSyntheticFixtures.merchant)
        guard value.merchant.id == id else { throw APIError.malformedResponse }; return value
    }
}
@MainActor struct SearchMapFixtureHostView: View {
    @State private var reader: SearchMapFixtureReader
    @State private var scope: UUID
    private let entry: String
    @State private var walking: WalkingNavigationFixtureSupport
    init() {
        let args = ProcessInfo.processInfo.arguments
        func argument(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }; return args[i + 1]
        }
        let value = SearchMapFixtureReader(scenario: argument("--uitesting-search-map-scenario").flatMap(SearchMapFixtureReader.Scenario.init(rawValue:)) ?? .content)
        _reader = State(initialValue: value); _scope = State(initialValue: value.scope)
        entry = argument("--uitesting-search-map-entry") ?? "global"
        _walking = State(initialValue: WalkingNavigationFixtureSupport(scenario: argument("--uitesting-walking-scenario") ?? "content"))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("searchMap.fixtureGuest") { reader.becomeGuest(); walking.context = nil; scope = reader.scope }.accessibilityIdentifier("searchMap.fixture.guest")
                Button("searchMap.fixtureAccount") { reader.switchAccount(); walking.context = nil; scope = reader.scope }.accessibilityIdentifier("searchMap.fixture.account")
            }.buttonStyle(.bordered).frame(minHeight: 44)
            NavigationStack {
                if entry == "city" {
                    SearchMapExplorerView(reader: reader, mode: .city, initialArea: syntheticArea, destination: detail)
                } else if entry == "nearby" {
                    SearchMapExplorerView(reader: reader, mode: .nearby, initialArea: syntheticArea, destination: detail)
                } else if entry == "walking" {
                    SearchRoutePreviewView(origin: syntheticArea.coordinate, destination: RoamCoordinate(latitude: 1.004, longitude: 1.006)!, name: "Synthetic stop", scope: reader.scope,
                        navigationReference: try? WalkingTargetReference(kind: .cityNode, id: 71), offline: true)
                        .environment(\.walkingNavigationFactory, walking.factory)
                } else if entry == "route" {
                    SearchRoutePreviewView(origin: syntheticArea.coordinate, destination: RoamCoordinate(latitude: 1.004, longitude: 1.006)!, name: "Synthetic stop", scope: reader.scope, offline: true)
                } else {
                    GlobalSearchView(reader: reader, destination: detail)
                }
            }.id(scope)
        }
    }
    private var syntheticArea: RoamSearchArea { RoamSearchArea(coordinate: RoamCoordinate(latitude: 1, longitude: 1)!, label: "Synthetic area") }
    @ViewBuilder private func detail(_ destination: SearchMapDestination) -> some View {
        switch destination {
        case .topic(let id): TopicDetailView(id: id, reader: TopicFixtureReader())
        case .merchant(let id): SearchMapMerchantDetailView(id: id, reader: reader)
        case .cityNode(let id): Text(verbatim: "Synthetic city node \(id)")
        case .activity(let id): Text(verbatim: "Synthetic activity \(id)").accessibilityIdentifier("searchMap.destination.activity.\(id)")
        case .club(let id): Text(verbatim: "Synthetic club \(id)").accessibilityIdentifier("searchMap.destination.club.\(id)")
        }
    }
}
#endif
