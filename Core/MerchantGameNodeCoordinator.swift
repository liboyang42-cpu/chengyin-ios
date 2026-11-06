import Foundation

/// Page state for pages/merchant/game-node. Only exact APPLIED/FAILED receipts for the original request
/// release an unknown write; a reload or a projection that looks successful never does.
@MainActor public final class MerchantGameNodeCoordinator {
    public enum ViewState: Equatable { case loading, empty, ready, businessError(MerchantGameNodeMessage), networkError(MerchantGameNodeMessage) }
    public enum WriteState: Equatable { case idle, submitting, unknown }
    public enum Sheet: Equatable { case decline, pause, verify }
    public enum CheckinState: Equatable { case loading, ready, error }
    public struct ReceiptRow: Equatable, Identifiable {
        public var id: String { requestID }
        public let requestID: String, action: String, outcome: String, revision: Int, replayed: Bool
        public var actionKey: String {
            switch action {
            case "STATION_ACCEPT": return "merchantGameNode.action.STATION_ACCEPT"
            case "STATION_DECLINE": return "merchantGameNode.action.STATION_DECLINE"
            case "STATION_READY": return "merchantGameNode.action.STATION_READY"
            case "STATION_PAUSE": return "merchantGameNode.action.STATION_PAUSE"
            case "STATION_RESUME": return "merchantGameNode.action.STATION_RESUME"
            default: return "merchantGameNode.action.VERIFY_SUBMISSION"
            }
        }
        public var outcomeKey: String {
            outcome == "APPLIED" ? "merchantGameNode.outcome.applied" : outcome == "FAILED" ? "merchantGameNode.outcome.failed" : "merchantGameNode.outcome.pending"
        }
    }
    private struct PendingWrite { let index: MerchantGameNodePendingIndex; let command: MerchantGameNodeCommand? }
    /// Settles the dispatch exactly once; only touched on the main actor.
    private final class Once: @unchecked Sendable { var done = false; var timer: Task<Void, Never>? }

    public let service: any MerchantGameNodeServing
    public let activityID: Int
    public let requestedNodeID: Int?
    public var deadlineNanoseconds: UInt64 = 15_000_000_000
    public var onChange: (() -> Void)?
    public var now: () -> Date = Date.init

    public private(set) var viewState: ViewState = .loading { didSet { onChange?() } }
    public private(set) var projection: MerchantGameNodeProjection?
    public private(set) var lastRejection: MerchantGameNodeRejection?
    public private(set) var stationIndex = 0
    public private(set) var summary = MerchantGameNodeSummary(nil)
    public private(set) var sheet: Sheet? { didSet { onChange?() } }
    /// The presented confirmation; `frozen` keeps the exact command for the tapped confirm button.
    public private(set) var confirmation: MerchantGameNodeCommand? { didSet { onChange?() } }
    private var frozen: MerchantGameNodeCommand?
    public private(set) var writeState: WriteState = .idle { didSet { onChange?() } }
    public private(set) var writeMessage: MerchantGameNodeMessage? { didSet { onChange?() } }
    public private(set) var canRetryUnknownWrite = false { didSet { onChange?() } }
    public private(set) var recentReceipts: [ReceiptRow] = [] { didSet { onChange?() } }
    public private(set) var toast: MerchantGameNodeMessage? { didSet { onChange?() } }
    public private(set) var checkinVisible = false { didSet { onChange?() } }
    public private(set) var checkinState: CheckinState = .loading { didSet { onChange?() } }
    public private(set) var checkinQRCodeURL = ""
    public private(set) var checkinCountdown = 0 { didSet { onChange?() } }
    public private(set) var checkinError: MerchantGameNodeMessage?
    public var readyDraft = MerchantGameNodeReadyDraft() { didSet { onChange?() } }
    public var declineDraft = MerchantGameNodeDeclineDraft() { didSet { onChange?() } }
    public var pauseDraft = MerchantGameNodePauseDraft() { didSet { onChange?() } }
    public var verifyDraft = MerchantGameNodeVerifyDraft() { didSet { onChange?() } }

