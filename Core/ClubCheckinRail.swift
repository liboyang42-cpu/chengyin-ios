import Foundation

/// Mini-program club/checkin-detail `buildRail`: 已报名 → 已接洽 → 已核销 → 已评价.
/// `railStep` = -1 (refunded) or an absent/non-integer step lights nothing; the client
/// never infers progress from other fields.
public struct ClubCheckinRail: Equatable {
    public enum Step: String, CaseIterable, Sendable { case signed, contacted, verified, reviewed }
    public struct Stop: Equatable, Identifiable {
        public let step: Step
        public let reached: Bool
        public let current: Bool
        public var id: String { step.rawValue }
    }
    public let stops: [Stop]
    /// `statusCode == REFUNDED`: 这单已退款，履约轨迹不再推进。
    public let refunded: Bool
    public init(railStep: ClubGovernanceValue, statusCode: ClubGovernanceValue) {
        let at: Int? = { if case .integer(let value) = railStep { return value }; return nil }()
        stops = Step.allCases.enumerated().map { index, step in
            .init(step: step, reached: (at ?? -1) >= 0 && index <= (at ?? -1), current: at == index)
        }
        refunded = statusCode == .string("REFUNDED")
    }
}
