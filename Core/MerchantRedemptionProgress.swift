import Foundation

/// Read-only P067 Mini buildTimeline/progressStep, using state facts rather than timestamps.
public struct MerchantRedemptionProgress: Equatable {
    public enum State: String { case done, current, pending }
    public struct Step: Equatable, Identifiable {
        public let id: String
        public let state: State
        public let timestamp: String?
    }
    public let steps: [Step]
    public init?(record: MerchantBusinessRecord, access: MerchantBusinessAccess) {
        let fields = record.fields
        guard record.kind == .redemption, access.allows("merchant:finance:read"),
              fields.mbText("settlementRoute") == "CHAPTER_OFFER",
              let settlement = fields.mbText("settlementState"), !settlement.isEmpty,
              let display = fields.mbText("displayState"), !display.isEmpty else { return nil }
        let done: Int
        let current: Bool
        switch settlement {
        case "SETTLED", "ADJUSTED", "ADJUSTMENT_PENDING": done = 4; current = false
        case "PENDING": done = 1; current = true
        default: done = 1; current = false
        }
        let paidAt = fields["publicSettlement"]?.object?["paidAt"]?.string
        steps = ["redeemed", "generated", "confirmed", "paid"].enumerated().map { index, id in
            let state: State = index < done ? .done : (current && index == done ? .current : .pending)
            // Never attach an apparent date to a future node, even if an inconsistent payload contains it.
            let timestamp = state == .done ? (id == "redeemed" ? fields["occurredAt"]?.string : id == "paid" ? paidAt : nil) : nil
            return Step(id: id, state: state, timestamp: timestamp)
        }
    }
}
