import Foundation

/// Updates the original draft's routeGraphJson. Saving/publishing remains the existing writer.
public struct CollectSetAuthorDefinition: Codable, Equatable, Identifiable {
    public var key: String
    public var title: String
    public var nodeIds: [Int]
    public var id: String { key }
    public init(key: String, title: String, nodeIds: [Int]) { self.key = key; self.title = title; self.nodeIds = nodeIds }
}
public enum CollectSetAuthoring {
    public static func definitions(in draft: ProjectEditDraft) throws -> [CollectSetAuthorDefinition] {
        let graph = try graph(in: draft)
        guard let raw = graph["collectSets"] else { return [] }
        guard let rows = raw.array, rows.allSatisfy({ row in
            guard let fields = row.object else { return false }
            return Set(fields.keys) == Set(["key", "title", "nodeIds"])
        }) else { throw ProjectEditError.invalidDraft }
        let definitions = try JSONDecoder().decode([CollectSetAuthorDefinition].self, from: JSONEncoder().encode(raw))
        _ = try applying(definitions, to: draft)
        return definitions
    }
    public static func applying(_ definitions: [CollectSetAuthorDefinition], to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        let nodes = draft.chapters.flatMap(\.nodes).compactMap { $0.localMetadata["id"]?.integer }
        guard Set(nodes).count == nodes.count, definitions.count <= 64,
              Set(definitions.map(\.key)).count == definitions.count else { throw ProjectEditError.invalidDraft }
        for set in definitions {
            guard set.key.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil,
                  !set.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, set.title.utf16.count <= 120,
                  (1...200).contains(set.nodeIds.count), Set(set.nodeIds).count == set.nodeIds.count,
                  set.nodeIds.allSatisfy({ $0 > 0 && nodes.contains($0) }) else { throw ProjectEditError.invalidDraft }
        }
        let original = try rawGraph(in: draft)
        let encoded = try JSONEncoder().encode(definitions)
        var scanner = FieldScanner(bytes: Array(original.utf8))
        let data = try scanner.replacing(with: encoded)
        guard let raw = String(data: data, encoding: .utf8), data.count <= 262_144 else { throw ProjectEditError.invalidDraft }
        var changed = draft; changed.preserved["routeGraphJson"] = .string(raw)
        if changed.preserved["routeMode"] == nil { changed.preserved["routeMode"] = .string("LINEAR") }
        return changed
    }
    private static func graph(in draft: ProjectEditDraft) throws -> [String: ProjectEditJSON] {
        let raw = try rawGraph(in: draft)
        return try JSONDecoder().decode([String: ProjectEditJSON].self, from: Data(raw.utf8))
    }
    private static func rawGraph(in draft: ProjectEditDraft) throws -> String {
        guard let value = draft.preserved["routeGraphJson"], value != .null else { return "{}" }
        guard let raw = value.text else { throw ProjectEditError.invalidDraft }
        if raw.isEmpty { return "{}" }
        guard raw.utf8.count <= 262_144 else { throw ProjectEditError.invalidDraft }
        func uniqueKeys(_ value: ContentDraftJSON) throws {
            switch value {
            case .object(let fields):
                var seen = Set<String>()
                for (bytes, child) in fields {
                    guard let key = String(data: bytes, encoding: .utf8), seen.insert(key).inserted else { throw ProjectEditError.invalidDraft }
                    try uniqueKeys(child)
                }
            case .array(let values): for child in values { try uniqueKeys(child) }
            default: break
            }
        }
        let parsed = try ContentDraftJSON.parse(raw)
        guard case .object = parsed else { throw ProjectEditError.invalidDraft }
        try uniqueKeys(parsed)
        return raw
    }
    /// Replace only the top-level value token; keep every unrelated graph byte intact.
    private struct FieldScanner {
        var bytes: [UInt8]
        var index = 0
        mutating func whitespace() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        mutating func stringEnd() throws {
            guard index < bytes.count, bytes[index] == 34 else { throw ProjectEditError.invalidDraft }
            index += 1
            while index < bytes.count {
                if bytes[index] == 92 { index += 2 }
                else if bytes[index] == 34 { index += 1; return }
                else { index += 1 }
            }
            throw ProjectEditError.invalidDraft
        }
        mutating func valueEnd() throws {
            whitespace()
            guard index < bytes.count else { throw ProjectEditError.invalidDraft }
            if bytes[index] == 34 { try stringEnd(); return }
            if bytes[index] == 123 || bytes[index] == 91 {
                var depth = 0
                repeat {
                    guard index < bytes.count else { throw ProjectEditError.invalidDraft }
                    if bytes[index] == 34 { try stringEnd(); continue }
                    if bytes[index] == 123 || bytes[index] == 91 { depth += 1 }
                    if bytes[index] == 125 || bytes[index] == 93 { depth -= 1 }
                    index += 1
                } while depth > 0
            } else {
                while index < bytes.count && ![9, 10, 13, 32, 44, 125, 93].contains(bytes[index]) { index += 1 }
            }
        }
        mutating func replacing(with replacement: Data) throws -> Data {
            whitespace(); guard index < bytes.count, bytes[index] == 123 else { throw ProjectEditError.invalidDraft }; index += 1
            var hasFields = false
            while true {
                whitespace(); guard index < bytes.count else { throw ProjectEditError.invalidDraft }
                if bytes[index] == 125 {
                    let insertion = Data(((hasFields ? "," : "") + "\"collectSets\":").utf8) + replacement
                    bytes.insert(contentsOf: insertion, at: index); return Data(bytes)
                }
                let keyStart = index; try stringEnd()
                let key = try JSONDecoder().decode(String.self, from: Data(bytes[keyStart..<index]))
                whitespace(); guard index < bytes.count, bytes[index] == 58 else { throw ProjectEditError.invalidDraft }; index += 1; whitespace()
                let start = index; try valueEnd()
                if key == "collectSets" { bytes.replaceSubrange(start..<index, with: replacement); return Data(bytes) }
                hasFields = true; whitespace()
                if index < bytes.count && bytes[index] == 44 { index += 1 }
            }
        }
    }
}
