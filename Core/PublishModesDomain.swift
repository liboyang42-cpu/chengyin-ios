import Foundation

public enum PublishModesError: Error, Equatable {
    case invalidDraft, invalidContract, unavailable, changedSession, forbidden, staleReview, conflict, uncertain, storage
    case rejected(String)
}
public enum PublishingRegion: String, Codable { case china, unitedStates }
public struct PublishingSession: Codable, Equatable {
    public let namespace: String
    public let accountID: Int
    public let epoch: UUID
    public let role: String
    public let region: PublishingRegion
    public init(namespace: String, accountID: Int, epoch: UUID, role: String, region: PublishingRegion) {
        self.namespace = namespace; self.accountID = accountID; self.epoch = epoch; self.role = role; self.region = region
    }
    public var storageKey: String { "\(namespace)|\(region.rawValue)|\(accountID)" }
}
/// Numeric identity alone is never enough to address a published resource.
public struct PublishedResource: Codable, Equatable, Hashable, Identifiable {
    public var id: String { "\(kind.rawValue):\(value)" }
    public enum Kind: String, Codable, CaseIterable { case topic, activity, template }
    public let kind: Kind
    public let value: Int
    public init(kind: Kind, value: Int) throws {
        guard value > 0 else { throw PublishModesError.invalidContract }; self.kind = kind; self.value = value
    }
}
public struct PublishingCapability: Equatable {
    public let role: String
    public let remaining: Int?
    public let simple: Bool
    public let pro: Bool
    public init(_ body: [String: ProjectEditJSON]) {
        let supplied = body["role"]?.text ?? "player"
        role = ["club", "merchant"].contains(supplied) ? supplied : "player"
        remaining = body["quota"]?.object?["themesRemaining"]?.integer
        simple = body["permission"]?.object?["canSimplePublish"] != .bool(false)
        pro = body["permission"]?.object?["canProPublish"] != .bool(false)
    }
    public var activity: Bool { role == "club" }
    public var quotaExhausted: Bool { remaining.map { $0 <= 0 } ?? false }
}
public struct PublishingPlace: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let address: String
    public let latitude: Double
    public let longitude: Double
    public init(id: String, name: String, address: String, latitude: Double, longitude: Double) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { throw PublishModesError.invalidDraft }
        self.id = id; self.name = name; self.address = address; self.latitude = latitude; self.longitude = longitude
    }
}
public struct QuickPublishNode: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var name = ""
    public var description = ""
    /// AI output never supplies a confirmed place. Only explicit picker confirmation does.
    public var confirmedPlace: PublishingPlace?
    public init() {}
}
public struct QuickPublishDraft: Codable, Equatable {
    public var subtitle: String?
    public var aiTraceID: String?
    public var title = ""
    public var description = ""
    public var product: ProjectEditProduct = .city
    public var nodes: [QuickPublishNode] = []
    public init() {}
    public static func parseAI(_ data: [String: ProjectEditJSON]) throws -> Self {
        guard let raw = data["draft"]?.object, let title = raw["title"]?.text,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let list = raw["nodes"]?.array, !list.isEmpty, list.count <= 3 else { throw PublishModesError.invalidDraft }
        var result = Self(); result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.description = raw["storyline"]?.text ?? ""
        result.nodes = try list.map { value in
            guard let object = value.object else { throw PublishModesError.invalidDraft }
            let names = ["merchantName", "roleText", "task"].map { (object[$0]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let name = names.first(where: { !$0.isEmpty }) else { throw PublishModesError.invalidDraft }
            var node = QuickPublishNode(); node.name = name
            node.description = ["task", "roleText"].compactMap { object[$0]?.text }.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
            return node
        }
        return result
    }
    /// This is a seed, not publication. ProjectEdit retains its own full validation and review.
    public func professionalSeed(now: Date = Date(), calendar: Calendar = .current) throws -> ProjectEditDraft {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !nodes.isEmpty,
              nodes.allSatisfy({ $0.confirmedPlace != nil && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw PublishModesError.invalidDraft }
        var result = ProjectEditDraft(product: product); result.name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.description = description.trimmingCharacters(in: .whitespacesAndNewlines); result.subtitle = subtitle ?? ""
        if let aiTraceID, !aiTraceID.isEmpty { result.preserved["aiTraceId"] = .string(aiTraceID) }
        result.preserved["publishMode"] = .string("ai_simple")
        var chapter = ProjectEditChapter(); chapter.id = "quick_chapter"; chapter.name = "路线"; chapter.description = result.description
        chapter.nodes = nodes.enumerated().map { index, node in
            var n = ProjectEditNode(); n.id = "quick_node_\(index + 1)"; n.name = node.name.trimmingCharacters(in: .whitespacesAndNewlines); n.description = node.description
            if let place = node.confirmedPlace { n.address = place.address.isEmpty ? place.name : place.address; n.latitude = String(place.latitude); n.longitude = String(place.longitude) }
            return n
        }
        result.chapters = [chapter]
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var ticket = ProjectEditTicket(); ticket.name = product == .city ? "城市定向票" : "自由探索票"; ticket.price = "0"
        ticket.startTime = formatter.string(from: now); ticket.endTime = formatter.string(from: calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now)) ?? now)
        formatter.dateFormat = "yyyy-MM-dd"; ticket.saleStartTime = formatter.string(from: now)
        ticket.saleEndTime = formatter.string(from: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now)
        ticket.localMetadata["refundSupported"] = .bool(true); result.tickets = [ticket]
        return result
    }
}
public struct ActivityPublishTicket: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var name = ""
    public var price = ""
    public var stock = ""
    public var start = ""
    public var end = ""
    public init() {}
    public func wire(activityStart: String, activityEnd: String) throws -> ProjectEditJSON {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let price = ProjectEditValidation.decimal(price), price >= 0, let stock = Int(stock), stock > 0,
              let start = ProjectEditValidation.dateTime(start), let end = ProjectEditValidation.dateTime(end), end > start,
              start >= activityStart, end <= activityEnd else { throw PublishModesError.invalidDraft }
        return .object(["name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)), "price": .number(price), "totalStock": .number(Decimal(stock)), "startTime": .string(start), "endTime": .string(end)])
    }
}
public struct ActivityPublishDraft: Codable, Equatable {
    public var name = ""
    public var description = ""
    public var coverURL = ""
    public var place: PublishingPlace?
    public var addressName = ""
    public var start = ""
    public var end = ""
    /// Play-template selection, never a topic ID or an activity ID.
    public var playTemplateID: AuthoringPlayTemplateID?
    public var categoryIDs: [Int] = []
    public var collaboratorMemberIDs: [Int] = []
    public var tickets: [ActivityPublishTicket] = []
    public init() {}
    public func wire() throws -> [String: ProjectEditJSON] {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !addressName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !coverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let start = ProjectEditValidation.dateTime(start), let end = ProjectEditValidation.dateTime(end), end > start,
              let template = playTemplateID, !categoryIDs.isEmpty, categoryIDs.allSatisfy({ $0 > 0 }),
              collaboratorMemberIDs.allSatisfy({ $0 > 0 }), Set(collaboratorMemberIDs).count == collaboratorMemberIDs.count,
              !tickets.isEmpty else { throw PublishModesError.invalidDraft }
        var body: [String: ProjectEditJSON] = ["name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)), "description": .string(description.trimmingCharacters(in: .whitespacesAndNewlines)), "imgUrl": .string(coverURL), "imgArr": .string(coverURL), "addressName": .string(addressName), "startDate": .string(start), "endDate": .string(end), "templateId": .number(Decimal(template.rawValue)), "categoryIds": .string(categoryIDs.map(String.init).joined(separator: ",")), "tickets": .array(try tickets.map { try $0.wire(activityStart: start, activityEnd: end) }), "collaborators": .array(collaboratorMemberIDs.map { .number(Decimal($0)) })]
        if let place { body["address"] = .string(place.address); body["longitude"] = .string(String(place.longitude)); body["latitude"] = .string(String(place.latitude)) }
        return body
    }
}
/// Topic-only rewards: activity tickets use their distinct contract above.
public struct PublishingTopicRewards: Equatable {
    public var selfPlay = false
    public var selfPlayPrice = ""
    public var selfPlayQuota = ""
    public var medalName = ""
    public var medalImage = ""
    public var couponID = 0
    public init() {}
    public init(draft: ProjectEditDraft) {
        func text(_ key: String) -> String {
            if let text = draft.preserved[key]?.text { return text }
            if let raw = draft.preserved[key], case .number(let value) = raw { return NSDecimalNumber(decimal: value).stringValue }
            return ""
        }
        selfPlay = draft.preserved["selfPlay"]?.integer == 1
        selfPlayPrice = text("selfPlayPrice"); selfPlayQuota = text("selfPlayQuota")
        medalName = text("finishMedalName"); medalImage = text("finishMedalImg")
        couponID = draft.preserved["completeRewardCouponId"]?.integer ?? 0
    }
    public func applying(to source: ProjectEditDraft) throws -> ProjectEditDraft {
        guard couponID >= 0,
              selfPlayPrice.isEmpty || ProjectEditValidation.decimal(selfPlayPrice).map({ $0 >= 0 }) == true,
              selfPlayQuota.isEmpty || Int(selfPlayQuota).map({ $0 >= 0 }) == true else { throw PublishModesError.invalidDraft }
        return updatingDraft(source)
    }
    /// Local keystrokes only; applying(to:) validates before review or dispatch.
    public func updatingDraft(_ source: ProjectEditDraft) -> ProjectEditDraft {
        var draft = source
        draft.preserved["selfPlay"] = .number(selfPlay ? 1 : 0)
        draft.preserved["selfPlayPrice"] = selfPlayPrice.isEmpty ? .number(0) : .string(selfPlayPrice)
        draft.preserved["selfPlayQuota"] = selfPlayQuota.isEmpty ? .number(0) : .string(selfPlayQuota)
        draft.preserved["finishMedalName"] = medalName.isEmpty ? nil : .string(medalName)
        draft.preserved["finishMedalImg"] = medalImage.isEmpty ? nil : .string(medalImage)
        draft.preserved["completeRewardCouponId"] = .number(Decimal(couponID)); return draft
    }
}
