import Foundation

/// Exact uploaded picture + idempotency key are the source's only create reconciliation inputs.
/// Secure storage is required, scoped by namespace/deployment/account (not transient login epoch).
/// No card, credential, raw photo or location is persisted here.
public struct RoamStampPending: Codable, Equatable {
    public let pictureURL: URL
    public let idempotencyKey: String
    public init(pictureURL: URL, idempotencyKey: String) throws {
        guard pictureURL.scheme == "https", pictureURL.host != nil, pictureURL.user == nil, pictureURL.password == nil,
              pictureURL.fragment == nil, !pictureURL.path.isEmpty, pictureURL.path != "/",
              (1...128).contains(idempotencyKey.utf8.count),
              idempotencyKey.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw RetainedImageFailure.invalid }
        self.pictureURL = pictureURL; self.idempotencyKey = idempotencyKey
    }
}
@MainActor public protocol RoamStampPendingStorage {
    func load(scope: RetainedImageScope) throws -> RoamStampPending?
    func save(_ pending: RoamStampPending, scope: RetainedImageScope) throws
    func clear(_ pending: RoamStampPending, scope: RetainedImageScope) throws
}
@MainActor public struct StoredRoamStampPending: RoamStampPendingStorage {
    private let read: (String) throws -> Data?
    private let write: (Data, String) throws -> Void
    public init(read: @escaping (String) throws -> Data?, write: @escaping (Data, String) throws -> Void) { self.read = read; self.write = write }
    private func key(_ scope: RetainedImageScope) throws -> String {
        guard scope.destination == .stamp, let namespace = scope.namespace, !namespace.isEmpty else { throw RetainedImageFailure.invalid }
        return "stamp-create.v1." + Data([namespace, scope.realm, String(scope.accountID)].map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
    public func load(scope: RetainedImageScope) throws -> RoamStampPending? {
        guard let data = try read(key(scope)), data != Data("null".utf8) else { return nil }
        guard data.count <= 16384, let record = try? JSONDecoder().decode(RoamStampPending.self, from: data) else { throw ImageUploadJournalFailure.corrupt }
        return try RoamStampPending(pictureURL: record.pictureURL, idempotencyKey: record.idempotencyKey)
    }
    public func save(_ pending: RoamStampPending, scope: RetainedImageScope) throws {
        if let existing = try load(scope: scope), existing != pending { throw ImageUploadJournalFailure.locked }
        let data = try JSONEncoder().encode(pending), name = try key(scope)
        try write(data, name); guard try read(name) == data else { throw ImageUploadJournalFailure.unavailable }
    }
    public func clear(_ pending: RoamStampPending, scope: RetainedImageScope) throws {
        guard try load(scope: scope) == pending else { throw ImageUploadJournalFailure.locked }
        let name = try key(scope), data = Data("null".utf8)
        try write(data, name); guard try read(name) == data else { throw ImageUploadJournalFailure.unavailable }
    }
}
@MainActor public final class RoamStampCaptureCoordinator {
    public enum Phase: Equatable { case ready, review, uploading, awaitingCreate, creating, unknown, created(Int), unavailable, failed }
    public private(set) var phase: Phase = .ready
    public private(set) var selection: RetainedSelectedImage?
    public private(set) var pending: RoamStampPending?
    public let scope: RetainedImageScope
    public let uploads: RetainedImageUploadCoordinator
    private let executor: any RoamMediaMutationExecuting
    private let storage: any RoamStampPendingStorage
    private var generation = 0
    public var changed: (() -> Void)?
    public init(scope: RetainedImageScope, uploads: RetainedImageUploadCoordinator,
                executor: any RoamMediaMutationExecuting, storage: any RoamStampPendingStorage) {
        self.scope = scope; self.uploads = uploads; self.executor = executor; self.storage = storage
        do { pending = try storage.load(scope: scope); if pending != nil { phase = .unknown } }
        catch { phase = .unavailable }
        if uploads.locked && pending == nil { phase = .unknown }
    }
    public var canCapture: Bool { pending == nil && !uploads.locked && [.ready, .review, .failed].contains(phase) }
    public var canUpload: Bool { phase == .review && uploads.uploader.isConfigured && uploads.uploader.scope == scope }
    public var canCreate: Bool { pending != nil && phase != .creating && executor.enabled && executor.scope == scope }
    public func captured(_ image: RetainedSelectedImage) {
        guard canCapture else { return }; selection = image; phase = .review; changed?()
    }
    public func retake() { guard canCapture else { return }; selection = nil; phase = .ready; changed?() }
    public func upload() async {
        guard canUpload, let selection else { return }
        uploads.prepare(selection, scope: scope)
        guard case .reviewing(let review) = uploads.state else { phase = .unknown; changed?(); return }
        let ticket = generation; phase = .uploading; changed?()
        await uploads.confirm(review)
        guard ticket == generation, !Task.isCancelled else { return }
        guard case .uploaded(let proof) = uploads.state else { phase = uploads.locked ? .unknown : .failed; changed?(); return }
        do {
            let record = try RoamStampPending(pictureURL: proof.url, idempotencyKey: "stamp-" + proof.id.uuidString)
            // Persist the exact create command before allowing a single create dispatch.
            guard uploads.applyLocally(proof, consume: { proof in
                guard proof.scope == self.scope else { return false }
                do { try self.storage.save(record, scope: self.scope); return true } catch { return false }
            }) else { phase = .unknown; changed?(); return }
            pending = record; phase = .awaitingCreate; changed?()
        } catch { phase = .unknown; changed?() }
    }
    /// An explicit retry reuses the original URL/key, never uploads again or changes the key.
    public func create() async {
        guard canCreate, let pending else { return }
        let ticket = generation; phase = .creating; changed?()
        do {
            try storage.save(pending, scope: scope)
            let data = try await executor.execute(.createStamp(pictureURL: pending.pictureURL.absoluteString, caption: "", idempotencyKey: pending.idempotencyKey))
            guard ticket == generation, executor.scope == scope, !Task.isCancelled else { return }
            let receipt = try RoamMutationReceiptDecoder.value(RoamStampCreatedReceipt.self, from: data)
            try storage.clear(pending, scope: scope)
            self.pending = nil; selection = nil; phase = .created(receipt.id)
        } catch let error as RetainedImageFailure {
            if ticket == generation {
                if case .rejected = error {
                    do { try storage.clear(pending, scope: scope); self.pending = nil; phase = .failed }
                    catch { phase = .unknown }
                } else { phase = .unknown }
            }
        } catch { if ticket == generation { phase = .unknown } }
        changed?()
    }
    public func cancel() {
        generation += 1; uploads.clear(); selection = nil
        if pending != nil || uploads.locked || phase == .creating { phase = .unknown }
        else if phase != .unavailable { phase = .ready }
        changed?()
    }
}
