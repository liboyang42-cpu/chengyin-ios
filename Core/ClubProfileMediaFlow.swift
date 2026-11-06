import Foundation
import Combine

public extension ClubOperationsCommand {
    var profileMediaReceipts: [ClubProfileMediaReceipt] {
        switch self { case .create(let draft), .update(let draft, _): return [draft.logoUpload, draft.coverUpload].compactMap { $0 }; default: return [] }
    }
}
public extension ClubOperationsDraft {
    @MainActor mutating func stageMedia(_ receipt: ClubProfileMediaReceipt) throws {
        guard receipt.isCurrent() else { throw ClubOperationsBlock.changed }
        switch receipt.field { case .logo: logo = receipt.reference; logoUpload = receipt; case .cover: cover = receipt.reference; coverUpload = receipt }
    }
    mutating func discardMedia(_ field: ClubProfileMediaField, original: ClubOperationsProfile?) {
        switch field { case .logo: logo = original?.club.logo ?? ""; logoUpload = nil; case .cover: cover = original?.club.cover ?? ""; coverUpload = nil }
    }
    func validateMedia(original: ClubOperationsProfile?) throws {
        for (field, value, old, receipt) in [(ClubProfileMediaField.logo, logo, original?.club.logo ?? "", logoUpload), (.cover, cover, original?.club.cover ?? "", coverUpload)] {
            if let receipt {
                guard receipt.field == field, receipt.reference == value, receipt.scope.source == original,
                      receipt.scope.target == (original.map { .club($0.club.id) } ?? .create) else { throw ClubOperationsBlock.mediaUnavailable }
            } else if value != old { throw ClubOperationsBlock.mediaUnavailable }
        }
    }
}

/// One owner for the full create/edit presentation, not the temporarily disappearing form.
/// Closing a crop keeps the saved profile intact. Retiring this owner revokes staged proofs.
@MainActor public final class ClubProfileMediaFlow: ObservableObject {
    public enum State: Equatable { case idle, uploading, uploaded, notSent, rejected, revoked, unknown }
    @Published public private(set) var state: State = .idle
    @Published public private(set) var pendingAsset: Int64?
    @Published public private(set) var reviewState: String?
    @Published public private(set) var preview: RetainedSelectedImage?
    @Published public private(set) var field: ClubProfileMediaField?
    public private(set) var scope: ClubProfileMediaScope?
    public private(set) var service: ClubProfileMediaService?
    public let ownerID = UUID()
    private var generation = UUID()
    private var uploadTask: Task<Void, Never>?
    private var retired = false
    public init() {}
    public var current: Bool { !retired && scope.map { service?.isCurrent($0) == true } == true }
    public func open(field: ClubProfileMediaField, snapshot: ClubOperationsSnapshot, identity: ClubReadIdentity, service: ClubProfileMediaService) -> Bool {
        guard state != .uploading, let next = service.scope(snapshot: snapshot, identity: identity, ownerID: ownerID) else { return false }
        if scope != nil && scope != next { retire() }
        retired = false; self.scope = next; self.service = service; self.field = field; preview = nil; state = .idle
        do { pendingAsset = try service.pendingAsset(scope: next, field: field); reviewState = pendingAsset == nil ? nil : "待查询" } catch { state = .unknown }
        return true
    }
    public func accepts(_ image: RetainedSelectedImage) -> Bool { current && field?.accepts(image) == true }
    public func prepare(_ image: RetainedSelectedImage) { guard accepts(image), state != .uploading else { return }; preview = image; state = .idle }
    public func upload(consume: @escaping (ClubProfileMediaReceipt) -> Void) {
        guard current, state != .uploading, state != .unknown, let image = preview, let field, let scope, let service else { return }
        let captured = generation; state = .uploading
        uploadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let receipt = try await service.upload(image, field: field, scope: scope, ownerCurrent: { [weak self] in self?.generation == captured && self?.current == true })
                guard generation == captured, current, !Task.isCancelled else { return }
                consume(receipt); state = .uploaded; preview = nil
            } catch {
                guard generation == captured else { return }
                switch error { case ClubProfileMediaFailure.notSent: state = .notSent
                case ClubProfileMediaFailure.rejected: state = .rejected
                case ClubProfileMediaFailure.revoked: state = .revoked
                case ClubProfileMediaFailure.reviewPending(let id, let review): pendingAsset = id; reviewState = review; preview = nil; state = .idle
                default: state = .unknown }
            }
            uploadTask = nil
        }
    }
    public func checkReview(retry: Bool, consume: @escaping (ClubProfileMediaReceipt) -> Void) {
        guard current, state != .uploading, pendingAsset != nil, let scope, let field, let service else { return }
        let captured = generation; state = .uploading
        uploadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let receipt = try await service.review(field: field, scope: scope, retry: retry,
                    ownerCurrent: { [weak self] in self?.generation == captured && self?.current == true })
                guard generation == captured, current, !Task.isCancelled else { return }
                consume(receipt); pendingAsset = nil; reviewState = nil; state = .uploaded
            } catch {
                guard generation == captured else { return }
                if case ClubProfileMediaFailure.reviewPending(let id, let review) = error { pendingAsset = id; reviewState = review; state = .idle }
                else { state = .unknown }
            }
            uploadTask = nil
        }
    }
    public func closeSelection() { preview = nil; field = nil; if state != .uploading && state != .unknown { state = .idle } }
    public func retire() {
        generation = UUID(); retired = true; uploadTask?.cancel(); uploadTask = nil; preview = nil; field = nil
        state = state == .uploading ? .unknown : .idle; scope = nil; service = nil
    }
}
