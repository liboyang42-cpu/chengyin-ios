import Foundation

/// Read-only projection of the club roster. These counts never authorize a refund.
public struct ClubEnrollmentTeam: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let image: String?
    public let date: String?
    public let signupCount: Int?
    public init(value: ClubGovernanceValue, clubID: Int) throws {
        try ClubEnrollmentDecode.object(value)
        id = try ClubEnrollmentDecode.id(value["id"])
        if value["clubId"] != .null { guard try ClubEnrollmentDecode.id(value["clubId"]) == clubID else { throw ClubGovernanceFailure.targetChanged } }
        name = try ClubEnrollmentDecode.text(value["name"])
        image = try ClubEnrollmentDecode.text(value["imgUrl"])
        date = try ClubEnrollmentDecode.text(value["startDate"]).map { String($0.prefix(10)) }
        signupCount = try ClubEnrollmentDecode.count(value["signupCount"])
    }
    public static func list(_ value: ClubGovernanceValue, clubID: Int) throws -> [Self] {
        guard clubID > 0 else { throw ClubGovernanceFailure.invalidRequest }
        let teams = try ClubEnrollmentDecode.rows(value).map { try Self(value: $0, clubID: clubID) }
        try ClubEnrollmentDecode.unique(teams.map(\.id)); return teams
    }
}

public enum ClubEnrollmentCheckin: String, Equatable { case unknown, pending, done }
public struct ClubEnrollmentRegistrant: Equatable, Identifiable {
    public let id: Int
    public let memberID: Int?
    public let avatar: String?
    public let nickname: String?
    public let paymentStatus: Int?
    public let verificationStatus: Int?
    public var checkin: ClubEnrollmentCheckin {
        switch verificationStatus { case 0: return .pending; case 1: return .done; default: return .unknown }
    }
    fileprivate init(_ value: ClubGovernanceValue) throws {
        try ClubEnrollmentDecode.object(value)
        id = try ClubEnrollmentDecode.id(value["id"])
        memberID = value["memberId"] == .null ? nil : try ClubEnrollmentDecode.id(value["memberId"])
        avatar = try ClubEnrollmentDecode.text(value["avatar"])
        nickname = try ClubEnrollmentDecode.text(value["nickname"])
        paymentStatus = try ClubEnrollmentDecode.count(value["paymentStatus"])
        verificationStatus = try ClubEnrollmentDecode.count(value["verificationStatus"])
    }
}
public struct ClubEnrollmentTicket: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let mode: Int?
    public let capacity: Int?
    public let deadline: String?
    public let teamStatus: Int?
    public let registrants: [ClubEnrollmentRegistrant]
    fileprivate init(_ value: ClubGovernanceValue) throws {
        try ClubEnrollmentDecode.object(value)
        id = try ClubEnrollmentDecode.id(value["id"])
        name = try ClubEnrollmentDecode.text(value["name"])
        mode = try ClubEnrollmentDecode.count(value["mode"])
        capacity = try ClubEnrollmentDecode.count(value["totalInventory"])
        deadline = try ClubEnrollmentDecode.text(value["signupDeadline"]).map { String($0.prefix(16)).replacingOccurrences(of: "T", with: " ") }
        teamStatus = try ClubEnrollmentDecode.count(value["teamStatus"])
        // Missing/null list is a source-supported empty list; malformed non-list is not.
        registrants = value["cmsRegistrationList"] == .null ? [] : try ClubEnrollmentDecode.rows(value["cmsRegistrationList"]).map(ClubEnrollmentRegistrant.init)
        try ClubEnrollmentDecode.unique(registrants.map(\.id))
    }
}
public struct ClubEnrollmentRoster: Equatable {
    public let clubID: Int
    public let topicID: Int
    public let canRefund: Bool
    public let tickets: [ClubEnrollmentTicket]
    public var paidCount: Int { tickets.reduce(0) { $0 + $1.registrants.count } }
    /// Unknown payment/checkin fields cannot safely contribute a definite refundable count.
    public var refundableCount: Int? {
        let rows = tickets.flatMap(\.registrants)
        guard rows.allSatisfy({ $0.paymentStatus != nil && ($0.paymentStatus != 2 || $0.checkin != .unknown) }) else { return nil }
        return rows.filter { $0.paymentStatus == 2 && $0.checkin == .pending }.count
    }
    public var deadline: String? { tickets.compactMap(\.deadline).first }
    public var teamStatus: Int? {
        if tickets.contains(where: { $0.teamStatus == 1 }) { return 1 }
        if tickets.contains(where: { $0.teamStatus == 2 }) { return 2 }
        return !tickets.isEmpty && tickets.allSatisfy({ $0.teamStatus == 0 }) ? 0 : nil
    }
    public init(value: ClubGovernanceValue, scope: ClubGovernanceScope) throws {
        try scope.validate(); try ClubEnrollmentDecode.object(value)
        clubID = try ClubEnrollmentDecode.id(value["clubId"])
        topicID = try ClubEnrollmentDecode.id(value["topicId"])
        guard clubID == scope.clubID, topicID == scope.topicID else { throw ClubGovernanceFailure.targetChanged }
        guard let canRefund = value["canRefund"].bool else { throw ClubGovernanceFailure.malformed }
        self.canRefund = canRefund
        tickets = try ClubEnrollmentDecode.rows(value["omsTicketList"]).map(ClubEnrollmentTicket.init)
        try ClubEnrollmentDecode.unique(tickets.map(\.id))
        try ClubEnrollmentDecode.unique(tickets.flatMap(\.registrants).map(\.id))
    }
}
private enum ClubEnrollmentDecode {
    static func object(_ value: ClubGovernanceValue) throws { guard value.object != nil else { throw ClubGovernanceFailure.malformed } }
    static func id(_ value: ClubGovernanceValue) throws -> Int { guard let number = value.int, number > 0 else { throw ClubGovernanceFailure.malformed }; return number }
    static func count(_ value: ClubGovernanceValue) throws -> Int? {
        if value == .null { return nil }
        guard let number = value.int, number >= 0 else { throw ClubGovernanceFailure.malformed }; return number
    }
    static func text(_ value: ClubGovernanceValue) throws -> String? {
        if value == .null { return nil }; guard let text = value.string else { throw ClubGovernanceFailure.malformed }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
    static func rows(_ value: ClubGovernanceValue) throws -> [ClubGovernanceValue] {
        guard let rows = value.array, rows.allSatisfy({ $0.object != nil }) else { throw ClubGovernanceFailure.malformed }; return rows
    }
    static func unique(_ ids: [Int]) throws { guard Set(ids).count == ids.count else { throw ClubGovernanceFailure.malformed } }
}
