import Foundation

public struct IMMediaSelection: Equatable {
    public let id: UUID
    public let scope: IMScope
    public let bytes: Data
    public let mimeType: String
    public let fileExtension: String
    public init(scope: IMScope, bytes: Data, mimeType: String, fileExtension: String, id: UUID = UUID()) throws {
        self.id = id; self.scope = scope; self.bytes = bytes; self.mimeType = mimeType; self.fileExtension = fileExtension
        try validateImage()
    }
    public func validateImage() throws {
        guard !bytes.isEmpty, bytes.count <= SocialMessageMediaService.maximumBytes else { throw SocialMediaFailure.tooLarge }
        let p = Array(bytes.prefix(12))
        let jpeg = mimeType == "image/jpeg" && fileExtension == "jpg" && p.starts(with: [255,216,255])
        let png = mimeType == "image/png" && fileExtension == "png" && p.starts(with: [137,80,78,71,13,10,26,10])
        // A deployment's real picker must decode and re-encode, strip metadata and enforce
        // dimensions before providing these bytes. Signatures alone do not prove decodability.
        guard jpeg || png else { throw SocialMediaFailure.notImage }
    }
}
public struct IMMediaConsent: Equatable {
    public enum Purpose: Equatable { case selection, upload }
    public let scope: IMScope
    public let selectionID: UUID
    public let purpose: Purpose
    public init(scope: IMScope, selectionID: UUID, purpose: Purpose) { self.scope = scope; self.selectionID = selectionID; self.purpose = purpose }
}
@MainActor public protocol IMImageSelecting: AnyObject {
    var isConfigured: Bool { get }
    func select(scope: IMScope, consent: IMMediaConsent) async throws -> IMMediaSelection?
    func cancel()
}
/// No PhotosUI, AVFoundation, file-system picker or permission prompts in default composition.
@MainActor public final class IMDormantImagePicker: IMImageSelecting {
    public var isConfigured: Bool { false }
    public init() {}
    public func select(scope: IMScope, consent: IMMediaConsent) async throws -> IMMediaSelection? { throw APIError.notConfigured }
    public func cancel() {}
}
@MainActor public final class IMFixtureImagePicker: IMImageSelecting {
    public var isConfigured: Bool { true }
    public var selection: IMMediaSelection?
    public private(set) var selectionCount = 0
    public init(selection: IMMediaSelection?) { self.selection = selection }
    public func select(scope: IMScope, consent: IMMediaConsent) async throws -> IMMediaSelection? {
        guard consent.scope == scope, consent.purpose == .selection else { throw IMCapabilityGap.consentRequired }
        guard selection?.scope == scope || selection == nil else { throw IMCapabilityGap.staleScope }
        selectionCount += 1; return selection
    }
    public func cancel() { selection = nil }
}

