import Foundation

/// Lossless source values: no money/status defaults and no cross-domain identifier coercion.
public enum CoopFlowJSON: Codable, Equatable {
    case null, bool(Bool), number(Decimal), string(String), array([CoopFlowJSON]), object([String: CoopFlowJSON])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Decimal.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([CoopFlowJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: CoopFlowJSON].self)) }
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
    public subscript(_ key: String) -> CoopFlowJSON { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    public var rows: [CoopFlowJSON]? { if case .array(let v) = self { return v }; return nil }
    public var text: String? {
        switch self { case .string(let v): return v; case .number(let v): return NSDecimalNumber(decimal: v).stringValue; default: return nil }
    }
    public var integer: Int? {
        guard let text, let v = Int(text) else { return nil }; return v
    }
    public var flag: Bool? { if case .bool(let v) = self { return v }; return nil }
    public static func id(_ v: Int) -> Self { .number(Decimal(v)) }
    public func canonical() throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return try e.encode(self) }
}
public enum CoopFlowFailure: Error, Equatable {
    case disabled, invalid(String), stale, permission, conflict, ambiguous, storage, malformed, unavailable
    case server(Int, String?)
}
public struct CoopFlowIdentity: Codable, Equatable, Hashable {
    public enum Domain: String, Codable { case member, merchant, club, topic, invite, application, registration, offer, template, settlement }
    public let domain: Domain
    public let id: Int
    public init(_ domain: Domain, _ id: Int) throws {
        guard id > 0 else { throw CoopFlowFailure.invalid("identity") }; self.domain = domain; self.id = id
    }
}
public struct CoopFlowMoney: Equatable {
    public let amount: Decimal?
    /// Source cooperation contracts use CNY. Never convert to the current display market's currency.
    public let currency = "CNY"
    public init(_ source: CoopFlowJSON) { amount = source.text.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
}
public struct CoopFlowSettlement: Equatable {
    public enum Source: String { case finance, mybiz }
    public let source: Source
    public let record: CoopFlowJSON
    public var id: Int? { record[source == .finance ? "topicId" : "id"].integer }
    public var amount: CoopFlowMoney { CoopFlowMoney(record[source == .finance ? "myIncome" : "amount"]) }
    public var payee: String? { source == .finance ? "organizer" : record["payeeType"].text }
    public var status: String {
        if source == .finance {
            guard let settled = record["settled"].flag else { return "unknown" }
            guard settled, amount.amount != nil else { return "pending" }
            guard let arrived = record["myIncomeArrived"].flag else { return "unknown" }
            return arrived ? "credited" : "inTransit"
        }
        switch record["status"].integer { case 0: return "inTransit"; case 1: return "credited"; case 2: return "void"; default: return "unknown" }
    }
}
public struct CoopFlowNearbyPartner: Equatable {
    public let source: CoopFlowJSON
    public var merchantID: Int? { source["id"].integer }
    public var memberID: Int? { source["memberId"].integer }
    public var canInvite: Bool { source["canInvite"].flag == true && (memberID ?? 0) > 0 }
    public var dialablePhone: String? {
        guard source["canCall"].flag == true, let value = source["phone"].text, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }; return value
    }
}
public enum CoopFlowHandle: Int, Codable { case accept = 1, reject = 2, cancel = 3 }
public enum CoopFlowTargetKind: Int, Codable { case merchant = 0, club = 1
    public var wire: String { self == .merchant ? "merchant" : "club" }
}
public enum CoopFlowCompensation: Equatable { case traffic, fixed(Decimal) }
public struct CoopFlowInvitation: Equatable {
    public let kind: CoopFlowTargetKind
    /// Merchant invitations use memberId, not merchant.id. Club invitations use clubId.
    public let recipient: CoopFlowIdentity
    public let topicID: Int
    public let message: String
    public let compensation: CoopFlowCompensation
    public let originApplyID: Int?
    public let scope: String?
    public init(kind: CoopFlowTargetKind, recipient: CoopFlowIdentity, topicID: Int, message: String,
                compensation: CoopFlowCompensation = .traffic, originApplyID: Int? = nil, scope: String? = nil) throws {
        guard recipient.domain == (kind == .merchant ? .member : .club), topicID > 0,
              originApplyID == nil || (kind == .club && originApplyID! > 0) else { throw CoopFlowFailure.invalid("recipient") }
        if case .fixed(let fee) = compensation { guard fee > 0 else { throw CoopFlowFailure.invalid("fixedFee") } }
        self.kind = kind; self.recipient = recipient; self.topicID = topicID; self.message = message
        self.compensation = compensation; self.originApplyID = originApplyID; self.scope = scope
    }
}
/// Local review entry derived only from a received, pending application in the current session.
/// A club ID is never substituted with a merchant/member/application ID. This is not a write grant.
public struct CoopFlowInvitationContext: Identifiable, Equatable {
    public let session: CoopFlowSession
    public let recipient: CoopFlowIdentity
    public let recipientName: String
    public let topicID: Int
    public let originApplyID: Int?
    public let kind: CoopFlowTargetKind
    public let scope: String?
    public var id: String { "\(session.accountID):\(session.epoch):\(kind.rawValue):\(originApplyID ?? 0):\(topicID):\(recipient.id)" }

