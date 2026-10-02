import XCTest
@testable import QuestifyCore

final class TemplateAuthoringTests: XCTestCase {
    func testDormantBuilderUsesSourceJSONAndAuthorization() throws {
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.com")))
        let descriptor = try TemplateAuthoringContract.request(.init(title: "Sample"), intent: .saveDraft)
        let request = try TemplateAuthoringWireRequestBuilder.make(descriptor, configuration: config, token: "synthetic-token")
        XCTAssertEqual(request.url?.path, "/api/template/draft"); XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
    }
    func testDormantBuilderUsesMultipartIncludingBlankFields() throws {
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.com")))
        let request = try TemplateAuthoringWireRequestBuilder.make(TemplateAuthoringContract.listMine(), configuration: config, token: "synthetic-token", boundary: "TEST")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"category_id\"\r\n\r\n\r\n"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=TEST")
    }
    func testDormantBuilderRejectsUnverifiedPathAndBoundaryInjection() throws {
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.com")))
        XCTAssertThrowsError(try TemplateAuthoringWireRequestBuilder.make(.init(path: "/api/topic/delete", body: .form([:]), mutates: true), configuration: config, token: "synthetic-token"))
        XCTAssertThrowsError(try TemplateAuthoringWireRequestBuilder.make(TemplateAuthoringContract.listMine(), configuration: config, token: "synthetic-token", boundary: "bad\r\n"))
    }
    func testDecodedPlayIdentityRejectsInvalidValues() { XCTAssertThrowsError(try JSONDecoder().decode(AuthoringPlayTemplateID.self, from: Data("-1".utf8))) }
    func testPlayIdentityRejectsInvalidValues() { XCTAssertNil(AuthoringPlayTemplateID(rawValue: 0)); XCTAssertNil(AuthoringPlayTemplateID(rawValue: -1)) }
    func testDraftRequiresOnlyTitleForSave() throws {
        var d = TemplateAuthoringDraft(); XCTAssertFalse(d.canSave); d.title = "  Sample  "
        let r = try TemplateAuthoringContract.request(d, intent: .saveDraft)
        XCTAssertEqual(r.path, "/api/template/draft"); XCTAssertEqual(r.method, "POST")
        guard case .json(let payload) = r.body else { return XCTFail("JSON required") }
        XCTAssertEqual(payload["title"], .string("Sample")); XCTAssertFalse(d.publishIssues.isEmpty)
    }
    func testPublishHasIndependentValidation() { XCTAssertThrowsError(try TemplateAuthoringContract.request(.init(title: "Sample"), intent: .publish)) }
    func testDescriptionUsesDartUTF16Length() { var d = TemplateAuthoringDraft(title: "x"); d.description = String(repeating: "🎲", count: 16); XCTAssertTrue(d.publishIssues.contains("templateAuthor.validation.descriptionLength")) }
    func testAuthPrecedesBodyDecode() { XCTAssertThrowsError(try TemplateAuthoringContract.requireSuccess(Data(), httpStatus: 401)) { XCTAssertEqual($0 as? APIError, .unauthorized) } }
    func testMalformedSuccessIsNotAccepted() { XCTAssertThrowsError(try TemplateAuthoringContract.requireSuccess(Data("{}".utf8), httpStatus: 200)) }
    func testBodyAuthPrecedesOptionalMessageType() { XCTAssertThrowsError(try TemplateAuthoringContract.requireSuccess(Data(#"{"code":401,"msg":{}}"#.utf8), httpStatus: 200)) { XCTAssertEqual($0 as? APIError, .unauthorized) } }
    func testListContractExactFields() {
        XCTAssertEqual(TemplateAuthoringContract.listMine(), .init(path: "/api/template/my-list", body: .form(["is_quote": "", "keyword": "", "category_id": "", "pageNum": "1", "pageSize": "100"]), mutates: false))
    }
    func testLibraryToggleUsesTemplateIDAndInvertsKnownOneOnly() throws {
        let id = try XCTUnwrap(AuthoringPlayTemplateID(rawValue: 42))
        XCTAssertEqual(TemplateAuthoringContract.libraryStatus(id: id, current: 1).body, .form(["template_id": "42", "publish_status": "0"]))
        XCTAssertEqual(TemplateAuthoringContract.libraryStatus(id: id, current: nil).body, .form(["template_id": "42", "publish_status": "1"]))
    }
    func testDeleteDoesNotUseTopicOrActivityID() throws {
        XCTAssertEqual(TemplateAuthoringContract.remove(id: try XCTUnwrap(.init(rawValue: 7))).body, .form(["template_id": "7"]))
    }
    func testModuleTogglesOmitDisabledFields() throws {
        var d = TemplateAuthoringDraft(title: "x"); d.finishEnabled = false; d.rewardEnabled = false; d.storyEnabled = false; d.voiceEnabled = false
        d.questionAnswer = "secret"; d.feedbackText = "reward"; d.storyText = "story"; d.audioUrl = "asset"
        let p = try TemplateAuthoringContract.payload(d)
        for key in ["finishEnabled", "rewardEnabled", "storyEnabled", "voiceEnabled", "validationMethod", "questionAnswer", "feedbackText", "storyText", "audioUrl"] { XCTAssertNil(p[key], key) }
    }
    func testQuestionChoiceAndPhotoPayloadsRemainDistinct() throws {
        var d = TemplateAuthoringDraft(title: "x"); d.questionAnswer = "text"; d.questionA = "A"; d.photoRequireDesc = "photo"
        d.validationMethod = .text; var p = try TemplateAuthoringContract.payload(d); XCTAssertNotNil(p["questionAnswer"]); XCTAssertNil(p["questionA"])
        d.validationMethod = .choice; p = try TemplateAuthoringContract.payload(d); XCTAssertNil(p["questionAnswer"]); XCTAssertNotNil(p["questionA"])
        d.validationMethod = .photo; p = try TemplateAuthoringContract.payload(d); XCTAssertNotNil(p["photoRequireDesc"]); XCTAssertNil(p["questionA"])
    }
    func testGPSHintsUseCodeFive() throws {
        var d = TemplateAuthoringDraft(title: "x"); d.validationMethod = .gps; d.hint1 = "Look nearby"
        let p = try TemplateAuthoringContract.payload(d); XCTAssertEqual(p["validationMethod"], .number(5)); XCTAssertEqual(p["hint1"], .string("Look nearby"))
    }
    func testOriginalTemplateAttributionSurvives() throws {
        var d = TemplateAuthoringDraft(title: "x"); d.originalTemplateID = .init(rawValue: 15)
        XCTAssertEqual(try TemplateAuthoringContract.payload(d)["originalTemplateId"], .number(15))
    }
    func testAdoptionUsesPublicFieldsWithoutAnswersOrServerID() throws {
        let row = try JSONDecoder().decode(DiscoveryPlayTemplate.self, from: Data(#"{"id":9,"title":"Public","description":"Read","players":"2-6","duration":10,"questionName":"public question","validationMethod":1,"categoryId":4}"#.utf8))
        let d = try TemplateAuthoringDraft.adopt(row)
        XCTAssertEqual(d.originalTemplateID?.rawValue, 9); XCTAssertNil(d.id); XCTAssertNil(d.questionName); XCTAssertNil(d.questionAnswer); XCTAssertNil(d.correctAnswer)
    }
    func testRewardRequiresAtLeastOneAndCompleteMedal() {
        var d = TemplateAuthoringDraft(title: "x"); XCTAssertTrue(d.publishIssues.contains("templateAuthor.validation.reward"))
        d.medalImg = "image"; XCTAssertTrue(d.publishIssues.contains("templateAuthor.validation.medal")); d.medalName = "Name"; XCTAssertFalse(d.publishIssues.contains("templateAuthor.validation.medal"))
    }
    func testRemovedCorrectChoiceBlocksPublish() {
        var d = TemplateAuthoringDraft(title: "x"); d.validationMethod = .choice; d.questionName = "Q"; d.questionA = "A"; d.questionB = "B"; d.correctAnswer = "D"
        XCTAssertTrue(d.publishIssues.contains("templateAuthor.validation.correctAnswer"))
    }
    func testStoryWireContainsNoLocalID() throws {
        var d = TemplateAuthoringDraft(); try d.setStory([.init(), .init(text: "Scene", tag: "Open", imgs: ["image"])])
        let raw = try XCTUnwrap(d.storyJson); XCTAssertFalse(raw.contains("\"id\"")); XCTAssertEqual(try d.storyBeats().count, 1)
    }
    func testMalformedStoryIsNotSilentlyOverwritten() { var d = TemplateAuthoringDraft(); d.storyJson = "{}"; XCTAssertThrowsError(try d.storyBeats()) }
    func testEnablingGamesPreservesOtherGamesAndTimer() {
        var a = TemplateAdvancedDraft(); a.set("timer", "enabled", .bool(true)); a.setGameEnabled(.react, true); a.setGameEnabled(.quiet, true)
        XCTAssertTrue(a.enabled("reaction")); XCTAssertTrue(a.enabled("quietHold")); XCTAssertTrue(a.enabled("timer"))
    }
    func testClearGameRetainsModifiers() { var a = TemplateAdvancedDraft(); a.set("timer", "enabled", .bool(true)); a.setGameEnabled(.react, true); a.setGameEnabled(.react, false); XCTAssertTrue(a.enabledGames.isEmpty); XCTAssertTrue(a.enabled("timer")) }
    func testDefaultAdvancedSerializesEmpty() throws { XCTAssertEqual(try TemplateAdvancedDraft().serialize(), "") }
    func testSevenFlutterGamesAndFiveSourceBackedMiniAdditions() { XCTAssertEqual(Set(TemplateAdvancedGame.allCases.map(\.rawValue)), Set(["coin", "dice", "react", "shake", "quiet", "countdown", "stopwatch", "sort", "match", "classify", "compass", "shout"])) }
    func testCoinRequiresBothActions() { var a = TemplateAdvancedDraft(); a.setGameEnabled(.coin, true); XCTAssertTrue(a.issues.contains("templateAuthor.validation.coinAction")); a.setNested("coinFlip", "heads", "action", "Look up"); a.setNested("coinFlip", "tails", "action", "Look down"); XCTAssertTrue(a.issues.isEmpty) }
    func testDiceRequiresSixNonemptyFaces() { var a = TemplateAdvancedDraft(); a.setGameEnabled(.dice, true); XCTAssertFalse(a.issues.isEmpty); for i in 0..<6 { a.setFace(i, "Action \(i)") }; XCTAssertTrue(a.issues.isEmpty) }
    func testReactionRangeBounds() { var a = TemplateAdvancedDraft(); a.setGameEnabled(.react, true); a.set("reaction", "goalMs", .number(119)); XCTAssertFalse(a.issues.isEmpty); a.set("reaction", "goalMs", .number(120)); XCTAssertTrue(a.issues.isEmpty) }
    func testUntimedBallOmitsSecondsOnlyDuringSerialization() throws {
        var a = TemplateAdvancedDraft(); a.setGameEnabled(.shake, true); let p = try JSONDecoder().decode([String: TemplateAuthoringJSON].self, from: Data(a.serialize().utf8))
        XCTAssertNil(p["ballShake"]?.object?["seconds"]); XCTAssertNotNil(a.value["ballShake"]?.object?["seconds"])
    }
    func testTimerBoundsAndIntegerRequirement() { var a = TemplateAdvancedDraft(); a.set("timer", "enabled", .bool(true)); a.set("timer", "durationSeconds", .number(10.5)); XCTAssertFalse(a.issues.isEmpty); a.set("timer", "durationSeconds", .number(86400)); XCTAssertTrue(a.issues.isEmpty) }
    func testCountdownRequiresCompletionText() { var a = TemplateAdvancedDraft(); a.setGameEnabled(.countdown, true); XCTAssertFalse(a.issues.isEmpty); a.set("countdown", "doneText", .string("Done")); XCTAssertTrue(a.issues.isEmpty) }
    func testStopwatchZeroTriesMeansUnlimited() { var a = TemplateAdvancedDraft(); a.setGameEnabled(.stopwatch, true); a.set("stopwatch", "tries", .number(0)); XCTAssertTrue(a.issues.isEmpty) }
    func testUnknownAdvancedPreservedButBlocksSubmission() throws { var a = TemplateAdvancedDraft(); a.value["future"] = .object(["secret": .string("keep")]); XCTAssertThrowsError(try a.serialize()); XCTAssertEqual(a.value["future"]?.object?["secret"], .string("keep")) }
    func testBranchIsNowStructuredAndSupported() { var a = TemplateAdvancedDraft(); a.setCreatorEnabled(.branch, true); XCTAssertTrue(a.creatorIssues(.branch).isEmpty); XCTAssertFalse(a.issues.contains("templateAuthor.validation.advancedUnsupported")) }
    func testBadAdvancedJSONAndUnknownSchemaReject() { XCTAssertThrowsError(try TemplateAdvancedDraft(raw: "bad")); XCTAssertThrowsError(try TemplateAdvancedDraft(raw: #"{"schemaVersion":2}"#)) }
    func testSecretStrippedBlindAnswerNotDefaultedToA() throws { let a = try TemplateAdvancedDraft(raw: #"{"blindTaste":{"enabled":true}}"#); XCTAssertEqual(a.text("blindTaste", "answerKey"), "") }
    func testDuplicateAndModerationRejectionsAreDistinct() {
        XCTAssertTrue(TemplateAuthoringRejection(message: "名称已存在", code: 500).duplicateName)
        XCTAssertTrue(TemplateAuthoringRejection(message: "含有敏感词", code: 500).contentRejected)
        XCTAssertFalse(TemplateAuthoringRejection(message: "网络稍后重试", code: 500).contentRejected)
    }
    func testDictionaryFallbackIsComplete() { for key in ["app_template_players", "app_template_duration", "app_template_difficulty"] { XCTAssertFalse(TemplateAuthoringDictionaryOption.fallback(key).isEmpty) } }
    func testDictionaryRejectsUnknownType() { XCTAssertThrowsError(try TemplateAuthoringContract.dictionary("unverified")) }
    func testPrefabThirteenScenesTerminateAtFlow() { var s = PrefabPreviewState(); for _ in 0..<30 { s.advance() }; XCTAssertEqual(s.scene, .flow); XCTAssertEqual(PrefabPreviewScene.allCases.count, 13) }
    func testPrefabCheckClampsTwoDiceAndPadsOne() { let result = PrefabPreviewState().check(skill: "rule", dc: 9, rolls: [99]); XCTAssertEqual(result.dice, [6, 1]); XCTAssertEqual(result.score, 9); XCTAssertTrue(result.ok) }
    func testPrefabObserveTrimsAndDeduplicatesAcrossLocations() { var s = PrefabPreviewState(); s.observe(where: "walk", text: "  Tree  "); s.observe(where: "hall", text: "Tree"); s.observe(where: "hall", text: "  "); XCTAssertEqual(s.observations.count, 1) }
    func testPrefabGainBoundsAndThoughtUniqueness() { var s = PrefabPreviewState(); s.gain(hp: -50, luck: 50, dreams: -2, thought: "One"); s.gain(thought: "One"); XCTAssertEqual(s.hp, 0); XCTAssertEqual(s.luck, 4); XCTAssertEqual(s.dreams, 0); XCTAssertEqual(s.thoughts, ["One"]) }
    func testPrefabSourceClassificationRules() { var s = PrefabPreviewState(); var p = PrefabPreviewProfile(); p.place = "北京"; p.dream = "程序员"; s.applyProfile(p); XCTAssertEqual(s.skills["rule"], 3); XCTAssertEqual(s.skills["precision"], 2) }
    func testPrefabV1RestoresSceneResetsStep() { let s = PrefabPreviewState.restore(Data(#"{"version":1,"scene":"work","step":9}"#.utf8)); XCTAssertEqual(s.scene, .work); XCTAssertEqual(s.step, 0) }
    func testPrefabUnknownVersionOrSceneResets() { XCTAssertEqual(PrefabPreviewState.restore(Data(#"{"version":3,"scene":"work"}"#.utf8)), .init()); XCTAssertEqual(PrefabPreviewState.restore(Data(#"{"version":2,"scene":"unknown"}"#.utf8)), .init()) }
    func testPrefabTopicNameMatchesSourceExactShape() { XCTAssertTrue(PrefabPreviewState.isPrefabTopic(name: "预制人生 · 城市")); XCTAssertFalse(PrefabPreviewState.isPrefabTopic(name: "我的预制人生")); XCTAssertFalse(PrefabPreviewState.isPrefabTopic(name: "预制人生2")) }
    func testPrefabStorageDisambiguatesActivityTopicPreview() { XCTAssertNotEqual(PrefabPreviewIdentity.activity(1).storageComponent, PrefabPreviewIdentity.topic(1).storageComponent) }
}

#if DEBUG
@MainActor final class TemplateAuthoringSafetyTests: XCTestCase {
    private var session: TemplateAuthoringSession? = try? .init(accountID: 1, namespace: "test-CN", epoch: 1, authorizationRevision: "member-1")
    private func make(_ storage: TemplateAuthoringMemoryStorage? = nil, _ transport: TemplateAuthoringSyntheticTransport? = nil) -> (TemplateAuthoringCoordinator, TemplateAuthoringLocalStore, TemplateAuthoringSyntheticTransport) {
        let storage = storage ?? TemplateAuthoringMemoryStorage(), transport = transport ?? TemplateAuthoringSyntheticTransport()
        let store = TemplateAuthoringLocalStore(storage: storage)
        let c = TemplateAuthoringCoordinator(adapter: .init(transport: transport), store: store, currentSession: { [weak self] in self?.session }); c.open(seed: TemplateAuthoringSyntheticFixtures.draft()); return (c, store, transport)
    }
    func testProductionAdapterNeverSends() async { let a = TemplateAuthoringAdapter(); XCTAssertFalse(a.canSimulate); let result = await a.submit(TemplateAuthoringContract.listMine()); XCTAssertEqual(result, .notSent) }
    func testReviewMutationInvalidatesConfirmation() async throws { let (c, _, t) = make(); c.prepare(.publish); let r = try XCTUnwrap(c.review); var d = c.draft; d.title = "new"; c.change(d); await c.confirm(r); XCTAssertTrue(t.requests.isEmpty) }
    func testCancelledReviewCannotSubmit() async throws { let (c, _, t) = make(); c.prepare(.publish); let r = try XCTUnwrap(c.review); c.cancelReview(); await c.confirm(r); XCTAssertTrue(t.requests.isEmpty) }
    func testNavigationInvalidatesReview() async throws { let (c, _, t) = make(); c.prepare(.publish); let r = try XCTUnwrap(c.review); c.leaveScreen(); await c.confirm(r); XCTAssertTrue(t.requests.isEmpty) }
    func testRoleRevisionInvalidatesReview() async throws { let (c, _, t) = make(); c.prepare(.publish); let r = try XCTUnwrap(c.review); session = try .init(accountID: 1, namespace: "test-CN", epoch: 1, authorizationRevision: "role-2"); await c.confirm(r); XCTAssertTrue(t.requests.isEmpty) }
    func testEpochChangeInvalidatesReview() async throws { let (c, _, t) = make(); c.prepare(.publish); let r = try XCTUnwrap(c.review); session = try .init(accountID: 1, namespace: "test-CN", epoch: 2, authorizationRevision: "member-1"); await c.confirm(r); XCTAssertTrue(t.requests.isEmpty) }
    func testUnknownOutcomePersistsAndReopenCannotRetry() async throws {
        let storage = TemplateAuthoringMemoryStorage(), transport = TemplateAuthoringSyntheticTransport(scenario: .uncertain)
        let (c, _, _) = make(storage, transport); c.prepare(.publish); await c.confirm(try XCTUnwrap(c.review)); XCTAssertEqual(c.state, .uncertain)
        let (reopened, _, _) = make(storage, transport); XCTAssertEqual(reopened.state, .uncertain); reopened.prepare(.publish); XCTAssertNil(reopened.review); XCTAssertEqual(transport.requests.count, 1)
    }
    func testUnknownOutcomeCannotDiscardLocalLock() async throws { let (c, _, _) = make(TemplateAuthoringMemoryStorage(), TemplateAuthoringSyntheticTransport(scenario: .uncertain)); c.prepare(.publish); await c.confirm(try XCTUnwrap(c.review)); c.discardLocal(); XCTAssertNotNil(c.pending); XCTAssertTrue(c.locked) }
    func testSuccessfulSimulationIsTerminalAcrossReopen() async throws { let storage = TemplateAuthoringMemoryStorage(); let (c, _, _) = make(storage); c.prepare(.publish); await c.confirm(try XCTUnwrap(c.review)); let (reopened, _, _) = make(storage); XCTAssertEqual(reopened.state, .simulated); XCTAssertTrue(reopened.locked) }
    func testStorageFailurePreventsSend() async throws { let s = TemplateAuthoringMemoryStorage(); let (c, _, t) = make(s); c.prepare(.publish); let r = try XCTUnwrap(c.review); s.failWrites = true; await c.confirm(r); XCTAssertTrue(t.requests.isEmpty); XCTAssertEqual(c.state, .blocked) }
    func testSameOwnerReauthFindsDraftButOtherAccountDoesNot() throws {
        let storage = TemplateAuthoringMemoryStorage(), store = TemplateAuthoringLocalStore(storage: storage), identity = TemplateAuthoringIdentity()
        let first = try XCTUnwrap(session); try store.save(.init(title: "Private"), session: first, identity: identity)
        let second = try TemplateAuthoringSession(accountID: 1, namespace: "test-CN", epoch: 2, authorizationRevision: "member-2")
        guard case .ready = store.load(session: second, identity: identity) else { return XCTFail("Expected same-owner restore") }
        let other = try TemplateAuthoringSession(accountID: 2, namespace: "test-CN", epoch: 1, authorizationRevision: "member-1")
        XCTAssertEqual(store.load(session: other, identity: identity), .missing)
    }
    func testRegionalNamespacesIsolateDrafts() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity()
        try store.save(.init(title: "CN"), session: XCTUnwrap(session), identity: identity)
        let us = try TemplateAuthoringSession(accountID: 1, namespace: "test-US", epoch: 1, authorizationRevision: "member-1")
        XCTAssertEqual(store.load(session: us, identity: identity), .missing)
    }
    func testDuplicateResponseClearsPendingAndAllowsNameCorrection() async throws { let (c, _, _) = make(TemplateAuthoringMemoryStorage(), TemplateAuthoringSyntheticTransport(scenario: .duplicate)); c.prepare(.publish); await c.confirm(try XCTUnwrap(c.review)); XCTAssertNil(c.pending); XCTAssertEqual(c.messageKey, "templateAuthor.duplicateName") }
    func testSignoutDuringSubmitCannotDisplayStaleSuccess() async throws {
        let t = TemplateAuthoringSyntheticTransport(); t.delayNanoseconds = 40_000_000
        let (c, store, _) = make(TemplateAuthoringMemoryStorage(), t); c.prepare(.publish); let r = try XCTUnwrap(c.review); let identity = c.identity; let captured = try XCTUnwrap(session)
        let task = Task { await c.confirm(r) }; try await Task.sleep(nanoseconds: 10_000_000); session = nil; c.synchronizeSession(); await task.value
        XCTAssertNotEqual(c.state, .simulated); XCTAssertNotNil(try store.pending(session: captured, identity: identity)); XCTAssertEqual(c.draft.title, "")
    }
    func testPrefabSecureStoreIsAccountScoped() throws {
        let storage = TemplateAuthoringMemoryStorage(), store = PrefabPreviewStore(storage: storage), identity = PrefabPreviewIdentity.local(UUID())
        var state = PrefabPreviewState(); state.note = "Private"; try store.save(state, identity: identity, session: XCTUnwrap(session))
        let other = try TemplateAuthoringSession(accountID: 2, namespace: "test-CN", epoch: 1, authorizationRevision: "member-1"); XCTAssertNil(try store.load(identity: identity, session: other))
    }
}
#endif
