import XCTest
@testable import QuestifyCore

final class TemplateCompositionTests: XCTestCase {
    private func compound() throws -> TemplateAdvancedDraft { try .init(raw: TemplateAuthoringSyntheticFixtures.compoundAdvanced) }
    func testCoinDiceAndModifiersSerializeTogetherAndReopenWithoutLoss() throws {
        let draft = try compound(), raw = try draft.serialize(), restored = try TemplateAdvancedDraft(raw: raw)
        XCTAssertEqual(restored.enabledGames, [.coin, .dice, .quiet])
        XCTAssertTrue(restored.enabled("timer")); XCTAssertTrue(restored.enabled("timeWindow"))
        XCTAssertEqual(try restored.serialize(), raw)
        XCTAssertEqual(restored.text("coinFlip", "kicker"), draft.text("coinFlip", "kicker"))
        XCTAssertEqual(restored.value["mistakeTier"], .string("easy"))
    }
    func testAllTwelveGamesCanBeConfiguredAndSerializedTogether() throws {
        var draft = try compound()
        for game in TemplateAdvancedGame.allCases {
            draft.setGameEnabled(game, true)
            if game.isReasoning {
                draft.set(game.section, "prompt", .string("Arrange the sample clues"))
                for field in game == .sort ? ["items"] : game == .match ? ["left", "right"] : ["items", "bins"] {
                    for index in draft.rows(game.section, field).indices { draft.setRow(game.section, field, index: index, key: "label", text: "Clue \(field) \(index)") }
                }
            }
        }
        draft.set("compass", "bearing", .number(90)); draft.set("countdown", "doneText", .string("Continue"))
        XCTAssertTrue(draft.issues.isEmpty, draft.issues.joined(separator: ","))
        XCTAssertEqual(try TemplateAdvancedDraft(raw: draft.serialize()).enabledGames.count, 12)
    }
    func testDisablingOneGameRetainsItsFieldsAndEverySibling() throws {
        var draft = try compound(); let before = draft.value
        draft.setGameEnabled(.coin, false)
        for (key, value) in before where key != "coinFlip" { XCTAssertEqual(draft.value[key], value, key) }
        XCTAssertEqual(draft.value["coinFlip"]?.object?["heads"], before["coinFlip"]?.object?["heads"])
        draft.setGameEnabled(.coin, true); XCTAssertEqual(draft.value, before)
    }
    func testEditingAnAddressedGameDoesNotOverwriteAnotherGamesFields() throws {
        var draft = try compound(); let coin = draft.value["coinFlip"], quiet = draft.value["quietHold"]
        draft.setFace(2, "New third action"); draft.setDiceMode("d20")
        draft.set("diceRoll", "successText", .string("Continue")); draft.set("diceRoll", "failText", .string("Retry"))
        XCTAssertEqual(draft.value["coinFlip"], coin); XCTAssertEqual(draft.value["quietHold"], quiet)
        let restored = try TemplateAdvancedDraft(raw: draft.serialize())
        XCTAssertEqual(restored.enabledGames, [.coin, .dice, .quiet]); XCTAssertEqual(restored.diceMode, "d20")
    }
    func testInlineChecksEveryEnabledGameInsteadOfOnlyTheFirst() throws {
        var draft = try compound(); draft.setGameEnabled(.coin, false)
        draft.setGameEnabled(.compass, true); draft.set("compass", "bearing", .number(90)); draft.setPresentation("inline")
        XCTAssertEqual(draft.enabledGames.first, .dice); XCTAssertTrue(draft.presentationRequiresFullscreen)
        XCTAssertTrue(draft.issues.contains("playkitAuthor.validation.fullscreenOnly")); XCTAssertThrowsError(try draft.serialize())
        draft.setPresentation("fullscreen"); XCTAssertTrue(draft.issues.isEmpty)
    }
    func testInlineChecksRemainingCreatorFamiliesAndRecoversAfterDisable() throws {
        var draft = try compound(); draft.setGameEnabled(.coin, false); draft.setPresentation("inline")
        XCTAssertFalse(draft.presentationRequiresFullscreen); XCTAssertTrue(draft.issues.isEmpty)
        draft.setCreatorEnabled(.steps, true); XCTAssertTrue(draft.presentationRequiresFullscreen); XCTAssertThrowsError(try draft.serialize())
        draft.setCreatorEnabled(.steps, false); XCTAssertTrue(draft.issues.isEmpty)
    }
    func testTimerCanCoexistWithCoinAndDiceWithoutDisablingEither() throws {
        var draft = try compound(); draft.set("timer", "durationSeconds", .number(60))
        XCTAssertTrue(draft.issues.isEmpty); let restored = try TemplateAdvancedDraft(raw: draft.serialize())
        XCTAssertEqual(restored.value["timer"]?.object?["durationSeconds"], .number(60)); XCTAssertTrue(restored.enabled("coinFlip")); XCTAssertTrue(restored.enabled("diceRoll"))
    }
    func testOneAdaptiveRuleCanRelaxSeveralEnabledFamilies() throws {
        var draft = try compound(); draft.setGameEnabled(.react, true)
        draft.appendRootVariant(); draft.setRootVariant(0, key: "relax", entry: .object(["timer.durationSeconds": .string("+30"), "quietHold.seconds": .string("-5"), "reaction.goalMs": .string("+100")]))
        XCTAssertTrue(draft.rootCreatorIssues.isEmpty)
        let result = try draft.rehearsedVariant(sample: .init())
        XCTAssertEqual(result.index, 0); XCTAssertEqual(result.draft.value["timer"]?.object?["durationSeconds"], .number(330))
        XCTAssertEqual(result.draft.value["quietHold"]?.object?["seconds"], .number(10)); XCTAssertEqual(result.draft.value["reaction"]?.object?["goalMs"], .number(420))
        XCTAssertTrue(result.draft.enabled("coinFlip")); XCTAssertTrue(result.draft.enabled("diceRoll"))
        XCTAssertEqual(try TemplateAdvancedDraft(raw: draft.serialize()).rootVariants, draft.rootVariants)
    }
    func testDisablingAnAdaptiveOperandPreservesRuleButBlocksSubmission() throws {
        var draft = try compound(); draft.appendRootVariant(); draft.setRootVariant(0, key: "relax", entry: .object(["quietHold.seconds": .string("-5")]))
        let variants = draft.rootVariants; draft.setGameEnabled(.quiet, false)
        XCTAssertEqual(draft.rootVariants, variants); XCTAssertThrowsError(try draft.serialize())
        draft.setGameEnabled(.quiet, true); XCTAssertTrue(draft.rootCreatorIssues.isEmpty)
    }
    func testUnknownRootAndGameFieldsSurviveEnablementAndSnapshotButFailClosed() throws {
        var draft = try compound(); draft.value["future"] = .array([.string("retain")]); draft.set("diceRoll", "futureRule", .string("retain"))
        let coin = draft.value["coinFlip"]; draft.setGameEnabled(.quiet, false); draft.setGameEnabled(.react, true)
        let restored = try JSONDecoder().decode(TemplateAdvancedDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored.value["future"], draft.value["future"]); XCTAssertEqual(restored.value["diceRoll"], draft.value["diceRoll"]); XCTAssertEqual(restored.value["coinFlip"], coin)
        XCTAssertThrowsError(try restored.serialize())
    }
    func testReviewLabelsCoverEveryEnabledFamilyAndExcludeDisabledOnes() throws {
        var draft = try compound(); XCTAssertEqual(draft.enabledConfigurationLabelKeys, ["templateAuthor.timer", "templateAuthor.game.coin", "templateAuthor.game.dice", "templateAuthor.game.quiet", "creator.family.timeWindow"])
        draft.setGameEnabled(.coin, false); XCTAssertFalse(draft.enabledConfigurationLabelKeys.contains("templateAuthor.game.coin")); XCTAssertTrue(draft.enabledConfigurationLabelKeys.contains("templateAuthor.game.dice"))
    }
    func testRoleViewsAndRootRulesSurviveGameTogglesAndReserialization() throws {
        var draft = try compound(); draft.setRoleViewsEnabled(true); draft.setGameEnabled(.react, true); draft.setGameEnabled(.quiet, false)
        let roles = draft.value["roleViews"], restored = try TemplateAdvancedDraft(raw: draft.serialize())
        XCTAssertEqual(restored.value["roleViews"], roles); XCTAssertEqual(restored.value["mistakeTier"], .string("easy")); XCTAssertEqual(restored.enabledGames, [.coin, .dice, .react])
    }
}

