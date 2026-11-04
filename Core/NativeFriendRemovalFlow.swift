import Foundation

/// Real-row confirmation plus owner-wide, durable recovery even after that friend row disappears.
@MainActor public final class NativeFriendRemovalFlow {
    public enum Phase: Equatable { case closed, loading, ready, reviewing, removing, unknown, resolved, unavailable, failed }
    public let item: NativeFriendItem?
    private var savedPhase: Phase = .closed
    public private(set) var phase: Phase {
        get { isCurrent ? savedPhase : (pending == nil ? .closed : .unknown) }
        set { savedPhase = newValue }
    }
    private var savedRelationship: NativeFriendRelationship?
    public private(set) var currentRelationship: NativeFriendRelationship? {
        get { isCurrent ? savedRelationship : nil }
        set { savedRelationship = newValue }
    }
    private var savedReview: NativeFriendRemovalCommand?
    public private(set) var review: NativeFriendRemovalCommand? {
        get { isCurrent ? savedReview : nil }
        set { savedReview = newValue }
    }
    public private(set) var pending: OperationPendingRecord?
    private var savedResult: NativeFriendRemovalReceipt?
    public private(set) var result: NativeFriendRemovalReceipt? {
        get { isCurrent ? savedResult : nil }
        set { savedResult = newValue }
    }
    public private(set) var issue: String?
    public private(set) var busy = false
    public var onChange: (() -> Void)?
    public var onResolved: (() -> Void)?
    private let service: (any NativeFriendRemovalServing)?
    private let journal: any OperationPendingListing
    private let ownerKey: String
    private var generation: UInt64 = 0
    private var authorityRetired = false
    private var authorityTask: Task<Void, Never>?
    public var isCurrent: Bool { !authorityRetired && service?.isCurrent == true }
    private static let prefix = "native-friend-removal.v1."
    public init(item: NativeFriendItem? = nil, service: (any NativeFriendRemovalServing)?, journal: any OperationPendingListing, ownerKey: String) {
        self.item = item; self.service = service; self.journal = journal; self.ownerKey = ownerKey
        // Local grant/context observation only. No network read, automatic replay, or permission grant.
        authorityTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self, self.validateAuthority() else { return }
            }
        }
    }
    deinit { authorityTask?.cancel() }
    @discardableResult public func validateAuthority() -> Bool {
        guard isCurrent else {
            if !authorityRetired {
                authorityRetired = true; generation &+= 1; busy = false
                currentRelationship = nil; review = nil; result = nil
                phase = pending == nil ? .closed : .unknown; issue = "friendRemoval.closed"; changed()
            }
            return false
        }
        return true
    }
    /// Never label an original operation with an unrelated currently selected friend row.
    public var presentationItem: NativeFriendItem? {
        guard isCurrent, phase != .closed, let item else { return nil }
        if pending != nil {
            guard let original = pendingCommand, original.peerID == item.peerID, original.expectedVersion == item.version else { return nil }
        }
        if let result {
            guard result.peerID == item.peerID, result.expectedVersion == item.version else { return nil }
        }
        return item
    }
    public var canReview: Bool {
        guard let item, let current = currentRelationship else { return false }
        return phase == .ready && !busy && pending == nil && isCurrent && service?.canWrite == true &&
            item.state == .friend && current.state == .friend && current.peerID == item.peerID && current.version == item.version
    }
    public var canConfirm: Bool { phase == .reviewing && review != nil && !busy && pending == nil && isCurrent && service?.canWrite == true }
    public var canRecover: Bool { phase == .unknown && !busy && pendingCommand != nil && isCurrent }
    public var canSettle: Bool { false }
    public var canRetryOriginal: Bool { canRecover && service?.canWrite == true }
    public var pendingCommand: NativeFriendRemovalCommand? { isCurrent ? pending.flatMap { try? command($0) } : nil }
    /// A synchronous presentation callback may close this visit before the service starts.
    /// Preserve any original journal entry; never dispatch from that retired visit.
    private func requireCurrentVisit(_ stamp: UInt64) throws {
        guard generation == stamp, isCurrent, !Task.isCancelled else { throw NativeFriendFailure.staleSession }
    }
    private func changed() { onChange?() }
    private func key(_ value: NativeFriendRemovalCommand) -> String { Self.prefix + "\(value.peerID).\(value.expectedVersion)" }
    private func command(_ record: OperationPendingRecord) throws -> NativeFriendRemovalCommand {
        guard record.ownerKey == ownerKey, record.targetKey.hasPrefix(Self.prefix) else { throw NativeFriendFailure.invalid }
        let parts = record.targetKey.dropFirst(Self.prefix.count).split(separator: ".")
        guard parts.count == 2, let peer = Int64(parts[0]), peer > 0, let version = Int64(parts[1]), version > 0, version < Int64.max else { throw NativeFriendFailure.invalid }
        return .init(requestID: record.operationID, peerID: peer, expectedVersion: version)
    }
    private func findPending() throws -> OperationPendingRecord? {
        try journal.pendingRecords(ownerKey: ownerKey).first { $0.targetKey.hasPrefix(Self.prefix) }
    }
    private func finish(_ service: any NativeFriendRemovalServing, stamp: UInt64) {
        guard generation == stamp else { return }
        if !service.isCurrent { currentRelationship = nil; review = nil; result = nil; phase = pending == nil ? .closed : .unknown; issue = "friendRemoval.closed" }
        busy = false; changed()
    }
    public func load() async {
        guard !busy, !Task.isCancelled else { return }
        generation &+= 1; let stamp = generation; review = nil; issue = nil; currentRelationship = nil; result = nil
        do { pending = try findPending() }
        catch { phase = .failed; issue = "friendRemoval.storageFailure"; changed(); return }
        guard let service, validateAuthority() else { phase = pending == nil ? .closed : .unknown; issue = pending == nil ? nil : "friendRemoval.closed"; changed(); return }
        // UNKNOWN is presented from the journal, not inferred from the present friend list.
        if pending != nil { phase = .unknown; changed(); return }
        guard let item, item.state == .friend, item.peerID > 0, item.version > 0, item.version < Int64.max else { phase = .ready; changed(); return }
        busy = true; phase = .loading; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let current = try await service.relationship(peerID: item.peerID)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            guard current.viewerID == service.viewerID, current.peerID == item.peerID, current.version >= 0 else { throw NativeFriendFailure.invalid }
            currentRelationship = current
            phase = current.state == .friend && current.version == item.version ? .ready : .unavailable
            if phase == .unavailable { issue = "friendRemoval.changed" }
        } catch { if generation == stamp { phase = .failed; issue = "friendRemoval.readFailure" } }
    }
    public func reviewRemoval() {
        guard canReview, let item else { return }
        review = .init(peerID: item.peerID, expectedVersion: item.version); phase = .reviewing; issue = nil; changed()
    }
    public func cancelReview() { guard !busy, pending == nil else { return }; review = nil; phase = .ready; changed() }
    public func confirm() async {
        guard let confirmed = review else { return }
        await confirm(confirmed: confirmed)
    }
    /// The normal view captures the displayed UUID before queuing its asynchronous gesture.
    public func confirm(confirmed: NativeFriendRemovalCommand) async {
        guard !Task.isCancelled, canConfirm, let command = review, command == confirmed, let service else { return }
        let stamp = generation
        let record = OperationPendingRecord(operationID: command.requestID, ownerKey: ownerKey, targetKey: key(command))
        do {
            // MainActor and owner-wide journal fence competing screens before the first await.
            if let original = try findPending() { pending = original; review = nil; phase = .unknown; changed(); return }
            try journal.write(record); pending = record
            // The existing record contains the entire payload: UUID + peer + exact relationship version.
            guard try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) == record,
                  try self.command(record) == command else { throw NativeFriendFailure.unknown }
        } catch { pending = record; review = nil; phase = .unknown; issue = "friendRemoval.storageFailure"; changed(); return }
        review = nil; busy = true; phase = .removing; issue = nil; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let value = try await service.remove(command)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            try resolve(value, record: record, service: service)
        } catch NativeFriendFailure.notSent {
            // Only a proven pre-dispatch refusal may clear without a terminal server receipt.
            guard generation == stamp else { return }
            do { try clear(record); phase = .failed; issue = "friendRemoval.notSent" }
            catch { phase = .unknown; issue = "friendRemoval.storageFailure" }
        } catch { if generation == stamp { phase = .unknown; issue = "friendRemoval.unknown" } }
    }
    private func clear(_ record: OperationPendingRecord, matchedTerminal: Bool = false) throws {
        if let original = try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) {
            guard original == record else { throw NativeFriendFailure.unknown }
            try journal.clear(record)
        } else if !matchedTerminal { throw NativeFriendFailure.unknown }
        // Another recovery screen may already have cleared this exact terminal operation.
        pending = nil
    }
    private func resolve(_ value: NativeFriendRemovalReceipt, record: OperationPendingRecord, service: any NativeFriendRemovalServing) throws {
        let original = try command(record)
        guard value.matches(original, viewerID: service.viewerID), ["APPLIED", "REJECTED"].contains(value.outcome) else { throw NativeFriendFailure.unknown }
        try clear(record, matchedTerminal: true); result = value; currentRelationship = value.currentRelationship
        // A terminal receipt remains known even if a subsequent journal listing is unavailable.
        phase = .resolved; issue = value.currentRelationship == nil ? "friendRemoval.currentUnavailable" : nil
        do { pending = try findPending(); if pending != nil { phase = .unknown } }
        catch { issue = "friendRemoval.journalReadFailure" }
        onResolved?() // Owner's ordinary friends list rereads; peer-owner visibility is verified on the backend.
    }
    /// A separately confirmed gesture continues ONLY the complete original command after readback.
    public func retryOriginal(confirmed: NativeFriendRemovalCommand) async {
        guard !Task.isCancelled, validateAuthority(), canRetryOriginal, let record = pending,
              let original = try? command(record), original == confirmed, let service else { return }
        let stamp = generation; busy = true; issue = nil; changed()
        defer { finish(service, stamp: stamp) }
        do {
            guard try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) == record else { throw NativeFriendFailure.unknown }
            try requireCurrentVisit(stamp)
            let prior = try await service.receipt(original)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            guard prior.matches(original, viewerID: service.viewerID) else { throw NativeFriendFailure.unknown }
            if prior.outcome != "UNKNOWN" { try resolve(prior, record: record, service: service) }
            else {
                // Another recovery may have completed/replaced this journal while the read was suspended.
                // An old UNKNOWN response is not permission to dispatch a retired original request.
                guard pending == record,
                      try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) == record else {
                    throw NativeFriendFailure.unknown
                }
                try requireCurrentVisit(stamp)
                let value = try await service.remove(original)
                guard generation == stamp, isCurrent, !Task.isCancelled else { return }
                try resolve(value, record: record, service: service)
            }
        } catch {
            // A failed retry cannot disprove execution of an earlier uncertain attempt.
            if generation == stamp { phase = .unknown; issue = "friendRemoval.unknown" }
        }
    }
    public func recover() async { await recoverOrSettle(settle: false, confirmed: nil) }
    /// UI must capture the exact original command in a separate destructive confirmation.
    public func settleOriginal(confirmed: NativeFriendRemovalCommand) async { await recoverOrSettle(settle: true, confirmed: confirmed) }
    private func recoverOrSettle(settle: Bool, confirmed: NativeFriendRemovalCommand?) async {
        guard !Task.isCancelled, canRecover, let record = pending, let original = try? command(record) else { return }
        guard let service, validateAuthority() else {
            currentRelationship = nil; result = nil; phase = .unknown; issue = "friendRemoval.closed"; changed(); return
        }
        guard !settle || (canSettle && confirmed == original) else { return }
        let stamp = generation; busy = true; issue = nil; changed(); defer { finish(service, stamp: stamp) }
        do {
            let value: NativeFriendRemovalReceipt
            try requireCurrentVisit(stamp)
            if settle { value = try await service.settle(original) } else { value = try await service.receipt(original) }
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            try resolve(value, record: record, service: service)
        } catch { if generation == stamp { phase = .unknown; issue = "friendRemoval.unknown" } }
    }
    public func invalidate() {
        generation &+= 1; currentRelationship = nil; review = nil; result = nil; busy = false; phase = .closed; issue = nil; changed()
        // Navigation, withdrawal and account changes never erase durable original identities.
    }
}
