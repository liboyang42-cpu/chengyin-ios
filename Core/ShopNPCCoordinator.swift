import Foundation
import Observation

/// A review token binds exact content and identity; review never dispatches.
public struct ShopNPCReview: Equatable {
    public enum Content: Equatable { case text(String); case voice(ShopNPCVoiceClip) }
    public let id: UUID
    public let scope: ShopNPCScope
    public let content: Content
    public let replacing: UUID?
}
/// One explicit send action, captured synchronously before the UI queues its Task.
/// Its nonce never becomes a server request ID and cannot be manufactured by a caller.
public struct ShopNPCTransmissionIntent: Equatable {
    fileprivate let nonce: UUID
    fileprivate let generation: UInt64
    fileprivate let reviewID: UUID
}
@MainActor @Observable public final class ShopNPCCoordinator {
    public private(set) var messages: [ShopNPCMessage] = []
    public private(set) var pending: ShopNPCReview?
    public private(set) var failure: ShopNPCFailure?
    public private(set) var busy = false
    public private(set) var active = true
    public private(set) var isSuspended = false
    public private(set) var scope: ShopNPCScope
    public private(set) var grants: ShopNPCGrants
    private let client: ShopNPCHTTPClient
    private var epoch: UInt64 = 0
    private var transmission: Task<ShopNPCReply, Error>?
    private var transmissionIntent: ShopNPCTransmissionIntent?
    private var lastSend: Date?
    private let now: () -> Date
    public init(scope: ShopNPCScope, grants: ShopNPCGrants = .init(), client: ShopNPCHTTPClient, now: @escaping () -> Date = Date.init) {
        self.scope = scope; self.grants = grants; self.client = client; self.now = now
    }
    public func rebind(scope: ShopNPCScope, grants: ShopNPCGrants) {
        guard self.scope != scope || self.grants != grants else { return }
        invalidate(); self.scope = scope; self.grants = grants; active = true
    }
    public func invalidate() {
        epoch &+= 1; transmissionIntent = nil; transmission?.cancel(); transmission = nil
        active = false; isSuspended = false; busy = false; pending = nil; messages = []; failure = nil; lastSend = nil
    }
    /// Cancels local waiting only. The server may already have accepted the original request.
    /// Keep its exact review, content and request ID until explicit retry or discard.
    public func stopWaiting() {
        guard active, busy else { return }
        epoch &+= 1; transmissionIntent = nil; transmission?.cancel(); transmission = nil; busy = false; failure = .unknownOutcome
    }
    /// This state is in-memory only; closing the destination permanently clears it.
    public func suspend() {
        guard active, !isSuspended else { return }
        stopWaiting()
        // Invalidate a button action even if its queued Task has not started yet.
        epoch &+= 1; transmissionIntent = nil; isSuspended = true
        revalidateSuspension()
    }
    /// Foregrounding checks authority but never restores content or sends automatically.
    @discardableResult public func revalidateSuspension() -> Bool {
        guard active, isSuspended else { return false }
        do { try client.validateResume(scope: scope, grants: grants); return true }
        catch {
            let reason = error as? ShopNPCFailure ?? .stale
            invalidate(); failure = reason; return false
        }
    }
    public func resumeAfterInterruption() {
        guard revalidateSuspension() else { return }
        isSuspended = false
    }
    public func cancelReview() {
        guard active, !isSuspended, !busy else { return }
        transmissionIntent = nil; pending = nil; failure = nil
    }
    public func reviewText(_ value: String) throws {
        try check(voice: false)
        guard pending == nil else { throw ShopNPCFailure.busy }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ShopNPCFailure.invalid }
        pending = .init(id: UUID(), scope: scope, content: .text(text), replacing: nil); failure = nil
    }
    /// Explicit regeneration is a new model request; failures retain original answer and ID.
    public func reviewRegeneration(answerID: UUID) throws {
        try check(voice: false)
        guard pending == nil else { throw ShopNPCFailure.busy }
        guard let index = messages.firstIndex(where: { $0.id == answerID && !$0.mine }),
              let question = messages[..<index].last(where: { $0.mine }) else { throw ShopNPCFailure.invalid }
        pending = .init(id: UUID(), scope: scope, content: .text(question.text), replacing: answerID); failure = nil
    }
    public func reviewVoice(_ clip: ShopNPCVoiceClip) throws {
        try check(voice: true)
        guard pending == nil else { throw ShopNPCFailure.busy }
        pending = .init(id: UUID(), scope: scope, content: .voice(clip), replacing: nil); failure = nil
    }
    /// Capture only at the user's explicit button action, before starting an async Task.
    public func prepareTransmission(reviewID: UUID) throws -> ShopNPCTransmissionIntent {
        guard let review = pending, review.id == reviewID, review.scope == scope else { throw ShopNPCFailure.invalid }
        let voice: Bool = { if case .voice = review.content { return true }; return false }()
        try check(voice: voice)
        let intent = ShopNPCTransmissionIntent(nonce: UUID(), generation: epoch, reviewID: reviewID)
        transmissionIntent = intent
        return intent
    }
    /// Direct callers confirm now. Deferred UI actions must use the captured-intent overload.
    public func transmit(reviewID: UUID) async {
        do {
            let intent = try prepareTransmission(reviewID: reviewID)
            await transmit(reviewID: reviewID, intent: intent)
        } catch { failure = error as? ShopNPCFailure ?? .invalid }
    }
    /// Consume a one-use action before dispatch. A stale action never mutates a newer state.
    public func transmit(reviewID: UUID, intent: ShopNPCTransmissionIntent) async {
        guard transmissionIntent == intent, intent.generation == epoch, intent.reviewID == reviewID else { return }
        transmissionIntent = nil
        guard let review = pending, review.id == reviewID else { failure = .invalid; return }
        let voice: Bool = { if case .voice = review.content { return true }; return false }()
        do { try check(voice: voice) } catch { failure = error as? ShopNPCFailure ?? .invalid; return }
        guard review.scope == scope else { failure = .stale; pending = nil; return }
        if let lastSend, now().timeIntervalSince(lastSend) < 1 { failure = .rateLimited; return }
        lastSend = now(); busy = true; failure = nil
        let stamp = epoch
        let client = self.client
        let task = Task<ShopNPCReply, Error> {
            try Task.checkCancellation()
            switch review.content {
            case .text(let text): return try await client.text(text, requestID: review.id, scope: review.scope)
            case .voice(let clip): return try await client.voice(clip, requestID: review.id, scope: review.scope)
            }
        }
        transmission = task
        do {
            let reply = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard active, !isSuspended, epoch == stamp, scope == review.scope else { return }
            try Task.checkCancellation()
            guard !task.isCancelled else { throw CancellationError() }
            transmission = nil; busy = false; pending = nil; failure = nil
            if let replacing = review.replacing {
                guard !reply.text.isEmpty, let index = messages.firstIndex(where: { $0.id == replacing }) else { failure = .malformed; return }
                messages[index].text = reply.text
            } else {
                switch review.content {
                case .text(let text): messages.append(.init(mine: true, text: text))
                case .voice: messages.append(.init(mine: true, text: reply.asr.flatMap { $0.isEmpty ? nil : $0 } ?? "（语音）"))
                }
                // Empty success is not fabricated AI speech or completion evidence.
                if reply.text.isEmpty { failure = .malformed }
                else { messages.append(.init(mine: false, text: reply.text)) }
            }
        } catch {
            guard active, !isSuspended, epoch == stamp, scope == review.scope else { return }
            transmission = nil; busy = false; failure = error as? ShopNPCFailure ?? .unknownOutcome
        }
    }
    private func check(voice: Bool) throws {
        guard active, !isSuspended, scope.valid else { throw ShopNPCFailure.stale }
        guard !busy else { throw ShopNPCFailure.busy }
        guard voice ? grants.voiceAllowed : grants.textAllowed else { throw ShopNPCFailure.disabled }
    }
}
