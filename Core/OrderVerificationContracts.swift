import Foundation

public enum OrderVerificationOutcome: String, Equatable { case reportedRedeemed, needsChoice, failed, unknown }
public enum OrderVerificationChoiceKind: String, Equatable { case chapter, station }
public struct OrderVerificationChoice: Equatable, Identifiable { public let id: Int; public let name: String? }

/// Source scan_result.dart's three-way contract. Choice flags take precedence over a
/// business code, but never over authentication/authorization. No signed credential retained.
public struct OrderVerificationReceipt: Decodable, Equatable {
    public let outcome: OrderVerificationOutcome
    public let message: String?
    public let choiceKind: OrderVerificationChoiceKind?
    public let choices: [OrderVerificationChoice]
    enum CodingKeys: String, CodingKey { case code, msg, data }
    private struct Payload: Decodable {
        let needChapterChoice: Bool?
        let needStationChoice: Bool?
        let chapterIds: [Int]?
        let chapters: [Named]?
        let stations: [Named]?
    }
    private struct Named: Decodable {
        let id: Int?
        let registrationMerchantId: Int?
        let name: String?
        let title: String?
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let code = try c.decodeIfPresent(Int.self, forKey: .code)
        if code == 401 { throw APIError.unauthorized }
        if code == 403 { throw OrderLifecycleFailure.accessDenied }
        message = try c.decodeIfPresent(String.self, forKey: .msg)
        let payload = try c.decodeIfPresent(Payload.self, forKey: .data)
        var candidates: [OrderVerificationChoice] = []
        if payload?.needChapterChoice == true {
            outcome = .needsChoice; choiceKind = .chapter
            if let described = payload?.chapters, !described.isEmpty {
                candidates = described.compactMap { value in
                    guard let id = value.id, id > 0 else { return nil }
                    return OrderVerificationChoice(id: id, name: value.name ?? value.title)
                }
            } else { candidates = (payload?.chapterIds ?? []).filter { $0 > 0 }.map { OrderVerificationChoice(id: $0, name: nil) } }
        } else if payload?.needStationChoice == true {
            outcome = .needsChoice; choiceKind = .station
            // Never substitute station.id for registrationMerchantId. They identify different things.
            candidates = (payload?.stations ?? []).compactMap { value in
                guard let id = value.registrationMerchantId, id > 0 else { return nil }
                return OrderVerificationChoice(id: id, name: value.name ?? value.title)
            }
        } else {
            choiceKind = nil
            outcome = code == 200 ? .reportedRedeemed : (code == nil ? .unknown : .failed)
        }
        var seen = Set<Int>()
        choices = candidates.filter { seen.insert($0.id).inserted }
    }
    /// Selection alone is not a redemption result; empty choices remain non-redeemed.
    public func containsChoice(_ id: Int) -> Bool { outcome == .needsChoice && choices.contains { $0.id == id } }
}
