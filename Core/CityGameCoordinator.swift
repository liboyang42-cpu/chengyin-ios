import Foundation
import Observation

/// One player choice the review card shows before anything is sent (W20.4–W20.7).
public struct CityGameReview: Equatable, Sendable {
    public let kind: CityActionKind
    public let targetId: String
    public let propertyId: String?
    public let serviceTitle: String?
    /// Server quote for point-spending actions; nil for free actions (roll, accept task).
    public let quote: CityActionQuote?
    public let expectedVersion: Int64
}

/// Drives the W20 player loop on top of the reviewed CITY read snapshot and the agent-H
/// action contracts: snapshot → choose → quote → explicit payer confirmation → one
/// in-flight intent → receipt, or receipt readback by the same requestId when the
/// outcome is unknown. A retry re-sends the exact same intent; it never re-rolls,
/// re-prices or re-spends. A changed quote is never auto-accepted. Everything is gated
/// by `ReformWorldCapabilities.cityActions` (OFF by default) and an injected service,
/// which only DEBUG fixtures provide. No cost, reward, dice or budget value is defined
/// here; every number shown comes from the server snapshot or quote.
@available(macOS 14.0, *)
@MainActor @Observable public final class CityGameCoordinator {
    public enum Phase: String, Sendable { case disabled, idle, loading, ready, unavailable, quoting, review, sending, unknown, invalidated }
    public enum Notice: String, Sendable {
        case unavailable, invalidQuote, payerMismatch, quoteExpired, insufficientPoints, busy, noReceiptYet, unknownOutcome, boardNotOpen, notJoined, refreshed
    }
    public private(set) var phase: Phase = .idle
    public private(set) var snapshot: CityGameSnapshot?
    public private(set) var review: CityGameReview?
    public private(set) var notice: Notice?
    public private(set) var lastOutcome: CityPendingAction.Outcome?
    public let read: CityReadSnapshot
    private var pending = CityPendingAction()
    private var stream: CityDeltaStream?
    private let service: (any CityGameServing)?
    private let capabilities: ReformWorldCapabilities
    private let memberId: String
    private let isCurrent: () -> Bool
    private let now: () -> Date
    private let serverOffset: () -> TimeInterval
    private var generation = UUID()

    public init(read: CityReadSnapshot, service: (any CityGameServing)?, capabilities: ReformWorldCapabilities, memberId: String,
                isCurrent: @escaping () -> Bool, now: @escaping () -> Date = { Date() }, serverOffset: @escaping () -> TimeInterval = { 0 }) {
        self.read = read; self.service = service; self.capabilities = capabilities; self.memberId = memberId
        self.isCurrent = isCurrent; self.now = now; self.serverOffset = serverOffset
        if service == nil || !capabilities.allows(.cityActions) || !ReformWire.id(memberId) { phase = .disabled }
    }

    public var pendingIntent: CityActionIntent? { pending.intent }
    public var isBusy: Bool { [.loading, .quoting, .sending].contains(phase) }
    public var canRetryExact: Bool { phase == .unknown && pending.intent != nil && isCurrent() }

    /// Why the board accepts no new actions right now, if anything.
    public var boardNotice: Notice? {
        guard let snapshot else { return nil }
        if !snapshot.lifecycle.acceptsNewActions || read.board.lifecycle != "OPEN" { return .boardNotOpen }
        if read.membership != .joined || read.participation == nil { return .notJoined }
        return nil
    }

    private var hasActionBudget: Bool { (snapshot?.rules.actionsRemaining ?? 0) > 0 }

    public var canRoll: Bool {
        guard phase == .ready, boardNotice == nil, let snapshot, snapshot.roundSeq != nil else { return false }
        return hasActionBudget
    }

