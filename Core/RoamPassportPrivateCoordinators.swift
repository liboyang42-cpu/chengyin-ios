import Foundation
import Observation

/// Shared issue vocabulary for the three private tools. `message` is the server's refusal text, shown verbatim.
public enum RoamPrivateToolIssue: Equatable {
    case readFailed(APIError?), signInRequired, notConfigured, changedContext
    case writesDisabled, outcomeUnknown, rejected(String?), invalidDraft, pendingFirst, expired
    static func from(_ error: Error) -> RoamPrivateToolIssue {
        if let failure = error as? RoamPrivateWriteError {
            switch failure {
            case .rejected(let message): return .rejected(message)
            case .outcomeUnknown: return .outcomeUnknown
            case .writesDisabled: return .writesDisabled
            case .pendingMismatch: return .pendingFirst
            case .changedContext: return .changedContext
            case .invalidDraft: return .invalidDraft
            }
        }
        guard let api = error as? APIError else { return .readFailed(nil) }
        switch api {
        case .unauthorized: return .signInRequired
        case .notConfigured: return .notConfigured
        default: return .readFailed(api)
        }
    }
}

// MARK: 时光胶囊

@MainActor @Observable public final class RoamCapsuleCoordinator {
    public enum Phase: Equatable { case idle, loading, ready, failed, sending }
    public private(set) var phase: Phase = .idle
    public private(set) var items: [RoamCapsule] = []
    public private(set) var hasMore = false
    public private(set) var opened: RoamCapsule?
    public private(set) var deleted = false
    public private(set) var issue: RoamPrivateToolIssue?
    /// The draft awaiting explicit confirmation. Confirming dispatches exactly this value.
    public private(set) var review: RoamCapsuleDraft?
    public private(set) var deleteReview: String?
    private var nextBeforeID: String?
    private let tools: any RoamPrivateToolsServing
    private let owner: RoamExperienceIdentity?
    private var generation = 0
    public init(tools: any RoamPrivateToolsServing) { self.tools = tools; owner = tools.identity }
    public var pending: RoamCapsuleDraft? { tools.identity == owner ? tools.pendingCapsule : nil }
    /// Unconfirmed request ID, including a journal-restored one whose draft no longer
    /// exists after a restart. It locks new creates but can never rebuild a draft.
    public var pendingRequestID: String? { tools.identity == owner ? tools.unresolvedCapsuleRequestID : nil }
    public var isBusy: Bool { phase == .loading || phase == .sending }
    public var canWrite: Bool { tools.allowsWrites && tools.identity == owner && owner != nil }
    private func live() -> Bool { owner != nil && tools.identity == owner }
    private func reset() { generation += 1; items = []; hasMore = false; nextBeforeID = nil; opened = nil; review = nil; deleteReview = nil; phase = .idle }

    /// First page; `beforeID` reads the next page, which replaces the visible rows (mini-program `next`).
    public func load(more: Bool = false) async {
        guard live() else { reset(); issue = owner == nil ? .signInRequired : .changedContext; return }
        guard !isBusy else { return }
        generation += 1; let ticket = generation
        let cursor = more ? nextBeforeID : nil
        phase = .loading; issue = nil
        if !more { opened = nil; deleted = false }
        do {
            let page = try await tools.capsules(beforeID: cursor)
            guard ticket == generation, live() else { return }
            items = page.items; hasMore = page.hasMore; nextBeforeID = page.nextBeforeID; phase = .ready
        } catch {
            guard ticket == generation, live(), !(error is CancellationError) else { return }
            if !more { items = []; hasMore = false }
            issue = .from(error); phase = .failed
        }
    }
    /// Locked capsules never fetch content; only an OPEN row is read in detail.
    public func open(_ capsule: RoamCapsule) async {
        guard capsule.state == .open, live(), !isBusy else { return }
        generation += 1; let ticket = generation
        phase = .loading; issue = nil
        do {
            let value = try await tools.capsule(id: capsule.id)
            guard ticket == generation, live() else { return }
            opened = value.state == .open ? value : nil; phase = .ready
            if value.state != .open { await load() }
        } catch {
            guard ticket == generation, live(), !(error is CancellationError) else { return }
            issue = .from(error); phase = .failed
        }
    }
    /// 收好了 / 返回列表: forget the shown content and reread metadata.
    public func closeOpened() async { opened = nil; deleted = false; await load() }

