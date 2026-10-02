import Foundation

public enum CooperationDirection: String, CaseIterable, Hashable { case received, sent }
public struct CooperationInviteKey: Hashable {
    public let id: Int
    public let direction: CooperationDirection
    public init(id: Int, direction: CooperationDirection) { self.id = id; self.direction = direction }
}

/// Source: coop_invite_row.dart. Unknown states remain unknown; missing amounts never become zero.
public struct CooperationInvite: Decodable, Equatable {
    public let id: Int
    public let inviteType: Int?
    public let fromId: Int?
    public let toType: String?
    public let toId: Int?
    public let topicId: Int?
    public let gameId: Int?
    public let status: Int?
    public let message: String?
    public let handleReason: String?
    public let shareMode: Int?
    public let shareRate: Double?
    public let fixedFee: Double?
    public let depositOwed: Bool
    public let depositAmount: Double?
    public let depositRefundPending: Bool
    public let termsFrozen: Bool
    public let expireTime: CooperationSourceTime?
    public let createTime: CooperationSourceTime?
    public let partner: CooperationPartner?
    public let coverURL: String?
    public var legacyReadonly: Bool { inviteType == 2 }
    public var statusKey: String {
        guard let status, (0...5).contains(status) else { return "cooperation.status.unknown" }
        return "cooperation.invite.status.\(status)"
    }
    enum CodingKeys: String, CodingKey {
        case id, inviteType, fromId, toType, toId, topicId, gameId, status, message, handleReason
        case shareMode, shareRate, fixedFee, depositOwed, depositAmount, depositRefundPending, termsFrozen
        case expireTime, createTime, partner, cover, topicCover, topicImgUrl
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.positiveID(.id)
        inviteType = try c.decodeIfPresent(Int.self, forKey: .inviteType)
        fromId = try c.decodeIfPresent(Int.self, forKey: .fromId)
        toType = try c.decodeIfPresent(String.self, forKey: .toType)
        toId = try c.decodeIfPresent(Int.self, forKey: .toId)
        topicId = try c.decodeIfPresent(Int.self, forKey: .topicId)
        gameId = try c.decodeIfPresent(Int.self, forKey: .gameId)
        status = try c.decodeIfPresent(Int.self, forKey: .status)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        handleReason = try c.decodeIfPresent(String.self, forKey: .handleReason)
        shareMode = try c.decodeIfPresent(Int.self, forKey: .shareMode)
        shareRate = try c.decodeIfPresent(Double.self, forKey: .shareRate)
        fixedFee = try c.decodeIfPresent(Double.self, forKey: .fixedFee)
        depositOwed = try c.decodeIfPresent(Bool.self, forKey: .depositOwed) ?? false
        depositAmount = try c.decodeIfPresent(Double.self, forKey: .depositAmount)
        depositRefundPending = try c.decodeIfPresent(Bool.self, forKey: .depositRefundPending) ?? false
        termsFrozen = try c.decodeIfPresent(Bool.self, forKey: .termsFrozen) ?? false
        expireTime = try c.decodeIfPresent(CooperationSourceTime.self, forKey: .expireTime)
        createTime = try c.decodeIfPresent(CooperationSourceTime.self, forKey: .createTime)
        partner = try c.decodeIfPresent(CooperationPartner.self, forKey: .partner)
        coverURL = try [c.decodeIfPresent(String.self, forKey: .cover), c.decodeIfPresent(String.self, forKey: .topicCover), c.decodeIfPresent(String.self, forKey: .topicImgUrl)].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
public struct CooperationPartner: Decodable, Equatable {
    public let name: String?
    public let leaderName: String?
    public let phone: String?
}
/// Keep source wall-time text verbatim. No timezone/countdown is invented for unzoned strings.
public enum CooperationSourceTime: Decodable, Equatable {
    case text(String), milliseconds(Double)
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(String.self) { self = .text(value) }
        else { self = .milliseconds(try c.decode(Double.self)) }
    }
    public var date: Date? {
        if case .milliseconds(let value) = self { return Date(timeIntervalSince1970: value / 1_000) }
        return nil
    }
}
public struct CooperationSlot: Decodable, Equatable {
    public let pending: Int?
    public let accepted: Int?
    public let cap: Int?
}
public struct CooperationSlots: Decodable, Equatable {
    public let byGame: [String: CooperationSlot]?
    public let byTopic: [String: CooperationSlot]?
}
public struct CooperationOccupancy: Equatable {
    public enum Kind: Equatable { case gamePending, topicAccepted }
    public let kind: Kind
    public let count: Int
    public let capacity: Int
}
public struct CooperationInvites: Decodable, Equatable {
    public let sent: [CooperationInvite]
    public let received: [CooperationInvite]
    public let slots: CooperationSlots?
    enum CodingKeys: String, CodingKey { case sent, received, slots }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sent = try c.decodeIfPresent([CooperationInvite].self, forKey: .sent) ?? []
        received = try c.decodeIfPresent([CooperationInvite].self, forKey: .received) ?? []
        slots = try c.decodeIfPresent(CooperationSlots.self, forKey: .slots)
    }
    public func rows(_ direction: CooperationDirection) -> [CooperationInvite] { direction == .sent ? sent : received }
    public func occupancy(for invite: CooperationInvite) -> CooperationOccupancy? {
        if let game = invite.gameId, let slot = slots?.byGame?[String(game)] {
            guard let count = slot.pending, let cap = slot.cap, count >= 0, cap >= 0 else { return nil }
            return CooperationOccupancy(kind: .gamePending, count: count, capacity: cap)
        }
        if let topic = invite.topicId, let slot = slots?.byTopic?[String(topic)],
           let count = slot.accepted, let cap = slot.cap, count >= 0, cap >= 0 {
            return CooperationOccupancy(kind: .topicAccepted, count: count, capacity: cap)
        }
        return nil
    }
}
public struct CooperationInviteDetail: Equatable {
    public let row: CooperationInvite
    public let occupancy: CooperationOccupancy?
    public init(row: CooperationInvite, occupancy: CooperationOccupancy?) { self.row = row; self.occupancy = occupancy }
}

