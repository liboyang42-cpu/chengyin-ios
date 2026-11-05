import Foundation

public enum InvoiceLaunchIssue: Error, Equatable {
    case invalid, malformed, disabled, staleSession, unauthorized, unavailable
    case rejected(String), outcomeUnknown, pendingConflict, storageUnavailable
    case originalReadUnavailable
}

/// Legacy routes plus separately approved original-receipt routes verified at c6eac3.
/// Amount, tax and eligibility stay server-owned. New delete/cancel receipts are not enabled.
public enum InvoiceLaunchRoute: String, CaseIterable {
    case titles, saveTitle = "titles/save", deleteTitle = "titles/delete"
    case eligibleOrders = "orders/eligible", apply, list, detail, cancel
    case originalRequest = "request", saveTitleRequest = "titles/save-request", titleRequest = "titles/request"
    public var needsOriginalReceipts: Bool { [.originalRequest, .saveTitleRequest, .titleRequest].contains(self) }
    public var path: String { "api/invoice/" + rawValue }
    public var isMutation: Bool { [.saveTitle, .saveTitleRequest, .deleteTitle, .apply, .cancel].contains(self) }
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
    private enum CodingKeys: String, CodingKey { case id, titleType, titleName, taxNoMasked, isDefault }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try InvoiceLaunchWire.id(c, .id)
        titleType = try c.decode(String.self, forKey: .titleType)
        titleName = try c.decode(String.self, forKey: .titleName)
        taxNoMasked = try c.decodeIfPresent(String.self, forKey: .taxNoMasked)
        isDefault = try c.decode(Bool.self, forKey: .isDefault)
    }
    func validate() throws {
        guard id > 0, ["PERSONAL", "COMPANY"].contains(titleType), !titleName.isEmpty,
              InvoiceLaunchWire.masked(taxNoMasked) else { throw InvoiceLaunchIssue.malformed }
    }
}
public struct InvoiceLaunchOrder: Decodable, Equatable {
    public let orderId: Int64
    public let issuerId: Int64?
    public let issuerName: String?
    public let orderSource: String?
    public let amount: Decimal
    public let orderTitle: String?
    public let ticketName: String?
    public let paymentTime: InvoiceLaunchTime?
    private enum CodingKeys: String, CodingKey { case orderId, issuerId, issuerName, orderSource, amount, orderTitle, ticketName, paymentTime }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orderId = try InvoiceLaunchWire.id(c, .orderId)
        issuerId = try c.decodeIfPresent(InvoiceLaunchWire.ExactID.self, forKey: .issuerId)?.value
        issuerName = try c.decodeIfPresent(String.self, forKey: .issuerName)
        orderSource = try c.decodeIfPresent(String.self, forKey: .orderSource)
        amount = try c.decode(Decimal.self, forKey: .amount)
        orderTitle = try c.decodeIfPresent(String.self, forKey: .orderTitle)
        ticketName = try c.decodeIfPresent(String.self, forKey: .ticketName)
        paymentTime = try c.decodeIfPresent(InvoiceLaunchTime.self, forKey: .paymentTime)
    }
    func validate() throws {
        guard orderId > 0, orderSource == nil || orderSource == "registration",
              issuerId.map({ $0 > 0 }) != false, !amount.isNaN else { throw InvoiceLaunchIssue.malformed }
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
    public let requestId: String?
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
    /// The frozen projection contains no file locator. ISSUED and invoiceNo are
    /// application facts, never proof that a downloadable invoice exists.
    public var documentStatus: InvoiceFileStatus { .unknown }
    private enum CodingKeys: String, CodingKey { case id, requestId, applicationNo, status, titleType, titleName, taxNoMasked, totalAmount, orderCount, provider, invoiceNo, rejectReason, issuedAt, createTime, orders, replayed }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try InvoiceLaunchWire.id(c, .id)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
        applicationNo = try c.decode(String.self, forKey: .applicationNo)
        status = try c.decode(InvoiceLaunchStatus.self, forKey: .status)
        titleType = try c.decode(String.self, forKey: .titleType)
        titleName = try c.decode(String.self, forKey: .titleName)
        taxNoMasked = try c.decodeIfPresent(String.self, forKey: .taxNoMasked)
        totalAmount = try c.decode(Decimal.self, forKey: .totalAmount)
        orderCount = try c.decode(Int.self, forKey: .orderCount)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        invoiceNo = try c.decodeIfPresent(String.self, forKey: .invoiceNo)
        rejectReason = try c.decodeIfPresent(String.self, forKey: .rejectReason)
        issuedAt = try c.decodeIfPresent(InvoiceLaunchTime.self, forKey: .issuedAt)
        createTime = try c.decodeIfPresent(InvoiceLaunchTime.self, forKey: .createTime)
        orders = try c.decode([InvoiceLaunchOrder].self, forKey: .orders)
        replayed = try c.decodeIfPresent(Bool.self, forKey: .replayed)
    }
    func validate(summary: Bool = false) throws {
        guard id > 0, requestId.map(InvoiceLaunchWire.requestID) != false, !applicationNo.isEmpty, ["PERSONAL", "COMPANY"].contains(titleType),
              !titleName.isEmpty, InvoiceLaunchWire.masked(taxNoMasked), !totalAmount.isNaN,
              orderCount > 0, (summary && orders.isEmpty || orders.count == orderCount),
              Set(orders.map(\.orderId)).count == orders.count else { throw InvoiceLaunchIssue.malformed }
        try orders.forEach { try $0.validate() }
    }
    func matches(_ command: InvoiceLaunchApply) -> Bool {
        Set(orders.map(\.orderId)) == Set(command.orderIds) && orders.count == command.orderIds.count
    }
}

/// Atomic return value for the normal invoice entry. A pending operation is
/// supplied alongside the lists so the host cannot mistake browsing for recovery.
public struct InvoiceLaunchOverview: Equatable {
    public let titles: [InvoiceLaunchTitle]
    public let eligibleOrders: [InvoiceLaunchOrder]
    public let applications: [InvoiceLaunchApplication]
    public let pending: InvoiceLaunchPending?
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

public struct InvoiceLaunchTitleReceipt: Decodable, Equatable {
    public let requestId: String
    public let titleId: Int64
    public let status: String
    private enum CodingKeys: String, CodingKey { case requestId, titleId, status }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try c.decode(String.self, forKey: .requestId)
        titleId = try InvoiceLaunchWire.id(c, .titleId)
        status = try c.decode(String.self, forKey: .status)
    }
    func validate(request: String, target: Int64? = nil) throws {
        guard requestId == request, InvoiceLaunchWire.requestID(requestId), status == "SAVED",
              target == nil || target == titleId else { throw InvoiceLaunchIssue.malformed }
    }
}

enum InvoiceLaunchWire {
    struct ExactID: Decodable {
        let value: Int64
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let text = try? c.decode(String.self) {
                guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
                      let parsed = Int64(text), parsed > 0, String(parsed) == text else { throw InvoiceLaunchIssue.malformed }
                value = parsed
            } else {
                let parsed = try c.decode(Int64.self)
                guard parsed > 0 else { throw InvoiceLaunchIssue.malformed }
                value = parsed
            }
        }
    }
    static func id<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Int64 {
        try c.decode(ExactID.self, forKey: key).value
    }

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