    public func prepareCreate(body: String, unlockDate: String) {
        guard !isBusy else { return }
        guard canWrite else { issue = tools.allowsWrites ? .changedContext : .writesDisabled; return }
        guard pending == nil, pendingRequestID == nil else { issue = .pendingFirst; return }
        let draft = RoamCapsuleDraft(body: body, unlockDate: unlockDate)
        do { try draft.validate(now: tools.now); review = draft; issue = nil } catch { issue = .invalidDraft }
    }
    public func cancelReview() { review = nil }
    /// Explicit confirmation: the reviewed draft becomes the pending request before dispatch.
    public func confirmCreate() async -> Bool {
        guard let review, canWrite, !isBusy, pending == nil, pendingRequestID == nil else { return false }
        tools.pendingCapsule = review; self.review = nil
        return await dispatch(review)
    }
    /// 用原内容重试: the same request ID and payload, never a new draft.
    public func retryPending() async -> Bool {
        guard let pending, canWrite, !isBusy else { return false }
        return await dispatch(pending)
    }
    private func dispatch(_ draft: RoamCapsuleDraft) async -> Bool {
        generation += 1; let ticket = generation
        phase = .sending; issue = nil
        do {
            _ = try await tools.createCapsule(draft)
            guard ticket == generation, live() else { return false }
            if tools.pendingCapsule == draft { tools.pendingCapsule = nil }
            phase = .ready
            await load()
            return true
        } catch {
            guard ticket == generation, live() else { return false }
            if error is RoamPrivatePendingJournalError {
                // The minimal identity could not be made durable (or the journal is
                // unreadable), so nothing was sent. The draft stays pending in memory
                // and the same original request can be attempted again unchanged.
                issue = .outcomeUnknown
                phase = .ready
                return false
            }
            let found = RoamPrivateToolIssue.from(error)
            switch found {
            case .rejected where !uncertain.contains(draft.requestID), .writesDisabled, .invalidDraft:
                // Only a refusal of a never-uncertain attempt releases the pending slot.
                if tools.pendingCapsule == draft { tools.pendingCapsule = nil }
                issue = found
            case .rejected:
                issue = found
            default:
                uncertain.insert(draft.requestID); issue = .outcomeUnknown
            }
            phase = .ready
            return false
        }
    }
    private var uncertain: Set<String> = []
    /// 核对上次封存: the receipt of the original request ID is the only proof of its outcome.
    public func verifyPending() async {
        // After a restart only the request ID survives; the receipt of that original ID
        // is still the only proof, and no draft is ever rebuilt from the ID alone.
        guard let requestID = pending?.requestID ?? pendingRequestID, live(), !isBusy else { return }
        let pending = self.pending
        generation += 1; let ticket = generation
        phase = .loading; issue = nil
        do {
            _ = try await tools.capsuleReceipt(requestID: requestID)
            guard ticket == generation, live() else { return }
            if let pending, tools.pendingCapsule == pending { tools.pendingCapsule = nil }
            phase = .ready
            await load()
        } catch {
            guard ticket == generation, live(), !(error is CancellationError) else { return }
            issue = .outcomeUnknown; phase = .ready
        }
    }
    public func prepareDelete() { guard canWrite, let opened, !isBusy else { return }; deleteReview = opened.id }
    public func cancelDelete() { deleteReview = nil }
    public func confirmDelete() async {
        guard let id = deleteReview, canWrite, !isBusy else { return }
        deleteReview = nil
        generation += 1; let ticket = generation
        phase = .sending; issue = nil
        do {
            _ = try await tools.deleteCapsule(id: id)
            guard ticket == generation, live() else { return }
            opened = nil; deleted = true; items.removeAll { $0.id == id }; phase = .ready
        } catch {
            guard ticket == generation, live() else { return }
            // Unknown deletes keep the opened capsule; rereading the list shows whether it is gone.
            issue = .from(error); phase = .ready
        }
    }
}

