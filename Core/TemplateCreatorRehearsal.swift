import Foundation

/// A separate local rehearsal. It never emits network evidence, XP, inventory,
/// completion records or player state. Secret values remain creator-local.
public struct TemplateCreatorRehearsal: Equatable {
    public enum Result: String, Equatable { case ready, matched, missed, invalid, providerRequired }
    public private(set) var result: Result = .ready
    public private(set) var branchStepID: String?
    public private(set) var visited: [String] = []
    public private(set) var foundTargets = Set<String>()
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func evaluate(_ family: TemplateCreatorFamily, draft: TemplateAdvancedDraft, text: String = "", selected: Set<String> = [], elapsed: Double? = nil) {
        guard draft.creatorIssues(family).isEmpty else { result = .invalid; return }
        let fields = draft.value[family.rawValue]?.object ?? [:]
        func string(_ key: String) -> String { fields[key]?.string ?? "" }
        switch family {
        case .compare:
            let known = Set(["left", "right"].flatMap { fields[$0]?.object?["items"]?.array ?? [] }.compactMap { $0.object?["id"]?.string })
            guard selected.isSubset(of: known) else { result = .invalid; return }
            let correct = Set((fields["answer"]?.array ?? []).compactMap(\.string))
            result = selected == correct ? .matched : .missed
        case .estimate:
            guard let guess = Double(text), guess.isFinite, let answer = fields["answer"]?.number, let tolerance = fields["tolerance"]?.number else { result = .missed; return }
            result = abs(guess - answer) <= tolerance ? .matched : .missed
        case .blindTaste: result = selected == [string("answerKey")] ? .matched : .missed
        case .pricePair:
            let correct = Set((fields["items"]?.array ?? []).filter { $0.object?["correct"]?.bool == true }.compactMap { $0.object?["id"]?.string })
            result = selected == correct ? .matched : .missed
        case .qa:
            if string("mode") == "SHOT" { result = .providerRequired }
            else if string("mode") == "TYPE" { result = text.trimmingCharacters(in: .whitespacesAndNewlines) == string("answerText").trimmingCharacters(in: .whitespacesAndNewlines) ? .matched : .missed }
            else {
                let correct = Set((fields["options"]?.array ?? []).filter { $0.object?["correct"]?.bool == true }.compactMap { $0.object?["id"]?.string })
                result = selected == correct ? .matched : .missed
            }
        case .typeIn:
            guard let elapsed, elapsed.isFinite, elapsed >= 0, let seconds = fields["seconds"]?.number else { result = .invalid; return }
            let target = string("target"), caseSensitive = fields["caseSensitive"]?.bool == true
            let matches = caseSensitive ? text == target : text.lowercased() == target.lowercased()
            result = matches && elapsed <= seconds ? .matched : .missed
        default: result = .providerRequired
        }
    }
    public mutating func startBranch(_ draft: TemplateAdvancedDraft) {
        guard draft.creatorIssues(.branch).isEmpty else { result = .invalid; return }
        branchStepID = draft.text("branch", "startStepId"); visited = branchStepID.map { [$0] } ?? []; result = .ready
    }
    public mutating func chooseBranch(_ optionID: String, draft: TemplateAdvancedDraft) {
        let steps = draft.rows("branch", "steps")
        guard let step = steps.first(where: { $0.object?["id"]?.string == branchStepID })?.object,
              step["terminal"]?.bool == false,
              let option = (step["options"]?.array ?? []).first(where: { $0.object?["id"]?.string == optionID })?.object,
              let target = option["nextStepId"]?.string, let next = steps.first(where: { $0.object?["id"]?.string == target })?.object else { result = .invalid; return }
        branchStepID = target; visited.append(target); result = next["terminal"]?.bool == true ? .matched : .ready
    }
    public mutating func tapHiddenObject(draft: TemplateAdvancedDraft, x: Double, y: Double) {
        guard draft.creatorIssues(.hiddenObject).isEmpty, x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { result = .invalid; return }
        let targets = draft.rows("hiddenObject", "hotspots").compactMap(\.object)
        if let hit = targets.first(where: { target in
            guard let tx = target["x"]?.number, let ty = target["y"]?.number, let radius = target["r"]?.number else { return false }
            return hypot(tx - x, ty - y) <= radius
        }), let id = hit["id"]?.string {
            foundTargets.insert(id); result = foundTargets.count == targets.count ? .matched : .ready
        } else { result = .missed }
    }

}
