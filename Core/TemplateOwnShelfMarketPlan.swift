import Foundation

/// Mini-program `utils/template-market.js` marketView, as display-only review copy.
/// It builds no request and grants no write: the marketplace submit/toggle endpoints are
/// not in any reviewed allowlist, so the plan is shown for review and never dispatched.
public struct TemplateOwnShelfMarketPlan: Equatable {
    public enum Action: Equatable {
        /// 提交广场审核.
        case submitReview
        /// 撤回广场审核 (pending, target 0).
        case withdrawReview
        /// 从广场下架 (listed, target 0).
        case delist
        /// 上架广场 (approved and unlisted, target 1).
        case list
        public var publishTarget: Int? {
            switch self {
            case .submitReview: return nil
            case .withdrawReview, .delist: return 0
            case .list: return 1
            }
        }
        public var labelKey: String {
            switch self {
            case .submitReview: return "templateOwnShelf.market.submit"
            case .withdrawReview: return "templateOwnShelf.market.withdraw"
            case .delist: return "templateOwnShelf.market.delist"
            case .list: return "templateOwnShelf.market.list"
            }
        }
    }
    public let action: Action?
    /// Always false: no reviewed endpoint allowlist entry exists for these writes.
    public var isDispatchable: Bool { false }
    public init(_ state: TemplateOwnShelfStateProjection) {
        let approved = state.personal == .approved
        // The source menu offers submission first when both could apply.
        if approved && (state.market == .notSubmitted || state.market == .rejected) { action = .submitReview }
        else if state.market == .reviewing { action = .withdrawReview }
        else if state.market == .listed { action = .delist }
        else if approved && state.market == .unlisted { action = .list }
        else { action = nil }
    }
}

/// Same approved `api/template/my-list` object as the state projection.
/// A malformed optional column is absent; this envelope adds no request.
struct TemplateOwnShelfCardFactsEnvelope: Decodable {
    struct Payload: Decodable { let rows: [TemplateOwnShelfCardFacts] }
    let data: Payload
}

/// Optional card columns the source card shows (评分, 次引用, 时长, 创建时间, 审核反馈).
/// Decoded separately from the shared DTO; a malformed column is simply absent.
public struct TemplateOwnShelfCardFacts: Decodable, Equatable {
    public let rating: Decimal?
    public let useCount: Int?
    public let durationMinutes: Int
    public let createTime: String?
    public let reviewFeedback: String?
    private enum Keys: String, CodingKey { case rating, useNum, duration, createTime, reason }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        func text(_ key: Keys) -> String? {
            guard let raw = try? values.decode(String.self, forKey: key) else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func number(_ key: Keys) -> Decimal? {
            if let value = try? values.decode(Decimal.self, forKey: key) { return value }
            return text(key).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        }
        rating = number(.rating).flatMap { $0 >= 0 ? $0 : nil }
        useCount = number(.useNum).flatMap { $0 >= 0 ? NSDecimalNumber(decimal: $0).intValue : nil }
        // Source renders `${duration || 0}分钟`.
        durationMinutes = number(.duration).flatMap { $0 > 0 ? NSDecimalNumber(decimal: $0).intValue : nil } ?? 0
        createTime = text(.createTime)
        reviewFeedback = text(.reason)
    }
}

/// Source 删除节点玩法 danger copy, shown inside the existing review → confirm flow.
public enum TemplateOwnShelfDeleteCopy {
    public static let titleKey = "templateOwnShelf.delete.title %@"
    public static let bodyKey = "templateOwnShelf.delete.body"
    public static let consequenceKeys = ["templateOwnShelf.delete.keepsReferences", "templateOwnShelf.delete.irreversible"]
    public static let confirmKey = "templateOwnShelf.delete.confirm"
}