@MainActor final class TemplateCompositionReviewTests: XCTestCase {
    private var session: TemplateAuthoringSession? { try? .init(accountID: 901, namespace: "compound-fixture", epoch: 1, authorizationRevision: "member") }
    func testLocalReopenAndFrozenReviewRetainCompoundPayloadAndUsageLocation() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { self.session })
        var draft = TemplateAuthoringSyntheticFixtures.compoundDraft(); draft.usageLocation = "Synthetic courtyard"; coordinator.open(seed: draft); coordinator.saveLocal()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { self.session }); reopened.open(); reopened.restoreDraft()
        XCTAssertEqual(reopened.draft.advanced.value, draft.advanced.value); XCTAssertEqual(reopened.draft.usageLocation, draft.usageLocation)
        reopened.prepare(.publish); let review = try XCTUnwrap(reopened.review)
        guard case .json(let payload) = review.request.body else { return XCTFail("Expected reviewed JSON") }
        let restored = try TemplateAdvancedDraft(raw: XCTUnwrap(payload["advancedConfigJson"]?.string))
        XCTAssertEqual(restored.enabledGames, [.coin, .dice, .quiet]); XCTAssertEqual(payload["usageLocation"], .string("Synthetic courtyard")); XCTAssertEqual(review.draft, draft)
    }
    func testChangingOneEnabledGameInvalidatesOldReviewWithoutSending() async throws {
        let transport = TemplateAuthoringSyntheticTransport(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: transport), store: store, currentSession: { self.session })
        coordinator.open(seed: TemplateAuthoringSyntheticFixtures.compoundDraft()); coordinator.prepare(.publish); let review = try XCTUnwrap(coordinator.review)
        var next = coordinator.draft; next.advanced.setGameEnabled(.coin, false); coordinator.change(next); await coordinator.confirm(review)
        XCTAssertNil(coordinator.review); XCTAssertTrue(transport.requests.isEmpty); XCTAssertTrue(coordinator.draft.advanced.enabled("diceRoll"))
    }
}
