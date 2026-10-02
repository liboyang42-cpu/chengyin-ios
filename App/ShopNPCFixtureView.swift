#if DEBUG
import SwiftUI

@MainActor private final class ShopNPCFixtureHTTP: ShopNPCHTTPTransport {
    func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse {
        .init(status: 200, body: Data(#"{"code":200,"data":{"text":"Fixture reply / 测试回答"},"asr":"Fixture question / 测试问题"}"#.utf8))
    }
}
/// In-memory fixtures only. Never connected to application credentials, recording, or network.
@MainActor struct ShopNPCFixtureView: View {
    private let coordinator: ShopNPCCoordinator
    init(enabled: Bool = false) {
        var grants = ShopNPCGrants()
        if enabled { grants.server = true; grants.provider = true; grants.legal = true; grants.access = true }
        coordinator = .init(scope: .init(sessionID: "fixture-session", accountID: "fixture-user", roleID: "player", accessRevision: 1, nodeID: ShopNPCNodeID(7)!), grants: grants, client: .init(transport: ShopNPCFixtureHTTP()))
    }
    var body: some View { NavigationStack { ShopNPCView(coordinator: coordinator, name: "Fixture NPC", greeting: nil) } }
}
#endif
