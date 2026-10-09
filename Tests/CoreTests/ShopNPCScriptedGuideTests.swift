import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class ScriptGuideWire: HTTPTransport {
    var calls = 0
    var mode = 1
    var registered = true
    var playable = true
    var node: [String: Any] = ["nodeId": 701, "name": "Synthetic stop", "npc": ["name": "Synthetic guide"],
        "done": false, "arrived": true, "ruleInstructions": "  Read the sign.\nReturn to the task.  ", "requiredMaterials": "Paper",
        "questionAnswer": "SECRET ANSWER", "answerReveal": "SECRET REVEAL", "hint1": "LOCKED HINT", "merchantGuide": "PRIVATE STAFF GUIDE"]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1
        guard request.httpMethod == "GET", request.url?.path == "/api/play/nodes" else { XCTFail("Unexpected operation"); throw APIError.invalidRequest }
        let data: [String: Any] = ["topicId": 71, "mode": mode, "registered": registered, "playable": playable, "total": 1, "doneCount": 0, "nodes": [node]]
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
}
@MainActor private final class ScriptGuideSession {
    var current: PlayExperienceSession? = try! .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token")
}
@available(macOS 14.0, *)
@MainActor final class ShopNPCScriptedGuideTests: XCTestCase {
    private func scope(node: Int = 701, access: UInt64 = 1, account: String = "7") -> ShopNPCScope {
        .init(sessionID: "synthetic:1:activity:41", accountID: account, roleID: "player", accessRevision: access, nodeID: ShopNPCNodeID(node)!)
    }
    private func runtime(_ wire: ScriptGuideWire, session: ScriptGuideSession) throws -> PlayExperienceCoordinator {
        .init(scope: .activity(41), service: .init(configuration: try .init(baseURL: URL(string: "https://synthetic.invalid")!), transport: wire, enabled: [.reads]),
              recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { session.current })
    }
    func testProjectsOnlyReturnedRulesAndMaterialsWithoutNewRequestOrAIGrant() async throws {
        let wire = ScriptGuideWire(), session = ScriptGuideSession(), conversation = scope()
        let runtime = try runtime(wire, session: session); await runtime.load()
        let source = try XCTUnwrap(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 701, conversation: conversation))
        guard case .available(let guide) = source.state(for: conversation) else { return XCTFail() }
        XCTAssertEqual(guide.rules, "  Read the sign.\nReturn to the task.  "); XCTAssertEqual(guide.materials, "Paper")
        XCTAssertEqual(Set(Mirror(reflecting: guide).children.compactMap(\.label)), ["nodeID", "rules", "materials"])
        XCTAssertFalse(ShopNPCGrants().textAllowed); XCTAssertEqual(wire.calls, 1)
        _ = source.state(for: conversation); XCTAssertEqual(wire.calls, 1)
        XCTAssertFalse(runtime.canWrite)
    }
    func testMissingRulesAreExplicitlyMissingRatherThanReplacedByQuestionOrHint() async throws {
        let wire = ScriptGuideWire(), session = ScriptGuideSession(), conversation = scope()
        wire.node.removeValue(forKey: "ruleInstructions"); wire.node["requiredMaterials"] = " \n"
        let runtime = try runtime(wire, session: session); await runtime.load()
        let source = try XCTUnwrap(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 701, conversation: conversation))
        guard case .available(let guide) = source.state(for: conversation) else { return XCTFail() }
        XCTAssertNil(guide.rules); XCTAssertNil(guide.materials); XCTAssertEqual(wire.calls, 1)
    }
    func testLockedHiddenAndUnnamedNodesHaveNoProjection() async throws {
        for variant in 0..<3 {
            let wire = ScriptGuideWire(), session = ScriptGuideSession()
            if variant == 0 { wire.node["locked"] = true }
            else if variant == 1 { wire.node["routeNodeState"] = "HIDDEN" }
            else { wire.node["npc"] = ["name": " "] }
            let runtime = try runtime(wire, session: session); await runtime.load()
            XCTAssertNil(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 701, conversation: scope()))
        }
    }
    func testUnregisteredUnavailableAndUnknownModeCannotCreateGuide() async throws {
        for variant in 0..<3 {
            let wire = ScriptGuideWire(), session = ScriptGuideSession()
            if variant == 0 { wire.registered = false }
            else if variant == 1 { wire.playable = false }
            else { wire.mode = 99 }
            let runtime = try runtime(wire, session: session); await runtime.load()
            XCTAssertNil(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 701, conversation: scope()))
        }
    }
    func testWrongNodeAndChangedConversationBindingFailClosed() async throws {
        let wire = ScriptGuideWire(), session = ScriptGuideSession(), conversation = scope()
        let runtime = try runtime(wire, session: session); await runtime.load()
        XCTAssertNil(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 702, conversation: conversation))
        let source = try XCTUnwrap(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 701, conversation: conversation))
        for next in [scope(node: 702), scope(access: 2), scope(account: "8")] { XCTAssertEqual(source.state(for: next), .unavailable) }
    }
    func testRefreshCannotSilentlySubstituteNewOrIdenticalRulesInAnOpenGuide() async throws {
        let wire = ScriptGuideWire(), session = ScriptGuideSession(), conversation = scope()
        let runtime = try runtime(wire, session: session); await runtime.load()
        let source = try XCTUnwrap(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 701, conversation: conversation))
        await runtime.load(); XCTAssertEqual(source.state(for: conversation), .unavailable)
        let fresh = try XCTUnwrap(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 701, conversation: conversation))
        wire.node["ruleInstructions"] = "New rules"; await runtime.load()
        XCTAssertEqual(fresh.state(for: conversation), .unavailable)
    }
    func testSignOutEpochChangeAndRetirementHideRules() async throws {
        for variant in 0..<3 {
            let wire = ScriptGuideWire(), session = ScriptGuideSession(), conversation = scope()
            let runtime = try runtime(wire, session: session); await runtime.load()
            let source = try XCTUnwrap(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 701, conversation: conversation))
            if variant == 0 { session.current = nil }
            else if variant == 1 { session.current = try .init(accountID: 7, epoch: 2, namespace: "synthetic", token: "next-token") }
            else { source.retire() }
            XCTAssertEqual(source.state(for: conversation), .unavailable)
        }
    }
    func testNativeCapacityLimitNeverTruncatesIntoApparentlyCompleteRules() async throws {
        let wire = ScriptGuideWire(), session = ScriptGuideSession(), conversation = scope()
        wire.node["ruleInstructions"] = String(repeating: "x", count: 65_537)
        let runtime = try runtime(wire, session: session); await runtime.load()
        let source = try XCTUnwrap(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 701, conversation: conversation))
        XCTAssertEqual(source.state(for: conversation), .tooLarge)
    }
    func testBothExistingPlayModesUseTheSameReadOnlyProjection() async throws {
        for mode in [1, 2] {
            let wire = ScriptGuideWire(), session = ScriptGuideSession(), conversation = scope(); wire.mode = mode
            let runtime = try runtime(wire, session: session); await runtime.load()
            let source = try XCTUnwrap(ShopNPCScriptedGuideSource(runtime: runtime, nodeID: 701, conversation: conversation))
            guard case .available = source.state(for: conversation) else { return XCTFail() }
            XCTAssertEqual(wire.calls, 1); XCTAssertFalse(runtime.canWrite)
        }
    }
}
