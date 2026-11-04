import Foundation
import CryptoKit
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func validChainID(_ value: String) -> Bool { Int64(value).map { $0 > 0 && String($0) == value } == true }
public struct NativeChannelChainReference: Codable, Equatable {
    public let chainID, conversationID, messageID, creatorID: String
    public init(chainID: String, conversationID: String, messageID: String, creatorID: String) throws {
        guard [chainID, conversationID, messageID, creatorID].allSatisfy({ chainIDValue in validChainID(chainIDValue) }) else { throw APIError.malformedResponse }
        self.chainID = chainID; self.conversationID = conversationID; self.messageID = messageID; self.creatorID = creatorID
    }
    public init?(message: MessagingMessage) {
        struct Card: Decodable { let source, chainId, conversationId, creatorMemberId: String }
        guard message.isPayloadVisible, message.type == 14, let sender = message.senderID, sender > 0,
              let bytes = message.extraJSON?.data(using: .utf8), bytes.count <= 2048,
              let card = try? JSONDecoder().decode(Card.self, from: bytes), card.source == "original-channel-chain-v1",
              card.conversationId == String(message.conversationID), card.creatorMemberId == String(sender),
              let value = try? Self(chainID: card.chainId, conversationID: card.conversationId,
                                    messageID: String(message.id), creatorID: card.creatorMemberId) else { return nil }
        self = value
    }
}
public struct NativeChannelChainCommand: Codable, Equatable {
    public enum Operation: String, Codable { case create = "CREATE", join = "JOIN", withdraw = "WITHDRAW", close = "CLOSE" }
    public let requestId, conversationId: String
    public let operation: Operation
    public let chainId, title: String?
    public let maxSlots: Int?
    public let deadlineAt: Int64?
    public let content: String?
    public var path: String { "api/im/chain/" + operation.rawValue.lowercased() }
    public var digest: String {
        let fields = ["chain-v1", operation.rawValue, conversationId, chainId ?? "", title ?? "", maxSlots.map(String.init) ?? "", deadlineAt.map(String.init) ?? "", content ?? ""]
        let bytes = Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    public func validate() throws {
        guard validChainID(conversationId), let request = UUID(uuidString: requestId), request.uuidString.lowercased() == requestId else { throw APIError.invalidRequest }
        func text(_ value: String?, limit: Int) -> Bool {
            guard let value, !value.isEmpty, value.unicodeScalars.count <= limit,
                  value == value.trimmingCharacters(in: .whitespacesAndNewlines), !value.contains("<"), !value.contains("&") else { return false }
            return !value.unicodeScalars.contains { $0.value == 0 }
        }
        if operation == .create {
            guard chainId == nil, content == nil, text(title, limit: 200), let maxSlots, (0...Int(Int32.max)).contains(maxSlots),
                  deadlineAt.map({ (0...253402300799000).contains($0) }) ?? true else { throw APIError.invalidRequest }
        } else {
            guard chainId.map(validChainID) == true, title == nil, maxSlots == nil, deadlineAt == nil,
                  operation == .join ? text(content, limit: 2000) : content == nil else { throw APIError.invalidRequest }
        }
    }
}
public struct NativeChannelChainEntry: Decodable, Equatable, Identifiable {
    public let id, chainId, memberId, position, version, status: String
    public let content: String?
    fileprivate func validate(chain: String) throws {
        guard [id, chainId, memberId, position, version].allSatisfy(validChainID), chainId == chain,
              ["ACTIVE", "WITHDRAWN"].contains(status), status == "ACTIVE" ? content.map({ !$0.isEmpty && $0.unicodeScalars.count <= 2000 }) == true : content == nil else { throw APIError.malformedResponse }
    }
}
public struct NativeChannelChainRecord: Decodable, Equatable {
    public let id, conversationId, messageId, creatorMemberId, title, status, version: String
    public let maxSlots, activeCount: Int
    public let deadlineAt: Int64?
    public let accepting, canParticipate, canClose: Bool
    public var reference: NativeChannelChainReference? { try? .init(chainID: id, conversationID: conversationId, messageID: messageId, creatorID: creatorMemberId) }
}
public struct NativeChannelChainPage: Decodable {
    let source: String
    public let chain: NativeChannelChainRecord
    public let list: [NativeChannelChainEntry]
    public let mine: NativeChannelChainEntry?
    public let hasMore: Bool
    public let nextCursor: String?
    fileprivate func validate(reference: NativeChannelChainReference, actor: String, cursor: String) throws {
        guard source == "original-channel-chain-v1", chain.reference == reference, validChainID(chain.version),
              !chain.title.isEmpty, chain.title.unicodeScalars.count <= 200, ["OPEN", "CLOSED"].contains(chain.status),
              (0...Int(Int32.max)).contains(chain.maxSlots), (0...Int(Int32.max)).contains(chain.activeCount),
              chain.maxSlots == 0 || chain.activeCount <= chain.maxSlots,
              !chain.canClose || (chain.creatorMemberId == actor && chain.status == "OPEN" && chain.canParticipate),
              chain.deadlineAt.map({ (0...253402300799000).contains($0) }) ?? true,
              chain.status == "OPEN" || !chain.accepting, list.count <= 50,
              Set(list.map(\.id)).count == list.count, Set(list.map(\.memberId)).count == list.count,
              hasMore ? nextCursor == list.last?.position && nextCursor != nil : nextCursor == nil else { throw APIError.malformedResponse }
        var last = Int64(cursor) ?? -1
        guard last >= 0 else { throw APIError.invalidRequest }
        for entry in list { try entry.validate(chain: chain.id); guard let position = Int64(entry.position), position > last else { throw APIError.malformedResponse }; last = position }
        if let mine { try mine.validate(chain: chain.id); guard mine.memberId == actor, mine.status != "ACTIVE" || chain.activeCount > 0 else { throw APIError.malformedResponse } }
        // A withdrawn personal row must never coexist with an older visible copy.
        if let personal = list.first(where: { $0.memberId == actor || $0.id == mine?.id }) {
            guard personal == mine else { throw APIError.malformedResponse }
        }
    }
}
private struct NativeChannelChainReceipt: Decodable {
    struct Result: Decodable {
        let chainId, messageId, creatorMemberId, chainVersion, status: String
        let activeCount: Int
        let entry: NativeChannelChainEntry?
        func reference(conversation: String) throws -> NativeChannelChainReference { try .init(chainID: chainId, conversationID: conversation, messageID: messageId, creatorID: creatorMemberId) }
    }
    let source, actorId, conversationId, requestId, state: String
    let operation, requestHash: String?
    let resultRedacted: Bool?
    let result: Result?
    func validate(command: NativeChannelChainCommand, actor: String) throws {
        guard source == "original-channel-chain-request-v1", actorId == actor, conversationId == command.conversationId,
              requestId == command.requestId, ["APPLIED", "PENDING", "NOT_FOUND"].contains(state) else { throw APIError.malformedResponse }
        if state == "NOT_FOUND" {
            guard operation == nil, requestHash == nil, result == nil, resultRedacted == nil else { throw APIError.malformedResponse }; return
        }
        guard operation == command.operation.rawValue, requestHash == command.digest else { throw APIError.malformedResponse }
        if state == "PENDING" { guard result == nil, resultRedacted == nil else { throw APIError.malformedResponse }; return }
        if resultRedacted == true { guard result == nil else { throw APIError.malformedResponse }; return }
        guard resultRedacted == false, let result, validChainID(result.chainVersion), (0...Int(Int32.max)).contains(result.activeCount),
              command.chainId == nil || command.chainId == result.chainId else { throw APIError.malformedResponse }
        _ = try result.reference(conversation: command.conversationId)
        switch command.operation {
        case .create:
            guard result.creatorMemberId == actor, result.chainVersion == "1", result.status == "OPEN", result.activeCount == 0, result.entry == nil else { throw APIError.malformedResponse }
        case .close:
            guard result.creatorMemberId == actor, result.status == "CLOSED", result.entry == nil else { throw APIError.malformedResponse }
        case .join, .withdraw:
            guard result.status == "OPEN", let entry = result.entry, entry.memberId == actor,
                  command.operation != .join || result.activeCount > 0,
                  entry.status == (command.operation == .join ? "ACTIVE" : "WITHDRAWN") else { throw APIError.malformedResponse }
            try entry.validate(chain: result.chainId)
            if command.operation == .join { guard entry.content?.utf8.elementsEqual((command.content ?? "").utf8) == true else { throw APIError.malformedResponse } }
        }
    }
}
private enum NativeChannelChainFailure: Error { case rejected(Int, String) }

/// Same protected storage primitive as existing original-message journals. One exact
/// intent per actor/realm/channel; no tokens or role guesses, and no expiry on restart.
@MainActor private final class NativeChannelChainJournal {
    private let storage: any ProjectEditDataStorage
    private let owner: String
    private let channel: String
    private let key: String
    private static var leases: Set<String> = []
    private struct Record: Codable { let schema: Int, owner: String, command: NativeChannelChainCommand }
    init(storage: any ProjectEditDataStorage, context: RuntimeDependencyContext, channel: String) {
        self.storage = storage; self.channel = channel
        owner = [context.baseURL.absoluteString, context.session.namespace, String(context.session.accountID), channel].map { "\($0.utf8.count):\($0)" }.joined()
        key = "original-channel-chain.v1." + SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func acquire() -> Bool { Self.leases.insert(key).inserted }
    func release() { Self.leases.remove(key) }
    func restore() throws -> NativeChannelChainCommand? {
        guard let data = try storage.read(key) else { return nil }
        guard data.count <= 32768 else { throw APIError.malformedResponse }
        let record = try JSONDecoder().decode(Record.self, from: data)
        let encoded = try JSONEncoder().encode(record)
        guard record.schema == 1, record.owner == owner, record.command.conversationId == channel,
              (try JSONSerialization.jsonObject(with: data) as? NSDictionary) == (try JSONSerialization.jsonObject(with: encoded) as? NSDictionary) else { throw APIError.malformedResponse }
        try record.command.validate(); return record.command
    }
    func save(_ command: NativeChannelChainCommand) throws {
        try command.validate(); guard command.conversationId == channel else { throw APIError.invalidRequest }
        if let old = try restore() { guard old.digest == command.digest, old.requestId == command.requestId else { throw APIError.invalidRequest }; return }
        try storage.write(JSONEncoder().encode(Record(schema: 1, owner: owner, command: command)), key: key)
        guard let saved = try restore(), saved.digest == command.digest, saved.requestId == command.requestId else { throw APIError.malformedResponse }
    }
    func settle(_ command: NativeChannelChainCommand) throws {
        guard let saved = try restore(), saved.digest == command.digest, saved.requestId == command.requestId else { throw APIError.invalidRequest }
        try storage.remove(key); guard try restore() == nil else { throw APIError.malformedResponse }
    }
}

@MainActor public final class NativeChannelChainService {
    public let conversationID: String
    private let context: RuntimeDependencyContext
    private let transport: any HTTPTransport
    private let permitsRoute: (String, String) -> Bool
    private let current: () -> Bool
    private let unauthorized: () -> Void
    private var retired = false
    public var actorID: String { String(context.session.accountID) }
    public var isCurrent: Bool { guard !retired, current() else { retired = true; return false }; return true }
    public init(context: RuntimeDependencyContext, conversationID: String, transport: any HTTPTransport,
                permits: @escaping (String, String) -> Bool, current: @escaping () -> Bool, unauthorized: @escaping () -> Void) throws {
        guard validChainID(conversationID), context.session.accountID > 0, context.market == .china else { throw APIError.notConfigured }
        self.context = context; self.conversationID = conversationID; self.transport = transport
        permitsRoute = permits; self.current = current; self.unauthorized = unauthorized
    }
    public func allows(_ operation: NativeChannelChainCommand.Operation) -> Bool { allows("POST", "api/im/chain/" + operation.rawValue.lowercased()) }
    public var canRead: Bool { allows("GET", "api/im/chain/info") }
    public var canRecover: Bool { allows("GET", "api/im/interaction/request") }
    private func allows(_ method: String, _ path: String) -> Bool { isCurrent && permitsRoute(method, path) }
    private func request(method: String, path: String, query: [String: String] = [:], body: Data? = nil) throws -> URLRequest {
        guard allows(method, path) else { throw APIError.notConfigured }
        var url = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { url.queryItems = query.sorted(by: { $0.key < $1.key }).map { .init(name: $0.key, value: $0.value) } }
        guard let target = url.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: target); request.httpMethod = method; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    private func send<Value: Decodable>(_ request: URLRequest, sourceCurrent: () -> Bool) async throws -> Value {
        guard isCurrent, sourceCurrent(), !Task.isCancelled else { throw APIError.notConfigured }
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation(); guard isCurrent, sourceCurrent() else { throw APIError.notConfigured }
        guard data.count <= 512 * 1024 else { throw APIError.malformedResponse }
        let header = try? JSONDecoder().decode(NativeChainHeader.self, from: data)
        if status == 401 || header?.code == 401 { unauthorized(); retired = true; throw APIError.unauthorized }
        guard (200..<300).contains(status), let header else { throw APIError.malformedResponse }
        guard header.code == 200 else {
            if [400,403,404,409].contains(header.code), let code = header.errorCode, !code.isEmpty { throw NativeChannelChainFailure.rejected(header.code, code) }
            throw APIError.malformedResponse
        }
        return try JSONDecoder().decode(NativeChainEnvelope<Value>.self, from: data).data
    }
    fileprivate func page(_ reference: NativeChannelChainReference, cursor: String, sourceCurrent: () -> Bool) async throws -> NativeChannelChainPage {
        guard reference.conversationID == conversationID else { throw APIError.invalidRequest }
        let request = try request(method: "GET", path: "api/im/chain/info", query: ["conversation_id": conversationID, "chain_id": reference.chainID, "cursor": cursor, "limit": "50"])
        let page: NativeChannelChainPage = try await send(request, sourceCurrent: sourceCurrent)
        try page.validate(reference: reference, actor: actorID, cursor: cursor); return page
    }
    fileprivate func receipt(_ command: NativeChannelChainCommand, sourceCurrent: () -> Bool) async throws -> NativeChannelChainReceipt {
        guard command.conversationId == conversationID else { throw APIError.invalidRequest }
        let request = try request(method: "GET", path: "api/im/interaction/request", query: ["conversation_id": conversationID, "request_id": command.requestId])
        let receipt: NativeChannelChainReceipt = try await send(request, sourceCurrent: sourceCurrent)
        try receipt.validate(command: command, actor: actorID); return receipt
    }
    fileprivate func perform(_ command: NativeChannelChainCommand, sourceCurrent: () -> Bool) async throws -> NativeChannelChainReceipt {
        try command.validate(); guard command.conversationId == conversationID else { throw APIError.invalidRequest }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let request = try request(method: "POST", path: command.path, body: encoder.encode(command))
        let receipt: NativeChannelChainReceipt = try await send(request, sourceCurrent: sourceCurrent)
        try receipt.validate(command: command, actor: actorID); return receipt
    }
}
private struct NativeChainEnvelope<Value: Decodable>: Decodable { let data: Value }

private struct NativeChainHeader: Decodable { let code: Int; let errorCode: String? }

public enum NativeChannelChainPhase: Equatable { case idle, reading, reviewing, submitting, unknown, applied, appliedRedacted, rejected(String), failed, persistenceFailed, closed }
/// In-memory receipt presentation only; never a current roster or a reusable authorization.
public struct NativeChannelChainConfirmedRequest: Equatable {
    public let requestID: String
    public let operation: NativeChannelChainCommand.Operation
    public let resultRedacted: Bool
}
@MainActor @Observable public final class NativeChannelChainFlow {
    public let service: NativeChannelChainService
    public private(set) var reference: NativeChannelChainReference?
    public private(set) var page: NativeChannelChainPage?
    public private(set) var entries: [NativeChannelChainEntry] = []
    public private(set) var pending: NativeChannelChainCommand?
    public private(set) var review: NativeChannelChainCommand?
    public private(set) var phase: NativeChannelChainPhase = .idle
    private var confirmedRequest: NativeChannelChainConfirmedRequest?
    public var lastConfirmedRequest: NativeChannelChainConfirmedRequest? {
        isCurrent && service.canRecover ? confirmedRequest : nil
    }
    public private(set) var readFailed = false
    public private(set) var busy = false
    private let journal: NativeChannelChainJournal
    private let initialReference: NativeChannelChainReference?
    private var active = false
    private var generation: UInt64 = 0
    @ObservationIgnored private var sourceCurrent: () -> Bool = { false }
    public var isCurrent: Bool { active && sourceCurrent() && service.isCurrent }
    public var ownsPending: Bool { pending != nil && (initialReference == nil || pending?.chainId == initialReference?.chainID) }
    public var canCreate: Bool { isCurrent && phase != .persistenceFailed && !busy && pending == nil && review == nil && reference == nil && service.canRecover && service.canRead && service.allows(.create) }
    public var canJoin: Bool {
        isCurrent && !busy && pending == nil && review == nil && service.canRecover && service.allows(.join)
            && page?.chain.canParticipate == true && page?.chain.accepting == true
            && (page?.mine?.status == "ACTIVE" || page?.chain.maxSlots == 0 || (page.map { $0.chain.activeCount < $0.chain.maxSlots } ?? false))
    }
    public var canWithdraw: Bool { isCurrent && !busy && pending == nil && review == nil && service.canRecover && service.allows(.withdraw) && page?.chain.canParticipate == true && page?.chain.accepting == true && page?.mine?.status == "ACTIVE" }
    public var canClose: Bool { isCurrent && !busy && pending == nil && review == nil && service.canRecover && service.allows(.close) && page?.chain.canClose == true }
    public init(service: NativeChannelChainService, context: RuntimeDependencyContext, storage: any ProjectEditDataStorage, reference: NativeChannelChainReference?) throws {
        guard service.actorID == String(context.session.accountID), reference == nil || reference?.conversationID == service.conversationID else { throw APIError.invalidRequest }
        self.service = service; self.reference = reference; initialReference = reference
        journal = .init(storage: storage, context: context, channel: service.conversationID)
    }
    public func activate(current: @escaping () -> Bool) async {
        guard !Task.isCancelled else { return }
        confirmedRequest = nil
        sourceCurrent = current; active = true; generation &+= 1; phase = .idle
        guard isCurrent else { deactivate(); return }
        do { pending = try journal.restore() } catch { phase = .persistenceFailed; return }
        if ownsPending { await recover() } else if pending != nil { phase = .unknown }
        if isCurrent, reference != nil, phase != .appliedRedacted, phase != .persistenceFailed { await refresh() }
    }
    public func deactivate() {
        confirmedRequest = nil
        active = false; generation &+= 1; busy = false; page = nil; entries = []; review = nil; pending = nil; readFailed = false; phase = .closed
        // Retain durable intent. Disappearance cannot prove that a dispatched write rolled back.
    }
    private func current(_ run: UInt64) -> Bool { generation == run && isCurrent && !Task.isCancelled }
    public func refresh() async { await read(more: false) }
    public func more() async { await read(more: true) }
    private func read(more: Bool) async {
        guard isCurrent, !busy, review == nil, service.canRead, let reference else { return }
        let cursor = more ? page?.nextCursor : "0"
        guard let cursor else { return }
        let version = page?.chain.version
        generation &+= 1; let run = generation; busy = true; readFailed = false
        if pending == nil { phase = .reading }
        if !more { page = nil; entries = [] }
        defer { if generation == run { busy = false } }
        do {
            let value = try await service.page(reference, cursor: cursor, sourceCurrent: { self.current(run) })
            guard current(run) else { return }
            if more && value.chain.version != version {
                // Participation changed while paging. Restart at the same original chain,
                // never mix row snapshots or replace source order with numeric message IDs.
                let fresh = try await service.page(reference, cursor: "0", sourceCurrent: { self.current(run) })
                guard current(run) else { return }; page = fresh; entries = fresh.list
            } else {
                let oldIDs = Set(entries.map(\.id))
                let oldMembers = Set(entries.map(\.memberId))
                guard !more || value.list.allSatisfy({ !oldIDs.contains($0.id) && !oldMembers.contains($0.memberId) }) else { throw APIError.malformedResponse }
                if more, let personal = entries.first(where: { $0.memberId == service.actorID || $0.id == value.mine?.id }) {
                    guard personal == value.mine else { throw APIError.malformedResponse }
                }
                page = value; entries = more ? entries + value.list : value.list
            }
            if pending == nil { phase = .idle }
        } catch {
            guard current(run) else { return }; page = nil; entries = []; readFailed = true
            if pending == nil { phase = .failed }
        }
    }
    public func prepareCreate(title: String, maxSlots: Int, deadline: Date?) {
        guard canCreate else { return }
        let milliseconds: Int64?
        if let deadline {
            let value = deadline.timeIntervalSince1970 * 1000
            guard value.isFinite, value > Date().timeIntervalSince1970 * 1000, value < 253402300799000 else { phase = .rejected("CHAIN_DEADLINE_PAST"); return }
            milliseconds = Int64(value)
        } else { milliseconds = nil }
        prepare(.init(requestId: UUID().uuidString.lowercased(), conversationId: service.conversationID, operation: .create,
                      chainId: nil, title: title.trimmingCharacters(in: .whitespacesAndNewlines), maxSlots: maxSlots, deadlineAt: milliseconds, content: nil))
    }
    public func prepareJoin(content: String) {
        guard canJoin, let reference else { return }
        prepare(.init(requestId: UUID().uuidString.lowercased(), conversationId: service.conversationID, operation: .join,
                      chainId: reference.chainID, title: nil, maxSlots: nil, deadlineAt: nil, content: content.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    public func prepareWithdraw() { if canWithdraw { prepareAction(.withdraw) } }
    public func prepareClose() { if canClose { prepareAction(.close) } }
    private func prepareAction(_ operation: NativeChannelChainCommand.Operation) {
        guard let reference else { return }
        prepare(.init(requestId: UUID().uuidString.lowercased(), conversationId: service.conversationID, operation: operation,
                      chainId: reference.chainID, title: nil, maxSlots: nil, deadlineAt: nil, content: nil))
    }
    private func prepare(_ command: NativeChannelChainCommand) {
        do { try command.validate(); confirmedRequest = nil; review = command; phase = .reviewing }
        catch { phase = .rejected("INVALID_CHAIN_TEXT_OR_INPUT") }
    }
    public func cancelReview() { guard !busy else { return }; review = nil; phase = pending == nil ? .idle : .unknown }
    public func confirm() async {
        guard isCurrent, !busy, pending == nil, let command = review, service.canRecover,
              service.allows(command.operation), journal.acquire() else { return }
        generation &+= 1; let run = generation; busy = true
        defer { journal.release(); if generation == run { busy = false } }
        do {
            // The frozen review remains unchanged; a fresh original read still owns
            // current capacity, author, status, membership and message visibility.
            if let reference {
                let latest = try await service.page(reference, cursor: "0", sourceCurrent: { self.current(run) })
                guard current(run), command.chainId == reference.chainID else { return }
                page = latest; entries = latest.list
                switch command.operation {
                case .join:
                    guard latest.chain.canParticipate, latest.chain.accepting,
                          latest.mine?.status == "ACTIVE" || latest.chain.maxSlots == 0 || latest.chain.activeCount < latest.chain.maxSlots else { throw APIError.invalidRequest }
                case .withdraw: guard latest.chain.canParticipate, latest.chain.accepting, latest.mine?.status == "ACTIVE" else { throw APIError.invalidRequest }
                case .close: guard latest.chain.canClose else { throw APIError.invalidRequest }
                case .create: throw APIError.invalidRequest
                }
            }
            guard current(run) else { return }
            do { try journal.save(command) } catch { phase = .persistenceFailed; return }
            pending = command; review = nil; phase = .submitting
            guard current(run) else { return }
            await dispatch(command, run: run, retry: false)
        } catch { if current(run) { review = nil; phase = .rejected("CHAIN_REVIEW_CHANGED") } }
    }
    public func recover() async {
        guard isCurrent, !busy, ownsPending, service.canRecover, let command = pending else { return }
        generation &+= 1; let run = generation; busy = true; phase = .reading
        defer { if generation == run { busy = false } }
        do {
            let receipt = try await service.receipt(command, sourceCurrent: { self.current(run) })
            guard current(run) else { return }
            try settle(receipt, command: command)
        } catch { if current(run) { phase = .unknown } }
    }
    /// Explicit retry reads the SAME request first. A missing receipt is uncertainty,
    /// not a grant to create a replacement intent, change text or renew the deadline.
    public func retryOriginal() async {
        guard isCurrent, !busy, ownsPending, service.canRecover, let command = pending,
              service.allows(command.operation), journal.acquire() else { return }
        generation &+= 1; let run = generation; busy = true; phase = .reading
        defer { journal.release(); if generation == run { busy = false } }
        do {
            let receipt = try await service.receipt(command, sourceCurrent: { self.current(run) })
            guard current(run) else { return }
            if receipt.state == "APPLIED" { try settle(receipt, command: command); return }
            guard receipt.state == "NOT_FOUND" else { phase = .unknown; return }
            guard current(run), let saved = try journal.restore(), saved == command, saved.digest == command.digest else { throw APIError.invalidRequest }
            phase = .submitting; await dispatch(command, run: run, retry: true)
        } catch { if current(run) { phase = .unknown } }
    }
    private func dispatch(_ command: NativeChannelChainCommand, run: UInt64, retry: Bool) async {
        do {
            let receipt = try await service.perform(command, sourceCurrent: { self.current(run) })
            guard current(run) else { return }; try settle(receipt, command: command)
        } catch {
            guard current(run) else { return }
            // Only a first dispatch's explicit transactional rejection proves THIS
            // fresh intent did not commit. A retry rejection never clears old uncertainty.
            if !retry, case NativeChannelChainFailure.rejected(_, let code) = error, code != "REQUEST_ID_CONFLICT" {
                do { try journal.settle(command); pending = nil; phase = .rejected(code) }
                catch { phase = .persistenceFailed }
            } else { phase = .unknown }
        }
    }
    private func settle(_ receipt: NativeChannelChainReceipt, command: NativeChannelChainCommand) throws {
        guard receipt.state == "APPLIED" else { phase = .unknown; return }
        let recovered = try receipt.result.map { try $0.reference(conversation: service.conversationID) }
        guard ownsPending, receipt.resultRedacted == true || recovered != nil,
              initialReference == nil || recovered == nil || recovered == initialReference else { throw APIError.malformedResponse }
        try journal.settle(command); pending = nil; review = nil; page = nil; entries = []
        confirmedRequest = .init(requestID: command.requestId, operation: command.operation,
                                 resultRedacted: receipt.resultRedacted == true)
        if receipt.resultRedacted == true { phase = .appliedRedacted; return }
        guard let recovered else { throw APIError.malformedResponse }
        // The toolbar recovery may resume any original chain in THIS exact channel.
        // A card detail remains its original card; it never adopts another pending chain.
        if initialReference == nil || initialReference == recovered { reference = recovered }
        phase = .applied
    }
}
