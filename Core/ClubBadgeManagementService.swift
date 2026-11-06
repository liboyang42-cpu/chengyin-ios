import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ClubBadgeMutationOutcome {
    case confirmed(ClubBadgeOriginalReceipt), rejected(String), unknown, notSent
}

@MainActor public final class ClubBadgeManagementService {
    public let context: RuntimeDependencyContext
    public let clubID: Int
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let approval: (RuntimeDependencyContext) -> ClubBadgeManagementApproval?
    private let unauthorized: () -> Void
    private var sessionRetired = false
    public init(context: RuntimeDependencyContext, clubID: Int, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?,
                approval: @escaping (RuntimeDependencyContext) -> ClubBadgeManagementApproval?,
                unauthorized: @escaping () -> Void = {}) {
        self.context = context; self.clubID = clubID; self.transport = transport
        self.current = current; self.approval = approval; self.unauthorized = unauthorized
    }
    public var isCurrent: Bool { !sessionRetired && current() == context }
    // The callback may notify a host, but is not responsible for this instance's lifetime.
    // Call only after the response's context and read-authority checks have succeeded.
    private func retireUnauthorizedSession() {
        guard !sessionRetired else { return }
        sessionRetired = true
        unauthorized()
    }
    public var canRead: Bool { isCurrent && approval(context)?.permits(context, clubID: clubID, writing: false) == true }
    public var canWrite: Bool { isCurrent && approval(context)?.permits(context, clubID: clubID, writing: true) == true }
    public func detail() async throws -> ClubRecord {
        let data = try await read(ClubBadgeManagementRoute.detailPath, fields: ["id": clubID])
        let club = try JSONDecoder().decode(Value<ClubRecord>.self, from: data).data
        guard club.id == clubID else { throw ClubBadgeManagementFailure.invalid }; return club
    }
    public func badges() async throws -> [ClubBadgeRecord] {
        let data = try await read(ClubBadgeManagementRoute.listPath, fields: ["id": clubID])
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = envelope["data"] as? [Any] else { throw ClubBadgeManagementFailure.invalid }
        var values: [ClubBadgeRecord] = [], codes = Set<String>()
        for row in rows {
            // The mini-program omits rows without server badgeCode. Never manufacture one.
            guard let object = row as? [String: Any], let code = object["badgeCode"] as? String,
                  ClubBadgeManagementRoute.validCode(code) else { continue }
            let bytes = try JSONSerialization.data(withJSONObject: object)
            let badge = try JSONDecoder().decode(ClubBadgeRecord.self, from: bytes)
            guard badge.clubId == nil || badge.clubId == clubID, codes.insert(code).inserted else { throw ClubBadgeManagementFailure.invalid }
            values.append(badge)
        }
        return values
    }
    public func members() async throws -> [ClubMember] {
        let data = try await read(ClubBadgeManagementRoute.membersPath, fields: ["clubId": clubID])
        let rows = try JSONDecoder().decode(Value<[ClubMember]>.self, from: data).data
        guard Set(rows.map(\.memberId)).count == rows.count else { throw ClubBadgeManagementFailure.invalid }; return rows
    }
    public func receipt(_ entry: ClubBadgeManagementEntry) async throws -> ClubBadgeOriginalReceipt {
        try entry.validate(context, clubID: clubID)
        let data = try await read(ClubBadgeManagementRoute.receiptPath, fields: entry.receiptFields)
        let value = try JSONDecoder().decode(Value<ClubBadgeOriginalReceipt>.self, from: data).data
        try value.validate(entry); return value
    }
    /// Called only after user confirmation + fresh owner/list/member checks. Before dispatch,
    /// the caller must durably reserve UNKNOWN. No retry loop exists at any layer in this client.
    func mutate(_ entry: ClubBadgeManagementEntry, fields: [String: Any], isCurrentView: () -> Bool,
                reserve: () throws -> Void) async throws -> ClubBadgeMutationOutcome {
        try entry.validate(context, clubID: clubID)
        guard entry.sourceSHA256 == (try ClubBadgeManagementRoute.sourceHash(operation: entry.operation, fields: fields)),
              let issued = approval(context), issued.permits(context, clubID: clubID, writing: true),
              isCurrent, isCurrentView(), !Task.isCancelled else { return .notSent }
        let path = entry.operation == "CREATE" ? ClubBadgeManagementRoute.createPath : ClubBadgeManagementRoute.grantPath
        var request = try makeRequest(path, fields: fields)
        request.setValue(entry.requestID, forHTTPHeaderField: ClubBadgeManagementRoute.requestHeader)
        request.setValue(entry.sourceSHA256, forHTTPHeaderField: ClubBadgeManagementRoute.sourceHeader)
        guard ClubBadgeManagementRoute(request: request, baseURL: context.baseURL) != nil else { return .notSent }
        try reserve() // Synchronous main-actor write + readback; failure means no send.
        guard isCurrent, isCurrentView(), !Task.isCancelled, approval(context) == issued else { return .notSent }
        do {
            let (data, status) = try await transport.send(request)
            guard isCurrent, isCurrentView(), !Task.isCancelled, approval(context)?.sameReadAuthority(as: issued) == true else { return .unknown }
            if status == 401 { retireUnauthorizedSession(); return .unknown }
            guard (200..<300).contains(status) else { return .unknown }
            let envelope = try statusEnvelope(data)
            if envelope.code == 401 { retireUnauthorizedSession(); return .unknown }
            // Only a validated original receipt can resolve a dispatched request. An
            // application error inside HTTP 200 is not proof of rollback/non-execution.
            // Keep the durable original identity locked for status recovery, including 5xx.
            guard envelope.code == 200 else { return .unknown }
            let value = try JSONDecoder().decode(Value<ClubBadgeOriginalReceipt>.self, from: data).data
            try value.validate(entry)
            guard value.isTerminal else { return .unknown }; return .confirmed(value)
        } catch { return .unknown }
    }
    private func makeRequest(_ path: String, fields: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: context.baseURL.appendingPathComponent(path)); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue(String(request.httpBody?.count ?? 0), forHTTPHeaderField: "Content-Length")
        return request
    }
    private func read(_ path: String, fields: [String: Any]) async throws -> Data {
        guard let issued = approval(context), issued.permits(context, clubID: clubID, writing: false), isCurrent else { throw ClubBadgeManagementFailure.unavailable }
        let request = try makeRequest(path, fields: fields)
        guard ClubBadgeManagementRoute(request: request, baseURL: context.baseURL) != nil, !Task.isCancelled,
              isCurrent, approval(context)?.sameReadAuthority(as: issued) == true else { throw ClubBadgeManagementFailure.stale }
        let (data, status) = try await transport.send(request)
        guard isCurrent, !Task.isCancelled, approval(context)?.sameReadAuthority(as: issued) == true else { throw ClubBadgeManagementFailure.stale }
        if status == 401 { retireUnauthorizedSession(); throw ClubBadgeManagementFailure.forbidden }
        if status == 403 { throw ClubBadgeManagementFailure.forbidden }
        guard (200..<300).contains(status) else { throw ClubBadgeManagementFailure.unknown }
        let envelope = try statusEnvelope(data)
        if envelope.code == 401 { retireUnauthorizedSession(); throw ClubBadgeManagementFailure.forbidden }
        guard envelope.code == 200 else { throw ClubBadgeManagementFailure.server(envelope.msg ?? "服务器未返回可确认的数据。") }
        return data
    }
    private func statusEnvelope(_ data: Data) throws -> Status {
        guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8), (try? ContentDraftJSON.parse(text)) != nil else { throw ClubBadgeManagementFailure.invalid }
        return try JSONDecoder().decode(Status.self, from: data)
    }
    private struct Status: Decodable { let code: Int; let msg: String? }
    private struct Value<T: Decodable>: Decodable { let data: T }
}
