import Foundation
import Observation

/// Explicit original-board owner; no approval issuer or generic route activation.
@MainActor @Observable public final class CityArrivalEvidenceRuntimeOwner {
    public let captured: RuntimeDependencyContext
    public let capturedRevision: UInt64
    public let board: CityReadBoard?
    public let approval: CityArrivalEvidenceApproval
    public private(set) var controller: CityArrivalEvidenceController?
    public private(set) var isRetired = false
    private let current: () -> RuntimeDependencyContext?
    private let revision: () -> UInt64
    private let selected: (RuntimeDependencyContext) -> CityArrivalEvidenceApproval?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, revision: UInt64, board: CityReadBoard?,
                approval: CityArrivalEvidenceApproval?, underlying: any HTTPTransport, journal: any OperationPendingJournal,
                current: @escaping () -> RuntimeDependencyContext?, currentRevision: @escaping () -> UInt64,
                selected: @escaping (RuntimeDependencyContext) -> CityArrivalEvidenceApproval? = { _ in nil },
                unauthorized: @escaping () -> Void = {}) throws {
        guard let approval,
              context.role == context.session.role, approval.matches(context),
              let live = current(), ContentDraftContextFence.matches(context, live), context.session == live.session,
              currentRevision() == revision, selected(live) === approval else { throw CityArrivalEvidenceError.disabled }
        switch approval.audience {
        case .player(let region): guard let board, board.valid, board.regionId == region else { throw CityArrivalEvidenceError.disabled }
        case .merchant: guard board == nil else { throw CityArrivalEvidenceError.disabled }
        }
        captured = context; capturedRevision = revision; self.board = board; self.approval = approval
        self.current = current; self.revision = currentRevision; self.selected = selected
        let transport = CityArrivalEvidenceTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard let self, self.isCurrent else { return nil }; return self.captured },
            selected: { [weak self] context, audience in guard let self, self.isCurrent, audience == self.approval.audience else { return nil }; return self.selected(context) })
        let service = CityArrivalEvidenceService(approval: approval, transport: transport, board: board)
        controller = CityArrivalEvidenceController(audience: approval.audience, service: service, journal: journal, unauthorized: { [weak self] in
            guard let self, self.isCurrent else { return }; unauthorized(); self.retire()
        })
        let delay = max(0, min(86400, approval.expiresAt.timeIntervalSinceNow))
        expiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)); try Task.checkCancellation() } catch { return }
            self?.retire()
        }
    }
    deinit { expiry?.cancel() }
    public var isCurrent: Bool {
        guard !isRetired, revision() == capturedRevision, let live = current(),
              ContentDraftContextFence.matches(captured, live), captured.session == live.session,
              live.role == live.session.role, selected(live) === approval else { return false }
        return approval.matches(live)
    }
    public func synchronize() { if !isCurrent { retire() } }
    public func retire() { isRetired = true; controller?.invalidate(); expiry?.cancel(); expiry = nil }
}
