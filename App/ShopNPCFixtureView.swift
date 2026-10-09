#if DEBUG
import SwiftUI

@MainActor private final class ShopNPCFixtureHTTP: ShopNPCHTTPTransport {
    func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--reference-npc-unknown") { throw ShopNPCFailure.unknownOutcome }
        if args.contains("--reference-npc-failed") {
            // A known rejection arrives in a decoded response. Thrown transport failures
            // intentionally remain unknown outcomes in the shipping HTTP client.
            return .init(status: 200, body: Data(#"{"code":503,"msg":"Synthetic failure / 测试失败"}"#.utf8))
        }
        if args.contains("--reference-npc-pending") { try await Task.sleep(for: .seconds(30)) }
        let id = try fixtureRequestID(request.body)
        return .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["code": 200,
            "data": ["requestId": id, "outcomeStatus": "SUCCEEDED", "safetyDecision": "PASS", "retryable": false,
                     "safeText": "Fixture reply / 测试回答"], "asr": "Fixture question / 测试问题"]))
    }

    // Synthetic 9b success replies echo the exact text/multipart request ID.
    private func fixtureRequestID(_ bytes: Data) throws -> String {
        if let body = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], let id = body["requestId"] as? String { return id }
        let marker = "name=\"requestId\"\r\n\r\n"
        let tail = String(decoding: bytes, as: UTF8.self).components(separatedBy: marker)
        guard tail.count == 2, let id = tail.last?.components(separatedBy: "\r\n").first, UUID(uuidString: id) != nil else { throw ShopNPCFailure.invalid }
        return id
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