/// Application history is distinct from the open pool and must never be reconstructed from it.
public struct CooperationApplication: Decodable, Equatable {
    public let applyId: Int
    public let topicId: Int
    public let status: Int?
    public let topicName: String?
    public let clubId: Int?
    public let clubName: String?
    public let merchantNick: String?
    public let message: String?
    public let startDate: CooperationSourceTime?
    public let scope: String?
    public var statusKey: String {
        guard let status, (0...3).contains(status) else { return "cooperation.status.unknown" }
        return "cooperation.application.status.\(status)"
    }
    enum CodingKeys: String, CodingKey { case applyId, topicId, status, topicName, clubId, clubName, merchantNick, message, startDate, scope }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        applyId = try c.positiveID(.applyId); topicId = try c.positiveID(.topicId)
        status = try c.decodeIfPresent(Int.self, forKey: .status)
        topicName = try c.decodeIfPresent(String.self, forKey: .topicName)
        clubId = try c.decodeIfPresent(Int.self, forKey: .clubId)
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName)
        merchantNick = try c.decodeIfPresent(String.self, forKey: .merchantNick)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        startDate = try c.decodeIfPresent(CooperationSourceTime.self, forKey: .startDate)
        scope = try c.decodeIfPresent(String.self, forKey: .scope)
    }
}
public struct CooperationRegistration: Decodable, Equatable {
    public let id: Int
    public let topicId: Int?
    public let topicName: String?
    public let memberId: Int?
    public let merchantName: String?
    public let merchantMeta: String?
    public let addressName: String?
    public let address: String?
    public let auditStatus: Int?
    public var statusKey: String {
        guard let auditStatus, (0...2).contains(auditStatus) else { return "cooperation.status.unknown" }
        return "cooperation.registration.status.\(auditStatus)"
    }
    enum CodingKeys: String, CodingKey { case id, topicId, topicName, memberId, merchantName, merchantMeta, addressName, address, auditStatus }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.positiveID(.id)
        topicId = try c.decodeIfPresent(Int.self, forKey: .topicId)
        topicName = try c.decodeIfPresent(String.self, forKey: .topicName)
        memberId = try c.decodeIfPresent(Int.self, forKey: .memberId)
        merchantName = try c.decodeIfPresent(String.self, forKey: .merchantName)
        merchantMeta = try c.decodeIfPresent(String.self, forKey: .merchantMeta)
        addressName = try c.decodeIfPresent(String.self, forKey: .addressName)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        auditStatus = try c.decodeIfPresent(Int.self, forKey: .auditStatus)
    }
}
public struct CooperationRegistrations: Decodable, Equatable {
    public let rows: [CooperationRegistration]
    public let hasMore: Bool?
    enum CodingKeys: String, CodingKey { case rows, hasMore }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decodeIfPresent([CooperationRegistration].self, forKey: .rows) ?? []
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore)
    }
}
public struct CooperationPoolItem: Decodable, Equatable {
    public let topicId: Int
    public let name: String?
    public let subtitle: String?
    public let cover: String?
    public let startDate: CooperationSourceTime?
    public let endDate: CooperationSourceTime?
    public let recruitDeadline: CooperationSourceTime?
    public let merchantNick: String?
    public let state: String?
    public let applyId: Int?
    public var stateKey: String {
        guard let state, ["open", "applied", "invited", "taken", "cooped", "converted", "declined", "withdrawn"].contains(state) else { return "cooperation.status.unknown" }
        return "cooperation.pool.state.\(state)"
    }
    enum CodingKeys: String, CodingKey { case topicId, name, subtitle, cover, startDate, endDate, recruitDeadline, merchantNick, state, applyId }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topicId = try c.positiveID(.topicId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        startDate = try c.decodeIfPresent(CooperationSourceTime.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(CooperationSourceTime.self, forKey: .endDate)
        recruitDeadline = try c.decodeIfPresent(CooperationSourceTime.self, forKey: .recruitDeadline)
        merchantNick = try c.decodeIfPresent(String.self, forKey: .merchantNick)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        applyId = try c.decodeIfPresent(Int.self, forKey: .applyId)
    }
}
public struct CooperationPool: Decodable, Equatable {
    public let rows: [CooperationPoolItem]
    public let hasClub: Bool
    enum CodingKeys: String, CodingKey { case rows, hasClub }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decodeIfPresent([CooperationPoolItem].self, forKey: .rows) ?? []
        hasClub = try c.decodeIfPresent(Bool.self, forKey: .hasClub) ?? false
    }
}
public struct CooperationClubCandidate: Decodable, Equatable {
    public let id: Int
    public let clubName: String?
    public let message: String?
    public let status: Int?
    public let inviteStatus: String?
    public let createTime: CooperationSourceTime?
    public var statusKey: String {
        guard let status, (0...3).contains(status) else { return "cooperation.status.unknown" }
        return "cooperation.application.status.\(status)"
    }
    enum CodingKeys: String, CodingKey { case id, clubName, message, status, inviteStatus, createTime }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.positiveID(.id)
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        status = try c.decodeIfPresent(Int.self, forKey: .status)
        inviteStatus = try c.decodeIfPresent(String.self, forKey: .inviteStatus)
        createTime = try c.decodeIfPresent(CooperationSourceTime.self, forKey: .createTime)
    }
}
public struct CooperationMerchantCandidate: Decodable, Equatable {
    public let id: Int
    public let name: String?
    public let status: Int?
    enum CodingKeys: String, CodingKey { case id, name, merchantName, status }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.positiveID(.id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? c.decodeIfPresent(String.self, forKey: .merchantName)
        status = try c.decodeIfPresent(Int.self, forKey: .status)
    }
}
public struct CooperationCandidates: Decodable, Equatable {
    public let clubApplies: [CooperationClubCandidate]
    public let registrations: [CooperationMerchantCandidate]
    enum CodingKeys: String, CodingKey { case clubApplies, registrations }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clubApplies = try c.decodeIfPresent([CooperationClubCandidate].self, forKey: .clubApplies) ?? []
        registrations = try c.decodeIfPresent([CooperationMerchantCandidate].self, forKey: .registrations) ?? []
    }
}
private extension KeyedDecodingContainer {
    func positiveID(_ key: Key) throws -> Int {
        let value = try decode(Int.self, forKey: key)
        guard value > 0 else { throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid cooperation identity") }
        return value
    }
}

public enum CooperationReadFailure: Error, Equatable {
    case forbidden(message: String?)
    case rejected(code: Int, message: String?)
    case httpStatus(Int, message: String?)
    case unavailable
    case ambiguousIdentity
}
public enum CooperationIssue: Equatable {
    case login, unconfigured, failure, malformed, unavailable, ambiguousIdentity
    case forbidden(String?), server(String)
    public init(_ error: Error) {
        switch error {
        case APIError.unauthorized: self = .login
        case APIError.notConfigured: self = .unconfigured
        case APIError.malformedResponse: self = .malformed
        case CooperationReadFailure.unavailable: self = .unavailable
        case CooperationReadFailure.ambiguousIdentity: self = .ambiguousIdentity
        case CooperationReadFailure.forbidden(let message): self = .forbidden(message)
        case CooperationReadFailure.rejected(_, let message), CooperationReadFailure.httpStatus(_, let message):
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self = .server(message) }
            else { self = .failure }
        default: self = .failure
        }
    }
    public var key: String {
        switch self {
        case .login: return "cooperation.login"
        case .unconfigured: return "cooperation.unconfigured"
        case .failure, .server: return "cooperation.failure"
        case .malformed: return "cooperation.malformed"
        case .unavailable: return "cooperation.unavailable"
        case .ambiguousIdentity: return "cooperation.ambiguous"
        case .forbidden: return "cooperation.forbidden"
        }
    }
    public var canRetry: Bool {
        switch self { case .failure, .malformed, .server: return true; default: return false }
    }
}
public enum CooperationSection<Value> {
    case content(Value), failure(CooperationIssue)
}
/// Each inbox source settles independently. A failed section is never represented by an empty array.
public struct CooperationInbox {
    public let direction: CooperationDirection
    public let invitations: CooperationSection<CooperationInvites>
    public let applications: CooperationSection<[CooperationApplication]>
    public let registrations: CooperationSection<CooperationRegistrations>?
    public init(direction: CooperationDirection, invitations: CooperationSection<CooperationInvites>, applications: CooperationSection<[CooperationApplication]>, registrations: CooperationSection<CooperationRegistrations>?) {
        self.direction = direction; self.invitations = invitations; self.applications = applications; self.registrations = registrations
    }
    public var isPartial: Bool {
        if case .failure = invitations { return true }
        if case .failure = applications { return true }
        if let registrations, case .failure = registrations { return true }
        return false
    }
}
