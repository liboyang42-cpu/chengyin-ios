import Foundation

/// A server readiness observation, not authorization to charge or a payment result.
/// Missing readiness stays unknown. Only a literal server `true` is ready.
public struct RegistrationPaymentReadinessSnapshot: Decodable, Equatable {
    public let ready: Bool?
    public let message: String?
    public var isReady: Bool { ready == true }
}

/// Registration owner kinds are not the theme's product_type values.
public enum RegistrationCountOwnerKind: Int, Equatable, Sendable {
    case topic = 1
    case activity = 2
}

public struct RegistrationCountScope: Equatable, Sendable {
    public let kind: RegistrationCountOwnerKind
    public let ownerID: Int
    public init(kind: RegistrationCountOwnerKind, ownerID: Int) throws {
        guard ownerID > 0 else { throw APIError.invalidRequest }
        self.kind = kind
        self.ownerID = ownerID
    }
}

/// The original server groups confirmed registrations by participate_date and sums
/// order_num. Preserve its calendar label and count; do not derive capacity or money.
public struct RegistrationDailyCount: Decodable, Equatable {
    public let participateDate: String
    public let totalCount: Int

    private enum CodingKeys: String, CodingKey { case participateDate, totalCount }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        participateDate = try values.decode(String.self, forKey: .participateDate)
        totalCount = try values.decode(Int.self, forKey: .totalCount)
        guard !participateDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              participateDate.count <= 64,
              !participateDate.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              totalCount >= 0 else { throw APIError.malformedResponse }
    }
}
