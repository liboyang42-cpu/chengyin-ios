import XCTest
import SwiftUI
import UIKit
import Combine
@testable import Questify

@MainActor final class TemplateConfiguredRehearsalPreviewTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private let games: [TemplateAdvancedGame] = [.coin, .dice, .react, .countdown, .stopwatch]
    private func setup(visible: Bool = true) throws -> (TemplateAuthoringModel, TemplateConfiguredRehearsalPreviewController, Owner) {
        let owner = Owner(try .init(accountID: 1014, namespace: "configured-preview", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Unsaved configuration"; model.draft.description = "Keep local"
        for game in games { model.draft.advanced.setGameEnabled(game, true) }
        for index in 0..<6 { model.draft.advanced.setFace(index, "My face \(index + 1)") }
        model.draft.advanced.setNested("coinFlip", "heads", "action", "My unsaved action")
        model.draft.advanced.set("countdown", "doneText", .string("My countdown end"))
        let controller = TemplateConfiguredRehearsalPreviewController(model: model)
        if visible { controller.viewAppeared(sceneIsActive: true) }
        return (model, controller, owner)
    }
    func testNewAndInactiveOwnerCannotOpenOrClose() throws {
        let (_, controller, _) = try setup(visible: false); var closes = 0
        let oldOpen = controller.openAction(.coin), oldClose = controller.closeAction { closes += 1 }
        oldOpen(); oldClose(); XCTAssertTrue(controller.path.isEmpty); XCTAssertEqual(closes, 0)
        controller.viewAppeared(sceneIsActive: false); oldOpen(); XCTAssertFalse(controller.isCurrent)
        controller.viewAppeared(sceneIsActive: true); oldOpen(); oldClose()
        XCTAssertTrue(controller.isCurrent); XCTAssertTrue(controller.path.isEmpty); XCTAssertEqual(closes, 0)
    }
    func testAllFiveRoutesUseCurrentUnsavedModelWithoutWriting() throws {
        let (model, controller, _) = try setup(), draft = model.draft, stored = model.coordinator.draft
        XCTAssertNotEqual(draft, stored)
        for game in games {
            XCTAssertTrue(controller.canOpen(game), game.rawValue); controller.openAction(game)()
            let destination = try XCTUnwrap(controller.path.first)
            XCTAssertTrue(controller.currentModel(for: destination) === model)
            XCTAssertEqual(controller.draft, draft); controller.navigationPath.wrappedValue = []
        }
        XCTAssertEqual(model.draft, draft); XCTAssertEqual(model.coordinator.draft, stored)
        XCTAssertNil(model.review); XCTAssertFalse(model.coordinator.canSubmit)
    }
    func testD20MiniAndDeviceGamesKeepTheirExistingBranches() throws {
        let (model, controller, _) = try setup()
        for game in [TemplateAdvancedGame.shake, .quiet, .sort, .match, .classify, .compass, .shout] {
            XCTAssertNil(controller.route(for: game)); controller.openAction(game)(); XCTAssertTrue(controller.path.isEmpty)
        }
        model.draft.advanced.setDiceMode("d20")
        let fresh = TemplateConfiguredRehearsalPreviewController(model: model); fresh.viewAppeared(sceneIsActive: true)
        XCTAssertNil(fresh.route(for: .dice)); XCTAssertFalse(fresh.canOpen(.dice))
    }
    func testMalformedAndDisabledConfigurationCannotOpen() throws {
        for game in games {
            let (model, _, _) = try setup(); model.draft.advanced.value[game.section] = .string("Opaque")
            let fresh = TemplateConfiguredRehearsalPreviewController(model: model); fresh.viewAppeared(sceneIsActive: true)
            fresh.openAction(game)(); XCTAssertTrue(fresh.path.isEmpty)
        }
        let (model, _, _) = try setup(); model.draft.advanced.setGameEnabled(.coin, false)
        let fresh = TemplateConfiguredRehearsalPreviewController(model: model); fresh.viewAppeared(sceneIsActive: true)
        XCTAssertFalse(fresh.canOpen(.coin))
    }
    func testOpenCallbackIsSingleUseAndCannotReplaceCurrentRoute() throws {
        let (_, controller, _) = try setup(), open = controller.openAction(.coin)
        open(); let destination = try XCTUnwrap(controller.path.first)
        open(); controller.openAction(.react)(); XCTAssertEqual(controller.path, [destination])
        controller.navigationPath.wrappedValue = []; open(); XCTAssertTrue(controller.path.isEmpty)
    }
    func testOldPopAndDestinationCannotAffectReopenedSameRoute() throws {
        let (_, controller, _) = try setup(); controller.openAction(.coin)()
        let oldDestination = try XCTUnwrap(controller.path.first), oldPop = controller.navigationPath
        oldPop.wrappedValue = []; controller.openAction(.coin)()
        let current = try XCTUnwrap(controller.path.first); XCTAssertNotEqual(current.id, oldDestination.id)
        oldPop.wrappedValue = []; XCTAssertEqual(controller.path, [current])
        XCTAssertNil(controller.currentModel(for: oldDestination)); XCTAssertNotNil(controller.currentModel(for: current))
    }
    func testPathBindingRejectsForgedPushAndReplacement() throws {
        let (_, controller, _) = try setup()
        controller.navigationPath.wrappedValue = [.init(route: .coin)]; XCTAssertTrue(controller.path.isEmpty)
        controller.openAction(.coin)(); let current = controller.path
        controller.navigationPath.wrappedValue = [.init(route: .reaction)]; XCTAssertEqual(controller.path, current)
    }
    func testHiddenForegroundAndOldCallbacksCannotReviveSnapshot() throws {
        let (model, controller, _) = try setup(), open = controller.openAction(.coin)
        controller.viewDisappeared(); controller.sceneChanged(isActive: true); controller.viewAppeared(sceneIsActive: true)
        open(); controller.openAction(.coin)(); XCTAssertFalse(controller.isCurrent); XCTAssertTrue(controller.path.isEmpty)
        let fresh = TemplateConfiguredRehearsalPreviewController(model: model); fresh.viewAppeared(sceneIsActive: true)
        fresh.openAction(.coin)(); XCTAssertEqual(fresh.path.first?.route, .coin)
        open(); XCTAssertEqual(fresh.path.first?.route, .coin)
    }
    func testBackgroundRetiresRouteAndDoesNotRestartOnForeground() throws {
        let (_, controller, _) = try setup(); controller.openAction(.stopwatch)()
        let destination = try XCTUnwrap(controller.path.first), oldPop = controller.navigationPath
        controller.sceneChanged(isActive: false); controller.sceneChanged(isActive: true)
        oldPop.wrappedValue = []; XCTAssertFalse(controller.isCurrent); XCTAssertTrue(controller.path.isEmpty)
        XCTAssertNil(controller.currentModel(for: destination)); controller.viewAppeared(sceneIsActive: true)
        XCTAssertFalse(controller.canOpen(.stopwatch))
    }
    func testRepeatedAppearanceKeepsCurrentChildAndPopPermit() throws {
        let (_, controller, _) = try setup(); controller.openAction(.coin)()
        let destination = try XCTUnwrap(controller.path.first), pop = controller.navigationPath
        controller.viewAppeared(sceneIsActive: true)
        XCTAssertEqual(controller.path, [destination]); XCTAssertNotNil(controller.currentModel(for: destination))
        pop.wrappedValue = []; XCTAssertTrue(controller.path.isEmpty); XCTAssertTrue(controller.canOpen(.coin))
    }
    func testDraftABAAndBusyABARequireANewSheetOwner() throws {
        for change in ["draft", "busy"] {
            let (model, controller, _) = try setup(), original = model.draft, open = controller.openAction(.coin)
            if change == "draft" { model.draft.title = "Changed"; model.draft = original }
            else { model.busy = true; model.busy = false }
            controller.viewAppeared(sceneIsActive: true); open(); XCTAssertFalse(controller.isCurrent)
            XCTAssertTrue(controller.path.isEmpty); XCTAssertEqual(model.draft, original)
        }
    }
    func testReviewMetadataAndMediaChangesInvalidatePendingRoute() throws {
        for change in ["review", "metadata", "load", "leave"] {
            let (model, controller, _) = try setup(); controller.openAction(.coin)()
            switch change { case "review": model.prepare(.saveDraft); case "metadata": model.changed(); case "load": model.load(); default: model.leave() }
            XCTAssertFalse(controller.isCurrent); XCTAssertFalse(controller.canOpen(.coin))
        }
    }
    func testOwnerChangeCannotExposeOldDraftOrPushANewRoute() throws {
        let (model, controller, owner) = try setup(); controller.openAction(.coin)()
        let destination = try XCTUnwrap(controller.path.first)
        owner.session = try .init(accountID: 1015, namespace: "configured-preview", epoch: 2, authorizationRevision: "member")
        XCTAssertNil(controller.currentModel(for: destination)); XCTAssertFalse(controller.isCurrent)
        model.load(); controller.viewAppeared(sceneIsActive: true); XCTAssertFalse(controller.canOpen(.coin))
    }
    func testCloseIsSingleUseAndOldDismissCannotCloseFreshSheet() throws {
        let (model, controller, _) = try setup(); var closes = 0
        let close = controller.closeAction { closes += 1 }; close(); close(); XCTAssertEqual(closes, 1)
        let fresh = TemplateConfiguredRehearsalPreviewController(model: model); fresh.viewAppeared(sceneIsActive: true)
        close(); XCTAssertEqual(closes, 1); XCTAssertTrue(fresh.isCurrent)
        fresh.closeAction { closes += 1 }(); XCTAssertEqual(closes, 2); XCTAssertFalse(fresh.isCurrent)
    }
    func testOldPathGetterCannotObserveReopenedRouteOrFreshOwner() throws {
        let (model, controller, _) = try setup(); controller.openAction(.coin)()
        let old = controller.navigationPath, original = try XCTUnwrap(old.wrappedValue.first)
        XCTAssertEqual(original.route, .coin)
        old.wrappedValue = []; controller.openAction(.react)()
        let current = try XCTUnwrap(controller.navigationPath.wrappedValue.first)
        XCTAssertEqual(current.route, .reaction); XCTAssertNotEqual(current.id, original.id)
        XCTAssertTrue(old.wrappedValue.isEmpty)
        controller.viewDisappeared(); controller.sceneChanged(isActive: true)
        XCTAssertTrue(old.wrappedValue.isEmpty)
        let fresh = TemplateConfiguredRehearsalPreviewController(model: model); fresh.viewAppeared(sceneIsActive: true)
        fresh.openAction(.coin)(); XCTAssertEqual(fresh.navigationPath.wrappedValue.first?.route, .coin)
        XCTAssertTrue(old.wrappedValue.isEmpty)
    }
    @MainActor private final class ManualScheduler: TemplateTimerRehearsalScheduler {
        var ticks: [@MainActor () -> Void] = []
        func schedule(interval: TimeInterval, tick: @escaping @MainActor () -> Void) -> TemplateTimerCancellation {
            ticks.append(tick); return {}
        }
    }
    func testEnteringAndActingInAllFiveRehearsalsDoesNotPublishParentModel() throws {
        let (model, preview, _) = try setup(), before = model.draft, stored = model.coordinator.draft
        var publications = 0
        let observation = model.objectWillChange.sink { publications += 1 }
        defer { withExtendedLifetime(observation) {} }
        let coin = TemplateCoinFlipRehearsalController(model: model, mode: .currentConfiguration)
        coin.viewAppeared(sceneIsActive: true); coin.showAction()()
        XCTAssertNotNil(coin.visibleState?.result); XCTAssertTrue(preview.isCurrent)
        let d6 = TemplateD6RehearsalController(model: model)
        d6.reload(); d6.sampleAction()()
        XCTAssertNotNil(d6.visibleSample); XCTAssertTrue(preview.isCurrent)
        let countdown = TemplateTimerRehearsalController(model: model, kind: .countdown, mode: .currentConfiguration,
            clock: { 1000 }, scheduler: ManualScheduler())
        countdown.viewAppeared(sceneIsActive: true); countdown.action(.start)()
        XCTAssertEqual(countdown.visibleState?.phase, .running); XCTAssertTrue(preview.isCurrent)
        let stopwatch = TemplateTimerRehearsalController(model: model, kind: .stopwatch, mode: .currentConfiguration,
            clock: { 1000 }, scheduler: ManualScheduler())
        stopwatch.viewAppeared(sceneIsActive: true); stopwatch.action(.start)()
        XCTAssertEqual(stopwatch.visibleState?.phase, .running); XCTAssertTrue(preview.isCurrent)
        let reaction = TemplateReactionRehearsalController(model: model, mode: .currentConfiguration,
            clock: { 1000 }, delayUnit: { 0 }, scheduler: ManualScheduler())
        reaction.viewAppeared(sceneIsActive: true); reaction.action(.tap)()
        XCTAssertEqual(reaction.visibleState?.phase, .waiting); XCTAssertTrue(preview.isCurrent)
        coin.viewDisappeared(); d6.retire(); countdown.viewDisappeared(); stopwatch.viewDisappeared(); reaction.viewDisappeared()
        XCTAssertEqual(publications, 0); XCTAssertTrue(preview.isCurrent)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, stored); XCTAssertNil(model.review)
    }
    private func legacyPreview(choice: Bool = false) throws -> (TemplateAuthoringModel, TemplateConfiguredRehearsalPreviewController, Owner) {
        let (model, _, owner) = try setup(visible: false)
        for game in games { model.draft.advanced.setGameEnabled(game, false) }
        model.draft.finishEnabled = true; model.draft.validationMethod = choice ? .choice : .text
        model.draft.questionName = "Which fruit?"; model.draft.questionAnswer = "Orange、柑橘"
        model.draft.questionA = "Apple"; model.draft.questionB = "Orange"; model.draft.correctAnswer = "B"
        model.draft.hint1 = "An orange fruit"; model.draft.legacyHintsEnabled = true
        let preview = TemplateConfiguredRehearsalPreviewController(model: model); preview.viewAppeared(sceneIsActive: true)
        return (model, preview, owner)
    }
    func testNormalLegacyTextAndChoiceUseActualAnswerHintAndSubmitWithoutParentWrite() throws {
        for choice in [false, true] {
            let (model, preview, _) = try legacyPreview(choice: choice), before = model.draft, stored = model.coordinator.draft
            XCTAssertTrue(preview.offersLegacyQuestion); XCTAssertTrue(preview.canOpenLegacyQuestion)
            preview.openLegacyQuestionAction()()
            let destination = try XCTUnwrap(preview.path.first), routed = try XCTUnwrap(preview.currentModel(for: destination))
            XCTAssertEqual(destination.route, .legacyQuestion); XCTAssertTrue(routed === model)
            var publications = 0; let observation = model.objectWillChange.sink { publications += 1 }
            let editor = TemplateLegacyQuestionRehearsalController(model: routed)
            XCTAssertEqual(editor.question, "Which fruit?")
            if choice { editor.selectAction(.a)() } else { editor.answerInput().wrappedValue = "Apple" }
            editor.submitAction()(); XCTAssertEqual(editor.state, .wrong)
            editor.hintAction()(); XCTAssertEqual(editor.visibleHint, "An orange fruit")
            if choice { editor.selectAction(.b)() } else { editor.answerInput().wrappedValue = " ORANGE " }
            editor.submitAction()(); XCTAssertEqual(editor.state, .completed)
            editor.retire(); XCTAssertEqual(publications, 0); withExtendedLifetime(observation) {}
            XCTAssertTrue(preview.isCurrent); XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, stored)
            XCTAssertFalse(model.coordinator.canSubmit); XCTAssertNil(model.review)
        }
    }
    func testNormalLegacyRouteRejectsAdvancedPrimaryDisabledAndIncompleteQuestions() throws {
        for state in ["advanced", "disabled", "incomplete", "photo", "choice-answer"] {
            let (model, _, _) = try legacyPreview(choice: state == "choice-answer")
            switch state {
            case "advanced": model.draft.advanced.setCreatorEnabled(.qa, true)
            case "disabled": model.draft.finishEnabled = false
            case "photo": model.draft.validationMethod = .photo
            case "choice-answer": model.draft.correctAnswer = "Z"
            default: model.draft.questionAnswer = ""
            }
            let preview = TemplateConfiguredRehearsalPreviewController(model: model); preview.viewAppeared(sceneIsActive: true)
            preview.openLegacyQuestionAction()(); XCTAssertFalse(preview.canOpenLegacyQuestion, state)
            XCTAssertTrue(preview.path.isEmpty, state)
        }
    }
    func testNormalLegacyOldOpenReadPopAndDestinationCannotCrossReopenOrHide() throws {
        let (_, preview, _) = try legacyPreview(), open = preview.openLegacyQuestionAction()
        open(); let old = try XCTUnwrap(preview.path.first), pop = preview.navigationPath
        pop.wrappedValue = []; preview.openLegacyQuestionAction()()
        let current = try XCTUnwrap(preview.path.first); XCTAssertNotEqual(old.id, current.id)
        open(); pop.wrappedValue = []; XCTAssertEqual(preview.path, [current]); XCTAssertTrue(pop.wrappedValue.isEmpty)
        XCTAssertNil(preview.currentModel(for: old)); XCTAssertNotNil(preview.currentModel(for: current))
        preview.viewDisappeared(); preview.sceneChanged(isActive: true)
        preview.openLegacyQuestionAction()(); XCTAssertTrue(preview.path.isEmpty); XCTAssertFalse(preview.canOpenLegacyQuestion)
    }
    func testHostedNormalLegacyPreviewEntryKeepsOwnerAndAllowsBack() async throws {
        let (model, preview, _) = try legacyPreview(choice: true)
        let host = UIHostingController(rootView: TemplateConfiguredRehearsalPreview(controller: preview) {
            TemplateAuthoringPreviewView(draft: model.draft)
        }.environment(\.scenePhase, .active))
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let appeared = await waitUntil { preview.isCurrent }; XCTAssertTrue(appeared)
        preview.openLegacyQuestionAction()(); host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(preview.isCurrent); XCTAssertEqual(preview.path.first?.route, .legacyQuestion)
        preview.navigationPath.wrappedValue = []; host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(preview.isCurrent); XCTAssertTrue(preview.canOpenLegacyQuestion)
    }
    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<100 { if predicate() { return true }; try? await Task.sleep(nanoseconds: 20_000_000) }
        return predicate()
    }
    func testHostedNormalSummaryPushBackKeepsOuterOwnerLive() async throws {
        let (model, controller, _) = try setup(visible: false)
        let host = UIHostingController(rootView: TemplateConfiguredRehearsalPreview(controller: controller) {
            TemplateAuthoringPreviewView(draft: model.draft)
        }.environment(\.scenePhase, .active))
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let appeared = await waitUntil { controller.isCurrent }; XCTAssertTrue(appeared)
        controller.openAction(.coin)(); host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(controller.isCurrent); XCTAssertEqual(controller.path.first?.route, .coin)
        controller.navigationPath.wrappedValue = []; host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(controller.isCurrent); XCTAssertTrue(controller.canOpen(.react))
        controller.openAction(.react)(); XCTAssertEqual(controller.path.first?.route, .reaction)
    }
    func testHostedDetachRetiresAndOldPopCannotCloseNewHostRoute() async throws {
        let (model, old, _) = try setup(visible: false)
        let first = UIHostingController(rootView: TemplateConfiguredRehearsalPreview(controller: old) {
            TemplateAuthoringPreviewView(draft: model.draft)
        }.environment(\.scenePhase, .active))
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = first; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let appeared = await waitUntil { old.isCurrent }; XCTAssertTrue(appeared)
        old.openAction(.coin)(); let pop = old.navigationPath
        let fresh = TemplateConfiguredRehearsalPreviewController(model: model)
        window.rootViewController = UIHostingController(rootView: TemplateConfiguredRehearsalPreview(controller: fresh) {
            TemplateAuthoringPreviewView(draft: model.draft)
        }.environment(\.scenePhase, .active))
        let replaced = await waitUntil { !old.isCurrent && fresh.isCurrent }; XCTAssertTrue(replaced)
        fresh.openAction(.coin)(); let current = fresh.path
        pop.wrappedValue = []; old.openAction(.coin)(); XCTAssertEqual(fresh.path, current)
        XCTAssertFalse(old.isCurrent); XCTAssertTrue(fresh.isCurrent)
    }
}

