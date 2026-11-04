import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only the personal inventory contract. No TEAM, trade, quest or chapter commands.
public enum PlayThemeBackpackOperation: String, Codable, CaseIterable, Sendable {
    case use = "USE", discard = "DISCARD", receive = "RECEIVE"
}
public struct PlayThemeBackpackDiscard: Codable, Equatable, Sendable {
    public let itemId: String
    public let quantity: Int
    public init(itemID: String, quantity: Int) { itemId = itemID; self.quantity = quantity }
}
public struct PlayThemeBackpackCommand: Codable, Equatable {
    public let sessionId: Int
    public let expectedVersion: Int
    public let actionId: String
    public let operation: PlayThemeBackpackOperation
    public let contentId: String
    public let discardOwned: [PlayThemeBackpackDiscard]?
    init(sessionID: Int, version: Int, operation: PlayThemeBackpackOperation, contentID: String,
         discardOwned: [PlayThemeBackpackDiscard]?, actionID: String = "bag_" + UUID().uuidString) throws {
        sessionId = sessionID; expectedVersion = version; self.operation = operation
        contentId = contentID; self.discardOwned = discardOwned; actionId = actionID
        try validate()
    }
    func validate() throws {
        guard sessionId > 0, expectedVersion >= 0, expectedVersion < Int(Int32.max),
              !contentId.isEmpty, contentId.utf16.count <= 96,
              !actionId.isEmpty, actionId.utf8.count <= 80,
              actionId.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [58,95,45].contains($0) }),
              discardOwned == nil || operation == .receive else { throw PlayExperienceError.invalidAction }
        if let rows = discardOwned {
            guard rows.count <= 200, Set(rows.map { Data($0.itemId.utf8) }).count == rows.count,
                  rows.allSatisfy({ !$0.itemId.isEmpty && $0.itemId.utf16.count <= 96 && $0.quantity > 0 && $0.quantity <= Int(Int32.max) }) else { throw PlayExperienceError.invalidAction }
        }
    }
    func encodedBody() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Swift String equality normalizes Unicode. Request identity is UTF-8 bytes.
        (try? lhs.encodedBody()) == (try? rhs.encodedBody())
    }
}
public struct PlayThemeBackpackIntent: Codable, Equatable {
    public let owner: PlayRecoveryOwner
    public let activityID: Int
    public var scope: PlaySessionScope { activityID > 0 ? .activity(activityID) : .topic(topicID) }
    public let topicID: Int
    public let command: PlayThemeBackpackCommand
    public let requiresCompletedReceive: Bool
    /// Exact originally encoded JSON, including absent vs [] and discard row order.
    public let body: Data
    init(session: PlayExperienceSession, scope: PlaySessionScope, topicID: Int, command: PlayThemeBackpackCommand, requiresCompletedReceive: Bool = false) throws {
        owner = .init(session: session); activityID = { if case .activity(let id) = scope { return id }; return 0 }()
        self.topicID = topicID; self.command = command; self.requiresCompletedReceive = requiresCompletedReceive
        guard scope.isValid else { throw PlayExperienceError.invalidAction }
        if case .topic(let id) = scope, id != topicID { throw PlayExperienceError.invalidAction }
        body = try command.encodedBody(); try validate()
    }
    func validate() throws {
        try command.validate()
        guard owner.accountID > 0, !owner.namespace.isEmpty, !owner.role.isEmpty,
              (!requiresCompletedReceive || command.operation == .receive), activityID >= 0, scope.isValid, topicID > 0, body.count <= 65_536, body == (try command.encodedBody()) else { throw PlayExperienceError.persistenceUnavailable }
        if case .topic(let id) = scope, id != topicID { throw PlayExperienceError.persistenceUnavailable }
    }
    public var storageKey: String {
        // Neither epoch, role nor run ID creates a new slot around an old unresolved action.
        "theme-backpack:v1:" + Data(owner.namespace.utf8).base64EncodedString() + ":" + String(owner.accountID) + ":" + (activityID > 0 ? "activity-" + String(activityID) : "topic-" + String(topicID)) + ":" + String(topicID)
    }
}

