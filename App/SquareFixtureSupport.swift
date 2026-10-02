#if DEBUG
import SwiftUI

@MainActor final class SquareFixtureReader: SquareReading {
    enum Scenario: String { case content, empty, failure, unauthorized, unconfigured, unavailable, partial, pageFailure, invalidCursor, delayed }
    let scenario: Scenario
    let scope = UUID()
    var isConfigured: Bool { scenario != .unconfigured }
    var isOfflineExample: Bool { true }
    var isSignedIn: Bool { false }
    private var feedPageFailed = false
    private var commentsFailed = false
    init(scenario: Scenario = .content) { self.scenario = scenario }
    private func check() async throws {
        if scenario == .delayed { try await Task.sleep(nanoseconds: 700_000_000) }
        switch scenario {
        case .failure: throw APIError.httpStatus(503)
        case .unauthorized: throw APIError.unauthorized
        case .unconfigured: throw APIError.notConfigured
        default: break
        }
    }
    func squareFeed(query: SquareQuery, cursor: SquareCursor?) async throws -> SquareFeedPage {
        try await check()
        if query.mode.requiresAccount { throw SquareReadFailure.signInRequired }
        if query.mode == .nearby && (query.cityCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw SquareReadFailure.cityRequired }
        if scenario == .pageFailure && cursor != nil && !feedPageFailed { feedPageFailed = true; throw APIError.httpStatus(503) }
        if scenario == .empty || query.keyword?.lowercased() == "missing" { return .init(items: [], hasMore: false) }
        let items = try (cursor == nil ? [701, 702] : [702, 703]).map { try SquareSyntheticFixtures.post(id: $0).qualified(as: .communityV1) }
        return .init(items: items, hasMore: cursor == nil,
                     nextCursor: scenario == .invalidCursor ? nil : (cursor == nil ? SquareCursor(id: 702, score: 10) : nil))
    }
    func squareDetail(route: SquareContentRoute) async throws -> SquarePost {
        let value = try await squareDetail(id: route.id)
        return value.qualified(as: route.generation)
    }
    func squareComments(route: SquareContentRoute, pageNumber: Int) async throws -> SquareCommentPage {
        let value = try await squareComments(postID: route.id, pageNumber: pageNumber)
        return .init(items: value.items.map { $0.qualified(as: route.generation) }, pageNumber: value.pageNumber, pageSize: value.pageSize, hasMore: value.hasMore)
    }
    func squareDetail(id: Int) async throws -> SquarePost {
        try await check()
        if scenario == .unavailable { throw SquareReadFailure.server(code: 404, message: "Synthetic unavailable post / 示例内容不可用") }
        return try SquareSyntheticFixtures.post(id: id)
    }
    func squareComments(postID: Int, pageNumber: Int) async throws -> SquareCommentPage {
        try await check()
        if scenario == .partial && !commentsFailed { commentsFailed = true; throw APIError.httpStatus(503) }
        if scenario == .empty { return .init(items: [], pageNumber: pageNumber) }
        let all = try SquareSyntheticFixtures.comments()
        // Small pages are fixture-only; the real reader always sends the source pageSize 50.
        return .init(items: pageNumber == 1 ? Array(all.prefix(2)) : [all[1], all[2]], pageNumber: pageNumber, pageSize: pageNumber == 1 ? 2 : 50)
    }
}
@MainActor struct SquareFixtureHostView: View {
    @State private var reader: SquareFixtureReader
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-square-scenario")
        let value = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        _reader = State(initialValue: SquareFixtureReader(scenario: value.flatMap(SquareFixtureReader.Scenario.init(rawValue:)) ?? .content))
    }
    var body: some View {
        if reader.scenario == .unavailable || reader.scenario == .partial {
            NavigationStack { SquareDetailView(id: 701, reader: reader) }
        } else { SquareBrowserView(reader: reader) }
    }
}
#endif