    private var focusPause: Bool
    private var pending: PendingWrite?
    private var busyKeys = Set<String>()
    private var loadGeneration = 0, checkinEpoch = 0
    private var receiptReading = false, retrying = false, started = false
    private var preservedReadyDraft: (nodeID: Int, draft: MerchantGameNodeReadyDraft)?
    private var authorityConflictReadyDraft: (nodeID: Int, draft: MerchantGameNodeReadyDraft)?

    public init(service: any MerchantGameNodeServing, activityID: Int?, requestedNodeID: Int? = nil, focusPause: Bool = false) {
        self.service = service
        self.activityID = activityID.map { $0 > 0 && $0 <= MerchantGameNodeWire.maxSafe ? $0 : 0 } ?? 0
        self.requestedNodeID = requestedNodeID.flatMap { $0 > 0 ? $0 : nil }
        self.focusPause = focusPause
    }

    public var station: MerchantGameNodeStation? {
        guard let projection, projection.stations.indices.contains(stationIndex) else { return nil }
        return projection.stations[stationIndex]
    }
    public var fallbackOptions: [MerchantGameNodeFallbackOption] {
        guard let projection, let station else { return [] }; return projection.fallbackOptions(for: station)
    }
    public var permitsWrites: Bool { service.permitsWrites }
    public func clearToast() { toast = nil }

    public func start() async {
        guard !started else { return }; started = true
        guard activityID > 0 else {
            viewState = .businessError(.key("merchantGameNode.error.missingActivity")); return
        }
        restorePending()
        await load()
    }

    public func load() async {
        loadGeneration += 1; let token = loadGeneration, scope = service.scope
        viewState = .loading
        let result = await service.loadProjection(activityID: activityID)
        guard token == loadGeneration, scope == service.scope else { return }
        switch result {
        case .businessError(let message, _):
            projection = nil; summary = .init(nil); viewState = .businessError(message)
        case .networkError(let message):
            projection = nil; summary = .init(nil); viewState = .networkError(message)
        case .ready(let raw):
            do {
                let normalized = try MerchantGameNodeProjection(raw); lastRejection = nil
                summary = .init(normalized)
                guard let index = normalized.stationIndex(requestedNodeID: requestedNodeID, previous: stationIndex) else {
                    projection = normalized; viewState = .empty; return
                }
                show(normalized, index: index)
            } catch {
                lastRejection = error as? MerchantGameNodeRejection
                projection = nil; summary = .init(nil); viewState = .businessError(.key("merchantGameNode.error.incomplete"))
            }
        }
    }

    private func show(_ normalized: MerchantGameNodeProjection, index: Int) {
        let selected = normalized.stations[index]
        projection = normalized; stationIndex = index
        if let conflict = authorityConflictReadyDraft, conflict.nodeID == selected.nodeID { readyDraft = conflict.draft }
        else { readyDraft = .init(station: selected) }
        if let preserved = preservedReadyDraft, preserved.nodeID == selected.nodeID { readyDraft = preserved.draft; preservedReadyDraft = nil }
        authorityConflictReadyDraft = nil
        viewState = .ready
        if focusPause {
            focusPause = false
            if !openPause() { toast = .key("merchantGameNode.toast.cannotPause") }
        }
    }

    public func selectStation(_ index: Int) {
        guard writeState == .idle, let projection, projection.stations.indices.contains(index) else { return }
        show(projection, index: index)
    }
    public func toggleChecklist(_ index: Int) {
        guard station?.canReady == true, writeState == .idle, readyDraft.checklist.indices.contains(index) else { return }
        readyDraft.checklist[index].checked.toggle()
    }

