import XCTest
@testable import Questify

@MainActor final class ProjectAlbumPhotoOrderPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "album-order") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectAlbumPhotoOrderPresentation, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"; var album = ProjectEditBlock(kind: .dream); album.id = "album"
        album.sourceFields = ["title": .string("album"), "images": .array((0..<3).map { .object(["url": .string("duplicate"), "line": .string("caption-\($0)")]) })]
        draft.chapters[0].blocks = [album]
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: .init(storage: storage), currentSession: { owner.session }))
        await model.load()
        return (.init(model: model, chapterID: "chapter", blockID: "album", index: 1), owner, storage)
    }
    private func capture(_ p: ProjectAlbumPhotoOrderPresentation) throws -> ProjectAlbumPhotoOrderPresentation.Capture {
        p.setActive(true); return try XCTUnwrap(p.capture())
    }
    func testExplicitMoveOnlyOnceAndUsesExistingLocalSavePath() async throws {
        let (p, _, storage) = try await setup(), captured = try capture(p), saved = storage.data, revision = p.model.draftMutationRevision
        XCTAssertTrue(p.move(.up, captured: captured)); XCTAssertFalse(p.move(.up, captured: captured))
        XCTAssertEqual(p.model.draft.chapters[0].blocks![0].dreamImages[0]["line"], .string("caption-1"))
        XCTAssertEqual(p.model.draftMutationRevision, revision + 1); XCTAssertEqual(storage.data, saved)
        p.model.saveLocal(); XCTAssertFalse(storage.data.isEmpty)
    }
    func testInactiveReadOnlyAndPresentationRetirementReject() async throws {
        let (p, _, _) = try await setup(); XCTAssertNil(p.capture())
        let captured = try capture(p), before = ProjectEditPendingMaterials.exactData(p.model.draft)
        p.setActive(false); XCTAssertFalse(p.move(.up, captured: captured)); p.setActive(true)
        XCTAssertFalse(p.move(.up, captured: captured)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(p.model.draft), before)
        let (locked, _, _) = try await setup(scope: .whitelist); locked.setActive(true); XCTAssertNil(locked.capture())
    }
    func testOwnerEpochSignoutVisitAndRestoreInvalidateRenderedAction() async throws {
        for kind in ["owner", "epoch", "signout", "visit", "restore"] {
            let (p, owner, _) = try await setup(), captured = try capture(p)
            switch kind {
            case "signout": owner.session = nil
            case "visit": p.model.coordinator.beginEditorVisit(UUID())
            case "restore": p.model.saveLocal(); await p.model.load(force: true); p.model.restore()
            default: owner.session = try .init(accountID: kind == "owner" ? 8 : 7, epoch: 2, storageNamespace: "album-order")
            }
            let before = ProjectEditPendingMaterials.exactData(p.model.draft)
            XCTAssertFalse(p.move(.up, captured: captured)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(p.model.draft), before)
        }
    }
    func testDraftChangesAndSameByteABARejectStaleIndex() async throws {
        for kind in ["caption", "remove", "other", "aba"] {
            let (p, _, _) = try await setup(), captured = try capture(p)
            switch kind {
            case "caption": p.model.draft.chapters[0].blocks![0].setDreamImage(index: 1, field: "line", value: "updated")
            case "remove": p.model.draft.chapters[0].blocks = []
            case "other": p.model.draft.name += "!"
            default: let same = p.model.draft; p.model.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(p.model.draft)
            XCTAssertFalse(p.move(.down, captured: captured)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(p.model.draft), before)
        }
    }
    func testCaptureFromAnotherPresentationCannotMutate() async throws {
        let (p, _, _) = try await setup(), captured = try capture(p)
        let other = ProjectAlbumPhotoOrderPresentation(model: p.model, chapterID: "chapter", blockID: "album", index: 0)
        other.setActive(true); XCTAssertFalse(other.move(.up, captured: captured))
    }
}
