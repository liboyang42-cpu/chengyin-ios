import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// BK-LIKE: `POST /api/topic/like` takes an explicit final state, `type=1` like and
/// `type=0` unlike, both idempotent. An omitted or blank `type` keeps the legacy
/// toggle-as-like default, so this factory never builds a request without one.
public enum TopicLikeDirection: Int, Codable, Equatable, CaseIterable {
    case unlike = 0, like = 1
    public init(liked: Bool) { self = liked ? .like : .unlike }
    public var liked: Bool { self == .like }
    var typeField: String { String(rawValue) }
}

/// Audited request construction only. No transport, approval, or UI entry exists here.
public struct TopicLikeOperationFactory {
    public static let path = "api/topic/like"
    public let configuration: APIConfiguration
    public init(configuration: APIConfiguration) { self.configuration = configuration }
    public func request(topicID: Int, direction: TopicLikeDirection, token: String) throws -> URLRequest {
        guard topicID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        return try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(Self.path),
                                                      fields: ["id": String(topicID), "type": direction.typeField], token: token)
    }
}

/// Source acknowledgement is `AjaxResult{code,msg}` with no like state, so success
/// only proves the write was accepted; the like state comes from a fresh topic read.
public enum TopicLikeWriteOutcome: Equatable {
    case acknowledged
    /// A parsed business rejection (请先登录, 参数不合规, 主题不存在…) is a definite non-change.
    case rejected(String?)
    case unauthorized
    /// The request may have reached the server; only a readback resolves it.
    case unknown

    public static func decode(data: Data, status: Int) -> Self {
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        if status == 401 || envelope?.code == 401 || envelope?.code == 2 { return .unauthorized }
        guard (200..<300).contains(status), let envelope else { return .unknown }
        return envelope.code == 200 ? .acknowledged : .rejected(envelope.msg)
    }
    private struct Envelope: Decodable { let code: Int; let msg: String? }
}

public struct TopicLikeScope: Hashable {
    public let accountID: Int
    public let epoch: UInt64
    public let namespace: String
    public init(accountID: Int, epoch: UInt64, namespace: String) throws {
        guard accountID > 0, !namespace.isEmpty else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.namespace = namespace
    }
}

public struct TopicLikeWriteTicket: Equatable {
    public let topicID: Int
    public let direction: TopicLikeDirection
    let scope: TopicLikeScope
    let sequence: UInt64
}
public struct TopicLikeReadTicket: Equatable {
    public let topicID: Int
    let scope: TopicLikeScope
    let sequence: UInt64
    /// A read issued while a write is in flight cannot tell which side of it the server saw.
    let writeInFlight: Bool
}

/// Per-account ordering of explicit like intents and their readbacks. Only the newest
/// intent may settle a topic, and only a read started after that write completed can
/// confirm the server state; a button tap or acknowledgement is never treated as truth.
@MainActor public final class TopicLikeLedger {
    public enum State: Equatable {
        /// Last accepted server readback (`isLike` from a fresh topic read).
        case confirmed(liked: Bool)
        case sending(TopicLikeDirection)
        /// Write acknowledged; waiting for a readback to confirm the final state.
        case awaitingReadback(TopicLikeDirection)
        /// Outcome uncertain; nothing is re-sent until a readback resolves it.
        case unknown(TopicLikeDirection)
        case rejected(TopicLikeDirection, message: String?)
        /// Readback disagreed with the newest intent (e.g. an older request landed last).
        case mismatch(requested: TopicLikeDirection, liked: Bool)
    }
    public private(set) var scope: TopicLikeScope?
    public private(set) var states: [Int: State] = [:]
    private var latest: [Int: UInt64] = [:]
    private var inFlight: [Int: Set<UInt64>] = [:]
    private var counter: UInt64 = 0
    public init() {}

    /// A different account or epoch drops every state, ticket, and pending readback.
    private func bind(_ current: TopicLikeScope?) -> Bool {
        guard let current else { reset(); return false }
        if scope != current { reset(); scope = current }
        return true
    }
    public func reset() { scope = nil; states = [:]; latest = [:]; inFlight = [:] }

    /// Returns nil for a duplicate of the pending direction or while an uncertain write is unresolved.
    public func begin(topicID: Int, direction: TopicLikeDirection, scope current: TopicLikeScope?) -> TopicLikeWriteTicket? {
        guard topicID > 0, bind(current), let current else { return nil }
        switch states[topicID] {
        case .sending(let pending), .awaitingReadback(let pending):
            if pending == direction { return nil }
        case .unknown: return nil
        default: break
        }
        counter += 1
        latest[topicID] = counter; inFlight[topicID, default: []].insert(counter)
        states[topicID] = .sending(direction)
        return .init(topicID: topicID, direction: direction, scope: current, sequence: counter)
    }

    /// Returns false when the ticket is superseded or belongs to another account.
    @discardableResult
    public func complete(_ ticket: TopicLikeWriteTicket, outcome: TopicLikeWriteOutcome, scope current: TopicLikeScope?) -> Bool {
        guard current == ticket.scope, scope == ticket.scope else { if current != scope { reset() }; return false }
        inFlight[ticket.topicID]?.remove(ticket.sequence)
        if inFlight[ticket.topicID]?.isEmpty == true { inFlight[ticket.topicID] = nil }
        // An older response may still have changed the server, so the newest intent stays
        // unconfirmed; if nothing newer is in flight, the next readback decides.
        guard latest[ticket.topicID] == ticket.sequence else { return false }
        switch outcome {
        case .acknowledged: states[ticket.topicID] = .awaitingReadback(ticket.direction)
        case .rejected(let message): states[ticket.topicID] = .rejected(ticket.direction, message: message)
        case .unknown: states[ticket.topicID] = .unknown(ticket.direction)
        case .unauthorized: reset()
        }
        return true
    }

    public func beginReadback(topicID: Int, scope current: TopicLikeScope?) -> TopicLikeReadTicket? {
        guard topicID > 0, bind(current), let current else { return nil }
        return .init(topicID: topicID, scope: current, sequence: latest[topicID] ?? 0, writeInFlight: inFlight[topicID] != nil)
    }

    /// Applies a fresh server `isLike`. Rejected when a write started or was in flight
    /// during the read, or when the account changed.
    @discardableResult
    public func observe(_ ticket: TopicLikeReadTicket, liked: Bool, scope current: TopicLikeScope?) -> Bool {
        guard current == ticket.scope, scope == ticket.scope else { if current != scope { reset() }; return false }
        guard !ticket.writeInFlight, inFlight[ticket.topicID] == nil, (latest[ticket.topicID] ?? 0) == ticket.sequence else { return false }
        switch states[ticket.topicID] {
        case .awaitingReadback(let requested), .unknown(let requested):
            states[ticket.topicID] = requested.liked == liked ? .confirmed(liked: liked) : .mismatch(requested: requested, liked: liked)
        default:
            states[ticket.topicID] = .confirmed(liked: liked)
        }
        return true
    }

    /// Server truth only: nil until a readback for the current account was accepted.
    public func confirmedLiked(topicID: Int) -> Bool? {
        switch states[topicID] {
        case .confirmed(let liked), .mismatch(_, let liked): return liked
        default: return nil
        }
    }
}