    public init?(candidate: CoopFlowTargetCandidate, topic: CoopFlowOwnedTopic, scope: String?, session: CoopFlowSession?) {
        guard let session, topic.inviteWindowOpen == true, scope == nil || scope == "MERCHANT" else { return nil }
        self.session = session; self.recipient = candidate.recipient; self.recipientName = candidate.name
        self.topicID = topic.id; self.kind = candidate.kind; self.originApplyID = nil; self.scope = scope
    }

    public init?(receivedApplication row: CoopFlowJSON, session: CoopFlowSession?) {
        guard let session, row["status"].integer == 0,
              let topic = row["topicId"].integer, topic > 0,
              let apply = row["applyId"].integer, apply > 0,
              let club = row["clubId"].integer, let recipient = try? CoopFlowIdentity(.club, club) else { return nil }
        let scope = row["scope"].text?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Unknown ownership scopes are not downgraded to personal authority.
        guard row["scope"] == .null || scope == "" || scope == "MERCHANT" else { return nil }
        self.session = session; self.recipient = recipient
        self.recipientName = row["clubName"].text ?? ""
        self.topicID = topic; self.kind = .club; self.originApplyID = apply; self.scope = scope == "MERCHANT" ? scope : nil
    }

    public func invitation(message: String, compensation: CoopFlowCompensation,
                           currentSession: CoopFlowSession?) throws -> CoopFlowInvitation {
        guard currentSession == session else { throw CoopFlowFailure.stale }
        return try CoopFlowInvitation(kind: kind, recipient: recipient, topicID: topicID, message: message,
                                      compensation: compensation, originApplyID: originApplyID, scope: scope)
    }
}

