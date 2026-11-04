import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Uses composition's existing cookie-free, redirect-denying underlying transport.
/// No lease issuance, URLSession, retry, original rewrite, or generic allowlist change.
@MainActor public final class NativeChannelManagementFinalForward: NativeChannelManagementDispatching {
    private let context: RuntimeDependencyContext
    private let scope: NativeChannelManagementScope
    private let viewerRevision: UInt64
    private let approvalRevision: UUID
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let viewer: () -> UInt64
    private let selected: () -> NativeChannelManagementApproval?
    private var retired = false
    public init(context: RuntimeDependencyContext, scope: NativeChannelManagementScope, viewerRevision: UInt64,
                underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?,
                viewer: @escaping () -> UInt64, selected: @escaping () -> NativeChannelManagementApproval?) throws {
        guard let grant = selected(), grant.matches(context, viewerRevision: viewerRevision, scope: scope),
              ContentDraftContextFence.matches(current(), context), viewer() == viewerRevision else {
            throw NativeChannelManagementError.unavailable
        }
        self.context = context; self.scope = scope; self.viewerRevision = viewerRevision
        approvalRevision = grant.revision; self.underlying = underlying
        self.current = current; self.viewer = viewer; self.selected = selected
    }
    private func currentGrant() -> NativeChannelManagementApproval? {
        guard !retired, ContentDraftContextFence.matches(current(), context), viewer() == viewerRevision,
              let grant = selected(), grant.revision == approvalRevision,
              grant.matches(context, viewerRevision: viewerRevision, scope: scope) else {
            retired = true; return nil
        }
        return grant
    }
    public func send(_ request: URLRequest, fence: NativeChannelManagementDispatchFence) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard let access = NativeChannelManagementForwardRoute.access(request, context: context, scope: scope),
              currentGrant()?.operations.contains(access) == true, fence.isCurrent else {
            throw NativeChannelManagementError.changedIdentity
        }
        // No suspension between this live check and the one existing transport call.
        let response = try await underlying.send(request)
        guard !Task.isCancelled, currentGrant()?.operations.contains(access) == true, fence.isCurrent else {
            throw NativeChannelManagementError.changedIdentity
        }
        return response
    }
}

