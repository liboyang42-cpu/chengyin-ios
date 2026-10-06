#if DEBUG
import SwiftUI

@MainActor final class AccountCollectionFixtureReader: AccountCollectionReading {
    enum Scenario: String {
        case content, empty, failure, couponFailure, favoriteFailure, pageFailure
        case unauthorized, unconfigured, guest, unavailable, refreshed, sessionChange, codePresentation, postFailure, postPageFailure
    }
    let scenario: Scenario
    private(set) var scope = UUID()
    private(set) var isAuthenticated: Bool
    var isConfigured: Bool { scenario != .unconfigured }
    var isOfflineExample: Bool { true }
    private var pageFailed = false
    private var postPageFailed = false
    private var detailReads = 0
    init(scenario: Scenario = .content) { self.scenario = scenario; isAuthenticated = scenario != .guest }
    func signOut() { isAuthenticated = false; scope = UUID() }
    private func check() throws {
        guard isAuthenticated else { throw APIError.unauthorized }
        switch scenario {
        case .failure: throw APIError.httpStatus(503)
        case .unauthorized: throw APIError.unauthorized
        case .unconfigured: throw APIError.notConfigured
        default: break
        }
    }
    func favoriteTopics(pageNumber: Int, pageSize: Int) async throws -> TopicPage {
        try check()
        if scenario == .favoriteFailure { throw AccountCollectionReadFailure.rejected(code: 500, message: "Sample favorites source unavailable") }
        if scenario == .pageFailure, pageNumber > 1, !pageFailed {
            pageFailed = true
            throw AccountCollectionReadFailure.rejected(code: 500, message: "Sample next page unavailable")
        }
        let ids = scenario == .empty || pageNumber > 2 ? [] : pageNumber == 1 ? Array(301..<(301 + pageSize)) : [301, 301 + pageSize]
        let rows = try ids.map { id in
            try JSONDecoder().decode(TopicSummary.self, from: Data("{\"id\":\(id),\"name\":\"Sample favorite route \(id)\",\"addressName\":\"Sample waterfront\"}".utf8))
        }
        return TopicPage(rows: rows, pageNumber: pageNumber, pageSize: pageSize)
    }
    func favoritePosts(pageNumber: Int, pageSize: Int) async throws -> AccountCollectionPostPage {
        try check()
        if scenario == .postFailure { throw AccountCollectionReadFailure.rejected(code: 500, message: "Sample saved posts unavailable") }
        if scenario == .postPageFailure, pageNumber > 1, !postPageFailed {
            postPageFailed = true
            throw AccountCollectionReadFailure.rejected(code: 500, message: "Sample saved post page unavailable")
        }
        let ids = scenario == .empty || pageNumber > 2 ? [] : pageNumber == 1 ? Array(801..<(801 + pageSize)) : [801, 801 + pageSize]
        return try AccountCollectionPostPage(rows: ids.map { try SquareSyntheticFixtures.post(id: $0).qualified(as: .legacySquare) }, pageNumber: pageNumber, pageSize: pageSize)
    }
    func ownedCoupons(keyword: String?) async throws -> [AccountCollectionCoupon] {
        try check()
        if scenario == .couponFailure { throw AccountCollectionReadFailure.rejected(code: 500, message: "Sample coupons source unavailable") }
        if scenario == .empty { return [] }
        struct Envelope: Decodable { let data: [AccountCollectionCoupon] }
        let rows = try JSONDecoder().decode(Envelope.self, from: Data(AccountCollectionSyntheticFixtures.couponsJSON.utf8)).data
        guard let keyword, !keyword.isEmpty else { return rows }
        return rows.filter { ($0.name ?? "").localizedCaseInsensitiveContains(keyword) || ($0.displayDescription ?? "").localizedCaseInsensitiveContains(keyword) }
    }
    func ownedCoupon(id: Int) async throws -> AccountCollectionCoupon {
        try check()
        if scenario == .unavailable { throw AccountCollectionReadFailure.unavailable }
        detailReads += 1
        if scenario == .refreshed, detailReads > 1 {
            return try JSONDecoder().decode(AccountCollectionCoupon.self, from: Data("{\"id\":\(id),\"couponName\":\"Sample invalid after refresh\",\"useStatus\":3}".utf8))
        }
        guard let row = try await ownedCoupons(keyword: nil).first(where: { $0.id == id }) else { throw AccountCollectionReadFailure.unavailable }
        return row
    }
}