    // MARK: Sheets
    @discardableResult public func openDecline() -> Bool {
        guard station?.canDecline == true, writeState == .idle else { return false }
        declineDraft = .init(); sheet = .decline; return true
    }
    @discardableResult public func openPause() -> Bool {
        guard station?.canPause == true, writeState == .idle else { return false }
        pauseDraft = .init(); sheet = .pause; return true
    }
    @discardableResult public func openVerify(submissionID: String = "") -> Bool {
        guard station?.canVerify == true, writeState == .idle else { return false }
        verifyDraft = .init(submissionID: submissionID); sheet = .verify; return true
    }
    /// Scanned or pasted text; an unusable value never opens the sheet.
    @discardableResult public func openVerify(scanned text: String) -> Bool {
        let id = MerchantGameNodeSubmissionCode.parse(text)
        guard !id.isEmpty else { toast = .key("merchantGameNode.toast.badSubmissionCode"); return false }
        return openVerify(submissionID: id)
    }
    public func closeSheet() { guard writeState != .submitting else { return }; sheet = nil }

    // MARK: Prepare (request IDs are generated once here)
    private func requestID(_ action: MerchantStationAction, _ station: MerchantGameNodeStation) -> String {
        MerchantGameNodeRequestID.generate(action: action, activityID: activityID, nodeID: station.nodeID, now: now())
    }
    /// Accept and resume dispatch immediately in the source; iOS asks for an explicit confirmation first.
    public func prepareAccept() {
        guard let projection, let station, station.canAccept, writeState == .idle else { return }
        present(try? MerchantGameNodeCommand.accept(projection, station, requestID: requestID(.accept, station)))
    }
    public func prepareResume() {
        guard let projection, let station, station.canResume, writeState == .idle else { return }
        present(try? MerchantGameNodeCommand.resume(projection, station, requestID: requestID(.resume, station)))
    }
    private func present(_ command: MerchantGameNodeCommand?) { frozen = command; confirmation = command }
    /// Presentation dismissal only; the frozen command stays bound to the button that was tapped.
    public func dismissConfirmation() { confirmation = nil }
    public func cancelConfirmation() { confirmation = nil; frozen = nil }
    public func confirm(_ command: MerchantGameNodeCommand) async {
        guard command == frozen, writeState == .idle else { return }
        frozen = nil; confirmation = nil; await dispatch(command)
    }
    public func submitDecline() async {
        guard let projection, let station, writeState == .idle else { return }
        guard let command = try? MerchantGameNodeCommand.decline(projection, station, draft: declineDraft, requestID: requestID(.decline, station)) else {
            toast = .key("merchantGameNode.toast.declineReason"); return
        }
        await dispatch(command)
    }
    public func submitReady() async {
        guard let projection, let station, writeState == .idle else { return }
        guard let command = try? MerchantGameNodeCommand.ready(projection, station, draft: readyDraft, requestID: requestID(.ready, station)) else {
            toast = .key("merchantGameNode.toast.readyInvalid"); return
        }
        await dispatch(command)
    }
    /// A pause without an approved fallback asks for the source's extra confirmation first.
    public func submitPause() async {
        guard let projection, let station, writeState == .idle else { return }
        guard let command = try? MerchantGameNodeCommand.pause(projection, station, draft: pauseDraft, requestID: requestID(.pause, station)) else {
            toast = .key("merchantGameNode.toast.pauseInvalid"); return
        }
        if command.pausesWithoutFallback { present(command); return }
        await dispatch(command)
    }
    public func submitVerify() async {
        guard let projection, let station, writeState == .idle else { return }
        guard let command = try? MerchantGameNodeCommand.verify(projection, station, draft: verifyDraft, requestID: requestID(.verify, station)) else {
            toast = .key("merchantGameNode.toast.verifyInvalid"); return
        }
        await dispatch(command)
    }

