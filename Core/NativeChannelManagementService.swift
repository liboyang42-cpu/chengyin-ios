import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NativeChannelManagementAccess: String, Hashable {
    case directory, detail, managementInventory, metadataCommand, metadataReceipt, permissionsRead, permissionCommand, governanceReceipt
}

/// The host supplies an independently reviewed final-forward dispatcher. Its implementation
/// must call stillCurrent immediately before forwarding, and must not retry or follow redirects.
/// There is deliberately no adapter from the host's general HTTPTransport/URLSession.
@MainActor public protocol NativeChannelManagementDispatching {
    func send(_ request: URLRequest, fence: NativeChannelManagementDispatchFence) async throws -> (Data, Int)
}

@MainActor public final class NativeChannelManagementDispatchFence {
    private let check: () -> Bool
    public init(_ check: @escaping () -> Bool) { self.check = check }
    public var isCurrent: Bool { check() }
}

@MainActor public struct NativeChannelManagementDispatchTransport: NativeChannelManagementDispatching {
    private let operation: @MainActor (URLRequest, NativeChannelManagementDispatchFence) async throws -> (Data, Int)
    public init(_ operation: @escaping @MainActor (URLRequest, NativeChannelManagementDispatchFence) async throws -> (Data, Int)) { self.operation = operation }
    public func send(_ request: URLRequest, fence: NativeChannelManagementDispatchFence) async throws -> (Data, Int) {
        guard fence.isCurrent else { throw NativeChannelManagementError.changedIdentity }
        let response = try await operation(request, fence)
        guard fence.isCurrent else { throw NativeChannelManagementError.changedIdentity }; return response
    }
}

/// Composition-issued endpoint lease, independent of server RBAC. No initializer/factory in a view.
/// Native login provenance and deployment/RBAC review must be complete before the host issues it.
/// Current sources do not prove those gates; ordinary host integration supplies nil.
@MainActor @Observable public final class NativeChannelManagementApproval {
    public let context: RuntimeDependencyContext
    public let viewerRevision: UInt64
    public let scope: NativeChannelManagementScope
    public let operations: Set<NativeChannelManagementAccess>
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64, scope: NativeChannelManagementScope,
                operations: Set<NativeChannelManagementAccess>, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0, !context.session.namespace.isEmpty,
              AuthRequestBuilder.isValidToken(context.session.token), !operations.isEmpty,
              expiresAt > Date(), expiresAt.timeIntervalSinceNow <= 86400 else { throw NativeChannelManagementError.unavailable }
        self.context = context; self.viewerRevision = viewerRevision; self.scope = scope
        self.operations = operations; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ context: RuntimeDependencyContext, viewerRevision: UInt64, scope: NativeChannelManagementScope) -> Bool {
        !revoked && Date() < expiresAt && self.viewerRevision == viewerRevision && self.scope == scope
            && ContentDraftContextFence.matches(self.context, context)
    }
}

public struct NativeChannelManagementIdentity: Equatable {
    public let owner: NativeChannelManagementOwner
    public let epoch: UInt64
    public let viewerRevision: UInt64
    public let approvalRevision: UUID
}

/// Evidence of a successful real manager-inventory read, separate from row permission names.
/// Only this file's HTTP consumer can issue it; it is neither Codable nor a persistent grant.
/// Callers still check its captured identity against the current service and re-read before restore.
public struct NativeChannelManagementInventory {
    public let scope: NativeChannelManagementScope
    public let identity: NativeChannelManagementIdentity
    public let channels: [NativeChannelManagementChannel]
    fileprivate init(scope: NativeChannelManagementScope, identity: NativeChannelManagementIdentity,
                     channels: [NativeChannelManagementChannel]) {
        self.scope = scope; self.identity = identity; self.channels = channels
    }
    public func restorableChannel(_ id: NativeChannelManagementID) throws -> NativeChannelManagementChannel {
        guard let channel = channels.first(where: { $0.id == id }), channel.scope == scope,
              channel.status == 3, channel.recoverable, channel.purgeAt != nil else {
            throw NativeChannelManagementError.forbidden
        }
        return channel // Preserve sparse permissions exactly; do not add MANAGE_CHANNEL.
    }
}