@MainActor struct AccountCollectionFixtureHostView: View {
    @State private var reader: AccountCollectionFixtureReader
    @State private var revision = 0
    @State private var codeFixture = AccountCollectionCodeFixture()
    @State private var topicRoute: TopicRoute?
    @State private var postRoute: PostRoute?
    private struct TopicRoute: Identifiable { let id: Int }
    private struct PostRoute: Identifiable { let route: SquareContentRoute; var id: Int { route.id } }
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let index = arguments.firstIndex(of: "--uitesting-account-collection-scenario")
        let raw = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        _reader = State(initialValue: AccountCollectionFixtureReader(scenario: raw.flatMap(AccountCollectionFixtureReader.Scenario.init(rawValue:)) ?? .content))
    }
    private var codeFactory: (@MainActor (Int) -> CouponCodeCoordinator)? {
        guard reader.scenario == .codePresentation else { return nil }
        return { id in
            CouponCodeCoordinator(historyID: id, service: codeFixture, currentSession: {
                reader.isAuthenticated ? codeFixture.owner : nil
            })
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            if reader.scenario == .codePresentation {
                Text(verbatim: String(codeFixture.issues)).accessibilityIdentifier("ownedCoupon.fixture.issueCount")
            }
            if reader.scenario == .sessionChange {
                Button("accountCollection.fixture.signOut") { reader.signOut(); topicRoute = nil; postRoute = nil; revision += 1 }
                    .accessibilityIdentifier("accountCollection.fixture.signOut")
            }
            NavigationStack {
                if reader.scenario == .unavailable || reader.scenario == .refreshed {
                    AccountCollectionCouponDetailView(selection: .init(historyID: 701, ownerScope: reader.scope), reader: reader)
                } else {
                    Form {
                        NavigationLink {
                            AccountCollectionFavoritesView(reader: reader, onOpenTopic: { topicRoute = TopicRoute(id: $0) }, pageSize: 2,
                                                           onOpenPost: { postRoute = PostRoute(route: $0) })
                        } label: { Label("accountCollection.favorites.title", systemImage: "heart") }
                        .accessibilityIdentifier("accountCollection.openFavorites")
                        NavigationLink { AccountCollectionCouponsView(reader: reader) } label: {
                            Label("accountCollection.coupons.title", systemImage: "ticket")
                        }.accessibilityIdentifier("accountCollection.openCoupons")
                    }.appNavigationTitle("accountCollection.title")
                }
            }.id(revision)
                .environment(\.couponCodeFactory, codeFactory)
        }
        .sheet(item: $topicRoute) { route in
            NavigationStack {
                TopicDetailView(id: route.id, reader: TopicFixtureReader())
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { topicRoute = nil } } }
            }
        }
        .sheet(item: $postRoute) { saved in
            NavigationStack {
                SquareDetailView(id: saved.route.id, contentGeneration: saved.route.generation, reader: SquareFixtureReader())
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { postRoute = nil } } }
            }
        }
    }
}
/// Only the explicitly selected offline scenario offers a non-redeemable code fixture.
@MainActor @Observable private final class AccountCollectionCodeFixture: CouponCodeServing {
    let enabled = true
    let owner = try! CouponCodeSession(accountID: 1, epoch: 1, namespace: "synthetic", role: "player", token: "synthetic-token")
    private(set) var issues = 0
    func issue(historyID: Int, session: CouponCodeSession) async throws -> CouponCodeReceipt {
        guard historyID == 701, session == owner else { throw CouponCodeFailure.invalid }
        issues += 1
        return try JSONDecoder().decode(CouponCodeReceipt.self, from: Data(#"{"useStatus":0,"expiresIn":60,"token":"SYNTHETIC-NOT-REDEEMABLE","couponName":"Sample weekend benefit","description":"Offline current merchant terms"}"#.utf8))
    }
    func status(historyID: Int, session: CouponCodeSession) async throws -> OrderCouponStatus {
        guard historyID == 701, session == owner else { throw CouponCodeFailure.invalid }
        return try JSONDecoder().decode(OrderCouponStatus.self, from: Data(#"{"useStatus":0}"#.utf8))
    }
    func image(_ receipt: CouponCodeReceipt) async throws -> Data { throw CouponCodeFailure.mediaUnavailable }
}
#endif
