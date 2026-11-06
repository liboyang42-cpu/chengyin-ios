import Foundation
import Observation

/// Immutable, single-use final-dialog snapshot. Never persisted and never reconstructed from mutable UI state.
public struct PersonalLocationShareConfirmationTicket: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let presentationId: UUID
    public let scope: PersonalLocationShareScope
    public let generation: UInt64
    public let contextRevision: UInt64
    public let choiceRevision: UInt64
    public let recipientId: Int64
    public let policy: PersonalLocationSharePolicy
    public let mode: PersonalLocationSharePolicy.ModeChoice
    public let duration: PersonalLocationSharePolicy.DurationChoice
    public let disclosures: Set<PersonalLocationShareDisclosure>
    public let capturePurpose: PersonalLocationShareCaptureApproval
    public let allowsFirstPermissionRequest: Bool
    public let issuedUptime: TimeInterval
    public let localDeadlineUptime: TimeInterval
    fileprivate init(presentationId: UUID, scope: PersonalLocationShareScope, generation: UInt64, contextRevision: UInt64,
                     choiceRevision: UInt64, recipientId: Int64, policy: PersonalLocationSharePolicy,
                     mode: PersonalLocationSharePolicy.ModeChoice, duration: PersonalLocationSharePolicy.DurationChoice,
                     disclosures: Set<PersonalLocationShareDisclosure>, capturePurpose: PersonalLocationShareCaptureApproval,
                     allowsFirstPermissionRequest: Bool, issuedUptime: TimeInterval, localDeadlineUptime: TimeInterval) {
        id = UUID(); self.presentationId = presentationId; self.scope = scope; self.generation = generation; self.contextRevision = contextRevision
        self.choiceRevision = choiceRevision; self.recipientId = recipientId; self.policy = policy
        self.mode = mode; self.duration = duration; self.disclosures = disclosures; self.capturePurpose = capturePurpose
        self.allowsFirstPermissionRequest = allowsFirstPermissionRequest; self.issuedUptime = issuedUptime; self.localDeadlineUptime = localDeadlineUptime
    }
}

