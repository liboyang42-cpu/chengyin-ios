import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// New native protocol actions, not aliases for SUBMIT_STEPS or SUBSCRIBE_TIME_WINDOW.
public enum NativePlatformAction: String {
    case issue = "ISSUE_NATIVE_STEP_CHALLENGE"
    case submit = "SUBMIT_NATIVE_STEPS"
}
public struct NativePlatformPending: Equatable {
    public let sessionID: Int
    public let version: Int
    public let key: String
    public let action: NativePlatformAction
    public let payload: [String: PlayWireValue]
    public init(sessionID: Int, version: Int, key: String, action: NativePlatformAction, payload: [String: PlayWireValue]) throws {
        guard sessionID > 0, version >= 0, key.range(of: "^[A-Za-z0-9._:-]{1,64}$", options: .regularExpression) != nil else { throw NativePlatformIssue.invalidContract }
        self.sessionID = sessionID; self.version = version; self.key = key; self.action = action; self.payload = payload
    }
}
@MainActor public protocol NativePlatformServing {
    func action(_ pending: NativePlatformPending) async throws -> PlayAdvancedState
    func timeWindow(activityID: Int, topicID: Int, nodeID: Int) async throws -> NativeTimeWindow
}

/// The caller must supply a RuntimeDependencyTransport with exact route, region,
/// account, role, session epoch and token approvals. Default construction is off.
@MainActor public struct NativePlatformService: NativePlatformServing {
    public static let actionPath = "api/play/advanced/action"
    public static let windowPath = "api/play/advanced/time-window"
    private let service: PlayExperienceService
    private let owner: PlayExperienceSession
    private let current: () -> PlayExperienceSession?
    private let stepsEnabled: Bool
    private let remindersEnabled: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport, owner: PlayExperienceSession,
                stepsEnabled: Bool = false, remindersEnabled: Bool = false, current: @escaping () -> PlayExperienceSession?) {
        self.service = PlayExperienceService(configuration: configuration, transport: transport, enabled: (stepsEnabled || remindersEnabled) ? [.advanced, .reads] : [])
        self.owner = owner; self.current = current; self.stepsEnabled = stepsEnabled; self.remindersEnabled = remindersEnabled
    }
    public func action(_ pending: NativePlatformPending) async throws -> PlayAdvancedState {
        try gate(stepsEnabled)
        let expectedKeys: Set<String> = pending.action == .issue ? ["provider", "deviceKeyId"] :
            ["provider", "deviceKeyId", "challengeId", "dayKey", "sampleStartAt", "sampleEndAt", "cumulativeSteps", "assertion"]
        guard Set(pending.payload.keys) == expectedKeys,
              pending.payload["provider"]?.text == NativeStepChallenge.provider,
              let key = pending.payload["deviceKeyId"]?.text, key.range(of: "^[A-Za-z0-9+/_=-]{1,256}$", options: .regularExpression) != nil else { throw NativePlatformIssue.invalidContract }
        if pending.action == .submit {
            guard let start = pending.payload["sampleStartAt"]?.integer, let end = pending.payload["sampleEndAt"]?.integer,
                  start > 0, end > start, let count = pending.payload["cumulativeSteps"]?.integer, (0...100_000).contains(count),
                  pending.payload["challengeId"]?.text?.isEmpty == false, pending.payload["dayKey"]?.text?.isEmpty == false,
                  let assertion = pending.payload["assertion"]?.text, Data(base64Encoded: assertion) != nil, assertion.count <= 16_384 else { throw NativePlatformIssue.invalidContract }
        }
        let raw = try await service.request(Self.actionPath, json: ["sessionId": .int(pending.sessionID), "version": .int(pending.version),
            "idempotencyKey": .string(pending.key), "action": .string(pending.action.rawValue), "payload": .object(pending.payload)], capability: .advanced, token: owner.token)
        try gate(stepsEnabled)
        let result = try PlayAdvancedState(raw)
        guard result.sessionID == pending.sessionID, result.version > pending.version else { throw NativePlatformIssue.invalidContract }
        return result
    }
    public func timeWindow(activityID: Int, topicID: Int, nodeID: Int) async throws -> NativeTimeWindow {
        try gate(remindersEnabled)
        guard activityID >= 0, topicID > 0, nodeID > 0 else { throw NativePlatformIssue.invalidContract }
        var components = URLComponents(url: service.configuration.baseURL.appendingPathComponent(Self.windowPath), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "activityId", value: String(activityID)), URLQueryItem(name: "nodeId", value: String(nodeID)), URLQueryItem(name: "topicId", value: String(topicID))]
        var request = URLRequest(url: components.url!); request.httpMethod = "GET"; request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(owner.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        try Task.checkCancellation()
        let (bytes, status) = try await service.transport.send(request)
        try Task.checkCancellation(); try gate(remindersEnabled)
        let envelope = try JSONDecoder().decode(PlayWireValue.self, from: bytes)
        if status == 401 || envelope["code"].integer == 401 { throw PlayExperienceError.unauthorized }
        guard (200..<300).contains(status) else { throw NativePlatformIssue.network }
        if envelope["code"].integer == 409, envelope["data"]["reasonCode"].text == "TIME_WINDOW_OPENING_REQUIRED" { throw NativePlatformIssue.openingRequired }
        guard envelope["code"].integer == 200 else { throw NativePlatformIssue.network }
        let raw = envelope["data"]
        try gate(remindersEnabled)
        guard raw["activityId"].integer == activityID, raw["topicId"].integer == topicID, raw["nodeId"].integer == nodeID else { throw NativePlatformIssue.invalidContract }
        return try NativeTimeWindow(raw)
    }
    private func gate(_ enabled: Bool) throws {
        guard enabled else { throw NativePlatformIssue.disabled }
        guard current() == owner else { throw NativePlatformIssue.staleSession }
    }
}
