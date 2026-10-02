import Foundation

/// Lossless JSON for these legacy projections. Unknown fields are retained for conflict checks,
/// never promoted into editable identity, permission, money or moderation fields.
public enum MerchantContentValue: Codable, Equatable, Sendable {
    case null, bool(Bool), integer(Int), decimal(Decimal), string(String), array([Self]), object([String: Self])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .integer(v) }
        else if let v = try? c.decode(Decimal.self) { self = .decimal(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([Self].self) { self = .array(v) }
        else { self = .object(try c.decode([String: Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .null: try c.encodeNil(); case .bool(let v): try c.encode(v)
        case .integer(let v): try c.encode(v); case .decimal(let v): try c.encode(v)
        case .string(let v): try c.encode(v); case .array(let v): try c.encode(v); case .object(let v): try c.encode(v) }
    }
    public var object: [String: Self]? { if case .object(let v) = self { return v }; return nil }
    public var array: [Self]? { if case .array(let v) = self { return v }; return nil }
    public var text: String? { if case .string(let v) = self { return v }; return nil }
    public var integer: Int? {
        if case .integer(let v) = self { return v }
        if case .string(let v) = self, !v.isEmpty { return Int(v) }
        return nil
    }
    /// Game-session wire IDs/revisions must be integer JSON, never strings or fractional numbers.
    public var safeInteger: Int? {
        guard case .integer(let v) = self, (-9_007_199_254_740_991...9_007_199_254_740_991).contains(v) else { return nil }; return v
    }
    public var flag: Bool? { if case .bool(let v) = self { return v }; return nil }
    public subscript(_ key: String) -> Self { object?[key] ?? .null }
    public var display: String? {
        switch self { case .string(let v): return v; case .integer(let v): return String(v)
        case .decimal(let v): return NSDecimalNumber(decimal: v).stringValue; default: return nil }
    }
    public func decoded<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(self)) }
}

public enum MerchantContentFailure: Error, Equatable {
    case invalid, malformed, denied, changedSession, conflict, disabled, storage, unknown, locked
    case rejected(code: Int, message: String?)
    public var key: String {
        switch self { case .invalid: return "merchant.content.invalid"; case .malformed: return "merchant.content.malformed"
        case .denied: return "merchant.content.denied"; case .changedSession: return "merchant.content.sessionChanged"
        case .conflict: return "merchant.content.conflict"; case .disabled: return "merchant.content.disabled"
        case .storage: return "merchant.content.storage"; case .unknown, .locked: return "merchant.content.unknown"
        case .rejected: return "merchant.content.rejected" }
    }
}
public enum MerchantContentQuery: Codable, Hashable, Identifiable {
    case recruiting, projects, nodeAuthoring(chapterID: Int)
    case chapters(topicID: Int), applications, chapterNodes(topicID: Int?), upcoming(topicID: Int)
    case ownerApplications(topicID: Int), invitable(topicID: Int), pendingNodes(topicID: Int)
    case registrations(filter: Int), registration(id: Int), project(topicID: Int?), players(topicID: Int?)
    case city, claimable(keyword: String), cityPlacement, npc(nodeID: Int), voice(nodeID: Int)
    case gameEntries, game(activityID: Int), poster(nodeID: Int), liveCode(activityID: Int, nodeID: Int)
    public var id: String { String(describing: self) }
    public var key: String {
        switch self { case .recruiting: return "recruiting"; case .projects: return "projects"; case .nodeAuthoring: return "submitNode"; case .chapters: return "chapters"; case .applications: return "applications"; case .chapterNodes: return "nodes"
        case .upcoming: return "upcoming"; case .ownerApplications: return "reviews"; case .invitable: return "invitable"
        case .pendingNodes: return "nodeReviews"; case .registrations: return "registrations"; case .registration: return "registration"
        case .project: return "project"; case .players: return "players"; case .city: return "city"; case .claimable: return "claimable"
        case .cityPlacement: return "placement"; case .npc: return "npc"; case .voice: return "voice"
        case .gameEntries: return "games"; case .game: return "game"; case .poster: return "poster"; case .liveCode: return "liveCode" }
    }
    public var requiresProjects: Bool {
        switch self { case .gameEntries, .game, .npc, .voice, .poster, .liveCode: return false; default: return true }
    }
    public func validate() throws {
        switch self {
        case .nodeAuthoring(let id), .chapters(let id), .upcoming(let id), .ownerApplications(let id), .invitable(let id), .pendingNodes(let id),
             .registration(let id), .npc(let id), .voice(let id), .game(let id), .poster(let id): guard id > 0 else { throw MerchantContentFailure.invalid }
        case .chapterNodes(let id), .project(let id), .players(let id): if let id, id <= 0 { throw MerchantContentFailure.invalid }
        case .liveCode(let activity, let node): guard activity > 0, node > 0 else { throw MerchantContentFailure.invalid }
        case .registrations(let filter): guard (0...4).contains(filter) else { throw MerchantContentFailure.invalid }
        default: break
        }
    }
}
public struct MerchantContentSnapshot: Equatable {
    public let query: MerchantContentQuery
    public let scope: UUID
    public let access: MerchantAccess
    public let value: MerchantContentValue
    public let observedAt: Date
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.query == rhs.query && lhs.scope == rhs.scope && lhs.access == rhs.access && lhs.value == rhs.value }
    public var rows: [MerchantContentValue] { value.array ?? value["rows"].array ?? [] }
}
public enum MerchantRecruitMode: String {
    case chapters, registration, categoryMissing, notMerchant
    public static func fromServer(_ message: String) -> Self? {
        if message.contains("仅自由探索") { return .registration }
        if message.contains("品类") { return .categoryMissing }
        if message.contains("仅商家") { return .notMerchant }
        return nil
    }
}
public struct MerchantRegistrationContentDraft: Codable, Equatable {
    public var addressName = "", address = "", longitude = "", latitude = "", activityDesc = "", picUrl = "", limitNum = ""
    public init(detail: MerchantContentValue = .object([:])) {
        addressName = detail["addressName"].text ?? ""; address = detail["address"].text ?? ""
        longitude = detail["longitude"].display ?? ""; latitude = detail["latitude"].display ?? ""
        activityDesc = detail["activityDesc"].text ?? ""; picUrl = detail["picUrl"].text ?? ""; limitNum = detail["limitNum"].display ?? ""
    }
    public func fields() throws -> [String: MerchantContentValue] {
        func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trim(addressName).isEmpty, !trim(address).isEmpty, !trim(activityDesc).isEmpty,
              trim(limitNum).isEmpty || (Int(trim(limitNum)).map { $0 >= 0 } ?? false),
              picUrl.split(separator: ",").count <= 9 else { throw MerchantContentFailure.invalid }
        // startDate/endDate deliberately omitted: source preserves server date strings, never reformats them.
        return ["addressName": .string(trim(addressName)), "address": .string(trim(address)), "longitude": .string(trim(longitude)),
                "latitude": .string(trim(latitude)), "activityDesc": .string(trim(activityDesc)), "picUrl": .string(picUrl),
                "limitNum": .integer(Int(trim(limitNum)) ?? 0)]
    }
}
public struct MerchantChapterContentDraft: Codable, Equatable {
    public var templateID: Int?, name = "", description = "", address = "", longitude = "", latitude = "", imgUrl = "", businessTime = ""
    public init() {}
    public func fields(chapterID: Int) throws -> [String: MerchantContentValue] {
        guard chapterID > 0, let templateID, templateID > 0, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MerchantContentFailure.invalid }
        var fields: [String: MerchantContentValue] = ["chapterId": .integer(chapterID)]
        fields["templateId"] = .integer(templateID)
        for (k, v) in ["name": name, "description": description, "address": address, "longitude": longitude,
                       "latitude": latitude, "imgUrl": imgUrl, "businessTime": businessTime] { fields[k] = .string(v) }
        // xpValue is intentionally absent. Source blocked_by_backend_test records validated-but-unpersisted XP.
        return fields
    }
}
public struct MerchantCityPlacementDraft: Codable, Equatable {
    public var templateID: Int?, latitude = "", longitude = "", name = "", address = "", tags = "", coverImg = "", cityCode = ""
    public var addressConfirmed = false
    public init() {}
    public func fields() throws -> [String: String] {
        guard let templateID, templateID > 0, addressConfirmed else { throw MerchantContentFailure.invalid }
        var f = ["templateId": String(templateID), "radius": "80"]
        if !latitude.isEmpty || !longitude.isEmpty {
            guard let lat = Double(latitude), lat.isFinite, (-90...90).contains(lat),
                  let lng = Double(longitude), lng.isFinite, (-180...180).contains(lng) else { throw MerchantContentFailure.invalid }
            f["lat"] = latitude; f["lng"] = longitude
        }
        for (k, v) in ["name": name, "address": address, "tags": tags, "coverImg": coverImg, "cityCode": cityCode] where !v.isEmpty { f[k] = v }
        return f
    }
}