/// Context data only; never a webhook grant, credential, policy proof or fresh membership check.
/// ownerID is the original CLUB/TEAM aggregate id (guild_id), not the owner member id. Kind2 remains unsupported.
public struct NativeChannelManagementIntegrationContext: Equatable {
    public let channelID: NativeChannelManagementID
    public let ownerType: String
    public let ownerID: NativeChannelManagementID
    public let identity: NativeChannelManagementIdentity
    public let metadataVersion: NativeChannelManagementVersion
    public let permissionVersion: NativeChannelManagementVersion
    public let serverPermissionNames: Set<String>
    public let sourcePath: String
    fileprivate init(channel: NativeChannelManagementChannel, identity: NativeChannelManagementIdentity) throws {
        try channel.requireDetail(in: channel.scope)
        guard [1, 3].contains(channel.scope.guildKind), let version = channel.permissionVersion else { throw NativeChannelManagementError.invalidSource }
        channelID = channel.id; ownerType = channel.scope.guildKind == 1 ? "CLUB" : "TEAM"; ownerID = channel.scope.guildID
        self.identity = identity; metadataVersion = channel.version; permissionVersion = version
        serverPermissionNames = channel.permissionNames; sourcePath = "api/channels/\(channel.id)"
    }
}

/// Original 8 injects this read-only provider. Every entry fetches the real channel again.
/// 8 must independently verify native origin, im:webhook:manage and current dedicated authority.
@MainActor public protocol NativeChannelManagementIntegrationContextProviding: AnyObject {
    func currentChannelContext(channelID: NativeChannelManagementID) async throws -> NativeChannelManagementIntegrationContext
    func contextIsCurrent(_ context: NativeChannelManagementIntegrationContext) -> Bool
}

public struct NativeChannelManagementAppliedResult: Decodable, Equatable {
    public let requestID: String
    public let state: String
    public let id: NativeChannelManagementID?
    public let channelID: NativeChannelManagementID?
    public let guildKind: Int?
    public let guildID: NativeChannelManagementID?
    public let version: NativeChannelManagementVersion?
    public let status: Int?
    public let name: String?
    public let replayed: Bool?
    public let purgeAt: String?
    public let unchanged: Bool?
    public let permissionVersion: NativeChannelManagementVersion?
    public let targetType: Int?
    public let targetID: String?
    public let allowBits: String?
    public let denyBits: String?
    public let note: String?
    public let inherited: Bool?
    public let deleted: Bool?
    public let auditID: NativeChannelManagementID?
    enum CodingKeys: String, CodingKey { case state, id, version, status, name, replayed, unchanged; case requestID = "request_id", channelID = "channel_id", guildKind = "guild_kind", guildID = "guild_id", purgeAt = "purge_at"
        case permissionVersion = "perm_version", targetType = "target_type", targetID = "target_id"
        case allowBits = "allow_bits", denyBits = "deny_bits", note, inherited, deleted, auditID = "audit_id"
    }
    public func validate(for intent: NativeChannelManagementIntent) throws {
        guard requestID == intent.requestID, state == "APPLIED" else { throw NativeChannelManagementError.invalidSource }
        if intent.isPermissionChange {
            guard channelID == intent.channelID, targetType == intent.targetType,
                  targetID == intent.targetID, auditID != nil else { throw NativeChannelManagementError.invalidSource }
            if intent.hasPermissionCAS {
                guard let metadata = intent.expectedVersion, let permissions = intent.permissionVersion,
                      metadata.value < Int64.max, permissions.value < Int64.max,
                      version?.value == metadata.value + 1, permissionVersion?.value == permissions.value + 1 else {
                    throw NativeChannelManagementError.invalidSource
                }
            }
            if intent.operation == .deleteOverwrite {
                guard deleted == true, inherited == true else { throw NativeChannelManagementError.invalidSource }
            } else {
                guard inherited == false, deleted != true,
                      case .some(.string(let expectedAllow)) = intent.fields["allow_bits"],
                      case .some(.string(let expectedDeny)) = intent.fields["deny_bits"],
                      let allowBits, let denyBits, allowBits.hasPrefix("0x"), denyBits.hasPrefix("0x"),
                      let allow = UInt64(allowBits.dropFirst(2), radix: 16),
                      let deny = UInt64(denyBits.dropFirst(2), radix: 16),
                      allow == UInt64(expectedAllow.dropFirst(2), radix: 16),
                      deny == UInt64(expectedDeny.dropFirst(2), radix: 16) else {
                    throw NativeChannelManagementError.invalidSource
                }
                let expectedNote: String?
                if case .some(.string(let value)) = intent.fields["note"] { expectedNote = value } else { expectedNote = nil }
                guard note == expectedNote else { throw NativeChannelManagementError.invalidSource }
            }
        } else {
            guard let id, guildKind == intent.scope.guildKind, guildID == intent.scope.guildID, version != nil,
                  intent.channelID == nil || id == intent.channelID else { throw NativeChannelManagementError.invalidSource }
            guard let status, let name, (0...4).contains(status), !name.isEmpty, name.unicodeScalars.count <= 64 else {
                throw NativeChannelManagementError.invalidSource
            }
            let expectedStatus: Int?
            switch intent.operation {
            case .create, .edit, .unarchive: expectedStatus = 0
            case .archive, .restore: expectedStatus = 1
            case .delete: expectedStatus = 3
            default: expectedStatus = nil
            }
            guard expectedStatus == status else { throw NativeChannelManagementError.invalidSource }
            if let expected = intent.expectedVersion {
                guard expected.value < Int64.max, version?.value == (unchanged == true ? expected.value : expected.value + 1) else {
                    throw NativeChannelManagementError.invalidSource
                }
            } else if version?.value != 0 { throw NativeChannelManagementError.invalidSource }
        }
    }
}

