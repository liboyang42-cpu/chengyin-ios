import Foundation

/// Source: publish_draft.dart and publish_draft_logic.dart. Native editor state is
/// deliberately separate from wire payloads and from the Flutter secure-store format.
public enum ProjectEditProduct: Int, Codable, CaseIterable { case city = 1, freeExplore = 2 }
public enum ProjectEditScope: String, Codable { case full = "FULL", whitelist = "WHITELIST" }
public enum ProjectEditOwner: String, Codable { case personal = "", merchant = "MERCHANT" }
public enum ProjectEditJSON: Codable, Equatable {
    case null, bool(Bool), number(Decimal), string(String), array([ProjectEditJSON]), object([String: ProjectEditJSON])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Decimal.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([ProjectEditJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: ProjectEditJSON].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    var text: String? { if case .string(let v) = self { return v }; return nil }
    var integer: Int? {
        guard case .number(let v) = self, v >= Decimal(Int.min), v <= Decimal(Int.max) else { return nil }
        let n = NSDecimalNumber(decimal: v).intValue
        return Decimal(n) == v ? n : nil
    }
    var object: [String: ProjectEditJSON]? { if case .object(let v) = self { return v }; return nil }
    var array: [ProjectEditJSON]? { if case .array(let v) = self { return v }; return nil }
}
public struct ProjectEditNode: Identifiable, Codable, Equatable {
    public var id = UUID().uuidString
    public var name = ""
    public var description = ""
    public var address = ""
    public var longitude = ""
    public var latitude = ""
    public var imgUrl = ""
    public var nodeTime = 30
    public var templateID: Int?
    /// Unexposed local metadata is retained, never reconstructed from UI labels.
    public var localMetadata: [String: ProjectEditJSON] = [:]
    public init() {}
    public var hasUsableCoordinates: Bool {
        guard let x = Double(longitude), let y = Double(latitude), x.isFinite, y.isFinite else { return false }
        return x != 0 && y != 0 && (-180...180).contains(x) && (-90...90).contains(y)
    }
}
public struct ProjectEditBlock: Identifiable, Codable, Equatable {
    public enum Kind: String, Codable, CaseIterable, Hashable { case text, node, image, audio, dream, mood, thought, voice, odd, reveal }
    public var id = UUID().uuidString
    public var kind: Kind
    public var content = ""
    public var nodeID = ""
    public var url = ""
    /// Optional for old local envelopes; preserves supported source-only story semantics.
    public var sourceFields: [String: ProjectEditJSON]?
    /// Local filename belongs only to its exact uploaded reference; never part of the story wire payload.
    public var localAudio: ProjectStoryAudioLocalMetadata? = nil
    public init(kind: Kind, content: String = "", nodeID: String = "", url: String = "") {
        self.kind = kind; self.content = content; self.nodeID = nodeID; self.url = url
    }
}
public struct ProjectEditChapter: Identifiable, Codable, Equatable {
    public var id = UUID().uuidString
    public var name = ""
    public var description = ""
    public var nodes: [ProjectEditNode] = []
    public var blocks: [ProjectEditBlock]?
    public var schemaVersion = 1
    public var required = 1
    /// Complete source replacement carry-over, including merchant contractual limits.
    /// Only explicitly source-backed fields go into payload; unknown fields stay local.
    public var preserved: [String: ProjectEditJSON] = ["atmospherePreset": .string("DEFAULT"), "recruitEnabled": .number(0), "termsMode": .string("PERK")]
    public init() {}
    public var story: String {
        guard let blocks else { return description }
        return blocks.prefix(while: { $0.kind != .node }).filter { $0.kind == .text }.map(\.content).joined(separator: "\n")
    }
    public var hasRealStory: Bool {
        let value = story.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && !["暂无描述", "暂无", "无"].contains(value)
    }
    public mutating func addNode(product: ProjectEditProduct) throws {
        guard preserved["opening"] != .bool(true), preserved["ending"]?.object == nil else { throw ProjectEditError.invalidDraft }
        guard product != .city || hasRealStory else { throw ProjectEditError.storyRequired }
        let node = ProjectEditNode(); nodes.append(node)
        if blocks != nil { blocks?.append(.init(kind: .node, nodeID: node.id)) }
    }
    public mutating func removeNode(id: String) {
        nodes.removeAll { $0.id == id }; blocks?.removeAll { ($0.kind == .node || $0.isNarrative) && $0.nodeID == id }
    }
}
public struct ProjectEditTicket: Identifiable, Codable, Equatable {
    public var id = UUID().uuidString
    public var name = ""
    /// Empty is missing, "0" is an explicit free ticket. Never coalesce missing to zero.
    public var price = ""
    public var totalStock = "100"
    public var teamSize = "0"
    public var startTime = ""
    public var endTime = ""
    public var meetingPoint = ""
    public var gatherLng = ""
    public var gatherLat = ""
    public var description = ""
    public var saleStartTime = ""
    public var saleEndTime = ""
    public var localMetadata: [String: ProjectEditJSON] = [:]
    public init() {}
    /// Mini's syncWithTheme is stored/read back by the backend, but date
    /// resolution is client-side. Never infer this preference from equal dates.
    public var syncsWithThemeDates: Bool { localMetadata["syncWithTheme"] == .bool(true) }
    public var canEditThemeDateSync: Bool {
        guard let raw = localMetadata["syncWithTheme"] else { return true }
        if raw == .null { return true }
        if case .bool = raw { return true }
        return false
    }
    public func schedule(in draft: ProjectEditDraft) -> (start: String, end: String) {
        let synced = draft.product == .freeExplore && syncsWithThemeDates
        let start = synced ? draft.startDate : startTime
        let end = synced ? draft.endDate : endTime
        return (ProjectEditValidation.dateTime(start) ?? start,
                ProjectEditValidation.dateTime(end, endOfDay: true) ?? end)
    }
    public mutating func setThemeDateSync(_ enabled: Bool, in draft: ProjectEditDraft) throws {
        guard draft.product == .freeExplore, canEditThemeDateSync else { throw ProjectEditError.invalidDraft }
        // Turning off keeps the currently shown dates, matching mini's toggle.
        // A repeated off does not replace manually entered dates.
        if enabled {
            startTime = draft.startDate; endTime = draft.endDate
        } else if syncsWithThemeDates {
            let current = schedule(in: draft)
            startTime = current.start; endTime = current.end
        }
        localMetadata["syncWithTheme"] = .bool(enabled)
    }
    /// Legacy values are preserved until this field is explicitly changed. Unsupported
    /// wire types remain read-only, including after local draft restoration.
    public func canEditSaleTime(end: Bool) -> Bool {
        guard let raw = localMetadata[end ? "saleEndTime" : "saleStartTime"] else { return true }
        if raw == .null { return true }
        return raw.text != nil
    }
    public func saleTimePayloads() throws -> [String: ProjectEditJSON] {
        var result: [String: ProjectEditJSON] = [:]
        for end in [false, true] {
            let key = end ? "saleEndTime" : "saleStartTime"
            let value = end ? saleEndTime : saleStartTime
            let original = localMetadata[key]
            if value == (original?.text ?? "") {
                if let original { result[key] = original }
                continue
            }
            guard canEditSaleTime(end: end) else { throw ProjectEditError.invalidDraft }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result[key] = .null
            } else {
                guard let normalized = ProjectEditValidation.dateTime(value, endOfDay: end) else { throw ProjectEditError.invalidDraft }
                result[key] = .string(normalized)
            }
        }
        return result
    }
}
public struct ProjectEditDraft: Codable, Equatable {
    public var name = ""
    public var subtitle = ""
    public var description = ""
    public var startDate = ""
    public var endDate = ""
    public var recruitDeadline = ""
    public var imgUrl = ""
    public var imgArr = ""
    public var categoryIDs: [Int] = []
    public var product: ProjectEditProduct = .city
    public var chapters: [ProjectEditChapter] = []
    /// Local only; missing in historical envelopes and omitted from all publish payloads.
    public var pendingMaterials: [ProjectEditPendingMaterial]?
    public var tickets: [ProjectEditTicket] = []
    public var collaboratorIDs: [Int] = []
    public var clubID: Int?
    public var publishToCreative = true
    public var openMerchantPool = false
    public var owner: ProjectEditOwner = .personal
    public var completionRules: ProjectEditCompletionRules?
    public var baseRevision = ""
    public var preserved: [String: ProjectEditJSON] = [
        "publishMode": .string("pro"), "audioUrl": .string(""), "audioDuration": .number(0),
        "selfPlay": .number(0), "selfPlayPrice": .number(0), "selfPlayQuota": .number(0), "completeRewardCouponId": .number(0)
    ]
    public init(product: ProjectEditProduct = .city) { self.product = product }
    public func whitelistLockedFieldsEqual(to other: Self) -> Bool {
        var a = self; var b = other
        a.name = ""; b.name = ""; a.subtitle = ""; b.subtitle = ""; a.description = ""; b.description = ""
        a.imgUrl = ""; b.imgUrl = ""; a.imgArr = ""; b.imgArr = ""; a.categoryIDs = []; b.categoryIDs = []
        return a == b
    }
}
public enum ProjectEditError: Error, Equatable {
    case invalidContract, invalidDraft, storyRequired, staleConfirmation, changedSession, revisionConflict
    case notConfigured, persistenceUnavailable, unknownOutcome, notSent, rejected
}
public struct ProjectEditIssue: Identifiable, Equatable {
    public let id: String
    public let key: String
    public init(_ id: String, _ key: String) { self.id = id; self.key = key }
}

