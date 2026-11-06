import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public pages may be anonymous. Account, token, role and epoch still fence retained work.
public struct MerchantPublicHostContext: Equatable {
    public let market: RegionalMarket
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int?
    public let epoch: UInt64
    public let role: String?
    fileprivate let token: String?
    public init(market: RegionalMarket, baseURL: URL, namespace: String, accountID: Int? = nil,
                epoch: UInt64, role: String? = nil, token: String? = nil) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard !namespace.isEmpty,
              (accountID == nil && token == nil && role == nil) ||
                (accountID.map { $0 > 0 } == true && token.map(AuthRequestBuilder.isValidToken) == true && role?.isEmpty == false)
        else { throw APIError.invalidConfiguration }
        self.market = market; self.baseURL = baseURL; self.namespace = namespace
        self.accountID = accountID; self.epoch = epoch; self.role = role; self.token = token
    }
}

/// Exact CURRENT source capabilities. No voice/provider-resource route is accepted here.
/// An account-specific approval cannot turn into an anonymous or another account's grant.
public struct MerchantPublicProductionApproval {
    public let market: RegionalMarket
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int?
    public let publicHomeRead: Bool
    public let chatMerchantRows: Set<PublicMerchantRowID>
    public init(market: RegionalMarket, baseURL: URL, namespace: String, accountID: Int? = nil,
                publicHomeRead: Bool = false, chatMerchantRows: Set<PublicMerchantRowID> = []) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard !namespace.isEmpty, accountID.map({ $0 > 0 }) ?? true,
              chatMerchantRows.isEmpty || (accountID != nil && publicHomeRead) else { throw APIError.invalidConfiguration }
        self.market = market; self.baseURL = baseURL; self.namespace = namespace; self.accountID = accountID
        self.publicHomeRead = publicHomeRead; self.chatMerchantRows = chatMerchantRows
    }
    public func matches(_ context: MerchantPublicHostContext) -> Bool {
        market == .china && context.market == market && baseURL == context.baseURL &&
        namespace == context.namespace && accountID == context.accountID
    }
}

@MainActor public final class MerchantPublicProductionFactory {
    public static let supportsLegacyResources = false
    public let captured: MerchantPublicHostContext
    public let homeReader: any PublicMerchantHomeReading
    private let approval: MerchantPublicProductionApproval
    private let api: APIConfiguration
    private let transport: any HTTPTransport
    private let chatTransport: any HTTPTransport
    private let current: () -> MerchantPublicHostContext?
    private let grants: () -> MerchantNPCGrants
    private let journal: (any OperationPendingJournal)?
    public init?(api: APIConfiguration, approval: MerchantPublicProductionApproval? = nil,
                 transport: any HTTPTransport, chatTransport: (any HTTPTransport)? = nil, journal: (any OperationPendingJournal)? = nil,
                 current: @escaping () -> MerchantPublicHostContext?, grants: @escaping () -> MerchantNPCGrants = { .init() }) {
        guard let approval, let captured = current(), approval.matches(captured), api.baseURL == captured.baseURL else { return nil }
        self.captured = captured; self.approval = approval; self.api = api; self.transport = transport
        self.chatTransport = chatTransport ?? transport
        self.current = current; self.grants = grants; self.journal = journal
        if approval.publicHomeRead {
            homeReader = MerchantPublicScopedHomeReader(api: api, transport: transport, captured: captured, current: current)
        } else { homeReader = DisabledPublicMerchantHomeReader() }
    }
    public var isCurrent: Bool { current() == captured }
    public var chatGrants: MerchantNPCGrants {
        guard isCurrent, captured.accountID != nil, journal != nil, !approval.chatMerchantRows.isEmpty else { return .init() }
        // Chat acceptance never grants voice cloning, media transmission or merchant ownership.
        let input = grants(); var value = MerchantNPCGrants()
        value.server = input.server; value.provider = input.provider; value.legal = input.legal
        return value
    }
    public func chatClient(currentScope: @escaping (PublicMerchantRowID) -> MerchantNPCScope?) -> MerchantNPCHTTPClient {
        guard chatGrants.chatAllowed, let journal else { return .init() }
        return .init(transport: MerchantPublicChatTransport(api: api, approval: approval, captured: captured,
            transport: chatTransport, homeReader: homeReader, journal: journal, current: current,
            grants: { self.chatGrants }, currentScope: currentScope))
    }
    /// Existing legacy resource DTOs do not match this backend. Keep that seam hard closed.
    public func resourceClient() -> MerchantNPCHTTPClient { .init() }
}