@MainActor final class TemplateLowHPPresetTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private struct Fixture {
        let model: TemplateAuthoringModel
        let controller: TemplateLowHPPresetController
        let storage: TemplateAuthoringMemoryStorage
        let owner: Owner
    }
    private func validDraft() -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft()
        draft.set("timer", "enabled", .bool(true))
        draft.set("stopwatch", "enabled", .bool(true))
        return draft
    }
    private func fixture(appear: Bool = true) throws -> Fixture {
        let owner = Owner(try .init(accountID: 992, namespace: "low-hp-preset", epoch: 1, authorizationRevision: "member"))
        let storage = TemplateAuthoringMemoryStorage()
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: storage), currentSession: { owner.session }))
        model.load(); model.draft.title = "Current draft"; model.draft.advanced = validDraft(); model.changed()
        let controller = TemplateLowHPPresetController(model: model)
        if appear { controller.viewAppeared(sceneIsActive: true) }
        return .init(model: model, controller: controller, storage: storage, owner: owner)
    }
    private func custom(_ hp: Int, operation: String = "+10") -> TemplateAuthoringJSON {
        .object(["when": .object(["var": .string("sys.hp"), "op": .string("LTE"), "value": .number(Double(hp))]),
                 "relax": .object(["timer.durationSeconds": .string(operation)])])
    }
    func testOptionsUseCurrentEnabledFieldsAndKeepKnownBounds() {
        let value = TemplateLowHPPresetConfiguration(validDraft())
        let ids = Set(value.options.map(\.id))
        XCTAssertTrue(value.isSupported)
        XCTAssertTrue(ids.contains("timer.durationSeconds:+30"))
        XCTAssertTrue(ids.contains("stopwatch.tries:+2")); XCTAssertTrue(ids.contains("stopwatch.tries:=0"))
        XCTAssertTrue(ids.contains("stopwatch.toleranceMs:+300"))
        XCTAssertFalse(ids.contains(where: { $0.hasPrefix("typeIn.") }))
        for option in value.options {
            let result = value.applying(option.id)
            XCTAssertNotNil(result); XCTAssertTrue(result?.rootCreatorIssues.isEmpty == true)
        }
    }
    func testBoundsRemoveInvalidOptionsAndUnlimitedHasNoFurtherAttemptOption() {
        var draft = validDraft(); draft.set("timer", "durationSeconds", .number(86400))
        draft.set("stopwatch", "tries", .number(10)); draft.set("stopwatch", "toleranceMs", .number(5000))
        let ids = Set(TemplateLowHPPresetConfiguration(draft).options.map(\.id))
        XCTAssertFalse(ids.contains("timer.durationSeconds:+30"))
        XCTAssertFalse(ids.contains("stopwatch.tries:+2")); XCTAssertTrue(ids.contains("stopwatch.tries:=0"))
        XCTAssertFalse(ids.contains("stopwatch.toleranceMs:+5000"))
        draft.set("stopwatch", "tries", .number(0))
        XCTAssertFalse(TemplateLowHPPresetConfiguration(draft).options.contains { $0.field == .stopwatchAttempts })
    }
    func testMalformedBooleanCannotExposeOrActivateAnAdjustment() {
        for malformed in [TemplateAuthoringJSON.string("true"), .string("false"), .number(1), .null] {
            var draft = TemplateAdvancedDraft(); draft.set("timer", "enabled", malformed)
            let config = TemplateLowHPPresetConfiguration(draft)
            XCTAssertTrue(config.options.isEmpty)
            XCTAssertNil(config.applying("timer.durationSeconds:+30"))
            XCTAssertEqual(draft.value["timer"]?.object?["enabled"], malformed)
        }
    }
    func testInactiveDeviceCapabilitiesAreNeverOffered() {
        var draft = TemplateAdvancedDraft()
        for section in ["compass", "shout"] { draft.set(section, "enabled", .bool(true)) }
        XCTAssertFalse(TemplateLowHPPresetConfiguration(draft).options.contains { [.compassTolerance, .compassHold, .shout].contains($0.field) })
    }
    func testLowerDurationTimedShakeAndReactionAreDerivedFromCurrentValues() {
        var draft = TemplateAdvancedDraft()
        draft.set("quietHold", "enabled", .bool(true)); draft.set("quietHold", "seconds", .number(15))
        draft.set("reaction", "enabled", .bool(true)); draft.set("ballShake", "enabled", .bool(true))
        let first = Set(TemplateLowHPPresetConfiguration(draft).options.map(\.id))
        XCTAssertTrue(first.contains("quietHold.seconds:-5")); XCTAssertTrue(first.contains("reaction.goalMs:+150"))
        XCTAssertTrue(first.contains("ballShake.goal:-10")); XCTAssertFalse(first.contains("ballShake.seconds:+5"))
        draft.set("ballShake", "timed", .bool(true))
        XCTAssertTrue(TemplateLowHPPresetConfiguration(draft).options.contains { $0.id == "ballShake.seconds:+5" })
        draft.set("quietHold", "seconds", .number(5)); draft.set("ballShake", "seconds", .number(300))
        let last = Set(TemplateLowHPPresetConfiguration(draft).options.map(\.id))
        XCTAssertFalse(last.contains(where: { $0.hasPrefix("quietHold.seconds") })); XCTAssertFalse(last.contains("ballShake.seconds:+5"))
    }
    func testBlankAndMalformedVariantsAreNotSilentlyNormalized() {
        for raw in [TemplateAuthoringJSON.string(""), .object([:]), .null, .bool(false)] {
            var draft = validDraft(); draft.value["variants"] = raw
            let config = TemplateLowHPPresetConfiguration(draft)
            XCTAssertFalse(config.isSupported); XCTAssertNil(config.applying("")); XCTAssertEqual(config.original, draft)
        }
    }
    func testCustomUnknownAndDuplicateLowHPConditionsRemainUntouched() {
        let known = TemplateLowHPPresetConfiguration.Option(field: .timer, operation: "+30").row
        var unknown = known.object!; unknown["future"] = .string("keep")
        let candidates: [[TemplateAuthoringJSON]] = [[custom(3, operation: "+11")], [.object(unknown)], [known, known]]
        for rows in candidates {
            var draft = validDraft(); draft.value["variants"] = .array(rows)
            let config = TemplateLowHPPresetConfiguration(draft)
            XCTAssertFalse(config.isSupported); XCTAssertNil(config.applying(""))
            XCTAssertNil(config.applying("stopwatch.tries:+2")); XCTAssertEqual(config.original.value["variants"], .array(rows))
        }
    }
    func testChangingPresetPreservesCustomRulesAndItsExistingPriority() throws {
        var draft = validDraft()
        let before = custom(1), after = custom(8)
        let managed = TemplateLowHPPresetConfiguration.Option(field: .timer, operation: "+30").row
        draft.value["variants"] = .array([before, managed, after])
        let config = TemplateLowHPPresetConfiguration(draft)
        XCTAssertEqual(config.selectedID, "timer.durationSeconds:+30")
        let next = try XCTUnwrap(config.applying("stopwatch.tries:+2"))
        XCTAssertEqual(next.rootVariants.count, 3)
        XCTAssertEqual(next.rootVariants[0], before); XCTAssertEqual(next.rootVariants[2], after)
        XCTAssertEqual(next.rootVariants[1], TemplateLowHPPresetConfiguration.Option(field: .stopwatchAttempts, operation: "+2").row)
        var expected = draft; expected.value["variants"] = next.value["variants"]
        XCTAssertEqual(next, expected)
    }
    func testDisablingRemovesOnlyExactManagedRule() throws {
        var draft = validDraft(); let other = custom(1)
        draft.value["variants"] = .array([other, TemplateLowHPPresetConfiguration.Option(field: .timer, operation: "+30").row])
        let next = try XCTUnwrap(TemplateLowHPPresetConfiguration(draft).applying(""))
        XCTAssertEqual(next.rootVariants, [other])
        XCTAssertTrue(next.enabled("timer")); XCTAssertEqual(next.text("timer", "durationSeconds"), "300")
    }
    func testRuleLimitCannotDropCustomRulesToMakeRoom() {
        var draft = validDraft(); let rows = (0..<16).map { custom($0 + 4) }
        draft.value["variants"] = .array(rows)
        let config = TemplateLowHPPresetConfiguration(draft)
        XCTAssertNil(config.applying("timer.durationSeconds:+30"))
        XCTAssertEqual(config.original.rootVariants, rows)
    }
    func testPreviewUsesExistingFirstMatchAndDoesNotChangeTheSource() throws {
        var draft = validDraft(); draft.value["variants"] = .array([custom(5, operation: "+10")])
        let original = draft
        let candidate = try XCTUnwrap(TemplateLowHPPresetConfiguration(draft).applying("timer.durationSeconds:+30"))
        let result = try candidate.rehearsedVariant(sample: .init())
        XCTAssertEqual(result.index, 0); XCTAssertEqual(result.draft.text("timer", "durationSeconds"), "310")
        XCTAssertEqual(draft, original); XCTAssertEqual(candidate.text("timer", "durationSeconds"), "300")
    }
    func testSelectionAndCancelDoNotChangeDraftStorageOrReview() throws {
        let f = try fixture(), original = f.model.draft
        f.controller.selectionBinding.wrappedValue = "timer.durationSeconds:+30"
        XCTAssertNotNil(f.controller.preview); XCTAssertTrue(f.controller.canApply)
        XCTAssertEqual(f.model.draft, original); XCTAssertTrue(f.storage.values.isEmpty)
        var dismissals = 0; let cancel = f.controller.cancelAction { dismissals += 1 }; cancel(); cancel()
        XCTAssertEqual(dismissals, 1); XCTAssertEqual(f.model.draft, original)
        XCTAssertTrue(f.storage.values.isEmpty); XCTAssertNil(f.model.review)
    }
    func testExplicitApplyChangesOnlyRulesAndDoesNotSaveOrGrant() throws {
        let f = try fixture(), original = f.model.draft
        f.controller.selectionBinding.wrappedValue = "timer.durationSeconds:+30"
        let apply = f.controller.applyAction(); apply(); apply()
        XCTAssertEqual(f.model.draft.advanced.rootVariants.count, 1)
        var expected = original; expected.advanced.value["variants"] = f.model.draft.advanced.value["variants"]
        XCTAssertEqual(f.model.draft, expected); XCTAssertEqual(f.model.coordinator.draft, expected)
        XCTAssertTrue(f.controller.didApply); XCTAssertFalse(f.controller.canApply)
        XCTAssertTrue(f.storage.values.isEmpty); XCTAssertFalse(f.model.coordinator.canSubmit)
        XCTAssertNil(f.model.review); XCTAssertNil(f.model.coordinator.pending)
    }
    func testOldBindingCannotReadOrWriteTheNextVisibleSelection() throws {
        let f = try fixture(), old = f.controller.selectionBinding
        f.controller.viewDisappeared(); f.controller.viewAppeared(sceneIsActive: true)
        f.controller.selectionBinding.wrappedValue = "timer.durationSeconds:+30"
        XCTAssertEqual(old.wrappedValue, ""); old.wrappedValue = "stopwatch.tries:+2"
        XCTAssertEqual(f.controller.selectionBinding.wrappedValue, "timer.durationSeconds:+30")
    }
    func testOldApplyCancelAndReloadCannotCrossRetirement() throws {
        let f = try fixture(), original = f.model.draft
        var dismissals = 0
        let apply = f.controller.applyAction(), cancel = f.controller.cancelAction { dismissals += 1 }, reload = f.controller.reloadAction()
        f.controller.viewDisappeared(); f.controller.viewAppeared(sceneIsActive: true)
        f.controller.selectionBinding.wrappedValue = "timer.durationSeconds:+30"
        apply(); cancel(); reload()
        XCTAssertEqual(f.model.draft, original); XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(f.controller.selectionBinding.wrappedValue, "timer.durationSeconds:+30")
    }
    func testHiddenSceneAndReloadCannotReactivateTheOwner() throws {
        let f = try fixture()
        f.controller.viewDisappeared(); f.controller.sceneChanged(isActive: false); f.controller.sceneChanged(isActive: true); f.controller.reload()
        XCTAssertFalse(f.controller.isVisible); XCTAssertNil(f.controller.visibleConfiguration)
        f.controller.viewAppeared(sceneIsActive: false); XCTAssertNil(f.controller.visibleConfiguration)
        f.controller.sceneChanged(isActive: true); XCTAssertNotNil(f.controller.visibleConfiguration)
    }
    func testRepeatedVisibleAppearanceKeepsSelectionAndCurrentBinding() throws {
        let f = try fixture(), binding = f.controller.selectionBinding
        binding.wrappedValue = "timer.durationSeconds:+30"
        f.controller.viewAppeared(sceneIsActive: true); f.controller.sceneChanged(isActive: true)
        XCTAssertEqual(binding.wrappedValue, "timer.durationSeconds:+30"); XCTAssertTrue(f.controller.canApply)
    }
    func testOwnerChangeFencesReadsAndActionsBeforeParentNotification() throws {
        let f = try fixture(), original = f.model.draft
        var dismissals = 0
        let binding = f.controller.selectionBinding, apply = f.controller.applyAction()
        let cancel = f.controller.cancelAction { dismissals += 1 }, reload = f.controller.reloadAction()
        binding.wrappedValue = "timer.durationSeconds:+30"
        f.owner.session = try .init(accountID: 993, namespace: "low-hp-preset", epoch: 2, authorizationRevision: "member")
        XCTAssertEqual(binding.wrappedValue, ""); XCTAssertNil(f.controller.preview)
        binding.wrappedValue = "stopwatch.tries:+2"; apply(); cancel(); reload()
        XCTAssertEqual(f.model.draft, original); XCTAssertEqual(dismissals, 0); XCTAssertTrue(f.storage.values.isEmpty)
    }
    func testParentDraftABACannotReviveOldBindingOrApply() throws {
        let f = try fixture(), original = f.model.draft
        let binding = f.controller.selectionBinding, apply = f.controller.applyAction()
        f.model.draft.title = "Different"; f.model.draft = original; f.controller.reload()
        binding.wrappedValue = "timer.durationSeconds:+30"; apply()
        XCTAssertEqual(binding.wrappedValue, ""); XCTAssertEqual(f.model.draft, original)
        XCTAssertFalse(f.controller.canApply); XCTAssertTrue(f.storage.values.isEmpty)
    }
    func testBothLocalesDistinguishApplyFromSaveAndPublishing() {
        for text in TemplateLowHPPresetText.allCases {
            XCTAssertFalse(text.value(Locale(identifier: "en_US")).isEmpty)
            XCTAssertFalse(text.value(Locale(identifier: "zh_CN")).isEmpty)
        }
        XCTAssertEqual(TemplateLowHPPresetText.applied.value(Locale(identifier: "en_US")), "Applied to the draft. Not saved or published.")
        XCTAssertEqual(TemplateLowHPPresetText.applied.value(Locale(identifier: "zh_CN")), "已应用到草稿，尚未保存或发布。")
    }
}
