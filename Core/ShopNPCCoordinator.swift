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
@MainActor @Observable public final class ShopNPCCoordinator {
    public private(set) var messages: [ShopNPCMessage] = []
    public private(set) var pending: ShopNPCReview?
    public private(set) var failure: ShopNPCFailure?
    public private(set) var busy = false
    public private(set) var active = true
    public private(set) var scope: ShopNPCScope
    public private(set) var grants: ShopNPCGrants
    private let client: ShopNPCHTTPClient
    private var epoch: UInt64 = 0
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
        epoch &+= 1; active = false; busy = false; pending = nil; messages = []; failure = nil; lastSend = nil
    }
    public func cancelReview() { pending = nil; failure = nil }
    public func reviewText(_ value: String) throws {
        try check(voice: false)
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ShopNPCFailure.invalid }
        pending = .init(id: UUID(), scope: scope, content: .text(text), replacing: nil); failure = nil
    }
    /// Explicit regeneration is a new model request; failures retain original answer and ID.
    public func reviewRegeneration(answerID: UUID) throws {
        try check(voice: false)
        guard let index = messages.firstIndex(where: { $0.id == answerID && !$0.mine }),
              let question = messages[..<index].last(where: { $0.mine }) else { throw ShopNPCFailure.invalid }
        pending = .init(id: UUID(), scope: scope, content: .text(question.text), replacing: answerID); failure = nil
    }
    public func reviewVoice(_ clip: ShopNPCVoiceClip) throws {
        try check(voice: true)
        pending = .init(id: UUID(), scope: scope, content: .voice(clip), replacing: nil); failure = nil
    }
    /// User must confirm this review ID. Unknown outcomes retain its idempotency key.
    public func transmit(reviewID: UUID) async {
        guard let review = pending, review.id == reviewID else { failure = .invalid; return }
        let voice: Bool = { if case .voice = review.content { return true }; return false }()
        do { try check(voice: voice) } catch { failure = error as? ShopNPCFailure ?? .invalid; return }
        guard review.scope == scope else { failure = .stale; pending = nil; return }
        if let lastSend, now().timeIntervalSince(lastSend) < 1 { failure = .rateLimited; return }
        lastSend = now(); busy = true; failure = nil
        let stamp = epoch
        do {
            let reply: ShopNPCReply
            switch review.content {
            case .text(let text): reply = try await client.text(text, requestID: review.id, scope: review.scope)
            case .voice(let clip): reply = try await client.voice(clip, requestID: review.id, scope: review.scope)
            }
            guard active, epoch == stamp, scope == review.scope else { return }
            busy = false; pending = nil; failure = nil
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
            guard active, epoch == stamp, scope == review.scope else { return }
            busy = false; failure = error as? ShopNPCFailure ?? .unknownOutcome
        }
    }
    private func check(voice: Bool) throws {
        guard active, scope.valid else { throw ShopNPCFailure.stale }
        guard !busy else { throw ShopNPCFailure.busy }
        guard voice ? grants.voiceAllowed : grants.textAllowed else { throw ShopNPCFailure.disabled }
    }
}