@MainActor private final class MerchantPublicScopedHomeReader: PublicMerchantHomeReading {
    let scope = UUID()
    var isConfigured: Bool { current() == captured }
    let isOfflineExample = false
    private let reader: PublicMerchantHomeHTTPReader
    private let captured: MerchantPublicHostContext
    private let current: () -> MerchantPublicHostContext?
    init(api: APIConfiguration, transport: any HTTPTransport, captured: MerchantPublicHostContext,
         current: @escaping () -> MerchantPublicHostContext?) {
        reader = .init(configuration: api, transport: transport)
        self.captured = captured; self.current = current
    }
    func home(_ target: PublicMerchantHomeTarget) async throws -> PublicMerchantHome {
        try Task.checkCancellation()
        guard isConfigured else { throw PublicMerchantHomeFailure.notConfigured }
        let value = try await reader.home(target)
        try Task.checkCancellation()
        guard isConfigured else { throw CancellationError() }
        // Never project a returned row into a requested owner, or vice versa.
        switch target {
        case .ownerMemberID(let id): guard value.memberId == id.rawValue else { throw PublicMerchantHomeFailure.retryable }
        case .legacyMerchantRowID(let id): guard value.id == id.rawValue else { throw PublicMerchantHomeFailure.retryable }
        }
        return value
    }
}

/// The only authenticated operation accepted by this factory is current merchant-chat.
/// Fresh anonymous public-home readback precedes dispatch. The durable lock contains only
/// request identity, deployment/account and row; never a token, prompt, or model response.
@MainActor private final class MerchantPublicChatTransport: MerchantNPCHTTPTransport {
    private let api: APIConfiguration
    private let approval: MerchantPublicProductionApproval
    private let captured: MerchantPublicHostContext
    private let transport: any HTTPTransport
    private let homeReader: any PublicMerchantHomeReading
    private let journal: any OperationPendingJournal
    private let current: () -> MerchantPublicHostContext?
    private let grants: () -> MerchantNPCGrants
    private let currentScope: (PublicMerchantRowID) -> MerchantNPCScope?
    private var sending = false
    init(api: APIConfiguration, approval: MerchantPublicProductionApproval, captured: MerchantPublicHostContext,
         transport: any HTTPTransport, homeReader: any PublicMerchantHomeReading, journal: any OperationPendingJournal,
         current: @escaping () -> MerchantPublicHostContext?, grants: @escaping () -> MerchantNPCGrants,
         currentScope: @escaping (PublicMerchantRowID) -> MerchantNPCScope?) {
        self.api = api; self.approval = approval; self.captured = captured; self.transport = transport
        self.homeReader = homeReader; self.journal = journal; self.current = current; self.grants = grants; self.currentScope = currentScope
    }
    private func valid(_ scope: MerchantNPCScope) -> Bool {
        current() == captured && approval.matches(captured) && currentScope(scope.merchantRowID) == scope &&
        scope.accountID == captured.accountID && scope.namespace == captured.namespace &&
        approval.chatMerchantRows.contains(scope.merchantRowID) && grants().chatAllowed
    }
    func perform(_ input: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
        guard !sending, valid(input.scope), let token = captured.token,
              input.path == "/api/ai/npc/merchant-chat", input.method == "POST" else { throw MerchantNPCFailure.disabled }
        guard input.body.count <= 4096,
              let fields = try? JSONSerialization.jsonObject(with: input.body) as? [String: Any],
              Set(fields.keys) == ["requestId", "bizId", "message"],
              let requestID = fields["requestId"] as? String, let id = UUID(uuidString: requestID),
              fields["bizId"] as? Int == input.scope.merchantRowID.rawValue,
              let message = fields["message"] as? String, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              message.unicodeScalars.count <= 300 else { throw MerchantNPCFailure.invalid }
        let owner = "merchant-public-chat:\(captured.baseURL.absoluteString):\(captured.namespace.utf8.count):\(captured.namespace):\(input.scope.accountID)"
        let record = OperationPendingRecord(operationID: id, ownerKey: owner, targetKey: "merchant-row:\(input.scope.merchantRowID.rawValue)")
        do {
            if let pending = try journal.pending(ownerKey: owner, targetKey: record.targetKey), pending != record { throw MerchantNPCFailure.unknownOutcome }
        } catch { throw MerchantNPCFailure.unknownOutcome }
        sending = true; defer { sending = false }
        try Task.checkCancellation()
        let home = try await homeReader.home(.legacyMerchantRowID(input.scope.merchantRowID))
        guard valid(input.scope), home.id == input.scope.merchantRowID.rawValue, home.hasNPCIdentity else { throw MerchantNPCFailure.disabled }
        try Task.checkCancellation()
        do { try journal.write(record) } catch { throw MerchantNPCFailure.unknownOutcome }
        // Do not clear a pre-existing unknown record if session/cancellation changes now.
        guard valid(input.scope), !Task.isCancelled else { throw MerchantNPCFailure.unknownOutcome }
        var request = URLRequest(url: api.baseURL.appendingPathComponent("api/ai/npc/merchant-chat"))
        request.httpMethod = "POST"; request.httpBody = input.body; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        let result: (Data, Int)
        do { result = try await transport.send(request) } catch { throw MerchantNPCFailure.unknownOutcome }
        guard valid(input.scope), !Task.isCancelled else { throw MerchantNPCFailure.unknownOutcome }
        if let denial = MerchantNPCGameDispatchDenial(rawValue: result.1) { throw denial }
        guard result.0.count <= 1024 * 1024 else { throw MerchantNPCFailure.unknownOutcome }
        if (200..<300).contains(result.1),
           let object = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
           let code = object["code"] as? Int,
           let denial = MerchantNPCGameDispatchDenial(rawValue: code) { throw denial }
        // Only the exact request's terminal source status reconciles its pending lock.
        guard (200..<300).contains(result.1),
              let envelope = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              envelope["code"] as? Int == 200,
              let data = envelope["data"] as? [String: Any], data["requestId"] as? String == requestID,
              let bytes = try? JSONSerialization.data(withJSONObject: data),
              let reply = try? JSONDecoder().decode(MerchantNPCReply.self, from: bytes),
              (try? reply.validate(requestID: id)) != nil else { throw MerchantNPCFailure.unknownOutcome }
        if reply.outcomeStatus != "PROCESSING" && !reply.canRetry {
            do { try journal.clear(record) } catch { throw MerchantNPCFailure.unknownOutcome }
        }
        return .init(status: result.1, body: result.0)
    }
}

