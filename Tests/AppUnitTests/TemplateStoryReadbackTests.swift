import XCTest
@testable import Questify

/// STORY-READ-01: owner-read isolation and locked readback; Apple execution still required.
@MainActor final class TemplateStoryReadbackTests: XCTestCase {
    private func owner(_ account: Int = 911, epoch: UInt64 = 1, role: String = "member") throws -> TemplateAuthoringSession {
        try .init(accountID: account, namespace: "story-readback", epoch: epoch, authorizationRevision: role)
    }
    private func seed() -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Local story readback")
        draft.storyEnabled = true; draft.storyText = "independent historical summary"
        draft.storyJson = #" [ {"text":"  exact scene  ","tag":" exact tag ","imgs":["1","2","3","4","5","6","7"]} ] "#
        return draft
    }
    private func assertHidden(_ editor: TemplateStoryEditor, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(editor.canRead, file: file, line: line)
        XCTAssertTrue(editor.visibleBeats.isEmpty, file: file, line: line)
        XCTAssertNil(editor.visibleIssueKey, file: file, line: line)
        for beat in editor.beats {
            XCTAssertEqual(editor.text(beat.id, \.text).wrappedValue, "", file: file, line: line)
            XCTAssertEqual(editor.text(beat.id, \.tag).wrappedValue, "", file: file, line: line)
            XCTAssertEqual(editor.images(beat.id).wrappedValue, "", file: file, line: line)
        }
    }
    func testLockedCurrentOwnerRetainsExactBindingsAndRenderedMetadataWithoutWrites() async throws {
        let cases: [(TemplateAuthoringAuthority, Bool, TemplateAuthoringCoordinator.State)] = [
            (.synthetic, false, .simulated), (.synthetic, true, .uncertain), (.injectedHTTP, false, .acknowledged)
        ]
        for (authority, uncertain, state) in cases {
            let session = try owner(), transport = StoryReadbackFixtureTransport(authority: authority, uncertain: uncertain)
            let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: transport), store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
            coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
            let editor = TemplateStoryEditor(model: model), id = try XCTUnwrap(editor.beats.first?.id)
            let text = editor.text(id, \.text), tag = editor.text(id, \.tag), images = editor.images(id), original = model.draft
            func verifyLocked() {
                XCTAssertTrue(coordinator.locked); XCTAssertFalse(editor.canEdit); XCTAssertTrue(editor.canRead)
                XCTAssertEqual(text.wrappedValue, "  exact scene  "); XCTAssertEqual(tag.wrappedValue, " exact tag ")
                XCTAssertEqual(images.wrappedValue, "1\n2\n3\n4\n5\n6\n7")
                XCTAssertEqual(editor.visibleBeats.count, 1); XCTAssertEqual(editor.visibleBeats.first?.imgs.count, 7)
                let fresh = TemplateStoryEditor(model: model), freshID = fresh.beats[0].id
                XCTAssertTrue(fresh.canRead); XCTAssertFalse(fresh.canEdit)
                XCTAssertEqual(fresh.text(freshID, \.text).wrappedValue, "  exact scene  ")
                XCTAssertEqual(fresh.text(freshID, \.tag).wrappedValue, " exact tag ")
                XCTAssertEqual(fresh.images(freshID).wrappedValue, "1\n2\n3\n4\n5\n6\n7")
                text.wrappedValue = "late text"; tag.wrappedValue = "late tag"; images.wrappedValue = "late image"
                fresh.text(freshID, \.text).wrappedValue = "fresh locked edit"; editor.add()
                XCTAssertEqual(model.draft, original); XCTAssertEqual(coordinator.draft, original)
            }
            transport.onSend = { XCTAssertEqual(coordinator.state, .submitting); verifyLocked() }
            model.prepare(.saveDraft); await model.confirm(try XCTUnwrap(model.review))
            XCTAssertEqual(coordinator.state, state); XCTAssertEqual(transport.requests, 1); verifyLocked()
        }
    }
    func testRetainedAndFreshEditorsHideAccountEpochRoleAndLogoutDriftBeforeModelReload() throws {
        let replacements: [TemplateAuthoringSession?] = [try owner(912), try owner(epoch: 2), try owner(role: "merchant"), nil]
        for replacement in replacements {
            var session: TemplateAuthoringSession? = try owner()
            let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
            coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
            let editor = TemplateStoryEditor(model: model), id = try XCTUnwrap(editor.beats.first?.id)
            let text = editor.text(id, \.text), tag = editor.text(id, \.tag), images = editor.images(id), original = model.draft
            session = replacement
            XCTAssertFalse(model.canReadStoryDraft); assertHidden(editor)
            let beforeReload = TemplateStoryEditor(model: model); assertHidden(beforeReload)
            XCTAssertEqual(text.wrappedValue, ""); XCTAssertEqual(tag.wrappedValue, ""); XCTAssertEqual(images.wrappedValue, "")
            text.wrappedValue = "wrong owner"; images.wrappedValue = "wrong owner"; beforeReload.add()
            XCTAssertEqual(model.draft, original)
            model.load(); assertHidden(editor); assertHidden(beforeReload)
            XCTAssertEqual(text.wrappedValue, ""); XCTAssertEqual(tag.wrappedValue, ""); XCTAssertEqual(images.wrappedValue, "")
            if replacement != nil {
                model.draft = seed(); model.changed(); let fresh = TemplateStoryEditor(model: model)
                XCTAssertTrue(fresh.canRead); XCTAssertEqual(fresh.visibleBeats.first?.text, "  exact scene  ")
                assertHidden(editor); assertHidden(beforeReload)
            }
        }
    }
    func testNewEditorCannotLeaseOldModelDraftAfterCoordinatorIdentityReplacement() throws {
        let originalSession = try owner(); var session: TemplateAuthoringSession? = originalSession
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let old = TemplateStoryEditor(model: model), original = model.draft, oldIdentity = coordinator.identity
        session = nil; coordinator.synchronizeSession(); session = originalSession; coordinator.synchronizeSession()
        XCTAssertNotEqual(coordinator.identity, oldIdentity); XCTAssertFalse(model.canReadStoryDraft)
        assertHidden(old); let freshBeforeModel = TemplateStoryEditor(model: model); assertHidden(freshBeforeModel)
        freshBeforeModel.add(); XCTAssertEqual(model.draft, original)
        model.load(); assertHidden(old); assertHidden(freshBeforeModel)
        model.draft = seed(); model.changed(); XCTAssertTrue(TemplateStoryEditor(model: model).canRead)
    }
    func testSameOwnerModelAndEditorReloadRevokeOldBindingsWithoutChangingRawDraft() throws {
        let session = try owner(), coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model), id = try XCTUnwrap(editor.beats.first?.id)
        let text = editor.text(id, \.text), images = editor.images(id), original = model.draft
        editor.load(); XCTAssertTrue(editor.canRead); XCTAssertEqual(text.wrappedValue, ""); XCTAssertEqual(images.wrappedValue, "")
        let newText = editor.text(try XCTUnwrap(editor.beats.first?.id), \.text)
        model.load(); assertHidden(editor); XCTAssertEqual(newText.wrappedValue, "")
        editor.load(); XCTAssertTrue(editor.canRead); XCTAssertEqual(newText.wrappedValue, "")
        XCTAssertEqual(model.draft, original); XCTAssertEqual(coordinator.draft, original)
    }
    func testRestoreAndDiscardRevokeReadLeasesAndPreserveHistoricalBytes() throws {
        let session = try owner(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let saved = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        saved.open(seed: seed()); saved.saveLocal()
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let beforeRestore = TemplateStoryEditor(model: model)
        let restoreText = beforeRestore.text(try XCTUnwrap(beforeRestore.beats.first?.id), \.text)
        model.restore(); assertHidden(beforeRestore); XCTAssertEqual(restoreText.wrappedValue, "")
        XCTAssertEqual(model.draft, seed()); XCTAssertNil(model.draft.storyTimelineEdited)
        let restored = TemplateStoryEditor(model: model), id = try XCTUnwrap(restored.beats.first?.id)
        let oldText = restored.text(id, \.text), oldImages = restored.images(id), identity = coordinator.identity
        model.discard(); XCTAssertEqual(identity, coordinator.identity); assertHidden(restored)
        XCTAssertEqual(oldText.wrappedValue, ""); XCTAssertEqual(oldImages.wrappedValue, "")
        model.draft = seed(); model.changed(); assertHidden(restored)
        XCTAssertEqual(oldText.wrappedValue, ""); XCTAssertEqual(oldImages.wrappedValue, "")
        XCTAssertTrue(TemplateStoryEditor(model: model).canRead); XCTAssertEqual(model.draft, seed())
    }
    func testRawReplacementAndCachedIssueCannotLeakThroughPriorReadLease() throws {
        var session: TemplateAuthoringSession? = try owner()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model), id = try XCTUnwrap(editor.beats.first?.id), text = editor.text(id, \.text)
        model.draft.storyJson = #"[{"text":"replacement","tag":"","imgs":[]}]"#; model.changed()
        assertHidden(editor); XCTAssertEqual(text.wrappedValue, "")
        model.draft.storyJson = "{unknown"; model.changed(); let unsupported = TemplateStoryEditor(model: model)
        XCTAssertFalse(unsupported.canRead); XCTAssertEqual(unsupported.visibleIssueKey, "templateStory.unsupported")
        XCTAssertTrue(unsupported.visibleBeats.isEmpty)
        let original = model.draft; session = nil
        assertHidden(unsupported); assertHidden(TemplateStoryEditor(model: model)); XCTAssertEqual(model.draft, original)
    }
}

/// All responses are in-memory, including the injected-authority acknowledgment case.
@MainActor private final class StoryReadbackFixtureTransport: TemplateAuthoringTransport {
    let authority: TemplateAuthoringAuthority
    let uncertain: Bool
    var onSend: (() -> Void)?
    private(set) var requests = 0
    init(authority: TemplateAuthoringAuthority, uncertain: Bool) { self.authority = authority; self.uncertain = uncertain }
    func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) {
        requests += 1; onSend?()
        if uncertain { throw TemplateAuthoringError.uncertain }
        return (Data(#"{"code":200,"msg":"fixture only"}"#.utf8), 200)
    }
}
