import Foundation

/// Audited strings are evidence only. This module never builds a URLRequest or calls them.
public enum ProjectEditContract {
    public static let sourceCreatePath = "/api/topic/create"
    public static let sourceUpdatePath = "/api/topic/update"
    public static let sourceDetailPath = "/api/topic/edit-detail"
    public static let sourcePrecheckPath = "/api/ai/safety/precheck"
    public static let chapterCarryOver = ["imgArr", "audioUrl", "atmospherePreset", "recruitEnabled", "termsMode", "categoryId", "category", "maxMerchant", "perkMinValue", "allowedValidationMethods", "maxNodeXp", "calculatedDistance"]
    public static let topicCarryOver = ProjectEditStoryContract.topicFields + ["completeRuleJson", "publishMode", "audioUrl", "audioDuration", "selfPlay", "selfPlayPrice", "selfPlayQuota", "finishMedalName", "finishMedalImg", "completeRewardCouponId"]
    public static let whitelist = ["name", "subtitle", "description", "imgUrl", "imgArr", "categoryIds", "scope"]

    public static func payload(_ draft: ProjectEditDraft, topicID: Int?, scope: ProjectEditScope) throws -> [String: ProjectEditJSON] {
        guard ProjectEditValidation.issues(draft, scope: scope).isEmpty else { throw ProjectEditError.invalidDraft }
        var payload: [String: ProjectEditJSON] = [
            "name": .string(draft.name), "subtitle": .string(draft.subtitle), "description": .string(draft.description),
            "imgUrl": .string(draft.imgUrl), "imgArr": .string(draft.imgArr),
            "categoryIds": .string(draft.categoryIDs.map(String.init).joined(separator: ",")), "scope": .string(draft.owner.rawValue)
        ]
        if let topicID { guard topicID > 0 else { throw ProjectEditError.invalidContract }; payload["id"] = .number(Decimal(topicID)) }
        if scope == .whitelist { guard topicID != nil else { throw ProjectEditError.invalidContract }; return payload }
        payload["startDate"] = .string(ProjectEditValidation.dateTime(draft.startDate)!)
        payload["endDate"] = .string(ProjectEditValidation.dateTime(draft.endDate, endOfDay: true)!)
        payload["productType"] = .number(Decimal(draft.product.rawValue))
        payload["collaboratorIds"] = .array(draft.collaboratorIDs.map { .number(Decimal($0)) })
        payload["openMerchantPool"] = .number(draft.openMerchantPool ? 1 : 0)
        payload["openClubPool"] = .number(0)
        // Editing never republishes to Creative Square, even after local restore.
        payload["publishToCreative"] = .number(topicID == nil && draft.publishToCreative ? 1 : 0)
        if let clubID = draft.clubID { payload["clubId"] = .number(Decimal(clubID)) }
        if draft.product == .freeExplore { payload["recruitDeadline"] = .string(ProjectEditValidation.dateTime(draft.recruitDeadline, endOfDay: true)!) }
        for key in topicCarryOver { if let value = draft.preserved[key] { payload[key] = value } }
        if draft.completionRules != nil || draft.preserved["completeRuleJson"] != nil {
            let rules = (draft.completionRules ?? .init(raw: draft.preserved["completeRuleJson"])).forProduct(draft.product)
            payload["completeRuleJson"] = try rules.serialized(matching: draft.preserved["completeRuleJson"])
        }
        let storyFlow = ProjectEditStoryContract.usesV2(draft)
        if storyFlow, let story = payload["journeyStory"] { payload["journeyStory"] = try ProjectEditRichStoryContract.journeyStoryWithoutStandaloneEndingList(story) }
        guard storyFlow || !draft.chapters.contains(where: { $0.blocks != nil && !ProjectEditStoryContract.isLegacyProjection($0) }) else { throw ProjectEditError.invalidDraft }
        payload["chapters"] = .array(try draft.chapters.map { .object(try chapterPayload($0, product: draft.product, storyFlow: storyFlow, editing: topicID != nil)) })
        payload["tickets"] = .array(try draft.tickets.map { ticket in
            guard let price = ProjectEditValidation.decimal(ticket.price), let stock = Int(ticket.totalStock), let team = Int(ticket.teamSize) else { throw ProjectEditError.invalidDraft }
            let schedule = ticket.schedule(in: draft)
            var p: [String: ProjectEditJSON] = [
                "name": .string(ticket.name), "price": .number(price), "mode": .number(Decimal(draft.product.rawValue)),
                "totalStock": .number(Decimal(stock)), "teamSize": .number(Decimal(team)),
                "startTime": .string(ProjectEditValidation.dateTime(schedule.start)!),
                "endTime": .string(ProjectEditValidation.dateTime(schedule.end, endOfDay: true)!)
            ]
            if !ticket.description.isEmpty { p["description"] = .string(ticket.description) }
            p.merge(try ProjectTicketMeetingPoint.wireFields(ticket)) { _, edited in edited }
            p.merge(try ticket.saleTimePayloads()) { _, edited in edited }
            // Exact stored preference, including an untouched legacy value. The
            // server does not resolve date sync; start/end above already do so.
            if let sync = ticket.localMetadata["syncWithTheme"] { p["syncWithTheme"] = sync }
            return .object(p)
        })
        try ProjectEditStoryContract.validatePayload(payload)
        return payload
    }
    private static func chapterPayload(_ chapter: ProjectEditChapter, product: ProjectEditProduct, storyFlow: Bool, editing: Bool) throws -> [String: ProjectEditJSON] {
        guard ProjectChapterAtmosphere.canSubmit(chapter) else { throw ProjectEditError.invalidDraft }
        var ordered = chapter.nodes
        if storyFlow, let blocks = chapter.blocks {
            // Nodes absent from blocks retain their relative position at the end, matching source.
            let ids = blocks.filter { $0.kind == .node }.map(\.nodeID)
            let byID = Dictionary(uniqueKeysWithValues: chapter.nodes.map { ($0.id, $0) })
            ordered = try ids.map { id in guard let node = byID[id] else { throw ProjectEditError.invalidDraft }; return node }
            ordered += chapter.nodes.filter { !ids.contains($0.id) }
        }
        var p: [String: ProjectEditJSON] = ["name": .string(chapter.name), "description": .string(chapter.description)]
        for key in chapterCarryOver { if let value = chapter.preserved[key] { p[key] = value } }
        if editing, let id = chapter.preserved["id"] { p["id"] = id }
        if storyFlow { for key in ["opening", "ending"] { if let value = chapter.preserved[key] { p[key] = value } } }
        p["nodes"] = .array(ordered.enumerated().map { index, node in
            var row: [String: ProjectEditJSON] = ["name": .string(node.name), "sortID": .number(Decimal(index + 1)), "nodeTime": .number(Decimal(node.nodeTime))]
            for (key, value) in ["description": node.description, "address": node.address, "longitude": node.longitude, "latitude": node.latitude, "imgUrl": node.imgUrl] where !value.isEmpty { row[key] = .string(value) }
            if let id = node.templateID, id > 0 { row["templateId"] = .number(Decimal(id)) }
            for key in ProjectEditStoryContract.nodeFields where key != "id" || editing { if let value = node.localMetadata[key] { row[key] = value } }
            if row["clientNodeKey"] == nil { row["clientNodeKey"] = .string(node.id) }
            return .object(row)
        })
        if storyFlow {
            let rows = try ProjectEditStoryContract.materializedBlocks(chapter, ordered: ordered)
            p["description"] = .string(ProjectEditStoryContract.projectedDescription(rows))
            p["schemaVersion"] = .number(1); p["required"] = .number(1); p["blocks"] = .array(rows)
        }
        return p
    }
    public static func decodeEditDetail(_ data: Data, expectedTopicID: Int, owner: ProjectEditOwner) throws -> ProjectEditSnapshot {
        let response = try JSONDecoder().decode([String: ProjectEditJSON].self, from: data)
        guard response["code"]?.integer == 200, let body = response["data"]?.object,
              let topic = body["topic"]?.object, topic["id"]?.integer == expectedTopicID, expectedTopicID > 0,
              let editScope = body["editScope"]?.text.flatMap(ProjectEditScope.init(rawValue:)),
              let product = topic["productType"]?.integer.flatMap(ProjectEditProduct.init(rawValue:)),
              let chapters = body["chapters"]?.array, let tickets = body["tickets"]?.array else { throw ProjectEditError.invalidContract }
        func s(_ source: [String: ProjectEditJSON], _ key: String) -> String { source[key]?.text ?? "" }
        var d = ProjectEditDraft(product: product)
        d.owner = owner; d.name = s(topic, "name"); d.subtitle = s(topic, "subtitle"); d.description = s(topic, "description")
        d.startDate = s(topic, "startDate"); d.endDate = s(topic, "endDate"); d.recruitDeadline = s(topic, "recruitDeadline")
        d.imgUrl = s(topic, "imgUrl"); d.imgArr = s(topic, "imgArr"); d.publishToCreative = false
        d.openMerchantPool = topic["merchantStatus"]?.integer == 1; d.clubID = topic["clubId"]?.integer
        d.baseRevision = topic["updateTime"]?.text ?? topic["createTime"]?.text ?? ""
        guard !d.baseRevision.isEmpty else { throw ProjectEditError.invalidContract }
        d.categoryIDs = try s(topic, "categoryIds").split(separator: ",").map {
            guard let value = Int($0.trimmingCharacters(in: .whitespaces)), value > 0 else { throw ProjectEditError.invalidContract }; return value
        }
        d.collaboratorIDs = try (topic["collaboratorIds"]?.array ?? []).map { raw in
            guard let value = raw.integer, value > 0 else { throw ProjectEditError.invalidContract }; return value
        }
        for key in topicCarryOver { if let value = topic[key] { d.preserved[key] = value } }
        d.chapters = try chapters.enumerated().map { index, raw in
            guard let source = raw.object, let nodes = (source["cmsTopicNodeList"] ?? source["nodes"])?.array else { throw ProjectEditError.invalidContract }
            var c = ProjectEditChapter(); c.id = "chapter-\(source["id"]?.integer ?? index + 1)"
            c.name = s(source, "name"); c.description = s(source, "description")
            for key in ["id", "opening", "ending"] { if let value = source[key] { c.preserved[key] = value } }
            c.schemaVersion = source["schemaVersion"]?.integer ?? 1; c.required = source["required"]?.integer ?? 1
            for key in chapterCarryOver { if let value = source[key] { c.preserved[key] = value } }
            // Source aliases, rather than cosmetic UI colors, define the stored preset.
            // Preserve unknown values/types so a normal edit cannot silently turn
            // future data into DEFAULT. Only known values use the existing mapping.
            if ProjectChapterAtmosphere.canSubmit(c), let preset = ProjectChapterAtmosphere.selected(in: c) {
                c.preserved["atmospherePreset"] = .string(preset.rawValue)
            }
            var byServerID: [Int: String] = [:]
            c.nodes = try nodes.enumerated().map { ni, rawNode in
                guard let node = rawNode.object else { throw ProjectEditError.invalidContract }
                var n = ProjectEditNode(); n.id = c.id + "-node-\(node["id"]?.integer ?? ni + 1)"
                if let serverID = node["id"]?.integer { byServerID[serverID] = n.id }
                n.name = s(node, "name"); n.description = s(node, "description"); n.address = s(node, "address")
                n.longitude = s(node, "longitude"); n.latitude = s(node, "latitude"); n.imgUrl = s(node, "imgUrl")
                n.nodeTime = node["nodeTime"]?.integer ?? 30; n.templateID = node["templateId"]?.integer
                n.localMetadata = node; return n
            }
            if let rawStored = source["blocksJson"] {
                guard rawStored == .null || rawStored.text != nil else { throw ProjectEditError.invalidContract }
                c.preserved["_nativeStoredStoryFlow"] = .bool(!(rawStored.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            var storedBlocks = source["blocks"]
            if let json = source["blocksJson"]?.text, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                storedBlocks = try JSONDecoder().decode(ProjectEditJSON.self, from: Data(json.utf8))
            }
            if let rawBlocks = storedBlocks, rawBlocks != .null {
                guard let blocks = rawBlocks.array else { throw ProjectEditError.invalidContract }
                c.blocks = try blocks.enumerated().map { bi, rawBlock in
                    guard let block = rawBlock.object, Set(block.keys).isSubset(of: ProjectEditStoryContract.blockFields), let kind = block["type"]?.text.flatMap(ProjectEditBlock.Kind.init(rawValue:)) else { throw ProjectEditError.invalidContract }
                    var b = ProjectEditBlock(kind: kind, content: s(block, "content"), url: s(block, "url")); b.id = block["key"]?.text ?? c.id + "-block-\(bi + 1)"
                    let narrative = kind == .text && !(block["beat"]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if kind != .node && !narrative, ["nodeIndex", "nodeId", "nodeKey"].contains(where: { block[$0] != nil }) { throw ProjectEditError.invalidContract }
                    let metadata = block.filter { ProjectEditStoryContract.metadataFields.contains($0.key) }
                    b.sourceFields = metadata.isEmpty ? nil : metadata
                    if kind == .node || narrative {
                        if let key = block["nodeKey"]?.text, c.nodes.contains(where: { $0.id == key }) { b.nodeID = key }
                        else if let serverID = block["nodeId"]?.integer, let key = byServerID[serverID] { b.nodeID = key }
                        else if let index = block["nodeIndex"]?.integer, c.nodes.indices.contains(index) { b.nodeID = c.nodes[index].id }
                        else { throw ProjectEditError.invalidContract }
                    }
                    var shape = block
                    shape.removeValue(forKey: "nodeId"); shape.removeValue(forKey: "nodeKey")
                    if kind == .node || narrative, let nodeIndex = c.nodes.firstIndex(where: { $0.id == b.nodeID }) { shape["nodeIndex"] = .number(Decimal(nodeIndex)) }
                    try ProjectEditRichStoryContract.validateShape(shape, kind: kind)
                    return b
                }
            }
            return c
        }
        d.tickets = try tickets.enumerated().map { index, raw in
            guard let source = raw.object else { throw ProjectEditError.invalidContract }
            var t = ProjectEditTicket()
            // Flutter's PublishApi.editDetail preserves ticket list order without a
            // required ticket ID. This is a topic-scoped local row identity, never
            // a server ID or payload field. Identical fresh reads must compare equal.
            t.id = "topic-\(expectedTopicID)-ticket-index-\(index)"
            t.name = s(source, "name")
            if let rawPrice = source["price"], case .number(let price) = rawPrice { t.price = NSDecimalNumber(decimal: price).stringValue }
            t.totalStock = String(source["totalInventory"]?.integer ?? 100); t.teamSize = String(source["teamSize"]?.integer ?? 0)
            t.startTime = s(source, "startTime"); t.endTime = s(source, "endTime"); t.meetingPoint = s(source, "meetingPoint")
            t.gatherLng = ProjectTicketMeetingPoint.coordinateText("", original: source["gatherLng"])
            t.gatherLat = ProjectTicketMeetingPoint.coordinateText("", original: source["gatherLat"]); t.description = s(source, "description")
            t.saleStartTime = s(source, "saleStartTime"); t.saleEndTime = s(source, "saleEndTime"); t.localMetadata = source
            return t
        }
        try ProjectEditStoryContract.restoreMetadata(&d, body: body, topic: topic)
        return .init(topicID: expectedTopicID, scope: editScope, draft: d)
    }
}
public struct ProjectEditSnapshot: Codable, Equatable {
    public let topicID: Int?
    public let scope: ProjectEditScope
    public var draft: ProjectEditDraft
    public init(topicID: Int? = nil, scope: ProjectEditScope = .full, draft: ProjectEditDraft) {
        self.topicID = topicID; self.scope = scope; self.draft = draft
    }
}