    /// Server-backed choices for one property. Empty while busy, frozen, out of budget,
    /// paused or blocked by the safety overlay; neutral goals stay offered at zero points.
    public func actions(for property: CityPropertyState) -> [CityActionKind] {
        guard phase == .ready, boardNotice == nil, let snapshot, snapshot.roundSeq != nil, hasActionBudget,
              property.status.acceptsNewActions else { return [] }
        switch property.role {
        case .neutral: return [.acceptTask]
        case .operable:
            if property.heldByMyTeam { return [] }
            if property.status == .available {
                let limitReached = snapshot.rules.holdingLimit.map { snapshot.heldCount >= $0 } ?? true
                return limitReached ? [.acceptTask] : [.acceptTask, .acquireProperty]
            }
            var kinds: [CityActionKind] = [.acceptTask]
            if property.status == .held, property.challenge?.isTerminal ?? true { kinds.append(.startChallenge) }
            return kinds
        }
    }

    /// A service may be accepted only when its fee is published and the property is open.
    public func canAcceptService(_ service: CityServiceOffer, on property: CityPropertyState) -> Bool {
        guard phase == .ready, boardNotice == nil, snapshot?.roundSeq != nil, hasActionBudget, property.status.acceptsNewActions,
              !property.heldByMyTeam, property.status != .available else { return false }
        return service.memberPointsFee != nil
    }

    /// Logout, account/role/token change or leaving the board invalidates every reference.
    public func invalidate() {
        generation = UUID(); snapshot = nil; review = nil; stream = nil; notice = nil; lastOutcome = nil
        pending = CityPendingAction(); phase = .invalidated
    }

    private func gate() -> Bool {
        guard phase != .disabled, phase != .invalidated else { return false }
        guard isCurrent() else { invalidate(); return false }
        return true
    }

    public func load() async {
        guard gate(), let service, !isBusy, phase != .review else { return }
        let ticket = generation, wasUnknown = phase == .unknown
        phase = .loading
        do {
            let value = try await service.snapshot(for: read)
            try value.validate(against: read)
            guard ticket == generation, gate() else { return }
            snapshot = value
            let cursor = try CityStreamCursor(boardId: value.boardId, seasonId: value.seasonId, rulesReleaseId: value.rules.rulesReleaseId,
                                              boardVersion: value.boardVersion, sequence: value.sequence)
            if stream == nil { stream = CityDeltaStream(cursor: cursor) } else { stream?.reset(to: cursor) }
            // A snapshot never settles an unknown outcome; only its receipt can.
            phase = wasUnknown || pending.intent != nil ? .unknown : .ready
        } catch {
            guard ticket == generation, gate() else { return }
            snapshot = nil; notice = .unavailable
            phase = wasUnknown || pending.intent != nil ? .unknown : .unavailable
        }
    }

    /// Applies ordered deltas; any gap, regression or other season reloads the snapshot.
    public func refresh() async {
        guard gate(), let service, phase == .ready, let cursor = stream?.cursor else { return }
        let ticket = generation
        do {
            let page = try await service.deltas(after: cursor)
            guard ticket == generation, gate() else { return }
            switch stream?.ingest(page) ?? .snapshotRequired {
            case .unchanged: return
            case .applied, .snapshotRequired: notice = .refreshed; await load()
            }
        } catch {
            guard ticket == generation, gate() else { return }
            notice = .unavailable
        }
    }

    public func prepareRoll() {
        guard canRoll, let snapshot else { return }
        review = CityGameReview(kind: .roll, targetId: snapshot.boardId, propertyId: nil, serviceTitle: nil, quote: nil, expectedVersion: snapshot.boardVersion)
        notice = nil; lastOutcome = nil; phase = .review
    }

