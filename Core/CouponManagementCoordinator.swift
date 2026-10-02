import Foundation

public struct CouponManagementReview: Equatable, Identifiable {
    public enum Intent: Equatable { case publish(CouponManagementDraft), stop(CouponDefinition) }
    public let id: UUID
    public let intent: Intent
    public let request: CouponManagementRequest
    fileprivate let session: CouponManagementSession
    fileprivate let generation: UInt64
    fileprivate let permission: CouponPublisherPermission?
    fileprivate var resource: String {
        switch intent { case .publish: return "publish"; case .stop(let row): return "stop:\(row.id.value)" }
    }
}
@MainActor public final class CouponManagementCoordinator {
    private let adapter: CouponManagementAdapter
    private let authorizer: any CouponPublisherAuthorizing
    private let locks: any CouponManagementLocking
    private let currentSession: () -> CouponManagementSession?
    private var captured: CouponManagementSession?
    private var generation: UInt64 = 0
    private var readGeneration: UInt64 = 0
    public private(set) var draft = CouponManagementDraft()
    public private(set) var rows: [CouponDefinition] = []
    public private(set) var review: CouponManagementReview?
    public private(set) var busy = false
    public private(set) var loading = false
    public private(set) var issue: CouponManagementError?
    public private(set) var serverMessage: String?
    public private(set) var simulated = false
    public private(set) var acknowledged = false
    public var session: CouponManagementSession? { currentSession() }
    public var canSimulate: Bool { adapter.canSimulate }
    public var canSubmit: Bool { adapter.canSubmit }
    public var canRead: Bool { adapter.canRead }
    public init(adapter: CouponManagementAdapter, authorizer: any CouponPublisherAuthorizing, locks: any CouponManagementLocking, currentSession: @escaping () -> CouponManagementSession?) {
        self.adapter = adapter; self.authorizer = authorizer; self.locks = locks; self.currentSession = currentSession
    }
    public func synchronize() {
        guard captured != currentSession() else { return }
        captured = currentSession(); generation &+= 1; readGeneration &+= 1
        draft = .init(); rows = []; review = nil; busy = false; loading = false; issue = nil; serverMessage = nil; simulated = false; acknowledged = false
    }
    private func active(_ session: CouponManagementSession, _ stamp: UInt64) -> Bool {
        captured == session && currentSession() == session && generation == stamp && !Task.isCancelled
    }
    public func change(_ value: CouponManagementDraft) {
        synchronize(); guard !busy else { return }
        draft = value; generation &+= 1; review = nil; issue = nil; serverMessage = nil; simulated = false; acknowledged = false
    }
    public func cancelReview() { generation &+= 1; review = nil; busy = false }
    public func leave() { generation &+= 1; readGeneration &+= 1; review = nil; rows = []; loading = false; busy = false }
    public func discardDraft() { synchronize(); guard !busy else { return }; draft = .init(); cancelReview() }
    public func load(keyword: String? = nil) async {
        synchronize(); guard let session = captured else { issue = .signedOut; return }
        readGeneration &+= 1; let sequence = readGeneration
        loading = true; rows = []; issue = nil
        do {
            let result = try await adapter.published(session: session, keyword: keyword)
            guard currentSession() == session, captured == session, !Task.isCancelled, sequence == readGeneration else { return }
            rows = result; loading = false
        } catch {
            guard currentSession() == session, captured == session, !Task.isCancelled, sequence == readGeneration else { return }
            loading = false; issue = (error as? CouponManagementError) ?? .unavailable
        }
    }
    private func unlocked(_ session: CouponManagementSession, resource: String) throws {
        guard try locks.pending(ownerKey: session.ownerKey, resource: resource) == nil else { throw CouponManagementError.locked }
    }
    public func preparePublish() async {
        synchronize(); guard !busy, let session = captured else { issue = .signedOut; return }
        generation &+= 1; let stamp = generation; let snapshot = draft; review = nil; busy = true; issue = nil; serverMessage = nil
        do {
            let request = try CouponManagementContract.publish(snapshot)
            try unlocked(session, resource: "publish")
            let permission = try await authorizer.freshPermission(session: session)
            guard active(session, stamp) else { return }
            guard permission.mayPublish, !permission.revision.isEmpty else { throw CouponManagementError.forbidden }
            review = .init(id: UUID(), intent: .publish(snapshot), request: request, session: session, generation: stamp, permission: permission)
            busy = false
        } catch { if active(session, stamp) { busy = false; issue = (error as? CouponManagementError) ?? .unavailable } }
    }
    public func prepareStop(_ id: CouponDefinitionID) async {
        synchronize(); guard !busy, let session = captured else { issue = .signedOut; return }
        generation &+= 1; let stamp = generation; review = nil; busy = true; issue = nil; serverMessage = nil
        do {
            try unlocked(session, resource: "stop:\(id.value)")
            let owned = try await adapter.published(session: session)
            guard active(session, stamp) else { return }
            guard let row = owned.first(where: { $0.id == id }), row.state.canStop else { throw CouponManagementError.forbidden }
            rows = owned
            review = .init(id: UUID(), intent: .stop(row), request: CouponManagementContract.stop(id), session: session, generation: stamp, permission: nil)
            busy = false
        } catch { if active(session, stamp) { busy = false; issue = (error as? CouponManagementError) ?? .unavailable } }
    }
    public func confirm(_ accepted: CouponManagementReview) async {
        synchronize()
        guard !busy, review == accepted, accepted.session == captured, accepted.generation == generation else { issue = .changed; return }
        guard adapter.canSubmit else { issue = .unavailable; return }
        let session = accepted.session; let stamp = generation
        busy = true; issue = nil; serverMessage = nil
        var pending: CouponManagementPending?
        do {
            try unlocked(session, resource: accepted.resource)
            switch accepted.intent {
            case .publish(let value):
                guard draft == value else { throw CouponManagementError.changed }
                let fresh = try await authorizer.freshPermission(session: session)
                guard active(session, stamp) else { return }
                guard fresh == accepted.permission, fresh.mayPublish else { throw CouponManagementError.changed }
            case .stop(let baseline):
                let owned = try await adapter.published(session: session)
                guard active(session, stamp) else { return }
                guard let fresh = owned.first(where: { $0.id == baseline.id }), fresh == baseline, fresh.state.canStop else { throw CouponManagementError.changed }
            }
            guard active(session, stamp), review == accepted else { return }
            let record = CouponManagementPending(operationID: accepted.id, ownerKey: session.ownerKey, resource: accepted.resource, request: accepted.request, createdAt: Date())
            try locks.acquire(record); pending = record; review = nil
            let outcome = await adapter.submit(accepted.request, session: session)
            // If the account/epoch/navigation changes during dispatch, retain the durable record.
            guard active(session, stamp) else { return }
            switch outcome {
            case .simulated(let message):
                try locks.release(record); pending = nil; simulated = true; serverMessage = message
                if case .publish = accepted.intent { draft = .init() }
            case .acknowledged(let message):
                try locks.release(record); pending = nil; acknowledged = true; serverMessage = message
                if case .publish = accepted.intent { draft = .init() }
            case .notSent: try locks.release(record); pending = nil; issue = .unavailable
            case .rejected(let message): try locks.release(record); pending = nil; serverMessage = message
            case .unknown: issue = .locked
            }
            busy = false
            // Both successful and failed stops refresh state. A read can never clear the lock.
            if case .stop = accepted.intent { await refreshAfterMutation(session: session, stamp: stamp) }
            else if simulated || acknowledged { await refreshAfterMutation(session: session, stamp: stamp) }
        } catch {
            guard active(session, stamp) else { return }
            busy = false; review = nil
            issue = pending == nil ? ((error as? CouponManagementError) ?? .storage) : .locked
        }
    }
    private func refreshAfterMutation(session: CouponManagementSession, stamp: UInt64) async {
        readGeneration &+= 1; let sequence = readGeneration
        do {
            let result = try await adapter.published(session: session)
            guard active(session, stamp), sequence == readGeneration else { return }; rows = result
        } catch {
            guard active(session, stamp), sequence == readGeneration else { return }; rows = []
            if issue == nil { issue = (error as? CouponManagementError) ?? .unavailable }
        }
    }
    // No claim, reactivation, edit-after-publication, deletion, receipt lookup, issuance or redemption route:
    // none is established by coupon_api.dart's author/management contract.
}
