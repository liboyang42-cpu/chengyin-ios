import Foundation

/// Read-only guidance. Original serialization, including unchanged-byte passthrough, decides acceptance.
struct NativeRpgGrowthAuthorValidation {
    enum Issue: String, Hashable {
        case fields, enabled, role, maxLevel, skillPoints, thresholdCount, thresholdOrder, feats, originalContract
        var key: String { "growthValidation." + rawValue }
    }
    let issues: [Issue]
    let canPreview: Bool
    let thresholdCount: Int
    let requiredThresholdCount: Int?
    let canAddThreshold: Bool
    let canRemoveThreshold: Bool
    init(_ draft: NativeRpgGrowthAuthorDraft) {
        let growth = draft.growth
        let rows = growth?["xpThresholds"]?.array
        thresholdCount = rows?.count ?? 0
        let maximum = growth?["maxLevel"]?.integer
        requiredThresholdCount = maximum.flatMap { (1...20).contains($0) ? $0 - 1 : nil }
        canAddThreshold = rows.map { $0.count < 19 } ?? false
        canRemoveThreshold = rows.map { !$0.isEmpty } ?? false
        canPreview = (try? draft.serialized()) != nil
        // Unknown original configurations may pass through unchanged by explicit Core design.
        guard draft.changed, let growth else { issues = []; return }
        var result: [Issue] = []
        if !Set(growth.keys).isSubset(of: ["enabled", "maxLevel", "skillPointsPerLevel", "xpThresholds", "feats"]) { result.append(.fields) }
        if case .bool(let enabled)? = growth["enabled"] {
            if enabled && !draft.roleEnabled { result.append(.role) }
        } else { result.append(.enabled) }
        if let maximum {
            if !(1...20).contains(maximum) { result.append(.maxLevel) }
        } else { result.append(.maxLevel) }
        if let points = growth["skillPointsPerLevel"]?.integer {
            if !(0...1_000_000).contains(points) { result.append(.skillPoints) }
        } else { result.append(.skillPoints) }
        if let rows {
            if let requiredThresholdCount, rows.count != requiredThresholdCount { result.append(.thresholdCount) }
            var previous = 0
            for row in rows {
                guard let number = row.integer, number > previous, number <= 1_000_000_000 else { result.append(.thresholdOrder); break }
                previous = number
            }
        } else { result.append(.thresholdCount) }
        if let raw = growth["feats"] {
            if let values = raw.array {
                let names = values.compactMap(\.text)
                if values.count > 6 || names.count != values.count || Set(names).count != names.count || !Set(names).isSubset(of: Set(NativeRpgGrowthAuthorDraft.featKeys)) { result.append(.feats) }
            } else { result.append(.feats) }
        }
        if !canPreview && result.isEmpty { result.append(.originalContract) }
        issues = result
    }
    static func text(_ key: String, locale: Locale) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "GrowthValidation", locale: locale))
    }
}
