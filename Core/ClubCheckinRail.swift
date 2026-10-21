import Foundation

/// Mini-program club/checkin-detail `buildRail`: 已报名 → 已接洽 → 已核销 → 已评价.
/// `railStep` = -1 (refunded) or an absent/non-integer step lights nothing; the client
/// never infers progress from other fields.
public struct ClubCheckinRail: Equatable {
    public enum Step: String, CaseIterable, Sendable { case signed, contacted, verified, reviewed }
    public enum StateKind: String, Equatable, Sendable {
        case missing
        case denied
        case error

        public var title: String {
            switch self {
            case .missing: return "核销记录不存在"
            case .denied: return "无权查看该核销记录"
            case .error: return "核销详情加载失败"
            }
        }
    }
    public struct Stop: Equatable, Identifiable {
        public let step: Step
        public let reached: Bool
        public let current: Bool
        public var id: String { step.rawValue }
    }
    public let stops: [Stop]
    /// `statusCode == REFUNDED`: 这单已退款，履约轨迹不再推进。
    public let refunded: Bool
    public let sessionTimeText: String?
    public let statusTimeText: String?
    public init(railStep: ClubGovernanceValue, statusCode: ClubGovernanceValue, sessionTime: ClubGovernanceValue = .null, statusTime: ClubGovernanceValue = .null) {
        let at: Int? = { if case .integer(let value) = railStep { return value }; return nil }()
        stops = Step.allCases.enumerated().map { index, step in
            .init(step: step, reached: (at ?? -1) >= 0 && index <= (at ?? -1), current: at == index)
        }
        refunded = statusCode == .string("REFUNDED")
        sessionTimeText = Self.formatTime(sessionTime)
        statusTimeText = Self.formatTime(statusTime)
    }
    public static func stateKind(for failure: ClubGovernanceFailure?, recordPresent: Bool = true) -> StateKind? {
        if let failure {
            switch failure {
            case .forbidden: return .denied
            case .rejected(let code, _):
                if code == 403 { return .denied }
                if code == 404 { return .missing }
                return .error
            default:
                return .error
            }
        }
        return recordPresent ? nil : .missing
    }
    public static func stateTitle(for failure: ClubGovernanceFailure?, recordPresent: Bool = true) -> String? {
        stateKind(for: failure, recordPresent: recordPresent)?.title
    }
    public static func formatTime(_ value: ClubGovernanceValue) -> String? {
        switch value {
        case .string(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "T", with: " ")
            guard !trimmed.isEmpty else { return nil }
            return trimmed.count >= 16 ? String(trimmed.prefix(16)) : trimmed
        case .integer(let ms) where ms > 0:
            let seconds = ms > 10_000_000_000 ? Double(ms) / 1000.0 : Double(ms)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: Date(timeIntervalSince1970: seconds))
        default:
            return nil
        }
    }
}
