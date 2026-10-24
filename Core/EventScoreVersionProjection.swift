import Foundation

/// Start payload for ordinary city orienteering. The frozen rule version is copied
/// onto `resultVersionID` so finish and dispute cannot silently follow a later publish.
/// Missing `originalRequestID` stays Optional.none, never "".
public struct EventScoreStartPayload: Equatable, Sendable {
    public let courseID: Int
    public let frozenRuleVersionID: String
    public let resultVersionID: String
    public let safetyVersionID: String
    public let originalRequestID: String?
}

public struct EventScoreTerminalAction: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case finish, dispute }
    public let kind: Kind
    public let courseID: Int
    public let resultVersionID: String
    public let originalRequestID: String?
}

/// Untrusted wire values stay Optional.none. Never coerce to "" or [].
public enum EventScoreRequestIdentity {
    public static func parse(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == raw else { return nil }
        let count = trimmed.utf8.count
        guard count >= 8, count <= 64 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.:-"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }
}

public enum EventScoreOriginalOutcome: String, Equatable, Sendable {
    case running = "RUNNING"
    case finished = "FINISHED"
    case unknown = "UNKNOWN"
    case notFound = "NOT_FOUND"
    case invalidArgument = "EVENT_INVALID_ARGUMENT"
    case idempotencyConflict = "EVENT_IDEMPOTENCY_CONFLICT"
}

public struct EventScoreOriginalReceipt: Equatable, Sendable {
    public let originalRequestID: String?
    public let outcome: EventScoreOriginalOutcome
    public let mintedNewRequest: Bool
    public let start: EventScoreStartPayload?
    public let terminal: EventScoreTerminalAction?
}

/// Event score version identity. Not Growth personal rank and not a live republish.
public enum EventScoreVersionProjection {
    public static let gpsEvidenceKinds: Set<String> = ["GPS", "LAT", "LNG", "LATLNG", "COORDINATE", "LOCATION"]
    public static func freeze(
        selection: OrdinaryCityCourseSelection, safety: OrienteeringSafetyVersion
    ) -> EventScoreStartPayload? {
        freeze(selection: selection, safety: safety, originalRequestID: nil)
    }
    public static func freeze(
        selection: OrdinaryCityCourseSelection, safety: OrienteeringSafetyVersion,
        originalRequestID: String?
    ) -> EventScoreStartPayload? {
        guard safety.matches(selection),
              OrdinaryCityCourseSelector.versionOK(selection.publishedRuleVersionID) else { return nil }
        return EventScoreStartPayload(
            courseID: selection.courseID,
            frozenRuleVersionID: selection.publishedRuleVersionID,
            resultVersionID: selection.publishedRuleVersionID,
            safetyVersionID: selection.safetyVersionID,
            originalRequestID: EventScoreRequestIdentity.parse(originalRequestID))
    }
    public static func finish(
        start: EventScoreStartPayload, resultVersionID: String
    ) -> EventScoreTerminalAction? {
        terminal(.finish, start: start, resultVersionID: resultVersionID, originalRequestID: nil)
    }
    public static func dispute(
        start: EventScoreStartPayload, resultVersionID: String
    ) -> EventScoreTerminalAction? {
        terminal(.dispute, start: start, resultVersionID: resultVersionID, originalRequestID: nil)
    }
    /// A later published rule id cannot rewrite an already frozen start.
    public static func retainsFrozenRule(
        start: EventScoreStartPayload, laterPublishedRuleVersionID: String
    ) -> Bool {
        start.frozenRuleVersionID == start.resultVersionID
            && start.frozenRuleVersionID != laterPublishedRuleVersionID
    }
    /// GPS evidence is never accepted as task proof. Catalog GPS is already unselectable.
    public static func rejectsGPSEvidence(kind: String?, fingerprint: String?) -> Bool {
        let token = (kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if gpsEvidenceKinds.contains(token) { return true }
        let text = (fingerprint ?? "").lowercased()
        return text.contains("\"lat\"") || text.contains("\"lng\"")
            || text.contains("\"latitude\"") || text.contains("\"longitude\"")
            || text.contains("gps=")
    }
    /// Growth personal rank never substitutes an event-score finish.
    public static func growthLeaderboardSubstitutesEventScore(_ rank: Int?) -> Bool {
        _ = rank
        return false
    }
    private static func terminal(
        _ kind: EventScoreTerminalAction.Kind, start: EventScoreStartPayload, resultVersionID: String,
        originalRequestID: String?
    ) -> EventScoreTerminalAction? {
        guard OrdinaryCityCourseSelector.versionOK(resultVersionID),
              resultVersionID == start.resultVersionID,
              resultVersionID == start.frozenRuleVersionID,
              start.courseID > 0 else { return nil }
        return EventScoreTerminalAction(
            kind: kind, courseID: start.courseID, resultVersionID: resultVersionID,
            originalRequestID: EventScoreRequestIdentity.parse(originalRequestID))
    }
}

/// In-process original freeze/finish ledger. Another TEAM/register/finish request cannot
/// rewrite the original keys; recover keeps FINISHED / NOT_FOUND unknown and does not mint empty ids.
public struct EventScoreOriginalLedger: Equatable {
    private struct Run: Equatable {
        var startRequestID: String
        var payload: EventScoreStartPayload
        var finishRequestID: String?
        var terminal: EventScoreTerminalAction?
        var outcome: EventScoreOriginalOutcome
    }
    private var runsByStartID: [String: Run] = [:]
    private var finishToStart: [String: String] = [:]