/// Strict mutation facts are separate from the tolerant legacy read-only display projection.
public struct PlayThemeBackpackActionFacts: Equatable {
    public let backpack: PlayThemeBackpack
    public let sessionID: Int
    public let version: Int
    public let topicID: Int
    public let activityID: Int
    public let status: String
    public let raw: PlayWireValue
    public init(_ raw: PlayWireValue, scope: PlaySessionScope, topicID: Int, sessionID: Int? = nil) throws {
        guard raw.object != nil, raw["scope"] == .null || raw["scope"].text == "PERSONAL",
              raw["runtimeScope"] == .null || raw["runtimeScope"].text == "PLAYER",
              raw["inventoryEnabled"].bool == true,
              let run = raw["sessionId"].integer, run > 0, sessionID == nil || run == sessionID,
              let version = raw["version"].integer, version >= 0, version <= Int(Int32.max),
              raw["topicId"].integer == topicID,
              let activity = raw["activityId"].integer, activity >= 0,
              let status = raw["status"].text, ["ACTIVE", "COMPLETED", "ENDED"].contains(status),
              let used = raw["used"].integer, used >= 0,
              let capacity = raw["capacity"].integer, capacity >= 0,
              raw["contents"].array != nil, raw["pending"].object != nil else { throw PlayExperienceError.malformed }
        switch scope {
        case .activity(let id): guard id == activity else { throw PlayExperienceError.staleSession }
        case .topic(let id): guard id == topicID, activity == 0 else { throw PlayExperienceError.staleSession }
        }
        self.raw = raw; self.sessionID = run; self.version = version; self.topicID = topicID
        activityID = activity; self.status = status; backpack = try .init(raw)
    }
    public var hasReservedSupplies: Bool {
        raw["activeQuest"].text?.isEmpty == false || raw["activeOperation"] != .null
    }
    public var canDiscardOwned: Bool { status == "COMPLETED" && !hasReservedSupplies && raw["allowDiscard"].bool == true }
    private func pendingRow(_ id: String) -> PlayWireValue? {
        (raw["pending"].object ?? [:]).first { $0.key.utf8.elementsEqual(id.utf8) }?.value
    }
    private func pendingSlots(_ id: String) -> Int? {
        guard let row = pendingRow(id), row["itemId"].text?.isEmpty == false,
              let quantity = row["quantity"].integer, quantity > 0, quantity <= Int(Int32.max),
              let slots = row["slots"].integer, slots >= 0 else { return nil }
        return slots
    }
    public func hasRoomForPending(_ id: String) -> Bool {
        guard let slots = pendingSlots(id) else { return false }
        let (total, overflow) = backpack.used.addingReportingOverflow(slots)
        return !overflow && total <= backpack.capacity
    }
    public func allows(_ operation: PlayThemeBackpackOperation, contentID: String, completedReceiveAccepted: Bool) -> Bool {
        guard !contentID.isEmpty, contentID.utf16.count <= 96 else { return false }
        let hasPending = pendingSlots(contentID) != nil
        let sameID: (PlayWireValue) -> Bool = { row in row["id"].text.map { $0.utf8.elementsEqual(contentID.utf8) } == true }
        if status == "COMPLETED" {
            return completedReceiveAccepted && !hasReservedSupplies && operation == .receive && hasPending &&
                (raw["allowedActions"].array ?? []).contains { $0["operation"].text == "RECEIVE" && $0["contentId"].text.map { $0.utf8.elementsEqual(contentID.utf8) } == true && $0["claimOnly"].bool == true }
        }
        guard status == "ACTIVE", !backpack.claimOnly, raw["awaitingRescue"].bool != true else { return false }
        if operation == .receive { return hasPending && hasRoomForPending(contentID) }
        guard !hasReservedSupplies else { return false }
        guard let item = (raw["contents"].array ?? []).first(where: sameID), item["kind"].text == "ITEM",
              let quantity = item["quantity"].integer, quantity > 0 else { return false }
        if operation == .discard { return raw["allowDiscard"].bool == true }
        return item["wear"].bool != true && item["worn"].bool != true &&
            (item["stat"].text?.isEmpty == false || item["statKey"].text?.isEmpty == false)
    }
    func review(_ operation: PlayThemeBackpackOperation, contentID: String, discardOwned: [PlayThemeBackpackDiscard]?, completedReceiveAccepted: Bool) throws -> PlayThemeBackpackCommand {
        guard allows(operation, contentID: contentID, completedReceiveAccepted: completedReceiveAccepted) else { throw PlayExperienceError.invalidAction }
        if let selection = discardOwned {
            guard status == "COMPLETED", operation == .receive, selection.isEmpty || canDiscardOwned else { throw PlayExperienceError.invalidAction }
            for row in selection {
                guard let held = (raw["contents"].array ?? []).first(where: { $0["id"].text.map { $0.utf8.elementsEqual(row.itemId.utf8) } == true }),
                      held["kind"].text == "ITEM", let quantity = held["quantity"].integer,
                      row.quantity > 0, row.quantity <= quantity else { throw PlayExperienceError.invalidAction }
            }
        }
        if status == "COMPLETED", operation == .receive {
            guard let slots = pendingSlots(contentID) else { throw PlayExperienceError.invalidAction }
            var removed = 0
            for row in discardOwned ?? [] {
                guard let held = (raw["contents"].array ?? []).first(where: { $0["id"].text.map { $0.utf8.elementsEqual(row.itemId.utf8) } == true }),
                      let cost = held["slotCost"].integer, cost >= 0 else { throw PlayExperienceError.invalidAction }
                let (amount, overflow) = cost.multipliedReportingOverflow(by: row.quantity)
                let (total, additionOverflow) = removed.addingReportingOverflow(amount)
                guard !overflow, !additionOverflow else { throw PlayExperienceError.invalidAction }; removed = total
            }
            guard removed <= backpack.used else { throw PlayExperienceError.invalidAction }
            let (total, overflow) = (backpack.used - removed).addingReportingOverflow(slots)
            guard !overflow, total <= backpack.capacity else { throw PlayExperienceError.invalidAction }
        }
        return try .init(sessionID: sessionID, version: version, operation: operation, contentID: contentID, discardOwned: discardOwned)
    }
}

