import Foundation

public enum InvoiceLaunchIssue: Error, Equatable {
    case invalid, malformed, disabled, staleSession, unauthorized, unavailable
    case rejected(String), outcomeUnknown, pendingConflict, storageUnavailable
    case originalReadUnavailable
}

/// Only the eight routes present at hengyin 58f4cc4. Request-receipt routes from
/// c6eac3 are deliberately absent. Amount, tax and eligibility stay server-owned.
public enum InvoiceLaunchRoute: String, CaseIterable {
    case titles, saveTitle = "titles/save", deleteTitle = "titles/delete"
    case eligibleOrders = "orders/eligible", apply, list, detail, cancel
    public var path: String { "api/invoice/" + rawValue }
    public var isMutation: Bool { [.saveTitle, .deleteTitle, .apply, .cancel].contains(self) }
}

/// Memory-only session snapshot. Namespace must be the existing reviewed regional
/// storage namespace. A new epoch is required for every logout/login transition.
public struct InvoiceLaunchSession: Equatable {
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int64
    public let role: String
    public let epoch: UInt64
    let token: String
    public init(baseURL: URL, namespace: String, accountID: Int64, role: String,
                epoch: UInt64, token: String) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard accountID > 0, !namespace.isEmpty, !role.isEmpty,
              AuthRequestBuilder.isValidToken(token) else { throw InvoiceLaunchIssue.invalid }
        self.baseURL = baseURL; self.namespace = namespace; self.accountID = accountID
        self.role = role; self.epoch = epoch; self.token = token
    }
    // Stable across process restart/token rotation. Contains no credential or PII.
    var ownerKey: String {
        [baseURL.absoluteString, namespace, String(accountID)]
            .map { "\($0.utf8.count):\($0)" }.joined(separator: ":")
    }
}

public struct InvoiceLaunchTitleDraft: Encodable, Equatable {
    public let id: Int64?
    public let titleType: String
    public let titleName: String
    public let taxNo: String?
    public let isDefault: Bool
    public init(id: Int64? = nil, titleType: String, titleName: String,
                taxNo: String? = nil, isDefault: Bool = false) throws {
        guard id.map({ $0 > 0 }) != false else { throw InvoiceLaunchIssue.invalid }
        self.id = id; self.titleType = titleType; self.titleName = titleName
        self.taxNo = taxNo; self.isDefault = isDefault
        // Validation/normalization of title and tax number belongs to the server.
        // Never hydrate taxNo from the masked title projection.
    }
}
public struct InvoiceLaunchTitle: Decodable, Equatable {
    public let id: Int64
    public let titleType: String
    public let titleName: String
    public let taxNoMasked: String?
    public let isDefault: Bool
    func validate() throws {
        guard id > 0, ["PERSONAL", "COMPANY"].contains(titleType), !titleName.isEmpty,
              InvoiceLaunchWire.masked(taxNoMasked) else { throw InvoiceLaunchIssue.malformed }
    }
}
public struct InvoiceLaunchOrder: Decodable, Equatable {
    public let orderId: Int64
    public let orderSource: String?
    public let amount: Decimal
    public let orderTitle: String?
    public let ticketName: String?
    public let paymentTime: InvoiceLaunchTime?
    func validate() throws {
        guard orderId > 0, orderSource == nil || orderSource == "registration",
              !amount.isNaN else { throw InvoiceLaunchIssue.malformed }
    }
}
public enum InvoiceLaunchStatus: String, Decodable {
    case submitted = "SUBMITTED", issued = "ISSUED", rejected = "REJECTED", cancelled = "CANCELLED"
}
/// Preserve the Jackson Date representation for display; never infer a deadline.
public enum InvoiceLaunchTime: Decodable, Equatable {
    case text(String), epochMilliseconds(Int64)
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let milliseconds = try? value.decode(Int64.self) { self = .epochMilliseconds(milliseconds) }
        else { self = .text(try value.decode(String.self)) }
    }
}
public struct InvoiceLaunchApplication: Decodable, Equatable {
    public let id: Int64
    public let applicationNo: String
    public let status: InvoiceLaunchStatus
    public let titleType: String
    public let titleName: String
    public let taxNoMasked: String?
    public let totalAmount: Decimal
    public let orderCount: Int
    public let provider: String?
    public let invoiceNo: String?
    public let rejectReason: String?
    public let issuedAt: InvoiceLaunchTime?
    public let createTime: InvoiceLaunchTime?
    public let orders: [InvoiceLaunchOrder]
    public let replayed: Bool?
    func validate(summary: Bool = false) throws {
        guard id > 0, !applicationNo.isEmpty, ["PERSONAL", "COMPANY"].contains(titleType),
              !titleName.isEmpty, InvoiceLaunchWire.masked(taxNoMasked), !totalAmount.isNaN,
              orderCount > 0, (summary && orders.isEmpty || orders.count == orderCount),
              Set(orders.map(\.orderId)).count == orders.count else { throw InvoiceLaunchIssue.malformed }
        try orders.forEach { try $0.validate() }
    }
    func matches(_ command: InvoiceLaunchApply) -> Bool {
        Set(orders.map(\.orderId)) == Set(command.orderIds) && orders.count == command.orderIds.count
    }
}

/// The original request identity and exact body survive restart. No calculated total,
/// memberId, tax rate or inferred eligibility can be put on this request.
public struct InvoiceLaunchApply: Codable, Equatable {
    public let requestId: String
    public let titleId: Int64
    public let orderIds: [Int64]
    public init(requestId: String = UUID().uuidString, titleId: Int64, orderIds: [Int64]) throws {
        self.requestId = requestId; self.titleId = titleId; self.orderIds = orderIds
        try validate()
    }
    func validate() throws {
        guard InvoiceLaunchWire.requestID(requestId), titleId > 0, !orderIds.isEmpty,
              orderIds.allSatisfy({ $0 > 0 }), Set(orderIds).count == orderIds.count else { throw InvoiceLaunchIssue.invalid }
    }
}

enum InvoiceLaunchWire {
    static func requestID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
    static func masked(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return true }
        return value.range(of: "^(?:[0-9A-Z]{2}\\*{6}[0-9A-Z]{4}|\\*{6})$", options: .regularExpression) != nil
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
