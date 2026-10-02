import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// App-only source contract: a club ID is never a conversation ID. This call can create
/// or repair the member's club group, so it is an explicit, independently gated action.
@MainActor public protocol ClubChatServing: AnyObject {
    var identity: MessagingReadIdentity? { get }
    var isConfigured: Bool { get }
    func enter(clubID: Int, expectedIdentity: MessagingReadIdentity) async throws -> Int
}
@MainActor public final class ClubChatService: ClubChatServing {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let enabled: Bool
    private let session: () -> GroupPollSession?
    private let onUnauthorized: (GroupPollSession) -> Void
    public var identity: MessagingReadIdentity? { session()?.identity }
    public var isConfigured: Bool { enabled && identity != nil }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Bool = false,
                session: @escaping () -> GroupPollSession?, onUnauthorized: @escaping (GroupPollSession) -> Void = { _ in }) {
        self.configuration = configuration; self.transport = transport; self.enabled = enabled
        self.session = session; self.onUnauthorized = onUnauthorized
    }
    public func enter(clubID: Int, expectedIdentity: MessagingReadIdentity) async throws -> Int {
        guard isConfigured else { throw APIError.notConfigured }
        guard clubID > 0, let snapshot = session(), snapshot.identity == expectedIdentity, !Task.isCancelled else { throw APIError.invalidRequest }
        var request = try OperationAdapterHTTP.json(configuration: configuration, path: "api/club/chat", body: JSONEncoder().encode(["id": clubID]), token: snapshot.token)
        request.httpShouldHandleCookies = false
        do {
            let (data, status) = try await transport.send(request)
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            struct Header: Decodable { let code: Int; let msg: String? }
            struct Receipt: Decodable { struct Body: Decodable { let conversationId: Int }; let data: Body }
            guard data.count <= 16384 else { throw APIError.malformedResponse }
            let header = try? JSONDecoder().decode(Header.self, from: data)
            guard (200..<300).contains(status) else { throw MessagingReadFailure(httpStatus: status, code: header?.code, message: header?.msg) }
            guard let header else { throw APIError.malformedResponse }
            guard header.code == 200 else { throw MessagingReadFailure(code: header.code, message: header.msg) }
            guard let id = try? JSONDecoder().decode(Receipt.self, from: data).data.conversationId, id > 0 else { throw APIError.malformedResponse }
            return id
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }; throw error
        }
    }
}
public enum ClubChatPhase: Equatable { case idle, entering, ready(MessagingConversation), unknown, rejected, stale }
@MainActor public final class ClubChatCoordinator {
    public let clubID: Int
    public let identity: MessagingReadIdentity
    public let service: any ClubChatServing
    private let clubs: any ClubReading
    private let messages: any MessagingReading
    private var phase: ClubChatPhase = .idle
    private var generation: UInt64 = 0
    public var onChange: (() -> Void)?
    public var isCurrent: Bool {
        service.identity == identity && messages.identity == identity && clubs.clubIdentity.accountID == identity.accountID && clubs.clubIdentity.epoch == identity.epoch
    }
    public var visiblePhase: ClubChatPhase { isCurrent ? phase : .stale }
    public var canEnter: Bool { isCurrent && service.isConfigured && clubs.isClubConfigured && messages.isConfigured && phase != .entering }
    public init(clubID: Int, identity: MessagingReadIdentity, service: any ClubChatServing, clubs: any ClubReading, messages: any MessagingReading) throws {
        guard clubID > 0, identity.accountID > 0 else { throw APIError.invalidRequest }
        self.clubID = clubID; self.identity = identity; self.service = service; self.clubs = clubs; self.messages = messages
    }
    public func enter() async {
        guard canEnter, !Task.isCancelled else { return }
        generation &+= 1; let request = generation; phase = .entering; onChange?()
        var dispatched = false
        do {
            let club = try await clubs.clubDetail(id: clubID)
            guard isCurrent, generation == request, !Task.isCancelled else { return }
            guard club.id == clubID, club.isOwner || club.isJoined else { throw MessagingReadFailure(code: 403) }
            dispatched = true
            let conversationID = try await service.enter(clubID: clubID, expectedIdentity: identity)
            guard isCurrent, generation == request, !Task.isCancelled else { return }
            let conversations = try await messages.messagingConversations()
            guard isCurrent, generation == request, !Task.isCancelled else { return }
            guard let conversation = conversations.first(where: { $0.id == conversationID && $0.kind == .group && $0.counterparty?.bizKey == "club_\(clubID)" }) else { throw APIError.malformedResponse }
            phase = .ready(conversation)
        } catch {
            guard isCurrent, generation == request, !Task.isCancelled else { return }
            // Retrying is always the same club's source get-or-create operation, never
            // an im/start call or a new group creation API. No automatic retry.
            phase = dispatched ? .unknown : .rejected
        }
        onChange?()
    }
    public func suspend() { generation &+= 1; if phase == .entering { phase = .unknown }; onChange?() }
}