/// Game-only extraction of the existing signed-in merchant NPC adapter.
/// The public-home transport stays independent. An adapter recognizes only an
/// already-approved exact game POST; it never creates a grant or original-read authority.
@MainActor public final class MerchantGameNPCProductionTransport: HTTPTransport {
    private let approval: MerchantPublicProductionApproval
    private let captured: MerchantPublicHostContext
    private let transport: any HTTPTransport
    private let current: () -> MerchantPublicHostContext?
    private let grants: () -> MerchantNPCGrants
    public init(approval: MerchantPublicProductionApproval, context: MerchantPublicHostContext,
                transport: any HTTPTransport, current: @escaping () -> MerchantPublicHostContext?,
                grants: @escaping () -> MerchantNPCGrants) {
        self.approval = approval; captured = context; self.transport = transport
        self.current = current; self.grants = grants
    }
    private func accepts(_ request: URLRequest) -> Bool {
        guard current() == captured, captured.accountID != nil, approval.matches(captured), grants().chatAllowed,
              request.httpMethod == "POST", !request.httpShouldHandleCookies,
              request.httpBodyStream == nil, request.url?.query == nil, request.url?.fragment == nil,
              request.url?.absoluteString == captured.baseURL.appendingPathComponent("api/ai/npc/merchant-chat").absoluteString,
              request.value(forHTTPHeaderField: "Authorization") == captured.token,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let body = request.httpBody, body.count <= 4096,
              let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              Set(fields.keys) == ["requestId", "bizId", "message"],
              let raw = fields["requestId"] as? String, UUID(uuidString: raw)?.uuidString == raw,
              let row = fields["bizId"] as? Int, let identity = PublicMerchantRowID(row),
              approval.chatMerchantRows.contains(identity),
              let message = fields["message"] as? String, MerchantNPCMessageDraft(message).isValid,
              let canonical = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
              canonical == body else { return false }
        return true
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard accepts(request) else { throw APIError.notConfigured }
        let result = try await transport.send(request)
        try Task.checkCancellation()
        guard accepts(request) else { throw CancellationError() }
        // An exact current HTTP denial carries no trusted content. Preserve its
        // status even when its untrusted body is oversized; never settle the UUID.
        if MerchantNPCGameDispatchDenial(rawValue: result.1) != nil { return (Data(), result.1) }
        guard result.0.count <= 1_048_576 else { throw CancellationError() }
        return result
    }
}
