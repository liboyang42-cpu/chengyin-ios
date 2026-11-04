import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The existing host must check this fence at the actual network forward, after any queue.
/// No generic URLSession adapter is supplied; redirects and automatic retries are forbidden.
@MainActor public protocol NativeChannelProgressDispatching {
    func send(_ request: URLRequest, fence: NativeChannelProgressDispatchFence) async throws -> (Data, Int)
}
@MainActor public final class NativeChannelProgressDispatchFence {
    private let check: () -> Bool
    public init(_ check: @escaping () -> Bool) { self.check = check }
    public var isCurrent: Bool { !Task.isCancelled && check() }
}
@MainActor private struct NativeChannelProgressForwardTransport: HTTPTransport {
    let dispatcher: any NativeChannelProgressDispatching
    let fence: NativeChannelProgressDispatchFence
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard fence.isCurrent else { throw NativeChannelProgressError.closed }
        do {
            let value = try await dispatcher.send(request, fence: fence)
            guard fence.isCurrent else { throw NativeChannelProgressError.closed }; return value
        } catch {
            guard fence.isCurrent else { throw NativeChannelProgressError.closed }; throw error
        }
    }
}

public enum NativeChannelProgressOperation: String, Hashable { case definitions, overview, top, detail, best, recent, version, meter, privacy, savePrivacy, receipt }

/// Supplied by the existing session/43 scope host from its actual permission and revocation source.
/// A nonempty version identifies that source's current authorization snapshot, not a UI flag.
public struct NativeChannelProgressAuthoritySnapshot: Equatable {
    public let identity: NativeChannelProgressIdentity
    public let channelID: Int64?
    public let authorizationVersion: String
    public let metadataVersion: Int64?
    public let permissionVersion: Int64?
    public let endpointApprovalRevision: UUID
    public let viewerRevision: UInt64
    public let operations: Set<NativeChannelProgressOperation>
    public init(identity: NativeChannelProgressIdentity, channelID: Int64?, authorizationVersion: String,
                metadataVersion: Int64?, permissionVersion: Int64?, endpointApprovalRevision: UUID, viewerRevision: UInt64,
                operations: Set<NativeChannelProgressOperation>) throws {
        guard channelID.map({ $0 > 0 }) ?? operations.isSubset(of: [.privacy, .savePrivacy, .receipt]), !authorizationVersion.isEmpty,
              channelID == nil || (metadataVersion.map({ $0 >= 0 }) == true && permissionVersion.map({ $0 >= 0 }) == true) else { throw NativeChannelProgressError.invalid }
        self.identity = identity; self.channelID = channelID; self.authorizationVersion = authorizationVersion; self.operations = operations
        self.metadataVersion = metadataVersion; self.permissionVersion = permissionVersion
        self.endpointApprovalRevision = endpointApprovalRevision; self.viewerRevision = viewerRevision
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity && lhs.channelID == rhs.channelID &&
        lhs.authorizationVersion.utf8.elementsEqual(rhs.authorizationVersion.utf8) &&
        lhs.metadataVersion == rhs.metadataVersion && lhs.permissionVersion == rhs.permissionVersion &&
        lhs.endpointApprovalRevision == rhs.endpointApprovalRevision && lhs.viewerRevision == rhs.viewerRevision && lhs.operations == rhs.operations
    }
}