/// Explicit integration acceptance only. Defaults remain closed; UI never enables this service.
/// Completed claims additionally need a verified backend CAS fix (frozen 58 only updates status=0).
public struct PlayThemeBackpackActionService {
    let configuration: APIConfiguration
    let transport: any HTTPTransport
    public let accepted: Bool
    public let completedReceiveAccepted: Bool
    private let lifetime: PlayInteractionLifetime?
    public init(configuration: APIConfiguration, transport: any HTTPTransport, accepted: Bool = false,
                completedReceiveAccepted: Bool = false, lifetime: PlayInteractionLifetime? = nil) {
        self.configuration = configuration; self.transport = transport; self.accepted = accepted
        self.completedReceiveAccepted = completedReceiveAccepted; self.lifetime = lifetime
    }
    @MainActor var hasCurrentLifetime: Bool { transport is PlayRecoveryRecordingTransport || lifetime?.isCurrent == true }
    @MainActor func check() throws {
        guard accepted else { throw PlayExperienceError.disabled }
        guard transport is PlayRecoveryRecordingTransport || lifetime != nil else { throw PlayExperienceError.staleSession }
        try lifetime?.check(); try Task.checkCancellation()
    }
    @MainActor func read(scope: PlaySessionScope, topicID: Int, sessionID: Int?, session: PlayExperienceSession) async throws -> PlayWireValue {
        try check()
        guard scope.isValid, topicID > 0, sessionID == nil || sessionID! > 0 else { throw APIError.invalidRequest }
        var fields = scope.fields; fields["topicId"] = String(topicID)
        // Explicit 0 distinguishes self-play from an ambiguous legacy unscoped activity.
        if case .topic = scope { fields["activityId"] = "0" }
        if let sessionID { fields["sessionId"] = String(sessionID) }
        var request = try request(token: session.token, path: "state")
        var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        url.queryItems = fields.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }; request.url = url.url
        let reply: (Data, Int)
        if transport is PlayRecoveryRecordingTransport { reply = try await transport.send(request) }
        else {
            guard let transport = transport as? any PlayThemeBackpackTransport else { throw PlayExperienceError.disabled }
            reply = try await transport.sendThemeBackpackRead(request, session: session, scope: scope, topicID: topicID)
        }
        return try decode(reply)
    }
    @MainActor func checkWrite(recovery: PlayThemeBackpackRecoveryStore) throws {
        try check()
        guard transport is PlayRecoveryRecordingTransport ||
            (transport is any PlayThemeBackpackTransport && recovery.permitsSystemDispatch(to: configuration.baseURL)) else { throw PlayExperienceError.persistenceUnavailable }
    }
    @MainActor func write(_ snapshot: PlayThemeBackpackRecoverySnapshot, session: PlayExperienceSession, recovery: PlayThemeBackpackRecoveryStore, checkOwner: @escaping () throws -> Void) async throws -> PlayWireValue {
        try check(); try checkOwner()
        guard snapshot.value.state == .dispatching, snapshot.value.dispatchProcess == recovery.processID,
              try await recovery.read() == snapshot else { throw PlayExperienceError.persistenceUnavailable }
        try check()
        try checkOwner()
        let intent = snapshot.value.intent
        try intent.validate()
        guard transport is PlayRecoveryRecordingTransport || recovery.permitsSystemDispatch(to: configuration.baseURL) else { throw PlayExperienceError.persistenceUnavailable }
        guard intent.owner.matches(session), !intent.requiresCompletedReceive || completedReceiveAccepted else { throw PlayExperienceError.disabled }
        var request = try request(token: session.token, path: "action")
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = intent.body
        let reply: (Data, Int)
        if transport is PlayRecoveryRecordingTransport { reply = try await transport.send(request) }
        else {
            guard let transport = transport as? any PlayThemeBackpackTransport else { throw PlayExperienceError.disabled }
            let permit = PlayThemeBackpackDispatchPermit(session: session, snapshot: snapshot,
                recovery: recovery, baseURL: configuration.baseURL, checkCurrent: checkOwner)
            reply = try await transport.sendThemeBackpackWrite(request, permit: permit)
        }
        try checkOwner()
        return try decode(reply)
    }
    private func request(token: String, path: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token), ["state", "action"].contains(path) else { throw APIError.invalidRequest }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/play/theme/" + path))
        request.httpMethod = "GET"; request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    @MainActor private func decode(_ reply: (Data, Int)) throws -> PlayWireValue {
        try check()
        let (data, status) = reply
        guard data.count <= 512 * 1024 else { throw PlayExperienceError.malformed }
        let envelope = try? JSONDecoder().decode(PlayWireValue.self, from: data)
        if status == 401 || envelope?["code"].integer == 401 { throw PlayExperienceError.unauthorized }
        guard (200..<300).contains(status) else { throw PlayExperienceError.unknownResult }
        guard let code = envelope?["code"].integer else { throw PlayExperienceError.malformed }
        guard code == 200 else { throw PlayExperienceError.rejected(code, envelope?["msg"].text) }
        guard let value = envelope?["data"], value.object != nil else { throw PlayExperienceError.malformed }
        return value
    }
}