public struct CoopFlowPerkTemplate: Equatable {
    public let name: String
    public let type: Int
    public let retailValue: Decimal
    public let unitCost: Decimal?
    public let quota: Int
    public let validEnd: String?
    public init(name: String, type: Int, retailValue: Decimal, unitCost: Decimal?, quota: Int, validEnd: String?) throws {
        func money(_ value: Decimal, positive: Bool) -> Bool {
            var v = value; var rounded = Decimal(); NSDecimalRound(&rounded, &v, 2, .plain)
            return rounded == value && value <= Decimal(string: "99999999.99")! && (positive ? value > 0 : value >= 0)
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, (0...2).contains(type), quota > 0,
              money(retailValue, positive: true), unitCost.map({ money($0, positive: false) }) ?? true else { throw CoopFlowFailure.invalid("perkTemplate") }
        if let validEnd {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.isLenient = false
            guard let date = formatter.date(from: validEnd), formatter.string(from: date) == validEnd else { throw CoopFlowFailure.invalid("validEnd") }
        }
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines); self.type = type
        self.retailValue = retailValue; self.unitCost = unitCost; self.quota = quota; self.validEnd = validEnd
    }
}
/// Immutable request review. Financial/legal/contact effects remain independently disabled at execution.
public enum CoopFlowMutation: Equatable {
    case invite(CoopFlowInvitation)
    case handle(inviteID: Int, action: CoopFlowHandle, reason: String?)
    case apply(topicID: Int), withdraw(topicID: Int), decline(applyID: Int, scope: String?)
    case confirm(registrationID: Int), reject(registrationID: Int)
    case createTemplate(CoopFlowPerkTemplate), deleteTemplate(id: Int)
    case attachPerks(inviteID: Int, templateIDs: [Int])
    case enrollOffer(fields: [String: CoopFlowJSON])
    case reconfirmOffer(id: Int), pauseOffer(id: Int)
    case review(topicID: Int, memberID: Int, rating: Int, comment: String?)
    case complaint(topicID: Int, reason: String)
    case contact(inviteID: Int)
    public var path: String {
        let suffix: String
        switch self {
        case .invite: suffix = "invite"; case .handle: suffix = "handle"
        case .apply: suffix = "pool/apply"; case .withdraw: suffix = "pool/withdraw"; case .decline: suffix = "pool/decline"
        case .confirm: suffix = "candidates/confirm"; case .reject: suffix = "candidates/reject"
        case .createTemplate: suffix = "perk-template/save"; case .deleteTemplate: suffix = "perk-template/delete"
        case .attachPerks: suffix = "perks/attach"; case .enrollOffer: suffix = "offer/enroll"
        case .reconfirmOffer: suffix = "offer/circle-supply/reconfirm-current"; case .pauseOffer: suffix = "offer/circle-supply/pause"
        case .review: suffix = "review/save"; case .complaint: suffix = "complaint/report"; case .contact: suffix = "contact"
        }; return "api/coop/" + suffix
    }
    public var requiresSeparateEnablement: Bool {
        switch self { case .invite, .handle, .contact, .complaint, .enrollOffer: return true; default: return false }
    }
    public func body() throws -> CoopFlowJSON {
        var b: [String: CoopFlowJSON] = [:]
        func positive(_ n: Int) throws -> CoopFlowJSON { guard n > 0 else { throw CoopFlowFailure.invalid("id") }; return .id(n) }
        switch self {
        case .invite(let f):
            b = ["inviteType": .id(f.kind.rawValue), "toType": .string(f.kind.wire), "toId": .id(f.recipient.id), "topicId": .id(f.topicID),
                 "shareMode": .id(0), "message": .string(f.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (f.kind == .club ? "邀请贵俱乐部来参加活动" : "邀请贵店承接本主题合作") : f.message.trimmingCharacters(in: .whitespacesAndNewlines))]
            if case .fixed(let fee) = f.compensation { b["shareMode"] = .id(2); b["fixedFee"] = .number(fee) }
            if let origin = f.originApplyID { b["originApplyId"] = .id(origin) }
            if let scope = f.scope, !scope.isEmpty { b["scope"] = .string(scope) }
        case .handle(let id, let action, let reason):
            b = ["id": try positive(id), "status": .id(action.rawValue)]
            if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { b[action == .cancel ? "message" : "handleReason"] = .string(reason) }
        case .apply(let id), .withdraw(let id): b = ["topicId": try positive(id)]
        case .decline(let id, let scope):
            b = ["applyId": try positive(id)]; if let scope, !scope.isEmpty { b["scope"] = .string(scope) }
        case .confirm(let id), .reject(let id): b = ["registrationId": try positive(id)]
        case .createTemplate(let f):
            b = ["name": .string(f.name), "perkType": .id(f.type), "retailValue": .number(f.retailValue), "quota": .id(f.quota), "validEnd": f.validEnd.map(CoopFlowJSON.string) ?? .null]
            if let cost = f.unitCost { b["unitCost"] = .number(cost) }
        case .deleteTemplate(let id): b = ["id": try positive(id)]
        case .attachPerks(let id, let templates):
            guard !templates.isEmpty, Set(templates).count == templates.count else { throw CoopFlowFailure.invalid("templates") }
            b = ["inviteId": try positive(id), "templateIds": .array(try templates.map(positive))]
        case .enrollOffer(let fields):
            b = fields.filter { !["id", "topicId", "merchantId", "quotaUsed", "status"].contains($0.key) }
            guard (b["chapterId"]?.integer ?? 0) > 0, let mode = b["termsMode"]?.text,
                  ["PERK", "REVSHARE", "TRAFFIC"].contains(mode),
                  Set(b.keys).isSubset(of: ["chapterId", "termsMode", "perkTemplateId", "quotaTotal", "perHeadFee"]) else { throw CoopFlowFailure.invalid("offerShape") }
            if mode == "PERK" {
                guard (b["perkTemplateId"]?.integer ?? 0) > 0, (b["quotaTotal"]?.integer ?? 0) > 0, b["perHeadFee"] == nil else { throw CoopFlowFailure.invalid("perk") }
            } else if mode == "REVSHARE" {
                guard let fee = CoopFlowMoney(b["perHeadFee"] ?? .null).amount, fee >= 0, b["perkTemplateId"] == nil, b["quotaTotal"] == nil else { throw CoopFlowFailure.invalid("perHeadFee") }
            } else {
                guard b["perkTemplateId"] == nil, b["quotaTotal"] == nil, b["perHeadFee"] == nil else { throw CoopFlowFailure.invalid("traffic") }
            }
        case .reconfirmOffer(let id), .pauseOffer(let id): b = ["offerId": try positive(id)]
        case .review(let topic, let member, let rating, let comment):
            guard (1...5).contains(rating) else { throw CoopFlowFailure.invalid("rating") }
            b = ["topicId": try positive(topic), "toId": try positive(member), "rating": .id(rating)]
            if let comment { b["comment"] = .string(comment) }
        case .complaint(let topic, let reason):
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CoopFlowFailure.invalid("reason") }
            b = ["topicId": try positive(topic), "reason": .string(reason)]
        case .contact(let id): b = ["id": try positive(id)]
        }
        return .object(b)
    }
}

