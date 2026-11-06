import Foundation

/// Original participation-date aggregate, never inferred from purchase/CRM rows.
public struct ClubParticipationTrend: Equatable {
    public struct Row: Equatable {
        public let date: String
        public let count: Int
    }
    public let topicID: Int
    public let rows: [Row]
    public init(topicID: Int, value: ClubGovernanceValue) throws {
        guard topicID > 0, case .array(let values) = value else { throw ClubGovernanceFailure.malformed }
        self.topicID = topicID
        rows = try values.map { value in
            guard case .object(let fields) = value,
                  case .string(let date)? = fields["participateDate"],
                  !date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let count = Self.count(fields["totalCount"]) else {
                throw ClubGovernanceFailure.malformed
            }
            // Keep server order/date bytes, including sparse dates; no zero-fill or client sorting.
            return Row(date: date, count: count)
        }
    }
    private static func count(_ value: ClubGovernanceValue?) -> Int? {
        if case .integer(let count)? = value { return count >= 0 ? count : nil }
        // Original mini tests explicitly cover numeric strings. Accept digits only,
        // never JS Number(null/empty/bool), signs, fractions, exponents or overflow.
        if case .string(let text)? = value, !text.isEmpty,
           text.utf8.allSatisfy({ (48...57).contains($0) }), let count = Int(text) { return count }
        return nil
    }
}
public struct ClubParticipationTrendDenied: Error, Equatable {
    public let message: String?
    public init(message: String?) { self.message = message }
}
