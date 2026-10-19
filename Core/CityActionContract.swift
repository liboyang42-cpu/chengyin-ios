import Foundation

/// Reform plan v9 §29–35 / W20 resident CITY business game, write side. The read
/// surface (`CityPlayerReader`, `api/city-game/{current,participation,points}`) is
/// untouched. Proposed operations (RollCityRound, AcceptCityTask, SubmitCityEvidence,
/// QuoteCityAction, AcquireProperty, AcceptServiceVisit, CompleteServiceVisit,
/// StartCityChallenge, GetActionReceipt) are not reviewed endpoints, so this file only
/// builds and validates bodies and reconciles receipts. It performs no I/O.
///
/// Invariants carried from the plan: existing member points only (no city currency,
/// no team wallet); the payer is explicit and is always the confirming member (never a
/// teammate); round numbers come from the server; a retry keeps the SAME requestId and
/// never re-rolls, re-prices or re-spends; a lost property keeps the finished task.
/// No cost, reward, dice, protection or action-budget value is defined on the client.
public enum CityActionIssue: Error, Equatable {
    case disabled, invalid, boardNotOpen, notJoined, payerMismatch, quoteExpired, quoteChanged, unconfirmed
    case busy, receiptMismatch, illegalTransition
}

public enum CityBoardLifecycle: String, Decodable, Sendable {
    case draft = "DRAFT", review = "REVIEW", ready = "READY", open = "OPEN", frozen = "FROZEN", closing = "CLOSING", closed = "CLOSED", archived = "ARCHIVED"
    /// Only an OPEN board accepts new player actions; FROZEN/CLOSING settle in-flight work only.
    public var acceptsNewActions: Bool { self == .open }
}

public enum CityActionKind: String, Sendable {
    case roll = "ROLL_ROUND", acceptTask = "ACCEPT_TASK", submitEvidence = "SUBMIT_EVIDENCE", acquireProperty = "ACQUIRE_PROPERTY"
    case acceptServiceVisit = "ACCEPT_SERVICE_VISIT", completeServiceVisit = "COMPLETE_SERVICE_VISIT", startChallenge = "START_CHALLENGE"
    /// Actions that may spend member points and therefore need a quote and explicit payer consent.
    public var requiresQuote: Bool { [.acquireProperty, .acceptServiceVisit, .startChallenge].contains(self) }
}

/// Server quote for a paid action. Points are the member's existing points balance.
public struct CityActionQuote: Decodable, Equatable, Sendable {
    public let quoteId: String
    public let quoteVersion: Int64
    public let action: String
    public let boardId, targetId, payerMemberId, ruleVersion: String
    public let memberPointsCost: Int64
    public let actionCost: Int
    public let beneficiaryMemberIds: [String]
    public let expiresAtMillis: Int64
    public func validate() throws {
        guard [quoteId, boardId, targetId, payerMemberId].allSatisfy(ReformWire.id), ReformWire.version(quoteVersion), ReformWire.label(ruleVersion, limit: 64),
              let kind = CityActionKind(rawValue: action), kind.requiresQuote, memberPointsCost >= 0, actionCost >= 0,
              beneficiaryMemberIds.count <= 16, beneficiaryMemberIds.allSatisfy(ReformWire.id), Set(beneficiaryMemberIds).count == beneficiaryMemberIds.count,
              expiresAtMillis > 0 else { throw CityActionIssue.invalid }
    }
}

/// The confirming member's explicit consent to exactly one quote version.
public struct CityPayerConsent: Equatable, Sendable {
    public let quoteId: String
    public let quoteVersion: Int64
    public let payerMemberId: String
    public init(quote: CityActionQuote, confirmingMemberId: String, confirmed: Bool, deviceNow: Date, serverOffset: TimeInterval) throws {
        try quote.validate()
        guard confirmed else { throw CityActionIssue.unconfirmed }
        // W20.4/W20.13: no deduction from a teammate; the payer must be the person confirming.
        guard quote.payerMemberId == confirmingMemberId else { throw CityActionIssue.payerMismatch }
        guard deviceNow.addingTimeInterval(serverOffset).timeIntervalSince1970 * 1000 < Double(quote.expiresAtMillis) else { throw CityActionIssue.quoteExpired }
        quoteId = quote.quoteId; quoteVersion = quote.quoteVersion; payerMemberId = confirmingMemberId
    }
}