    public init() {}

    public mutating func freeze(
        selection: OrdinaryCityCourseSelection, safety: OrienteeringSafetyVersion,
        originalRequestID: String?
    ) -> EventScoreOriginalReceipt {
        guard let id = EventScoreRequestIdentity.parse(originalRequestID) else {
            return Self.blank(.invalidArgument)
        }
        guard let payload = EventScoreVersionProjection.freeze(
            selection: selection, safety: safety, originalRequestID: id) else {
            return EventScoreOriginalReceipt(
                originalRequestID: id, outcome: .invalidArgument, mintedNewRequest: false,
                start: nil, terminal: nil)
        }
        if var existing = runsByStartID[id] {
            if existing.payload.courseID != payload.courseID
                || existing.payload.frozenRuleVersionID != payload.frozenRuleVersionID
                || existing.payload.resultVersionID != payload.resultVersionID
                || existing.payload.safetyVersionID != payload.safetyVersionID {
                return receipt(existing, requestID: id, outcome: .idempotencyConflict)
            }
            existing.payload = payload
            runsByStartID[id] = existing
            return receipt(existing, requestID: id, outcome: existing.outcome)
        }
        let run = Run(startRequestID: id, payload: payload, finishRequestID: nil,
                      terminal: nil, outcome: .running)
        runsByStartID[id] = run
        return receipt(run, requestID: id, outcome: .running)
    }

    public mutating func finish(
        start: EventScoreStartPayload, resultVersionID: String, originalRequestID: String?
    ) -> EventScoreOriginalReceipt {
        guard let finishID = EventScoreRequestIdentity.parse(originalRequestID) else {
            return Self.blank(.invalidArgument)
        }
        guard let action = EventScoreVersionProjection.finish(start: start, resultVersionID: resultVersionID)
        else {
            return EventScoreOriginalReceipt(
                originalRequestID: finishID, outcome: .invalidArgument, mintedNewRequest: false,
                start: start, terminal: nil)
        }
        if let boundStart = finishToStart[finishID], let existing = runsByStartID[boundStart] {
            if existing.startRequestID == start.originalRequestID {
                return receipt(existing, requestID: finishID, outcome: .finished)
            }
            if let original = runMatching(start), let already = original.finishRequestID {
                return receipt(original, requestID: already, outcome: .idempotencyConflict)
            }
            return receipt(existing, requestID: existing.finishRequestID ?? boundStart,
                           outcome: .idempotencyConflict)
        }
        guard var run = runMatching(start) else {
            return EventScoreOriginalReceipt(
                originalRequestID: finishID, outcome: .notFound, mintedNewRequest: false,
                start: start, terminal: nil)
        }
        if let already = run.finishRequestID, already != finishID {
            return receipt(run, requestID: already, outcome: .idempotencyConflict)
        }
        let bound = EventScoreTerminalAction(
            kind: action.kind, courseID: action.courseID,
            resultVersionID: action.resultVersionID, originalRequestID: finishID)
        run.finishRequestID = finishID
        run.terminal = bound
        run.outcome = .finished
        runsByStartID[run.startRequestID] = run
        finishToStart[finishID] = run.startRequestID
        return receipt(run, requestID: finishID, outcome: .finished)
    }

    public func recoverOriginal(originalRequestID: String?) -> EventScoreOriginalReceipt {
        recoverUnknown(originalRequestID: originalRequestID)
    }

    /// In-process recover. FINISHED stays FINISHED; missing originals stay typed NOT_FOUND
    /// unknown. Never mints an empty id.
    public func recoverUnknown(originalRequestID: String?) -> EventScoreOriginalReceipt {
        guard let id = EventScoreRequestIdentity.parse(originalRequestID) else {
            return Self.blank(.notFound)
        }
        if let startID = finishToStart[id], let run = runsByStartID[startID] {
            return receipt(run, requestID: id, outcome: run.outcome == .finished ? .finished : .unknown)
        }
        if let run = runsByStartID[id] {
            if run.outcome == .finished, let finishID = run.finishRequestID {
                return receipt(run, requestID: finishID, outcome: .finished)
            }
            return receipt(run, requestID: id, outcome: .unknown)
        }
        return EventScoreOriginalReceipt(
            originalRequestID: id, outcome: .notFound, mintedNewRequest: false,
            start: nil, terminal: nil)
    }

    public func readback(_ originalRequestID: String?) -> EventScoreOriginalReceipt {
        recoverUnknown(originalRequestID: originalRequestID)
    }

