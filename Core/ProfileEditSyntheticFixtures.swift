import Foundation

/// In-memory fixture only. No credential, network, image upload, or production identity.
public actor ProfileEditSyntheticService: ProfileEditServing {
    public enum Scenario: Equatable { case success, rejected, unknown, missingPreservation }
    private let scenario: Scenario
    private var name = "Trail Friend"
    private var introduction = "Weekend walks"
    public init(scenario: Scenario = .success) { self.scenario = scenario }
    public func read(token: String) async throws -> ProfileEditSnapshot {
        var object: [String: Any] = ["id": 901, "nickname": name, "introduction": introduction,
                                     "avatar": "", "wechat": "", "casePics": "", "tagIds": "4,7"]
        if scenario == .missingPreservation { object.removeValue(forKey: "casePics") }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    public func save(_ payload: ProfileEditPayload, token: String) async throws {
        switch scenario {
        case .success: name = payload.name; introduction = payload.introduction
        case .rejected: throw ProfileEditWriteError.rejected(.init(code: 422, message: "Synthetic content rejection"))
        case .unknown: throw ProfileEditWriteError.outcomeUnknown
        case .missingPreservation: throw ProfileEditWriteError.notSent
        }
    }
}
