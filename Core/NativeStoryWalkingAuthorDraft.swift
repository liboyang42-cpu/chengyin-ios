import Foundation

/// Only original FULL topic metadata. Original project save/request recovery/review/publication owns persistence.
public struct NativeStoryWalkingAuthorDraft {
    public struct Entrance: Equatable {
        public var label = "", source = "", longitude = "", latitude = "", datum = ""
        public var floor = "" { didSet { if oldValue != floor { originalEmptyText.remove("floor") } } }
        public var approach = "" { didSet { if oldValue != approach { originalEmptyText.remove("approachNote") } } }
        public var alternative = "" { didSet { if oldValue != alternative { originalEmptyText.remove("accessibleAlternative") } } }
        public var businessTime = "" { didSet { if oldValue != businessTime { originalEmptyText.remove("businessTime") } } }
        // In-memory provenance only. A legal, untouched empty string differs from null in the
        // original reviewed content. Once edited, clearing still uses the existing null contract.
        private var originalEmptyText: Set<String> = []
        public var closed: Bool?
        public init() { }
        fileprivate init(_ raw: ProjectEditJSON) throws {
            guard let row = raw.object, Set(row.keys) == ["label","floor","approachNote","source","longitude","latitude","datum","temporarilyClosed","accessibleAlternative","businessTime"],
                  let label = row["label"]?.text, let source = row["source"]?.text, let datum = row["datum"]?.text,
                  case .number(let longitude)? = row["longitude"], case .number(let latitude)? = row["latitude"],
                  case .bool(let closed)? = row["temporarilyClosed"] else { throw Failure.unsupported }
            func optional(_ key: String) throws -> String { guard let value = row[key] else { throw Failure.unsupported }; if value == .null { return "" }; guard let text = value.text else { throw Failure.unsupported }; return text }
            self.label = label; self.source = source; self.datum = datum; self.longitude = NSDecimalNumber(decimal: longitude).stringValue
            self.latitude = NSDecimalNumber(decimal: latitude).stringValue; self.closed = closed
            floor = try optional("floor"); approach = try optional("approachNote"); alternative = try optional("accessibleAlternative"); businessTime = try optional("businessTime")
            originalEmptyText = Set(["floor", "approachNote", "accessibleAlternative", "businessTime"].filter { row[$0] == .string("") })
        }
        fileprivate func json() throws -> ProjectEditJSON {
            func valid(_ text: String, _ limit: Int, required: Bool = false) -> Bool { text.utf16.count <= limit && !text.contains("\0") && (!required || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            guard valid(label,300,required:true), valid(source,1000,required:true), valid(floor,100), valid(approach,2000), valid(alternative,2000), valid(businessTime,1000),
                  ["WGS84","GCJ02","BD09"].contains(datum), let closed,
                  let lng = Double(longitude), lng.isFinite, abs(lng) <= 180, let lat = Double(latitude), lat.isFinite, abs(lat) <= 90,
                  let lngValue = Decimal(string: longitude, locale: Locale(identifier: "en_US_POSIX")), let latValue = Decimal(string: latitude, locale: Locale(identifier: "en_US_POSIX")) else { throw Failure.invalid }
            func optional(_ text: String, _ key: String) -> ProjectEditJSON { text.isEmpty && !originalEmptyText.contains(key) ? .null : .string(text) }
            return .object(["label":.string(label),"floor":optional(floor,"floor"),"approachNote":optional(approach,"approachNote"),"source":.string(source),"longitude":.number(lngValue),"latitude":.number(latValue),"datum":.string(datum),"temporarilyClosed":.bool(closed),"accessibleAlternative":optional(alternative,"accessibleAlternative"),"businessTime":optional(businessTime,"businessTime")])
        }
    }
    public struct Node: Identifiable, Equatable {
        public let id: Int
        public var region = ""
        public var entrance: Entrance?
        public init(id: Int) { self.id = id }
    }
    public enum Failure: Error { case unsupported, changed, invalid }
    public var nodes: [Node] = []
    public var ttl = ""
    public var schema = 2
    private let originalDraftBytes: Data
    private let original: ProjectEditJSON?
    private let root: [String: ProjectEditJSON]
    public init(draft: ProjectEditDraft) throws {
        guard let bytes = ProjectEditPendingMaterials.exactData(draft) else { throw Failure.unsupported }; originalDraftBytes = bytes
        let stored = draft.preserved["themeRuntimeConfig"]; original = stored
        if stored == nil || stored == .null || stored?.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { root = ["schemaVersion":.number(1)] }
        else {
            guard let raw = stored?.text, raw.utf8.count <= 200_000, let parsed = try? JSONDecoder().decode(ProjectEditJSON.self,from:Data(raw.utf8)).object,
                  parsed["schemaVersion"] == .number(1) else { throw Failure.unsupported }; root = parsed
        }
        guard let raw = root["walkingNavigation"] else { return }
        guard let policy = raw.object, Set(policy.keys) == ["schemaVersion","authorityTTLSeconds","nodes"], let version = policy["schemaVersion"]?.integer,
              [1,2].contains(version), let seconds = policy["authorityTTLSeconds"]?.integer, (1...300).contains(seconds),
              case .array(let rows)? = policy["nodes"], rows.count <= 2000 else { throw Failure.unsupported }
        schema = version; ttl = String(seconds)
        for value in rows {
            guard let row = value.object, Set(row.keys) == (version == 1 ? Set(["nodeId","region"]) : Set(["nodeId","region","entrance"])),
                  let id = row["nodeId"]?.integer, id > 0, let region = row["region"]?.text, !nodes.contains(where: { $0.id == id }) else { throw Failure.unsupported }
            var node = Node(id: id); node.region = region
            if version == 2, let entrance = row["entrance"], entrance != .null { node.entrance = try .init(entrance) }
            nodes.append(node)
        }
    }
    public func applying(to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard ProjectEditPendingMaterials.exactData(draft) == originalDraftBytes else { throw Failure.changed }
        if schema == 1 { return draft } // Viewing the old contract cannot silently upgrade or erase it.
        guard schema == 2, let seconds = Int(ttl), String(seconds) == ttl, (1...300).contains(seconds), nodes.count <= 2000,
              Set(nodes.map(\.id)).count == nodes.count else { throw Failure.invalid }
        let allowed = Set(draft.chapters.flatMap(\.nodes).compactMap { $0.localMetadata["id"]?.integer }.filter { $0 > 0 })
        var rows: [ProjectEditJSON] = []
        for node in nodes {
            guard allowed.contains(node.id), node.region.range(of: "^[A-Z]{2}$", options:.regularExpression) != nil else { throw Failure.invalid }
            rows.append(.object(["nodeId":.number(Decimal(node.id)),"region":.string(node.region),"entrance":try node.entrance?.json() ?? .null]))
        }
        var value = root; value["walkingNavigation"] = .object(["schemaVersion":.number(2),"authorityTTLSeconds":.number(Decimal(seconds)),"nodes":.array(rows)])
        if let bytes = ProjectEditPendingMaterials.exactData(ProjectEditJSON.object(root)),
           ProjectEditPendingMaterials.exactData(ProjectEditJSON.object(value)) == bytes { return draft }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let data = try encoder.encode(ProjectEditJSON.object(value))
        guard data.count <= 200_000, let raw = String(data:data,encoding:.utf8) else { throw Failure.invalid }
        var result = draft; result.preserved["themeRuntimeConfig"] = .string(raw); return result
    }
}
