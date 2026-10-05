import XCTest
@testable import Questify

@MainActor final class TemplateCompositionLifecycleTests: XCTestCase {
    private func session(_ accountID: Int = 901) throws -> TemplateAuthoringSession {
        try .init(accountID: accountID, namespace: "composition-lifecycle-fixture", epoch: 1, authorizationRevision: "member")
    }
    func testChildToggleSurvivesParentLoadAndLocalReopenWithSiblingsIntact() throws {
        let owner = try session()
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        let seed = TemplateAuthoringSyntheticFixtures.compoundDraft()
        coordinator.open(seed: seed)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.setGameEnabled(.coin, false)
        XCTAssertFalse(coordinator.draft.advanced.enabled("coinFlip"))
        model.leave(); model.load(); model.save()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        reopened.open(); reopened.restoreDraft()
        XCTAssertFalse(reopened.draft.advanced.enabled("coinFlip"))
        for (key, value) in seed.advanced.value where key != "coinFlip" {
            XCTAssertEqual(reopened.draft.advanced.value[key], value, key)
        }
        XCTAssertEqual(reopened.draft.advanced.value["coinFlip"]?.object?["heads"], seed.advanced.value["coinFlip"]?.object?["heads"])
    }
    func testNestedCreatorFieldAndRootEditsSurviveParentReappearance() throws {
        let owner = try session()
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        coordinator.open(seed: TemplateAuthoringSyntheticFixtures.compoundDraft())
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.leave()
        model.draft.description = "Child field edit"
        model.draft.advanced.setCreatorEnabled(.compare, true)
        let expected = model.draft
        model.load(); model.save()
        XCTAssertEqual(model.draft, expected); XCTAssertEqual(coordinator.draft, expected)
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        reopened.open(); reopened.restoreDraft(); XCTAssertEqual(reopened.draft, expected)
    }
    func testUnsynchronizedChildDraftDoesNotCrossSameAccountEpoch() throws {
        var owner: TemplateAuthoringSession? = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: TemplateAuthoringSyntheticFixtures.compoundDraft())
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.description = "Previous epoch private draft"
        owner = try .init(accountID: 901, namespace: "composition-lifecycle-fixture", epoch: 2, authorizationRevision: "member")
        model.load()
        XCTAssertNotEqual(model.draft.description, "Previous epoch private draft")
        XCTAssertEqual(model.draft, coordinator.draft)
    }
    func testChildToggleCannotMutateAfterSessionChange() throws {
        var owner: TemplateAuthoringSession? = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: TemplateAuthoringSyntheticFixtures.compoundDraft())
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let previous = model.draft
        owner = try session(902)
        model.setGameEnabled(.coin, false)
        XCTAssertEqual(model.draft, previous)
        model.load()
        XCTAssertFalse(model.draft.advanced.enabled("coinFlip"))
        XCTAssertFalse(model.draft.advanced.enabled("diceRoll"))
    }
    func testChildToggleCannotMutateLockedSubmission() async throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: TemplateAuthoringSyntheticTransport(scenario: .uncertain)), store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: TemplateAuthoringSyntheticFixtures.compoundDraft())
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load(); model.prepare(.publish)
        await model.confirm(try XCTUnwrap(model.review))
        XCTAssertTrue(coordinator.locked)
        let previous = model.draft
        model.setGameEnabled(.coin, false)
        XCTAssertEqual(model.draft, previous)
        XCTAssertEqual(coordinator.draft, previous)
    }
    func testChoiceOptionMediaBindingSurvivesLocalSaveAndParentReappearance() throws {
        let owner = try session(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.title = "Local choice"; model.draft.validationMethod = .choice
        model.draft.questionA = "A text"; model.draft.questionB = "B text"; model.draft.correctAnswer = "B"
        model.optionMedia(.a, .image).wrappedValue = "https://images.example/a.png"
        model.optionMedia(.b, .audio).wrappedValue = "https://audio.example/b.m4a"
        let expected = model.draft
        model.leave(); model.load(); model.save()
        XCTAssertEqual(model.draft, expected)
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        reopened.open(); reopened.restoreDraft(); XCTAssertEqual(reopened.draft, expected)
        XCTAssertFalse(coordinator.canSubmit); XCTAssertNil(coordinator.review)
        XCTAssertNil(try store.pending(session: owner, identity: coordinator.identity))
    }
    func testChoiceOptionMediaBindingCannotChangeUnsupportedRawOrOtherMethods() throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.validationMethod = .choice; model.draft.questionOptionMediaJson = "{future unfinished"
        model.optionMedia(.a, .image).wrappedValue = "replacement"
        XCTAssertEqual(model.draft.questionOptionMediaJson, "{future unfinished")
        model.draft.questionOptionMediaJson = nil
        for method in TemplateAuthoringMethod.allCases where method != .choice {
            model.draft.validationMethod = method
            model.optionMedia(.a, .image).wrappedValue = "replacement"
            XCTAssertNil(model.draft.questionOptionMediaJson)
        }
    }
    func testRetainedChoiceOptionMediaBindingCannotChangeNewAccountDraft() throws {
        var owner: TemplateAuthoringSession? = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.validationMethod = .choice
        let binding = model.optionMedia(.a, .image)
        binding.wrappedValue = "previous-account-image"
        let previous = model.draft
        owner = try session(902)
        XCTAssertEqual(binding.wrappedValue, "")
        binding.wrappedValue = "late-change"
        XCTAssertEqual(model.draft, previous)
        model.load(); XCTAssertNil(model.draft.questionOptionMediaJson)
        model.draft.validationMethod = .choice
        binding.wrappedValue = "stale-binding-after-load"
        XCTAssertNil(model.draft.questionOptionMediaJson)
        model.optionMedia(.b, .audio).wrappedValue = "new-account-audio"
        XCTAssertEqual(model.draft.choiceOptionMedia.text(.b, .audio), "new-account-audio")
        XCTAssertEqual(binding.wrappedValue, "")
    }
    func testChoiceOptionMediaLimitFailureIsVisibleWithoutReplacingDraft() throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.validationMethod = .choice
        let binding = model.optionMedia(.a, .image)
        binding.wrappedValue = "../images/original.png"
        let previous = model.draft
        binding.wrappedValue = String(repeating: "x", count: 501)
        XCTAssertEqual(model.draft, previous)
        XCTAssertEqual(model.optionMediaIssue, "templateAuthor.optionMedia.limit")
        binding.wrappedValue = "asset:replacement"
        XCTAssertNil(model.optionMediaIssue)
        XCTAssertEqual(model.draft.choiceOptionMedia.text(.a, .image), "asset:replacement")
    }
    func testDiscardFencesRetainedChoiceMediaBindingWithinSameSession() throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.validationMethod = .choice
        let binding = model.optionMedia(.a, .image)
        binding.wrappedValue = "original-reference"
        model.discard(); model.draft.validationMethod = .choice
        XCTAssertEqual(binding.wrappedValue, "")
        binding.wrappedValue = "discarded-binding-late-change"
        XCTAssertNil(model.draft.questionOptionMediaJson)
        model.optionMedia(.a, .image).wrappedValue = "current-reference"
        XCTAssertEqual(model.draft.choiceOptionMedia.text(.a, .image), "current-reference")
    }
}
