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
    private var state: IMUploadState = .idle
    private var generation: UInt64 = 0
    private var acknowledgedAttempt: UUID?
    public var onChange: (() -> Void)?
    public var isCurrent: Bool { writer.identity == scope.identity }
    public var isConfigured: Bool { writer.isConfigured && picker.isConfigured }
    public var visibleState: IMUploadState { isCurrent ? state : .idle }
    private let journal: any ImageUploadJournal
    private let target: ImageUploadTarget?
    public init(scope: IMScope, writer: any IMExpandedWriting, picker: any IMImageSelecting,
                journal: (any ImageUploadJournal)? = nil, target: ImageUploadTarget? = nil) {
        self.scope = scope; self.writer = writer; self.picker = picker; self.journal = journal ?? UnavailableImageUploadJournal(); self.target = target
        do {
            guard let target, target.accountID == scope.identity.accountID, target.kind == "im",
                  target.entityID == scope.conversationID else { state = .outcomeUnknown; return }
            if let value = try self.journal.entry(for: target), !value.phase.permitsNewSelection { state = .outcomeUnknown }
        } catch { state = .outcomeUnknown }
    }
    public func selectAfterConsent() async {
        guard isCurrent, isConfigured else { return }
        do {
            guard let target else { state = .outcomeUnknown; onChange?(); return }
            if let value = try self.journal.entry(for: target), !value.phase.permitsNewSelection { state = .outcomeUnknown; onChange?(); return }
        } catch { state = .outcomeUnknown; onChange?(); return }
        switch state { case .selecting, .uploading, .outcomeUnknown: return; default: break }
        generation &+= 1; let run = generation; state = .selecting; onChange?()
        do {
            let consent = IMMediaConsent(scope: scope, selectionID: UUID(), purpose: .selection)
            let selected = try await picker.select(scope: scope, consent: consent)
            guard run == generation, isCurrent, !Task.isCancelled else { return }
            guard let selected else { state = .idle; onChange?(); return }
            guard selected.scope == scope else { throw IMCapabilityGap.staleScope }
            try selected.validateImage(); state = .selected(selected)
        } catch { guard run == generation, isCurrent else { return }; state = .failed }
        onChange?()
    }
    public func uploadAfterConsent() async {
        guard isCurrent, case .selected(let selection) = state else { return }
        guard let target else { state = .outcomeUnknown; onChange?(); return }
        do { try Task.checkCancellation(); try journal.begin(target: target, attemptID: selection.id) }
        catch { state = .outcomeUnknown; onChange?(); return }
        let run = generation; state = .uploading; onChange?()
        do {
            let url = try await writer.upload(selection, consent: .init(scope: scope, selectionID: selection.id, purpose: .upload), expectedIdentity: scope.identity)
            guard run == generation, isCurrent, !Task.isCancelled else { return }
            // Upload acknowledgement is not a sent IM message; never persist its URL.
            try journal.record(target: target, attemptID: selection.id, phase: .acknowledged)
            acknowledgedAttempt = selection.id
            state = .uploaded(url)
        } catch { guard run == generation else { return }; state = .outcomeUnknown }
        onChange?()
    }
    /// Local IM review accepted the scoped image. This is never a message-send receipt.
    @discardableResult public func applyLocally(_ url: URL, consume: (URL) -> Bool) -> Bool {
        guard isCurrent, case .uploaded(let current) = state, current == url,
              let target, let attempt = acknowledgedAttempt, consume(url) else { return false }
        do {
            try journal.record(target: target, attemptID: attempt, phase: .locallyApplied)
            acknowledgedAttempt = nil; state = .idle; onChange?(); return true
        } catch { state = .outcomeUnknown; onChange?(); return false }
    }
    /// Dismissal forgets bytes and invalidates completions; upload is never automatically retried.
    public func clear() {
        generation &+= 1; picker.cancel()
        switch state { case .uploading, .outcomeUnknown: state = .outcomeUnknown; default: state = .idle }
        onChange?()
    }
}