// MARK: 探索目标

@MainActor @Observable public final class RoamGoalsCoordinator {
    public enum Phase: Equatable { case idle, loading, ready, failed, sending }
    public private(set) var phase: Phase = .idle
    public private(set) var rows: [RoamExplorationGoal] = []
    public private(set) var hasMore = false
    public private(set) var detail: RoamExplorationGoal?
    public private(set) var issue: RoamPrivateToolIssue?
    public private(set) var review: RoamGoalDraft?
    public private(set) var cancelReview: String?
    private var nextBeforeID: String?
    private var uncertain: Set<String> = []
    private let tools: any RoamPrivateToolsServing
    private let owner: RoamExperienceIdentity?
    private var generation = 0
    public init(tools: any RoamPrivateToolsServing) { self.tools = tools; owner = tools.identity }
    public var pending: RoamGoalDraft? { tools.identity == owner ? tools.pendingGoal : nil }
    /// Unconfirmed request ID, including a journal-restored one whose draft no longer
    /// exists after a restart. It locks new creates but can never rebuild a draft.
    public var pendingRequestID: String? { tools.identity == owner ? tools.unresolvedGoalRequestID : nil }
    public var isBusy: Bool { phase == .loading || phase == .sending }
    public var canWrite: Bool { tools.allowsWrites && tools.identity == owner && owner != nil }
    public var periods: [RoamGoalPeriod] { RoamGoalPeriod.periods(now: tools.now) }
    public var today: String { RoamShanghaiCalendar.dateText(dayNumber: RoamShanghaiCalendar.dayNumber(now: tools.now)) }
    private func live() -> Bool { owner != nil && tools.identity == owner }

    /// Page 1 replaces; later pages append (mini-program `nextPage`).
    public func load(more: Bool = false) async {
        guard live() else { rows = []; detail = nil; issue = owner == nil ? .signInRequired : .changedContext; phase = .idle; return }
        guard !isBusy else { return }
        generation += 1; let ticket = generation
        phase = .loading; issue = nil
        do {
            let page = try await tools.goals(beforeID: more ? nextBeforeID : nil)
            guard ticket == generation, live() else { return }
            rows = more ? rows + page.items.filter { item in !rows.contains { $0.id == item.id } } : page.items
            hasMore = page.hasMore; nextBeforeID = page.nextBeforeID; phase = .ready
        } catch {
            guard ticket == generation, live(), !(error is CancellationError) else { return }
            if !more { rows = []; hasMore = false }
            issue = .from(error); phase = .failed
        }
    }
    public func open(_ id: String) async {
        guard live(), !isBusy else { return }
        generation += 1; let ticket = generation
        phase = .loading; issue = nil
        do {
            let value = try await tools.goal(id: id)
            guard ticket == generation, live() else { return }
            detail = value; phase = .ready
        } catch {
            guard ticket == generation, live(), !(error is CancellationError) else { return }
            issue = .from(error); phase = .ready
        }
    }
    public func closeDetail() { detail = nil }
    public func dismissIssue() { issue = nil }