    public func prepare(_ kind: CityActionKind, property: CityPropertyState, service offer: CityServiceOffer? = nil) async {
        guard gate(), phase == .ready else { return }
        if let offer { guard kind == .acceptServiceVisit, canAcceptService(offer, on: property) else { return } }
        else { guard actions(for: property).contains(kind) else { return } }
        let target = offer?.serviceId ?? property.propertyId
        notice = nil; lastOutcome = nil
        guard kind.requiresQuote else {
            review = CityGameReview(kind: kind, targetId: target, propertyId: property.propertyId, serviceTitle: nil, quote: nil, expectedVersion: property.stateVersion)
            phase = .review; return
        }
        guard let service else { return }
        let ticket = generation
        phase = .quoting
        do {
            let quote = try await service.quote(kind, targetId: target, read: read)
            guard ticket == generation, gate() else { return }
            try quote.validate()
            guard quote.action == kind.rawValue, quote.boardId == read.board.boardId, quote.targetId == target else { throw CityActionIssue.invalid }
            // W20.4/W20.13: the payer is the confirming member; teammates are never charged.
            guard quote.payerMemberId == memberId else { notice = .payerMismatch; phase = .ready; return }
            if let offer, let fee = offer.memberPointsFee, quote.memberPointsCost != fee { throw CityActionIssue.quoteChanged }
            review = CityGameReview(kind: kind, targetId: target, propertyId: property.propertyId, serviceTitle: offer?.title, quote: quote, expectedVersion: property.stateVersion)
            phase = .review
        } catch {
            guard ticket == generation, gate() else { return }
            notice = .invalidQuote; phase = .ready
        }
    }

    /// Insufficient balance never sends; zero-point players keep neutral/free choices.
    public var reviewAffordable: Bool {
        guard let review else { return false }
        guard let quote = review.quote else { return true }
        guard let points = snapshot?.memberPoints else { return false }
        return points >= quote.memberPointsCost
    }

    public func cancelReview() {
        guard phase == .review else { return }
        review = nil; phase = .ready
    }

    public func confirm() async {
        guard gate(), phase == .review, let review, let snapshot, let roundSeq = snapshot.roundSeq else { return }
        guard reviewAffordable else { notice = .insufficientPoints; return }
        let intent: CityActionIntent
        do {
            var consent: CityPayerConsent?
            if let quote = review.quote {
                consent = try CityPayerConsent(quote: quote, confirmingMemberId: memberId, confirmed: true, deviceNow: now(), serverOffset: serverOffset())
            }
            intent = try CityActionIntent(kind: review.kind, board: read.board, lifecycle: snapshot.lifecycle, participation: read.participation,
                                          targetId: review.targetId, roundSeq: roundSeq, expectedVersion: review.expectedVersion, consent: consent)
            try pending.begin(intent, capabilities: capabilities)
        } catch let issue as CityActionIssue {
            self.review = nil; phase = .ready
            switch issue {
            case .quoteExpired: notice = .quoteExpired
            case .payerMismatch: notice = .payerMismatch
            case .busy: notice = .busy
            case .boardNotOpen: notice = .boardNotOpen
            case .notJoined: notice = .notJoined
            default: notice = .invalidQuote
            }
            return
        } catch { self.review = nil; phase = .ready; notice = .invalidQuote; return }
        self.review = nil
        await send(intent)
    }

    /// Re-sends the identical pending intent (same requestId and body).
    public func retryExact() async {
        guard gate(), canRetryExact, let intent = pending.intent else { return }
        await send(intent)
    }

    private func send(_ intent: CityActionIntent) async {
        guard let service else { return }
        let ticket = generation
        phase = .sending; notice = nil
        do {
            let receipt = try await service.submit(intent)
            guard ticket == generation, gate() else { return }
            try settle(receipt)
        } catch {
            guard ticket == generation, gate() else { return }
            notice = .unknownOutcome; phase = .unknown; return
        }
        await load()
    }

    /// Reads the receipt for the pending requestId; a missing receipt keeps it unknown.
    public func readBack() async {
        guard gate(), phase == .unknown, let service, let intent = pending.intent else { return }
        let ticket = generation
        phase = .sending
        do {
            let receipt = try await service.receipt(for: intent)
            guard ticket == generation, gate() else { return }
            guard let receipt else { notice = .noReceiptYet; phase = .unknown; return }
            try settle(receipt)
        } catch {
            guard ticket == generation, gate() else { return }
            notice = .unknownOutcome; phase = .unknown; return
        }
        await load()
    }

    private func settle(_ receipt: CityActionReceipt) throws {
        let outcome = try pending.resolve(receipt)
        lastOutcome = outcome
        if outcome == .unknown { throw CityActionIssue.receiptMismatch }
        phase = .idle
    }
}