/// Reuses 43's actual context provider. CLUB context data is never converted into a progress grant.
@MainActor public enum NativeChannelProgressBinding {
    public static func make(context: NativeChannelManagementIntegrationContext,
                            provider: any NativeChannelManagementIntegrationContextProviding,
                            selectedAuthority: @escaping () -> NativeChannelProgressAuthoritySnapshot?,
                            dispatcher: any NativeChannelProgressDispatching, token: @escaping () -> String?,
                            storage: any NativeChannelProgressJournalStorage, onUnauthorized: @escaping () -> Void) throws -> NativeChannelProgressCoordinator {
        guard context.ownerType == "CLUB", provider.contextIsCurrent(context), let authority = selectedAuthority(),
              authority.channelID.map(String.init) == context.channelID.rawValue,
              authority.identity.actorID == Int64(context.identity.owner.accountID),
              authority.identity.namespace.utf8.elementsEqual(context.identity.owner.namespace.utf8),
              authority.identity.origin.absoluteString.utf8.elementsEqual(context.identity.owner.baseURL.utf8),
              authority.identity.sessionEpoch == String(context.identity.epoch),
              authority.viewerRevision == context.identity.viewerRevision,
              authority.metadataVersion == context.metadataVersion.value,
              authority.permissionVersion == context.permissionVersion.value else { throw NativeChannelProgressError.closed }
        let client = try NativeChannelProgressClient(captured: authority, dispatcher: dispatcher,
            current: { provider.contextIsCurrent(context) ? selectedAuthority() : nil }, token: token, onUnauthorized: onUnauthorized)
        return try .init(access: client, journal: .init(identity: authority.identity, storage: storage))
    }
}
@MainActor public protocol NativeChannelProgressAccess: AnyObject {
    var authority: NativeChannelProgressAuthoritySnapshot? { get }
    func retireOperations()
    func definitions() async throws -> NativeChannelProgressDefinitions
    func overview() async throws -> NativeChannelProgressOverview
    func page(_ query: NativeChannelProgressQuery, detail: Bool, cursor: String?) async throws -> NativeChannelProgressPage
    func best(_ query: NativeChannelProgressQuery) async throws -> NativeChannelProgressRow
    func recent(_ query: NativeChannelProgressQuery, cursor: String?) async throws -> NativeChannelProgressPage
    func version(_ boardKey: String) async throws -> NativeChannelProgressVersion
    func meter(_ board: NativeChannelProgressBoard) async throws -> NativeChannelProgressMeter
    func privacy() async throws -> NativeChannelProgressPrivacy
    func save(_ command: NativeChannelProgressPrivacyCommand) async throws -> NativeChannelProgressPrivacy
    func receipt(_ command: NativeChannelProgressPrivacyCommand) async throws -> NativeChannelProgressPrivacy?
}

