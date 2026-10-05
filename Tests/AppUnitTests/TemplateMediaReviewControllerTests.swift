import XCTest
@testable import Questify

@MainActor final class TemplateMediaReviewControllerTests: XCTestCase {
    private final class Owner { var value: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession?) { self.value = value } }
    private func setup() throws -> (TemplateAuthoringModel, TemplateMediaReviewController, Owner) {
        let owner = Owner(try .init(accountID: 901, namespace: "media-review-fixture", epoch: 1, authorizationRevision: "member"))
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.value })
        var seed = TemplateAuthoringSyntheticFixtures.draft(); seed.validationMethod = .choice
        seed.questionImg = "  fixture:image-e\u{301}\r\n"; seed.questionAudio = "\tfixture:question-audio "
        seed.voiceEnabled = true; seed.audioUrl = " fixture:narration\n"
        for letter in TemplateChoiceOptionMedia.Letter.allCases {
            try seed.setChoiceOptionMedia(letter, .image, to: " fixture:image-\(letter.rawValue) ")
            try seed.setChoiceOptionMedia(letter, .audio, to: " fixture:audio-\(letter.rawValue) ")
        }
        coordinator.open(seed: seed)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let media = TemplateMediaReviewController(model: model, fixtureMode: "generated"); media.reload()
        return (model, media, owner)
    }
    private func open(_ media: TemplateMediaReviewController, _ field: TemplateAuthoringMediaField) throws -> TemplateMediaReviewController.Review {
        media.open(try XCTUnwrap(media.rows.first { $0.field == field })); return try XCTUnwrap(media.review)
    }
    private func bytes(_ a: String?, _ b: String?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.map { Array($0.utf8) }, b.map { Array($0.utf8) }, file: file, line: line)
    }
    func testEveryFixedFieldReviewsWithoutChangingAnyDraftBytesOrRemoteAuthority() throws {
        let (model, media, _) = try setup(); let before = model.draft
        XCTAssertEqual(media.rows.count, 11)
        for row in media.rows {
            media.open(row); let review = try XCTUnwrap(media.review)
            bytes(review.savedReference, row.savedReference)
            media.finish(review); XCTAssertNil(media.review)
            media.open(row); XCTAssertNil(media.review, "Consumed target cannot start another review")
            XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, before)
        }
        bytes(model.draft.questionImg, before.questionImg)
        XCTAssertFalse(model.coordinator.canSubmit); XCTAssertNil(model.coordinator.review)
    }
    func testDefaultPickerGateDoesNotBeginDeviceSelection() throws {
        let (_, media, _) = try setup(), review = try open(media, .questionImage)
        XCTAssertFalse(try XCTUnwrap(media.presentation(for: review.id)).canSelectImage)
        media.selectImage(review)
        XCTAssertEqual(media.presentation(for: review.id)?.state, .awaitingSelection)
        XCTAssertEqual(media.review, review)
    }
    func testGeneratedSanitizedImageUsesOwnAspectAndNeverChangesReference() throws {
        let (model, media, _) = try setup(); let before = model.draft
        media.beginSynthetic(try open(media, .questionImage))
        let review = try XCTUnwrap(media.review), draft = try XCTUnwrap(media.presentation(for: review.id)?.crop)
        XCTAssertEqual(draft.source.width, 96); XCTAssertEqual(draft.source.height, 48)
        let rect = try TemplateImageCropRect(sourceWidth: 96, sourceHeight: 48, zoom: 2)
        media.confirmCrop(review, id: draft.id, rect: rect)
        let ready = try XCTUnwrap(media.presentation(for: review.id))
        XCTAssertEqual(ready.state, .ready); XCTAssertEqual(ready.image?.width, 48); XCTAssertEqual(ready.image?.height, 24)
        XCTAssertNil(ready.audio); XCTAssertEqual(model.draft, before)
        media.finish(review); XCTAssertNil(media.presentation(for: review.id)); bytes(model.draft.questionImg, before.questionImg)
    }
    func testRetainedOldPanelAndDismissalCannotReacquireOrCancelNewField() throws {
        let (_, media, _) = try setup(), old = try open(media, .questionImage)
        media.beginSynthetic(old, held: true); let oldPending = try XCTUnwrap(media.review)
        let current = try open(media, .questionAudio)
        XCTAssertNil(media.presentation(for: old.id)); XCTAssertNotEqual(current.id, old.id)
        media.completeSynthetic(oldPending); media.selectImage(oldPending); media.finish(oldPending)
        XCTAssertNil(media.reselect(oldPending)); media.cancel(originalID: old.id)
        XCTAssertEqual(media.review, current); XCTAssertEqual(media.presentation(for: current.id)?.state, .awaitingSelection)
    }
    func testSamePanelReselectRotatesSelectionAndRejectsRetainedCallbacks() throws {
        let (_, media, _) = try setup(), original = try open(media, .questionAudio)
        media.beginSynthetic(original, held: true); let pending = try XCTUnwrap(media.review)
        let next = try XCTUnwrap(media.reselect(pending))
        XCTAssertEqual(next.id, original.id); XCTAssertNotEqual(next.selection.selectionID, pending.selection.selectionID)
        media.completeSynthetic(pending); media.finish(pending)
        XCTAssertEqual(media.review, next); XCTAssertEqual(media.presentation(for: original.id)?.state, .awaitingSelection)
        media.beginSynthetic(next); let ready = try XCTUnwrap(media.presentation(for: original.id))
        XCTAssertEqual(ready.audio?.format, .m4a); XCTAssertEqual(ready.audio?.byteCount, 128)
        XCTAssertEqual(ready.audio?.evidence, .extensionAndByteCountOnly); XCTAssertNil(ready.image)
    }
    func testExplicitClearAndABAReferenceEditInvalidateBeforeOnChange() throws {
        let (model, media, _) = try setup(), original = try open(media, .questionImage)
        let raw = try XCTUnwrap(model.draft.questionImg), oldRow = try XCTUnwrap(media.rows.first { $0.field == .questionImage })
        let binding = model.optional(\.questionImg)
        binding.wrappedValue = ""; binding.wrappedValue = raw
        XCTAssertNil(media.review); XCTAssertFalse(media.isCurrent(original))
        media.open(oldRow); XCTAssertNil(media.review)
        model.changed(); let fresh = try open(media, .questionImage)
        XCTAssertNotEqual(fresh.selection.slotRevision, original.selection.slotRevision); bytes(model.draft.questionImg, raw)
    }
    func testDirectMutationBeforeObservationCannotExposeOrFinishOldReview() throws {
        let (model, media, _) = try setup(), old = try open(media, .questionImage)
        model.draft.questionImg = "replacement"
        XCTAssertNil(media.presentation(for: old.id)); media.finish(old)
        XCTAssertEqual(model.draft.questionImg, "replacement")
        model.changed(); XCTAssertNil(media.review)
    }
    func testRetainedReferenceAndStorySettersCannotInvalidateNewEditorReview() throws {
        let (model, media, _) = try setup()
        let raw = model.optional(\.questionImg), option = model.optionMedia(.a, .image)
        let story = TemplateStoryEditor(model: model), oldStory = story.images(story.beats[0].id)
        model.load(); media.reload()
        let current = try open(media, .questionImage), before = model.draft
        raw.wrappedValue = "stale"; option.wrappedValue = "stale"; oldStory.wrappedValue = "stale"
        XCTAssertEqual(model.draft, before); XCTAssertEqual(media.review, current)
        XCTAssertNotNil(media.presentation(for: current.id))
    }
    func testReloadRestoreDiscardAndRetireDropCandidatesAndCapturedTargets() throws {
        for action in ["load", "restore", "discard", "leave"] {
            let (model, media, _) = try setup(), old = try open(media, .questionImage)
            media.beginSynthetic(old); let staged = try XCTUnwrap(media.review)
            let row = try XCTUnwrap(media.rows.first { $0.field == .questionImage })
            switch action { case "load": model.load(); case "restore": model.restore(); case "discard": model.discard(); default: media.retire() }
            XCTAssertNil(media.presentation(for: staged.id)); XCTAssertNil(media.review)
            media.reload(); media.open(row); XCTAssertNil(media.review)
            media.completeSynthetic(staged); XCTAssertNil(media.review)
        }
    }
    func testOwnerChangeAndABAWithExplicitLifecycleNeverReviveOldReview() throws {
        let (model, media, owner) = try setup(), firstOwner = owner.value, old = try open(media, .questionAudio)
        owner.value = try .init(accountID: 902, namespace: "media-review-fixture", epoch: 2, authorizationRevision: "member")
        XCTAssertNil(media.presentation(for: old.id)); model.load()
        owner.value = firstOwner; model.load(); media.reload()
        media.beginSynthetic(old); media.finish(old); XCTAssertNil(media.review)
    }
    func testStoryDuplicatesStayDistinctMoveKeepsSlotsAndInvalidatesPending() throws {
        let (model, _, _) = try setup()
        try model.draft.setStory([.init(text: "First", imgs: ["same", "same"]), .init(text: "Second", imgs: ["third"])])
        model.changed(); let story = TemplateStoryEditor(model: model)
        let media = TemplateMediaReviewController(model: model, story: story, fixtureMode: "generated"); media.reload()
        let firstBeat = story.beats[0].id
        let duplicates = media.rows.filter { $0.field == .storyBeatImage(beatID: firstBeat) && $0.savedReference != nil }
        XCTAssertEqual(duplicates.count, 2); XCTAssertNotEqual(duplicates[0].id, duplicates[1].id)
        media.open(duplicates[0]); let old = try XCTUnwrap(media.review)
        story.move(IndexSet(integer: 0), to: 2)
        XCTAssertNil(media.review); XCTAssertNil(media.presentation(for: old.id))
        let moved = media.rows.filter { $0.field == .storyBeatImage(beatID: firstBeat) && $0.savedReference != nil }
        XCTAssertEqual(moved.map(\.id), duplicates.map(\.id))
        XCTAssertNotEqual(moved[0].target.slotRevision, duplicates[0].target.slotRevision)
        media.open(duplicates[0]); XCTAssertNil(media.review)
    }
    func testStoryInsertionCandidateRespectsSixImageCapAndDeletionFencesTarget() throws {
        let (model, _, _) = try setup()
        try model.draft.setStory([.init(text: "Full", imgs: (1...6).map { "fixture:\($0)" }), .init(text: "Empty")])
        model.changed(); let story = TemplateStoryEditor(model: model)
        let media = TemplateMediaReviewController(model: model, story: story); media.reload()
        XCTAssertEqual(media.rows.filter { $0.field == .storyBeatImage(beatID: story.beats[0].id) }.count, 6)
        let candidate = try XCTUnwrap(media.rows.first { $0.field == .storyBeatImage(beatID: story.beats[1].id) })
        XCTAssertNil(candidate.savedReference); media.open(candidate); let old = try XCTUnwrap(media.review)
        story.remove(IndexSet(integer: 1)); media.open(candidate)
        XCTAssertNil(media.review); XCTAssertNil(media.presentation(for: old.id))
    }
    func testComputedMediaLabelsUseTheRequestedLocale() {
        XCTAssertEqual(TemplateMediaReviewLabels.state(.ready, locale: Locale(identifier: "en")),
                       "Ready for local review only. The saved reference is unchanged.")
        XCTAssertEqual(TemplateMediaReviewLabels.state(.ready, locale: Locale(identifier: "zh-Hans")),
                       "仅供本地审阅，已保存的引用保持不变。")
        XCTAssertEqual(TemplateMediaReviewLabels.title(.optionImage(.a), ordinal: 0, locale: Locale(identifier: "zh-Hans")), "选项图片 A")
    }
}
