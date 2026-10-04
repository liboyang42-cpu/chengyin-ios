import Foundation

public struct CouponManagementRequest: Equatable, Codable {
    public enum Body: Equatable, Codable { case multipart([String: String]), json(Data) }
    public let path: String
    public let body: Body
    public let mutates: Bool
    public var method: String { "POST" }
    init(path: String, body: Body, mutates: Bool) { self.path = path; self.body = body; self.mutates = mutates }
}
public enum CouponManagementContract {
    public static func published(keyword: String? = nil) -> CouponManagementRequest {
        var fields = ["scope": "MERCHANT"]
        if let keyword, !keyword.isEmpty { fields["keyword"] = keyword }
        return .init(path: "/api/coupon/mypublishlist", body: .multipart(fields), mutates: false)
    }
    public static func publish(_ draft: CouponManagementDraft) throws -> CouponManagementRequest {
        guard draft.blocker == nil, let start = draft.startTime, let end = draft.endTime,
              let type = draft.couponType, let count = Int(draft.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw CouponManagementError.invalid }
        var body: [String: Any] = ["scope": "MERCHANT", "name": draft.name.trimmingCharacters(in: .whitespacesAndNewlines), "startTime": CouponValidityTime.wire(start), "endTime": CouponValidityTime.wire(end), "couponType": type, "publishCount": count]
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty { body["description"] = description }
        return .init(path: "/api/coupon/publish", body: .json(try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])), mutates: true)
    }
    public static func stop(_ id: CouponDefinitionID) -> CouponManagementRequest {
        .init(path: "/api/coupon/stop", body: .multipart(["couponId": String(id.value), "scope": "MERCHANT"]), mutates: true)
    }
    private struct ListEnvelope: Decodable { let code: Int; let msg: String?; let data: [CouponDefinition]? }
    public static func decodePublished(_ data: Data, status: Int) throws -> [CouponDefinition] {
        try requireSuccess(data, status: status)
        guard let envelope = try? JSONDecoder().decode(ListEnvelope.self, from: data), let rows = envelope.data,
              Set(rows.map(\.id)).count == rows.count else { throw CouponManagementError.malformed }
        return rows
    }
    public static func requireSuccess(_ data: Data, status: Int) throws {
        struct Envelope: Decodable { let code: Int; let msg: String? }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw CouponManagementError.malformed }
        let code = envelope.code
        guard (200..<300).contains(status), code == 200 else {
            // Conflicting HTTP failure and business-success envelope cannot prove rejection.
            guard code != 200 else { throw CouponManagementError.malformed }
            if let message = envelope.msg, !message.isEmpty { throw CouponManagementError.server(message) }
            if status == 401 || code == 401 { throw CouponManagementError.signedOut }
            throw CouponManagementError.malformed
        }
    }
    public static func message(_ data: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["msg"] as? String
    }
}
/// Endpoint descriptors are injected; no base URL, bearer token, provider or live grants here.
@MainActor public protocol CouponManagementTransport: AnyObject {
    var isSynthetic: Bool { get }
    func send(_ request: CouponManagementRequest, session: CouponManagementSession) async throws -> (Data, Int)
}
public enum CouponManagementOutcome: Equatable { case simulated(String?), acknowledged(String?), receipt(CouponDefinitionID, String?), notSent, rejected(String), unknown, unknownWithMessage(String) }
@MainActor public final class CouponManagementAdapter {
    private let transport: (any CouponManagementTransport)?
    private let syntheticWritesEnabled: Bool
    private let dormantWritesEnabled: Bool
    public init(transport: (any CouponManagementTransport)? = nil, syntheticWritesEnabled: Bool = false, dormantWritesEnabled: Bool = false) {
        self.transport = transport; self.syntheticWritesEnabled = syntheticWritesEnabled; self.dormantWritesEnabled = dormantWritesEnabled
    }
    public var canRead: Bool { transport != nil }
    public var canRecoverCommands: Bool { (transport as? CouponManagementRuntimeTransport)?.canRecoverCommands == true }
    func prepareCommand(record: CouponManagementPending, session: CouponManagementSession, permission: CouponPublisherPermission) throws -> CouponCommandIdentity? {
        try (transport as? CouponManagementRuntimeTransport)?.prepareCommand(record: record, session: session, permission: permission)
    }
    func recoverCommand(_ record: CouponManagementPending, session: CouponManagementSession, permission: CouponPublisherPermission) async throws -> CouponManagementOutcome {
        guard let runtime = transport as? CouponManagementRuntimeTransport else { throw CouponManagementError.unavailable }
        return try await runtime.readCommand(record, session: session, permission: permission)
    }
    public var canSimulate: Bool {
        #if DEBUG
        return syntheticWritesEnabled && transport?.isSynthetic == true
        #else
        return false
        #endif
    }
    public var canSubmit: Bool { canSimulate || (dormantWritesEnabled && transport?.isSynthetic == false) }
    public func permits(_ action: CouponManagementWriteApproval.Action) -> Bool {
        guard canSubmit else { return false }
        return (transport as? any CouponManagementReviewedTransport)?.permitsAction(action) ?? true
    }
    public func published(session: CouponManagementSession, keyword: String? = nil) async throws -> [CouponDefinition] {
        guard let transport else { throw CouponManagementError.unavailable }
        try Task.checkCancellation()
        let (data, status) = try await transport.send(CouponManagementContract.published(keyword: keyword), session: session)
        try Task.checkCancellation()
        return try CouponManagementContract.decodePublished(data, status: status)
    }
    func submit(_ request: CouponManagementRequest, session: CouponManagementSession, authorization: CouponManagementDispatchAuthorization? = nil) async -> CouponManagementOutcome {
        guard canSubmit, request.mutates, let transport else { return .notSent }
        let response: (Data, Int)
        do {
            if let reviewed = transport as? any CouponManagementReviewedTransport {
                guard let authorization else { return .notSent }
                response = try await reviewed.sendReviewed(request, session: session, authorization: authorization)
            } else { response = try await transport.send(request, session: session) }
        }
        catch { return .unknown }
        let (data, status) = response
        if let record = authorization?.record, record.command != nil {
            return CouponCommandReceipt.outcome(data, status: status, record: record)
        }
        do {
            // The pinned controller returns ordinary HTTP 200; 202 is not a publication receipt.
            guard status == 200 || (400..<500).contains(status) else { return .unknown }
            try CouponManagementContract.requireSuccess(data, status: status)
            if !transport.isSynthetic, request.path == "/api/coupon/publish" {
                struct Receipt: Decodable { struct Value: Decodable { let id: CouponDefinitionID }; let data: Value }
                guard let id = (try? JSONDecoder().decode(Receipt.self, from: data))?.data.id else { return .unknown }
                return .receipt(id, CouponManagementContract.message(data))
            }
            return transport.isSynthetic ? .simulated(CouponManagementContract.message(data)) : .acknowledged(CouponManagementContract.message(data))
        } catch CouponManagementError.server(let message) {
            // The server also returns HTTP 200/code 500 for unknown exceptions. Neither a
            // business-looking message nor an arbitrary non-200 code proves not-applied.
            // Only the explicitly synthetic transport can assert a definitive fixture rejection.
            return transport.isSynthetic ? .rejected(message) : .unknownWithMessage(message)
        }
        catch { return .unknown }
    }
}

/// Exact wire bytes for a host-owned read transport / fake write transport.
/// Deliberately no URL construction or authenticated live executor.
extension CouponManagementRequest {
    public func encodedBody(boundary: String) throws -> (contentType: String, data: Data) {
        switch body {
        case .json(let data): return ("application/json", data)
        case .multipart(let fields):
            guard !boundary.isEmpty, boundary.utf8.count <= 70,
                  boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { throw CouponManagementError.invalid }
            let parts = try fields.sorted { $0.key < $1.key }.map { key, value -> String in
                guard ["keyword", "couponId", "scope"].contains(key), !value.contains(boundary) else { throw CouponManagementError.invalid }
                return "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n"
            }.joined()
            return ("multipart/form-data; boundary=\(boundary)", Data((parts + "--\(boundary)--\r\n").utf8))
        }
    }
}
