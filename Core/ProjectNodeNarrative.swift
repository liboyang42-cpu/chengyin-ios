import Foundation

/// Mini's current narrative editor merges the legacy fields only on explicit completion.
/// Merely opening, restoring or cancelling an editor never rewrites a node.
public enum ProjectNodeNarrative {
    public enum Field: String, CaseIterable, Identifiable {
        case hookText, cardHookLong, fragmentText
        public var id: String { rawValue }
    }
    /// Matches the existing narrative textarea, measured as JavaScript string units.
    public static let maximumLength = 2000

    public static func mergedDescription(in node: ProjectEditNode) throws -> String {
        var values = [node.description]
        for field in Field.allCases {
            switch node.localMetadata[field.rawValue] {
            case nil, .null?: break
            case .string(let text)?: values.append(text)
            default: throw ProjectEditError.invalidDraft
            }
        }
        var seen = Set<[UInt8]>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(Array($0.utf8)).inserted }.joined(separator: "\n")
    }

    public static func applying(_ description: String, to node: ProjectEditNode) throws -> ProjectEditNode {
        _ = try mergedDescription(in: node) // Unknown legacy types must not be erased.
        guard description.utf16.count <= maximumLength else { throw ProjectEditError.invalidDraft }
        var next = node; next.description = description
        for field in Field.allCases { next.localMetadata[field.rawValue] = .string("") }
        return next
    }
}
