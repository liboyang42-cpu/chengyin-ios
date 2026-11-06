import Foundation

/// Owner-private remark/star editor: explicit review, durable proof-only recovery and no invented settlement/replay body.
@MainActor public final class NativeFriendMetadataFlow {
    public enum Phase: Equatable { case closed, loading, ready, reviewing, saving, unknown, resolved, failed, unavailable }
    public let peerID: Int64
    private var savedPhase: Phase = .closed
    public private(set) var phase: Phase {
        get { isCurrent ? savedPhase : (pending == nil ? .closed : .unknown) }
        set { savedPhase = newValue }
    }
    private var savedMetadata: NativeFriendMetadata?
    public private(set) var metadata: NativeFriendMetadata? {
        get { isCurrent ? savedMetadata : nil }
        set { savedMetadata = newValue }
    }
    private var savedGroups: [NativeFriendMetadataGroup] = []
    public private(set) var groups: [NativeFriendMetadataGroup] {
        get { isCurrent ? savedGroups : [] }
        set { savedGroups = newValue }
    }
    private var savedReview: NativeFriendMetadataCommand?
    public private(set) var review: NativeFriendMetadataCommand? {
        get { isCurrent ? savedReview : nil }
        set { savedReview = newValue }
    }
    public private(set) var pending: OperationPendingRecord?
    public private(set) var issue: String?
    /// Local recovery/read failure never changes a matching server terminal outcome back to UNKNOWN.
    public private(set) var recoveryIssue: String?
    public private(set) var busy = false
    public private(set) var didApply = false
    public var onChange: (() -> Void)?
    public var onApplied: (() -> Void)?
    private let service: (any NativeFriendMetadataServing)?
    private let journal: any OperationPendingListing
    private let ownerKey: String
    private var generation: UInt64 = 0
    private var authorityRetired = false
    private var authorityTask: Task<Void, Never>?
    public var isCurrent: Bool { !authorityRetired && service?.isCurrent == true }
    public private(set) var resolvedIdentity: PendingIdentity?
    public var canPresentPeer: Bool { peerID > 0 && isCurrent && (pending == nil || (pendingIdentity?.action == .remark && pendingIdentity?.targetID == peerID)) }
    public var canRecover: Bool { !busy && isCurrent && pending != nil }
    private static let prefix = "native-friend-metadata.v1."
    public init(peerID: Int64, service: (any NativeFriendMetadataServing)?, journal: any OperationPendingListing, ownerKey: String) {
        self.peerID = peerID; self.service = service; self.journal = journal; self.ownerKey = ownerKey
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
                authorityRetired = true; generation &+= 1; busy = false; metadata = nil; groups = []; review = nil
                resolvedIdentity = nil; didApply = false; recoveryIssue = nil; phase = pending == nil ? .closed : .unknown; changed()
            }
            return false
        }
        return true
    }
    public var canEdit: Bool { phase == .ready && !busy && pending == nil && metadata != nil && isCurrent && service?.canWrite == true }
    public var canEditStar: Bool { canEdit && service?.canStarWrite == true }
    public var canEditProgress: Bool { canEdit && metadata?.progressScope != nil && service?.canProgressWrite == true }
    public var canManageGroups: Bool { phase == .ready && !busy && pending == nil && isCurrent && !groups.isEmpty && service?.canManageGroups == true }
    public var canAssignGroup: Bool { canEdit && !groups.isEmpty && service?.canAssignGroup == true }
    public var canConfirm: Bool {
        guard phase == .reviewing, let review, !busy, pending == nil, isCurrent else { return false }
        if review.action != .remark { return service?.canManageGroups == true }
        return service?.canWrite == true && (review.starred == nil || service?.canStarWrite == true) && (!review.updatesGroup || service?.canAssignGroup == true) && (review.progressScope == nil || service?.canProgressWrite == true)
    }
    /// Presentation comes only from the durable original identity, never the currently open friend's row.
    public struct PendingIdentity: Equatable {
        public let action: NativeFriendMetadataAction
        public let targetID: Int64
        public let requestID: UUID
        public var shortRequestID: String { String(requestID.uuidString.prefix(8)) }
        public var actionLabelKey: String {
            switch action {
            case .remark: return "friendMeta.pendingRemark"
            case .groupSave: return targetID == 0 ? "friendMeta.pendingGroupCreate" : "friendMeta.pendingGroupEdit"
            case .groupDelete: return "friendMeta.pendingGroupDelete"
            }
        }
        public var targetLabelKey: String {
            action == .remark ? "friendMeta.pendingFriendTarget" : (targetID == 0 ? "friendMeta.pendingNewGroupTarget" : "friendMeta.pendingGroupTarget")
        }
    }
    public var pendingIdentity: PendingIdentity? {
        guard isCurrent, let pending, let (action, target, _) = try? identity(pending) else { return nil }
        return PendingIdentity(action: action, targetID: target, requestID: pending.operationID)
    }
    public var hasResolvedPending: Bool { resolvedIdentity != nil && resolvedIdentity == pendingIdentity }
    /// A synchronous presentation callback may close this visit before the service starts.
    /// Preserve any original journal entry; never dispatch from that retired visit.
    private func requireCurrentVisit(_ stamp: UInt64) throws {
        guard generation == stamp, isCurrent, !Task.isCancelled else { throw NativeFriendFailure.staleSession }
    }
    private func changed() { onChange?() }
    public var canSettle: Bool { false }
    private func key(_ command: NativeFriendMetadataCommand) throws -> String { Self.prefix + command.action.rawValue + ".\(command.targetID)." + (try command.fingerprint()) }
    private func identity(_ record: OperationPendingRecord) throws -> (NativeFriendMetadataAction, Int64, String?) {
        guard record.ownerKey == ownerKey, record.targetKey.hasPrefix(Self.prefix) else { throw NativeFriendFailure.invalid }
        let parts = record.targetKey.dropFirst(Self.prefix.count).split(separator: ".")
        guard [2, 3].contains(parts.count), let action = NativeFriendMetadataAction(rawValue: String(parts[0])), let target = Int64(parts[1]),
              target > 0 || (target == 0 && action == .groupSave) else { throw NativeFriendFailure.invalid }
        let hash = parts.count == 3 ? String(parts[2]) : nil
        guard hash == nil || hash?.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw NativeFriendFailure.invalid }
        return (action, target, hash)
    }
    private func finish(_ service: any NativeFriendMetadataServing, stamp: UInt64) {
        guard generation == stamp else { return }
        if !service.isCurrent { metadata = nil; groups = []; review = nil; phase = pending == nil ? .closed : .unknown }
        busy = false; changed()
    }
    public func load() async {
        guard !busy else { return }
        generation &+= 1; let stamp = generation; review = nil; issue = nil; recoveryIssue = nil; didApply = false; resolvedIdentity = nil; metadata = nil; groups = []
        if service?.isCurrent != true { metadata = nil; groups = [] }
        do { pending = try journal.pendingRecords(ownerKey: ownerKey).first { $0.targetKey.hasPrefix(Self.prefix) } }
        catch { phase = .failed; issue = "friendMeta.storageFailure"; changed(); return }
        guard let service, validateAuthority() else { phase = pending == nil ? .closed : .unknown; changed(); return }
        // The original receipt is independently readable even after this friend disappears.
        // Do not put a current friend/group request in front of durable recovery after restart.
        if pending != nil { phase = .unknown; changed(); return }
        busy = true; phase = .loading; changed(); defer { finish(service, stamp: stamp) }
        do { try await refresh(service, stamp: stamp); phase = pending == nil ? .ready : .unknown }
        catch { failRead(error, stamp: stamp) }
    }
    private func refresh(_ service: any NativeFriendMetadataServing, stamp: UInt64) async throws {
        var next: NativeFriendMetadata?
        if peerID > 0 {
            try requireCurrentVisit(stamp)
            next = try await service.read(peerID: peerID)
            guard generation == stamp, isCurrent, !Task.isCancelled,
                  next?.viewerID == service.viewerID, next?.peerID == peerID else { throw NativeFriendFailure.invalid }
        }
        var nextGroups: [NativeFriendMetadataGroup] = []
        if service.canReadGroups {
            try requireCurrentVisit(stamp)
            let value = try await service.groups()
            guard generation == stamp, isCurrent, !Task.isCancelled,
                  NativeFriendMetadataValidation.validGroups(value, viewerID: service.viewerID) else { throw NativeFriendFailure.invalid }
            nextGroups = value.list
        }
        // peerID == 0 also hosts original-result recovery; no group grant is needed to read a remark receipt.
        metadata = next; groups = nextGroups
    }
    private func failRead(_ error: Error, stamp: UInt64) {
        guard generation == stamp else { return }
        metadata = nil; groups = []
        if pending != nil { phase = .unknown; issue = "friendMeta.unknown" }
        else if case NativeFriendMetadataFailure.rejected(404, _) = error { phase = .unavailable; issue = "friendMeta.noLongerFriend" }
        else if case NativeFriendFailure.rejected(404) = error { phase = .unavailable; issue = "friendMeta.noLongerFriend" }
        else { phase = .failed; issue = "friendMeta.loadFailure" }
    }
    public func reviewMetadata(remark: String, groupID: Int64?, starred: Bool) {
        guard canEdit, let current = metadata else { return }
        let text = NativeFriendMetadataValidation.remark(remark)
        guard NativeFriendMetadataValidation.validRemark(text) else { issue = "friendMeta.invalidRemark"; changed(); return }
        review = .init(action: .remark, targetID: peerID, expectedVersion: current.version, expectedFriendVersion: current.friendVersion,
                       remark: text)
        phase = .reviewing; issue = nil; recoveryIssue = nil; didApply = false; resolvedIdentity = nil; changed()
    }
    public func reviewStar(_ selected: Bool) {
        guard canEditStar, let current = metadata else { return }
        let desired = selected ? 1 : 0
        guard desired != current.starred else { return }
        review = .init(action: .remark, targetID: peerID, expectedVersion: current.version, expectedFriendVersion: current.friendVersion,
                       starred: desired, updatesRemark: false)
        phase = .reviewing; issue = nil; recoveryIssue = nil; didApply = false; resolvedIdentity = nil; changed()
    }
    public func reviewProgress(_ selected: Bool) {
        guard canEditProgress, let current = metadata else { return }
        let desired = selected ? 1 : 0
        guard desired != current.progressScope else { return }
        review = .init(action: .remark, targetID: peerID, expectedVersion: current.version, expectedFriendVersion: current.friendVersion,
                       updatesRemark: false, progressScope: desired)
        phase = .reviewing; issue = nil; recoveryIssue = nil; didApply = false; resolvedIdentity = nil; changed()
    }
    public func reviewAssignment(_ selected: Int64?) {
        guard canAssignGroup, let current = metadata else { return }
        let group = selected == 0 ? nil : selected
        guard group == nil || groups.contains(where: { $0.id == group && $0.isDefault == 0 }), group != current.groupID else { return }
        review = .init(action: .remark, targetID: peerID, expectedVersion: current.version, expectedFriendVersion: current.friendVersion,
                       groupID: group, updatesRemark: false, updatesGroup: true)
        phase = .reviewing;issue = nil;recoveryIssue = nil;didApply = false;resolvedIdentity = nil;changed()
    }
    public func reviewGroup(id: Int64?, name: String, position: Int) {
        guard canManageGroups else { return }
        let normalized = NativeFriendMetadataValidation.groupName(name)
        guard NativeFriendMetadataValidation.validGroupName(normalized), (0...Int(Int32.max)).contains(position) else { issue="friendMeta.invalidGroup";changed();return }
        var version: Int64 = 0
        if let id {
            guard let owned = groups.first(where: { $0.id == id && $0.isDefault == 0 }) else { return };version=owned.version
        } else if groups.count >= 20 { issue="friendMeta.groupLimit";changed();return }
        review = .init(action: .groupSave, targetID: id ?? 0, expectedVersion: version, name: normalized, position: position)
        phase = .reviewing;issue = nil;recoveryIssue = nil;didApply = false;resolvedIdentity = nil;changed()
    }
    public func reviewDeleteGroup(id: Int64, moveTo: Int64?) {
        guard canManageGroups,let owned=groups.first(where: { $0.id == id && $0.isDefault == 0 }) else { return }
        let destination=moveTo == 0 ? nil : moveTo
        guard destination != id, destination == nil || groups.contains(where: { $0.id == destination && $0.isDefault == 0 }) else { return }
        review = .init(action: .groupDelete, targetID: id, expectedVersion: owned.version, groupID: destination)
        phase = .reviewing;issue = nil;recoveryIssue = nil;didApply = false;resolvedIdentity = nil;changed()
    }
    public func cancelReview() { guard !busy, pending == nil else { return }; review = nil; phase = .ready; changed() }
    public func confirm() async {
        guard let expected = review else { return }
        await confirm(expected: expected)
    }
    /// The visible review authorizes only this original immutable command.
    public func confirm(expected: NativeFriendMetadataCommand) async {
        guard canConfirm, let command = review, command == expected, let service else { return }
        let stamp = generation
        let record: OperationPendingRecord
        do { record = OperationPendingRecord(operationID: command.requestID, ownerKey: ownerKey, targetKey: try key(command)) }
        catch { issue = "friendMeta.storageFailure"; changed(); return }
        do {
            // Owner-wide MainActor fence spans navigation stacks, without persisting private remark text.
            if let existing = try journal.pendingRecords(ownerKey: ownerKey).first(where: { $0.targetKey.hasPrefix(Self.prefix) }) {
                pending = existing; review = nil; phase = .unknown; issue = "friendMeta.unknown"; changed(); return
            }
            try journal.write(record); pending = record
            guard try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) == record else { throw NativeFriendFailure.unknown }
        } catch { pending = record; review = nil; phase = .unknown; issue = "friendMeta.storageFailure"; changed(); return }
        review = nil; busy = true; phase = .saving; issue = nil; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let result = try await service.write(command)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            guard try resolve(result, record: record, service: service) else { return }
            await refreshAfterResolution(service, stamp: stamp)
        } catch NativeFriendFailure.notSent { reject(record, issue: "friendMeta.notSent", stamp: stamp) }
        catch NativeFriendMetadataFailure.rejected(let code, let key) {
            let issue: String
            switch key {
            case "STAR_LIMIT_REACHED": issue = "friendMeta.starLimit"
            case "GROUP_LIMIT_REACHED": issue = "friendMeta.groupLimit"
            case "GROUP_NAME_DUPLICATE": issue = "friendMeta.groupDuplicate"
            default: issue = code == 409 ? "friendMeta.conflict" : (code == 404 ? "friendMeta.noLongerFriend" : "friendMeta.rejected")
            }
            if generation == stamp { phase = .unknown; self.issue = issue }
        }
        catch NativeFriendFailure.rejected(let code) {
            if generation == stamp { phase = .unknown; issue = code == 409 ? "friendMeta.conflict" : (code == 404 ? "friendMeta.noLongerFriend" : "friendMeta.rejected") }
        } catch { if generation == stamp { phase = .unknown; issue = "friendMeta.unknown" } }
    }
    private func clear(_ record: OperationPendingRecord) throws {
        if let stored = try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) {
            guard stored == record else { throw NativeFriendFailure.unknown }; try journal.clear(record)
        }
        pending = nil
    }
    private func reject(_ record: OperationPendingRecord, issue: String, stamp: UInt64) {
        do {
            try clear(record)
            if generation == stamp { phase = .failed; self.issue = issue; metadata = nil; groups = [] }
        } catch { if generation == stamp { phase = .unknown; self.issue = "friendMeta.storageFailure" } }
    }
    @discardableResult private func resolve(_ receipt: NativeFriendMetadataReceipt, record: OperationPendingRecord, service: any NativeFriendMetadataServing) throws -> Bool {
        let (action, target, hash) = try identity(record)
        guard let hash, receipt.payloadHash == hash, receipt.viewerID == service.viewerID, receipt.action == action, receipt.targetID == target,
              UUID(uuidString: receipt.requestID) == record.operationID, ["APPLIED", "REJECTED"].contains(receipt.outcome) else { throw NativeFriendFailure.unknown }
        if let current = receipt.current {
            guard action == .remark, current.viewerID == service.viewerID, current.peerID == target else { throw NativeFriendFailure.unknown }
        }
        if receipt.outcome == "REJECTED" { guard receipt.current == nil && receipt.groups == nil else { throw NativeFriendFailure.unknown } }
        if receipt.outcome == "APPLIED" && action != .remark { guard receipt.groups?.viewerID == service.viewerID else { throw NativeFriendFailure.unknown } }
        let resolved = PendingIdentity(action: action, targetID: target, requestID: record.operationID)
        let alreadyResolved = resolvedIdentity == resolved
        resolvedIdentity = resolved; didApply = receipt.outcome == "APPLIED"; phase = .resolved; recoveryIssue = nil
        metadata = nil; groups = []
        if didApply { issue=nil }
        else { switch receipt.reason { case "STAR_LIMIT_REACHED": issue="friendMeta.starLimit";case "GROUP_LIMIT_REACHED": issue="friendMeta.groupLimit";case "GROUP_NAME_DUPLICATE": issue="friendMeta.groupDuplicate";default: issue="friendMeta.finalized" } }
        // The result is already proven. Failed local cleanup must keep its identity and outcome visible.
        do { try clear(record) }
        catch { recoveryIssue = "friendMeta.cleanupFailure"; changed(); if didApply && !alreadyResolved { onApplied?() }; return false }
        changed(); if didApply && !alreadyResolved { onApplied?() }
        return true
    }
    private func refreshAfterResolution(_ service: any NativeFriendMetadataServing, stamp: UInt64) async {
        guard generation == stamp, isCurrent, !Task.isCancelled else { return }
        metadata = nil; groups = []
        do { pending = try journal.pendingRecords(ownerKey: ownerKey).first { $0.targetKey.hasPrefix(Self.prefix) } }
        catch { phase = .resolved; recoveryIssue = "friendMeta.pendingReadFailure"; changed(); return }
        // A second durable original request takes precedence over today's friend/group projection.
        guard pending == nil else { phase = .unknown; changed(); return }
        changed()
        do { try await refresh(service, stamp: stamp); phase = .ready }
        catch {
            guard generation == stamp else { return }
            metadata = nil; groups = []; phase = .resolved; recoveryIssue = "friendMeta.currentUnavailable"
        }
    }
    public func recover() async {
        guard !Task.isCancelled, !busy, let service, validateAuthority(), let record = pending else { return }
        let stamp = generation; busy = true; changed(); defer { finish(service, stamp: stamp) }
        if hasResolvedPending {
            // This screen already validated the terminal proof. Retry only its local cleanup;
            // after restart that in-memory proof is gone and the same UUID must be read again.
            do { try clear(record); recoveryIssue = nil; await refreshAfterResolution(service, stamp: stamp) }
            catch { phase = .resolved; recoveryIssue = "friendMeta.cleanupFailure" }
            return
        }
        do {
            let (action, target, _) = try identity(record)
            try requireCurrentVisit(stamp)
            let receipt = try await service.receipt(action: action, targetID: target, requestID: record.operationID)
            guard generation == stamp, isCurrent, !Task.isCancelled else { return }
            guard try resolve(receipt, record: record, service: service) else { return }
            await refreshAfterResolution(service, stamp: stamp)
        } catch { if generation == stamp { phase = .unknown; issue = "friendMeta.unknown" } }
    }
    /// No formal settlement rule; identity/hash cannot reconstruct a private remark body after restart.
    public func settleOriginal() async { }
    public func invalidate() {
        generation &+= 1; metadata = nil; groups = []; review = nil; resolvedIdentity = nil; didApply = false; busy = false; phase = .closed; issue = nil; recoveryIssue = nil; changed()
        // Pending request identity is retained for this account/deployment after navigation or sign-out.
    }
}
