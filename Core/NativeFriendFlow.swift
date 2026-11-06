import Foundation

/// One account/deployment-scoped workflow. A pending command survives navigation, logout and lease expiry.
@MainActor public final class NativeFriendFlow {
    public enum Phase: Equatable { case closed, loading, ready, failed, unknown }
    private var savedPhase: Phase = .closed
    public private(set) var phase: Phase {
        get { isCurrent ? savedPhase : (pending == nil ? .closed : .unknown) }
        set { savedPhase = newValue }
    }
    private var savedIncoming: [NativeFriendItem] = []
    public private(set) var incoming: [NativeFriendItem] {
        get { isCurrent ? savedIncoming : [] }
        set { savedIncoming = newValue }
    }
    private var savedOutgoing: [NativeFriendItem] = []
    public private(set) var outgoing: [NativeFriendItem] {
        get { isCurrent ? savedOutgoing : [] }
        set { savedOutgoing = newValue }
    }
    private var savedFriends: [NativeFriendItem] = []
    public private(set) var friends: [NativeFriendItem] {
        get { isCurrent ? savedFriends : [] }
        set { savedFriends = newValue }
    }
    private var savedGroups: [NativeFriendMetadataGroup] = []
    public var groups: [NativeFriendMetadataGroup] { isCurrent ? savedGroups : [] }
    private var savedReviews: [NativeFriendReview] = []
    public private(set) var reviews: [NativeFriendReview] {
        get { isCurrent ? savedReviews : [] }
        set { savedReviews = newValue }
    }
    private var savedReviewCursor: Int64? = nil
    public private(set) var reviewCursor: Int64? {
        get { isCurrent ? savedReviewCursor : nil }
        set { savedReviewCursor = newValue }
    }
    private var savedLastReview: NativeFriendReview? = nil
    public private(set) var lastReview: NativeFriendReview? {
        get { isCurrent ? savedLastReview : nil }
        set { savedLastReview = newValue }
    }
    private var savedRelationship: NativeFriendRelationship? = nil
    public private(set) var relationship: NativeFriendRelationship? {
        get { isCurrent ? savedRelationship : nil }
        set { savedRelationship = newValue }
    }
    public private(set) var issue: String?
    public private(set) var busy = false
    private var savedRequestCursor: Int64? = nil
    public private(set) var requestCursor: Int64? {
        get { isCurrent ? savedRequestCursor : nil }
        set { savedRequestCursor = newValue }
    }
    private var savedFriendCursor: Int64? = nil
    public private(set) var friendCursor: Int64? {
        get { isCurrent ? savedFriendCursor : nil }
        set { savedFriendCursor = newValue }
    }
    public private(set) var pending: OperationPendingRecord?
    private var pendingCommand: NativeFriendCommand?
    // A source-bound unknown request may only recover its original proof, including from the global friend entry.
    public var canRetryOriginal: Bool { canRecover && service?.canWrite == true && pendingCommand != nil && pendingCommand?.source == nil }
    private let intentJournal: NativeFriendIntentJournal?
    private var savedActionReview: NativeFriendActionReview?
    public var actionReview: NativeFriendActionReview? { isCurrent ? savedActionReview : nil }
    public var isCurrent: Bool { !authorityRetired && service?.isCurrent == true }
    public var canRecover: Bool { isCurrent && pending != nil && !busy }
    public var onChange: (() -> Void)?
    private let service: (any NativeFriendServing)?
    private let journal: any OperationPendingListing
    private let ownerKey: String
    private var generation: UInt64 = 0
    private var authorityRetired = false
    private var authorityTask: Task<Void, Never>?
    private static let prefix = "native-friend.v1."
    public init(service: (any NativeFriendServing)?, journal: any OperationPendingListing, ownerKey: String, intentJournal: NativeFriendIntentJournal? = nil) {
        self.service = service; self.journal = journal; self.ownerKey = ownerKey; self.intentJournal = intentJournal
        // This checks only the captured local grant/context, including while a child page is open.
        // It never requests a network read and is not a notification/presence subscription.
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
                authorityRetired = true; generation &+= 1; busy = false; clearConfirmedState()
                phase = pending == nil ? .closed : .unknown; changed()
            }
            return false
        }
        return true
    }
    public var canWrite: Bool { isCurrent && intentJournal != nil && service?.canWrite == true && pending == nil && !busy && phase == .ready }
    /// A synchronous presentation callback may close this visit before the service starts.
    /// Preserve any original journal entry; never dispatch from that retired visit.
    private func requireCurrentVisit(_ stamp: UInt64) throws {
        guard generation == stamp, isCurrent, !Task.isCancelled else { throw NativeFriendFailure.staleSession }
    }
    private func changed() { onChange?() }
    private func clearConfirmedState() {
        incoming = []; outgoing = []; friends = []; savedGroups = []; reviews = []; lastReview = nil; relationship = nil
        requestCursor = nil; friendCursor = nil; reviewCursor = nil; savedActionReview = nil; pendingCommand = nil
    }
    private func finish(_ service: any NativeFriendServing, stamp: UInt64) {
        guard generation == stamp else { return }
        guard validateAuthority() else { return }
        busy = false; changed()
    }
    private func key(_ command: NativeFriendCommand) -> String { Self.prefix + "\(command.peerID).\(command.action.rawValue)" + (command.reviewID.map { ".review.\($0)" } ?? "") }
    private func identity(_ record: OperationPendingRecord) throws -> (Int64, NativeFriendAction, Int64?) {
        guard record.ownerKey == ownerKey, record.targetKey.hasPrefix(Self.prefix) else { throw NativeFriendFailure.invalid }
        let parts = record.targetKey.dropFirst(Self.prefix.count).split(separator: ".")
        guard [2, 4].contains(parts.count), let peer = Int64(parts[0]), peer > 0, let action = NativeFriendAction(rawValue: String(parts[1])) else { throw NativeFriendFailure.invalid }
        let reviewID = parts.count == 4 ? Int64(parts[3]) : nil
        guard parts.count == 2 || (parts[2] == "review" && action == .cancel && (reviewID ?? 0) > 0) else { throw NativeFriendFailure.invalid }
        return (peer, action, reviewID)
    }
    private func restorePendingIntent() throws {
        pending = try journal.pendingRecords(ownerKey: ownerKey).first { $0.targetKey.hasPrefix(Self.prefix) }
        if isCurrent { pendingCommand = try intentJournal?.restore() } else { pendingCommand = nil }
        if let command = pendingCommand {
            guard let uuid = UUID(uuidString: command.requestID) else { throw NativeFriendFailure.invalid }
            let expected = OperationPendingRecord(operationID: uuid, ownerKey: ownerKey, targetKey: key(command))
            if let pending { guard pending == expected else { throw NativeFriendFailure.unknown } }
            else { try journal.write(expected); pending = expected }
            guard try journal.pending(ownerKey: ownerKey, targetKey: expected.targetKey) == expected else { throw NativeFriendFailure.unknown }
        }
    }
    public func load() async {
        guard !busy else { return }
        generation &+= 1; let stamp = generation
        issue = nil; savedActionReview = nil
        // A refresh replaces confirmed data only after both reads succeed. Identity loss is different:
        // old account / withdrawn-grant content must disappear even if the next read fails.
        if service?.isCurrent != true { clearConfirmedState() }
        do { try restorePendingIntent() }
        catch { phase = .failed; issue = "friend.storageFailure"; changed(); return }
        guard let service, validateAuthority() else { phase = pending == nil ? .closed : .unknown; changed(); return }
        busy = true; phase = .loading; changed()
        defer { finish(service, stamp: stamp) }
        do {
            try await refresh(service, stamp: stamp)
            // An explicit refresh retires the old single-result banner. The newly fetched lists
            // are authoritative; an older pending-review receipt must not contradict a terminal row.
            relationship = nil; lastReview = nil; phase = pending == nil ? .ready : .unknown
        }
        catch { if generation == stamp { phase = pending == nil ? .failed : .unknown; issue = "friend.loadFailure" } }
    }
    private func refresh(_ service: any NativeFriendServing, stamp: UInt64) async throws {
        try requireCurrentVisit(stamp)
        let requests = try await service.page(requests: true, cursor: 0)
        guard generation == stamp, isCurrent, !Task.isCancelled else { throw NativeFriendFailure.staleSession }
        try requireCurrentVisit(stamp)
        let list = try await service.page(requests: false, cursor: 0)
        guard generation == stamp, service.isCurrent, !Task.isCancelled else { throw NativeFriendFailure.staleSession }
        incoming = requests.incoming; outgoing = requests.outgoing; friends = list.friends; savedGroups = list.groups?.list ?? []; reviews = requests.reviews ?? []
        reviewCursor = requests.reviewHasMore == true ? requests.reviewNextCursor : nil
        requestCursor = requests.hasMore ? requests.nextCursor : nil; friendCursor = list.hasMore ? list.nextCursor : nil
    }
    public func loadMore(requests: Bool) async {
        guard validateAuthority(), !busy, let service, let cursor = requests ? requestCursor : friendCursor else { return }
        let stamp = generation; busy = true; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let page = try await service.page(requests: requests, cursor: cursor)
            guard generation == stamp, service.isCurrent, !Task.isCancelled else { return }
            if requests {
                incoming = merged(incoming, page.incoming); outgoing = merged(outgoing, page.outgoing)
                requestCursor = page.hasMore ? page.nextCursor : nil
            } else {
                // A renamed/deleted/reordered group snapshot cannot be merged with older sections.
                guard savedGroups == (page.groups?.list ?? []) else {
                    friends=[];savedGroups=[];friendCursor=nil;phase = .failed;issue="friend.loadFailure";return
                }
                friends = merged(friends, page.friends);friendCursor = page.hasMore ? page.nextCursor : nil
            }
        } catch { if generation == stamp { issue = "friend.loadFailure" } }
    }
    public func loadMoreReviews() async {
        guard validateAuthority(), !busy, let service, let cursor = reviewCursor else { return }
        let stamp = generation; busy = true; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let page = try await service.reviewPage(cursor: cursor)
            guard generation == stamp, service.isCurrent, !Task.isCancelled else { return }
            let next = page.reviews ?? []; let replacing = Set(next.map(\.id))
            reviews = reviews.filter { !replacing.contains($0.id) } + next
            reviewCursor = page.reviewHasMore == true ? page.reviewNextCursor : nil
        } catch { if generation == stamp { issue = "friend.loadFailure" } }
    }
    private func merged(_ old: [NativeFriendItem], _ new: [NativeFriendItem]) -> [NativeFriendItem] {
        let replacing = Set(new.map(\.peerID)); return old.filter { !replacing.contains($0.peerID) } + new
    }
    public func reviewRequest(peerID: Int64, message: String, source: NativeFriendChannelSource? = nil) {
        guard validateAuthority(), canWrite, savedActionReview == nil, let service,
              peerID > 0, peerID != service.viewerID, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              message.unicodeScalars.count <= 60 else { return }
        guard source == nil || source?.isValid == true else { return }
        savedActionReview = .init(command: .init(peerID: peerID, action: .request, message: message, source: source))
        issue = nil; changed()
    }
    /// F26 selected incoming member: re-read the original pair and bind the exact displayed version.
    /// This does not fabricate a first-page request row or accept automatically.
    public func reviewIncomingFromChannel(peerID: Int64, expectedVersion: Int64) async {
        guard validateAuthority(), canWrite, savedActionReview == nil, let service, peerID > 0, expectedVersion > 0 else { return }
        let stamp = generation; busy = true; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let original = try await service.relationship(peerID: peerID)
            guard generation == stamp, isCurrent, !Task.isCancelled, original.state == .pendingIncoming, original.version == expectedVersion else { throw NativeFriendFailure.unknown }
            savedActionReview = .init(command: .init(peerID: peerID, action: .accept, expectedVersion: expectedVersion))
            issue = nil
        } catch { if generation == stamp { savedActionReview = nil; issue = "friend.conflict" } }
    }
    public func reviewAction(_ action: NativeFriendAction, item: NativeFriendItem) {
        guard validateAuthority(), canWrite, savedActionReview == nil,
              ((action == .accept || action == .reject) && incoming.contains(item)) ||
              (action == .cancel && outgoing.contains(item)) else { return }
        savedActionReview = .init(command: .init(peerID: item.peerID, action: action, expectedVersion: item.version), item: item)
        issue = nil; changed()
    }
    public func reviewCancellation(_ proposal: NativeFriendReview) {
        guard validateAuthority(), canWrite, savedActionReview == nil, proposal.state == .pending, reviews.contains(proposal) else { return }
        savedActionReview = .init(command: .init(peerID: proposal.peerID, action: .cancel,
            expectedVersion: proposal.version, reviewID: proposal.id), proposal: proposal)
        issue = nil; changed()
    }
    public func cancelReview() { savedActionReview = nil; changed() }
    public func confirmReview() async {
        guard let expected = savedActionReview else { return }
        await confirmReview(expected: expected)
    }
    /// A queued sheet action cannot authorize a replacement application or command.
    public func confirmReview(expected: NativeFriendActionReview) async {
        guard validateAuthority(), canWrite, let review = savedActionReview, review == expected else { return }
        // A refresh retires the review. Never substitute a newly received application for this version.
        if let item = review.item {
            guard (review.command.action == .cancel ? outgoing : incoming).contains(item) else {
                savedActionReview = nil; issue = "friend.conflict"; changed(); return
            }
        }
        if let proposal = review.proposal {
            guard reviews.contains(proposal), proposal.state == .pending else {
                savedActionReview = nil; issue = "friend.conflict"; changed(); return
            }
        }
        savedActionReview = nil
        // No suspension between consuming the one-shot review and the existing durable write fence.
        await perform(review.command)
    }
    public func perform(_ command: NativeFriendCommand) async {
        guard validateAuthority(), canWrite, let service, let intentJournal, intentJournal.acquire() else { return }
        defer { intentJournal.release() }
        savedActionReview = nil
        let stamp = generation
        let record = OperationPendingRecord(operationID: UUID(uuidString: command.requestID) ?? UUID(), ownerKey: ownerKey, targetKey: key(command))
        // Command ID must match the durable identity exactly, not a fallback-generated retry key.
        guard record.operationID.uuidString.caseInsensitiveCompare(command.requestID) == .orderedSame else { issue = "friend.invalid"; changed(); return }
        do {
            // Other navigation stacks may hold another ready flow for this same account/deployment.
            // Check-and-write is synchronous on MainActor: no suspension may split this owner-wide fence.
            if let existing = try journal.pendingRecords(ownerKey: ownerKey).first(where: { $0.targetKey.hasPrefix(Self.prefix) }) {
                pending = existing; phase = .unknown; issue = "friend.unknown"; changed(); return
            }
            try intentJournal.save(command); pendingCommand = command
            try journal.write(record); pending = record
            guard try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) == record,
                  try intentJournal.restore() == command else { throw NativeFriendFailure.unknown }
        } catch {
            do { try restorePendingIntent(); phase = pending == nil ? .failed : .unknown }
            catch { pending = record; phase = .unknown }
            issue = "friend.storageFailure"; changed(); return
        }
        busy = true; issue = nil; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let receipt = try await service.write(command)
            guard generation == stamp, service.isCurrent, !Task.isCancelled else { return }
            try resolve(receipt, record: record, service: service)
            phase = .ready
            do { try await refresh(service, stamp: stamp) } catch { if generation == stamp { phase = pending == nil ? .failed : .unknown; issue = "friend.loadFailure" } }
        } catch NativeFriendFailure.notSent { clearRejected(record, stamp: stamp, issue: "friend.notSent") }
        catch NativeFriendFailure.rejected(let code) {
            clearRejected(record, stamp: stamp, issue: code == 401 ? "friend.sessionExpired" : (code == 409 ? "friend.conflict" : "friend.rejected"))
            if code == 409, generation == stamp, pending == nil, isCurrent {
                // A definite stale-version refusal retires the reviewed row before another gesture.
                // The server remains the version authority; never change the command and retry it.
                do { try await refresh(service, stamp: stamp) }
                catch { if generation == stamp { phase = .failed; issue = "friend.loadFailure" } }
            }
        }
        catch { if generation == stamp { phase = .unknown; issue = "friend.unknown" } }
    }
    private func clearRejected(_ record: OperationPendingRecord, stamp: UInt64, issue: String) {
        do {
            if let stored = try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) {
                guard stored == record else { throw NativeFriendFailure.unknown }
                try journal.clear(record)
            }
            if let command = try intentJournal?.restore() {
                guard command.requestID.caseInsensitiveCompare(record.operationID.uuidString) == .orderedSame else { throw NativeFriendFailure.unknown }
                try intentJournal?.settle(command); pendingCommand = nil
            }
            // Definite non-execution can retire the old identity even if unauthorized handling retired its UI.
            if generation == stamp { pending = nil; phase = .ready; self.issue = issue }
        } catch { if generation == stamp { phase = .unknown; self.issue = "friend.storageFailure" } }
    }
    private func resolve(_ receipt: NativeFriendReceipt, record: OperationPendingRecord, service: any NativeFriendServing) throws {
        let (peer, action, reviewID) = try identity(record)
        guard receipt.viewerID == service.viewerID, receipt.peerID == peer, receipt.action == action,
              receipt.requestID.caseInsensitiveCompare(record.operationID.uuidString) == .orderedSame,
              ["APPLIED", "PENDING_REVIEW", "REJECTED", "CANCELLED", "EXPIRED", "INVALIDATED"].contains(receipt.outcome), let result = receipt.relationship,
              result.viewerID == service.viewerID, result.peerID == peer else { throw NativeFriendFailure.unknown }
        if let expected = reviewID {
            guard receipt.review?.id == expected, receipt.review?.state == .cancelled, receipt.outcome == "APPLIED" else { throw NativeFriendFailure.unknown }
        } else if action == .cancel && receipt.review != nil { throw NativeFriendFailure.unknown }
        if receipt.outcome != "APPLIED" {
            guard action == .request, let review = receipt.review, review.peerID == peer, review.state.rawValue == receipt.outcome,
                  review.requestID.caseInsensitiveCompare(receipt.requestID) == .orderedSame else { throw NativeFriendFailure.unknown }
        }
        let intent = try intentJournal?.restore()
        if let intent {
            guard intent.requestID.caseInsensitiveCompare(record.operationID.uuidString) == .orderedSame,
                  intent.peerID == peer, intent.action == action, intent.reviewID == reviewID,
                  receipt.payloadHash == intent.originalIntentProof else { throw NativeFriendFailure.unknown }
        }
        if let stored = try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) {
            guard stored == record else { throw NativeFriendFailure.unknown } // Never clear a newer command from another page.
            try journal.clear(record)
        }
        if let intent { try intentJournal?.settle(intent) }
        pendingCommand = nil
        // Another page may already have resolved this identity. The matched APPLIED receipt, not absence, proves success.
        pending = nil; relationship = result; lastReview = receipt.review
    }
    public func recover() async {
        guard validateAuthority(), canRecover, let service, let record = pending else { return }
        let stamp = generation; busy = true; changed(); defer { finish(service, stamp: stamp) }
        do {
            let (peer, action, _) = try identity(record)
            try requireCurrentVisit(stamp)
            let receipt = try await service.receipt(peerID: peer, action: action, requestID: record.operationID.uuidString)
            guard generation == stamp, service.isCurrent, !Task.isCancelled else { return }
            try resolve(receipt, record: record, service: service)
            try restorePendingIntent()
            phase = pending == nil ? .ready : .unknown; issue = nil
            do { try await refresh(service, stamp: stamp) } catch { if generation == stamp { phase = pending == nil ? .failed : .unknown; issue = "friend.loadFailure" } }
        } catch { if generation == stamp { phase = .unknown; issue = "friend.unknown" } }
    }
    /// Explicit gesture only. Read the original request first; replay the protected exact body/key, never reconstruct one.
    public func retryOriginal() async {
        guard validateAuthority(), canRetryOriginal, let service, let record = pending,
              let intentJournal, intentJournal.acquire() else { return }
        let stamp = generation; busy = true; changed()
        defer { intentJournal.release(); finish(service, stamp: stamp) }
        do {
            guard let command = try intentJournal.restore(), command == pendingCommand,
                  command.requestID.caseInsensitiveCompare(record.operationID.uuidString) == .orderedSame else { throw NativeFriendFailure.unknown }
            try requireCurrentVisit(stamp)
            let prior = try await service.receipt(peerID: command.peerID, action: command.action, requestID: command.requestID)
            guard generation == stamp, service.isCurrent, !Task.isCancelled else { return }
            if prior.outcome != "UNKNOWN" { try resolve(prior, record: record, service: service) }
            else {
                try requireCurrentVisit(stamp)
                // An independent recovery page may have settled the original while
                // its receipt read was suspended. A cached UNKNOWN is not authority
                // to send after the durable original has disappeared or changed.
                guard pending == record,
                      try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) == record,
                      try intentJournal.restore() == command else { throw NativeFriendFailure.unknown }
                let receipt = try await service.write(command)
                guard generation == stamp, service.isCurrent, !Task.isCancelled else { return }
                try resolve(receipt, record: record, service: service)
            }
            phase = .ready; issue = nil
            do { try await refresh(service, stamp: stamp) } catch { if generation == stamp { phase = .failed; issue = "friend.loadFailure" } }
        } catch {
            // Even a definite refusal of this retry cannot disprove a previous uncertain attempt.
            if generation == stamp { phase = .unknown; issue = "friend.unknown" }
        }
    }
    /// Read-only existing-chat handoff, never the old /api/im/start write.
    public func existingConversation(peerID: Int64) async -> Int? {
        guard validateAuthority(), !busy, let service else { return nil }
        let stamp = generation; busy = true; changed(); defer { finish(service, stamp: stamp) }
        do {
            try requireCurrentVisit(stamp)
            let result = try await service.relationship(peerID: peerID)
            guard generation == stamp, service.isCurrent, !Task.isCancelled else { return nil }
            guard result.viewerID == service.viewerID, result.peerID == peerID else { throw NativeFriendFailure.invalid }
            relationship = result; lastReview = nil
            guard let id = result.conversationID, id > 0 else { issue = "friend.noConversation"; return nil };return id
        } catch { if generation == stamp && isCurrent { issue = "friend.loadFailure" }; return nil }
    }
    public func invalidate() {
        generation &+= 1; busy = false; clearConfirmedState()
        phase = .closed; issue = nil; changed()
        // No journal clearing. The same account can recover after sign-in; another account cannot see it.
    }
}
