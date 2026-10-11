import Foundation

/// In-memory fixture only. No credential, network, image upload, or production identity.
public actor ProfileEditSyntheticService: ProfileEditServing {
    public enum Scenario: Equatable { case success, rejected, unknown, missingPreservation, refreshFailure, portfolioImages, contactQR, preferenceRemoval, caseRemoval }
    private let scenario: Scenario
    private var readCount = 0
    private var tagIds = "4,7"
    private var wechat = ""
    private var casePics = ""
    private var name = "Trail Friend"
    private var introduction = "Weekend walks"
    private var caseIntroduction = "City photo stories"
    public init(scenario: Scenario = .success) {
        self.scenario = scenario
        if scenario == .contactQR { wechat = "https://profile-fixture.invalid/contact.png" }
        if scenario == .preferenceRemoval { tagIds = "4,7007" }
        if scenario == .portfolioImages || scenario == .caseRemoval {
            casePics = "https://profile-fixture.invalid/one.jpg;https://profile-fixture.invalid/two.jpg"
        }
    }
    public func read(token: String) async throws -> ProfileEditSnapshot {
        readCount += 1
        if scenario == .refreshFailure && readCount == 2 { throw APIError.malformedResponse }
        var object: [String: Any] = ["id": 901, "nickname": name, "introduction": introduction,
                                     "avatar": "", "wechat": wechat, "casePics": casePics, "caseIntroducton": caseIntroduction, "tagIds": tagIds]
        if scenario == .preferenceRemoval {
            object["sysCategoryList"] = [["id": 4, "categoryName": "City walks"], ["id": 7007, "categoryName": "Retired category"]]
        }
        if scenario == .missingPreservation { object.removeValue(forKey: "casePics") }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    public func save(_ payload: ProfileEditPayload, token: String) async throws {
        switch scenario {
        case .success, .refreshFailure, .portfolioImages, .contactQR, .preferenceRemoval, .caseRemoval:
            name = payload.name; introduction = payload.introduction; tagIds = payload.tagIds; wechat = payload.wechat; casePics = payload.casePics
            if let text = payload.caseIntroduction { caseIntroduction = text }
        case .rejected: throw ProfileEditWriteError.rejected(.init(code: 422, message: "Synthetic content rejection"))
        case .unknown: throw ProfileEditWriteError.outcomeUnknown
        case .missingPreservation: throw ProfileEditWriteError.notSent
        }
    }
}
