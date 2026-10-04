import Foundation
import Observation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Explicit deployment verification of the frozen v1 backend, never inferred from a 200 response.
/// A configured lease is not authentication and does not grant a write action. Default: absent.
@MainActor @Observable public final class CouponCommandProtocolApproval {
    public let context: RuntimeDependencyContext
    public let merchantID: Int
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public let expiresAt: Date
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, merchantID: Int, verifiedVersion: Int, expiresAt: Date) throws {
        guard context.market == .china, merchantID > 0, verifiedVersion == 1,
              expiresAt > Date(), expiresAt.timeIntervalSinceNow <= 86_400 else { throw APIError.invalidConfiguration }
        endpoints = try .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID, paths: ["api/merchant/coop-profile", "api/coupon/command-receipt"])
        self.context = context; self.merchantID = merchantID; self.expiresAt = expiresAt
    }
    public func revoke() { isRevoked = true }
    public func expireIfNeeded(now: Date = Date()) { if now >= expiresAt { revoke() } }
    public func matches(_ context: RuntimeDependencyContext, merchantID: Int) -> Bool {
        !isRevoked && Date() < expiresAt && self.merchantID == merchantID && ContentDraftContextFence.matches(self.context, context)
    }
}

/// Only these two fields from the authenticated coop-profile whitelist are decoded or retained.
struct CouponCommandOwnerIdentity: Decodable {
    let id: Int
    let memberId: Int
    static func decode(_ data: Data, status: Int, merchantID: Int) throws -> Int {
        struct Envelope: Decodable { let code: Int; let data: CouponCommandOwnerIdentity? }
        guard status == 200, let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.code == 200, let identity = envelope.data,
              identity.id == merchantID, identity.memberId > 0 else { throw CouponManagementError.forbidden }
        return identity.memberId
    }
}

/// Added only before the FIRST send of a newly confirmed v1 command. Never retrofit old journals.
public struct CouponCommandIdentity: Codable, Equatable {
    public let version: Int
    public let requestID: String
    public let actorMemberID: Int
    public let merchantID: Int
    public let ownerMemberID: Int
    public let operation: String
    public let payloadHash: String
    init(record: CouponManagementPending, session: CouponManagementSession, permission: CouponPublisherPermission) throws {
        guard let merchant = permission.merchantID, merchant > 0, let owner = permission.ownerMemberID, owner > 0,
              permission.mayPublish, record.ownerKey == session.ownerKey else { throw CouponManagementError.unavailable }
        try Self.validateWire(record)
        version = 1; requestID = record.operationID.uuidString.lowercased(); actorMemberID = session.accountID
        merchantID = merchant; ownerMemberID = owner
        operation = try CouponCommandCanonical.operation(record.request)
        payloadHash = try CouponCommandCanonical.hash(record.request, merchantID: merchant, ownerMemberID: owner)
    }
    static func validateWire(_ record: CouponManagementPending) throws {
        guard let wire = record.wire else { throw CouponManagementError.storage }
        let boundary: String
        switch record.request.body {
        case .json: boundary = "Unused"
        case .multipart:
            let prefix = "multipart/form-data; boundary="
            guard wire.contentType.hasPrefix(prefix) else { throw CouponManagementError.storage }
            boundary = String(wire.contentType.dropFirst(prefix.count))
        }
        let expected = try record.request.encodedBody(boundary: boundary)
        guard wire.contentType == expected.contentType, wire.data == expected.data else { throw CouponManagementError.storage }
    }
    func validatePayload(record: CouponManagementPending) throws {
        try Self.validateWire(record)
        guard version == 1, requestID == record.operationID.uuidString.lowercased(), merchantID > 0, ownerMemberID > 0,
              operation == (try CouponCommandCanonical.operation(record.request)),
              payloadHash == (try CouponCommandCanonical.hash(record.request, merchantID: merchantID, ownerMemberID: ownerMemberID)),
              record.resource == (operation == "PUBLISH" ? "publish" : "stop:\(try CouponCommandCanonical.stopID(record.request))") else { throw CouponManagementError.changed }
    }
    func validate(record: CouponManagementPending, session: CouponManagementSession, permission: CouponPublisherPermission) throws {
        try validatePayload(record: record)
        guard actorMemberID == session.accountID, record.ownerKey == session.ownerKey,
              merchantID == permission.merchantID, ownerMemberID == permission.ownerMemberID,
              permission.mayPublish else { throw CouponManagementError.changed }
    }
}

