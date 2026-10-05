import Foundation

/// In-memory fixture only. No credential, network, image upload, or production identity.
public actor ProfileEditSyntheticService: ProfileEditServing {
    public enum Scenario: Equatable { case success, rejected, unknown, missingPreservation, refreshFailure }
    private let scenario: Scenario
    private var readCount = 0
    private var tagIds = "4,7"
    private var name = "Trail Friend"
    private var introduction = "Weekend walks"
    public init(scenario: Scenario = .success) { self.scenario = scenario }
    public func read(token: String) async throws -> ProfileEditSnapshot {
        readCount += 1
        if scenario == .refreshFailure && readCount == 2 { throw APIError.malformedResponse }
        var object: [String: Any] = ["id": 901, "nickname": name, "introduction": introduction,
                                     "avatar": "", "wechat": "", "casePics": "", "tagIds": tagIds]
        if scenario == .missingPreservation { object.removeValue(forKey: "casePics") }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    public func save(_ payload: ProfileEditPayload, token: String) async throws {
        switch scenario {
        case .success, .refreshFailure:
            name = payload.name; introduction = payload.introduction; tagIds = payload.tagIds
        case .rejected: throw ProfileEditWriteError.rejected(.init(code: 422, message: "Synthetic content rejection"))
        case .unknown: throw ProfileEditWriteError.outcomeUnknown
        case .missingPreservation: throw ProfileEditWriteError.notSent
        }
    }
}