    public static let originalRewardRead = "orientation.originalRewardRead"
    public static let scoringReceipt = "orientScoring.receipt"
    public static let sessionReceipt = "orientSession.receipt"
    public static let sessionReceiptNotFound = "ORIENT_RECEIPT_NOT_FOUND"

    public indirect enum Wire: Equatable, Sendable {
        case null
        case bool(Bool)
        case int(Int64)
        case string(String)
        case array([Wire])
        case object([String: Wire])
    }

    public enum WireFailure: Error, Equatable {
        case waitingSource(String)
        case notFound(String)
        case transport(String)
        case forbidden(String)
    }
    public static let receiptKinds: Set<String> = ["SETTLE", "APPEAL", "DISPUTE"]
    public struct WaitingSource: Error, Equatable {
        public let capability: String
    }

    /// Read-only original reward facts. Caller supplies member/session and the existing
    /// read closure. Missing source is WAITING_SOURCE. Never-seen returns nil and does
    /// not occupy freeze/finish keys. Does not copy a private reward writer.
    public func recoverFromOriginalRewardRead(
        memberID: Int64?,
        sessionID: Int64?,
        read: ((Int64, Int64) async throws -> Wire)?
    ) async throws -> Wire? {
        guard let memberID, memberID > 0, let sessionID, sessionID > 0 else { return nil }
        guard let read else {
            throw WireFailure.waitingSource(Self.originalRewardRead)
        }
        return try await read(memberID, sessionID)
    }

    /// Read IOrientScoringService.receipt. Kind must be SETTLE, APPEAL, or DISPUTE.
    /// NOT_FOUND is returned as-is. A settlement or appeal for another session is nil.
    /// Nil is only an unusable identity, not a NOT_FOUND receipt. Does not append.
    public func recoverFromScoringReceipt(
        memberID: Int64?,
        kind: String?,
        sessionID: Int64?,
        idempotencyKey: String?,
        receipt: ((Int64, String, Int64, String) async throws -> Wire)?
    ) async throws -> Wire? {
        guard let memberID, memberID > 0, let sessionID, sessionID > 0,
              let key = EventScoreRequestIdentity.parse(idempotencyKey),
              let kind, Self.receiptKinds.contains(kind) else { return nil }
        guard let receipt else {
            throw WireFailure.waitingSource(Self.scoringReceipt)
        }
        let found = try await receipt(memberID, kind, sessionID, key)
        if Self.wireString(found, "state") == "NOT_FOUND" { return found }
        if kind == "SETTLE" {
            guard Self.wireInt(found, "sessionId") == sessionID else { return nil }
        }
        if kind == "APPEAL" || kind == "DISPUTE" {
            guard case .object(let fields) = found, let record = fields["record"],
                  Self.wireInt(record, "sessionId") == sessionID else { return nil }
        }
        return found
    }

    private static func wireString(_ wire: Wire, _ key: String) -> String? {
        guard case .object(let fields) = wire, case .string(let value) = fields[key] else { return nil }
        return value
    }

    private static func wireInt(_ wire: Wire, _ key: String) -> Int64? {
        guard case .object(let fields) = wire, case .int(let value) = fields[key] else { return nil }
        return value
    }

    /// Read IOrientSessionService.receipt. Numbers, null, and bool stay on the Wire.
    /// Not-found and transport errors stay thrown. Does not start or abandon the session.
    public func recoverFromSessionReceipt(
        memberID: Int64?,
        sessionID: Int64?,
        idempotencyKey: String?,
        receipt: ((Int64, Int64, String) async throws -> Wire)?
    ) async throws -> Wire? {
        guard let memberID, memberID > 0, let sessionID, sessionID > 0,
              let key = EventScoreRequestIdentity.parse(idempotencyKey) else { return nil }
        guard let receipt else {
            throw WireFailure.waitingSource(Self.sessionReceipt)
        }
        return try await receipt(memberID, sessionID, key)
    }

    private func runMatching(_ start: EventScoreStartPayload) -> Run? {
        if let id = start.originalRequestID, let run = runsByStartID[id] { return run }
        return runsByStartID.values.first(where: {
            $0.payload.courseID == start.courseID
                && $0.payload.frozenRuleVersionID == start.frozenRuleVersionID
                && $0.payload.resultVersionID == start.resultVersionID
        })
    }

    private func receipt(
        _ run: Run, requestID: String, outcome: EventScoreOriginalOutcome
    ) -> EventScoreOriginalReceipt {
        EventScoreOriginalReceipt(
            originalRequestID: requestID, outcome: outcome, mintedNewRequest: false,
            start: run.payload, terminal: run.terminal)
    }

    private static func blank(_ outcome: EventScoreOriginalOutcome) -> EventScoreOriginalReceipt {
        EventScoreOriginalReceipt(
            originalRequestID: nil, outcome: outcome, mintedNewRequest: false,
            start: nil, terminal: nil)
    }
}
