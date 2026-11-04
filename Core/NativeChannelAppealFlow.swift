import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Display facts from the already actor/scope-validated original moderation row.
/// No field here grants appeal rights or infers that a sanction has expired.
public struct NativeChannelActionFacts: Equatable {
    public let type: String?, status: String?, reasonCode: String?
    public let scopeType: String?, scopeID: String?
    public let startsAt: String?, expiresAt: String?
    public let durationSeconds: Int64?
    public init(source: [String: Any]) {
        func text(_ key: String) -> String? {
            guard let value = source[key] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        type = text("action_type"); status = text("status"); reasonCode = text("reason_code")
        scopeType = text("scope_type"); scopeID = NativeChannelGovernanceNotice.positive(source["scope_id"])
        startsAt = text("starts_at"); expiresAt = text("expires_at")
        let seconds = NativeChannelGovernanceNotice.integer(source["duration_sec"])
        durationSeconds = seconds.map({ $0 >= 0 }) == true ? seconds : nil
    }
}

@MainActor @Observable public final class NativeChannelAppealFlow {
    public enum State: Equatable { case idle, loading, ready, reviewing, submitting, unknown, applied, unavailable }
    public enum Operation: String, Codable { case submit, evidence, withdraw }
    public let notice: NativeChannelGovernanceNotice
    public private(set) var state: State = .idle
    public private(set) var actionReason = ""
    public private(set) var actionFacts: NativeChannelActionFacts?
    public private(set) var actionFactsUnavailable = false
    public private(set) var appealStatus = ""
    private var storedAppealDetails: NativeChannelAppealDetails?
    public var appealDetails: NativeChannelAppealDetails? { isCurrent && currentReady && pending == nil ? storedAppealDetails : nil }
    public private(set) var decisionReason = ""
    public private(set) var deadline = ""
    public private(set) var requestID: String?
    public private(set) var reviewedText = ""
    public private(set) var reviewedOperation: Operation?
    private var appealID: String?
    private var currentReady = false
    public private(set) var currentReadFailed = false
    public private(set) var readingCurrent = false
    /// A locator is not a pending operation or proof of the current appeal state.
    public private(set) var locatorUnavailable = false
    private var canAppeal = false
    private var canAddEvidence = false
    private var active = false
    // A returning visit must not re-admit a response started before deactivation.
    private var visitID = UUID()
    private var refreshAfterFlight = false
    private var busy = false
    private var storageFailed = false
    private var pending: Record?
    private var review: Record?
    @ObservationIgnored private let context: RuntimeDependencyContext
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let storage: any ProjectEditDataStorage
    @ObservationIgnored private let locatorStorage: (any ProjectEditDataStorage)?
    @ObservationIgnored private let current: () -> Bool
    @ObservationIgnored private let permits: (String, String) -> Bool
    @ObservationIgnored private let unauthorized: () -> Void
    @ObservationIgnored private let makeRequestID: () -> UUID
    @ObservationIgnored private let runtimeAuthorization: NativeChannelAppealRuntimeAuthorization?
    private static var leases: Set<String> = []
    private final class ReadWaiter {
        weak var flow: NativeChannelAppealFlow?
        let visit: UUID
        init(flow: NativeChannelAppealFlow, visit: UUID) { self.flow = flow; self.visit = visit }
    }
    private static var readWaiters: [String: [ReadWaiter]] = [:]
    private struct Record: Codable, Equatable {
        let version: Int
        let owner: String
        let actionID: String
        let operation: Operation
        let requestID: String
        let path: String
        let body: Data
    }
    private struct Locator: Codable, Equatable {
        let version: Int
        let owner: String
        let actionID: String
        let appealID: String
    }
    private var locatorKey: String { "channel-appeal-locator.v1." + Data((owner + ":" + notice.actionID).utf8).base64EncodedString() }
    private var owner: String { [context.session.namespace, context.baseURL.absoluteString, String(context.session.accountID), String(notice.guildKind), notice.guildID].map { "\($0.utf8.count):\($0)" }.joined() }
    private var key: String { "channel-appeal.v1." + Data((owner + ":" + notice.actionID).utf8).base64EncodedString() }
    public var isCurrent: Bool { active && current() }
    public var hasPending: Bool { pending != nil }
    public var journalUnavailable: Bool { storageFailed }
    public var canSubmit: Bool { isCurrent && currentReady && !busy && !storageFailed && pending == nil && canAppeal && permits("POST", "api/im/appeals") }
    public var canSupplement: Bool { isCurrent && currentReady && !busy && pending == nil && !storageFailed && canAddEvidence && appealID.map { permits("POST", "api/im/appeals/\($0)/evidence") } == true }
    public var canWithdraw: Bool { isCurrent && currentReady && !busy && pending == nil && !storageFailed && ["PENDING", "REVIEWING"].contains(appealStatus) && appealID.map { permits("POST", "api/im/appeals/\($0)/withdraw") } == true }
    public var canRecover: Bool { isCurrent && !busy && !storageFailed && pending.map { permits("GET", receiptPath($0.requestID)) } == true }
    public var canRetry: Bool { canRecover && pending.map { permits("POST", $0.path) } == true }
    public init(notice: NativeChannelGovernanceNotice, context: RuntimeDependencyContext, transport: any HTTPTransport,
                storage: any ProjectEditDataStorage, current: @escaping () -> Bool,
                permits: @escaping (String, String) -> Bool, unauthorized: @escaping () -> Void, makeRequestID: @escaping () -> UUID = { UUID() },
                locatorStorage: (any ProjectEditDataStorage)? = nil, runtimeAuthorization: NativeChannelAppealRuntimeAuthorization? = nil) throws {
        guard notice.recipientID == context.session.accountID, [1,2,3].contains(notice.guildKind),
              NativeChannelGovernanceNotice.positive(notice.actionID) != nil,
              NativeChannelGovernanceNotice.positive(notice.guildID) != nil else { throw APIError.invalidRequest }
        self.notice = notice; self.context = context; self.transport = transport; self.storage = storage
        self.locatorStorage = locatorStorage; self.runtimeAuthorization = runtimeAuthorization
        self.current = current; self.permits = permits; self.unauthorized = unauthorized; self.makeRequestID = makeRequestID
        do { pending = try restore(); requestID = pending?.requestID; if pending != nil { state = .unknown } }
        catch { storageFailed = true; state = .unavailable }
    }
    public func deactivate() {
        visitID = UUID(); refreshAfterFlight = false
        active = false; currentReady = false; currentReadFailed = false; readingCurrent = false; canAppeal = false; canAddEvidence = false; review = nil; reviewedText = ""; reviewedOperation = nil
        actionReason = ""; actionFacts = nil; actionFactsUnavailable = false
        storedAppealDetails = nil; decisionReason = ""; appealStatus = ""; deadline = ""; state = .unavailable
    }
    public func activate() async {
        guard !active else { return }
        visitID = UUID(); active = true
        if busy { refreshAfterFlight = true; return }
        await refresh()
    }
    private func matchesVisit(_ visit: UUID) -> Bool { isCurrent && visitID == visit }
    private func finishFlight() {
        busy = false; Self.leases.remove(key)
        let waiters = Self.readWaiters.removeValue(forKey: key) ?? []
        for waiter in waiters {
            Task { @MainActor in
                guard let flow = waiter.flow, flow.matchesVisit(waiter.visit) else { return }
                await flow.refresh()
            }
        }
        guard refreshAfterFlight else { return }
        refreshAfterFlight = false
        let visit = visitID
        guard matchesVisit(visit) else { return }
        Task { [weak self] in
            guard let self, self.matchesVisit(visit) else { return }
            await self.refresh()
        }
    }
    public func refresh() async {
        guard isCurrent, !busy else { return }
        let visit = visitID
        guard Self.leases.insert(key).inserted else {
            var waiters = Self.readWaiters[key] ?? []
            waiters.removeAll { $0.flow == nil || $0.flow === self }
            waiters.append(ReadWaiter(flow: self, visit: visit))
            Self.readWaiters[key] = waiters
            return
        }
        busy = true; defer { finishFlight() }
        // A refresh invalidates the unsent review even if the new read later fails.
        review = nil; reviewedText = ""; reviewedOperation = nil
        do {
            let restored = try restore()
            // Losing/changing the durable copy is not proof that a known request settled.
            // Keep its identity fenced until the same original can be read back again.
            guard pending == nil || restored == pending else { throw APIError.malformedResponse }
            pending = restored; requestID = pending?.requestID; storageFailed = false
        } catch {
            guard matchesVisit(visit) else { return }
            storageFailed = true; currentReady = false
            state = pending == nil ? .unavailable : .unknown
            return
        }
        do {
            if let original = pending {
                state = .unknown
                guard issueOriginal(original, recovering: true) else { throw APIError.notConfigured }
                let receipt = try await exchange("GET", receiptPath(original.requestID))
                if receipt["state"] as? String == "APPLIED", let result = receipt["result"] as? [String: Any] { try await settle(original, result) }
                return
            }
            await readCurrent(afterApplied: state == .applied)
        } catch { if matchesVisit(visit) { currentReady = false; state = pending == nil ? .unavailable : .unknown } }
    }
    /// Current eligibility is read independently; an immutable request result is not a grant.
    private func readCurrent(afterApplied: Bool) async {
        let visit = visitID
        currentReady = false; currentReadFailed = false; readingCurrent = true
        canAppeal = false; canAddEvidence = false
        actionReason = ""; actionFacts = nil; actionFactsUnavailable = false
        storedAppealDetails = nil; decisionReason = ""; appealStatus = ""; deadline = ""
        if !afterApplied { state = .loading }
        defer { if visitID == visit { readingCurrent = false } }
        do {
            // A completed appeal remains addressable when moderation/me no longer lists its action.
            // Neither this protected locator nor a notice hint is authority or a current snapshot.
            let locatedID = appealID ?? restoreLocator() ?? NativeChannelGovernanceNotice.positive(notice.appealIDHint)
            if let locatedID {
                let currentAppeal = try await exchange("GET", "api/im/appeals/" + locatedID)
                try accept(currentAppeal, expectedID: locatedID)
                storedAppealDetails = NativeChannelAppealDetails(source: currentAppeal)
                guard matchesVisit(visit), !Task.isCancelled else { throw APIError.unauthorized }
                // Current sanction details are a separate read, not the appeal receipt.
                // Their absence must not turn an acknowledged appeal into a failure.
                await readActionFactsAfterAppeal()
                guard matchesVisit(visit), !Task.isCancelled else { throw APIError.unauthorized }
                currentReady = true; state = afterApplied ? .applied : .ready; return
            }
            if afterApplied { throw APIError.malformedResponse }
            let data = try await exchange("GET", "api/im/moderation/me", query: [URLQueryItem(name: "guild_kind", value: String(notice.guildKind)), URLQueryItem(name: "guild_id", value: notice.guildID)])
            guard let rows = data["list"] as? [[String: Any]], let action = rows.first(where: { NativeChannelGovernanceNotice.positive($0["action_id"]) == notice.actionID }),
                  NativeChannelGovernanceNotice.positive(action["target_member_id"]) == String(context.session.accountID),
                  NativeChannelGovernanceNotice.positive(action["guild_id"]) == notice.guildID,
                  NativeChannelGovernanceNotice.positive(action["guild_kind"]) == String(notice.guildKind) else { throw APIError.malformedResponse }
            actionFacts = .init(source: action)
            actionReason = action["reason_text"] as? String ?? ""; deadline = action["appeal_deadline"] as? String ?? ""
            canAppeal = (action["appealable"] as? NSNumber)?.intValue == 1
            let currentAppealID = NativeChannelGovernanceNotice.positive(action["existing_appeal_id"])
            appealID = currentAppealID
            if let appealID {
                let currentAppeal = try await exchange("GET", "api/im/appeals/" + appealID)
                try accept(currentAppeal)
                storedAppealDetails = NativeChannelAppealDetails(source: currentAppeal)
            }
            guard matchesVisit(visit), !Task.isCancelled else { throw APIError.unauthorized }
            currentReady = true; state = afterApplied ? .applied : .ready
        } catch {
            guard matchesVisit(visit) else { return }
            currentReady = false; canAppeal = false; canAddEvidence = false
            actionReason = ""; actionFacts = nil; actionFactsUnavailable = true
            storedAppealDetails = nil; decisionReason = ""; appealStatus = ""; deadline = ""
            if isCurrent { currentReadFailed = true; state = afterApplied ? .applied : .unavailable }
        }
    }
    private func readActionFactsAfterAppeal() async {
        let visit = visitID
        do {
            let data = try await exchange("GET", "api/im/moderation/me", query: [URLQueryItem(name: "guild_kind", value: String(notice.guildKind)), URLQueryItem(name: "guild_id", value: notice.guildID)])
            guard let rows = data["list"] as? [[String: Any]],
                  let action = rows.first(where: { NativeChannelGovernanceNotice.positive($0["action_id"]) == notice.actionID }),
                  NativeChannelGovernanceNotice.positive(action["target_member_id"]) == String(context.session.accountID),
                  NativeChannelGovernanceNotice.positive(action["guild_id"]) == notice.guildID,
                  NativeChannelGovernanceNotice.positive(action["guild_kind"]) == String(notice.guildKind),
                  matchesVisit(visit), !Task.isCancelled else { throw APIError.malformedResponse }
            actionFacts = .init(source: action)
            actionReason = action["reason_text"] as? String ?? ""
            deadline = action["appeal_deadline"] as? String ?? ""
            actionFactsUnavailable = false
        } catch {
            guard matchesVisit(visit) else { return }
            actionFacts = nil
            if isCurrent { actionFactsUnavailable = true }
        }
    }
    @discardableResult public func prepare(_ operation: Operation, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf16.count <= 500, pending == nil, review == nil,
              (operation == .submit ? canSubmit : operation == .evidence ? canSupplement : canWithdraw) else { return false }
        let id = makeRequestID().uuidString.lowercased(); var body: [String: Any]; let path: String
        switch operation {
        case .submit:
            path = "api/im/appeals"
            body = ["guild_kind": notice.guildKind, "guild_id": notice.guildID, "action_id": notice.actionID,
                    "reason_code": "MISJUDGE", "reason_text": trimmed, "submit_request_id": id]
        case .evidence:
            guard let appealID else { return false }; path = "api/im/appeals/\(appealID)/evidence"
            body = ["request_id": id, "evidence_json": ["text": trimmed]]
        case .withdraw:
            guard let appealID else { return false }; path = "api/im/appeals/\(appealID)/withdraw"
            body = ["request_id": id, "reason": trimmed]
        }
        guard let bytes = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes]) else { return false }
        review = Record(version: 1, owner: owner, actionID: notice.actionID, operation: operation, requestID: id, path: path, body: bytes)
        reviewedText = trimmed; reviewedOperation = operation; state = .reviewing; return true
    }
    public func cancelReview() {
        guard review != nil else { return }
        review = nil; reviewedText = ""; reviewedOperation = nil
        if isCurrent, currentReady, !busy, pending == nil { state = .ready }
    }
    public func confirm() async {
        guard isCurrent, currentReady, !busy, !storageFailed, state == .reviewing, let original = review, pending == nil,
              (original.operation == .submit ? canSubmit : original.operation == .evidence ? canSupplement : canWithdraw),
              permits("POST", original.path), Self.leases.insert(key).inserted else { return }
        let visit = visitID
        busy = true; defer { finishFlight() }
        // The reviewed source narrows its independent receipt right to this exact request.
        // Missing or revoked approval still fails before any journal write.
        guard issueOriginal(original, recovering: false) else {
            review = nil; reviewedText = ""; reviewedOperation = nil; state = .unavailable; return
        }
        // Admit all three fresh operations only with this review's exact receipt.
        guard permits("GET", receiptPath(original.requestID)) else {
            review = nil; reviewedText = ""; reviewedOperation = nil; state = .unavailable; return
        }
        do {
            guard try restore() == nil else { throw APIError.invalidRequest }
            try storage.write(JSONEncoder().encode(original), key: key)
            guard try restore() == original else { throw APIError.malformedResponse }
            pending = original; requestID = original.requestID; review = nil; state = .submitting
            try await settle(original, try await exchange("POST", original.path, body: original.body, freshReceiptID: original.requestID))
        } catch {
            guard matchesVisit(visit) else { return }
            state = pending == nil ? .unavailable : .unknown
            if pending == nil { storageFailed = true }
        }
    }
    /// Explicit retry first checks the same original receipt; NOT_FOUND alone never auto-sends.
    public func retryOriginal() async {
        guard canRecover, let original = pending, permits("POST", original.path), Self.leases.insert(key).inserted else { return }
        let visit = visitID
        busy = true; defer { finishFlight() }
        do {
            guard try restore() == original else { throw APIError.invalidRequest }
            guard issueOriginal(original, recovering: true) else { throw APIError.notConfigured }
            let receipt = try await exchange("GET", receiptPath(original.requestID))
            if receipt["state"] as? String == "APPLIED", let result = receipt["result"] as? [String: Any] { try await settle(original, result); return }
            guard receipt["state"] as? String == "NOT_FOUND", receipt["retry_with_original_request"] as? Bool == true else { state = .unknown; return }
            state = .submitting; try await settle(original, try await exchange("POST", original.path, body: original.body))
        } catch { if matchesVisit(visit) { state = .unknown } }
    }
    private func accept(_ row: [String: Any], expectedID: String? = nil) throws {
        guard NativeChannelGovernanceNotice.positive(row["action_id"]) == notice.actionID,
              NativeChannelGovernanceNotice.positive(row["appellant_member_id"]) == String(context.session.accountID),
              let id = NativeChannelGovernanceNotice.positive(row["appeal_id"]),
              let status = row["status"] as? String, ["PENDING","REVIEWING","UPHELD","REVERSED","WITHDRAWN"].contains(status) else { throw APIError.malformedResponse }
        if let expected = expectedID ?? appealID, expected != id { throw APIError.malformedResponse }
        appealID = id; appealStatus = status; decisionReason = row["decision_reason"] as? String ?? ""
        runtimeAuthorization?.acceptCurrentAppeal(id)
        canAddEvidence = (row["can_add_evidence"] as? NSNumber)?.intValue == 1; canAppeal = false
        rememberLocator(id)
    }
    private func settle(_ original: Record, _ result: [String: Any]) async throws {
        guard isCurrent, try restore() == original else { throw APIError.invalidRequest }
        guard let returnedRequest = result["request_id"] as? String,
              returnedRequest.utf8.elementsEqual(original.requestID.utf8),
              result["state"] as? String == "APPLIED" else { throw APIError.malformedResponse }
        if original.operation != .submit {
            let parts = original.path.split(separator: "/")
            guard parts.count == 5, NativeChannelGovernanceNotice.positive(result["appeal_id"]) == String(parts[3]) else { throw APIError.malformedResponse }
        }
        if original.operation == .withdraw { guard result["status"] as? String == "WITHDRAWN" else { throw APIError.malformedResponse } }
        currentReady = false
        try accept(result); try storage.remove(key)
        guard try restore() == nil else { throw APIError.malformedResponse }
        pending = nil; requestID = nil; state = .applied
        runtimeAuthorization?.finish(original.requestID)
        await readCurrent(afterApplied: true)
    }
    private func restore() throws -> Record? {
        guard let data = try storage.read(key) else { return nil }
        guard data.count <= 16 * 1024 else { throw APIError.malformedResponse }
        let row = try JSONDecoder().decode(Record.self, from: data)
        let encoded = try JSONEncoder().encode(row)
        guard row.version == 1, row.owner == owner, row.actionID == notice.actionID, UUID(uuidString: row.requestID) != nil,
              row.body.count <= 8192,
              (try JSONSerialization.jsonObject(with: data) as? NSDictionary) == (try JSONSerialization.jsonObject(with: encoded) as? NSDictionary),
              let body = try JSONSerialization.jsonObject(with: row.body) as? [String: Any] else { throw APIError.malformedResponse }
        if row.operation == .submit {
            guard row.path == "api/im/appeals", body["submit_request_id"] as? String == row.requestID,
                  body["action_id"] as? String == notice.actionID, body["guild_id"] as? String == notice.guildID,
                  NativeChannelGovernanceNotice.positive(body["guild_kind"]) == String(notice.guildKind) else { throw APIError.malformedResponse }
        } else {
            let pieces = row.path.split(separator: "/")
            guard pieces.count == 5, pieces[0] == "api", pieces[1] == "im", pieces[2] == "appeals",
                  NativeChannelGovernanceNotice.positive(String(pieces[3])) != nil,
                  pieces[4] == (row.operation == .evidence ? "evidence" : "withdraw"), body["request_id"] as? String == row.requestID else { throw APIError.malformedResponse }
        }
        return row
    }
    /// This side store never shares the pending-record key or its failure flag.
    private func restoreLocator() -> String? {
        guard let locatorStorage else { return nil }
        do {
            guard let data = try locatorStorage.read(locatorKey) else { return nil }
            guard data.count <= 2048 else { throw APIError.malformedResponse }
            let row = try JSONDecoder().decode(Locator.self, from: data)
            guard row.version == 1, row.owner == owner, row.actionID == notice.actionID,
                  NativeChannelGovernanceNotice.positive(row.appealID) != nil,
                  (try JSONSerialization.jsonObject(with: data) as? NSDictionary) ==
                    (try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? NSDictionary) else { throw APIError.malformedResponse }
            locatorUnavailable = false
            return row.appealID
        } catch {
            locatorUnavailable = true
            return nil
        }
    }
    /// Best-effort ID retention must not turn a proven APPLIED result into UNKNOWN.
    /// Persist before journal cleanup to reduce the restart window; original cleanup still decides pending.
    private func rememberLocator(_ id: String) {
        guard isCurrent, let locatorStorage else { return }
        do {
            let data = try JSONEncoder().encode(Locator(version: 1, owner: owner, actionID: notice.actionID, appealID: id))
            try locatorStorage.write(data, key: locatorKey)
            guard try locatorStorage.read(locatorKey) == data else { throw APIError.malformedResponse }
            locatorUnavailable = false
        } catch {
            locatorUnavailable = true
        }
    }
    private func issueOriginal(_ record: Record, recovering: Bool) -> Bool {
        guard let runtimeAuthorization else { return true } // Existing explicit-route clients remain compatible.
        let original = NativeChannelAppealOriginalCommand(operation: record.operation, requestID: record.requestID, path: record.path, body: record.body)
        return runtimeAuthorization.issue(original, recovering: recovering, pendingMatches: { [weak self] in
            guard let self, self.isCurrent else { return false }
            return (try? self.restore()) == record
        })
    }
    private func receiptPath(_ id: String) -> String { "api/channel-platform/governance/moderation/requests/" + id }
    private func exchange(_ method: String, _ path: String, body: Data? = nil, query: [URLQueryItem] = [], freshReceiptID: String? = nil) async throws -> [String: Any] {
        let visit = visitID
        if method == "GET" { runtimeAuthorization?.locateCurrentAppeal(path) }
        guard matchesVisit(visit), permits(method, path) else { throw APIError.unauthorized }
        guard freshReceiptID.map({ permits("GET", receiptPath($0)) }) ?? true else { throw APIError.unauthorized }
        guard var components = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        try Task.checkCancellation(); let (data, status) = try await transport.send(request)
        guard matchesVisit(visit) else { throw APIError.unauthorized }; try Task.checkCancellation()
        guard data.count <= 256 * 1024, let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.malformedResponse }
        let code = (response["code"] as? NSNumber)?.intValue
        if status == 401 || code == 401 { unauthorized(); throw APIError.unauthorized }
        guard (200..<300).contains(status), code == 200, let result = response["data"] as? [String: Any] else { throw APIError.malformedResponse }
        return result
    }
}
