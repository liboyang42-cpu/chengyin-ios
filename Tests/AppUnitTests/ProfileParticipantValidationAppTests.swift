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
    func testAppSessionDurablePausedRunRecoveryAcrossRestartAndReturnRefresh() async throws {
        @MainActor final class MemoryVault: AppTokenStorage {
            var token: String?
            func read() throws -> String? { token }
            func write(_ token: String) throws { self.token = token }
            func clear() throws { token = nil }
        }
        final class ContinuationAuthWire: HTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, Int) {
                switch request.url?.lastPathComponent {
                case "phone":
                    return (Data(#"{"code":200,"token":"synthetic-7","data":{"id":7}}"#.utf8), 200)
                case "userInfo":
                    return (Data(#"{"code":200,"appUser":{"id":7,"role":"player"}}"#.utf8), 200)
                default:
                    throw APIError.invalidRequest
                }
            }
        }
        let base = URL(string: "https://continuation.example/native")!
        let deployment = try ReviewedAppDeployment(
            market: .china,
            baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]],
            verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.questify.continuation",
            realm: "synthetic",
            reads: [.playNodesAndRouteState]
        )
        let endpoints = try OperationEndpointApproval(
            baseURL: base,
            namespace: deployment.storageScope.service,
            accountID: 7,
            paths: ["api/play/nodes", "api/play/route-state"]
        )
        let issuance = UUID()
        let suite = "continuation-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        let anchors = ContinuationAnchors()
        let ciphertexts = ContinuationCiphertexts()
        let construction = PlayRecoveryConstruction.synthetic(anchors: anchors, ciphertexts: ciphertexts)
        let vault = MemoryVault()
        let wire = ContinuationAuthWire()

        func makeSession() -> AppSession {
            let root = AppCompositionRoot(
                deployment: .reviewed(deployment),
                storage: .init(defaults: defaults, tokenStore: { _ in vault }, playRecovery: construction),
                makeTransport: { wire },
                sessionDependencies: { _ in
                    .init(configuration: .init(market: .china, endpoints: endpoints, play: [.reads], playReadApprovalID: issuance))
                }
            )
            return AppSession(composition: root)
        }

        // Process 1: Sign in, register scope .activity(41), and write a durable paused snapshot to PlayDurableRecovery.
        let session1 = makeSession()
        await session1.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session1.account?.id, 7)
        // PlayerJourneyService default readsEnabled == false stays unchanged:
        XCTAssertFalse(session1.playerJourneyReader.isConfigured)

        session1.registerPlayContinuationScope(.activity(41), title: "外滩暗影")
        let playSession1 = try PlayExperienceSession(
            accountID: 7,
            epoch: 1,
            namespace: deployment.storageScope.service,
            token: "synthetic-7",
            role: "player"
        )
        let recovery1 = try construction.make(
            session: playSession1,
            scope: .activity(41),
            regionalConfiguration: deployment.regional,
            storageScope: deployment.storageScope
        )
        let storageKey = PlayRunStorageKey.make(session: playSession1, scope: .activity(41))
        let initialPaused = try await recovery1.read(key: storageKey)
        let pausedSnapshot = try PlayPausedSnapshot(
            owner: .init(session: playSession1),
            record: try PlayPausedRecord(elapsedSeconds: 540, savedAt: 1_700_000_100)
        )
        _ = try await recovery1.write(pausedSnapshot, replacing: initialPaused, key: storageKey)

        // Process 2 (simulated app restart): New AppSession with no in-memory PlayExperienceCoordinator loaded yet.
        let session2 = makeSession()
        await session2.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session2.account?.id, 7)
        XCTAssertFalse(session2.playerJourneyReader.isConfigured)

        let coordinator = HomeContinuationCoordinator()
        let recoveredCards = await coordinator.reload(
            ownerScope: session2.currentHomeContinuationOwnerScope,
            isAuthenticated: session2.isSignedIn,
            isJourneyReadConfigured: session2.playerJourneyReader.isConfigured,
            currentOwnerScope: { session2.currentHomeContinuationOwnerScope },
            loadParticipations: { try await session2.playerJourneyReader.participations() },
            loadPausedRuns: { records in await session2.loadPausedContinueRuns(participations: records) }
        )
        XCTAssertEqual(coordinator.readAvailability, .journeyReadNotApproved)
        XCTAssertEqual(recoveredCards.count, 1)
        XCTAssertEqual(recoveredCards.first?.playScope, .activity(41))
        XCTAssertEqual(recoveredCards.first?.title, "外滩暗影")
        XCTAssertEqual(recoveredCards.first?.subtitle, "已进行 9 分钟")

        // Pre-tap verification enters runtime (.activity(41)) when durable pause and playExperience are valid:
        let card41 = try XCTUnwrap(recoveredCards.first)
        let navDecision = await coordinator.verifyNavigation(
            for: card41,
            currentOwnerScope: { session2.currentHomeContinuationOwnerScope },
            canEnterRuntime: { session2.playExperience(for: $0) != nil },
            hasDurableOrLivePause: { await session2.hasResumablePlayState(for: $0) }
        )
        XCTAssertEqual(navDecision, .enterRuntime(.activity(41)))

        // Simulate completing/ending the run inside runtime (tombstoning the durable paused record) and returning to Home:
        let currentPaused = try await recovery1.read(key: storageKey)
        let endedSnapshot = try PlayPausedSnapshot(
            owner: .init(session: playSession1),
            record: nil,
            tombstone: 1_700_000_200
        )
        _ = try await recovery1.write(endedSnapshot, replacing: currentPaused, key: storageKey)

        let refreshedCards = await coordinator.reload(
            ownerScope: session2.currentHomeContinuationOwnerScope,
            isAuthenticated: session2.isSignedIn,
            isJourneyReadConfigured: session2.playerJourneyReader.isConfigured,
            currentOwnerScope: { session2.currentHomeContinuationOwnerScope },
            loadParticipations: { try await session2.playerJourneyReader.participations() },
            loadPausedRuns: { records in await session2.loadPausedContinueRuns(participations: records) }
        )
        XCTAssertTrue(refreshedCards.isEmpty)
    }
}

private actor ContinuationAnchors: ContentDraftAnchorStore {
    private var values: [String: ContentDraftAnchorItem] = [:]
    func read(slot: String) throws -> ContentDraftAnchorItem? { values[slot] }
    func insert(slot: String, item: ContentDraftAnchorItem) throws -> Bool {
        guard values[slot] == nil else { return false }; values[slot] = item; return true
    }
    func exchange(slot: String, matchingTag: Data, item: ContentDraftAnchorItem) throws -> Bool {
        guard values[slot]?.tag == matchingTag else { return false }; values[slot] = item; return true
    }
}
private actor ContinuationCiphertexts: ContentDraftCiphertextStore {
    private var values: [String: Data] = [:]
    private var presence: Set<String> = []
    func createPresence(slot: String) -> Bool { presence.insert(slot).inserted }
    func hasPresence(slot: String) -> Bool { presence.contains(slot) }
    func insert(name: String, bytes: Data) throws {
        guard values[name] == nil else { throw ContentDraftIssue.storageUnavailable }; values[name] = bytes
    }
    func readDurably(name: String, limit: Int) throws -> Data {
        guard let value = values[name], value.count <= limit else { throw ContentDraftIssue.storageUnavailable }; return value
    }
    func removeDurably(name: String) { values[name] = nil }
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
