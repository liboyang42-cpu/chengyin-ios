import XCTest
import SwiftUI
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
    func testParticipantsViewsConstructWithPurposeSubtitleKey() throws {
        let store = ValidationStore()
        let coordinator = ParticipantMutationCoordinator(writer: store, reader: store)
        let listView = ProfileParticipantsView(reader: store, coordinator: coordinator)
        let detailView = ProfileParticipantDetailView(id: 911, reader: store, coordinator: nil)
        _ = listView.body
        _ = detailView.body
        XCTAssertEqual(store.writes, 0)

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("App/ProfileParticipantsView.swift"), encoding: .utf8)
        XCTAssertEqual(source.components(separatedBy: #"Text("participant.form.purpose")"#).count - 1, 3)
        XCTAssertFalse(source.contains(#"Text("profile.participants.hint")"#))

        let localizationsData = try Data(contentsOf: root.appendingPathComponent("docs/participant-localizations.json"))
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: localizationsData) as? [[String: String]])
        let purposeEntry = try XCTUnwrap(entries.first { $0["key"] == "participant.form.purpose" })
        XCTAssertEqual(purposeEntry["zh-Hans"], "用于报名联系和到场核验，不会公开展示，也不用于配送。")
    }
    func testHomeHeroHeaderAndPlayContinuationBannerViewsIntegrateWithParityPresentation() throws {
        let run = PlayContinueRun(scope: .activity(12), elapsedSeconds: 420, title: "外滩迷雾")
        let duplicateJoined = try JSONDecoder().decode(
            ParticipationRecord.self,
            from: Data(#"{"id":80,"ownerType":0,"cmsActivity":{"id":12,"name":"外滩迷雾"}}"#.utf8)
        )
        let joinedTopic = try JSONDecoder().decode(
            ParticipationRecord.self,
            from: Data(#"{"id":81,"ownerType":1,"activityTitle":" 愚园路漫步 ","cmsTopic":{"id":91,"address":" 静安寺 "}}"#.utf8)
        )
        let cards = HomeIndexParityPresentation.continuationCards(
            pausedRuns: [run],
            participations: [duplicateJoined, joinedTopic]
        )
        XCTAssertEqual(cards.map(\.kind), [.continueGame, .continueExploration])
        XCTAssertEqual(cards.map(\.destination), [.activity(12), .topic(91)])
        XCTAssertEqual(cards[0].subtitle, "已进行 7 分钟")
        XCTAssertEqual(cards[1].subtitle, "静安寺")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            HomeIndexParityPresentation.upcomingCountdownText(start: now.addingTimeInterval(3_600 + 120), now: now),
            "距上线 1小时2分"
        )

        var selectedBanner: HomeIndexParityPresentation.ActionBanner?
        let hero = HomeHeroHeaderSectionView(nickname: "阿明", selectedCity: "上海", isNationwide: false) {
            selectedBanner = $0
        }
        _ = hero.body
        hero.onSelectBanner?(HomeIndexParityPresentation.fixedActionBanners[0])
        XCTAssertEqual(selectedBanner?.id, "club_apply")

        var openedDestination: HomeFeedDestination?
        var selectedCard: HomeIndexParityPresentation.ContinuationCard?
        let continuationBanner = PlayContinuationBannerView(cards: cards, onSelectCard: {
            selectedCard = $0
        }) {
            openedDestination = $0
        }
        _ = continuationBanner.body
        continuationBanner.onOpen?(cards[1].destination)
        XCTAssertEqual(openedDestination, .topic(91))
        continuationBanner.onSelectCard?(cards[0])
        XCTAssertEqual(selectedCard?.playScope, .activity(12))

        XCTAssertEqual(FreeExplorationVisitSteps.formatStat(0), "0")
        XCTAssertEqual(FreeExplorationVisitSteps.formatStat(15), "15")
        XCTAssertEqual(FreeExplorationVisitSteps.formatStat(1e100), "—")
        XCTAssertEqual(FreeExplorationVisitSteps.formatStat(-5), "—")
        XCTAssertEqual(FreeExplorationVisitSteps.formatStat(.nan), "—")
        XCTAssertEqual(FreeExplorationVisitSteps.formatStat(.infinity), "—")
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