@MainActor public final class NativeChannelProgressClient: NativeChannelProgressAccess {
    private let captured: NativeChannelProgressAuthoritySnapshot
    private let current: () -> NativeChannelProgressAuthoritySnapshot?
    private let token: () -> String?
    private let dispatcher: any NativeChannelProgressDispatching
    private let onUnauthorized: () -> Void
    private let capturedCredential: String
    private var operationRevision: UInt64 = 0
    private var authorityRetired = false
    /// A loss that has been observed can never be reversed by an equal-looking snapshot.
    /// A later session/approval must bind a new client. Visit retirement remains separate.
    public var authority: NativeChannelProgressAuthoritySnapshot? {
        guard !authorityRetired else { return nil }
        guard current() == captured, let credential = token(),
              capturedCredential.utf8.elementsEqual(credential.utf8) else {
            authorityRetired = true; retireOperations(); return nil
        }
        return captured
    }
    public func retireOperations() { operationRevision &+= 1 }
    public init(captured: NativeChannelProgressAuthoritySnapshot, dispatcher: any NativeChannelProgressDispatching,
                current: @escaping () -> NativeChannelProgressAuthoritySnapshot?, token: @escaping () -> String?, onUnauthorized: @escaping () -> Void) throws {
        guard let credential = token(), AuthRequestBuilder.isValidToken(credential) else { throw NativeChannelProgressError.closed }
        self.captured = captured; self.current = current; self.token = token; capturedCredential = credential
        self.dispatcher = dispatcher; self.onUnauthorized = onUnauthorized
        _ = try APIConfiguration(baseURL: captured.identity.origin)
    }
    private func isCurrent(_ operation: NativeChannelProgressOperation, revision: UInt64, credential: String) -> Bool {
        !Task.isCancelled && authority != nil && operationRevision == revision && captured.operations.contains(operation) &&
        capturedCredential.utf8.elementsEqual(credential.utf8)
    }
    private func service(_ operation: NativeChannelProgressOperation, revision: UInt64, credential: String) throws -> NativeChannelProgressService {
        let fence = NativeChannelProgressDispatchFence { [weak self] in
            self?.isCurrent(operation, revision: revision, credential: credential) == true
        }
        return .init(configuration: try APIConfiguration(baseURL: captured.identity.origin), transport: NativeChannelProgressForwardTransport(dispatcher: dispatcher, fence: fence))
    }
    private func checked<Value>(_ operation: NativeChannelProgressOperation, work: (NativeChannelProgressService, String) async throws -> Value) async throws -> Value {
        let revision = operationRevision, credential = capturedCredential
        guard isCurrent(operation, revision: revision, credential: credential) else { throw NativeChannelProgressError.closed }
        let service = try service(operation, revision: revision, credential: credential)
        do {
            let value = try await work(service, credential)
            guard isCurrent(operation, revision: revision, credential: credential) else { throw NativeChannelProgressError.closed }
            return value
        } catch {
            // A stale response, including a stale 401, cannot act on a newer visit/session.
            guard isCurrent(operation, revision: revision, credential: credential) else { throw NativeChannelProgressError.closed }
            if case NativeChannelProgressError.server(let status, _) = error, status == 401 || status == 403 {
                authorityRetired = true; retireOperations()
                if status == 401 { onUnauthorized() }
                throw NativeChannelProgressError.closed
            }
            throw error
        }
    }
    private func requiredChannel() throws -> Int64 { guard let id = captured.channelID else { throw NativeChannelProgressError.invalid }; return id }
    public func definitions() async throws -> NativeChannelProgressDefinitions { try await checked(.definitions) { service, credential in try await service.definitions(channelID: requiredChannel(), token: credential) } }
    public func overview() async throws -> NativeChannelProgressOverview { try await checked(.overview) { service, credential in try await service.overview(channelID: requiredChannel(), token: credential) } }
    public func page(_ query: NativeChannelProgressQuery, detail: Bool, cursor: String?) async throws -> NativeChannelProgressPage { try await checked(detail ? .detail : .top) { service, credential in try await service.page(channelID: requiredChannel(), query: query, detail: detail, cursor: cursor, token: credential) } }
    public func best(_ query: NativeChannelProgressQuery) async throws -> NativeChannelProgressRow { try await checked(.best) { service, credential in try await service.best(channelID: requiredChannel(), query: query, token: credential) } }
    public func recent(_ query: NativeChannelProgressQuery, cursor: String?) async throws -> NativeChannelProgressPage { try await checked(.recent) { service, credential in try await service.recent(channelID: requiredChannel(), query: query, cursor: cursor, token: credential) } }
    public func version(_ key: String) async throws -> NativeChannelProgressVersion { try await checked(.version) { service, credential in try await service.version(channelID: requiredChannel(), boardKey: key, token: credential) } }
    public func meter(_ board: NativeChannelProgressBoard) async throws -> NativeChannelProgressMeter { try await checked(.meter) { service, credential in try await service.meter(channelID: requiredChannel(), board: board, actorID: captured.identity.actorID, token: credential) } }
    public func privacy() async throws -> NativeChannelProgressPrivacy { try await checked(.privacy) { service, credential in try await service.privacy(channelID: captured.channelID, token: credential) } }
    public func save(_ command: NativeChannelProgressPrivacyCommand) async throws -> NativeChannelProgressPrivacy { try await checked(.savePrivacy) { service, credential in try await service.save(command, token: credential) } }
    public func receipt(_ command: NativeChannelProgressPrivacyCommand) async throws -> NativeChannelProgressPrivacy? { try await checked(.receipt) { service, credential in try await service.receipt(command, token: credential) } }
}
