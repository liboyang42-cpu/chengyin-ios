import Foundation

/// Deployment-reviewed encoder/validation limits; no provider limits are inferred from Flutter.
public struct MerchantNPCVoiceConfiguration: Equatable {
    public let sampleRate: Double
    public let channels: Int
    public let bitRate: Int
    public let minDuration: TimeInterval
    public let maxDuration: TimeInterval
    public let maxBytes: Int
    public let approvedHosts: Set<String>
    public init(sampleRate: Double, channels: Int, bitRate: Int, minDuration: TimeInterval, maxDuration: TimeInterval, maxBytes: Int, approvedHosts: Set<String>) throws {
        guard sampleRate.isFinite, sampleRate > 0, channels > 0, bitRate > 0, minDuration.isFinite, minDuration > 0, maxDuration.isFinite, maxDuration >= minDuration, maxBytes > 0, !approvedHosts.isEmpty else { throw MerchantNPCFailure.invalid }
        self.sampleRate = sampleRate; self.channels = channels; self.bitRate = bitRate; self.minDuration = minDuration; self.maxDuration = maxDuration; self.maxBytes = maxBytes; self.approvedHosts = approvedHosts
    }
    public func validate(_ clip: MerchantNPCVoiceClip) throws {
        guard clip.duration.isFinite, (minDuration...maxDuration).contains(clip.duration), !clip.bytes.isEmpty, clip.bytes.count <= maxBytes,
              clip.bytes.count >= 12, clip.bytes.subdata(in: 4..<8) == Data("ftyp".utf8) else { throw MerchantNPCFailure.invalid }
    }
}
public struct MerchantNPCVoiceClip {
    public let id: UUID
    public let bytes: Data
    public let duration: TimeInterval
    public init(id: UUID = UUID(), bytes: Data, duration: TimeInterval) { self.id = id; self.bytes = bytes; self.duration = duration }
}
public struct MerchantNPCVoiceLocalGrants {
    public var capture = false
    public var playback = false
    public init() {}
}
@MainActor public protocol MerchantNPCVoiceDevice: AnyObject {
    func start(configuration: MerchantNPCVoiceConfiguration, interrupted: @escaping () -> Void) async throws
    func finish() throws -> MerchantNPCVoiceClip?
    func play(_ clip: MerchantNPCVoiceClip) throws
    func cancel()
}
@MainActor public protocol MerchantNPCVoiceUploading {
    func upload(_ clip: MerchantNPCVoiceClip, index: Int, scope: MerchantNPCScope) async throws -> MerchantNPCMediaReference
    var destination: String { get }
}
public struct MerchantNPCVoiceUploadReview: Identifiable {
    public let id: UUID
    public let clipID: UUID
    public let index: Int
    public let byteCount: Int
    public let duration: TimeInterval
    public let destination: String
}
/// Memory-only clips/URLs. Recovery stores metadata only in the existing resource journal.
@MainActor public final class MerchantNPCVoiceSamplesCoordinator {
    public let resources: MerchantNPCResourcesCoordinator
    public let configuration: MerchantNPCVoiceConfiguration?
    private let device: any MerchantNPCVoiceDevice
    private let uploader: any MerchantNPCVoiceUploading
    private let journal: any OperationPendingJournal
    private let grants: () -> MerchantNPCGrants
    private let localGrants: () -> MerchantNPCVoiceLocalGrants
    public var onChange: (() -> Void)?
    public private(set) var clips: [Int: MerchantNPCVoiceClip] = [:]
    public private(set) var uploaded: [Int: MerchantNPCMediaReference] = [:]
    public private(set) var recording: Int?
    public private(set) var busy = false
    public private(set) var review: MerchantNPCVoiceUploadReview?
    public private(set) var failure: MerchantNPCFailure?
    public private(set) var ownsVoice = false
    public private(set) var consent = false
    private var script: MerchantNPCVoiceScript?
    private var generation = 0
    private var active = true
    private var ownerKey: String { "merchant-npc:\(resources.scope.namespace.utf8.count):\(resources.scope.namespace):account:\(resources.scope.accountID)" }
    private var targetKey: String { "resources:merchant-row:\(resources.scope.merchantRowID.rawValue)" }
    public var recoveryMetadata: OperationPendingRecord? { try? journal.pending(ownerKey: ownerKey, targetKey: targetKey) }
    public var unresolved: Bool { (try? journal.pending(ownerKey: ownerKey, targetKey: targetKey)) != nil || journalUnreadable }
    private var journalUnreadable: Bool { do { _ = try journal.pending(ownerKey: ownerKey, targetKey: targetKey); return false } catch { return true } }
    public var isCurrent: Bool { active && resources.isCurrent }
    public var ready: Bool { isCurrent && resources.canEnroll && configuration != nil && ownsVoice && consent && resources.script?.isUsable == true && script == resources.script && !unresolved && !busy }
    public init(resources: MerchantNPCResourcesCoordinator, configuration: MerchantNPCVoiceConfiguration? = nil, device: any MerchantNPCVoiceDevice, uploader: any MerchantNPCVoiceUploading, journal: any OperationPendingJournal, grants: @escaping () -> MerchantNPCGrants = { .init() }, localGrants: @escaping () -> MerchantNPCVoiceLocalGrants = { .init() }) {
        self.resources = resources; self.configuration = configuration; self.device = device; self.uploader = uploader; self.journal = journal; self.grants = grants; self.localGrants = localGrants
    }
    public func attest(ownsVoice: Bool, consent: Bool) {
        guard !busy else { return }
        clearEphemeral(); self.ownsVoice = ownsVoice; self.consent = consent; script = resources.script; onChange?()
    }
    public func record(_ index: Int) async {
        guard ready, localGrants().capture, (0..<5).contains(index), recording == nil, uploaded.isEmpty,
              index == 0 || clips[0] != nil, let configuration else { return }
        review = nil; resources.discardReview(); recording = index; busy = true; let stamp = generation; onChange?()
        do {
            try await device.start(configuration: configuration) { [weak self] in self?.interrupted() }
            guard isCurrent, generation == stamp, localGrants().capture, script == resources.script, !Task.isCancelled else { invalidate(); return }
            busy = false
        } catch { recording = nil; busy = false; failure = error as? MerchantNPCFailure ?? .invalid }
        onChange?()
    }
    public func finish() {
        guard isCurrent, !busy, let index = recording else { return }
        defer { recording = nil; onChange?() }
        guard localGrants().capture, script == resources.script else { invalidate(); return }
        do { if let clip = try device.finish(), let configuration { try configuration.validate(clip); clips[index] = clip; failure = nil } }
        catch { failure = error as? MerchantNPCFailure ?? .invalid }
        // nil/interruption preserves the previous successful sample.
    }
    private func interrupted() { recording = nil; busy = false; review = nil; onChange?() }
    public func play(_ index: Int) {
        guard ready, recording == nil, localGrants().playback, let clip = clips[index] else { return }
        do { try device.play(clip) } catch { failure = .invalid }; onChange?()
    }
    public func stopPlayback() { guard recording == nil, !busy else { return }; device.cancel(); onChange?() }
    public func prepareUpload() {
        guard ready, recording == nil, grants().resourceAllowed, grants().voiceCloning, clips.count == 5,
              let clip = clips[uploaded.count], uploaded.count < 5 else { return }
        review = .init(id: UUID(), clipID: clip.id, index: uploaded.count, byteCount: clip.bytes.count, duration: clip.duration, destination: uploader.destination); onChange?()
    }
    public func discardReview() { review = nil; resources.discardReview(); onChange?() }
    public func confirmUpload(_ id: UUID) async {
        guard ready, recording == nil, grants().resourceAllowed, grants().voiceCloning, let review, review.id == id,
              let clip = clips[review.index], clip.id == review.clipID, review.index == uploaded.count else { return }
        self.review = nil; busy = true; let stamp = generation; onChange?()
        await resources.refresh()
        guard isCurrent, generation == stamp, !Task.isCancelled, script == resources.script, resources.canEnroll,
              grants().resourceAllowed, grants().voiceCloning, ownsVoice, consent else { busy = false; onChange?(); return }
        let record = OperationPendingRecord(ownerKey: ownerKey, targetKey: targetKey, acknowledgedSteps: uploaded.count)
        do {
            guard !unresolved else { throw MerchantNPCFailure.unknownOutcome }
            try configuration?.validate(clip)
            try journal.write(record) // Persist before transport; no automatic replay after uncertainty.
            let reference = try await uploader.upload(clip, index: review.index, scope: resources.scope)
            guard isCurrent, generation == stamp, !Task.isCancelled, script == resources.script, grants().resourceAllowed,
                  reference.scope == resources.scope, reference.selectionID == clip.id, reference.kind == .voiceSample(index: review.index),
                  let host = reference.url.host, configuration?.approvedHosts.contains(host) == true else { throw MerchantNPCFailure.unknownOutcome }
            try journal.clear(record); uploaded[review.index] = reference; failure = nil
        } catch { failure = .unknownOutcome } // Deliberately conservative, including malformed replies and cancelled awaits.
        busy = false; onChange?()
    }
    public func prepareEnrollment() {
        guard ready, uploaded.count == 5 else { return }
        do { try resources.prepare(.enroll(samples: (0..<5).compactMap { uploaded[$0] }, requestID: UUID()), ownsVoice: ownsVoice, explicitConsent: consent) }
        catch { failure = error as? MerchantNPCFailure ?? .invalid }; onChange?()
    }
    private func clearEphemeral() { generation += 1; device.cancel(); clips.removeAll(); uploaded.removeAll(); review = nil; recording = nil; busy = false; resources.discardReview() }
    public func invalidate() { active = false; clearEphemeral(); ownsVoice = false; consent = false; script = nil; onChange?() }
}