public enum IMUploadState: Equatable { case idle, selecting, selected(IMMediaSelection), uploading, uploaded(URL), outcomeUnknown, failed }
@MainActor public final class IMImageUploadCoordinator {
    public let scope: IMScope
    private let writer: any IMExpandedWriting
    private let picker: any IMImageSelecting
    private let journal: any ImageUploadJournal
    private let target: ImageUploadTarget?
    private let originalJournal: OrdinaryIMImageJournal?
    private let expanded: IMExpandedCoordinator?
    private let reader: (any MessagingReading)?
    private let stillCurrent: () -> Bool
    private var pending: OrdinaryIMImageJournal.Pending?
    private var state: IMUploadState = .idle
    private var readback: OrdinaryIMImageReadback = .unchecked
    private var generation: UInt64 = 0
    private var acknowledgedAttempt: UUID?
    private var reading = false
    private var consumptionClosed = false
    private var visibleMessage: MessagingMessage?
    public var onChange: (() -> Void)?
    public var isCurrent: Bool { !consumptionClosed && stillCurrent() && writer.identity == scope.identity && (expanded?.isCurrent ?? true) && expanded?.visibleState != .closed }
    public var isConfigured: Bool {
        writer.canUploadOrdinaryImage && picker.isConfigured
            && (originalJournal == nil || (writer.canRecoverImageUpload && writer.canSendOrdinaryImage && writer.canRecoverOrdinaryImage))
    }
    public var visibleState: IMUploadState { isCurrent ? state : .idle }
    public var originalReadback: OrdinaryIMImageReadback {
        guard isCurrent else { return .closed }
        if case .visible = readback, reader?.isConfigured != true || reader?.identity != scope.identity { return .unknown }
        return readback
    }
    public var originalRequestID: UUID? { isCurrent ? pending?.requestID : nil }
    public var originalClientMessageID: String? {
        guard isCurrent else { return nil }
        return pending?.clientMessageID ?? (try? expanded?.retainedOrdinaryImage())?.clientMessageID
    }
    public var canRecover: Bool { isCurrent && originalClientMessageID != nil && !reading && writer.canRecoverOrdinaryImage }
    public var canFinish: Bool { isCurrent && visibleMessage != nil && !reading && reader?.isConfigured == true && reader?.identity == scope.identity }
    public init(scope: IMScope, writer: any IMExpandedWriting, picker: any IMImageSelecting,
                journal: (any ImageUploadJournal)? = nil, target: ImageUploadTarget? = nil,
                originalJournal: OrdinaryIMImageJournal? = nil, expanded: IMExpandedCoordinator? = nil,
                reader: (any MessagingReading)? = nil, stillCurrent: @escaping () -> Bool = { true }) {
        self.scope = scope; self.writer = writer; self.picker = picker
        self.journal = journal ?? UnavailableImageUploadJournal(); self.target = target
        self.originalJournal = originalJournal; self.expanded = expanded; self.reader = reader; self.stillCurrent = stillCurrent
        do {
            guard let target, target.accountID == scope.identity.accountID, target.kind == "im",
                  target.entityID == scope.conversationID else { state = .outcomeUnknown; return }
            if let originalJournal {
                guard expanded?.scope == scope else { throw APIError.invalidConfiguration }
                pending = try originalJournal.restore(current: scope)
            }
            let priorUpload = try self.journal.entry(for: target)
            if pending != nil || priorUpload.map({ !$0.phase.permitsNewSelection }) == true { state = .outcomeUnknown }
        } catch { state = .outcomeUnknown }
    }
    public func selectAfterConsent() async {
        guard isCurrent, isConfigured, pending == nil, !reading else { return }
        do {
            guard let target else { throw ImageUploadJournalFailure.unavailable }
            if let value = try journal.entry(for: target), !value.phase.permitsNewSelection { throw ImageUploadJournalFailure.locked }
        } catch { state = .outcomeUnknown; onChange?(); return }
        switch state { case .selecting, .uploading, .outcomeUnknown: return; default: break }
        generation &+= 1; let run = generation; state = .selecting; onChange?()
        do {
            let selected = try await picker.select(scope: scope, consent: .init(scope: scope, selectionID: UUID(), purpose: .selection))
            guard current(run) else { return }
            guard let selected else { state = .idle; onChange?(); return }
            guard selected.scope == scope else { throw IMCapabilityGap.staleScope }
            try selected.validateImage(); state = .selected(selected)
        } catch { guard current(run) else { return }; state = .failed }
        onChange?()
    }
    public func uploadAfterConsent() async {
        guard isCurrent, isConfigured, !reading, case .selected(let selection) = state, let target else { return }
        let operation: UUID?
        if let originalJournal { guard let id = originalJournal.beginOperation() else { return }; operation = id }
        else { operation = nil }
        defer { if let operation { originalJournal?.endOperation(operation) } }
        do {
            try Task.checkCancellation()
            if let originalJournal { pending = try originalJournal.reserve(selection) }
            try journal.begin(target: target, attemptID: selection.id)
        } catch { state = .outcomeUnknown; onChange?(); return }
        let run = generation; state = .uploading; readback = .unchecked; visibleMessage = nil; onChange?()
        do {
            let url = try await writer.upload(selection, consent: .init(scope: scope, selectionID: selection.id, purpose: .upload), expectedIdentity: scope.identity)
            guard current(run) else { return }
            try journal.record(target: target, attemptID: selection.id, phase: .acknowledged)
            acknowledgedAttempt = selection.id; state = .uploaded(url)
        } catch { if current(run) { fail(error) } }
        onChange?()
    }
    /// Both ordinary hosts use this SAME reserved client UUID; the original sender still owns review/dispatch.
    public func outgoingIntent(_ url: URL) throws -> IMOutgoingIntent {
        guard isCurrent, case .uploaded(let original) = state, original == url else { throw APIError.notConfigured }
        if let pending { return try IMOutgoingIntent(scope: scope, payload: .image(url), clientMessageID: pending.clientMessageID) }
        return try IMOutgoingIntent(scope: scope, payload: .image(url))
    }
    @discardableResult public func applyLocally(_ url: URL, consume: (URL) -> Bool) -> Bool {
        guard isCurrent, !reading, case .uploaded(let current) = state, current == url,
              let target, let attempt = acknowledgedAttempt, consume(url) else { return false }
        do {
            if originalJournal == nil {
                // Preserve the existing legacy journal transition and its failure result.
                try journal.record(target: target, attemptID: attempt, phase: .locallyApplied)
            } else {
                guard let entry = try journal.entry(for: target), entry.attemptID == attempt else { throw ImageUploadJournalFailure.locked }
                if entry.phase == .acknowledged {
                    try journal.record(target: target, attemptID: attempt, phase: .locallyApplied)
                } else if entry.phase != .locallyApplied { throw ImageUploadJournalFailure.locked }
            }
            acknowledgedAttempt = nil; state = .idle; onChange?(); return true
        } catch { state = .outcomeUnknown; onChange?(); return false }
    }
    /// No upload/send fallback. Reload uses the exact original upload UUID and client UUID.
    /// Original send restoration is independent of picker/upload write permission.
    public func recover() async {
        guard canRecover, let originalJournal, let expanded,
              let operation = originalJournal.beginOperation() else { return }
        let run = generation; reading = true; readback = .reading; visibleMessage = nil; onChange?()
        defer {
            originalJournal.endOperation(operation); reading = false
            if current(run), readback == .reading { readback = .unknown }
            onChange?()
        }
        do {
            guard try originalJournal.restore(current: scope) == pending else { throw ImageUploadJournalFailure.corrupt }
            let intent: IMOutgoingIntent
            if let retained = try expanded.retainedOrdinaryImage() {
                guard pending == nil || retained.clientMessageID == pending?.clientMessageID else { throw ImageUploadJournalFailure.locked }
                intent = retained
            } else {
                guard let pending, writer.canRecoverImageUpload else { throw APIError.notConfigured }
                let uploaded = try await writer.recoverImageUpload(requestID: pending.requestID, sourceSHA256: pending.sourceSHA256, expectedIdentity: scope.identity)
                guard current(run) else { return }
                guard case .uploaded(let url) = uploaded else { state = .outcomeUnknown; readback = .unknown; return }
                if let target, let entry = try journal.entry(for: target), entry.attemptID == pending.requestID, entry.phase == .pending {
                    try journal.record(target: target, attemptID: pending.requestID, phase: .acknowledged)
                }
                acknowledgedAttempt = pending.requestID; state = .uploaded(url)
                intent = try IMOutgoingIntent(scope: scope, payload: .image(url), clientMessageID: pending.clientMessageID)
            }
            let result = try await writer.recoverOrdinaryImage(intent, expectedIdentity: scope.identity)
            guard current(run) else { return }
            guard case .found(let receipt) = result else {
                // NOT_FOUND is a read result, never automatic resend or UUID rotation.
                readback = .notSent; return
            }
            if expanded.pendingOrdinaryImage == intent {
                _ = await expanded.recoverOrdinaryImage(stillAuthorized: { self.current(run) })
                guard current(run), case .acknowledged(.sent(let found)) = expanded.visibleState, found.id == receipt.id else { throw APIError.malformedResponse }
            }
            state = .outcomeUnknown; readback = .sent(messageID: receipt.id)
            guard let reader, reader.isConfigured, reader.identity == scope.identity else { return }
            // This is the existing independent history reader, never the send ACK or upload result.
            var cursor = 0, visited = Set<Int>()
            while visited.insert(cursor).inserted {
                let page = try await reader.messagingMessages(conversationID: scope.conversationID, cursor: cursor)
                guard current(run), reader.identity == scope.identity, reader.isConfigured else { return }
                guard page.messages.count <= 50, Set(page.messages.map(\.id)).count == page.messages.count,
                      page.messages.allSatisfy({ $0.conversationID == scope.conversationID }) else { throw APIError.malformedResponse }
                if let row = page.messages.first(where: { $0.id == receipt.id }) {
                    guard row.isPayloadVisible, row.type == 2, row.senderID == scope.identity.accountID,
                          row.content == receipt.content, row.extraJSON == nil else { readback = .notVisible(messageID: receipt.id); return }
                    visibleMessage = row; readback = .visible(messageID: row.id); return
                }
                guard page.hasMore, let next = page.nextCursor, next > 0 else { readback = .notVisible(messageID: receipt.id); return }
                cursor = next
            }
            throw APIError.malformedResponse
        } catch { if current(run) { fail(error) } }
    }
    /// Explicit completion after the independent visible row; original send ledger settles first.
    public func finishVisible() {
        guard canFinish, let originalJournal, let expanded, let visibleMessage else { return }
        do {
            if let intent = try expanded.retainedOrdinaryImage() {
                guard pending == nil || intent.clientMessageID == pending?.clientMessageID else { throw ImageUploadJournalFailure.locked }
                try expanded.finishOrdinaryImage(intent, visible: visibleMessage)
            } else {
                // Crash after original send settlement but before sidecar removal: this run
                // has independently reread BOTH original UUID receipt and visible history.
                switch expanded.visibleState { case .idle, .acknowledged: break; default: throw ImageUploadJournalFailure.locked }
            }
            if let pending { try originalJournal.settle(pending, current: scope) }
            self.pending = nil; self.visibleMessage = nil; state = .idle; readback = .unchecked; onChange?()
        } catch { fail(error); onChange?() }
    }
    private func current(_ run: UInt64) -> Bool { generation == run && isCurrent && !Task.isCancelled }
    private func fail(_ error: Error) {
        state = .outcomeUnknown; readback = .unknown; visibleMessage = nil
        if error as? APIError == .unauthorized || (error as? MessagingReadFailure).map(OrdinaryIMSendReceipt.revokesRead) == true {
            consumptionClosed = true; generation &+= 1; picker.cancel(); readback = .closed
        }
    }
    public func retireConsumption() {
        consumptionClosed = true; generation &+= 1; picker.cancel()
        visibleMessage = nil; state = .outcomeUnknown; readback = .closed; onChange?()
    }
    public func clear() {
        generation &+= 1; picker.cancel(); visibleMessage = nil; readback = .unchecked
        if pending != nil { state = .outcomeUnknown }
        else { switch state { case .uploading, .outcomeUnknown: state = .outcomeUnknown; default: state = .idle } }
        onChange?()
    }
}