public enum NativeChannelManagementOriginalOutcome: Equatable {
    case applied(NativeChannelManagementAppliedResult)
    case appliedRedacted
    case pending
    case notFound
}

@MainActor public protocol NativeChannelManagementServing: NativeChannelManagementIntegrationContextProviding {
    var scope: NativeChannelManagementScope { get }
    var owner: NativeChannelManagementOwner { get }
    var identity: NativeChannelManagementIdentity? { get }
    var isCurrent: Bool { get }
    func invalidate()
    func allows(_ access: NativeChannelManagementAccess) -> Bool
    func directory() async throws -> NativeChannelManagementDirectory
    func directoryIncludingOwnHidden() async throws -> NativeChannelManagementDirectory
    func inventory() async throws -> NativeChannelManagementInventory
    func detail(_ id: NativeChannelManagementID) async throws -> NativeChannelManagementChannel
    func permissions(_ id: NativeChannelManagementID) async throws -> NativeChannelManagementPermissions
    func roles() async throws -> [NativeChannelManagementRole]
    func effectivePermissions(_ id: NativeChannelManagementID) async throws -> NativeChannelManagementEffectivePermissions
    func execute(_ intent: NativeChannelManagementIntent) async throws -> NativeChannelManagementAppliedResult
    func originalOutcome(_ intent: NativeChannelManagementIntent) async throws -> NativeChannelManagementOriginalOutcome
}

public extension NativeChannelManagementServing {
    func directoryIncludingOwnHidden() async throws -> NativeChannelManagementDirectory { throw NativeChannelManagementError.unavailable }
}

