import XCTest
@testable import Questify

private final class ScriptGuideAppRead: HTTPTransport {
    var calls = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1
        return (Data(#"{"code":200,"data":{"topicId":71,"mode":2,"registered":true,"playable":true,"total":1,"doneCount":0,"nodes":[{"nodeId":701,"npc":{"name":"Synthetic guide"},"ruleInstructions":"Synthetic public rules","requiredMaterials":"Paper","done":false}]}}"#.utf8), 200)
    }
}
@MainActor private final class ScriptGuideAppChat: ShopNPCHTTPTransport {
    var calls = 0
    func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse { calls += 1; XCTFail(); throw ShopNPCFailure.disabled }
    func validateResume(scope: ShopNPCScope, grants: ShopNPCGrants) throws {}
}
@MainActor final class ShopNPCScriptedGuideAppTests: XCTestCase {
    private func setup() async throws -> (PlayExperienceCoordinator, ShopNPCScriptedGuideSource, ShopNPCCoordinator, ScriptGuideAppChat) {
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token")
        let runtime = PlayExperienceCoordinator(scope: .activity(41), service: .init(configuration: try .init(baseURL: URL(string: "https://synthetic.invalid")!), transport: ScriptGuideAppRead(), enabled: [.reads]), recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { session })
        await runtime.load()
        let scope = ShopNPCScope(sessionID: "synthetic:1:activity:41", accountID: "7", roleID: "player", accessRevision: 1, nodeID: ShopNPCNodeID(701)!)
        let chat = ScriptGuideAppChat()
        let actual = ShopNPCCoordinator(scope: scope, client: .init(transport: chat))
        return (runtime, try XCTUnwrap(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 701, conversation: scope)), actual, chat)
    }
    func testNoAIGrantsStillAllowsCurrentSourceRulesWithoutChatCalls() async throws {
        let (runtime, source, coordinator, chat) = try await setup()
        XCTAssertFalse(coordinator.grants.textAllowed)
        guard case .available(let guide)? = ShopNPCScriptedGuidePresentation.state(source: source, coordinator: coordinator) else { return XCTFail() }
        XCTAssertEqual(guide.rules, "Synthetic public rules"); XCTAssertEqual(chat.calls, 0); XCTAssertFalse(runtime.canWrite)
    }
    func testBackgroundSuspensionAndInvalidationHideTheGuide() async throws {
        let (runtime, source, coordinator, chat) = try await setup()
        coordinator.suspend(); XCTAssertNil(ShopNPCScriptedGuidePresentation.state(source: source, coordinator: coordinator))
        coordinator.resumeAfterInterruption(); XCTAssertNotNil(ShopNPCScriptedGuidePresentation.state(source: source, coordinator: coordinator))
        coordinator.invalidate(); XCTAssertNil(ShopNPCScriptedGuidePresentation.state(source: source, coordinator: coordinator))
        XCTAssertEqual(chat.calls, 0); XCTAssertNotNil(runtime.snapshot)
    }
    func testChangedReadContextNeverDisplaysTheOldRuleText() async throws {
        let (runtime, source, coordinator, chat) = try await setup()
        await runtime.load()
        XCTAssertEqual(ShopNPCScriptedGuidePresentation.state(source: source, coordinator: coordinator), .unavailable)
        XCTAssertEqual(chat.calls, 0)
    }
}