/// Bridge to Cooperation's separate supply lifecycle. No IDs are inferred or interchanged.
public struct MerchantContentSupplyContext: Equatable {
    public let applicationID: Int, chapterID: Int
    public let termsMode: String?, offerID: Int?, circleThemeCode: String?
    public let offerActive: Bool, offerStateKnown: Bool, canEnroll: Bool, canReconfirmOrPause: Bool
    public init(application: MerchantContentValue, recruitmentChapters: [MerchantContentValue]) throws {
        guard let id = application["id"].integer, id > 0, let chapter = application["chapterId"].integer, chapter > 0 else { throw MerchantContentFailure.invalid }
        applicationID = id; chapterID = chapter
        let matches = recruitmentChapters.filter { $0["id"].integer == chapter }
        let term = matches.count == 1 ? matches[0]["recruitStatus"]["termsMode"].text : nil
        termsMode = ["TRAFFIC", "PERK", "REVSHARE"].contains(term ?? "") ? term : nil
        offerID = application["offerId"].integer.flatMap { $0 > 0 ? $0 : nil }
        circleThemeCode = application["circleThemeCode"].text
        offerActive = application["offerActive"].flag == true || application["offerActive"].integer == 1
        offerStateKnown = application["offerActive"].flag != nil || [0, 1].contains(application["offerActive"].integer ?? -1)
        canEnroll = application["status"].integer == 1 && offerStateKnown && !offerActive && termsMode != nil
        canReconfirmOrPause = offerActive && offerID != nil && !(circleThemeCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