/// Exact CouponCommandService.hash v1: big-endian integers and int32-length ordinary UTF-8.
/// NOT JSON hashing, Java writeUTF/modified UTF-8, local Date precision, or locale-dependent text.
enum CouponCommandCanonical {
    static func operation(_ request: CouponManagementRequest) throws -> String {
        guard request.mutates else { throw CouponManagementError.invalid }
        switch request.path { case "/api/coupon/publish": return "PUBLISH"; case "/api/coupon/stop": return "STOP"; default: throw CouponManagementError.invalid }
    }
    static func stopID(_ request: CouponManagementRequest) throws -> Int {
        guard case .multipart(let fields) = request.body, let raw = fields["couponId"], let id = Int(raw), id > 0,
              fields == ["scope": "MERCHANT", "couponId": String(id)] else { throw CouponManagementError.invalid }
        return id
    }
    private struct Publish: Decodable {
        let scope: String; let name: String; let description: String?
        let couponType: Int32; let publishCount: Int64; let startTime: String; let endTime: String
    }
    static func hash(_ request: CouponManagementRequest, merchantID: Int, ownerMemberID: Int) throws -> String {
        guard merchantID > 0, ownerMemberID > 0 else { throw CouponManagementError.invalid }
        var bytes = Data()
        func integer<T: FixedWidthInteger>(_ value: T) { var value = value.bigEndian; withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) } }
        func string(_ value: String?) throws {
            guard let value else { integer(Int32(-1)); return }
            let data = Data(value.utf8); guard let length = Int32(exactly: data.count) else { throw CouponManagementError.invalid }
            integer(length); bytes.append(data)
        }
        let operation = try operation(request)
        integer(Int32(1)); try string(operation); integer(Int32(1)); integer(Int64(merchantID)); integer(Int64(ownerMemberID))
        if operation == "PUBLISH" {
            guard case .json(let data) = request.body else { throw CouponManagementError.invalid }
            let value = try JSONDecoder().decode(Publish.self, from: data)
            guard value.scope == "MERCHANT", !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (0...3).contains(value.couponType), value.publishCount > 0,
                  let start = CouponValidityTime.parse(value.startTime), let end = CouponValidityTime.parse(value.endTime), end > start else { throw CouponManagementError.invalid }
            try string(value.name); try string(value.description); integer(value.couponType); integer(value.publishCount)
            integer(Int64((start.timeIntervalSince1970 * 1000).rounded())); integer(Int64((end.timeIntervalSince1970 * 1000).rounded()))
        } else { integer(Int64(try stopID(request))) }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// Terminal receipt only. A missing receipt or a generic business error is always uncertain.