/// A single personal inventory writer. All reads retain unresolved original intents;
/// only the response to the original POST (or its exact idempotent replay) acknowledges it.
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayThemeBackpackActions {
    public enum Phase: Equatable {
        case idle, loading, ready, reviewing, sending, unknown, active, unavailable, storageUnavailable, stale
        case failed(message: String?)
    }
    public private(set) var phase: Phase = .idle
    public private(set) var facts: PlayThemeBackpackActionFacts?
    public private(set) var review: PlayThemeBackpackIntent?
    public private(set) var lastConfirmedOperation: PlayThemeBackpackOperation?
    public private(set) var pendingCommand: PlayThemeBackpackCommand?
    public var isCurrent: Bool { captured != nil && current() == captured && service.hasCurrentLifetime }
    public var canStart: Bool { visible && isCurrent && phase == .ready && pending == nil && !busy }
    public var canRecover: Bool { visible && isCurrent && phase == .unknown && !busy }
    public var completedReceiveAccepted: Bool { service.completedReceiveAccepted }
    private let service: PlayThemeBackpackActionService
    private let scope: PlaySessionScope
    private let topicID: Int
    private let current: () -> PlayExperienceSession?
    private let captured: PlayExperienceSession?
    private let recovery: PlayThemeBackpackRecoveryStore?
    private var pending: PlayThemeBackpackRecoverySnapshot?
    private var busy = false
    private var generation: UInt64 = 0
    private var visible = true
    private let onConfirmed: () async -> Void
    private var notificationPending = false
    public init(service: PlayThemeBackpackActionService, scope: PlaySessionScope, topicID: Int,
                current: @escaping () -> PlayExperienceSession?, recovery: PlayThemeBackpackRecoveryStore?,
                onConfirmed: @escaping () async -> Void = {}) {
        self.service = service; self.scope = scope; self.topicID = topicID; self.current = current
        captured = current(); self.recovery = recovery; self.onConfirmed = onConfirmed
        if !service.accepted || captured == nil || !scope.isValid || topicID <= 0 { phase = .unavailable }
        else if recovery == nil { phase = .storageUnavailable }
    }
    private func check(_ stamp: UInt64) throws -> PlayExperienceSession {
        guard visible, generation == stamp, let captured, current() == captured else { throw PlayExperienceError.staleSession }
        try service.check(); return captured
    }
    /// Navigation/background does not cancel, delete or reissue a persisted command.
    public func suspend() {
        visible = false; generation &+= 1; review = nil; facts = nil; lastConfirmedOperation = nil
    }
    public func activate() { visible = true }
    private func validate(_ value: PlayThemeBackpackRecoverySnapshot, session: PlayExperienceSession) throws {
        try value.value.intent.validate()
        guard value.value.intent.owner.matches(session), value.value.intent.scope == scope,
              value.value.intent.topicID == topicID else { throw PlayExperienceError.staleSession }
    }
    private func setPending(_ value: PlayThemeBackpackRecoverySnapshot?) {
        pending = value; pendingCommand = value?.value.intent.command
    }
    private func pendingPhase(_ value: PlayThemeBackpackRecoverySnapshot) -> Phase {
        value.value.state == .dispatching && value.value.dispatchProcess == recovery?.processID ? .active : .unknown
    }
    private func accept(_ value: PlayThemeBackpackActionFacts) {
        // An exact replay returns its old projection. Never replace a newer same-run view.
        if let old = facts, old.sessionID == value.sessionID, old.version > value.version { return }
        facts = value
    }
    private func acceptFresh(_ value: PlayThemeBackpackActionFacts) throws {
        if let old = facts, old.sessionID == value.sessionID, old.version > value.version { throw PlayExperienceError.malformed }
        facts = value
    }
    private func notifyConfirmed() async {
        guard notificationPending, isCurrent, visible else { return }
        notificationPending = false
        await onConfirmed()
    }
    private func fail(_ error: Error) {
        review = nil
        if !isCurrent || !visible || error as? PlayExperienceError == .staleSession || error as? PlayExperienceError == .unauthorized { facts = nil; lastConfirmedOperation = nil; phase = .stale; return }
        if error as? PlayExperienceError == .disabled { facts = nil; phase = .unavailable; return }
        if error as? PlayExperienceError == .persistenceUnavailable { phase = .storageUnavailable; return }
        if let pending { phase = pendingPhase(pending); return }
        if case PlayExperienceError.rejected(_, let message) = error { phase = .failed(message: message) }
        else { phase = .failed(message: nil) }
    }
    public func refresh() async {
        guard !busy else { return }
        guard let recovery else { phase = service.accepted ? .storageUnavailable : .unavailable; return }
        busy = true; defer { busy = false }; let stamp = generation
        review = nil; phase = .loading
        do {
            let session = try check(stamp)
            let stored = try await recovery.read()
            _ = try check(stamp)
            if let stored { try validate(stored, session: session) }
            setPending(stored)
            if let stored, stored.value.state == .acknowledged {
                try await finishAcknowledged(stored, stamp: stamp)
            }
            let originalID = stored?.value.intent.command.sessionId
            let value = try await service.read(scope: scope, topicID: topicID, sessionID: originalID, session: session)
            _ = try check(stamp)
            let next = try PlayThemeBackpackActionFacts(value, scope: scope, topicID: topicID, sessionID: originalID)
            try acceptFresh(next)
            phase = pending.map(pendingPhase) ?? .ready
        } catch { fail(error) }
        await notifyConfirmed()
    }
    public func begin(_ operation: PlayThemeBackpackOperation, contentID: String, discardOwned: [PlayThemeBackpackDiscard]? = nil) throws {
        guard canStart, let facts else { throw PlayExperienceError.busy }
        let session = try check(generation)
        let command = try facts.review(operation, contentID: contentID, discardOwned: discardOwned,
                                       completedReceiveAccepted: service.completedReceiveAccepted)
        review = try .init(session: session, scope: scope, topicID: topicID, command: command, requiresCompletedReceive: facts.status == "COMPLETED")
        lastConfirmedOperation = nil; phase = .reviewing
    }
    public func cancelReview() { if !busy, phase == .reviewing { review = nil; phase = .ready } }
    public func confirm() async {
        guard !busy, phase == .reviewing, let intent = review, let recovery, pending == nil else { return }
        busy = true; defer { busy = false }; let stamp = generation
        do {
            let session = try check(stamp)
            guard intent.owner.matches(session), let facts, facts.sessionID == intent.command.sessionId,
                  facts.version == intent.command.expectedVersion else { throw PlayExperienceError.staleSession }
            try service.checkWrite(recovery: recovery)
            // Hold the immutable reviewed body before any possible dispatch.
            let stored = try await recovery.prepare(intent)
            setPending(stored); review = nil
            _ = try check(stamp)
            try await dispatch(stored, stamp: stamp)
        } catch { fail(error) }
        await notifyConfirmed()
    }
    /// Explicit user retry of the one original request. No new UUID, refreshed version,
    /// changed selection, scope fallback, auto replay, or current-run substitution.
    public func recover() async {
        guard canRecover, let recovery else { return }
        busy = true; defer { busy = false }; let stamp = generation
        do {
            let session = try check(stamp)
            guard let stored = try await recovery.read() else { throw PlayExperienceError.persistenceUnavailable }
            _ = try check(stamp); try validate(stored, session: session); setPending(stored)
            if stored.value.state == .acknowledged {
                let command = stored.value.intent.command
                try await finishAcknowledged(stored, stamp: stamp)
                let fresh = try await service.read(scope: scope, topicID: topicID, sessionID: command.sessionId, session: session)
                _ = try check(stamp)
                try acceptFresh(.init(fresh, scope: scope, topicID: topicID, sessionID: command.sessionId))
                phase = .ready; await notifyConfirmed(); return
            }
            guard stored.value.state != .dispatching || stored.value.dispatchProcess != recovery.processID else {
                phase = .active; return
            }
            try service.checkWrite(recovery: recovery)
            try await dispatch(stored, stamp: stamp)
        } catch { fail(error) }
        await notifyConfirmed()
    }
    private func dispatch(_ original: PlayThemeBackpackRecoverySnapshot, stamp: UInt64) async throws {
        guard let recovery else { throw PlayExperienceError.persistenceUnavailable }
        _ = try check(stamp); phase = .sending
        let dispatching = try await recovery.transition(original, to: .dispatching)
        setPending(dispatching)
        do {
            let session = try check(stamp)
            let value = try await service.write(dispatching, session: session, recovery: recovery, checkOwner: { _ = try self.check(stamp) })
            _ = try check(stamp)
            let command = dispatching.value.intent.command
            let next = try PlayThemeBackpackActionFacts(value, scope: scope, topicID: topicID, sessionID: command.sessionId)
            guard next.version == command.expectedVersion + 1 else { throw PlayExperienceError.malformed }
            let receipt = try JSONEncoder().encode(value)
            let acknowledged = try await recovery.transition(dispatching, to: .acknowledged, receipt: receipt)
            setPending(acknowledged)
            _ = try check(stamp)
            try await finishAcknowledged(acknowledged, stamp: stamp)
            // The write receipt is authoritative for the original request; refresh the same run.
            let fresh = try await service.read(scope: scope, topicID: topicID, sessionID: command.sessionId, session: session)
            _ = try check(stamp)
            try acceptFresh(.init(fresh, scope: scope, topicID: topicID, sessionID: command.sessionId))
            phase = .ready
        } catch {
            // Only update the exact dispatching generation. Failure to persist is not an unlock.
            if pending?.value.state == .dispatching,
               let unknown = try? await recovery.transition(dispatching, to: .unknown) { setPending(unknown) }
            throw error
        }
    }
    private func finishAcknowledged(_ stored: PlayThemeBackpackRecoverySnapshot, stamp: UInt64) async throws {
        guard let recovery, stored.value.state == .acknowledged, let bytes = stored.value.receipt else { throw PlayExperienceError.persistenceUnavailable }
        let session = try check(stamp); try validate(stored, session: session)
        let value = try JSONDecoder().decode(PlayWireValue.self, from: bytes)
        let command = stored.value.intent.command
        let next = try PlayThemeBackpackActionFacts(value, scope: scope, topicID: topicID, sessionID: command.sessionId)
        guard next.version == command.expectedVersion + 1 else { throw PlayExperienceError.persistenceUnavailable }
        try await recovery.clear(stored)
        _ = try check(stamp)
        setPending(nil); review = nil; accept(next); lastConfirmedOperation = command.operation
        notificationPending = true
    }
}
