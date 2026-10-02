import Foundation

/// Account child routes from the retained client. All operations in this module are reads.
/// IDs are validated instead of synthesizing an address/order that cannot be opened safely.
public struct ProfileParticipant: Decodable, Equatable, Identifiable {
    public let id: Int
    public let fullName: String
    public let mobilePhone: String
    /// The entire province/city/district string, not a separate province component.
    public let province: String?
    public let detailAddress: String?
    public let isDefault: Bool
    public var oneLineAddress: String {
        [province, detailAddress].compactMap { value in
            value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }.joined(separator: " ")
    }
    private enum CodingKeys: String, CodingKey { case id, fullName, mobilePhone, province, detailAddress, isDefault }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guard id > 0 else { throw APIError.malformedResponse }
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName) ?? ""
        mobilePhone = try c.decodeIfPresent(String.self, forKey: .mobilePhone) ?? ""
        province = try c.decodeIfPresent(String.self, forKey: .province)
        detailAddress = try c.decodeIfPresent(String.self, forKey: .detailAddress)
        isDefault = (try? c.decode(Bool.self, forKey: .isDefault)) == true
            || (try? c.decode(Int.self, forKey: .isDefault)) == 1
            || (try? c.decode(String.self, forKey: .isDefault)) == "1"
    }
}

/// Registration and verification are separate facts. Neither becomes a payment verdict.
public enum ProfileRegistrationState: Equatable {
    case awaitingPayment, registered, cancelled, expired, unknown
    public init(code: Int?) {
        switch code {
        case 1: self = .awaitingPayment
        case 2: self = .registered
        case 3: self = .cancelled
        case 4: self = .expired
        default: self = .unknown
        }
    }
}

/// Shared read projection of MyRegistration and RegistrationDetail. Detail is always fetched
/// from /info; list snapshots are never treated as a fresh detail response. Unknown values
/// and missing prices remain unknown, including absent refund applications versus payout 0.
public struct ProfileOrder: Decodable, Equatable, Identifiable {
    public let id: Int
    public let ownerType: Int?
    public let ownerID: Int?
    public let registrationNo: String?
    public let registrationStatus: Int?
    public let verificationStatus: Int?
    public let paymentStatus: Int?
    public let title: String?
    public let productType: Int?
    public let startDate: String?
    public let endDate: String?
    public let addressName: String?
    public let meetingPoint: String?
    public let gatherLatitude: Double?
    public let gatherLongitude: Double?
    public let participateDate: String?
    public let payableAmount: Decimal?
    public let realName: String?
    /// The retained detail contract documents this as server-masked; do not unmask locally.
    public let phone: String?
    public let ticketName: String?
    public let orderNum: Int?
    public let paymentTime: String?
    public let paymentTypeLabel: String?
    public let createTime: String?
    public let verificationTime: String?
    public let expiresAt: String?
    public let organizerName: String?
    public let statusText: String?
    public let orderHint: String?
    public let refundable: Bool?
    public let refundPayoutStatus: Int?
    public var registrationState: ProfileRegistrationState { .init(code: registrationStatus) }

    private enum CodingKeys: String, CodingKey {
        case id, ownerType, ownerId, registrationNo, registrationStatus, verificationStatus, paymentStatus
        case cmsActivity, cmsTopic, omsTicket, participateDate, payableAmount, realName, phone, ticketName, orderNum
        case paymentTime, paymentTypeLabel, createTime, verificationTime, expiresAt, organizerName
        case statusText, orderHint, refundInfo, refundApplication
    }
    private struct Owner: Decodable, Equatable {
        let name: String?
        let productType: ProfileWireInteger?
        let startDate: String?
        let endDate: String?
        let addressName: String?
    }
    private struct MeetingTicket: Decodable {
        let meetingPoint: String?
        let gatherLat: Double?
        let gatherLng: Double?
    }
    private struct RefundInfo: Decodable { let refundable: Bool? }
    private struct RefundApplication: Decodable { let payoutStatus: ProfileWireInteger? }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guard id > 0 else { throw APIError.malformedResponse }
        ownerType = try c.decodeIfPresent(Int.self, forKey: .ownerType)
        ownerID = try c.decodeIfPresent(Int.self, forKey: .ownerId)
        registrationNo = try c.decodeIfPresent(String.self, forKey: .registrationNo)
        registrationStatus = try c.decodeIfPresent(Int.self, forKey: .registrationStatus)
        verificationStatus = try c.decodeIfPresent(Int.self, forKey: .verificationStatus)
        paymentStatus = try c.decodeIfPresent(Int.self, forKey: .paymentStatus)
        // Source precedence is the associated activity object, then the topic object.
        let owner = try c.decodeIfPresent(Owner.self, forKey: .cmsActivity)
            ?? c.decodeIfPresent(Owner.self, forKey: .cmsTopic)
        title = owner?.name
        productType = owner?.productType?.value
        startDate = owner?.startDate
        endDate = owner?.endDate
        addressName = owner?.addressName
        let meeting = try c.decodeIfPresent(MeetingTicket.self, forKey: .omsTicket)
        meetingPoint = meeting?.meetingPoint
        gatherLatitude = meeting?.gatherLat; gatherLongitude = meeting?.gatherLng
        participateDate = try c.decodeIfPresent(String.self, forKey: .participateDate)
        if c.contains(.payableAmount), !(try c.decodeNil(forKey: .payableAmount)) {
            // Flutter's order projection accepts numeric amounts, not numeric strings.
            guard (try? c.decode(String.self, forKey: .payableAmount)) == nil else {
                throw APIError.malformedResponse
            }
            let amount = try c.decode(Decimal.self, forKey: .payableAmount)
            guard !amount.isNaN, amount >= .zero else { throw APIError.malformedResponse }
            payableAmount = amount
        } else { payableAmount = nil }
        realName = try c.decodeIfPresent(String.self, forKey: .realName)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        ticketName = try c.decodeIfPresent(String.self, forKey: .ticketName)
        orderNum = try c.decodeIfPresent(Int.self, forKey: .orderNum)
        paymentTime = try c.decodeIfPresent(String.self, forKey: .paymentTime)
        paymentTypeLabel = try c.decodeIfPresent(String.self, forKey: .paymentTypeLabel)
        createTime = try c.decodeIfPresent(String.self, forKey: .createTime)
        verificationTime = try c.decodeIfPresent(String.self, forKey: .verificationTime)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        organizerName = try c.decodeIfPresent(String.self, forKey: .organizerName)
        statusText = try c.decodeIfPresent(String.self, forKey: .statusText)
        orderHint = try c.decodeIfPresent(String.self, forKey: .orderHint)
        refundable = try c.decodeIfPresent(RefundInfo.self, forKey: .refundInfo)?.refundable
        refundPayoutStatus = try c.decodeIfPresent(RefundApplication.self, forKey: .refundApplication)?.payoutStatus?.value
    }
}