@MainActor public final class NativeChannelManagementHTTPService: NativeChannelManagementServing {
    public let scope: NativeChannelManagementScope
    public let owner: NativeChannelManagementOwner
    private let context: RuntimeDependencyContext
    private let capturedViewer: UInt64
    private let capturedApproval: UUID?
    private let configuration: APIConfiguration
    private let transport: any NativeChannelManagementDispatching
    private let current: () -> RuntimeDependencyContext?
    private let viewer: () -> UInt64
    private let selectedApproval: () -> NativeChannelManagementApproval?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var retired = false
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64, scope: NativeChannelManagementScope,
                configuration: APIConfiguration, transport: any NativeChannelManagementDispatching,
                current: @escaping () -> RuntimeDependencyContext?, viewer: @escaping () -> UInt64,
                selectedApproval: @escaping () -> NativeChannelManagementApproval? = { nil },
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) throws {
        guard configuration.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8), context.market == .china else {
            throw NativeChannelManagementError.unavailable
        }
        self.context = context; capturedViewer = viewerRevision; self.scope = scope; self.configuration = configuration
        self.transport = transport; self.current = current; self.viewer = viewer; self.selectedApproval = selectedApproval
        self.onUnauthorized = onUnauthorized; capturedApproval = selectedApproval()?.revision
        owner = try .init(accountID: context.session.accountID, namespace: context.session.namespace, baseURL: context.baseURL)
    }
    public var isCurrent: Bool {
        guard !retired else { return false }
        guard let live = current(), ContentDraftContextFence.matches(context, live), viewer() == capturedViewer,
              let capturedApproval, let grant = selectedApproval(), grant.revision == capturedApproval,
              grant.matches(live, viewerRevision: capturedViewer, scope: scope) else { retired = true; return false }
        return true
    }
    public var identity: NativeChannelManagementIdentity? {
        guard isCurrent, let revision = capturedApproval else { return nil }
        return .init(owner: owner, epoch: context.session.epoch, viewerRevision: capturedViewer, approvalRevision: revision)
    }
    public func invalidate() { retired = true }
    public func allows(_ access: NativeChannelManagementAccess) -> Bool { isCurrent && selectedApproval()?.operations.contains(access) == true }
    public func directory() async throws -> NativeChannelManagementDirectory { try await readDirectory(includeHidden: false) }
    public func directoryIncludingOwnHidden() async throws -> NativeChannelManagementDirectory { try await readDirectory(includeHidden: true) }
    private func readDirectory(includeHidden: Bool) async throws -> NativeChannelManagementDirectory {
        let path = "api/guilds/\(scope.guildKind)/\(scope.guildID)/channels"
        let result: NativeChannelManagementDirectory = try await query(path, .directory, query: ["include_hidden": includeHidden ? "1" : "0", "with_unread": "1"])
        guard result.scope == scope else { throw NativeChannelManagementError.invalidSource }
        for row in result.channels { try row.requireDirectoryRow(in: scope) }
        return result
    }
    public func inventory() async throws -> NativeChannelManagementInventory {
        guard let captured = identity else { throw NativeChannelManagementError.changedIdentity }
        let result: [NativeChannelManagementChannel] = try await query("api/guilds/\(scope.guildKind)/\(scope.guildID)/channels/manage", .managementInventory)
        guard result.count <= 2500, Set(result.map(\.id)).count == result.count, result.allSatisfy({ $0.scope == scope }) else {
            throw NativeChannelManagementError.invalidSource
        }
        guard identity == captured else { throw NativeChannelManagementError.changedIdentity }
        return .init(scope: scope, identity: captured, channels: result)
    }
    public func detail(_ id: NativeChannelManagementID) async throws -> NativeChannelManagementChannel {
        let row: NativeChannelManagementChannel = try await query("api/channels/\(id)", .detail)
        guard row.id == id else { throw NativeChannelManagementError.invalidSource }; try row.requireDetail(in: scope); return row
    }
    public func permissions(_ id: NativeChannelManagementID) async throws -> NativeChannelManagementPermissions {
        let row: NativeChannelManagementPermissions = try await query("api/channels/\(id)/permissions", .permissionsRead)
        guard row.channelID == id, row.overrides.count <= 2000,
              Set(row.overrides.map(\.id)).count == row.overrides.count else { throw NativeChannelManagementError.invalidSource }
        for item in row.overrides {
            _ = try NativeChannelManagementOverwrite(targetType: item.targetType, targetID: item.targetID,
                allowBits: item.allowBits, denyBits: item.denyBits, note: item.note)
        }; return row
    }
    public func roles() async throws -> [NativeChannelManagementRole] {
        struct Page: Decodable { let list: [NativeChannelManagementRole]; let has_more: Bool }
        let page: Page = try await query("api/im/roles", .permissionsRead,
            query: ["guild_kind": String(scope.guildKind), "guild_id": scope.guildID.rawValue, "include_disabled": "false"])
        guard !page.has_more, page.list.count <= 2000, Set(page.list.map(\.id)).count == page.list.count,
              page.list.allSatisfy({ $0.guildKind == scope.guildKind && $0.guildID == scope.guildID && $0.status == 1 && !$0.name.isEmpty }) else {
            throw NativeChannelManagementError.invalidSource
        }; return page.list
    }
    public func effectivePermissions(_ id: NativeChannelManagementID) async throws -> NativeChannelManagementEffectivePermissions {
        let row: NativeChannelManagementEffectivePermissions = try await query("api/channels/\(id)/effective/\(owner.accountID)", .permissionsRead)
        guard row.channelID == id, row.memberID.rawValue == String(owner.accountID), row.names.count <= 64,
              row.permissions.hasPrefix("0x"), UInt64(row.permissions.dropFirst(2), radix: 16) != nil else {
            throw NativeChannelManagementError.invalidSource
        }; return row
    }
    public func execute(_ intent: NativeChannelManagementIntent) async throws -> NativeChannelManagementAppliedResult {
        try intent.validate(); guard intent.scope == scope else { throw NativeChannelManagementError.invalidSource }
        if intent.isPermissionChange {
            // Legacy v1 bytes are never upgraded or resent under the new CAS contract.
            guard intent.hasPermissionCAS else { throw NativeChannelManagementError.permissionCASUnavailable }
            guard allows(.permissionCommand), let id = intent.channelID else { throw NativeChannelManagementError.unavailable }
            let live = try await detail(id)
            guard live.canManagePermissions else { throw NativeChannelManagementError.forbidden }
            let snapshot = try await permissions(id)
            guard live.version == intent.expectedVersion, live.permissionVersion == intent.permissionVersion,
                  snapshot.version == intent.expectedVersion, snapshot.permissionVersion == intent.permissionVersion else {
                throw NativeChannelManagementError.versionConflict
            }
            if intent.operation == .putOverwrite {
                guard case .some(.string(let text)) = intent.fields["allow_bits"],
                      let allow = UInt64(text.dropFirst(2), radix: 16) else { throw NativeChannelManagementError.invalidDraft }
                let owned = NativeChannelManagementCapability.allCases.filter { live.permissionNames.contains($0.rawValue) }
                    .reduce(UInt64(0)) { $0 | $1.bit }
                guard allow & ~owned == 0 else { throw NativeChannelManagementError.forbidden }
            }
            // Fresh reads are UI preflight only. The original backend transaction compares
            // and increments BOTH versions; this consumer never substitutes a read lock for CAS.
            let row: NativeChannelManagementAppliedResult = try await send(path: intent.path, method: intent.method,
                body: intent.body(), reason: intent.reason, access: .permissionCommand)
            try row.validate(for: intent); return row
        }
        guard allows(.metadataCommand) else { throw NativeChannelManagementError.unavailable }
        if let id = intent.channelID {
            let live: NativeChannelManagementChannel
            if intent.operation == .restore {
                let inventory = try await inventory()
                guard inventory.identity == identity else { throw NativeChannelManagementError.changedIdentity }
                live = try inventory.restorableChannel(id)
            } else {
                live = try await detail(id)
                guard live.canManage else { throw NativeChannelManagementError.forbidden }
            }
            guard live.version == intent.expectedVersion else { throw NativeChannelManagementError.versionConflict }
        } else { _ = try await inventory() } // Real requireSpaceManager endpoint; VIEW is insufficient.
        let row: NativeChannelManagementAppliedResult = try await send(path: intent.path, method: intent.method,
            body: intent.body(), reason: intent.reason, access: .metadataCommand)
        try row.validate(for: intent); return row
    }
    public func originalOutcome(_ intent: NativeChannelManagementIntent) async throws -> NativeChannelManagementOriginalOutcome {
        try intent.validate(); guard intent.scope == scope else { throw NativeChannelManagementError.invalidSource }
        let receipt: Receipt = try await query(intent.receiptPath, intent.isPermissionChange ? .governanceReceipt : .metadataReceipt)
        // Governance NOT_FOUND omits request_id; only that exact state may omit it.
        guard receipt.requestID == intent.requestID || (intent.isPermissionChange && receipt.state == "NOT_FOUND" && receipt.requestID == nil) else {
            throw NativeChannelManagementError.invalidSource
        }
        switch receipt.state {
        case "NOT_FOUND": guard receipt.result == nil, receipt.outcomeKnown != true else { throw NativeChannelManagementError.invalidSource }; return .notFound
        case "PENDING": guard receipt.result == nil, receipt.outcomeKnown != true else { throw NativeChannelManagementError.invalidSource }; return .pending
        case "APPLIED":
            if receipt.redacted == true {
                guard receipt.outcomeKnown == true, receipt.result == nil else { throw NativeChannelManagementError.invalidSource }; return .appliedRedacted
            }
            guard let result = receipt.result else { throw NativeChannelManagementError.invalidSource }
            try result.validate(for: intent); return .applied(result)
        default: throw NativeChannelManagementError.invalidSource
        }
    }
    public func currentChannelContext(channelID: NativeChannelManagementID) async throws -> NativeChannelManagementIntegrationContext {
        let row = try await detail(channelID)
        guard let identity else { throw NativeChannelManagementError.changedIdentity }
        return try .init(channel: row, identity: identity)
    }
    public func contextIsCurrent(_ context: NativeChannelManagementIntegrationContext) -> Bool {
        identity == context.identity && context.ownerID == scope.guildID &&
            ((scope.guildKind == 1 && context.ownerType == "CLUB") || (scope.guildKind == 3 && context.ownerType == "TEAM"))
    }
    private struct Receipt: Decodable {
        let requestID: String?; let state: String; let result: NativeChannelManagementAppliedResult?
        let redacted: Bool?; let outcomeKnown: Bool?
        enum CodingKeys: String, CodingKey { case requestID = "request_id", state, result, redacted = "result_redacted", outcomeKnown = "outcome_known" }
    }
    private struct Header: Decodable { let code: Int; let errorCode: String?; let outcome_known: Bool? }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value }
    private func query<Value: Decodable>(_ path: String, _ access: NativeChannelManagementAccess, query: [String: String] = [:]) async throws -> Value {
        try await send(path: path, method: "GET", query: query, access: access)
    }
    private func send<Value: Decodable>(path: String, method: String, query: [String: String] = [:], body: Data? = nil,
                                        reason: String? = nil, access: NativeChannelManagementAccess) async throws -> Value {
        try Task.checkCancellation()
        guard allows(access) else { throw NativeChannelManagementError.unavailable }
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) } }
        guard let url = components?.url, url.fragment == nil else { throw NativeChannelManagementError.invalidSource }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.httpShouldHandleCookies = false; request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let reason { request.setValue(reason, forHTTPHeaderField: "X-Audit-Log-Reason") }
        // Last synchronous fence before the host's injected final-forward transport. No generic URLSession fallback.
        guard allows(access) else { throw NativeChannelManagementError.changedIdentity }
        let response: (Data, Int)
        do { response = try await transport.send(request, fence: .init { [weak self] in self?.allows(access) == true }) }
        catch { guard isCurrent else { throw NativeChannelManagementError.changedIdentity }; throw NativeChannelManagementError.outcomeUnknown }
        guard isCurrent, allows(access) else { throw NativeChannelManagementError.changedIdentity }
        // HTTP authentication failure is authoritative even when a proxy/server sends no JSON body.
        // The old-context fence stays above the callback, so a late response cannot expire a new session.
        if response.1 == 401 {
            invalidate(); onUnauthorized(context); throw NativeChannelManagementError.changedIdentity
        }
        guard !Task.isCancelled else { throw NativeChannelManagementError.changedIdentity }
        guard response.0.count <= 2 * 1024 * 1024, let header = try? JSONDecoder().decode(Header.self, from: response.0) else {
            throw NativeChannelManagementError.outcomeUnknown
        }
        if header.code == 401 {
            invalidate(); onUnauthorized(context); throw NativeChannelManagementError.changedIdentity
        }
        guard (200..<300).contains(response.1), header.code == 200 else {
            // Actual helper maps commit/storage uncertainty to OUTCOME_UNKNOWN before business causes.
            guard (400..<500).contains(response.1), response.1 == header.code, header.outcome_known != false,
                  let code = header.errorCode, code != "OUTCOME_UNKNOWN",
                  code.range(of: "^[A-Z][A-Z0-9_]{0,127}$", options: .regularExpression) != nil else {
                throw NativeChannelManagementError.outcomeUnknown
            }; throw NativeChannelManagementError.rejected(code)
        }
        do { return try JSONDecoder().decode(Envelope<Value>.self, from: response.0).data }
        catch { throw NativeChannelManagementError.outcomeUnknown }
    }
}
