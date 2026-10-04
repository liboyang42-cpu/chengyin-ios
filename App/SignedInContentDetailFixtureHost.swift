#if DEBUG
import SwiftUI

/// Synthetic transport through the normal composition and normal Home/Activities destinations.
/// No production endpoint, vault, permission, registration or runtime approval is supplied.
@MainActor struct SignedInContentDetailFixtureHost: View {
    @StateObject private var session: AppSession
    @StateObject private var wire: SignedInContentDetailFixtureWire
    @State private var ready = false
    private let guest: Bool
    init() {
        let args = ProcessInfo.processInfo.arguments
        guest = args.contains("--content-detail-guest")
        let wire = SignedInContentDetailFixtureWire()
        let deployment = try! ReviewedAppDeployment(market: .china, baseURL: "https://example.test/native",
            approvedBaseURLs: [.china: ["https://example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.questify.content-details", realm: "synthetic", reads: [.homeAndSearch],
            contentDetails: args.contains("--content-detail-unapproved") ? nil : .activityAndTopic)
        let vault = SignedInContentDetailFixtureVault()
        let defaults = UserDefaults(suiteName: "content-detail-fixture-" + UUID().uuidString)!
        let root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
        _session = StateObject(wrappedValue: root.makeSession())
        _wire = StateObject(wrappedValue: wire)
    }
    var body: some View {
        Group {
            if ready {
                TabView {
                    SessionHomeFeedView().environmentObject(session)
                        .tabItem { Text("homeFeed.title") }
                    ActivityBrowserView(reader: session)
                        .tabItem { Text("activity.browse") }
                }
            } else { ProgressView() }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(verbatim: String(wire.detailRequests)).accessibilityIdentifier("contentDetail.fixture.requests")
                Text(verbatim: session.isSignedIn ? "signed-in" : "guest").accessibilityIdentifier("contentDetail.fixture.identity")
                if wire.isPaused {
                    Button { wire.finishDelayedUnauthorized() } label: { Text(verbatim: "Release 401") }
                        .accessibilityIdentifier("contentDetail.fixture.release401")
                }
                Button { Task { await session.logout() } } label: { Text(verbatim: "Sign out") }
                    .accessibilityIdentifier("contentDetail.fixture.signOut")
                Button {
                    Task {
                        wire.role = wire.role == "player" ? "merchant" : "player"
                        await session.refreshOwnAccount()
                    }
                } label: { Text(verbatim: "Role") }
                    .accessibilityIdentifier("contentDetail.fixture.role")
            }.font(.caption)
        }
        .task {
            if !guest { await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456") }
            ready = true
        }
    }
}
@MainActor private final class SignedInContentDetailFixtureVault: AppTokenStorage {
    private var token: String?
    func read() throws -> String? { token }
    func write(_ token: String) throws { self.token = token }
    func clear() throws { token = nil }
}
@MainActor private final class SignedInContentDetailFixtureWire: ObservableObject, HTTPTransport {
    @Published private(set) var detailRequests = 0
    var role = "player"
    private var failed = false
    private var didPause = false
    @Published private(set) var isPaused = false
    private var pending: CheckedContinuation<(Data, Int), Error>?
    func finishDelayedUnauthorized() {
        let continuation = pending; pending = nil; isPaused = false
        continuation?.resume(returning: (Data(#"{"code":401}"#.utf8), 200))
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let args = ProcessInfo.processInfo.arguments, path = request.url!.path
        let json: String
        if path.hasSuffix("/phone") { json = "{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}" }
        else if path.hasSuffix("/userInfo") { json = "{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}" }
        else if path.hasSuffix("/topic/list") { json = #"{"code":200,"data":{"rows":[{"id":31,"name":"Synthetic route card"}]}}"# }
        else if path.hasSuffix("/activity/list") { json = #"{"code":200,"data":{"rows":[{"id":21,"name":"Synthetic activity card"}]}}"# }
        else if path.hasSuffix("/topic/info-to-user") || path.hasSuffix("/activity/info") {
            if path.hasSuffix("/topic/info-to-user"), args.contains("--content-detail-topic-failure") { throw APIError.httpStatus(503) }
            detailRequests += 1
            if (args.contains("--content-detail-fail-once") || args.contains("--content-detail-pause-retry")), !failed {
                failed = true; return (Data(), 503)
            }
            if args.contains("--content-detail-pause-retry"), !didPause {
                didPause = true
                return try await withCheckedThrowingContinuation { pending = $0; isPaused = true }
            }
            if args.contains("--content-detail-forbidden") { return (Data(#"{"code":403}"#.utf8), 403) }
            if path.hasSuffix("/activity/info") {
                if args.contains("--content-detail-club-gate") { json = #"{"code":200,"data":{"gate":true,"clubId":9,"message":"Join the synthetic club first","activityName":"Summary only"}}"# }
                else { json = #"{"code":200,"data":{"id":21,"name":"Synthetic activity detail","description":"Read-only content","topicId":31,"omsTicketList":[]}}"# }
            } else {
                let shelf = args.contains("--content-detail-unknown-shelf") ? "null" : args.contains("--content-detail-empty-shelf") ? "[]" : #"[{"id":21,"name":"Synthetic available walk","addressName":"Synthetic square"}]"#
                let name = role == "merchant" ? "Synthetic merchant route" : "Synthetic route detail"
                json = "{\"code\":200,\"data\":{\"id\":31,\"name\":\"\(name)\",\"activityList\":\(shelf)}}"
            }
        } else { json = #"{"code":200,"data":[]}"# }
        return (Data(json.utf8), 200)
    }
}
#endif
