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
        let fields = keyword.flatMap { $0.isEmpty ? nil : ["keyword": $0] } ?? [:]
        return .init(path: "/api/coupon/mypublishlist", body: .multipart(fields), mutates: false)
    }
    public static func publish(_ draft: CouponManagementDraft) throws -> CouponManagementRequest {
        guard draft.blocker == nil, let start = draft.startTime, let end = draft.endTime,
              let type = draft.couponType, let count = Int(draft.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw CouponManagementError.invalid }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        var body: [String: Any] = ["name": draft.name.trimmingCharacters(in: .whitespacesAndNewlines), "startTime": formatter.string(from: start), "endTime": formatter.string(from: end), "couponType": type, "publishCount": count]
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty { body["description"] = description }
        return .init(path: "/api/coupon/publish", body: .json(try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])), mutates: true)
    }
    public static func stop(_ id: CouponDefinitionID) -> CouponManagementRequest {
        .init(path: "/api/coupon/stop", body: .multipart(["couponId": String(id.value)]), mutates: true)
    }
    private struct ListEnvelope: Decodable { let code: Int; let msg: String?; let data: [CouponDefinition]? }
    public static func decodePublished(_ data: Data, status: Int) throws -> [CouponDefinition] {
        try requireSuccess(data, status: status)
        guard let envelope = try? JSONDecoder().decode(ListEnvelope.self, from: data), let rows = envelope.data,
              Set(rows.map(\.id)).count == rows.count else { throw CouponManagementError.malformed }
        return rows
    }
    public static func requireSuccess(_ data: Data, status: Int) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? Int else { throw CouponManagementError.malformed }
        guard (200..<300).contains(status), code == 200 else {
            // Conflicting HTTP failure and business-success envelope cannot prove rejection.
            guard code != 200 else { throw CouponManagementError.malformed }
            if let message = object["msg"] as? String, !message.isEmpty { throw CouponManagementError.server(message) }
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
public enum CouponManagementOutcome: Equatable { case simulated(String?), acknowledged(String?), notSent, rejected(String), unknown }
@MainActor public final class CouponManagementAdapter {
    private let transport: (any CouponManagementTransport)?
    private let syntheticWritesEnabled: Bool
    private let dormantWritesEnabled: Bool
    public init(transport: (any CouponManagementTransport)? = nil, syntheticWritesEnabled: Bool = false, dormantWritesEnabled: Bool = false) {
        self.transport = transport; self.syntheticWritesEnabled = syntheticWritesEnabled; self.dormantWritesEnabled = dormantWritesEnabled
    }
    public var canRead: Bool { transport != nil }
    public var canSimulate: Bool {
        #if DEBUG
        return syntheticWritesEnabled && transport?.isSynthetic == true
        #else
        return false
        #endif
    }
    public var canSubmit: Bool { canSimulate || (dormantWritesEnabled && transport?.isSynthetic == false) }
    public func published(session: CouponManagementSession, keyword: String? = nil) async throws -> [CouponDefinition] {
        guard let transport else { throw CouponManagementError.unavailable }
        try Task.checkCancellation()
        let (data, status) = try await transport.send(CouponManagementContract.published(keyword: keyword), session: session)
        try Task.checkCancellation()
        return try CouponManagementContract.decodePublished(data, status: status)
    }
    func submit(_ request: CouponManagementRequest, session: CouponManagementSession) async -> CouponManagementOutcome {
        guard canSubmit, request.mutates, let transport else { return .notSent }
        let response: (Data, Int)
        do { response = try await transport.send(request, session: session) }
        catch { return .unknown }
        let (data, status) = response
        do {
            guard (200..<300).contains(status) || (400..<500).contains(status) else { return .unknown }
            try CouponManagementContract.requireSuccess(data, status: status)
            return transport.isSynthetic ? .simulated(CouponManagementContract.message(data)) : .acknowledged(CouponManagementContract.message(data))
        } catch CouponManagementError.server(let message) { return .rejected(message) }
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
                guard ["keyword", "couponId"].contains(key), !value.contains(boundary) else { throw CouponManagementError.invalid }
                return "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n"
            }.joined()
            return ("multipart/form-data; boundary=\(boundary)", Data((parts + "--\(boundary)--\r\n").utf8))
        }
    }
}
