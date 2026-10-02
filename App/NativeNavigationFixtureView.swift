#if DEBUG
import SwiftUI

/// Original synthetic acceptance harness. It never constructs a production session,
/// talks to a server, captures a device, or creates a redeemable coupon.
@MainActor struct NativeNavigationFixtureView: View {
    let mode: String
    @State private var coupon: CouponCodeCoordinator?
    @State private var player: PlayPlayerGameCoordinator?
    private let teams = try? TeamFixtureEnvironment(scenario: .invitation)
    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case "coupon": if let coupon { CouponCodeView(model: coupon) }
                case "player": if let player { PlayPlayerSessionView(model: player) }
                case "badge": ObjectBadgeWallView(reader: ProfileFixtureReader(.success))
                case "team":
                    if let teams { TeamHomeView(coordinator: teams.makeCoordinator(), makeCoordinator: teams.makeCoordinator) }
                default: NativeRouteErrorView(failure: .unsupported, goHome: {})
                }
            }
        }.task {
            if mode == "coupon", coupon == nil, let owner = try? CouponCodeSession(accountID: 1, epoch: 1, namespace: "synthetic", role: "player", token: "synthetic-token") {
                coupon = CouponCodeCoordinator(historyID: 71, service: NativeNavigationCouponFixtureService(), currentSession: { owner })
            }
            if mode == "player", player == nil,
               let owner = try? PlayExperienceSession(accountID: 1, epoch: 1, namespace: "synthetic", token: "synthetic-token"),
               let configuration = try? APIConfiguration(baseURL: URL(string: "https://example.test")!) {
                player = PlayPlayerGameCoordinator(activityID: 41,
                    service: PlayExperienceService(configuration: configuration, transport: NativeNavigationPlayerFixtureTransport(), enabled: [.reads]), currentSession: { owner })
            }
        }
    }
}
@MainActor private struct NativeNavigationCouponFixtureService: CouponCodeServing {
    let enabled = true
    func issue(historyID: Int, session: CouponCodeSession) async throws -> CouponCodeReceipt {
        try JSONDecoder().decode(CouponCodeReceipt.self, from: Data(#"{"useStatus":0,"expiresIn":60,"token":"SYNTHETIC-NOT-REDEEMABLE","couponName":"Synthetic coupon","description":"Offline preview only"}"#.utf8))
    }
    func status(historyID: Int, session: CouponCodeSession) async throws -> OrderCouponStatus {
        try JSONDecoder().decode(OrderCouponStatus.self, from: Data(#"{"useStatus":0}"#.utf8))
    }
    func image(_ receipt: CouponCodeReceipt) async throws -> Data { throw CouponCodeFailure.mediaUnavailable }
}
private struct NativeNavigationPlayerFixtureTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard request.httpMethod == "GET" else { throw PlayExperienceError.disabled }
        let source = PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "\"inputType\":\"TEXT\"", with: "\"inputType\":\"SCAN\"")
        return (PlayExperienceSyntheticFixtures.envelope(source), 200)
    }
}
#endif
