import Foundation

/// Authoring only: coordinates share the existing hiddenObject wire shape.
public struct TemplateHotspotPlacement {
    public struct Point: Equatable { public let x: Double; public let y: Double }
    public struct Target: Identifiable, Equatable {
        public let id: String
        public let label: String
        public let point: Point?
    }
    public enum Edit { case add(String), label(String, String), remove(String), move(String, Int), place(String, x: Double, y: Double, width: Double, height: Double) }
    public let targets: [Target]
    public let isSupported: Bool
    public let canEdit: Bool
    public var canAdd: Bool { canEdit && targets.count < 5 }
    public var canRemove: Bool { canEdit && targets.count > 3 }
    public let sceneReference: String
    private let fingerprint: Data?

    public init(_ draft: TemplateAdvancedDraft) {
        let raw = draft.value["hiddenObject"]?.object?["hotspots"], rows = raw?.array
        let source = draft.value["hiddenObject"]?.object?["imageUrl"]
        sceneReference = source?.string ?? ""
        let encoded = Self.snapshot(draft); fingerprint = encoded
        var used = Set<String>()
        let supported = rows != nil && rows!.count <= 5 && (source == nil || source?.string != nil) && encoded != nil && rows!.allSatisfy { raw in
            guard let row = raw.object, let id = row["id"]?.string, Self.validID(id), used.insert(id).inserted,
                  row["label"] == nil || row["label"]?.string != nil,
                  let radius = row["r"]?.number, radius.isFinite, (0.03...0.15).contains(radius) else { return false }
            // Missing/out-of-range coordinates can be repaired by placing the target.
            return ["x", "y"].allSatisfy { row[$0] == nil || row[$0]?.string != nil || Self.finiteNumber(row[$0]) != nil }
        }
        isSupported = supported
        canEdit = supported && draft.enabled("hiddenObject")
        targets = supported ? rows!.map { raw in
            let row = raw.object!
            let point: Point?
            if let x = Self.finiteNumber(row["x"]), let y = Self.finiteNumber(row["y"]), (0...1).contains(x), (0...1).contains(y) { point = .init(x: x, y: y) }
            else { point = nil }
            return .init(id: row["id"]!.string!, label: row["label"]?.string ?? "", point: point)
        } : []
    }
    /// Only explicit user loading consumes this URL; no credentials/fragments or relative paths.
    public var sceneURL: URL? {
        guard !sceneReference.isEmpty, sceneReference.utf8.count <= 512,
              sceneReference.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }),
              let url = URL(string: sceneReference), url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }
    public static func point(x: Double, y: Double, width: Double, height: Double) -> Point? {
        guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        func normalized(_ coordinate: Double, _ extent: Double) -> Double { (min(1, max(0, coordinate / extent)) * 10000).rounded() / 10000 }
        return .init(x: normalized(x, width), y: normalized(y, height))
    }
    public func isCurrent(_ draft: TemplateAdvancedDraft) -> Bool { fingerprint != nil && fingerprint == Self.snapshot(draft) }
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> TemplateAdvancedDraft? {
        guard canEdit, isCurrent(draft) else { return nil }
        var rows = draft.rows("hiddenObject", "hotspots")
        switch edit {
        case .add(let id):
            guard canAdd, Self.validID(id), !targets.contains(where: { $0.id == id }) else { return nil }
            rows.append(.object(["id": .string(id), "label": .string(""), "x": .number(0.5), "y": .number(0.5), "r": .number(0.08)]))
        case .remove(let id):
            guard canRemove, let index = targets.firstIndex(where: { $0.id == id }) else { return nil }
            rows.remove(at: index)
        case .move(let id, let destination):
            guard let index = targets.firstIndex(where: { $0.id == id }), rows.indices.contains(destination), index != destination else { return nil }
            let row = rows.remove(at: index); rows.insert(row, at: destination)
        case .label(let id, let label):
            guard let index = targets.firstIndex(where: { $0.id == id }) else { return nil }
            var row = rows[index].object!; row["label"] = .string(label); rows[index] = .object(row)
        case .place(let id, let x, let y, let width, let height):
            guard let index = targets.firstIndex(where: { $0.id == id }), let point = Self.point(x: x, y: y, width: width, height: height) else { return nil }
            var row = rows[index].object!; row["x"] = .number(point.x); row["y"] = .number(point.y); rows[index] = .object(row)
        }
        var next = draft; next.set("hiddenObject", "hotspots", .array(rows)); return next
    }
    private static func finiteNumber(_ value: TemplateAuthoringJSON?) -> Double? {
        guard let number = value?.number, number.isFinite else { return nil }; return number
    }
    private static func validID(_ value: String) -> Bool { value.range(of: TemplateCreatorSchema.keyPattern, options: .regularExpression) != nil }
    private static func snapshot(_ draft: TemplateAdvancedDraft) -> Data? {
        guard let value = draft.value["hiddenObject"] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(value)
    }
}