public struct CoopFlowOfferContext: Equatable {
    public enum TermsMode: String { case perk = "PERK", revshare = "REVSHARE", traffic = "TRAFFIC" }
    public let chapterID: Int
    public let termsMode: TermsMode
    public let offerID: Int?
    public init(chapterID: Int, termsMode: TermsMode, offerID: Int? = nil) throws {
        guard chapterID > 0, offerID == nil || offerID! > 0 else { throw CoopFlowFailure.invalid("offerContext") }
        self.chapterID = chapterID; self.termsMode = termsMode; self.offerID = offerID
    }
}
public struct CoopFlowOfferDraft: Equatable {
    public let context: CoopFlowOfferContext
    public let templateID: Int?
    public let quota: Int?
    public let perHeadFee: Decimal?
    public init(context: CoopFlowOfferContext, templateID: Int? = nil, quota: Int? = nil, perHeadFee: Decimal? = nil) throws {
        guard context.offerID == nil else { throw CoopFlowFailure.invalid("offerAlreadyActive") }
        switch context.termsMode {
        case .perk: guard (templateID ?? 0) > 0, (quota ?? 0) > 0, perHeadFee == nil else { throw CoopFlowFailure.invalid("perk") }
        case .revshare: guard let fee = perHeadFee, fee >= 0, templateID == nil, quota == nil else { throw CoopFlowFailure.invalid("perHeadFee") }
        case .traffic: guard templateID == nil, quota == nil, perHeadFee == nil else { throw CoopFlowFailure.invalid("traffic") }
        }
        self.context = context; self.templateID = templateID; self.quota = quota; self.perHeadFee = perHeadFee
    }
    public var mutation: CoopFlowMutation {
        var fields: [String: CoopFlowJSON] = ["chapterId": .id(context.chapterID), "termsMode": .string(context.termsMode.rawValue)]
        if let templateID { fields["perkTemplateId"] = .id(templateID) }
        if let quota { fields["quotaTotal"] = .id(quota) }
        if let perHeadFee { fields["perHeadFee"] = .number(perHeadFee) }
        return .enrollOffer(fields: fields)
    }
}

public enum CoopFlowContractState: Equatable {
    case historicalReadOnly, frozen, pending, accepted, ended, unknown
    public init(invite: CoopFlowJSON) {
        if invite["inviteType"].integer == 2 { self = .historicalReadOnly }
        else if invite["termsFrozen"].flag == true { self = .frozen }
        else { switch invite["status"].integer { case 0: self = .pending; case 1: self = .accepted; case 2, 3, 4, 5: self = .ended; default: self = .unknown } }
    }
    /// UI affordance only. Server permissions must be re-read immediately before dispatch.
    public func actions(isFrom: Bool, isTo: Bool) -> [CoopFlowHandle] {
        switch self {
        case .pending: return (isTo ? [.accept, .reject] : []) + (isFrom ? [.cancel] : [])
        case .accepted: return isFrom ? [.cancel] : [] // Flutter detail exposes cancellation in sent direction only.
        default: return []
        }
    }
}

/// Audited financial source contract only. No creation/refund execution is exposed by the native adapter.
public enum CoopFlowFinancialContract {
    public static let depositCreatePath = "api/coop/deposit/create/app"
    public static let depositStatusPath = "api/coop/deposit/status"
    public static let refundRetryPath = "api/coop/deposit/refund/retry"
    public static func paymentStatus(_ value: CoopFlowJSON) -> String {
        guard let raw = value["paymentStatus"].text, ["success", "pending", "failed", "unknown"].contains(raw) else { return "unknown" }; return raw
    }
    /// A provider callback is never an accounting receipt. Missing fields mean an ambiguous outcome.
    public static func refundReceipt(_ envelope: CoopFlowJSON) throws -> String {
        guard envelope["code"].integer == 200,
              case .string = envelope["data"]["refundState"],
              let message = envelope["msg"].text, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CoopFlowFailure.ambiguous }
        return message
    }
}
