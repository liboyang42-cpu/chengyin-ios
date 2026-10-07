#if DEBUG
import Foundation

/// Offline inputs for contract, app-host and UI tests. These are not production data.
public enum PlayBranchHistorySyntheticFixtures {
    public static let recorded = #"[{"fromNodeId":701,"toNodeId":702,"edgeId":"same-edge","at":"2026-10-07 08:30:00"},{"fromNodeId":"702","toNodeId":"701","edgeId":"same-edge","at":1791331200000},{"fromNodeId":701,"toNodeId":703,"at":"bad-time"},{"fromNodeId":0,"toNodeId":702}]"#
    public static func route(log: String? = recorded, sessionID: Int = 501, version: Int = 2, mode: String = "BRANCH_GRAPH") -> String {
        let history = log.map { ",\"decisionLog\":" + $0 } ?? ""
        return "{\"routeMode\":\"\(mode)\",\"sessionId\":\(sessionID),\"status\":\"ACTIVE\",\"version\":\(version),\"nodeStates\":{\"701\":\"COMPLETED\",\"702\":\"PLAYABLE\",\"703\":\"HIDDEN\"}\(history)}"
    }
    public static func nodes(route: String) -> String {
        "{\"topicId\":71,\"topicName\":\"Synthetic branch history / 测试分支历史\",\"mode\":1,\"registered\":true,\"playable\":true,\"total\":3,\"doneCount\":1,\"nodes\":[{\"nodeId\":701,\"name\":\"Synthetic courtyard / 测试庭院\",\"done\":true},{\"nodeId\":702,\"name\":\"Synthetic garden / 测试花园\",\"done\":false},{\"nodeId\":703,\"name\":\"SECRET HIDDEN NAME\",\"done\":false}],\"routeState\":\(route)}"
    }
    public static func snapshot(log: String? = recorded, sessionID: Int = 501, version: Int = 2, scope: PlaySessionScope = .activity(41)) throws -> PlaySnapshot {
        let raw = route(log: log, sessionID: sessionID, version: version)
        let result = try JSONDecoder().decode(PlayNodesResult.self, from: Data(nodes(route: raw).utf8))
        let authority = try JSONDecoder().decode(PlayRouteState.self, from: Data(raw.utf8))
        return try PlaySnapshot(scope: scope, result: result, authority: authority)
    }
}
#endif