    public func prepareCreate(metric: RoamGoalMetric, target: Int, startDate: String, endDateExclusive: String) {
        guard !isBusy else { return }
        guard canWrite else { issue = tools.allowsWrites ? .changedContext : .writesDisabled; return }
        guard pending == nil, pendingRequestID == nil else { issue = .pendingFirst; return }
        let draft = RoamGoalDraft(metric: metric, target: target, startDate: startDate, endDateExclusive: endDateExclusive)
        do { try draft.validate(now: tools.now); review = draft; issue = nil } catch { issue = .invalidDraft }
    }
    public func cancelCreateReview() { review = nil }
    public func confirmCreate() async -> Bool {
        guard let review, canWrite, !isBusy, pending == nil, pendingRequestID == nil else { return false }
        tools.pendingGoal = review; self.review = nil
        return await dispatch(review)
    }
    /// 以原操作重试
    public func retryPending() async -> Bool {
        guard let pending, canWrite, !isBusy else { return false }
        return await dispatch(pending)
    }
    private func dispatch(_ draft: RoamGoalDraft) async -> Bool {
        generation += 1; let ticket = generation
        phase = .sending; issue = nil
        do {
            let value = try await tools.createGoal(draft)
            guard ticket == generation, live() else { return false }
            if tools.pendingGoal == draft { tools.pendingGoal = nil }
            detail = value; phase = .ready
            await load()
            return true
        } catch {
            guard ticket == generation, live() else { return false }
            if error is RoamPrivatePendingJournalError {
                // Nothing was sent: the minimal identity could not be made durable (or
                // the journal is unreadable). The reviewed draft stays pending as-is.
                issue = .outcomeUnknown
                phase = .ready
                return false
            }
            let found = RoamPrivateToolIssue.from(error)
            switch found {
            case .rejected where !uncertain.contains(draft.requestID), .writesDisabled, .invalidDraft:
                // A refusal stays on the form so the player can change the dates; no retry of the same payload.
                if tools.pendingGoal == draft { tools.pendingGoal = nil }
                issue = found
            case .rejected:
                issue = found
            default:
                uncertain.insert(draft.requestID); issue = .outcomeUnknown
            }
            phase = .ready
            return false
        }
    }
    /// Receipt readback for the unconfirmed request.
    public func verifyPending() async {
        guard let requestID = pending?.requestID ?? pendingRequestID, live(), !isBusy else { return }
        let pending = self.pending
        generation += 1; let ticket = generation
        phase = .loading; issue = nil
        do {
            let value = try await tools.goalReceipt(requestID: requestID)
            guard ticket == generation, live() else { return }
            if let pending, tools.pendingGoal == pending { tools.pendingGoal = nil }
            detail = value; phase = .ready
            await load()
        } catch {
            guard ticket == generation, live(), !(error is CancellationError) else { return }
            issue = .outcomeUnknown; phase = .ready
        }
    }
    public func prepareCancel() { guard canWrite, let detail, detail.state.isCancellable, !isBusy else { return }; cancelReview = detail.id }
    public func keepGoal() { cancelReview = nil }
    /// 取消目标: one way on the server; a confirmed cancellation is never revived by a late response.
    public func confirmCancel() async {
        guard let id = cancelReview, canWrite, !isBusy else { return }
        cancelReview = nil
        generation += 1; let ticket = generation
        phase = .sending; issue = nil
        do {
            let value = try await tools.cancelGoal(id: id)
            guard ticket == generation, live() else { return }
            detail = value; phase = .ready
            await load()
        } catch {
            guard ticket == generation, live() else { return }
            issue = .from(error); phase = .ready
        }
    }
}

// MARK: 导出探索记录

