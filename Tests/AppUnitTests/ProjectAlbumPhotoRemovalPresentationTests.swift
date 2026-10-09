import XCTest
@testable import Questify

@MainActor final class ProjectAlbumPhotoRemovalPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "album-removal") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectAlbumPhotoRemovalController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"; var album = ProjectEditBlock(kind: .dream); album.id = "album"
        album.sourceFields = ["images": .array((0..<3).map { .object(["url": .string("duplicate"), "line": .string("caption-\($0)")]) })]; draft.chapters[0].blocks = [album]
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model, chapterID: "chapter", blockID: "album", index: 1), owner, storage)
    }
    private func open(_ c: ProjectAlbumPhotoRemovalController) throws -> ProjectAlbumPhotoRemovalController.Opening {
        c.setActive(true); c.open(try XCTUnwrap(c.capture())); return try XCTUnwrap(c.opening)
    }
    func testOpeningAndCancelAreExactNoOps() async throws {
        let (c, _, storage) = try await setup(), before = ProjectEditPendingMaterials.exactData(c.model.draft), revision = c.model.draftMutationRevision, saved = storage.data
        let original = try open(c); XCTAssertEqual(original.capture.snapshot.caption, "caption-1"); c.close(original)
        XCTAssertFalse(c.remove(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before); XCTAssertEqual(c.model.draftMutationRevision, revision); XCTAssertEqual(storage.data, saved)
    }
    func testExplicitConfirmationRemovesOneDuplicateURLOrdinalOnlyOnce() async throws {
        let (c, _, storage) = try await setup(), original = try open(c), saved = storage.data, revision = c.model.draftMutationRevision
        XCTAssertTrue(c.remove(original)); XCTAssertFalse(c.remove(original))
        XCTAssertEqual(c.model.draft.chapters[0].blocks![0].dreamImages.map { $0["line"] }, [.string("caption-0"), .string("caption-2")])
        XCTAssertEqual(c.model.draftMutationRevision, revision + 1); XCTAssertEqual(storage.data, saved)
        c.model.saveLocal(); XCTAssertFalse(storage.data.isEmpty)
    }
    func testOldAndEmptySheetDismissalCannotCloseNewConfirmation() async throws {
        let (c, _, _) = try await setup(), empty = c.binding(nil), old = try open(c), binding = c.binding(old)
        c.close(old); let current = try open(c); binding.wrappedValue = nil; empty.wrappedValue = nil; c.close(old)
        XCTAssertEqual(c.opening?.id, current.id); XCTAssertFalse(c.remove(old)); XCTAssertTrue(c.isCurrent(current))
    }
    func testReorderEditRemovalAndSameByteABAInvalidateIndexConfirmation() async throws {
        for kind in ["reorder", "caption", "delete", "aba"] {
            let (c, _, _) = try await setup(), original = try open(c)
            switch kind {
            case "reorder": let images = c.model.draft.chapters[0].blocks![0].sourceFields!["images"]!.array!; c.model.draft.chapters[0].blocks![0].setField("images", .array(Array(images.reversed())))
            case "caption": c.model.draft.chapters[0].blocks![0].setDreamImage(index: 1, field: "line", value: "new")
            case "delete": c.model.draft.chapters[0].blocks = []
            default: let same = c.model.draft; c.model.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(c.model.draft); XCTAssertFalse(c.remove(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        }
    }
    func testOwnerEpochReadOnlyVisitAndRestoreRejectConfirmation() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); locked.setActive(true); XCTAssertNil(locked.capture())
        for kind in ["owner", "epoch", "visit", "restore"] {
            let (c, owner, _) = try await setup(), original = try open(c)
            switch kind {
            case "owner": owner.session = nil
            case "epoch": owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: "album-removal")
            case "visit": c.model.coordinator.beginEditorVisit(UUID())
            default: c.model.saveLocal(); await c.model.load(force: true); c.model.restore()
            }
            let before = ProjectEditPendingMaterials.exactData(c.model.draft); XCTAssertFalse(c.remove(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        }
    }
    func testRetiredBackgroundHostAndForeignControllerRejectStaleCapture() async throws {
        let (c, _, _) = try await setup(); XCTAssertNil(c.capture()); c.setActive(true)
        let captured = try XCTUnwrap(c.capture()), other = ProjectAlbumPhotoRemovalController(model: c.model, chapterID: "chapter", blockID: "album", index: 1)
        other.setActive(true); other.open(captured); XCTAssertNil(other.opening)
        c.setActive(false); c.setActive(true); c.open(captured); XCTAssertNil(c.opening)
        let current = try open(c); c.setActive(false); XCTAssertFalse(c.remove(current))
    }
    func testMalformedNeighborPreventsOpeningWithoutDroppingIt() async throws {
        let (c, _, _) = try await setup(); var rows = c.model.draft.chapters[0].blocks![0].sourceFields!["images"]!.array!; rows[0] = .null
        c.model.draft.chapters[0].blocks![0].setField("images", .array(rows)); c.setActive(true)
        let before = ProjectEditPendingMaterials.exactData(c.model.draft); XCTAssertNil(c.capture()); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
    }
}
