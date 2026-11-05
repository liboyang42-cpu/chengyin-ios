import Foundation
import CryptoKit

public enum FreeExploreLaunchFailure: Error, Equatable {
    case invalid, malformed, staleSession, disabled, busy, pendingConflict
    case storageUnavailable, outcomeUnknown, cancellationQuoteUnavailable
    case response(status: Int, code: Int, businessCode: String?)
}

/// Java Longs must never pass through Double (including persisted recovery IDs).
public struct FreeExploreLaunchID: Codable, Hashable {
    public let value: Int64
    public var text: String { String(value) }
    public init(_ value: Int64) throws {
        guard value > 0 else { throw FreeExploreLaunchFailure.invalid }
        self.value = value
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let text = try? c.decode(String.self) {
            guard let value = Int64(text), String(value) == text, value > 0 else { throw FreeExploreLaunchFailure.malformed }
            self.value = value
        } else {
            let value = try c.decode(Int64.self)
            guard value > 0 else { throw FreeExploreLaunchFailure.malformed }
            self.value = value
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(value)
    }
}

/// Server decimals are display values. There is no refund/price arithmetic here.
public struct FreeExploreLaunchDecimal: Decodable, Equatable {
    public let text: String
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let string = try? c.decode(String.self) { text = string }
        else { text = NSDecimalNumber(decimal: try c.decode(Decimal.self)).stringValue }
        guard !text.isEmpty, text.utf8.count <= 100,
              text.range(of: "^(0|[1-9][0-9]*)(\\.[0-9]+)?$", options: .regularExpression) != nil else {
            throw FreeExploreLaunchFailure.malformed
        }
    }
}

public struct FreeExploreLaunchCatalog: Decodable, Equatable {
    public struct Item: Decodable, Equatable {
        public struct Store: Decodable, Equatable {
            public let offerId: FreeExploreLaunchID
            public let merchantName: String?
            public let validEnd: String?
        }
        public let chapterId: FreeExploreLaunchID
        public let name: String?
        public let termsMode: String?
        public let unitsPerHolder: Int
        public let stores: [Store]
    }
    public let topicId: FreeExploreLaunchID
    public let topicName: String?
    public let productType: Int
    public let saleEnabled: Bool
    public let reservationEnabled: Bool
    public let items: [Item]
}

public struct FreeExploreLaunchReservation: Decodable, Equatable {
    public let id: FreeExploreLaunchID
    public let registrationId: FreeExploreLaunchID
    public let holderMemberId: FreeExploreLaunchID
    public let unitId: FreeExploreLaunchID
    public let chapterId: FreeExploreLaunchID
    public let offerId: FreeExploreLaunchID
    public let merchantId: FreeExploreLaunchID
    public let startAt: String
    /// Unknown values remain readable; they never become permission to write.
    public let status: String
    public let idempotencyKey: String
    public let requestFingerprint: String
    public func matches(_ command: FreeExploreLaunchReservationCommand, owner: FreeExploreLaunchID) -> Bool {
        holderMemberId == owner && registrationId == command.registrationId && unitId == command.unitId
            && offerId == command.offerId && idempotencyKey == command.idempotencyKey
            && requestFingerprint == command.fingerprint && !status.isEmpty
    }
}

public struct FreeExploreLaunchOrder: Decodable, Equatable {
    public struct Bundle: Decodable, Equatable {
        public struct Owner: Decodable, Equatable {
            public let registrationId: FreeExploreLaunchID
            public let holderMemberId: FreeExploreLaunchID
            public let topicId: FreeExploreLaunchID
        }
        public struct Unit: Decodable, Equatable {
            public let id: FreeExploreLaunchID
            public let registrationId: FreeExploreLaunchID
            public let holderMemberId: FreeExploreLaunchID
            public let chapterId: FreeExploreLaunchID
            public let status: String
        }
        public let order: Owner
        public let units: [Unit]
        public let reservations: [FreeExploreLaunchReservation]
    }
    public let registrationId: FreeExploreLaunchID
    public let registrationNo: String?
    public let parentOrderNo: String?
    public let paymentStatus: Int?
    public let registrationStatus: Int?
    public let bundle: Bundle?
    func validate(owner: FreeExploreLaunchID, registration: FreeExploreLaunchID) throws {
        guard registrationId == registration else { throw FreeExploreLaunchFailure.malformed }
        // A legacy/no-ledger order is read-only. The existing endpoint enforces its owner.
        guard let bundle else { return }
        guard bundle.order.registrationId == registration, bundle.order.holderMemberId == owner,
              Set(bundle.units.map(\.id)).count == bundle.units.count,
              Set(bundle.reservations.map(\.id)).count == bundle.reservations.count,
              bundle.units.allSatisfy({ $0.registrationId == registration && $0.holderMemberId == owner && !$0.status.isEmpty }),
              bundle.reservations.allSatisfy({ row in
                  row.registrationId == registration && row.holderMemberId == owner && !row.status.isEmpty
                      && bundle.units.contains(where: { $0.id == row.unitId && $0.chapterId == row.chapterId })
              }) else { throw FreeExploreLaunchFailure.malformed }
    }
}

public struct FreeExploreLaunchRefundQuote: Decodable, Equatable {
    public let route: String
    public let amount: FreeExploreLaunchDecimal
    public let totalValue: FreeExploreLaunchDecimal
    public let remainingValue: FreeExploreLaunchDecimal
    public let remainingRatio: FreeExploreLaunchDecimal
    public let afterSalesForMerchantBreach: Bool
    public let reason: String
    public let policyVersion: String
}

public struct FreeExploreLaunchReservationCommand: Codable, Equatable {
    public let registrationId: FreeExploreLaunchID
    public let unitId: FreeExploreLaunchID
    public let offerId: FreeExploreLaunchID
    /// Controller contract: epoch milliseconds, not an ISO date or seconds.
    public let startAt: Int64
    public let idempotencyKey: String
    public init(registrationId: FreeExploreLaunchID, unitId: FreeExploreLaunchID,
                offerId: FreeExploreLaunchID, startAt: Int64, idempotencyKey: String = "fx-" + UUID().uuidString) throws {
        self.registrationId = registrationId; self.unitId = unitId; self.offerId = offerId
        self.startAt = startAt; self.idempotencyKey = idempotencyKey
        try validate()
    }
    func validate() throws {
        guard startAt > 0, (1...64).contains(idempotencyKey.utf8.count),
              idempotencyKey.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw FreeExploreLaunchFailure.invalid
        }
    }
    var fingerprint: String {
        let input = "\(registrationId.text)|\(unitId.text)|\(offerId.text)|\(startAt)"
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func wireData() throws -> Data {
        try validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
