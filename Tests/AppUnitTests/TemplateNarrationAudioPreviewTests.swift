import XCTest
@testable import Questify

@MainActor final class TemplateNarrationAudioPreviewTests: XCTestCase {
    private final class Owner {
        var value: TemplateAuthoringSession?
        init(_ value: TemplateAuthoringSession) { self.value = value }
    }
    private func setup() throws -> (TemplateAuthoringModel, TemplateNarrationAudioPreviewController, Owner) {
        let owner = Owner(try .init(accountID: 909, namespace: "narration-preview", epoch: 1, authorizationRevision: "member"))
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.value })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.title = "Audio preview"; model.draft.voiceEnabled = true
        model.draft.audioUrl = "https://audio.example.test/narration.m4a"; model.draft.audioDuration = 45
        model.changed()
        let preview = TemplateNarrationAudioPreviewController(model: model); preview.activate()
        return (model, preview, owner)
    }
    private func playback(_ driver: SyntheticPlatformAudioDriver, enabled: Bool = true,
                        origins: Set<String> = ["https://audio.example.test"]) -> PlatformAudioPlayback {
        .init(driver: driver, policy: .init(approvedOrigins: origins), enabled: enabled)
    }
    private func open(_ preview: TemplateNarrationAudioPreviewController, player: PlatformAudioPlayback) throws -> TemplateNarrationAudioPreviewController.Selection {
        preview.select(try XCTUnwrap(preview.capture()), makePlayer: { player })
        return try XCTUnwrap(preview.selection)
    }
    private func play(_ player: PlatformAudioPlayback, driver: SyntheticPlatformAudioDriver) {
        player.approveSelectedMedia(); player.toggle(); driver.event?(.playing)
    }

    func testOpeningAndSelectingNeverAutoplaysOrChangesTheDraft() throws {
        let (model, preview, _) = try setup(), before = model.draft
        let driver = SyntheticPlatformAudioDriver(), player = playback(driver)
        _ = try open(preview, player: player)
        XCTAssertEqual(player.state, .idle); XCTAssertEqual(driver.starts, 0)
        player.toggle(); XCTAssertEqual(driver.starts, 0, "Source review is still required")
        play(player, driver: driver)
        XCTAssertEqual(driver.starts, 1); XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, before)
        XCTAssertEqual(model.draft.audioDuration, 45)
    }

    func testDefaultDisabledAndUnapprovedOriginsCannotStart() throws {
        for mode in ["disabled", "unapproved"] {
            let (_, preview, _) = try setup(), driver = SyntheticPlatformAudioDriver()
            let player = playback(driver, enabled: mode != "disabled", origins: mode == "unapproved" ? [] : ["https://audio.example.test"])
            _ = try open(preview, player: player)
            player.approveSelectedMedia(); player.toggle()
            XCTAssertEqual(player.state, .gated); XCTAssertEqual(driver.starts, 0)
        }
        let (_, preview, _) = try setup()
        preview.select(preview.capture(), makePlayer: nil); XCTAssertNil(preview.selection)
    }

    func testInvalidReferencesNeverCreateAPlayer() throws {
        for raw in ["", " http://audio.example.test/a", "http://audio.example.test/a", "file:///tmp/a.m4a",
                    "https://user@audio.example.test/a", "https://audio.example.test/a#fragment",
                    "https://audio.example.test/a\n", String(repeating: "a", count: 8193)] {
            let (model, preview, _) = try setup(); model.draft.audioUrl = raw
            XCTAssertNil(preview.capture(), raw)
            var creations = 0
            preview.select(preview.capture(), makePlayer: { creations += 1; return self.playback(SyntheticPlatformAudioDriver()) })
            XCTAssertEqual(creations, 0)
        }
    }

    func testRepeatedEntryTapsPauseResumeTheConsentedPlayerWithoutRecreation() throws {
        let (_, preview, _) = try setup(), driver = SyntheticPlatformAudioDriver(), player = playback(driver)
        let original = try open(preview, player: player); play(player, driver: driver)
        var replacements = 0
        let factory: @MainActor () -> PlatformAudioPlayback = { replacements += 1; return self.playback(SyntheticPlatformAudioDriver()) }
        preview.select(preview.capture(), makePlayer: factory); XCTAssertEqual(player.state, .paused)
        preview.select(preview.capture(), makePlayer: factory); XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(replacements, 0); XCTAssertEqual(preview.selection?.id, original.id)
        XCTAssertEqual(driver.starts, 1)
    }

    func testClearStopsImmediatelyAndLateEventsCannotRestoreSelectionOrFields() throws {
        let (model, preview, _) = try setup(), driver = SyntheticPlatformAudioDriver(), player = playback(driver)
        _ = try open(preview, player: player); play(player, driver: driver)
        let late = driver.event
        model.clearNarrationAudioAction()()
        XCTAssertEqual(player.state, .disposed); XCTAssertNil(preview.selection)
        XCTAssertNil(model.draft.audioUrl); XCTAssertNil(model.draft.audioDuration)
        late?(.playing); late?(.ended)
        XCTAssertEqual(player.state, .disposed); XCTAssertNil(preview.selection)
    }

    func testPendingLoadIsDisposedBeforeDirectReferenceMutationWithoutOnChange() throws {
        let (model, preview, _) = try setup(), driver = SyntheticPlatformAudioDriver(), player = playback(driver)
        _ = try open(preview, player: player); player.approveSelectedMedia(); player.toggle()
        let late = driver.event, old = preview.capture()
        model.draft.audioUrl = "https://audio.example.test/replacement.m4a"
        XCTAssertEqual(player.state, .disposed); XCTAssertNil(preview.selection)
        late?(.playing); XCTAssertEqual(player.state, .disposed)
        var creations = 0
        preview.select(old, makePlayer: { creations += 1; return self.playback(SyntheticPlatformAudioDriver()) })
        XCTAssertEqual(creations, 0)
    }

    func testABAReferenceAndUnrelatedEditsRetireTheOriginalCapture() throws {
        let (model, preview, _) = try setup(), old = try XCTUnwrap(preview.capture())
        let reference = model.draft.audioUrl
        model.draft.audioUrl = "https://audio.example.test/replacement.m4a"
        model.draft.audioUrl = reference
        XCTAssertFalse(preview.isCurrent(old))
        let current = try XCTUnwrap(preview.capture())
        model.draft.title = "Edited title"
        XCTAssertFalse(preview.isCurrent(current))
    }

    func testReloadRestoreDiscardLeaveAndModuleRemovalDisposeActivePlayback() throws {
        for action in ["load", "restore", "discard", "leave", "remove-module"] {
            let (model, preview, _) = try setup(), driver = SyntheticPlatformAudioDriver(), player = playback(driver)
            _ = try open(preview, player: player); play(player, driver: driver)
            switch action {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "leave": model.leave()
            default: model.draft.voiceEnabled = false
            }
            XCTAssertNil(preview.selection, action); XCTAssertEqual(player.state, .disposed, action)
        }
    }

    func testDeactivateRejectsStaleOpenAndReentryRequiresFreshReview() throws {
        let (_, preview, _) = try setup(), driver = SyntheticPlatformAudioDriver(), player = playback(driver)
        let selected = try open(preview, player: player), old = try XCTUnwrap(preview.capture())
        play(player, driver: driver); preview.deactivate()
        XCTAssertEqual(player.state, .disposed); XCTAssertNil(preview.capture())
        preview.activate(); preview.select(old, makePlayer: { player }); XCTAssertNil(preview.selection)
        let freshDriver = SyntheticPlatformAudioDriver(), freshPlayer = self.playback(freshDriver)
        let next = try open(preview, player: freshPlayer)
        preview.close(selected); XCTAssertEqual(preview.selection?.id, next.id)
        XCTAssertEqual(freshPlayer.state, .idle); XCTAssertEqual(freshDriver.starts, 0)
    }

    func testOwnerChangeInvalidatesCaptureAndLifecycleStopsThePlayer() throws {
        let (model, preview, owner) = try setup(), driver = SyntheticPlatformAudioDriver(), player = playback(driver)
        let selected = try open(preview, player: player); play(player, driver: driver)
        owner.value = try .init(accountID: 910, namespace: "narration-preview", epoch: 2, authorizationRevision: "member")
        XCTAssertFalse(preview.isCurrent(selected.capture))
        preview.synchronize(); XCTAssertEqual(player.state, .disposed)
        model.load(); XCTAssertNil(preview.selection)
        owner.value = nil; preview.synchronize(); XCTAssertNil(preview.capture())
    }

    func testFailureEndAndInterruptionKeepExistingPlatformRetryAndConsentRules() throws {
        for event in [PlatformAudioEvent.failed, .ended, .interrupted] {
            let (model, preview, _) = try setup(), before = model.draft
            let driver = SyntheticPlatformAudioDriver(), player = playback(driver)
            let selected = try open(preview, player: player); play(player, driver: driver)
            driver.event?(event)
            XCTAssertNotEqual(player.state, .playing); XCTAssertEqual(preview.selection?.id, selected.id)
            XCTAssertEqual(model.draft, before)
            // Re-selecting an idle/failed/ended presentation never restarts it by itself.
            preview.select(preview.capture(), makePlayer: { player }); XCTAssertEqual(driver.starts, 1)
        }
    }
}
