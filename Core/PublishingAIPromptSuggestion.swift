import Foundation

/// The three inspiration entries on the Mini simple-publish page. They are local text,
/// not generated plans, provider requests, saved drafts or permission to generate.
public enum PublishingAIPromptSuggestion: String, CaseIterable, Identifiable {
    case oldTown, familyWeekend, rainyDay
    public var id: String { rawValue }
    public var titleKey: String { "creatorAIPrompts." + rawValue }
    public func text(languageCode: String) -> String {
        let chinese = languageCode.lowercased().hasPrefix("zh")
        switch self {
        case .oldTown: return chinese ? "老城建筑与咖啡" : "Old-town architecture and coffee"
        case .familyWeekend: return chinese ? "周末亲子探险" : "A weekend family adventure"
        case .rainyDay: return chinese ? "雨天室内漫游" : "An indoor wander on a rainy day"
        }
    }
}
