import Foundation

/// A bounded, in-memory display projection for one open merchant conversation.
/// It is not a server history, a model context, a persistence envelope or a fact cache.
public struct MerchantNPCConversationHistory: Equatable {
    public enum Outcome: String, Equatable { case succeeded = "SUCCEEDED", rejected = "REJECTED", failed = "FAILED" }
    public struct Turn: Identifiable, Equatable {
        public let id: UUID
        public let question: String
        public let safeText: String
        public let outcome: Outcome
        public var utf8Count: Int { question.utf8.count + safeText.utf8.count }
    }
    public static let maximumTurns = 20
    public static let maximumUTF8Bytes = 65_536
    public private(set) var turns: [Turn] = []
    public private(set) var hasOmittedTurns = false
    public var utf8Count: Int { turns.reduce(0) { $0 + $1.utf8Count } }
    public init() {}

    /// Pending, retryable, unknown-status and empty replies never become completed turns.
    /// Only safeText is retained; provider errors, URLs and internal metadata are excluded.
    @discardableResult public mutating func record(requestID: UUID, question: String, reply: MerchantNPCReply) -> Bool {
        guard !reply.canRetry, let outcome = Outcome(rawValue: reply.outcomeStatus),
              let text = reply.safeText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let existing = turns.first(where: { $0.id == requestID }) {
            return existing.question.utf8.elementsEqual(question.utf8) && existing.safeText.utf8.elementsEqual(text.utf8) && existing.outcome == outcome
        }
        let questionSize = question.utf8.count
        guard questionSize <= Self.maximumUTF8Bytes, text.utf8.count <= Self.maximumUTF8Bytes - questionSize else {
            hasOmittedTurns = true; return false // No silent partial/truncated quotation.
        }
        let turn = Turn(id: requestID, question: question, safeText: text, outcome: outcome)
        while !turns.isEmpty && (turns.count >= Self.maximumTurns || utf8Count > Self.maximumUTF8Bytes - turn.utf8Count) {
            turns.removeFirst(); hasOmittedTurns = true
        }
        turns.append(turn); return true
    }
    public mutating func clear() { turns.removeAll(keepingCapacity: false); hasOmittedTurns = false }
}
