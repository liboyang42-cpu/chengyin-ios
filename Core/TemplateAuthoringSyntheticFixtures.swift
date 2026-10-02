#if DEBUG
import Foundation

@MainActor public final class TemplateAuthoringMemoryStorage: TemplateAuthoringStorage {
    public var values: [String: Data] = [:]
    public var failWrites = false
    public init() {}
    public func read(_ key: String) throws -> Data? { values[key] }
    public func write(_ data: Data, key: String) throws { guard !failWrites else { throw TemplateAuthoringError.storageUnavailable }; values[key] = data }
    public func remove(_ key: String) throws { values.removeValue(forKey: key) }
}
@MainActor public final class TemplateAuthoringSyntheticTransport: TemplateAuthoringTransport {
    public enum Scenario { case accepted, duplicate, contentRejected, uncertain, unauthorized }
    public let authority: TemplateAuthoringAuthority = .synthetic
    public var scenario: Scenario
    public var delayNanoseconds: UInt64 = 0
    public private(set) var requests: [TemplateAuthoringRequest] = []
    public init(scenario: Scenario = .accepted) { self.scenario = scenario }
    public func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) {
        requests.append(request)
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        if !request.mutates { return (Data(Self.list.utf8), 200) }
        switch scenario {
        case .accepted: return (Data(#"{"code":200,"msg":"ok"}"#.utf8), 200)
        case .duplicate: return (Data(#"{"code":500,"msg":"模板名称 Synthetic 已存在"}"#.utf8), 200)
        case .contentRejected: return (Data(#"{"code":500,"msg":"内容含有敏感词"}"#.utf8), 200)
        case .uncertain: throw TemplateAuthoringError.uncertain
        case .unauthorized: return (Data(#"{"code":401}"#.utf8), 401)
        }
    }
    public static let list = #"{"code":200,"data":[{"id":901,"title":"Synthetic interaction","description":"Fixture only","status":2,"publishStatus":0,"packType":0}]}"#
}
public enum TemplateAuthoringSyntheticFixtures {
    /// Synthetic multi-family creator input; no account, server or location data.
    public static let compoundAdvanced = #"{"schemaVersion":1,"coinFlip":{"enabled":true,"heads":{"label":"Heads","action":"Look up"},"tails":{"label":"Tails","action":"Look down"}},"diceRoll":{"enabled":true,"diceCount":1,"faces":["One","Two","Three","Four","Five","Six"]},"quietHold":{"enabled":true,"seconds":15},"timer":{"enabled":true,"durationSeconds":300,"timeoutResult":"FAILED"},"timeWindow":{"enabled":true,"openFrom":"20:00","openTo":"23:00"},"mistakeTier":"easy"}"#
    public static func compoundDraft() -> TemplateAuthoringDraft {
        var value = draft(); value.validationMethod = .manual
        // Keep parse errors visible to tests; this fixed fixture cannot create a live request.
        if let advanced = try? TemplateAdvancedDraft(raw: compoundAdvanced) { value.advanced = advanced }
        return value
    }
    public static func draft() -> TemplateAuthoringDraft {
        var d = TemplateAuthoringDraft(title: "Synthetic city question")
        d.description = "Find one small detail"; d.players = "1-2 人"; d.duration = 10; d.categoryId = 4
        d.validationMethod = .text; d.questionName = "What did you notice?"; d.questionAnswer = "window"
        d.feedbackText = "Thank you for looking closely"; d.storyEnabled = true
        try? d.setStory([.init(text: "This scene is synthetic.", tag: "Start")])
        return d
    }
}
#endif