public enum ProjectEditValidation {
    public static func decimal(_ value: String) -> Decimal? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^-?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
    /// Strict native validation intentionally rejects malformed dates the Dart regex allowed.
    /// Wire values remain wall-clock strings; no device-zone conversion is introduced.
    public static func dateTime(_ value: String, endOfDay: Bool = false) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "T", with: " ")
        let shape: String
        if v.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { shape = v + (endOfDay ? " 23:59:59" : " 00:00:00") }
        else if v.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$"#, options: .regularExpression) != nil { shape = v + ":00" }
        else if v.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil { shape = v }
        else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.isLenient = false
        guard let date = f.date(from: shape), f.string(from: date) == shape else { return nil }
        return shape
    }
    public static func issues(_ draft: ProjectEditDraft, scope: ProjectEditScope = .full) -> [ProjectEditIssue] {
        var issues: [ProjectEditIssue] = []
        func need(_ condition: Bool, _ id: String, _ key: String) { if !condition { issues.append(.init(id, "projectEdit.validation." + key)) } }
        need(!draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "name", "name")
        need(!draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "description", "description")
        need(!draft.imgUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "cover", "cover")
        need(!draft.categoryIDs.isEmpty && draft.categoryIDs.allSatisfy { $0 > 0 }, "categories", "categories")
        guard scope == .full else { return issues }
        need((try? PublishingTopicRewards(draft: draft).applying(to: draft)) != nil, "topicRewards", "rewards")
        let rules = (draft.completionRules ?? .init(raw: draft.preserved["completeRuleJson"])).forProduct(draft.product)
        if let key = rules.validationIssue(totalNodes: draft.chapters.reduce(0) { $0 + $1.nodes.count }) { issues.append(.init("completionRules", key)) }
        let start = dateTime(draft.startDate), end = dateTime(draft.endDate, endOfDay: true)
        need(start != nil, "start", "dates"); need(end != nil, "end", "dates")
        if let start, let end { need(end >= start, "dateOrder", "dateOrder") }
        if draft.product == .freeExplore { need(dateTime(draft.recruitDeadline, endOfDay: true) != nil, "deadline", "deadline") }
        need(!draft.chapters.isEmpty, "chapters", "chapters")
        for (ci, chapter) in draft.chapters.enumerated() {
            let standaloneStory = chapter.preserved["opening"] == .bool(true) || chapter.preserved["ending"]?.object != nil
            if draft.product == .city && !standaloneStory { need(chapter.hasRealStory, "story\(ci)", "story") }
            need(standaloneStory || !chapter.nodes.isEmpty, "nodes\(ci)", "nodes")
            need((chapter.blocks?.count ?? 0) <= 200, "blocks\(ci)", "blocks")
            let nodeIDs = chapter.nodes.map(\.id)
            need(Set(nodeIDs).count == nodeIDs.count, "nodeIDs\(ci)", "references")
            var refs = Set<String>()
            for block in chapter.blocks ?? [] {
                if block.kind == .node { need(nodeIDs.contains(block.nodeID) && refs.insert(block.nodeID).inserted, "reference\(block.id)", "references") }
                if block.kind == .image { need(!block.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "media\(block.id)", "media") }
            }
            for node in chapter.nodes {
                let storyGame = chapter.blocks?.contains { $0.kind == .node && $0.nodeID == node.id && $0.sourceFields?["locationRequired"] == .bool(false) } == true
                need(storyGame ? node.longitude.isEmpty && node.latitude.isEmpty && (node.templateID ?? 0) > 0 : node.hasUsableCoordinates, "coordinate\(node.id)", "coordinates")
                need(!node.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "nodeName\(node.id)", "nodeName")
                need(node.nodeTime >= 0, "nodeTime\(node.id)", "number")
            }
            if draft.product == .freeExplore, chapter.preserved["recruitEnabled"]?.integer == 1 {
                need((chapter.preserved["categoryId"]?.integer ?? 0) > 0, "merchantCategory\(ci)", "merchant")
                need(["PERK", "TRAFFIC"].contains(chapter.preserved["termsMode"]?.text ?? ""), "terms\(ci)", "merchant")
                need((0...127).contains(chapter.preserved["maxMerchant"]?.integer ?? 0), "merchantQuota\(ci)", "merchant")
                if let raw = chapter.preserved["perkMinValue"], raw != .null {
                    let v: Decimal? = { if case .number(let n) = raw { return n }; return decimal(raw.text ?? "") }()
                    need(v.map { $0 > 0 } ?? false, "perk\(ci)", "merchant")
                }
            }
        }
        for ticket in draft.tickets {
            need((try? ticket.saleTimePayloads()) != nil, "ticketSaleDates\(ticket.id)", "dates")
            need(!ticket.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "ticketName\(ticket.id)", "ticketName")
            need(decimal(ticket.price).map { $0 >= 0 } ?? false, "price\(ticket.id)", "price")
            need(Int(ticket.totalStock).map { $0 >= 0 } ?? false, "stock\(ticket.id)", "number")
            need(Int(ticket.teamSize).map { $0 >= 0 } ?? false, "team\(ticket.id)", "number")
            let schedule = ticket.schedule(in: draft)
            let ts = dateTime(schedule.start), te = dateTime(schedule.end, endOfDay: true)
            need(ts != nil && te != nil, "ticketDates\(ticket.id)", "dates")
            if let ts, let te { need(draft.product == .city ? te > ts : te >= ts, "ticketOrder\(ticket.id)", "dateOrder") }
            if draft.product == .city { need(!ticket.meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "meeting\(ticket.id)", "meeting") }
        }
        return issues
    }
}