/// Exact existing service wire only. Mutation bodies round-trip through the existing Intent
/// validator byte-for-byte. Unknown/duplicate fields, noncanonical routes and old CAS-less writes fail.
public enum NativeChannelManagementForwardRoute {
    public static func access(_ request: URLRequest, context: RuntimeDependencyContext,
                              scope: NativeChannelManagementScope) -> NativeChannelManagementAccess? {
        guard let url = request.url, let method = request.httpMethod, request.httpBodyStream == nil,
              url.fragment == nil, url.user == nil, url.password == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }).isSubset(of:
                ["accept", "authorization", "content-type", "x-audit-log-reason"]) else { return nil }
        func exact(_ path: String, query: [String: String] = [:]) -> Bool {
            var c = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
            if !query.isEmpty { c?.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) } }
            return c?.url?.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) == true
        }
        let guild = "api/guilds/\(scope.guildKind)/\(scope.guildID)/channels"
        let parts = url.path.split(separator: "/").map(String.init)
        if method == "GET" {
            guard request.httpBody == nil, request.value(forHTTPHeaderField: "Content-Type") == nil,
                  request.value(forHTTPHeaderField: "X-Audit-Log-Reason") == nil else { return nil }
            if exact(guild, query: ["include_hidden": "0", "with_unread": "1"]) { return .directory }
            // Explicit own-hidden recovery query; backend still filters by current viewer authority.
            if exact(guild, query: ["include_hidden": "1", "with_unread": "1"]) { return .directory }
            if exact(guild + "/manage") { return .managementInventory }
            if exact("api/im/roles", query: ["guild_kind": String(scope.guildKind), "guild_id": scope.guildID.rawValue,
                                            "include_disabled": "false"]) { return .permissionsRead }
            if let index = parts.lastIndex(of: "channels"), parts.count >= index + 2,
               let id = try? NativeChannelManagementID(parts[index + 1]) {
                if exact("api/channels/\(id)") { return .detail }
                if exact("api/channels/\(id)/permissions") || exact("api/channels/\(id)/effective/\(context.session.accountID)") { return .permissionsRead }
            }
            if let key = parts.last, key.range(of: "^[A-Za-z0-9_.:-]{8,64}$", options: .regularExpression) != nil {
                if exact("api/channel-platform/requests/" + key) { return .metadataReceipt }
                if exact("api/channel-platform/governance/requests/" + key) { return .governanceReceipt }
            }
            return nil
        }
        guard request.value(forHTTPHeaderField: "Content-Type") == "application/json", url.query == nil,
              let body = request.httpBody, body.count <= 32 * 1024,
              var fields = try? JSONDecoder().decode([String: NativeChannelManagementJSON].self, from: body),
              case .some(.string(let key)) = fields.removeValue(forKey: "request_id"),
              case .some(.string(let reason)) = fields.removeValue(forKey: "reason"),
              request.value(forHTTPHeaderField: "X-Audit-Log-Reason") == reason else { return nil }
        let version = fields.removeValue(forKey: "expected_version")
        let permissionVersion = fields.removeValue(forKey: "expected_perm_version")
        var operation: NativeChannelManagementIntent.Operation?
        var channel: String?
        var type: Int?
        var target: String?
        if method == "POST", exact(guild) { operation = .create }
        else if let index = parts.lastIndex(of: "channels"), parts.count >= index + 2,
                let id = try? NativeChannelManagementID(parts[index + 1]) {
            channel = id.rawValue
            if method == "PATCH", exact("api/channels/\(id)") { operation = .edit }
            if method == "DELETE", exact("api/channels/\(id)") { operation = .delete }
            if method == "POST", exact("api/channels/\(id)/restore") { operation = .restore }
            if method == "POST", exact("api/channels/\(id)/archive"), case .some(.integer(let value)) = fields["archived"] {
                if value == 1 { operation = .archive }; if value == 0 { operation = .unarchive }
            }
            if parts.count == index + 5, parts[index + 2] == "permissions", let t = Int(parts[index + 3]),
               String(t) == parts[index + 3], exact("api/channels/\(id)/permissions/\(t)/\(parts[index + 4])") {
                type = t; target = parts[index + 4]
                if method == "PUT" { operation = .putOverwrite }; if method == "DELETE" { operation = .deleteOverwrite }
            }
        }
        guard let operation else { return nil }
        let permissions = operation == .putOverwrite || operation == .deleteOverwrite
        // Reconstruct only for validation; never persist or forward the reconstructed body.
        var object: [String: Any] = ["schema": permissions ? 2 : 1, "operation": operation.rawValue,
            "scope": ["guildKind": scope.guildKind, "guildID": scope.guildID.rawValue],
            "requestID": key, "reason": reason]
        if let channel { object["channelID"] = channel }
        if let type { object["targetType"] = type }; if let target { object["targetID"] = target }
        if let version {
            guard case .string(let raw) = version else { return nil }; object["expectedVersion"] = raw
        }
        if let permissionVersion {
            guard case .string(let raw) = permissionVersion else { return nil }; object["permissionVersion"] = raw
        }
        guard let encoded = try? JSONEncoder().encode(fields), let values = try? JSONSerialization.jsonObject(with: encoded) else { return nil }
        object["fields"] = values
        guard let encodedIntent = try? JSONSerialization.data(withJSONObject: object),
              let intent = try? JSONDecoder().decode(NativeChannelManagementIntent.self, from: encodedIntent),
              (try? intent.body()) == body, intent.method == method, exact(intent.path) else { return nil }
        return permissions ? .permissionCommand : .metadataCommand
    }
}
