import Foundation
import Observation

/// One explicit aggregate command, original receipt only. A missing/unknown receipt never authorizes resend or settlement.
@MainActor @Observable public final class NativeProgressPrivacyFlow {
    public enum Phase: Equatable { case closed, loading, ready, reviewing, saving, unknown, unavailable }
    @ObservationIgnored private let service: NativeProgressPrivacyService?
    @ObservationIgnored private let journal: any OperationPendingListing
    @ObservationIgnored private let ownerKey: String
    private var rawPhase: Phase = .closed
    private var rawSnapshot: NativeProgressPrivacySnapshot?
    private var review: NativeProgressPrivacyCommand?
    private var pending: OperationPendingRecord?
    private var active = false
    private var generation: UInt64 = 0
    private var busy = false
    private var rawResult: String?
    public enum ResultPresentation: Equatable { case notSent, applied, conflict }
    private var rawResultPresentation: ResultPresentation?
    @ObservationIgnored private var authorityTask: Task<Void, Never>?
    private static let prefix = "native-progress-privacy.v1."
    public var isCurrent: Bool { active && service?.isCurrent == true }
    public var phase: Phase { isCurrent ? rawPhase : .closed }
    public var snapshot: NativeProgressPrivacySnapshot? { isCurrent ? rawSnapshot : nil }
    public var reviewedScope: NativeProgressPrivacyScope? { isCurrent ? review?.aggregate : nil }
    /// The immutable command shown by a confirmation; a delayed tap cannot authorize a replacement.
    public var reviewedCommand: NativeProgressPrivacyCommand? { isCurrent ? review : nil }
    public var requestID: String? { isCurrent ? pending?.operationID.uuidString : nil }
    public var pendingLabel: String? {
        guard isCurrent, let pending, let value = try? identity(pending) else { return nil }
        return value.target.kind == .user ? "本人总览隐私" : "频道 \(value.target.id) 总览隐私"
    }
    public var result: String? { isCurrent ? rawResult : nil }
    /// Display-only projection. Original strings remain compatible; no localized text is parsed as state.
    public var resultPresentation: ResultPresentation? { isCurrent ? rawResultPresentation : nil }
    public var pendingTarget: NativeProgressPrivacyTarget? {
        guard isCurrent, let pending else { return nil }
        return (try? identity(pending))?.target
    }
    /// Current write-authority facts only. Busy/review/pending locks are not permission denials.
    public struct WriteAuthorityPresentation: Equatable {
        public let independentWriteAllowed: Bool
        public let snapshotWriteAllowed: Bool
        public var isReadOnly: Bool { !independentWriteAllowed || !snapshotWriteAllowed }
    }
    /// No snapshot means no current authority conclusion; an old receipt never supplies this value.
    public var writeAuthorityPresentation: WriteAuthorityPresentation? {
        guard isCurrent, let service, let snapshot = rawSnapshot else { return nil }
        return .init(independentWriteAllowed: service.canWrite, snapshotWriteAllowed: snapshot.canWrite)
    }
    public var canEdit: Bool { isCurrent && !busy && pending == nil && rawPhase == .ready && rawSnapshot?.canWrite == true && service?.canWrite == true }
    public var canConfirm: Bool { isCurrent && !busy && pending == nil && review != nil && rawPhase == .reviewing && service?.canWrite == true }
    public var canRecover: Bool { isCurrent && !busy && pending != nil }
    public var canRefresh: Bool { isCurrent && !busy }
    public init(service: NativeProgressPrivacyService?, journal: any OperationPendingListing, ownerKey: String) {
        self.service = service; self.journal = journal; self.ownerKey = ownerKey
        authorityTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self else { return }
                if self.active && self.service?.isCurrent != true { self.deactivate(); return }
            }
        }
    }
    deinit { authorityTask?.cancel() }
    private func ownedPending() throws -> OperationPendingRecord? {
        do {
            let records = try journal.pendingRecords(ownerKey: ownerKey).filter { $0.targetKey.hasPrefix(Self.prefix) }
            NativeProgressPrivacyInvalidation.restore(owner: ownerKey, requests: Set(records.map(\.operationID)))
            return records.first
        } catch { NativeProgressPrivacyInvalidation.restore(owner: ownerKey, requests: nil); throw error }
    }
    private func identity(_ record: OperationPendingRecord) throws -> (target: NativeProgressPrivacyTarget, hash: String) {
        guard record.ownerKey == ownerKey, record.targetKey.hasPrefix(Self.prefix) else { throw NativeProgressPrivacyFailure.invalid }
        let parts = record.targetKey.dropFirst(Self.prefix.count).split(separator: ".")
        guard parts.count == 3, let kind = NativeProgressPrivacyTarget.Kind(rawValue: String(parts[0])), let id = Int64(parts[1]),
              String(parts[2]).range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw NativeProgressPrivacyFailure.invalid }
        return (try NativeProgressPrivacyTarget(kind: kind, id: id), String(parts[2]))
    }
    public func activate() async {
        active = true
        await refresh()
    }
    public func refresh() async {
        guard !busy else { return }
        generation &+= 1; let stamp = generation; review = nil; rawSnapshot = nil; rawResult = nil; rawResultPresentation = nil
        do { pending = try ownedPending() } catch { rawPhase = .unavailable; return }
        guard isCurrent, let service else { rawPhase = .closed; return }
        busy = true; rawPhase = .loading
        defer { if generation == stamp { busy = false } }
        do {
            let value = try await service.read()
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            rawSnapshot = value; rawPhase = pending == nil ? .ready : .unknown
        } catch { fail(stamp) }
    }
    public func prepare(_ scope: NativeProgressPrivacyScope) {
        guard canEdit, let value = rawSnapshot, scope != value.aggregate,
              let command = try? NativeProgressPrivacyCommand(snapshot: value, aggregate: scope) else { return }
        review = command; rawPhase = .reviewing; rawResult = nil; rawResultPresentation = nil
    }
    public func cancelReview() { guard isCurrent, !busy, pending == nil else { return }; review = nil; rawPhase = rawSnapshot == nil ? .unavailable : .ready }
    public func confirm() async {
        guard let expected = reviewedCommand else { return }
        await confirm(expected: expected)
    }
    /// Bind consent to the displayed UUID, target, desired scope and original CAS version.
    public func confirm(expected: NativeProgressPrivacyCommand) async {
        guard canConfirm, let command = review, command.requestID == expected.requestID,
              command.target == expected.target, command.aggregate == expected.aggregate,
              command.expectedUpdatedAt == expected.expectedUpdatedAt,
              command.expectedRevision == expected.expectedRevision, let service else { return }
        let stamp = generation
        let record: OperationPendingRecord
        do {
            if let existing = try ownedPending() { pending = existing; review = nil; rawPhase = .unknown; return }
            record = OperationPendingRecord(operationID: command.requestID, ownerKey: ownerKey,
                targetKey: Self.prefix + command.target.kind.rawValue + ".\(command.target.id)." + (try command.fingerprint()))
            try journal.write(record); pending = record
            guard try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) == record else { throw NativeProgressPrivacyFailure.unknown }
        } catch { review = nil; rawSnapshot = nil; rawPhase = .unknown; return }
        review = nil; rawSnapshot = nil; rawResult = nil; rawResultPresentation = nil; busy = true; rawPhase = .saving
        // A response may be lost after commit: invalidate before forwarding, not only after success.
        NativeProgressPrivacyInvalidation.pending(owner: ownerKey, request: record.operationID)
        defer { if generation == stamp { busy = false } }
        do {
            let proof = try await service.write(command)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            try resolve(proof, record: record, actor: service.actorID)
            await readAfterResult(service, stamp: stamp)
        } catch NativeFriendFailure.notSent {
            // Only the original transport's pre-forward failure is known not to have executed.
            do { try clear(record); if generation == stamp { rawPhase = .unavailable; rawResult = "请求未发送；请重新读取当前设置。"; rawResultPresentation = .notSent } }
            catch { fail(stamp) }
        } catch { fail(stamp) }
    }
    public func recover() async {
        guard canRecover, let record = pending, let service else { return }
        let stamp = generation; busy = true; rawSnapshot = nil; rawResult = nil; rawResultPresentation = nil; rawPhase = .loading
        defer { if generation == stamp { busy = false } }
        do {
            let proof = try await service.receipt(record.operationID)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            try resolve(proof, record: record, actor: service.actorID)
            await readAfterResult(service, stamp: stamp)
        } catch { fail(stamp) }
    }
    private func resolve(_ proof: NativeProgressPrivacyReceipt, record: OperationPendingRecord, actor: Int64) throws {
        let value = try identity(record)
        guard proof.actorID == actor, UUID(uuidString: proof.requestID) == record.operationID, proof.kind == value.target.kind,
              proof.scopeID == value.target.id, proof.payloadHash == value.hash, ["APPLIED", "REJECTED"].contains(proof.outcome),
              value.target.kind != .user || value.target.id == actor else { throw NativeProgressPrivacyFailure.unknown }
        if proof.outcome == "APPLIED" {
            guard proof.reason == "AGGREGATE_PRIVACY_SAVED", proof.appliedUpdatedAt.map(NativeProgressPrivacyValidation.timestamp) == true else { throw NativeProgressPrivacyFailure.unknown }
            if value.target.kind == .user { guard proof.appliedRevision == nil else { throw NativeProgressPrivacyFailure.unknown } }
            else { guard let revision = proof.appliedRevision, revision > 0, revision <= Int(Int32.max) else { throw NativeProgressPrivacyFailure.unknown } }
            NativeProgressPrivacyInvalidation.invalidate()
        } else {
            guard proof.reason == "PRIVACY_CONFLICT", proof.appliedUpdatedAt == nil, proof.appliedRevision == nil else { throw NativeProgressPrivacyFailure.unknown }
        }
        try clear(record)
        rawResult = proof.outcome == "APPLIED" ? "原请求已保存。下方重新读取当前设置，不把旧回执当现行授权。" : "原请求因版本冲突未修改设置。请查看当前值后重新确认。"
        rawResultPresentation = proof.outcome == "APPLIED" ? .applied : .conflict
        pending = try ownedPending()
    }
    private func clear(_ record: OperationPendingRecord) throws {
        guard try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) == record else { throw NativeProgressPrivacyFailure.unknown }
        try journal.clear(record); pending = nil
        NativeProgressPrivacyInvalidation.resolved(owner: ownerKey, request: record.operationID)
    }
    private func readAfterResult(_ service: NativeProgressPrivacyService, stamp: UInt64) async {
        do {
            let value = try await service.read()
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            rawSnapshot = value; rawPhase = pending == nil ? .ready : .unknown
        } catch { fail(stamp) }
    }
    private func fail(_ stamp: UInt64) {
        guard generation == stamp else { return }
        rawSnapshot = nil; review = nil; rawPhase = pending == nil ? .unavailable : .unknown
    }
    public func deactivate() {
        active = false; generation &+= 1; busy = false; rawSnapshot = nil; review = nil; rawResult = nil; rawResultPresentation = nil; rawPhase = .closed
        // Keep only original actor/deployment-scoped identity and hash for restart/revocation recovery.
    }
}
