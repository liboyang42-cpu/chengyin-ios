import XCTest
@testable import Questify

@MainActor final class ProjectEditorAudioPreviewTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "editor-preview") }
    @MainActor private final class Factory {
        var drivers: [SyntheticPlatformAudioDriver] = []
        func make() -> PlatformAudioPlayback {
            let driver = SyntheticPlatformAudioDriver(); drivers.append(driver)
            return .init(driver: driver, policy: .init(approvedOrigins: ["https://example.com"]), enabled: true)
        }
    }
    private func setup() async throws -> (ProjectEditorAudioPreviewController, Owner, Factory) {
        let owner = Owner()
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].preserved["audioUrl"] = .string("https://example.com/same.mp3")
        draft.chapters[0].blocks = [.init(kind: .audio, url: "https://example.com/same.mp3"), .init(kind: .audio, url: "https://example.com/same.mp3")]
        let coordinator = ProjectEditCoordinator(initial: .init(draft: draft), service: ProjectEditSyntheticService(),
            store: .init(storage: ProjectEditMemoryStorage()), currentSession: { owner.session })
        let editor = ProjectEditModel(coordinator: coordinator); await editor.load()
        return (.init(editor: editor, chapterID: draft.chapters[0].id), owner, Factory())
    }
    private func play(_ controller: ProjectEditorAudioPreviewController, _ factory: Factory,
                      _ destination: ProjectEditorAudioPreviewController.Destination) throws -> ProjectEditorAudioPreviewController.Selection {
        controller.select(controller.capture(destination), makePlayer: { factory.make() })
        let selection = try XCTUnwrap(controller.selection), player = try XCTUnwrap(selection.player)
        XCTAssertEqual(factory.drivers.last?.starts, 0)
        player.approveSelectedMedia(); player.toggle(); factory.drivers.last?.event?(.playing)
        XCTAssertEqual(player.state, .playing)
        return selection
    }
    func testChapterAndStoryBlocksWithSameURLAreMutuallyExclusiveSources() async throws {
        let (controller, _, factory) = try await setup()
        let original = try play(controller, factory, .chapterNarration), oldCallback = factory.drivers[0].event
        let id = controller.editor.draft.chapters[0].blocks![0].id
        let next = try play(controller, factory, .storyBlock(Data(id.utf8)))
        XCTAssertEqual(original.player?.state, .disposed); XCTAssertNotEqual(next.id, original.id)
        oldCallback?(.playing); XCTAssertEqual(original.player?.state, .disposed); XCTAssertEqual(next.player?.state, .playing)
        let secondID = controller.editor.draft.chapters[0].blocks![1].id
        let last = try play(controller, factory, .storyBlock(Data(secondID.utf8)))
        XCTAssertEqual(next.player?.state, .disposed); XCTAssertNotEqual(last.id, next.id)
    }
    func testRepeatedSameSourceTapPausesAndResumesOnlyAlreadyConsentedPlayer() async throws {
        let (controller, _, factory) = try await setup()
        let selection = try play(controller, factory, .chapterNarration)
        controller.select(controller.capture(.chapterNarration), makePlayer: { factory.make() })
        XCTAssertEqual(selection.player?.state, .paused)
        controller.select(controller.capture(.chapterNarration), makePlayer: { factory.make() })
        XCTAssertEqual(selection.player?.state, .playing); XCTAssertEqual(factory.drivers.count, 1)
        XCTAssertEqual(controller.selection?.id, selection.id)
    }
    func testUnknownURLWrongOriginAndDefaultOffCannotBorrowUploadPermission() async throws {
        let (controller, _, factory) = try await setup()
        for raw in ["", "http://example.com/a.mp3", "file:///tmp/audio", "https://user:password@example.com/a", "https://example.com/a#fragment", " https://example.com/a"] {
            controller.editor.draft.chapters[0].preserved["audioUrl"] = .string(raw)
            XCTAssertNil(controller.capture(.chapterNarration), raw)
        }
        controller.editor.draft.chapters[0].preserved["audioUrl"] = .string("https://unknown.invalid/audio")
        controller.select(controller.capture(.chapterNarration), makePlayer: { factory.make() })
        let denied = try XCTUnwrap(controller.selection?.player); denied.approveSelectedMedia(); denied.toggle()
        XCTAssertEqual(denied.state, .gated); XCTAssertEqual(factory.drivers[0].starts, 0)
        controller.retire(); controller.editor.draft.chapters[0].preserved["audioUrl"] = .string("https://example.com/a")
        controller.select(controller.capture(.chapterNarration), makePlayer: nil)
        XCTAssertNil(controller.selection?.player); XCTAssertEqual(factory.drivers.count, 1)
    }
    func testDeleteReorderReplacementAndSameByteABAStopAndRejectLateCallbacks() async throws {
        for action in ["delete", "reorder", "replace", "aba"] {
            let (controller, _, factory) = try await setup(), model = controller.editor
            let id = model.draft.chapters[0].blocks![0].id
            let selected = try play(controller, factory, .storyBlock(Data(id.utf8))), callback = factory.drivers[0].event
            switch action {
            case "delete": model.draft.chapters[0].blocks?.removeFirst()
            case "reorder": model.draft.chapters[0].blocks?.reverse()
            case "replace": model.draft.chapters[0].blocks?[0].url = "https://example.com/changed.mp3"
            default: let same = model.draft; model.draft = same
            }
            controller.synchronize(); callback?(.playing)
            XCTAssertNil(controller.selection, action); XCTAssertEqual(selected.player?.state, .disposed, action)
        }
    }
    func testOldButtonCloseAndForeignControllerCannotStealCurrentPreview() async throws {
        let (controller, _, factory) = try await setup()
        let stale = try XCTUnwrap(controller.capture(.chapterNarration))
        let original = try play(controller, factory, .chapterNarration)
        controller.close(original)
        let next = try play(controller, factory, .chapterNarration)
        controller.select(stale, makePlayer: { factory.make() }); controller.close(original)
        XCTAssertEqual(controller.selection?.id, next.id); XCTAssertEqual(factory.drivers.count, 2)
        let other = ProjectEditorAudioPreviewController(editor: controller.editor, chapterID: controller.chapterID)
        other.select(controller.capture(.chapterNarration), makePlayer: { factory.make() })
        XCTAssertNil(other.selection)
    }
    func testAccountEpochOrNavigationRetiresPreviewWithoutChangingDraftBytes() async throws {
        for action in ["account", "epoch", "signOut", "navigation"] {
            let (controller, owner, factory) = try await setup()
            let before = ProjectEditPendingMaterials.exactData(controller.editor.draft)
            let original = try play(controller, factory, .chapterNarration), late = factory.drivers[0].event
            switch action {
            case "account": owner.session = try .init(accountID: 8, epoch: 1, storageNamespace: "editor-preview")
            case "epoch": owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: "editor-preview")
            case "signOut": owner.session = nil
            default: controller.retire()
            }
            controller.synchronize(); late?(.playing)
            XCTAssertEqual(original.player?.state, .disposed, action)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.editor.draft), before, action)
        }
    }
    func testMissingDuplicateOrCanonicalAliasBlockIDsCannotResolvePreviewTarget() async throws {
        let (controller, _, _) = try await setup(), model = controller.editor
        XCTAssertNil(controller.capture(.storyBlock(Data("missing".utf8))))
        model.draft.chapters[0].blocks?[0].id = "e\u{301}"
        XCTAssertNil(controller.capture(.storyBlock(Data("é".utf8))))
        let block = try XCTUnwrap(model.draft.chapters[0].blocks?.first)
        model.draft.chapters[0].blocks?.append(block)
        XCTAssertNil(controller.capture(.storyBlock(Data(block.id.utf8))))
    }
}
