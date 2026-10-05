#if DEBUG
import SwiftUI

/// Synthetic-only public-reader fixtures. This host never installs write or media grants.
@MainActor struct PublicMerchantReviewFilterFixtureView: View {
    @State private var state: PublicMerchantReviewFilterFixtureState
    init(scenario: String) { _state = State(initialValue: .init(scenario: scenario)) }
    var body: some View {
        let configuration = try! APIConfiguration(baseURL: URL(string: "https://example.com/")!)
        let session = try! PublicMerchantReviewSession(accountID: state.accountID, scope: state.scope,
                                                       realm: configuration.baseURL.absoluteString, token: "synthetic-token-\(state.accountID)")
        let reader = PublicMerchantReviewHTTPReader(configuration: configuration,
            transport: PublicMerchantReviewFilterFixtureTransport(state: state), scope: state.scope,
            isOfflineExample: true, session: session)
        PublicMerchantReviewsView(target: .init(merchantRowID: PublicMerchantRowID(state.merchantID)!,
            ownerMemberID: PublicMerchantOwnerID(state.merchantID + 100)!), reader: reader)
            .safeAreaInset(edge: .bottom) {
                Text(verbatim: "Reads: \(state.reads); completed: \(state.completed); account: \(state.accountID)")
                    .font(.caption).accessibilityIdentifier("publicReview.fixture.reads")
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu("Fixture controls") {
                        Button("Switch account") { state.accountID += 1; state.scope = UUID() }
                            .accessibilityIdentifier("publicReview.fixture.account")
                        Button("Switch merchant") { state.merchantID += 1 }
                            .accessibilityIdentifier("publicReview.fixture.merchant")
                        Button("Finish old read") { state.finishPending() }
                            .accessibilityIdentifier("publicReview.fixture.finish")
                    }.accessibilityIdentifier("publicReview.fixture.controls")
                    NavigationLink("Fixture detail") { Text("Synthetic detail").accessibilityIdentifier("publicReview.fixture.detail") }
                        .accessibilityIdentifier("publicReview.fixture.openDetail")
                }
            }
    }
}

@MainActor @Observable private final class PublicMerchantReviewFilterFixtureState {
    let scenario: String
    var scope = UUID()
    var accountID = 8
    var merchantID = 73
    var reads = 0
    var completed = 0
    private var secondPageAttempts = 0
    private var pending: CheckedContinuation<Void, Never>?
    init(scenario: String) { self.scenario = scenario }
    func finishPending() { let value = pending; pending = nil; value?.resume() }
    func response(_ request: URLRequest) async throws -> (Data, Int) {
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
        let fields = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        guard request.url?.path == "/api/merchant/reviews/public", request.httpMethod == "POST",
              request.httpBody == nil, fields.count == 3, fields["pageSize"] == "20",
              let page = Int(fields["pageNum"] ?? ""), let merchant = Int(fields["merchantRowId"] ?? "") else {
            throw PublicMerchantHomeFailure.invalid
        }
        let account = accountID
        reads += 1
        defer { completed += 1 }
        if page == 2 {
            secondPageAttempts += 1
            if scenario == "reviews-retry", secondPageAttempts == 1 { return (Data(), 503) }
            if scenario == "reviews-late401", account == 8 {
                // Intentionally ignores cancellation to test the view's existing generation fence.
                await withCheckedContinuation { pending = $0 }
                return (Data(), 401)
            }
        }
        let empty = scenario == "reviews-empty"
        let changed = account != 8 || merchant != 73
        let identifiers: [Int] = empty ? [] : changed ? [101] : page == 1 ? Array(1...20) : [21, 22]
        let rows: [[String: Any]] = identifiers.map { id in
            let low = !changed && (id == 2 || id == 21) && scenario != "reviews-retry"
            let photo = !changed && (id == 3 || id == 21) && (scenario != "reviews-retry" || page == 2)
            return ["id": id, "rating": low ? 3 : 5, "content": "Synthetic public review \(id)",
                "imageUrls": photo ? ["https://example.com/review-\(id).jpg"] : [],
                "authorNickname": "Synthetic author \(id)", "verifiedRedemption": false,
                "status": "VISIBLE", "version": id, "canReply": false, "canReport": true]
        }
        let total = empty ? 0 : changed ? 1 : 22
        let data: [String: Any] = ["mode": "public", "pageNum": page, "pageSize": 20,
            "total": total, "hasMore": !empty && !changed && page == 1,
            "averageRating": empty ? NSNull() : 4.7 as Any,
            "eligibility": ["canCreate": false, "reasonCode": "LOGIN_REQUIRED", "registrationId": NSNull()],
            "items": rows]
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
}

private final class PublicMerchantReviewFilterFixtureTransport: HTTPTransport {
    private let state: PublicMerchantReviewFilterFixtureState
    init(state: PublicMerchantReviewFilterFixtureState) { self.state = state }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await state.response(request) }
}
#endif