    // MARK: Writes
    private func dispatch(_ command: MerchantGameNodeCommand) async {
        guard writeState == .idle, command.activityID == activityID else { return }
        guard service.permitsWrites else { toast = .key("merchantGameNode.writesDisabled"); return }
        guard !busyKeys.contains(command.lockKey) else { return }
        let scope = service.scope
        let entry = PendingWrite(index: command.pendingIndex, command: command)
        pending = entry; writeState = .submitting; writeMessage = nil
        guard service.persistPending(entry.index) else {
            pending = nil; writeState = .idle; canRetryUnknownWrite = false
            writeMessage = .key("merchantGameNode.write.storageFailed"); toast = .key("merchantGameNode.toast.storageFailed"); return
        }
        busyKeys.insert(command.lockKey)
        let result = await runWithDeadline(command)
        guard scope == service.scope else { return }
        handleWrite(result, entry: entry, retry: false)
    }

    private func runWithDeadline(_ command: MerchantGameNodeCommand) async -> MerchantGameNodeWriteResult {
        let service = self.service, deadline = deadlineNanoseconds, once = Once()
        return await withCheckedContinuation { (continuation: CheckedContinuation<MerchantGameNodeWriteResult, Never>) in
            let worker = Task { @MainActor in
                let result = await service.submit(command)
                guard !once.done else { return }
                once.done = true; once.timer?.cancel(); continuation.resume(returning: result)
            }
            once.timer = Task { @MainActor in
                try? await Task.sleep(nanoseconds: deadline)
                guard !once.done, !Task.isCancelled else { return }
                once.done = true; worker.cancel(); continuation.resume(returning: .unknown(nil))
            }
        }
    }

    private func handleWrite(_ result: MerchantGameNodeWriteResult, entry: PendingWrite, retry: Bool) {
        if case .businessError(let message, let code, _) = result, code == "GAME_AUTHORITY_CONFLICT" {
            pending = nil; busyKeys.remove(entry.index.lockKey); service.clearPending(activityID: activityID)
            if let station { authorityConflictReadyDraft = (station.nodeID, readyDraft) }
            writeState = .idle; writeMessage = message; canRetryUnknownWrite = false
            toast = message ?? .key("merchantGameNode.write.authorityConflict")
            Task { await load() }; return
        }
        var terminal: (MerchantGameNodeReceipt, failed: Bool, message: MerchantGameNodeMessage?)?
        switch result {
        case .success(let receipt) where receipt.matches(entry.index, outcome: "APPLIED"): terminal = (receipt, false, nil)
        case .businessError(let message, _, let receipt?) where receipt.matches(entry.index, outcome: "FAILED"): terminal = (receipt, true, message)
        default: terminal = nil
        }
        if let terminal {
            resolve(entry, receipt: terminal.0, failed: terminal.failed,
                    message: terminal.failed ? (terminal.message ?? .key(retry ? "merchantGameNode.write.originalFailed" : "merchantGameNode.write.failed")) : nil)
            return
        }
        var message: MerchantGameNodeMessage?
        switch result {
        case .unknown(let text): message = text
        case .businessError(let text, _, _): message = text
        case .success: message = nil
        }
        writeState = .unknown
        writeMessage = message ?? .key(retry ? "merchantGameNode.write.retryPending" : "merchantGameNode.write.pending")
        canRetryUnknownWrite = entry.command != nil
        sheet = nil
    }

    private func resolve(_ entry: PendingWrite, receipt: MerchantGameNodeReceipt, failed: Bool, message: MerchantGameNodeMessage?) {
        preservedReadyDraft = failed && entry.index.action == .ready ? (entry.index.nodeID, readyDraft) : nil
        pending = nil; busyKeys.remove(entry.index.lockKey); service.clearPending(activityID: activityID)
        record(receipt)
        writeState = .idle; writeMessage = message; canRetryUnknownWrite = false; sheet = nil
        Task { await load() }
    }

