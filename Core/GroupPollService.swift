import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact independent feature grants. Initialization cannot send, vote or create a card.
public struct GroupPollService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public let enabledPaths: Set<String>
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabledPaths: Set<String> = []) {
        self.configuration = configuration; self.transport = transport; self.enabledPaths = enabledPaths
    }
    public func result(_ reference: GroupPollReference, token: String) async throws -> GroupPoll {
        try permit("api/im/poll/result")
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/poll/result"), fields: ["poll_id": String(reference.pollID)], token: token)
        let poll = try await execute(request)
        try poll.validate(reference: reference, conversationID: reference.conversationID, results: true); return poll
    }
    public func perform(_ mutation: GroupPollMutation, scope: IMScope, reference: GroupPollReference?, token: String) async throws -> GroupPoll {
        try permit(mutation.path)
        if case .create(let draft) = mutation {
            guard draft.conversationId == scope.conversationID, draft.deadline.map({ $0 > Date() }) ?? true else { throw APIError.invalidRequest }
        } else {
            guard let reference, reference.conversationID == scope.conversationID else { throw APIError.invalidRequest }
            switch mutation {
            case .vote(let id, _), .close(let id, _): guard id == reference.pollID else { throw APIError.invalidRequest }
            case .create: break
            }
        }
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: mutation.path, body: mutation.body(), token: token)
        let poll = try await execute(request)
        try poll.validate(reference: reference, conversationID: scope.conversationID, results: mutation.path != "api/im/poll/create")
        switch mutation {
        case .create(let draft):
            guard poll.creatorMemberId == scope.identity.accountID, poll.clientPollKey == draft.clientPollKey,
                  poll.question == draft.question, poll.options.map(\.content) == draft.options,
                  poll.deadlineAt?.value == draft.deadline else { throw APIError.malformedResponse }
        case .vote(_, let option): guard poll.myOptionId == option else { throw APIError.malformedResponse }
        case .close(_, let version):
            guard poll.creatorMemberId == scope.identity.accountID, poll.status == "CLOSED", version < Int.max, poll.version == version + 1 else { throw APIError.malformedResponse }
        }
        return poll
    }
    private func permit(_ path: String) throws { guard enabledPaths.contains(path) else { throw APIError.notConfigured } }
    private func execute(_ input: URLRequest) async throws -> GroupPoll {
        var request = input; request.httpShouldHandleCookies = false
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        struct Header: Decodable { let code: Int; let msg: String?; let errorCode: String? }
        struct Receipt: Decodable { let data: GroupPoll }
        guard data.count <= 128 * 1024 else { throw APIError.malformedResponse }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        guard (200..<300).contains(status) else { throw MessagingReadFailure(httpStatus: status, code: header?.code, errorCode: header?.errorCode, message: header?.msg) }
        guard let header else { throw APIError.malformedResponse }
        guard header.code == 200 else { throw MessagingReadFailure(code: header.code, errorCode: header.errorCode, message: header.msg) }
        guard let poll = try? JSONDecoder().decode(Receipt.self, from: data).data else { throw APIError.malformedResponse }
        return poll
    }
}
public struct GroupPollSession: Equatable {
    public let identity: MessagingReadIdentity
    let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = .init(accountID: accountID, epoch: epoch); self.token = token
    }
}
@MainActor public protocol GroupPollServing: AnyObject {
    var identity: MessagingReadIdentity? { get }
    func permits(_ path: String) -> Bool
    func result(_ reference: GroupPollReference, expectedIdentity: MessagingReadIdentity) async throws -> GroupPoll
    func perform(_ mutation: GroupPollMutation, scope: IMScope, reference: GroupPollReference?) async throws -> GroupPoll
}
@MainActor public final class GroupPollSessionClient: GroupPollServing {
    private let service: GroupPollService?
    private let session: () -> GroupPollSession?
    private let onUnauthorized: (GroupPollSession) -> Void
    public var identity: MessagingReadIdentity? { session()?.identity }
    public init(service: GroupPollService? = nil, session: @escaping () -> GroupPollSession?, onUnauthorized: @escaping (GroupPollSession) -> Void = { _ in }) {
        self.service = service; self.session = session; self.onUnauthorized = onUnauthorized
    }
    public func permits(_ path: String) -> Bool { session() != nil && service?.enabledPaths.contains(path) == true }
    public func result(_ reference: GroupPollReference, expectedIdentity: MessagingReadIdentity) async throws -> GroupPoll {
        try await execute(expectedIdentity) { service, token in try await service.result(reference, token: token) }
    }
    public func perform(_ mutation: GroupPollMutation, scope: IMScope, reference: GroupPollReference?) async throws -> GroupPoll {
        try await execute(scope.identity) { service, token in try await service.perform(mutation, scope: scope, reference: reference, token: token) }
    }
    private func execute(_ identity: MessagingReadIdentity, operation: (GroupPollService, String) async throws -> GroupPoll) async throws -> GroupPoll {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot = session(), snapshot.identity == identity, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
        do {
            let value = try await operation(service, snapshot.token)
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }; return value
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }; throw error
        }
    }
}
