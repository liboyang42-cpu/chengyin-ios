#if DEBUG
import SwiftUI

@MainActor private final class ShopNPCFixtureHTTP: ShopNPCHTTPTransport {
    func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--reference-npc-unknown") { throw ShopNPCFailure.unknownOutcome }
        if args.contains("--reference-npc-failed") { throw ShopNPCFailure.server(code: 503, message: "Synthetic failure / 测试失败") }
        if args.contains("--reference-npc-pending") { try await Task.sleep(for: .seconds(30)) }
        return .init(status: 200, body: Data(#"{"code":200,"data":{"text":"Fixture reply / 测试回答"},"asr":"Fixture question / 测试问题"}"#.utf8))
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
    var body: some View {
        NavigationStack {
            ShopNPCView(coordinator: coordinator, name: "Fixture NPC", greeting: nil)
                .toolbar {
                    if ProcessInfo.processInfo.arguments.contains("--reference-npc-scope-control") {
                        Button("Invalidate fixture scope") { coordinator.invalidate() }
                            .accessibilityIdentifier("referenceNPC.invalidate")
                    }
                }
        }
        .modifier(AccessibilityFixtureOptions())
        .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--uitesting-max-text") ? .accessibility5 : .large)
    }
}
#endif
