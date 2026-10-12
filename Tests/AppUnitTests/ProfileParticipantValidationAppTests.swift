import XCTest
@testable import Questify

@MainActor final class ProfileParticipantValidationAppTests: XCTestCase {
    private func loaded(_ id: Int? = nil) async -> (ParticipantFormModel, ValidationStore) {
        let store = ValidationStore()
        let model = ParticipantFormModel(id: id, reader: store, coordinator: ParticipantMutationCoordinator(writer: store, reader: store))
        await model.load(); return (model, store)
    }
    func testInvalidReviewHasNoConfirmationOrDispatch() async {
        let (m, s) = await loaded(); XCTAssertEqual(m.reviewForSave(), .name)
        XCTAssertEqual(m.validationIssue, .name); XCTAssertFalse(m.showConfirmation); XCTAssertEqual(s.writes, 0)
    }
    func testCorrectionAdvancesAndValidInputUsesOriginalConfirmation() async {
        let (m, s) = await loaded(); _ = m.reviewForSave(); m.draft.fullName = "Fixture"
        XCTAssertEqual(m.validationIssue, .phone); XCTAssertEqual(m.reviewForSave(), .phone)
        m.draft.mobilePhone = "13800000000"; XCTAssertNil(m.validationIssue); XCTAssertNil(m.reviewForSave())
        XCTAssertTrue(m.showConfirmation); XCTAssertEqual(m.operation, .awaitingConfirmation); XCTAssertEqual(s.writes, 0)
    }
    func testConfirmationCancelPreservesDraftAndDoesNotWrite() async {
        let (m, s) = await loaded(); m.draft.fullName = "Fixture"; m.draft.mobilePhone = "13800000000"
        let draft = m.draft; _ = m.reviewForSave(); m.cancelConfirmation()
        XCTAssertEqual(m.draft, draft); XCTAssertFalse(m.showConfirmation); XCTAssertEqual(s.writes, 0)
    }
    func testRepeatedValidTapCannotReplacePendingConfirmation() async {
        let (m, s) = await loaded(); m.draft.fullName = "Fixture"; m.draft.mobilePhone = "13800000000"
        _ = m.reviewForSave(); let confirmation = m.confirmation
        XCTAssertFalse(m.canReviewForSave); _ = m.reviewForSave(); XCTAssertEqual(m.confirmation, confirmation); XCTAssertEqual(s.writes, 0)
    }
    func testExplicitConfirmationRetainsExistingSavePath() async {
        let (m, s) = await loaded(); m.draft.fullName = "Fixture"; m.draft.mobilePhone = "13800000000"
        _ = m.reviewForSave(); let saved = await m.confirmMutation(); XCTAssertTrue(saved); XCTAssertEqual(s.writes, 1)
    }
    func testReadIdentityChangeBlocksLocalAction() async {
        let (m, s) = await loaded(); s.identity = .init(accountID: 9002, epoch: 2)
        XCTAssertFalse(m.canReviewForSave); XCTAssertNil(m.reviewForSave()); XCTAssertFalse(m.validationReview.hasRequestedReview); XCTAssertEqual(s.writes, 0)
    }
    func testMissingConfigurationBlocksAction() async {
        let (m, s) = await loaded(); s.isConfigured = false
        XCTAssertFalse(m.canReviewForSave); XCTAssertNil(m.reviewForSave()); XCTAssertEqual(s.writes, 0)
    }
    func testDisappearAndReloadResetReview() async {
        let (m, _) = await loaded(); _ = m.reviewForSave(); m.disappear()
        XCTAssertFalse(m.validationReview.hasRequestedReview); XCTAssertNil(m.validationIssue)
        await m.load(); XCTAssertFalse(m.validationReview.hasRequestedReview)
    }
    func testEditingDoesNotChangeHiddenMetadata() async {
        let (m, s) = await loaded(911); let before = m.draft
        m.draft.fullName = ""; _ = m.reviewForSave(); m.draft.fullName = "Updated"
        XCTAssertEqual(m.draft.province, before.province); XCTAssertEqual(m.draft.detailAddress, before.detailAddress)
        XCTAssertEqual(m.draft.isDefault, before.isDefault); XCTAssertEqual(s.writes, 0)
    }
    func testUnknownWriteKeepsExistingLock() async {
        let (m, s) = await loaded(); s.loseResponse = true
        m.draft.fullName = "Fixture"; m.draft.mobilePhone = "13800000000"; _ = m.reviewForSave()
        _ = await m.confirmMutation(); XCTAssertFalse(m.canReviewForSave); _ = m.reviewForSave(); XCTAssertEqual(s.writes, 1)
    }
}

@MainActor private final class ValidationStore: ProfileReading, ParticipantWriting {
    var isConfigured = true
    var identity: ProfileReadIdentity? = .init(accountID: 9001, epoch: 1)
    var writes = 0
    var loseResponse = false
    func profileParticipants() async throws -> [ProfileParticipant] { [try await profileParticipant(id: 911)] }
    func profileParticipant(id: Int) async throws -> ProfileParticipant {
        try JSONDecoder().decode(ProfileParticipant.self, from: Data(#"{"id":911,"fullName":"Fixture","mobilePhone":"13800000000","province":"Synthetic region","detailAddress":"Synthetic street","isDefault":true}"#.utf8))
    }
    func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws {
        guard expectedIdentity == identity else { throw ParticipantWriteError.notSent(.unauthorized) }
        _ = try mutation.fields(); writes += 1
        if loseResponse { throw ParticipantWriteError.outcomeUnknown(.transport) }
    }
    func profileOrders() async throws -> [ProfileOrder] { [] }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.invalidRequest }
    func profileBadges() async throws -> ProfileBadgeWall { .init(identities: [], medals: []) }
}