/// One account/session owner for normal profile and Account entry points. No system-location permission calls.
@MainActor @Observable public final class PersonalLocationShareCoordinator {
    public enum RequestState: String { case creating, active, recoveryRequired, stopPending, stopped }
    /// Local durable metadata and current server reads are independent evidence, never substitutes.
    public enum JournalReadState: Equatable, Sendable { case unread, readable, unavailable }
    public enum ReadState: Equatable, Sendable { case notRead, loading, loaded, unavailable }
    public private(set) var journalReadState: JournalReadState = .unread
    public private(set) var ownedReadState: ReadState = .notRead
    public private(set) var receivedReadState: ReadState = .notRead
    public private(set) var isRestoringOriginalRequests = false
    public var hasUnpersistedStopIntent: Bool { !unpersistedStopKeys.isEmpty }
    public var originalRequestsAreVerifiedEmpty: Bool {
        journalReadState == .readable && !hasUnpersistedStopIntent && pending.isEmpty
    }
    public let scope: PersonalLocationShareScope
    public private(set) var recipientId: Int64?
    public private(set) var context: PersonalLocationShareContext?
    public private(set) var selectedModeId: String?
    public private(set) var selectedDurationId: String?
    public private(set) var acknowledgements: Set<PersonalLocationShareDisclosure> = []
    public private(set) var requests: [String: RequestState] = [:]
    public private(set) var pending: [PersonalLocationSharePendingRecord] = []
    public private(set) var ownedGrants: [PersonalLocationShareGrant] = []
    public private(set) var receiver: PersonalLocationShareReceiverProjection
    public private(set) var message = "尚未配置已批准的位置共享能力。"
    public private(set) var foreground = true
    public private(set) var connected = true
    public private(set) var isLoading = false
    public private(set) var publishingRequestKey: String?
    public private(set) var clockUptime: TimeInterval
    public private(set) var confirmationRevision: UInt64 = 0
    public private(set) var authorizationBlocked = false
    @ObservationIgnored private var issuedConfirmation: PersonalLocationShareConfirmationTicket?
    @ObservationIgnored private var pendingConfirmationStart: UUID?
    @ObservationIgnored private var pendingConfirmationPresentation: UUID?
    @ObservationIgnored private let service: (any PersonalLocationShareServicing)?
    @ObservationIgnored private let journal: any PersonalLocationShareJournaling
    @ObservationIgnored private let providerFactory: (any PersonalLocationShareCoordinateFactory)?
    @ObservationIgnored private var provider: (any PersonalLocationShareCoordinateProviding)?
    @ObservationIgnored private var publishingGrantId: String?
    @ObservationIgnored private let current: () -> PersonalLocationShareScope?
    @ObservationIgnored private let uptime: () -> TimeInterval
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var contextSerial: UInt64 = 0
    @ObservationIgnored private var publisher: Task<Void, Never>?
    @ObservationIgnored private var receiverPoll: Task<Void, Never>?
    @ObservationIgnored private var receiverReadRevision: UInt64 = 0
    @ObservationIgnored private var leaseTimer: Task<Void, Never>?
    @ObservationIgnored private var stopFence: Set<String> = []
    @ObservationIgnored private var managementReadRevision: UInt64 = 0
    @ObservationIgnored private var sequence: Int64 = 0
    @ObservationIgnored private var ownerDeadline: TimeInterval?
    @ObservationIgnored private var grantExpiryUptime: TimeInterval?
    @ObservationIgnored private var ownerLeaseTimer: Task<Void, Never>?
    @ObservationIgnored private var journalHealthy = false
    private var unpersistedStopKeys: Set<String> = []
    public init(scope: PersonalLocationShareScope, service: (any PersonalLocationShareServicing)? = nil,
                journal: any PersonalLocationShareJournaling, providerFactory: (any PersonalLocationShareCoordinateFactory)? = nil,
                current: @escaping () -> PersonalLocationShareScope?, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.scope = scope; self.service = service; self.journal = journal; self.providerFactory = providerFactory
        self.current = current; self.uptime = uptime; clockUptime = uptime()
        receiver = .init(recipientId: scope.accountId)
    }
    public private(set) var authorizationGeneration: UInt64 = 0
    private var isCurrent: Bool { !authorizationBlocked && current() == scope && service?.scope == scope }
    private var canRead: Bool { isCurrent && foreground && connected }
    public var providerIsConnected: Bool { providerFactory?.canCreate(scope: scope) == true && (providerFactory?.isSynthetic == false || service?.isSynthetic == true) }
    public var canConfirm: Bool {
        canRead && journalHealthy && unpersistedStopKeys.isEmpty && providerIsConnected && context?.eligible == true && recipientId == context?.recipientId &&
        selectedModeId != nil && selectedDurationId != nil &&
        acknowledgements == Set(PersonalLocationShareDisclosure.allCases) && pending.isEmpty && pendingConfirmationStart == nil && publishingRequestKey == nil
    }
    public var visibleLocations: [PersonalLocationShareReceiverProjection.Visible] { receiver.visible.values.sorted { $0.id < $1.id } }
    public func chooseMode(_ id: String?) {
        guard pending.isEmpty, pendingConfirmationStart == nil else { return }
        invalidateConfirmation()
        guard context?.policy?.modeChoices.contains(where: { $0.id == id }) == true else { selectedModeId = nil; return }
        selectedModeId = id; acknowledgements.remove(.precision)
    }
    public func chooseDuration(_ id: String?) {
        guard pending.isEmpty, pendingConfirmationStart == nil else { return }
        invalidateConfirmation()
        guard context?.policy?.durationChoices.contains(where: { $0.id == id }) == true else { selectedDurationId = nil; return }
        selectedDurationId = id; acknowledgements.remove(.duration)
    }
    public func acknowledge(_ disclosure: PersonalLocationShareDisclosure, accepted: Bool) {
        guard pending.isEmpty, pendingConfirmationStart == nil else { return }
        invalidateConfirmation()
        if accepted { acknowledgements.insert(disclosure) } else { acknowledgements.remove(disclosure) }
    }
    public func prepare(recipientId: Int64) async {
        guard !authorizationBlocked else { return }
        invalidateConfirmation()
        contextSerial &+= 1; let serial = contextSerial; let captured = generation
        self.recipientId = recipientId; context = nil; selectedModeId = nil; selectedDurationId = nil; acknowledgements = []
        guard canRead, let service, recipientId > 0, recipientId != scope.accountId else { message = "请登录并选择明确的其他成员。位置共享尚未启用。"; return }
        isLoading = true
        defer { if serial == contextSerial { isLoading = false } }
        do {
            let value = try await service.context(recipientId: recipientId)
            guard live(captured), serial == contextSerial else { return }
            guard value.ownerId == scope.accountId, value.recipientId == recipientId else { throw PersonalLocationShareFailure.invalidContract }
            guard value.eligible else {
                message = value.unavailableReason == "POLICY_UNAVAILABLE"
                    ? "尚无当前有效、已批准的共享政策，所有共享选择均不可用。"
                    : "此成员暂不具备共享资格。需双方互关、账号有效且无屏蔽。"
                return
            }
            guard let policy = value.policy else { throw PersonalLocationShareFailure.unavailable }
            try policy.validate(); context = value
            message = providerIsConnected ? "请选择精度、时长并逐项确认。" : "已取得选择政策，但独立采集用途或端点尚未批准；不能开始共享。"
            await restoreOriginalRequests()
        } catch { if handleAuthorizationFailure(error) { return }; if live(captured), serial == contextSerial { report(error) } }
    }
    public func openManagement() async {
        invalidateConfirmation()
        managementReadRevision &+= 1; let readRevision = managementReadRevision
        ownedReadState = .loading
        defer { if readRevision == managementReadRevision, ownedReadState == .loading { ownedReadState = .unavailable } }
        await restoreOriginalRequests()
        guard readRevision == managementReadRevision, !authorizationBlocked else { return }
        guard canRead, let service else { ownedReadState = .unavailable; message = "当前会话未配置已批准的位置共享读取能力。"; return }
        let captured = generation
        do {
            let value = try await service.owned()
            guard live(captured), readRevision == managementReadRevision else { return }
            guard value.ownerId == scope.accountId, value.serverNowMs > 0,
                  Set(value.grants.map(\.grantId)).count == value.grants.count,
                  value.grants.allSatisfy({ $0.structurallyValid && $0.ownerId == scope.accountId }) else { throw PersonalLocationShareFailure.invalidContract }
            ownedGrants = value.grants; ownedReadState = .loaded
            message = "已读取服务端授权状态。重启后不会自动恢复采集或共享。"
            await refreshReceived()
        } catch {
            if handleAuthorizationFailure(error) { return }
            if live(captured), readRevision == managementReadRevision { ownedReadState = .unavailable; report(error) }
        }
    }
    private func invalidateConfirmation() {
        confirmationRevision &+= 1; issuedConfirmation = nil
    }
    public func confirmationIsCurrent(_ ticket: PersonalLocationShareConfirmationTicket) -> Bool {
        issuedConfirmation == ticket && matchesConfirmation(ticket)
    }
    private func matchesConfirmation(_ ticket: PersonalLocationShareConfirmationTicket) -> Bool {
        guard canRead, journalHealthy, unpersistedStopKeys.isEmpty, providerIsConnected,
              ticket.scope == scope, ticket.generation == generation, ticket.contextRevision == contextSerial,
              ticket.choiceRevision == confirmationRevision, ticket.recipientId == recipientId,
              ticket.recipientId == context?.recipientId, context?.ownerId == scope.accountId, context?.eligible == true,
              context?.policy == ticket.policy, ticket.mode.id == selectedModeId,
              ticket.duration.id == selectedDurationId, ticket.disclosures == acknowledgements,
              ticket.disclosures == Set(PersonalLocationShareDisclosure.allCases),
              providerFactory?.confirmationPurpose(scope: scope) == ticket.capturePurpose,
              ticket.policy.modeChoices.contains(ticket.mode), ticket.policy.durationChoices.contains(ticket.duration),
              uptime().isFinite, uptime() < ticket.localDeadlineUptime else { return false }
        return true
    }
    public func makeConfirmationTicket(displayedRecipientId: Int64, presentationId: UUID, allowsFirstPermissionRequest: Bool) -> PersonalLocationShareConfirmationTicket? {
        guard canConfirm, displayedRecipientId == recipientId, displayedRecipientId == context?.recipientId,
              let policy = context?.policy, let mode = policy.modeChoices.first(where: { $0.id == selectedModeId }),
              let duration = policy.durationChoices.first(where: { $0.id == selectedDurationId }),
              let purpose = providerFactory?.confirmationPurpose(scope: scope), purpose.scope == scope else { return nil }
        invalidateConfirmation() // A newly opened dialog also retires any older presentation's ticket.
        let issuedAt = uptime()
        guard let deadline = Self.selectedDeadline(start: issuedAt, seconds: duration.seconds) else { return nil }
        let ticket = PersonalLocationShareConfirmationTicket(presentationId: presentationId, scope: scope, generation: generation, contextRevision: contextSerial,
            choiceRevision: confirmationRevision, recipientId: displayedRecipientId, policy: policy, mode: mode, duration: duration,
            disclosures: acknowledgements, capturePurpose: purpose, allowsFirstPermissionRequest: allowsFirstPermissionRequest,
            issuedUptime: issuedAt, localDeadlineUptime: deadline)
        issuedConfirmation = ticket; return ticket
    }
    public func confirmationEntryDisappeared(presentationId: UUID) {
        if issuedConfirmation?.presentationId == presentationId || pendingConfirmationPresentation == presentationId {
            invalidateConfirmation()
        }
    }
    public func cancelConfirmationTicket(_ ticket: PersonalLocationShareConfirmationTicket) {
        guard issuedConfirmation?.id == ticket.id else { return }
        invalidateConfirmation()
    }
    /// Consumes synchronously in the button action, before SwiftUI dismisses its dialog or any Task can suspend.
    @discardableResult public func confirmStart(ticket: PersonalLocationShareConfirmationTicket) -> Task<Void, Never> {
        guard !authorizationBlocked else { return Task {} }
        guard pendingConfirmationStart == nil, pending.isEmpty, publishingRequestKey == nil,
              confirmationIsCurrent(ticket) else {
            message = "确认内容已变化或已过期，请重新核验此接收者并确认。"; return Task {}
        }
        issuedConfirmation = nil; pendingConfirmationStart = ticket.id; pendingConfirmationPresentation = ticket.presentationId
        return Task { [weak self] in guard let self else { return }; await self.startConfirmed(ticket) }
    }
    private func startConfirmed(_ ticket: PersonalLocationShareConfirmationTicket) async {
        defer { if pendingConfirmationStart == ticket.id { pendingConfirmationStart = nil; pendingConfirmationPresentation = nil } }
        guard pendingConfirmationStart == ticket.id, matchesConfirmation(ticket), pending.isEmpty,
              publishingRequestKey == nil, let service else { return }
        let policy = ticket.policy; let recipientId = ticket.recipientId
        let selectedModeId = ticket.mode.id; let selectedDurationId = ticket.duration.id
        let captured = generation; let confirmationId = ticket.id
        do {
            try policy.validate()
            let request = PersonalLocationShareCreate(requestKey: UUID().uuidString.lowercased(), recipientId: recipientId,
                policyId: policy.policyId, policyVersion: policy.version, policyDigest: policy.digest,
                modeChoiceId: selectedModeId, durationChoiceId: selectedDurationId, foregroundOnly: true,
                acknowledgedDisclosures: PersonalLocationShareDisclosure.allCases)
            let record = try PersonalLocationSharePendingRecord(scope: scope, request: request)
            try journal.put(record, scope: scope) // Durable original key before the first mutating request.
            pending.append(record); requests[record.id] = .creating
            message = "正在确认服务端授权。"
            let receipt: PersonalLocationShareReceipt
            let requestStarted = uptime()
            do { receipt = try await service.create(request) }
            catch {
                if error as? PersonalLocationShareFailure == .retiredResponse {
                    // A retired creation can still have reached the server. Stop only its original key.
                    if pending.contains(where: { $0.id == record.id }) { await stop(requestKey: record.id) }
                    return
                }
                if handleAuthorizationFailure(error) { return }
                guard live(captured), pending.contains(where: { $0.id == record.id }) else { return }
                requests[record.id] = stopFence.contains(record.id) ? .stopPending : .recoveryRequired
                report(error)
                message += " 创建结果未知。保留原请求，请查询或停止；不会换新请求重试。"
                return
            }
            guard live(captured), pending.contains(where: { $0.id == record.id }) else { return }
            guard matchesConfirmation(ticket) else {
                // A different entry/context, vanished dialog host, or expired ticket never starts the old source.
                await stop(requestKey: record.id); return
            }
            let grant = try accept(receipt, requestKey: record.id)
            guard let grant, !stopFence.contains(record.id), requests[record.id] == .active else { return }
            do {
                try startPublisher(grant: grant, policy: policy, serverNowMs: receipt.serverNowMs,
                    requestStarted: requestStarted, confirmationId: confirmationId, ticket: ticket)
            } catch {
                report(error)
                await stop(requestKey: record.id)
                if live(captured), journalHealthy {
                    report(error)
                    if requests[record.id] == .stopPending { message += " 服务端撤销仍待确认，请重试原请求。" }
                }
            }
        } catch {
            if handleAuthorizationFailure(error) { return }
            if live(captured) { report(error) }
        }
    }
    /// Read-only recovery. A known ACTIVE grant never starts a provider after relaunch/readback.
    public func restoreOriginalRequests() async {
        guard !isRestoringOriginalRequests else { return }; isRestoringOriginalRequests = true
        defer { isRestoringOriginalRequests = false }
        do {
            let records = try journal.records(scope: scope)
            // A failed stop write must not be forgotten by a later read of older disk metadata.
            // This is an in-memory projection only; recovery never creates or replays a request.
            pending = records.map { value in
                var record = value
                if stopFence.contains(record.id) || unpersistedStopKeys.contains(record.id) { record.stopRequested = true }
                return record
            }
            let wasUnavailable = journalReadState == .unavailable
            journalReadState = .readable; journalHealthy = unpersistedStopKeys.isEmpty
            if wasUnavailable { message = "已重新读取原请求日志；不会自动恢复采集或重放创建。" }
            for record in pending {
                if record.stopRequested { stopFence.insert(record.id) }
                if requests[record.id] == nil { requests[record.id] = record.stopRequested ? .stopPending : .recoveryRequired }
            }
        } catch { journalReadState = .unavailable; journalHealthy = false; message = "原请求日志无法安全读取。已禁止新建共享，需修复日志后恢复。"; return }
        guard canRead else { return }
        for record in pending { await readback(requestKey: record.id) }
    }
    public func readback(requestKey: String) async {
        guard canRead, let service, pending.contains(where: { $0.id == requestKey }) else { return }
        let captured = generation
        do {
            let receipt = try await service.requestStatus(requestKey: requestKey)
            guard live(captured), pending.contains(where: { $0.id == requestKey }) else { return }
            _ = try accept(receipt, requestKey: requestKey)
            if requests[requestKey] == .active && publishingRequestKey != requestKey { requests[requestKey] = .recoveryRequired; message = "服务端仍有授权，但本机未恢复采集。请停止原授权后再重新确认共享。" }
        } catch { if handleAuthorizationFailure(error) { return }; if live(captured) { report(error) } }
    }
    /// Stops collection synchronously, before journaling, network I/O or awaiting a pending create.
    public func stop(requestKey: String) async {
        invalidateConfirmation()
        stopLocalPublisher(); stopFence.insert(requestKey); requests[requestKey] = .stopPending
        acknowledgements.removeAll(); receiver.clear(); cancelReceiver()
        do { try persistStop(requestKey: requestKey) }
        catch { journalHealthy = false; unpersistedStopKeys.insert(requestKey); message = "本机已停止；停止意图未能安全保存，服务端撤销尚未确认。已禁止新建共享。"; return }
        // An owner lease/publisher task can be the caller and has just cancelled itself.
        // A separate cleanup task must not inherit that cancellation as a failed revoke.
        let cleanup = Task { [weak self] in await self?.retryStop(requestKey: requestKey) }
        await cleanup.value
    }
    private func persistStop(requestKey: String) throws {
        if let index = pending.firstIndex(where: { $0.id == requestKey }) {
            pending[index].stopRequested = true
            try journal.put(pending[index], scope: scope)
        } else if let grant = ownedGrants.first(where: { $0.requestKey == requestKey }) {
            let request = PersonalLocationShareCreate(requestKey: grant.requestKey, recipientId: grant.recipientId,
                policyId: grant.policyId, policyVersion: grant.policyVersion, policyDigest: grant.policyDigest,
                modeChoiceId: grant.modeChoiceId, durationChoiceId: grant.durationChoiceId, foregroundOnly: true,
                acknowledgedDisclosures: PersonalLocationShareDisclosure.allCases)
            var record = try PersonalLocationSharePendingRecord(scope: scope, request: request); record.stopRequested = true
            try journal.put(record, scope: scope); pending.append(record)
        } else { throw PersonalLocationShareFailure.invalidContract }
        unpersistedStopKeys.remove(requestKey)
    }
    public func stopAll() async {
        let keys = Set(pending.map(\.id)).union(ownedGrants.filter { $0.status == .active }.map(\.requestKey))
        for key in keys { await stop(requestKey: key) }
    }
    public func retryStop(requestKey: String) async {
        guard !authorizationBlocked else { return }
        guard isCurrent, connected, let service,
              pending.contains(where: { $0.id == requestKey && $0.stopRequested }) else {
            message = "本机已停止，服务端撤销待确认。请在原账号恢复连接后重试。"; return
        }
        let captured = generation
        if unpersistedStopKeys.contains(requestKey) {
            do { try persistStop(requestKey: requestKey) }
            catch { journalHealthy = false; message = "本机已停止；停止意图仍无法保存，未发起撤销请求。已禁止新建共享。"; return }
        }
        do {
            let receipt = try await service.revoke(requestKey: requestKey)
            guard live(captured, requireForeground: false), pending.contains(where: { $0.id == requestKey }) else { return }
            _ = try accept(receipt, requestKey: requestKey)
            if !receipt.state.isTerminal { message = "本机已停止，服务端撤销待确认。" }
        } catch {
            if handleAuthorizationFailure(error) { return }
            if current() == scope { report(error); message += " 本机已停止，服务端撤销待确认。保留原请求重试。" }
        }
    }
    private func accept(_ receipt: PersonalLocationShareReceipt, requestKey: String) throws -> PersonalLocationShareGrant? {
        guard let index = pending.firstIndex(where: { $0.id == requestKey }), receipt.requestKey == requestKey,
              receipt.serverNowMs > 0, receipt.watermark >= 0,
              receipt.known == (receipt.state != .notFound) else { throw PersonalLocationShareFailure.invalidContract }
        var record = pending[index]
        if let old = record.serverRequestHash, receipt.requestHash != old { throw PersonalLocationShareFailure.invalidContract }
        if let hash = receipt.requestHash { guard !hash.isEmpty else { throw PersonalLocationShareFailure.invalidContract }; record.serverRequestHash = hash }
        if let grant = receipt.grant {
            guard grant.matches(record.request, ownerId: scope.accountId), grant.status == receipt.state,
                  grant.watermark <= receipt.watermark else { throw PersonalLocationShareFailure.invalidContract }
        }
        if receipt.state == .active {
            guard let grant = receipt.grant, receipt.requestHash != nil,
                  grant.expiresAtMs > receipt.serverNowMs else { throw PersonalLocationShareFailure.invalidContract }
        } else if receipt.state == .notFound {
            guard receipt.grant == nil, receipt.requestHash == nil else { throw PersonalLocationShareFailure.invalidContract }
        }
        if receipt.state.isTerminal {
            try journal.remove(requestKey: requestKey, scope: scope)
            // The validated original request is durably terminal. Its failed stop intent is now resolved;
            // retain every other key's write fence and require normal journal recovery before new consent.
            unpersistedStopKeys.remove(requestKey)
            pending.remove(at: index); requests[requestKey] = .stopped
            ownedGrants.removeAll { $0.requestKey == requestKey }
            if publishingRequestKey == requestKey { stopLocalPublisher() }
            message = "服务端已确认结束共享。已经看见的信息无法收回。"
            return nil
        }
        try journal.put(record, scope: scope); pending[index] = record
        if record.stopRequested || stopFence.contains(requestKey) { requests[requestKey] = .stopPending; return nil }
        requests[requestKey] = receipt.state == .active ? .active : .recoveryRequired
        if receipt.state == .notFound { message = "服务端暂未找到原请求，不等于已撤销。请选择停止原请求以建立停止记录。" }
        return receipt.grant
    }
    // Floating-point rounding must not extend even an unusually large approved duration.
    private static func addingWithoutExtension(_ start: TimeInterval, _ delta: TimeInterval) -> TimeInterval {
        let end = start + delta
        return end - start > delta ? end.nextDown : end
    }
    static func selectedDeadline(start: TimeInterval, seconds: Int64) -> TimeInterval? {
        guard start.isFinite, start >= 0, seconds > 0, seconds <= Int64.max / 1000 else { return nil }
        var delta = Double(seconds)
        if Int64(delta) > seconds { delta = delta.nextDown }
        let end = addingWithoutExtension(start, delta)
        return end.isFinite && end > start ? end : nil
    }
    static func confirmedDeadline(grant: PersonalLocationShareGrant, ticket: PersonalLocationShareConfirmationTicket,
                                  serverNowMs: Int64, requestStarted: TimeInterval) throws -> TimeInterval {
        let seconds = ticket.duration.seconds
        guard serverNowMs > 0, seconds > 0, seconds <= Int64.max / 1000,
              ticket.policy.durationChoices.contains(ticket.duration), grant.durationChoiceId == ticket.duration.id,
              grant.createdAtMs > 0, grant.createdAtMs <= serverNowMs, grant.expiresAtMs > serverNowMs,
              grant.expiresAtMs > grant.createdAtMs,
              grant.expiresAtMs - grant.createdAtMs <= seconds * 1000,
              requestStarted.isFinite, requestStarted >= ticket.issuedUptime, ticket.localDeadlineUptime.isFinite else { throw PersonalLocationShareFailure.invalidContract }
        let remaining = (Double(grant.expiresAtMs - serverNowMs).nextDown / 1000).nextDown
        let serverDeadline = addingWithoutExtension(requestStarted, remaining)
        guard let selectedDeadline = Self.selectedDeadline(start: requestStarted, seconds: seconds) else { throw PersonalLocationShareFailure.invalidContract }
        let deadline = min(ticket.localDeadlineUptime, serverDeadline, selectedDeadline)
        guard deadline.isFinite, deadline > requestStarted else { throw PersonalLocationShareFailure.expiredConfirmation }
        return deadline
    }
    private func startPublisher(grant: PersonalLocationShareGrant, policy: PersonalLocationSharePolicy, serverNowMs: Int64, requestStarted: TimeInterval, confirmationId: UUID, ticket: PersonalLocationShareConfirmationTicket) throws {
        guard canRead, providerIsConnected, !stopFence.contains(grant.requestKey), grant.ownerLeaseUntilMs > serverNowMs,
              policy.modeChoices.first(where: { $0.id == grant.modeChoiceId })?.mode == grant.mode, let providerFactory else { throw PersonalLocationShareFailure.providerUnavailable }
        let expiry = try Self.confirmedDeadline(grant: grant, ticket: ticket, serverNowMs: serverNowMs, requestStarted: requestStarted)
        guard uptime() < expiry else { throw PersonalLocationShareFailure.expiredConfirmation }
        stopLocalPublisher(); publishingRequestKey = grant.requestKey; publishingGrantId = grant.grantId; sequence = 0
        grantExpiryUptime = expiry
        ownerDeadline = min(expiry, requestStarted + Double(min(grant.expiresAtMs, grant.ownerLeaseUntilMs) - serverNowMs) / 1000)
        scheduleOwnerLease(requestKey: grant.requestKey)
        let captured = generation
        let binding = try PersonalLocationShareCaptureBinding(scope: scope, grant: grant, confirmationId: confirmationId, allowsFirstPermissionRequest: ticket.allowsFirstPermissionRequest, capturePurpose: ticket.capturePurpose)
        // No source object or manager can be constructed before this confirmed, authoritative grant.
        provider = try providerFactory.make(binding: binding, isCurrent: { [weak self] in
            guard let self else { return false }
            return self.live(captured) && self.publishingRequestKey == grant.requestKey &&
                self.publishingGrantId == grant.grantId && !self.stopFence.contains(grant.requestKey) &&
                self.ownerDeadline.map { self.uptime() < $0 } == true
        })
        publisher = Task { [weak self] in
            guard let self else { return }
            while self.live(captured), self.publishingRequestKey == grant.requestKey, !Task.isCancelled {
                do {
                    try await self.publishOne(grant: grant, policy: policy, captured: captured)
                    try await Self.pause(milliseconds: policy.refreshAfterMs)
                } catch {
                    if self.handleAuthorizationFailure(error) { return }
                    if self.publishingRequestKey == grant.requestKey {
                        self.report(error) // Do not hide permission/accuracy failures behind a hanging revoke.
                        await self.stop(requestKey: grant.requestKey)
                        if self.live(captured), self.journalHealthy {
                            self.report(error)
                            if self.requests[grant.requestKey] == .stopPending { self.message += " 服务端撤销仍待确认，请重试原请求。" }
                        }
                    }
                    return
                }
            }
        }
        message = "服务端授权已建立，正在等待本次前台定位；尚不能确认已发布位置。"
    }
    private func publishOne(grant: PersonalLocationShareGrant, policy: PersonalLocationSharePolicy, captured: UInt64) async throws {
        guard live(captured), !stopFence.contains(grant.requestKey), let service, let provider,
              publishingRequestKey == grant.requestKey, let ownerDeadline, uptime() < ownerDeadline else { throw PersonalLocationShareFailure.staleSession }
        let sample = try await provider.sample()
        guard live(captured), !stopFence.contains(grant.requestKey), publishingRequestKey == grant.requestKey,
              uptime() < ownerDeadline, !sample.sourceId.isEmpty, sequence < Int64.max else { throw PersonalLocationShareFailure.staleSession }
        sequence += 1
        let observation = PersonalLocationSharePublish(sequence: sequence, observedAtMs: sample.observedAtMs, datum: sample.datum,
            latitude: sample.latitude, longitude: sample.longitude, foreground: true)
        guard grant.mode != .exact || sample.systemAccuracy == .full else { throw PersonalLocationShareFailure.reducedAccuracyUnavailable }
        guard observation.valid else { throw PersonalLocationShareFailure.invalidContract }
        let sendStarted = uptime()
        let result = try await service.publish(grantId: grant.grantId, observation: observation, synthetic: provider.isSynthetic)
        guard live(captured), publishingRequestKey == grant.requestKey, !stopFence.contains(grant.requestKey),
              result.grantId == grant.grantId, result.sequence == sequence, result.observedAtMs == sample.observedAtMs,
              result.version >= grant.version, result.watermark >= grant.watermark,
              result.ownerLeaseUntilMs > result.observedAtMs else { throw PersonalLocationShareFailure.invalidContract }
        // Sending time, not receipt time, bounds lease renewal; never extend past original grant expiry.
        guard let expiry = grantExpiryUptime else { throw PersonalLocationShareFailure.invalidContract }
        self.ownerDeadline = min(expiry, sendStarted + Double(policy.ownerLeaseMs) / 1000)
        scheduleOwnerLease(requestKey: grant.requestKey)
        message = "已发布本次前台位置。仅按获批间隔继续；离线或离开前台会停止。"
    }
    private func scheduleOwnerLease(requestKey: String) {
        ownerLeaseTimer?.cancel()
        guard let deadline = ownerDeadline else { return }
        let remaining = max(0, deadline - uptime())
        ownerLeaseTimer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(min(remaining * 1_000_000_000, Double(Int64.max)))) } catch { return }
            guard let self, !Task.isCancelled, self.publishingRequestKey == requestKey else { return }
            await self.stop(requestKey: requestKey)
        }
    }
    public func refreshReceived() async {
        guard canRead, let service else { receiver.clear(); cancelReceiver(); receivedReadState = .unavailable; return }
        receivedReadState = .loading
        receiverReadRevision &+= 1; let readRevision = receiverReadRevision
        let captured = generation; let ticket = receiver.beginRead(); let requestStarted = uptime()
        defer { if readRevision == receiverReadRevision, receivedReadState == .loading { receivedReadState = .unavailable } }
        do {
            let value = try await service.received()
            guard live(captured), receiverReadRevision == readRevision else { return }
            if try receiver.apply(value, ticket: ticket, uptime: requestStarted) {
                clockUptime = uptime(); receiver.expire(at: clockUptime); receivedReadState = .loaded
                scheduleReceiver(); scheduleLeaseExpiry()
            }
        } catch {
            if handleAuthorizationFailure(error) { return }
            if live(captured), receiverReadRevision == readRevision { receiver.clear(); cancelReceiver(); receivedReadState = .unavailable; report(error) }
        }
    }
    private func scheduleReceiver() {
        receiverReadRevision &+= 1; let readRevision = receiverReadRevision
        receiverPoll?.cancel()
        guard let interval = receiver.refreshAfterMs, interval > 0 else { return }
        let captured = generation
        receiverPoll = Task { [weak self] in
            do { try await Self.pause(milliseconds: interval) } catch { return }
            guard let self, self.live(captured), self.receiverReadRevision == readRevision, !Task.isCancelled, let service = self.service else { return }
            do {
                let batch = try await service.events(cursor: self.receiver.cursor)
                guard self.live(captured), self.receiverReadRevision == readRevision, !Task.isCancelled else { return }
                let needsSnapshot = try self.receiver.apply(batch)
                if needsSnapshot { await self.refreshReceived() } else { self.scheduleReceiver() }
            } catch {
                if self.handleAuthorizationFailure(error) { return }
                if self.live(captured), self.receiverReadRevision == readRevision { self.receiver.clear(); self.cancelReceiver(); self.receivedReadState = .unavailable; self.report(error); self.message += " 接收位置已隐藏。" }
            }
        }
    }
    private func scheduleLeaseExpiry() {
        leaseTimer?.cancel()
        guard !receiver.visible.isEmpty else { return }
        let captured = generation
        leaseTimer = Task { [weak self] in
            guard let self else { return }
            // Wake at actual policy-derived stale/expiry boundaries, never a local business cadence.
            while self.live(captured), !self.receiver.visible.isEmpty, !Task.isCancelled {
                let now = self.uptime()
                let boundaries = self.receiver.visible.values.flatMap { [$0.deadlineUptime, $0.staleUptime] }.filter { $0 > now }
                guard let next = boundaries.min() else { self.receiver.expire(at: now); break }
                do { try await Task.sleep(nanoseconds: UInt64(min((next - now) * 1_000_000_000, Double(Int64.max)))) } catch { return }
                guard self.live(captured), !Task.isCancelled else { return }
                self.clockUptime = self.uptime(); self.receiver.expire(at: self.clockUptime)
            }
        }
    }
    private func stopLocalPublisher() { authorizationGeneration &+= 1; ownerLeaseTimer?.cancel(); ownerLeaseTimer = nil; grantExpiryUptime = nil; provider?.stop(); provider = nil; publishingGrantId = nil; publisher?.cancel(); publisher = nil; publishingRequestKey = nil; ownerDeadline = nil }
    private func cancelReceiver() { receiverReadRevision &+= 1; receiverPoll?.cancel(); receiverPoll = nil; leaseTimer?.cancel(); leaseTimer = nil }
    /// Called synchronously on background, path loss, logout, token/account/epoch changes.
    public func suspend(foreground: Bool, connected: Bool) {
        invalidateConfirmation()
        let keys = Set(pending.map(\.id)).union(ownedGrants.filter { $0.status == .active }.map(\.requestKey))
        stopLocalPublisher(); cancelReceiver(); receiver.clear(); generation &+= 1; contextSerial &+= 1
        self.foreground = foreground; self.connected = connected; context = nil; acknowledgements.removeAll(); isLoading = false
        for key in keys {
            stopFence.insert(key); requests[key] = .stopPending
            do { try persistStop(requestKey: key) }
            catch { journalHealthy = false; unpersistedStopKeys.insert(key); message = "本机已停止，但停止意图保存失败；服务端撤销待确认。已禁止新建共享。" }
        }
        // Best-effort safety cleanup uses the original account only. A changed account cannot send it.
        if connected && isCurrent {
            Task { [self] in
                for key in keys { await self.retryStop(requestKey: key) }
            }
        }
        ownedGrants.removeAll(); managementReadRevision &+= 1
        ownedReadState = .notRead; receivedReadState = .notRead
        if unpersistedStopKeys.isEmpty {
            message = "本机采集已停止，接收位置已清除。未确认的服务端撤销仍保留原请求。返回前台须重新核验并确认，不会自动恢复旧授权。"
        }
    }
    public func resume(foreground: Bool, connected: Bool) {
        guard !authorizationBlocked else { return }
        self.foreground = foreground; self.connected = connected
        // Deliberately no automatic create/publish/read. The user opens a normal entry to recover/read.
    }
    private func live(_ captured: UInt64, requireForeground: Bool = true) -> Bool {
        generation == captured && isCurrent && connected && (!requireForeground || foreground)
    }
    private static func pause(milliseconds: Int64) async throws {
        guard milliseconds > 0, UInt64(milliseconds) <= UInt64.max / 1_000_000 else { throw PersonalLocationShareFailure.invalidContract }
        try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }
    @discardableResult private func handleAuthorizationFailure(_ error: Error) -> Bool {
        guard let failure = error as? PersonalLocationShareFailure else { return false }
        if failure == .retiredResponse { return true } // No stop, message or receiver mutation may cross an old lease.
        guard case .authorizationRejected = failure else { return false }
        authorizationRejected(error); return true
    }
    public func authorizationRejected(_ error: Error) {
        guard let failure = error as? PersonalLocationShareFailure, case let .authorizationRejected(status, code) = failure else { return }
        if !authorizationBlocked { suspend(foreground: false, connected: false); authorizationBlocked = true }
        guard unpersistedStopKeys.isEmpty else { return } // A failed durable stop must remain visible.
        if code == "RELATION_UNAVAILABLE" { message = "服务端拒绝当前关系授权。已同步停止采集并清除接收位置。" }
        else if code == "POLICY_CHANGED" || code == "POLICY_UNAVAILABLE" { message = "服务端拒绝当前共享政策。已同步停止采集并清除接收位置。" }
        else { message = "服务端拒绝共享访问（\(status)）。已同步停止采集并清除接收位置；需重新核验会话与授权。" }
    }
    private func report(_ error: Error) {
        if handleAuthorizationFailure(error) || authorizationBlocked { return }
        switch error as? PersonalLocationShareFailure {
        case .unapprovedRead: message = "读取端点尚未批准；未发起网络读取。"
        case .unapprovedWrite: message = "写入端点尚未批准；未发起位置共享写入。"
        case .acceptanceUnavailable: message = "该政策要求接收者接受，但接受流程尚未接通，已禁止共享。"
        case .providerUnavailable, .syntheticTransportForbidden: message = "独立采集能力尚未启用；测试或模拟位置不能发送到真实服务。"
        case .existingLocationPermissionRequired: message = "仅使用已有前台定位权限，不会绕过拒绝或受限状态。首次授权须在确认中明确选择，当前已停止共享。"
        case .reducedAccuracyUnavailable: message = "系统仅提供降低精度的位置，不能冒充原采样精度；已停止此精确共享。"
        case .capturePurposeUnavailable: message = "个人共享的独立用途说明尚未批准或与安装包不符，已禁止采集。"
        case .expiredConfirmation: message = "确认窗口或已选共享时长已到期，请重新核验并确认。"
        case .unavailable: message = "当前没有可用的已批准共享政策。"
        case .server("POLICY_CHANGED"), .server("POLICY_UNAVAILABLE"):
            // A known policy outage is not permission to keep a different live publisher running.
            // Persist original stop intents without waiting for, or recursively issuing, cleanup HTTP.
            let wasConnected = connected
            suspend(foreground: foreground, connected: false); connected = wasConnected
            if unpersistedStopKeys.isEmpty { message = "共享政策已变更或不可用，已停止采集并隐藏接收位置。保留原请求待核验；不会自动重建。" }
        case .server("RELATION_UNAVAILABLE"): message = "当前关系或账号不再允许共享。"
        case .staleSession: message = "账号或会话已变化。位置已停止，不会在新账号下重试原请求。"
        default: message = "暂时无法验证共享状态。不会恢复采集或显示未经验证的位置。"
        }
    }

    public struct MessagePart: Equatable, Sendable {
        public let key: String?
        public let arguments: [String]
        public let fallback: String
    }
    public var messageParts: [MessagePart] { Self.presentation(for: message) }
    /// Only local, known messages are translated. Unknown future text remains honest, not a success.
    public static func presentation(for message: String) -> [MessagePart] {
        let suffixes: [(String, String)] = [
            (" 创建结果未知。保留原请求，请查询或停止；不会换新请求重试。", "personalLocationShare.status.createUnknown"),
            (" 服务端撤销仍待确认，请重试原请求。", "personalLocationShare.status.revokePending"),
            (" 本机已停止，服务端撤销待确认。保留原请求重试。", "personalLocationShare.status.stoppedPending"),
            (" 接收位置已隐藏。", "personalLocationShare.status.locationsHidden")
        ]
        var base = message
        var trailing: [MessagePart] = []
        while let suffix = suffixes.first(where: { base.hasSuffix($0.0) }) {
            base.removeLast(suffix.0.count)
            trailing.insert(.init(key: suffix.1, arguments: [], fallback: suffix.0), at: 0)
        }
        let key: String?
        switch base {
        case "尚未配置已批准的位置共享能力。": key = "personalLocationShare.status.01"
        case "请登录并选择明确的其他成员。位置共享尚未启用。": key = "personalLocationShare.status.02"
        case "尚无当前有效、已批准的共享政策，所有共享选择均不可用。": key = "personalLocationShare.status.03"
        case "此成员暂不具备共享资格。需双方互关、账号有效且无屏蔽。": key = "personalLocationShare.status.04"
        case "请选择精度、时长并逐项确认。": key = "personalLocationShare.status.05"
        case "已取得选择政策，但独立采集用途或端点尚未批准；不能开始共享。": key = "personalLocationShare.status.06"
        case "当前会话未配置已批准的位置共享读取能力。": key = "personalLocationShare.status.07"
        case "已读取服务端授权状态。重启后不会自动恢复采集或共享。": key = "personalLocationShare.status.08"
        case "确认内容已变化或已过期，请重新核验此接收者并确认。": key = "personalLocationShare.status.09"
        case "正在确认服务端授权。": key = "personalLocationShare.status.10"
        case "原请求日志无法安全读取。已禁止新建共享，需修复日志后恢复。": key = "personalLocationShare.status.11"
        case "服务端仍有授权，但本机未恢复采集。请停止原授权后再重新确认共享。": key = "personalLocationShare.status.12"
        case "本机已停止；停止意图未能安全保存，服务端撤销尚未确认。已禁止新建共享。": key = "personalLocationShare.status.13"
        case "本机已停止，服务端撤销待确认。请在原账号恢复连接后重试。": key = "personalLocationShare.status.14"
        case "本机已停止；停止意图仍无法保存，未发起撤销请求。已禁止新建共享。": key = "personalLocationShare.status.15"
        case "本机已停止，服务端撤销待确认。": key = "personalLocationShare.status.16"
        case "服务端已确认结束共享。已经看见的信息无法收回。": key = "personalLocationShare.status.17"
        case "服务端暂未找到原请求，不等于已撤销。请选择停止原请求以建立停止记录。": key = "personalLocationShare.status.18"
        case "服务端授权已建立，正在等待本次前台定位；尚不能确认已发布位置。": key = "personalLocationShare.status.19"
        case "已发布本次前台位置。仅按获批间隔继续；离线或离开前台会停止。": key = "personalLocationShare.status.20"
        case "本机已停止，但停止意图保存失败；服务端撤销待确认。已禁止新建共享。": key = "personalLocationShare.status.21"
        case "本机采集已停止，接收位置已清除。未确认的服务端撤销仍保留原请求。返回前台须重新核验并确认，不会自动恢复旧授权。": key = "personalLocationShare.status.22"
        case "服务端拒绝当前关系授权。已同步停止采集并清除接收位置。": key = "personalLocationShare.status.23"
        case "服务端拒绝当前共享政策。已同步停止采集并清除接收位置。": key = "personalLocationShare.status.24"
        case "读取端点尚未批准；未发起网络读取。": key = "personalLocationShare.status.25"
        case "写入端点尚未批准；未发起位置共享写入。": key = "personalLocationShare.status.26"
        case "该政策要求接收者接受，但接受流程尚未接通，已禁止共享。": key = "personalLocationShare.status.27"
        case "独立采集能力尚未启用；测试或模拟位置不能发送到真实服务。": key = "personalLocationShare.status.28"
        case "仅使用已有前台定位权限，不会绕过拒绝或受限状态。首次授权须在确认中明确选择，当前已停止共享。": key = "personalLocationShare.status.29"
        case "系统仅提供降低精度的位置，不能冒充原采样精度；已停止此精确共享。": key = "personalLocationShare.status.30"
        case "个人共享的独立用途说明尚未批准或与安装包不符，已禁止采集。": key = "personalLocationShare.status.31"
        case "确认窗口或已选共享时长已到期，请重新核验并确认。": key = "personalLocationShare.status.32"
        case "当前没有可用的已批准共享政策。": key = "personalLocationShare.status.33"
        case "共享政策已变更或不可用，已停止采集并隐藏接收位置。保留原请求待核验；不会自动重建。": key = "personalLocationShare.status.34"
        case "当前关系或账号不再允许共享。": key = "personalLocationShare.status.35"
        case "账号或会话已变化。位置已停止，不会在新账号下重试原请求。": key = "personalLocationShare.status.36"
        case "暂时无法验证共享状态。不会恢复采集或显示未经验证的位置。": key = "personalLocationShare.status.37"
        case "已重新读取原请求日志；不会自动恢复采集或重放创建。": key = "personalLocationShare.status.journalRecovered"
        default: key = nil
        }
        if let key { return [.init(key: key, arguments: [], fallback: base)] + trailing }
        let prefix = "服务端拒绝共享访问（"
        let suffix = "）。已同步停止采集并清除接收位置；需重新核验会话与授权。"
        if base.hasPrefix(prefix), base.hasSuffix(suffix) {
            let status = String(base.dropFirst(prefix.count).dropLast(suffix.count))
            if Int(status) != nil {
                return [.init(key: "personalLocationShare.status.authorizationRejected", arguments: [status], fallback: base)] + trailing
            }
        }
        return [.init(key: nil, arguments: [], fallback: base)] + trailing
    }
}