@MainActor @Observable public final class RoamExportCoordinator {
    public enum Phase: Equatable { case choosing, preparing, prepared, reading, complete, failed }
    public private(set) var phase: Phase = .choosing
    public private(set) var checkpoint: RoamExportCheckpoint?
    public private(set) var file: RoamExportFile?
    public private(set) var issue: RoamPrivateToolIssue?
    /// Prepared, but the server reported a source change: parts read so far are incomplete.
    public private(set) var sourceChanged = false
    /// Delivery permission for the finished file; issued only once reading completes.
    public private(set) var deliveryLease: RoamExportDeliveryLease?
    private var parts: [String] = []
    private let tools: any RoamPrivateToolsServing
    private let owner: RoamExperienceIdentity?
    private let pageSize: Int
    private var generation = 0
    public init(tools: any RoamPrivateToolsServing, pageSize: Int = RoamExportContract.defaultPageSize) {
        self.tools = tools; owner = tools.identity; self.pageSize = pageSize
    }
    public var presets: [RoamExportRangePreset] { RoamExportRangePreset.presets(now: tools.now) }
    public var isBusy: Bool { phase == .preparing || phase == .reading }
    public var read: Int { checkpoint?.offset ?? 0 }
    public var expected: Int { checkpoint?.snapshot.expectedRows ?? 0 }
    public var percent: Int { expected > 0 ? min(100, Int((Double(read) / Double(expected) * 100).rounded())) : (file != nil ? 100 : 0) }
    private func live() -> Bool { owner != nil && tools.identity == owner }
    private func clear() { generation += 1; parts = []; file = nil; checkpoint = nil; sourceChanged = false; deliveryLease?.revoke(); deliveryLease = nil }
    /// Backgrounding or leaving the page revokes delivery for good; the temporary
    /// share copy is the view's to remove, and a fresh lease is needed to deliver again.
    public func revokeDelivery() { deliveryLease?.revoke() }
    /// Re-issue delivery permission after a return to the page, revalidating identity
    /// and expiry at that moment rather than trusting the earlier render.
    public func renewDelivery() {
        guard live(), phase == .complete, let file, !file.isExpired(now: tools.now) else { return }
        if deliveryLease == nil || deliveryLease?.isRevoked == true {
            deliveryLease = RoamExportDeliveryLease(file: file, identity: owner)
        }
    }
    /// The file at the actual hand-off moment: foreground, current identity, unexpired,
    /// unrevoked. Anything else delivers nothing.
    public func fileForDelivery(foreground: Bool) -> RoamExportFile? {
        guard live(), phase == .complete, let file, file.rows > 0, let deliveryLease else { return nil }
        return deliveryLease.validatedFile(file, now: tools.now, currentIdentity: tools.identity, foreground: foreground)
    }

    public func prepare(startDate: String, endDateExclusive: String) async {
        guard live() else { clear(); issue = owner == nil ? .signInRequired : .changedContext; phase = .choosing; return }
        guard !isBusy else { return }
        clear(); let ticket = generation
        let request = RoamExportRequest(startDate: startDate, endDateExclusive: endDateExclusive, pageSize: pageSize)
        guard (try? request.validate()) != nil else { issue = .invalidDraft; phase = .choosing; return }
        phase = .preparing; issue = nil
        do {
            let value = try await tools.prepareExport(request)
            guard ticket == generation, live() else { return }
            checkpoint = value; phase = .prepared
        } catch {
            guard ticket == generation, live(), !(error is CancellationError) else { return }
            issue = .from(error); phase = .choosing
        }
    }
    /// One chunk per explicit tap. A failed chunk keeps the checkpoint so the same page can be reread.
    public func readNext() async {
        guard live() else { clear(); issue = .changedContext; phase = .choosing; return }
        guard let original = checkpoint, !original.complete, !original.changed, phase == .prepared || phase == .failed else { return }
        generation += 1; let ticket = generation
        phase = .reading; issue = nil
        do {
            let chunk = try await tools.exportPage(original)
            guard ticket == generation, live(), checkpoint == original else { return }
            if chunk.restartRequired || chunk.data == nil {
                parts = []; file = nil; checkpoint = nil; sourceChanged = true; phase = .choosing
                return
            }
            parts.append(chunk.data!)
            checkpoint = chunk.checkpoint
            if chunk.checkpoint.complete {
                let snapshot = chunk.checkpoint.snapshot
                file = RoamExportFile(fileName: snapshot.fileName, content: parts.joined(), expiresAtMs: snapshot.expiresAtMs, rows: snapshot.expectedRows)
                deliveryLease = file.flatMap { RoamExportDeliveryLease(file: $0, identity: owner) }
                phase = .complete
            } else { phase = .prepared }
        } catch {
            guard ticket == generation, live(), !(error is CancellationError) else { return }
            issue = .from(error); phase = .failed
        }
    }
    /// 重新选择范围: discard every part and the finished file.
    public func restart() { guard !isBusy else { return }; clear(); issue = nil; phase = .choosing }
    /// The file only while complete, current, non-empty and unexpired; otherwise nothing to save or share.
    public var shareableFile: RoamExportFile? { fileForDelivery(foreground: true) }
    public var isFileExpired: Bool { file?.isExpired(now: tools.now) == true }
    /// Expired content is discarded; the player prepares a new snapshot.
    public func discardExpired() { guard isFileExpired, !isBusy else { return }; clear(); issue = .expired; phase = .choosing }
}
