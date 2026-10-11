import Foundation

/// Optional display metadata, never authority to add or replace selected categories.
public struct ProfilePreferenceLabel: Decodable, Equatable {
    public let id: Int
    public let name: String?
    enum CodingKeys: String, CodingKey { case id; case name = "categoryName" }
}

/// Removing existing preferences never requires the current discovery catalogue.
public enum ProfilePreferenceRemoval {
    public static func validIDs(_ values: [Int]) -> Bool {
        values.allSatisfy { $0 > 0 } && Set(values).count == values.count
    }
    public static func parse(_ raw: String) -> [Int]? {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        var values: [Int] = []
        for part in raw.split(separator: ",", omittingEmptySubsequences: false) {
            let token = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, token.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let value = Int(token), value > 0 else { return nil }
            values.append(value)
        }
        return validIDs(values) ? values : nil
    }
    public static func selection(draft: ProfileEditDraft, snapshot: ProfileEditSnapshot) -> [Int]? {
        if let values = draft.routePreferenceIDs { return validIDs(values) ? values : nil }
        return parse(snapshot.tagIds)
    }
    public static func isOrderedSubset(_ proposed: [Int], of original: [Int]) -> Bool {
        guard validIDs(original), validIDs(proposed) else { return false }
        let kept = Set(proposed)
        return original.filter { kept.contains($0) } == proposed
    }
    public static func names(_ labels: [ProfilePreferenceLabel]) -> [Int: String] {
        let groups = Dictionary(grouping: labels, by: \.id)
        var result: [Int: String] = [:]
        for (id, values) in groups where id > 0 && values.count == 1 {
            if let name = values[0].name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result[id] = name
            }
        }
        return result
    }
}