public struct ProfileIdentityBadge: Decodable, Equatable {
    public let badgeCode: String
    public let badgeName: String
    public let nameEn: String
    public let statement: String
    public let iconURL: String
    public let category: String
    public let unlockHint: String
    public let unlocked: Bool
    public let unlockTime: String?
    private enum CodingKeys: String, CodingKey {
        case badgeCode, badgeName, nameEn, statement, iconUrl, category, unlockHint, unlocked, unlockTime
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        badgeCode = try c.profileText(.badgeCode)
        badgeName = try c.profileText(.badgeName)
        nameEn = try c.profileText(.nameEn)
        statement = try c.profileText(.statement)
        iconURL = try c.profileText(.iconUrl)
        category = try c.profileText(.category)
        unlockHint = try c.profileText(.unlockHint)
        unlocked = try c.decodeIfPresent(ProfileWireBoolean.self, forKey: .unlocked)?.value ?? false
        unlockTime = try c.decodeIfPresent(String.self, forKey: .unlockTime)
    }
}

public struct ProfileMedal: Decodable, Equatable {
    public let templateID: Int?
    public let medalImage: String
    public let medalName: String
    public let style: String
    public let topicID: Int?
    public let getTime: String?
    public let condition: String
    public let kind: String
    public let badgeCode: String
    public var isAchievement: Bool { kind == "achievement" }
    /// Achievement rows do not supply a condition; do not borrow city-node conditions.
    public var displayCondition: String { isAchievement ? "" : condition }
    private enum CodingKeys: String, CodingKey {
        case templateId, medalImg, medalName, style, topicId, getTime, condition, kind, badgeCode
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        templateID = try c.decodeIfPresent(ProfileWireInteger.self, forKey: .templateId)?.value
        medalImage = try c.profileText(.medalImg)
        medalName = try c.profileText(.medalName)
        style = try c.profileText(.style)
        topicID = try c.decodeIfPresent(ProfileWireInteger.self, forKey: .topicId)?.value
        getTime = try c.decodeIfPresent(String.self, forKey: .getTime)
        condition = try c.profileText(.condition)
        kind = try c.profileText(.kind)
        badgeCode = try c.profileText(.badgeCode)
    }
}

public struct ProfileBadgeWall: Equatable {
    public let identities: [ProfileIdentityBadge]
    /// nil means loading medals failed, not an empty collection.
    public let medals: [ProfileMedal]?
    public let medalFailureMessage: String?
    public var isPartial: Bool { medals == nil }
    public var isEmpty: Bool { identities.isEmpty && medals?.isEmpty == true }
    public init(identities: [ProfileIdentityBadge], medals: [ProfileMedal]?, medalFailureMessage: String? = nil) {
        self.identities = identities
        self.medals = medals
        self.medalFailureMessage = medalFailureMessage
    }
}

/// Only fields whose retained parsers accept wire strings use these helpers.
private struct ProfileWireInteger: Decodable, Equatable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let integer = try? c.decode(Int.self) { value = integer }
        else if let text = try? c.decode(String.self) { value = Int(text) }
        else if let number = try? c.decode(Double.self), number.isFinite { value = Int(exactly: number.rounded(.towardZero)) }
        else { value = nil }
    }
}
private struct ProfileWireBoolean: Decodable {
    let value: Bool
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let flag = try? c.decode(Bool.self) { value = flag }
        else if let number = try? c.decode(Int.self) { value = number == 1 }
        else if let text = try? c.decode(String.self) { value = text == "1" || text == "true" }
        else { value = false }
    }
}
private struct ProfileWireText: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let text = try? c.decode(String.self) { value = text }
        else if let flag = try? c.decode(Bool.self) { value = flag ? "true" : "false" }
        else if let number = try? c.decode(Decimal.self) { value = NSDecimalNumber(decimal: number).stringValue }
        else { throw APIError.malformedResponse }
    }
}
private extension KeyedDecodingContainer {
    func profileText(_ key: Key) throws -> String {
        try decodeIfPresent(ProfileWireText.self, forKey: key)?.value ?? ""
    }
}
