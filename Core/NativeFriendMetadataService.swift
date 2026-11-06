import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent default-closed grant. Existing friend, IM and conversation grants cannot enable it.
public struct NativeFriendMetadataApproval: Equatable {
    public let issuanceID: UUID
    public let endpoint: OperationEndpointApproval
    public let expiresAt: Date
    public let allowsStarChanges: Bool
    public let allowsGroupChanges: Bool
    public let allowsProgressChanges: Bool
    public static let readPaths: Set<String> = ["api/friend/metadata", "api/friend/metadata/receipt"]
    public static let groupReadPath = "api/friend/group/list"
    public static let settlePath = "api/friend/metadata/settle"
    public static let writePaths: Set<String> = [NativeFriendMetadataAction.remark.path]
    public static let groupWritePaths: Set<String> = [NativeFriendMetadataAction.groupSave.path, NativeFriendMetadataAction.groupDelete.path]
    public static let allowedPaths = readPaths.union(writePaths).union(groupWritePaths).union([groupReadPath])
    public init(endpoint: OperationEndpointApproval, expiresAt: Date, issuanceID: UUID = UUID(), allowsStarChanges: Bool = false, allowsGroupChanges: Bool = false, allowsProgressChanges: Bool = false) throws {
        guard Self.readPaths.isSubset(of: endpoint.paths), endpoint.paths.isSubset(of: Self.allowedPaths),
              expiresAt.timeIntervalSince1970.isFinite else { throw NativeFriendFailure.invalid }
        self.issuanceID = issuanceID; self.endpoint = endpoint; self.expiresAt = expiresAt; self.allowsStarChanges = allowsStarChanges; self.allowsGroupChanges = allowsGroupChanges; self.allowsProgressChanges = allowsProgressChanges
    }
}
@MainActor public final class NativeFriendMetadataService: NativeFriendMetadataServing {
    private let context: RuntimeDependencyContext
    private let approval: NativeFriendMetadataApproval
    private let current: () -> RuntimeDependencyContext?
    private let currentApproval: () -> NativeFriendMetadataApproval?
    private let transport: any HTTPTransport
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var retired = false
    public var viewerID: Int64 { Int64(context.session.accountID) }
    public var isCurrent: Bool {
        guard !retired, current() == context, currentApproval() == approval, Date() < approval.expiresAt else { retired = true; return false }
        return true
    }
    public var canSettle: Bool { false } // No formal settlement/cancellation writer.
    public var canWrite: Bool { isCurrent && approval.endpoint.paths.contains(NativeFriendMetadataAction.remark.path) }
    public var canStarWrite: Bool { canWrite && approval.allowsStarChanges }
    public var canProgressWrite: Bool { canWrite && approval.allowsProgressChanges }
    public var canReadGroups: Bool { isCurrent && approval.endpoint.paths.contains("api/friend/group/list") }
    public var canManageGroups: Bool { canReadGroups && approval.allowsGroupChanges && [NativeFriendMetadataAction.groupSave.path, NativeFriendMetadataAction.groupDelete.path].allSatisfy(approval.endpoint.paths.contains) }
    public var canAssignGroup: Bool { canReadGroups && canWrite && approval.allowsGroupChanges }
    public init(context: RuntimeDependencyContext, approval: NativeFriendMetadataApproval,
                currentApproval: @escaping () -> NativeFriendMetadataApproval?, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) throws {
        guard context.market == .china, approval.endpoint.baseURL == context.baseURL,
              approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              Date() < approval.expiresAt else { throw NativeFriendFailure.unavailable }
        self.context = context; self.approval = approval; self.currentApproval = currentApproval
        self.transport = transport; self.current = current; self.onUnauthorized = onUnauthorized
    }
    public func read(peerID: Int64) async throws -> NativeFriendMetadata {
        let value: NativeFriendMetadata = try await exchange("api/friend/metadata", fields: ["peer_id": String(peerID)], body: nil)
        try validate(value, peerID: peerID); return value
    }
    public func groups() async throws -> NativeFriendMetadataGroups {
        guard canReadGroups else { throw NativeFriendFailure.notSent }
        let value: NativeFriendMetadataGroups = try await exchange("api/friend/group/list", fields: [:], body: nil)
        try validate(value);return value
    }
    public func write(_ command: NativeFriendMetadataCommand) async throws -> NativeFriendMetadataReceipt {
        if command.action == .remark {
            guard canWrite, command.starred == nil || canStarWrite, !command.updatesGroup || canAssignGroup, command.progressScope == nil || canProgressWrite else { throw NativeFriendFailure.notSent }
        } else { guard canManageGroups else { throw NativeFriendFailure.notSent } }
        let value: NativeFriendMetadataReceipt = try await exchange(command.action.path, fields: [:], body: command.body())
        try validate(value, action: command.action, targetID: command.targetID, requestID: command.requestID)
        guard ["APPLIED", "REJECTED"].contains(value.outcome), value.payloadHash == (try command.fingerprint()) else { throw NativeFriendFailure.unknown }; return value
    }
    public func receipt(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID) async throws -> NativeFriendMetadataReceipt {
        let value: NativeFriendMetadataReceipt = try await exchange("api/friend/metadata/receipt", fields: ["action": action.rawValue, "target_id": String(targetID), "request_id": requestID.uuidString], body: nil)
        try validate(value, action: action, targetID: targetID, requestID: requestID); return value
    }
    public func settle(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID, payloadHash: String) async throws -> NativeFriendMetadataReceipt {
        throw NativeFriendFailure.notSent
    }
    private func validate(_ value: NativeFriendMetadata, peerID: Int64) throws {
        guard value.viewerID == viewerID, value.peerID == peerID, peerID > 0, peerID != viewerID,
              value.friendVersion > 0, value.version >= 0, [0, 1].contains(value.starred), value.progressScope.map({ [0,1].contains($0) }) ?? true,
              value.groupID.map({ $0 > 0 }) ?? true, NativeFriendMetadataValidation.validRemark(value.remark),
              ["NOT_CONNECTED", "ORIGINAL_POLICY"].contains(value.notificationEffect) else { throw NativeFriendFailure.invalid }
    }
    private func validate(_ value: NativeFriendMetadataGroups) throws {
        guard NativeFriendMetadataValidation.validGroups(value, viewerID: viewerID) else { throw NativeFriendFailure.invalid }
    }
    private func validate(_ value: NativeFriendMetadataReceipt, action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID) throws {
        guard value.viewerID == viewerID, value.action == action, value.targetID == targetID,
              UUID(uuidString: value.requestID) == requestID, ["APPLIED", "REJECTED", "UNKNOWN"].contains(value.outcome) else { throw NativeFriendFailure.invalid }
        if value.outcome != "UNKNOWN" { guard value.payloadHash?.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw NativeFriendFailure.invalid } }
        if value.outcome == "REJECTED" && (value.current != nil || value.groups != nil) { throw NativeFriendFailure.invalid }
        if let metadata = value.current { guard action == .remark else { throw NativeFriendFailure.invalid }; try validate(metadata, peerID: targetID) }
        if let groups = value.groups { guard action != .remark else { throw NativeFriendFailure.invalid }; try validate(groups) }
        if value.outcome == "APPLIED" && action != .remark && value.groups == nil { throw NativeFriendFailure.invalid }
    }
    private func exchange<T: Decodable>(_ path: String, fields: [String: String], body: Data?) async throws -> T {
        guard isCurrent, approval.endpoint.paths.contains(path), !Task.isCancelled else { throw NativeFriendFailure.notSent }
        var parts = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if body == nil && !fields.isEmpty { parts.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = parts.url else { throw NativeFriendFailure.notSent }
        var request = URLRequest(url: url); request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false; request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body
        guard NativeFriendMetadataTransportPolicy.accepts(request, context: context, approval: approval) else { throw NativeFriendFailure.notSent }
        let response: (Data, Int)
        do { response = try await transport.send(request) }
        catch NativeFriendFailure.notSent { throw NativeFriendFailure.notSent }
        catch { throw NativeFriendFailure.unknown }
        guard isCurrent, !Task.isCancelled else { throw NativeFriendFailure.unknown }
        guard response.0.count <= 262_144 else { throw NativeFriendFailure.unknown }
        let header = try? JSONDecoder().decode(Header.self, from: response.0)
        if response.1 == 401 && header?.code == 401 { retired = true; onUnauthorized(context); throw NativeFriendFailure.rejected(401) }
        guard (200..<300).contains(response.1), let header else { throw NativeFriendFailure.unknown }
        let originalRefusal = NativeFriendMetadataApproval.writePaths.union(NativeFriendMetadataApproval.groupWritePaths).contains(path) && body != nil && [400, 403, 404, 409].contains(header.code)
        if header.code != 200 && !originalRefusal {
            if header.code == 401 { retired = true; onUnauthorized(context) }
            if [400, 401, 403, 404, 409, 429].contains(header.code) { throw NativeFriendMetadataFailure.rejected(header.code, header.msg ?? "") }
            throw NativeFriendFailure.unknown
        }
        guard let payload = try? JSONDecoder().decode(Payload<T>.self, from: response.0) else { throw NativeFriendFailure.unknown }
        if originalRefusal {
            guard let proof = payload.data as? NativeFriendMetadataReceipt, proof.outcome == "REJECTED" else { throw NativeFriendFailure.unknown }
        }
        return payload.data
    }
    private struct Header: Decodable { let code: Int; let msg: String? }
    private struct Payload<T: Decodable>: Decodable { let data: T }
}
public enum NativeFriendMetadataTransportPolicy {
    public static func accepts(_ request: URLRequest, context: RuntimeDependencyContext, approval: NativeFriendMetadataApproval, now: Date = Date()) -> Bool {
        guard context.market == .china, !request.httpShouldHandleCookies, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json", request.value(forHTTPHeaderField: "Authorization") == context.session.token,
              approval.endpoint.baseURL == context.baseURL, approval.endpoint.namespace == context.session.namespace,
              approval.endpoint.accountID == context.session.accountID, now < approval.expiresAt,
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        var origin = parts; origin.query = nil
        guard let path = approval.endpoint.paths.first(where: { context.baseURL.appendingPathComponent($0) == origin.url }) else { return false }
        if NativeFriendMetadataApproval.readPaths.contains(path) || path == NativeFriendMetadataApproval.groupReadPath {
            guard request.httpMethod == "GET", request.httpBody == nil else { return false }
            let items = parts.queryItems ?? []; guard Set(items.map(\.name)).count == items.count, items.allSatisfy({ $0.value != nil }) else { return false }
            let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
            if path == "api/friend/group/list" { return fields.isEmpty }
            if path == "api/friend/metadata" { return Set(fields.keys) == ["peer_id"] && (Int64(fields["peer_id"] ?? "") ?? 0) > 0 && Int64(fields["peer_id"] ?? "") != Int64(context.session.accountID) }
            guard Set(fields.keys) == ["action", "target_id", "request_id"], let action = NativeFriendMetadataAction(rawValue: fields["action"] ?? ""),
                  let target = Int64(fields["target_id"] ?? ""), UUID(uuidString: fields["request_id"] ?? "") != nil else { return false }
            if action == .remark { return target > 0 && target != Int64(context.session.accountID) }
            return approval.endpoint.paths.contains("api/friend/group/list") && (target > 0 || (target == 0 && action == .groupSave))
        }
        guard NativeFriendMetadataApproval.writePaths.union(NativeFriendMetadataApproval.groupWritePaths).contains(path), request.httpMethod == "POST", parts.query == nil,
              let body = request.httpBody, body.count <= 4096, let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let identity = fields["request_id"] as? String, UUID(uuidString: identity) != nil,
              let version = integer(fields["expected_version"]), version >= 0 else { return false }
        if path == NativeFriendMetadataAction.remark.path {
            let required: Set<String> = ["peer_id", "request_id", "expected_version", "expected_friend_version"]
            let keys = Set(fields.keys)
            guard required.isSubset(of: keys), keys.isSubset(of: required.union(["remark", "starred", "group_id", "progress_scope"])),
                  !keys.isDisjoint(with: ["remark", "starred", "group_id", "progress_scope"]),
                  let peer = integer(fields["peer_id"]), peer > 0, peer != Int64(context.session.accountID),
                  (integer(fields["expected_friend_version"]) ?? 0) > 0, integer(fields["expected_friend_version"]) != Int64.max, version < Int64.max else { return false }
            if keys.contains("remark"), !(fields["remark"] is NSNull || ((fields["remark"] as? String).map { NativeFriendMetadataValidation.validRemark($0) } ?? false)) { return false }
            if keys.contains("group_id") {
                guard approval.allowsGroupChanges, approval.endpoint.paths.contains("api/friend/group/list"),
                      fields["group_id"] is NSNull || integer(fields["group_id"]).map({ $0 < Int64.max }) == true else { return false }
            }
            if keys.contains("progress_scope") {
                guard approval.allowsProgressChanges, fields["progress_scope"] is NSNull || integer(fields["progress_scope"]).map({ [0,1].contains($0) }) == true else { return false }
            }
            if keys.contains("starred") {
                guard approval.allowsStarChanges, fields["starred"] is NSNull || integer(fields["starred"]).map({ [0, 1].contains($0) }) == true else { return false }
            }
            return true
        }
        guard approval.allowsGroupChanges, approval.endpoint.paths.contains("api/friend/group/list"), version < Int64.max else { return false }
        if path == NativeFriendMetadataAction.groupSave.path {
            guard Set(fields.keys) == ["id", "name", "position", "expected_version", "request_id"], nullableID(fields["id"]),
                  let name = fields["name"] as? String, NativeFriendMetadataValidation.validGroupName(name),
                  let position = integer(fields["position"]), (0...Int64(Int32.max)).contains(position) else { return false }
            return fields["id"] is NSNull ? version == 0 : version > 0
        }
        guard Set(fields.keys) == ["id", "move_to_group_id", "expected_version", "request_id"],
              let id = integer(fields["id"]), id > 0, version > 0, nullableID(fields["move_to_group_id"]) else { return false }
        return integer(fields["move_to_group_id"]) != id
    }
    private static func integer(_ value: Any?) -> Int64? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: value.objCType)), value.int64Value >= 0 else { return nil }
        return value.int64Value
    }
    private static func nullableID(_ value: Any?) -> Bool { value is NSNull || (integer(value) ?? 0) > 0 }
}