    public func confirmUnknownWrite() async {
        guard writeState == .unknown, let entry = pending, !receiptReading else { return }
        receiptReading = true; let scope = service.scope
        writeMessage = .key("merchantGameNode.write.checking")
        let result = await service.readReceipt(activityID: activityID, requestID: entry.index.requestID)
        receiptReading = false
        guard scope == service.scope, pending?.index == entry.index else { return }
        switch result {
        case .matched(let receipt) where receipt.matches(entry.index, outcome: "APPLIED"):
            resolve(entry, receipt: receipt, failed: false, message: nil)
        case .businessError(let message, _, let receipt?) where receipt.matches(entry.index, outcome: "FAILED"):
            resolve(entry, receipt: receipt, failed: true, message: message ?? .key("merchantGameNode.write.failed"))
        case .pending:
            writeState = .unknown; writeMessage = .key("merchantGameNode.write.stillProcessing")
        case .businessError(let message, _, _):
            writeState = .unknown; writeMessage = message ?? .key("merchantGameNode.write.notConfirmed")
        case .invalidResponse(let message):
            writeState = .unknown; writeMessage = message
        case .networkError:
            writeState = .unknown; writeMessage = .key("merchantGameNode.error.network")
        case .matched:
            writeState = .unknown; writeMessage = .key("merchantGameNode.write.notConfirmed")
        }
    }

    /// Resends the frozen original command with its original request ID; never builds a new one.
    public func retryUnknownWrite() async {
        guard writeState == .unknown, let entry = pending, let command = entry.command, !retrying else { return }
        guard service.permitsWrites, service.persistPending(entry.index) else {
            writeState = .unknown; writeMessage = .key("merchantGameNode.write.retryStorageFailed"); canRetryUnknownWrite = true
            toast = .key("merchantGameNode.toast.retryNotSent"); return
        }
        retrying = true; let scope = service.scope
        writeState = .submitting; writeMessage = .key("merchantGameNode.write.retrying")
        let result = await service.submit(command)
        retrying = false
        guard scope == service.scope, pending?.index == entry.index else { return }
        handleWrite(result, entry: entry, retry: true)
    }

    private func restorePending() {
        guard let saved = service.restorePending(activityID: activityID) else { return }
        pending = PendingWrite(index: saved, command: nil)
        busyKeys.insert(saved.lockKey)
        writeState = .unknown; writeMessage = .key("merchantGameNode.write.lastPending"); canRetryUnknownWrite = false
    }

    private func record(_ receipt: MerchantGameNodeReceipt) {
        guard let requestID = receipt.requestID else { return }
        let row = ReceiptRow(requestID: requestID, action: receipt.action ?? "", outcome: receipt.outcome ?? "",
                             revision: receipt.revision ?? 0, replayed: receipt.replayed)
        recentReceipts = Array(([row] + recentReceipts.filter { $0.requestID != requestID }).prefix(5))
    }

    // MARK: Live check-in code
    @discardableResult public func showCheckin() async -> Bool {
        guard station?.playable == true else { return false }
        checkinVisible = true; await issueCheckin(); return true
    }
    public func closeCheckin() {
        checkinEpoch += 1; checkinVisible = false; checkinState = .loading
        checkinQRCodeURL = ""; checkinCountdown = 0; checkinError = nil
    }
    public func issueCheckin() async {
        guard checkinVisible, let nodeID = station?.nodeID else { return }
        checkinEpoch += 1; let epoch = checkinEpoch, scope = service.scope
        checkinState = .loading; checkinQRCodeURL = ""; checkinCountdown = 0; checkinError = nil
        let result = await service.issueLiveCode(activityID: activityID, nodeID: nodeID)
        guard epoch == checkinEpoch, scope == service.scope, checkinVisible else { return }
        switch result {
        case .ready(let url, _, let seconds):
            checkinQRCodeURL = url; checkinError = nil; checkinCountdown = seconds; checkinState = .ready
        case .failure(let message):
            checkinError = message; checkinState = .error
        }
    }
    /// One-second tick while the overlay is visible; reaching zero issues a fresh one-time code.
    public func tickCheckin() async {
        guard checkinVisible, checkinState == .ready else { return }
        let remaining = checkinCountdown - 1
        if remaining <= 0 { await issueCheckin() } else { checkinCountdown = remaining }
    }
}