enum CouponCommandReceipt {
    private struct Envelope: Decodable {
        struct Value: Decodable { let commandReceipt: Receipt?; let id: Int? }
        let code: Int; let msg: String?; let data: Value?
    }
    private struct Receipt: Decodable {
        let version: Int; let requestId: String; let operation: String; let scope: String
        let merchantId: Int; let ownerMemberId: Int; let actorMemberId: Int; let payloadHash: String
        let outcome: String; let reasonCode: String; let couponId: Int?; let couponStatusAtExecution: Int?; let completedAt: String
    }
    private static func compatibleStopRejection(reason: String, status: Int?) -> Bool {
        switch reason {
        case "COUPON_NOT_FOUND": return status == nil
        case "COUPON_MANUALLY_INVALIDATED": return status == 3
        case "COUPON_ALREADY_STOPPED": return status == 4
        case "COUPON_ENDED": return status == nil || status == 2
        case "STOP_CAS_NOT_APPLIED": return status == nil || status.map { (0...4).contains($0) } == true
        default: return false
        }
    }
    static func outcome(_ data: Data, status: Int, record: CouponManagementPending) -> CouponManagementOutcome {
        guard status == 200, let command = record.command, (try? command.validatePayload(record: record)) != nil,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data), let receipt = envelope.data?.commandReceipt,
              command.version == 1, receipt.version == command.version, receipt.requestId == command.requestID,
              receipt.operation == command.operation, receipt.scope == "MERCHANT", receipt.merchantId == command.merchantID,
              receipt.ownerMemberId == command.ownerMemberID, receipt.actorMemberId == command.actorMemberID,
              receipt.payloadHash == command.payloadHash, receipt.payloadHash.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil else { return .unknown }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard formatter.date(from: receipt.completedAt) != nil else { return .unknown }
        if receipt.outcome == "SUCCEEDED", envelope.code == 200, let raw = receipt.couponId, let id = try? CouponDefinitionID(raw) {
            if command.operation == "PUBLISH", receipt.reasonCode == "PUBLISHED", receipt.couponStatusAtExecution == 1, envelope.data?.id == raw {
                return .receipt(id, envelope.msg)
            }
            if command.operation == "STOP", receipt.reasonCode == "STOPPED", receipt.couponStatusAtExecution == 4,
               (try? CouponCommandCanonical.stopID(record.request)) == raw, envelope.data?.id == nil { return .receipt(id, envelope.msg) }
        }
        if receipt.outcome == "REJECTED", envelope.code == 500, envelope.data?.id == nil {
            if command.operation == "PUBLISH", ["QUOTA_REJECTED", "PUBLISH_RATE_LIMITED", "WRITE_NOT_APPLIED"].contains(receipt.reasonCode),
               receipt.couponId == nil, receipt.couponStatusAtExecution == nil { return .rejected(envelope.msg ?? receipt.reasonCode) }
            if command.operation == "STOP", ["COUPON_NOT_FOUND", "COUPON_MANUALLY_INVALIDATED", "COUPON_ALREADY_STOPPED", "COUPON_ENDED", "STOP_CAS_NOT_APPLIED"].contains(receipt.reasonCode),
               receipt.couponId == (try? CouponCommandCanonical.stopID(record.request)),
               compatibleStopRejection(reason: receipt.reasonCode, status: receipt.couponStatusAtExecution) { return .rejected(envelope.msg ?? receipt.reasonCode) }
        }
        return .unknown
    }
}

/// These requests have no mutation/retry method. The outer composition still checks current leases.
enum CouponCommandReadRoute {
    case owner, receipt
    init?(request: URLRequest, baseURL: URL, merchantID: Int) {
        guard request.httpMethod == "POST", request.url?.query == nil, request.url?.fragment == nil,
              request.httpBodyStream == nil, request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.value(forHTTPHeaderField: "X-Coupon-Command-Id") == nil,
              request.value(forHTTPHeaderField: "X-Coupon-Merchant-Id") == nil else { return nil }
        if request.url?.absoluteString == baseURL.appendingPathComponent("api/merchant/coop-profile").absoluteString {
            guard request.httpBody == nil, request.value(forHTTPHeaderField: "Content-Type") == nil else { return nil }; self = .owner; return
        }
        guard request.url?.absoluteString == baseURL.appendingPathComponent("api/coupon/command-receipt").absoluteString,
              let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("multipart/form-data; boundary="),
              let data = request.httpBody, data.count < 4096, let body = String(data: data, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"merchantId\"\r\n\r\n\(merchantID)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"requestId\"\r\n\r\n"
        guard body.hasPrefix(prefix), body.count >= prefix.count + 36 else { return nil }
        let id = String(body.dropFirst(prefix.count).prefix(36))
        guard UUID(uuidString: id)?.uuidString.lowercased() == id,
              let expected = try? AuthRequestBuilder.makeFormRequest(url: baseURL.appendingPathComponent("api/coupon/command-receipt"), fields: ["merchantId": String(merchantID), "requestId": id, "scope": "MERCHANT"], token: nil, boundary: boundary),
              expected.httpBody == data, expected.value(forHTTPHeaderField: "Content-Type") == type else { return nil }
        self = .receipt
    }
}
