import Foundation

/// Owner-wide durable original-request recovery, independent of an existing conversation or list row.
@MainActor public final class NativeBlacklistFlow {
    public enum Phase: Equatable { case closed, loading, ready, reviewing, submitting, unknown, resolved, failed }
    public private(set) var phase: Phase = .closed
    public private(set) var items: [NativeBlacklistItem] = []
    public private(set) var nextCursor: Int64?
    public private(set) var selected: NativeBlacklistItem?
    public private(set) var review: NativeBlacklistCommand?
    public private(set) var pending: OperationPendingRecord?
    public private(set) var result: NativeBlacklistReceipt?
    public private(set) var current: NativeBlacklistCurrent?
    public private(set) var issue: String?
    public private(set) var busy = false
    public var onChange: (() -> Void)?
    public var onResolved: (() -> Void)?
    private let service: (any NativeBlacklistServing)?
    private let journal: any OperationPendingListing
    private let ownerKey: String
    private var generation: UInt64 = 0
    private var serverWriteEnabled = false
    private var authorityRetired = false
    private var authorityTask: Task<Void, Never>?
    private static let prefix = "native-blacklist.v1."
    public init(service: (any NativeBlacklistServing)?, journal: any OperationPendingListing, ownerKey: String) {
        self.service = service; self.journal = journal; self.ownerKey = ownerKey
        // Local grant/context observation only. No presence, subscription or network polling.
        authorityTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self, self.validateAuthority() else { return }
            }
        }
    }
    deinit { authorityTask?.cancel() }
    public var isCurrent: Bool { !authorityRetired && service?.isCurrent == true }
    @discardableResult public func validateAuthority() -> Bool {
        guard isCurrent else {
            if !authorityRetired { authorityRetired = true; invalidate() }
            return false
        }
        return true
    }
    public var canReview: Bool { isCurrent && phase == .ready && !busy && pending == nil && serverWriteEnabled && service?.canWrite == true }
    public var canConfirm: Bool { isCurrent && phase == .reviewing && review != nil && !busy && pending == nil && serverWriteEnabled && service?.canWrite == true }
    public var canRecover: Bool { !busy && pendingCommand != nil && isCurrent }
    public var canSettle: Bool { canRecover && service?.canSettle == true }
    public var pendingCommand: NativeBlacklistCommand? { pending.flatMap { try? command($0) } }
    /// A synchronous presentation callback may close this visit before the service starts.
    /// Preserve any original journal entry; never dispatch from that retired visit.
    private func requireCurrentVisit(_ stamp: UInt64) throws {
        guard generation == stamp, isCurrent, !Task.isCancelled else { throw NativeFriendFailure.staleSession }
    }
    private func changed() { onChange?() }
    private func key(_ value: NativeBlacklistCommand) -> String { Self.prefix + "\(value.peerID).\(value.expectedBlockID)" }
    private func command(_ record: OperationPendingRecord) throws -> NativeBlacklistCommand {
        guard record.ownerKey == ownerKey, record.targetKey.hasPrefix(Self.prefix), record.acknowledgedSteps == 0 else { throw NativeBlacklistFailure.invalid }
        let parts = record.targetKey.dropFirst(Self.prefix.count).split(separator: ".")
        guard parts.count == 2, let peer = Int64(parts[0]), peer > 0, peer != service?.viewerID,
              let block = Int64(parts[1]), block > 0 else { throw NativeBlacklistFailure.invalid }
        return .init(requestID: record.operationID, peerID: peer, expectedBlockID: block)
    }
    private func findPending() throws -> OperationPendingRecord? {
        let rows = try journal.pendingRecords(ownerKey: ownerKey).filter { $0.targetKey.hasPrefix(Self.prefix) }
        for row in rows { _ = try command(row) }
        return rows.first
    }
    private func finish(_ service: any NativeBlacklistServing, stamp: UInt64) {
        guard generation == stamp else { return }
        if !validateAuthority() { return }
        busy = false; changed()
    }
    private func accept(_ value: NativeBlacklistPage, cursor: Int64, append: Bool) throws {
        guard let service, value.valid(viewer: service.viewerID, cursor: cursor) else { throw NativeBlacklistFailure.invalid }
        if append {
            guard Set(items.map(\.peerID)).isDisjoint(with: Set(value.items.map(\.peerID))),
                  Set(items.map(\.blockID)).isDisjoint(with: Set(value.items.map(\.blockID))) else { throw NativeBlacklistFailure.invalid }
            items += value.items
        } else { items = value.items }
        nextCursor = value.nextCursor; serverWriteEnabled = value.writeEnabled
    }
    public func load() async {
        guard !busy else { return }
        generation &+= 1; let stamp = generation
        items = []; nextCursor = nil; selected = nil; review = nil; result = nil; current = nil; pending = nil; issue = nil; serverWriteEnabled = false
        guard let service, validateAuthority() else { phase = .closed; changed(); return }
        do { pending = try findPending() }
        catch { phase = .failed; issue = "blacklist.storageFailure"; changed(); return }
        if pending != nil { phase = .unknown; changed(); return }
        busy = true; phase = .loading; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let page = try await service.page(cursor: 0)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            try accept(page, cursor: 0, append: false); phase = .ready
        } catch { if generation == stamp { phase = .failed; issue = "blacklist.readFailure" } }
    }
    public func loadMore() async {
        guard phase == .ready, !busy, pending == nil, let cursor = nextCursor, let service, isCurrent else { return }
        let stamp = generation; busy = true; issue = nil; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let page = try await service.page(cursor: cursor)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            try accept(page, cursor: cursor, append: true)
        } catch { if generation == stamp { issue = "blacklist.moreFailure" } }
    }
    public func reviewUnblock(_ item: NativeBlacklistItem) async {
        guard canReview, items.contains(item), let service else { return }
        let stamp = generation; busy = true; issue = nil; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let fresh = try await service.current(peerID: item.peerID)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            guard fresh.valid(viewer: service.viewerID, peer: item.peerID), fresh.blocked, fresh.blockID == item.blockID else {
                phase = .failed; issue = "blacklist.changed"; items = []; nextCursor = nil; return
            }
            current = fresh; selected = item; review = .init(peerID: item.peerID, expectedBlockID: item.blockID); phase = .reviewing
        } catch { if generation == stamp { issue = "blacklist.readFailure" } }
    }
    public func cancelReview() {
        guard !busy, pending == nil else { return }; review = nil; selected = nil; current = nil; phase = .ready; changed()
    }
    public func confirm() async {
        guard let expected = review else { return }
        await confirm(expected: expected)
    }
    /// The visible confirmation owns this exact command, never a later review.
    public func confirm(expected: NativeBlacklistCommand) async {
        guard canConfirm, let original = review, original == expected, let service else { return }
        let stamp = generation, record = OperationPendingRecord(operationID: original.requestID, ownerKey: ownerKey, targetKey: key(original))
        do {
            // MainActor fence across concurrent screens, before any suspension or network dispatch.
            if let existing = try findPending() { pending = existing; review = nil; selected = nil; current = nil; items = []; phase = .unknown; changed(); return }
            try journal.write(record); pending = record
        } catch { issue = "blacklist.storageFailure"; changed(); return }
        review = nil; selected = nil; current = nil; items = []; nextCursor = nil
        busy = true; phase = .submitting; issue = nil; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let receipt = try await service.unblock(original)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            try await resolve(receipt, record: record, service: service, stamp: stamp)
        } catch NativeBlacklistFailure.notSent {
            guard generation == stamp else { return }
            do { try clear(record, terminal: false); phase = .failed; issue = "blacklist.notSent" }
            catch { phase = .unknown; issue = "blacklist.storageFailure" }
        } catch { if generation == stamp { phase = .unknown; issue = "blacklist.unknown" } }
    }
    private func clear(_ record: OperationPendingRecord, terminal: Bool) throws {
        if let saved = try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) {
            guard saved == record else { throw NativeBlacklistFailure.unknown }; try journal.clear(record)
        } else if !terminal { throw NativeBlacklistFailure.unknown }
        pending = nil
    }
    private func resolve(_ receipt: NativeBlacklistReceipt, record: OperationPendingRecord, service: any NativeBlacklistServing, stamp: UInt64) async throws {
        let original = try command(record)
        guard receipt.matches(original, viewer: service.viewerID), ["APPLIED", "REJECTED"].contains(receipt.outcome) else { throw NativeBlacklistFailure.unknown }
        try clear(record, terminal: true); result = receipt; current = nil; phase = .resolved; issue = nil
        onResolved?()
        // Never infer today's state from a historical receipt, nor rewrite the receipt after a re-block.
        guard generation == stamp, isCurrent, !Task.isCancelled else { return }
        await readback(peer: original.peerID, service: service, stamp: stamp)
    }
    private func readback(peer: Int64, service: any NativeBlacklistServing, stamp: UInt64) async {
        current = nil; items = []; nextCursor = nil
        do {
            try requireCurrentVisit(stamp)
            let fresh = try await service.current(peerID: peer)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            guard fresh.valid(viewer: service.viewerID, peer: peer) else { throw NativeBlacklistFailure.invalid }; current = fresh
        } catch { if generation == stamp { issue = "blacklist.currentFailure" } }
        guard generation == stamp, isCurrent, !Task.isCancelled else { return }
        do {
            try requireCurrentVisit(stamp)
            let page = try await service.page(cursor: 0)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            try accept(page, cursor: 0, append: false)
        } catch { if generation == stamp { issue = current == nil ? "blacklist.currentFailure" : "blacklist.listReadbackFailure" } }
    }
    public func retryReadback() async {
        guard !busy, phase == .resolved, let result, let service, isCurrent else { return }
        let stamp = generation; busy = true; issue = nil; changed(); defer { finish(service, stamp: stamp) }
        await readback(peer: result.peerID, service: service, stamp: stamp)
    }
    public func recover() async { await recoverOrSettle(confirmed: nil) }
    public func settleOriginal(confirmed: NativeBlacklistCommand) async { await recoverOrSettle(confirmed: confirmed) }
    private func recoverOrSettle(confirmed: NativeBlacklistCommand?) async {
        guard canRecover, let record = pending, let original = try? command(record), let service else { return }
        guard confirmed == nil || (canSettle && confirmed == original) else { return }
        let stamp = generation; busy = true; issue = nil; changed(); defer { finish(service, stamp: stamp) }
        do {
            let receipt: NativeBlacklistReceipt
            try requireCurrentVisit(stamp)
            if confirmed != nil { receipt = try await service.settle(original) } else { receipt = try await service.receipt(original) }
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            try await resolve(receipt, record: record, service: service, stamp: stamp)
        } catch { if generation == stamp { phase = .unknown; issue = "blacklist.unknown" } }
    }
    public func invalidate() {
        generation &+= 1; items = []; nextCursor = nil; selected = nil; review = nil; pending = nil; result = nil; current = nil
        busy = false; serverWriteEnabled = false; phase = .closed; issue = nil; changed()
        // Only in-memory presentation is erased. Durable originals survive close/background/revocation.
    }
}
