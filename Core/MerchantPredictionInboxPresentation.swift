import Foundation

/// Source pages/merchant/predict/index.js shapeRound: the deadline line is the reason the page exists,
/// so the last day reads as "today or void" (danger) rather than "0 days left".
public struct MerchantPredictionInboxPresentation: Equatable {
    public enum Deadline: Equatable { case daysLeft(Int), lastDay }
    public enum Bets: Equatable { case count(Int), none }
    public let deadline: Deadline, bets: Bets, optionCount: Int
    public var isUrgent: Bool { deadline == .lastDay }
    public init(daysLeft: Int, betCount: Int, optionCount: Int) {
        deadline = daysLeft > 0 ? .daysLeft(daysLeft) : .lastDay
        bets = betCount > 0 ? .count(betCount) : .none
        self.optionCount = optionCount
    }
}
