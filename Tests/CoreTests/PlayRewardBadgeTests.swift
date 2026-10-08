import XCTest
@testable import QuestifyCore

@MainActor final class PlayRewardBadgeTests: XCTestCase {
    private func wire(_ json: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8)) }
    private func identity(_ code: String = "FIRST_STEP", unlocked: Bool = true) throws -> ProfileIdentityBadge {
        try JSONDecoder().decode(ProfileIdentityBadge.self, from: Data("{\"badgeCode\":\"\(code)\",\"badgeName\":\"Saved title\",\"unlocked\":\(unlocked)}".utf8))
    }
    private func medal(_ kind: String = "achievement", code: String = "FIRST_STEP") throws -> ProfileMedal {
        try JSONDecoder().decode(ProfileMedal.self, from: Data("{\"kind\":\"\(kind)\",\"badgeCode\":\"\(code)\",\"medalName\":\"Saved achievement\"}".utf8))
    }
    private var target: PlayRewardBadgeTarget { PlayRewardBadgeTarget(code: "FIRST_STEP", name: "Receipt title")! }
    func testReceiptRetainsStableCodesAndSourceOrderWithoutFabricatingMissingTargets() throws {
        let receipt = try wire(#"{"newBadges":[{"code":"TOPIC_CLEAR","name":"A"},{"code":"FIRST_STEP","name":"B"},{"name":"No code"}]}"#)
        let targets = PlayRewardBadgeTarget.targets(in: receipt)
        XCTAssertEqual(targets.map(\.code), ["TOPIC_CLEAR", "FIRST_STEP"])
        XCTAssertEqual(targets.map(\.name), ["A", "B"])
    }
    func testRepeatedCodesHaveOneNavigationIdentity() throws {
        let receipt = try wire(#"{"newBadges":[{"code":"FIRST_STEP","name":"A"},{"code":"FIRST_STEP","name":"B"}]}"#)
        XCTAssertEqual(PlayRewardBadgeTarget.targets(in: receipt).count, 1)
    }
    func testNoAwardsMalformedRowsAndNamesNeverCreateEarnedBadges() throws {
        for json in [#"{}"#, #"{"newBadges":null}"#, #"{"newBadges":{}}"#, #"{"newBadges":[null,42,{"code":2},{"code":""},{"code":" A "}]}"#] {
            XCTAssertTrue(PlayRewardBadgeTarget.targets(in: try wire(json)).isEmpty)
        }
        XCTAssertNil(PlayRewardBadgeTarget(code: "A\nB"))
        XCTAssertNil(PlayRewardBadgeTarget(code: String(repeating: "x", count: 257)))
        XCTAssertNil(PlayRewardBadgeTarget(code: "A", name: String(repeating: "x", count: 513))?.name)
    }
    func testExactIdentityCodeReadbackOverridesReceiptName() throws {
        let badge = try identity()
        let focus = PlayRewardBadgeFocus(target: target, wall: .init(identities: [badge], medals: []))
        XCTAssertEqual(focus, .identity(badge)); XCTAssertEqual(focus.statusKey, "playBadge.confirmed")
    }
    func testLockedIdentityRemainsLockedDespiteCompletionReceipt() throws {
        let focus = PlayRewardBadgeFocus(target: target, wall: .init(identities: [try identity(unlocked: false)], medals: []))
        XCTAssertEqual(focus.statusKey, "playBadge.locked")
    }
    func testAchievementMatchesButCityTemplateMedalDoesNot() throws {
        let achievement = try medal()
        XCTAssertEqual(PlayRewardBadgeFocus(target: target, wall: .init(identities: [], medals: [achievement])), .achievement(achievement))
        XCTAssertEqual(PlayRewardBadgeFocus(target: target, wall: .init(identities: [], medals: [try medal("medal")])), .missingFromWall)
    }
    func testSameNameDifferentCodeCannotConfirmReceipt() throws {
        XCTAssertEqual(PlayRewardBadgeFocus(target: target, wall: .init(identities: [try identity("OTHER")], medals: [])), .missingFromWall)
    }
    func testMissingAndIncompleteReadbackAreDifferentAndNeitherMeansNotIssued() throws {
        XCTAssertEqual(PlayRewardBadgeFocus(target: target, wall: .init(identities: [], medals: [])), .missingFromWall)
        XCTAssertEqual(PlayRewardBadgeFocus(target: target, wall: .init(identities: [], medals: nil)), .incompleteWall)
        XCTAssertEqual(PlayRewardBadgeFocus(target: target, wall: .init(identities: [try identity()], medals: nil)).statusKey, "playBadge.confirmed")
    }
    func testDuplicateOrConflictingAuthoritativeMatchesDoNotChooseAnEarnedState() throws {
        let one = try identity()
        XCTAssertEqual(PlayRewardBadgeFocus(target: target, wall: .init(identities: [one, one], medals: [])), .ambiguous)
        XCTAssertEqual(PlayRewardBadgeFocus(target: target, wall: .init(identities: [one], medals: [try medal()])), .ambiguous)
    }
    func testReadOnlyStartsWhenActivatedAndCurrentReadPublishes() async throws {
        let reader = RewardBadgeTestReader(); let model = PlayRewardBadgeReadModel(target: target, reader: reader)
        await model.load(); XCTAssertEqual(reader.calls, 0)
        model.activate(); let task = Task { await model.load() }; await reader.waitFor(1)
        reader.complete(0, .success(.init(identities: [try identity()], medals: [])))
        await task.value; XCTAssertEqual(model.focus?.statusKey, "playBadge.confirmed")
    }
    func testNewerRefreshWinsEvenWhenOldReadIgnoresCancellation() async {
        let reader = RewardBadgeTestReader(); let model = PlayRewardBadgeReadModel(target: target, reader: reader); model.activate()
        let old = Task { await model.load() }; await reader.waitFor(1)
        let newer = Task { await model.load() }; await reader.waitFor(2)
        reader.complete(1, .success(.init(identities: [], medals: []))); await newer.value
        reader.complete(0, .success(.init(identities: [], medals: nil))); await old.value
        XCTAssertEqual(model.focus, .missingFromWall)
    }
    func testDisappearRetiresInflightAndQueuedRetryUntilExplicitAppearance() async {
        let reader = RewardBadgeTestReader(); let model = PlayRewardBadgeReadModel(target: target, reader: reader); model.activate()
        let pending = Task { await model.load() }; await reader.waitFor(1)
        model.deactivate(); await model.load(); XCTAssertEqual(reader.calls, 1)
        reader.complete(0, .success(.init(identities: [], medals: []))); await pending.value
        XCTAssertNil(model.focus); XCTAssertFalse(model.isLoading)
        model.activate(); let returned = Task { await model.load() }; await reader.waitFor(2)
        reader.complete(1, .success(.init(identities: [], medals: []))); await returned.value
        XCTAssertEqual(model.focus, .missingFromWall)
    }
    func testSessionEpochApprovalAndAccountChangesHideReadbackWithoutAnotherLoad() async {
        for replacement in [ProfileReadIdentity(accountID: 9, epoch: 1), .init(accountID: 7, epoch: 2), .init(accountID: 7, epoch: 1, approvalRevision: UUID())] {
            let reader = RewardBadgeTestReader(); let model = PlayRewardBadgeReadModel(target: target, reader: reader); model.activate()
            let task = Task { await model.load() }; await reader.waitFor(1)
            reader.complete(0, .success(.init(identities: [], medals: []))); await task.value
            reader.identity = replacement
            XCTAssertNil(model.focus); XCTAssertNil(model.identity)
            await model.load(); XCTAssertEqual(reader.calls, 1, "An old receipt must not read another owner")
        }
    }
    func testLogoutAndRevokedConfigurationRejectLateSuccessAndFailure() async {
        for revokeConfiguration in [true, false] {
            let reader = RewardBadgeTestReader(); let model = PlayRewardBadgeReadModel(target: target, reader: reader); model.activate()
            let task = Task { await model.load() }; await reader.waitFor(1)
            if revokeConfiguration { reader.isConfigured = false } else { reader.identity = nil }
            reader.complete(0, .failure(APIError.unauthorized)); await task.value
            XCTAssertNil(model.focus); XCTAssertFalse(model.failed); XCTAssertFalse(model.isLoading)
        }
    }
    func testQueuedReadRechecksPlayLeaseBeforeInvokingUnchangedProfileReader() async {
        var authorized = true
        let reader = RewardBadgeTestReader()
        // Immediate results make a dispatch regression fail an assertion rather
        // than hang waiting for a response. No transport/test hook is in production.
        reader.immediateWall = .init(identities: [], medals: [])
        let originalIdentity = reader.identity
        let model = PlayRewardBadgeReadModel(target: target, reader: reader, isCurrent: { authorized })
        reader.onConfigurationRead = {
            // load has already captured owner before checking configuration. Return
            // the captured true configuration, but retire the Play lease before
            // the inner reader Task gets an execution turn.
            reader.onConfigurationRead = nil
            authorized = false
        }
        model.activate(); await model.load()
        XCTAssertEqual(reader.identity, originalIdentity, "Profile remains signed in and unchanged")
        XCTAssertEqual(reader.calls, 0, "A retired Play lease must prevent dispatch, not only publication")
        XCTAssertNil(model.focus)
    }
    func testQueuedReadRechecksCapturedProfileAccountAndEpochBeforeDispatch() async {
        for replacement in [ProfileReadIdentity(accountID: 9, epoch: 1), .init(accountID: 7, epoch: 2),
                            .init(accountID: 7, epoch: 1, approvalRevision: UUID())] {
            let reader = RewardBadgeTestReader(); reader.immediateWall = .init(identities: [], medals: [])
            let model = PlayRewardBadgeReadModel(target: target, reader: reader)
            reader.onConfigurationRead = {
                reader.onConfigurationRead = nil
                reader.identity = replacement
            }
            model.activate(); await model.load()
            XCTAssertEqual(reader.calls, 0, "A queued read cannot dispatch for a replacement profile identity")
            XCTAssertNil(model.focus)
        }
    }
    func testQueuedReadRechecksConfigurationBeforeDispatch() async {
        let reader = RewardBadgeTestReader(); reader.immediateWall = .init(identities: [], medals: [])
        let model = PlayRewardBadgeReadModel(target: target, reader: reader)
        reader.onConfigurationRead = {
            reader.onConfigurationRead = nil
            reader.isConfigured = false
        }
        model.activate(); await model.load()
        XCTAssertEqual(reader.calls, 0, "An initially configured read must recheck before dispatch")
        XCTAssertNil(model.focus)
    }
    func testRevokedPlayContextCancelsPublicationAndPreventsAnotherRead() async {
        var authorized = true
        let reader = RewardBadgeTestReader()
        let model = PlayRewardBadgeReadModel(target: target, reader: reader, isCurrent: { authorized })
        model.activate(); let task = Task { await model.load() }; await reader.waitFor(1)
        authorized = false
        reader.complete(0, .success(.init(identities: [], medals: []))); await task.value
        XCTAssertNil(model.identity); XCTAssertNil(model.focus)
        await model.load(); XCTAssertEqual(reader.calls, 1)
    }
    func testCurrentFailureCanRetryWithoutWritingOrClaimingAward() async {
        let reader = RewardBadgeTestReader(); let model = PlayRewardBadgeReadModel(target: target, reader: reader); model.activate()
        let failed = Task { await model.load() }; await reader.waitFor(1)
        reader.complete(0, .failure(APIError.malformedResponse)); await failed.value
        XCTAssertTrue(model.failed); XCTAssertNil(model.focus)
        let retry = Task { await model.load() }; await reader.waitFor(2)
        reader.complete(1, .success(.init(identities: [], medals: nil))); await retry.value
        XCTAssertFalse(model.failed); XCTAssertEqual(model.focus, .incompleteWall)
    }
}

@MainActor private final class RewardBadgeTestReader: ProfileReading {
    private var configured = true
    var onConfigurationRead: (() -> Void)?
    var isConfigured: Bool {
        get { let captured = configured; onConfigurationRead?(); return captured }
        set { configured = newValue }
    }
    var immediateWall: ProfileBadgeWall?
    var identity: ProfileReadIdentity? = .init(accountID: 7, epoch: 1)
    var calls = 0
    private var continuations: [CheckedContinuation<ProfileBadgeWall, Error>?] = []
    func profileBadges() async throws -> ProfileBadgeWall {
        calls += 1
        if let immediateWall { return immediateWall }
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func waitFor(_ count: Int) async { while calls < count { await Task.yield() } }
    func complete(_ index: Int, _ result: Result<ProfileBadgeWall, Error>) {
        continuations[index]?.resume(with: result); continuations[index] = nil
    }
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.invalidRequest }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.invalidRequest }
    func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.invalidRequest }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.invalidRequest }
}
