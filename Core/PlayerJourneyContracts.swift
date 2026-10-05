import Foundation

/// Account participation, saved participants and completed gameplay are separate sources.
public enum ParticipationFilter: String, CaseIterable, Identifiable {
    case all, notStarted, inProgress, completed
    public var id: String { rawValue }
    public func includes(_ value: ParticipationRecord, now: Date = Date()) -> Bool {
        self == .all || value.order.summary(now: now).state.rawValue == rawValue
    }
}
public struct ParticipationPlayEntry: Hashable {
    public let registrationID: Int
    public let scope: PlaySessionScope
    public init?(registrationID: Int, scope: PlaySessionScope) {
        guard registrationID > 0, scope.isValid else { return nil }
        self.registrationID = registrationID; self.scope = scope
    }
}
public struct ParticipationRecord: Decodable, Equatable, Identifiable {
    public let order: OrderLifecycleDetail
    public var id: Int { order.id }
    public let name: String?
    public let address: String?
    public let cover: String?
    public let isTopic: Bool
    public let isFreeExplore: Bool
    public let sourceID: Int?
    public var destination: PlaySessionScope? {
        guard let id = sourceID, id > 0 else { return nil }
        return isTopic ? .topic(id) : .activity(id)
    }
    public var playEntry: ParticipationPlayEntry? {
        guard let destination else { return nil }
        return ParticipationPlayEntry(registrationID: id, scope: destination)
    }
    public init(from decoder: Decoder) throws {
        order = try OrderLifecycleDetail(from: decoder)
        let raw = try PlayWireValue(from: decoder)
        isTopic = raw["ownerType"].tolerantInteger == 1 || raw["cmsTopic"].object != nil
        let source = isTopic ? raw["cmsTopic"] : raw["cmsActivity"]
        name = Self.text(raw["activityTitle"]) ?? Self.text(source["name"]) ?? Self.text(source["title"])
        address = Self.text(source["address"]) ?? Self.text(source["addressName"])
        cover = Self.text(source["imgUrl"]) ?? Self.text(source["imgArr"])
        sourceID = [raw["ownerId"].tolerantInteger, source["id"].tolerantInteger].compactMap { $0 }.first { $0 > 0 }
        isFreeExplore = isTopic && (raw["purchaseKind"].tolerantInteger == 3 || source["productType"].tolerantInteger == 2)
    }
    static func text(_ value: PlayWireValue) -> String? {
        guard let value = value.text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
public struct ParticipationDetail: Decodable, Equatable, Identifiable {
    public let record: ParticipationRecord
    public var id: Int { record.id }
    public let description: String?
    public let nodeName: String?
    public let cooperateDate: String?
    public let rules: String?
    public let templateID: Int?
    public let templateName: String?
    public let needsModification: Bool
    public let showOrderStats: Bool
    public let total: Int?
    public let verified: Int?
    public var pending: Int? { if let total, let verified { return total - verified }; return nil }
    public let refundDeadline: String?
    public func canCancel(now: Date = Date()) -> Bool {
        // Current mini replaced Flutter's obsolete three-day heuristic with order status.
        let state = record.order.summary(now: now).state
        return !needsModification && (record.order.registrationStatus == 1 || state == .notStarted || state == .inProgress)
    }
    public var cancellationAction: OrderLifecycleAction { record.order.paymentStatus == 2 ? .refund : .cancel }
    public init(from decoder: Decoder) throws {
        record = try ParticipationRecord(from: decoder)
        let raw = try PlayWireValue(from: decoder)
        let source = raw["cmsTopic"].object == nil ? raw["cmsActivity"] : raw["cmsTopic"]
        description = ParticipationRecord.text(raw["activityDesc"]) ?? ParticipationRecord.text(source["description"])
        nodeName = ParticipationRecord.text(raw["nodeName"])
        cooperateDate = ParticipationRecord.text(raw["cooperateDate"])
        rules = ParticipationRecord.text(raw["ruleInstructions"])
        templateID = raw["templateId"].tolerantInteger.flatMap { $0 > 0 ? $0 : nil }
        templateName = ParticipationRecord.text(raw["templateName"])
        needsModification = raw["displayStatus"].text == "需修改"
        showOrderStats = raw["status"].tolerantInteger == 1
        if let total = raw["totalOrderNum"].tolerantInteger, let verified = raw["verifiedNum"].tolerantInteger,
           total >= 0, verified >= 0, verified <= total { self.total = total; self.verified = verified }
        else { total = nil; verified = nil }
        refundDeadline = ParticipationRecord.text(raw["refundDeadlineDisplay"])
    }
}
public struct CompletedPlayRecord: Decodable, Equatable {
    public let name: String?
    public let activityID: Int?
    public let topicID: Int?
    public let cover: String?
    public let total: Int?
    public let doneCount: Int?
    public let completed: Bool?
    public var destination: PlaySessionScope? {
        if let activityID, activityID > 0 { return .activity(activityID) }
        if let topicID, topicID > 0 { return .topic(topicID) }
        return nil // Never synthesize an activity ID from a topic or navigate to zero.
    }
    public init(from decoder: Decoder) throws {
        let raw = try PlayWireValue(from: decoder)
        guard raw.object != nil else { throw APIError.malformedResponse }
        name = ParticipationRecord.text(raw["name"])
        activityID = raw["activityId"].tolerantInteger
        topicID = raw["topicId"].tolerantInteger
        cover = ParticipationRecord.text(raw["cover"])
        total = raw["total"].tolerantInteger.flatMap { $0 >= 0 ? $0 : nil }
        doneCount = raw["doneCount"].tolerantInteger.flatMap { $0 >= 0 ? $0 : nil }
        completed = raw["completed"].bool
    }
}