public struct CityActionIntent: Equatable, Sendable {
    public let kind: CityActionKind
    public let boardId, participationId, targetId, requestId: String
    /// Server-assigned round; the client never increments it.
    public let roundSeq: Int64
    public let expectedVersion: Int64
    public let consent: CityPayerConsent?
    public init(kind: CityActionKind, board: CityReadBoard, lifecycle: CityBoardLifecycle, participation: CityParticipation?, targetId: String, roundSeq: Int64, expectedVersion: Int64, consent: CityPayerConsent?, requestId: String = UUID().uuidString) throws {
        guard lifecycle.acceptsNewActions, board.lifecycle == "OPEN" else { throw CityActionIssue.boardNotOpen }
        guard let participation else { throw CityActionIssue.notJoined }
        guard ReformWire.id(targetId), ReformWire.version(roundSeq), ReformWire.version(expectedVersion), ReformWire.requestID(requestId) else { throw CityActionIssue.invalid }
        if kind.requiresQuote { guard consent != nil else { throw CityActionIssue.unconfirmed } }
        else if consent != nil { throw CityActionIssue.invalid }
        self.kind = kind; boardId = board.boardId; participationId = participation.participationId; self.targetId = targetId
        self.requestId = requestId; self.roundSeq = roundSeq; self.expectedVersion = expectedVersion; self.consent = consent
    }
    /// Canonical body. Never contains cost, reward, dice value or a client-computed outcome.
    public func body() throws -> Data {
        var object: [String: Any] = ["action": kind.rawValue, "boardId": boardId, "participationId": participationId, "targetId": targetId,
                                     "roundSeq": roundSeq, "expectedVersion": expectedVersion, "requestId": requestId]
        if let consent { object["quoteId"] = consent.quoteId; object["quoteVersion"] = consent.quoteVersion; object["payerMemberId"] = consent.payerMemberId }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

public struct CityActionReceipt: Decodable, Equatable, Sendable {
    public enum Decision: String, Decodable, Sendable {
        case applied = "APPLIED", rejected = "REJECTED", versionConflict = "VERSION_CONFLICT", quoteChanged = "QUOTE_CHANGED"
        /// The business effect already happened under another request (W20.12); show it, do not repeat.
        case effectAlreadyApplied = "EFFECT_ALREADY_APPLIED"
        /// Merchant pause / safety overlay / frozen board: no new action.
        case blocked = "BLOCKED"
    }
    public let requestId, boardId, action: String
    public let decision: Decision
    public let currentVersion: Int64
    public let reasonCode: String?
    /// W20 conflict rule: a completed task attempt is kept even if the property changed hands.
    public let taskAttemptKept: Bool
    public func validate(for intent: CityActionIntent) throws {
        guard requestId == intent.requestId, boardId == intent.boardId, action == intent.kind.rawValue, ReformWire.version(currentVersion) else { throw CityActionIssue.receiptMismatch }
        if let reasonCode { guard ReformWire.label(reasonCode, limit: 64) else { throw CityActionIssue.receiptMismatch } }
        switch decision {
        case .applied: guard currentVersion > intent.expectedVersion, reasonCode == nil else { throw CityActionIssue.receiptMismatch }
        case .versionConflict: guard currentVersion != intent.expectedVersion else { throw CityActionIssue.receiptMismatch }
        case .quoteChanged: guard intent.consent != nil else { throw CityActionIssue.receiptMismatch }
        case .rejected, .blocked, .effectAlreadyApplied: guard reasonCode != nil else { throw CityActionIssue.receiptMismatch }
        }
    }
}

/// One in-flight CITY action per participation. Unknown results are read back by
/// requestId; the same business intent is never re-sent under a new requestId.
public struct CityPendingAction: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case applied(version: Int64)
        case alreadyApplied
        /// Refresh snapshot, show current options; a kept task attempt is preserved.
        case refresh(taskAttemptKept: Bool)
        /// New quote needed; never auto-accept a changed price.
        case requote
        case rejected(String)
        case blocked(String)
        case unknown
    }
    public private(set) var intent: CityActionIntent?
    public init() {}
    public mutating func begin(_ next: CityActionIntent, capabilities: ReformWorldCapabilities) throws {
        guard capabilities.allows(.cityActions) else { throw CityActionIssue.disabled }
        if let intent { guard intent == next else { throw CityActionIssue.busy }; return } // exact retry only.
        intent = next
    }
    public mutating func resolve(_ receipt: CityActionReceipt?) throws -> Outcome {
        guard let current = intent else { throw CityActionIssue.illegalTransition }
        guard let receipt else { return .unknown }
        try receipt.validate(for: current)
        intent = nil
        switch receipt.decision {
        case .applied: return .applied(version: receipt.currentVersion)
        case .effectAlreadyApplied: return .alreadyApplied
        case .versionConflict: return .refresh(taskAttemptKept: receipt.taskAttemptKept)
        case .quoteChanged: return .requote
        case .rejected: return .rejected(receipt.reasonCode ?? "")
        case .blocked: return .blocked(receipt.reasonCode ?? "")
        }
    }
}

/// W20.14 asynchronous challenge. The defender is never required to be online.
public enum CityChallengeState: String, Decodable, Sendable {
    case offered = "OFFERED", accepted = "ACCEPTED", evidenceReady = "EVIDENCE_READY", resolved = "RESOLVED"
    case cancelled = "CANCELLED", expired = "EXPIRED", suspended = "SUSPENDED"
    public var isTerminal: Bool { [.resolved, .cancelled, .expired].contains(self) }
    public func canAdvance(to next: CityChallengeState) -> Bool {
        switch (self, next) {
        case (.offered, .accepted), (.accepted, .evidenceReady), (.evidenceReady, .resolved): return true
        case (.suspended, .accepted), (.suspended, .evidenceReady): return true
        case (let from, .cancelled), (let from, .expired), (let from, .suspended): return !from.isTerminal && from != next
        default: return false
        }
    }
}
