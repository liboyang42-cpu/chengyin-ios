import Foundation
import XCTest
import SwiftUI
@testable import Questify

#if DEBUG
@MainActor final class ProjectStoryTemplatePresentationTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "story-template-app")
    }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]
        var failWrites = false
        var writeCount = 0, writeAttempts = 0
        var failAtAttempt: Int?, failReads = false
        func read(_ key: String) throws -> Data? { if failReads { throw ProjectEditError.persistenceUnavailable }; return data[key] }
        func remove(_ key: String) throws { data[key] = nil }
        func write(_ value: Data, key: String) throws {
            writeAttempts += 1
            if failWrites || writeAttempts == failAtAttempt { throw ProjectEditError.persistenceUnavailable }
            writeCount += 1; data[key] = value
        }
    }
    /// An intentionally cancellation-uncooperative source exercises both late success and error callbacks.
    @MainActor private final class Source: ProjectStoryTemplateReading {
        var identity = UUID(), permitted = true
        let owner: Owner
        var rows: [ProjectEditJSON], details: [Int: ProjectEditJSON]
        var pages: [Int: ProjectStoryTemplatePage] = [:]
        var listCalls: [Int] = [], detailCalls: [Int] = []
        var sessions: [ProjectEditSession] = []
        var listError: Error?, detailError: Error?
        var holdNextList = false, holdNextDetail = false
        var pendingList: CheckedContinuation<ProjectStoryTemplatePage, Error>?
        var pendingDetail: CheckedContinuation<ProjectStoryTemplateDraft, Error>?
        private var heldPage: ProjectStoryTemplatePage?
        private var heldDraft: ProjectStoryTemplateDraft?
        init(owner: Owner, rows: [ProjectEditJSON], details: [Int: ProjectEditJSON]) {
            self.owner = owner; self.rows = rows; self.details = details
        }
        func isCurrent(session: ProjectEditSession) -> Bool { permitted && owner.session == session }
        func list(page: Int, session: ProjectEditSession) async throws -> ProjectStoryTemplatePage {
            listCalls.append(page); sessions.append(session)
            if let listError { throw listError }
            let value: ProjectStoryTemplatePage
            if let prepared = pages[page] { value = prepared }
            else { value = try .decode(.object(["rows": .array(rows), "total": .number(Decimal(rows.count))]), accountID: session.accountID, page: page) }
            if holdNextList {
                holdNextList = false; heldPage = value
                return try await withCheckedThrowingContinuation { pendingList = $0 }
            }
            return value
        }
        func detail(id: MemberPlayTemplateID, session: ProjectEditSession) async throws -> ProjectStoryTemplateDraft {
            detailCalls.append(id.rawValue); sessions.append(session)
            if let detailError { throw detailError }
            let raw = try XCTUnwrap(details[id.rawValue])
            let value = try ProjectStoryTemplateDraft.decode(raw, accountID: session.accountID, requestedID: id)
            if holdNextDetail {
                holdNextDetail = false; heldDraft = value
                return try await withCheckedThrowingContinuation { pendingDetail = $0 }
            }
            return value
        }
        func releaseDetail(error: Error? = nil) {
            guard let continuation = pendingDetail, let value = heldDraft else { return }
            pendingDetail = nil; heldDraft = nil
            if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: value) }
        }
        func releaseList(error: Error? = nil) {
            guard let continuation = pendingList, let value = heldPage else { return }
            pendingList = nil; heldPage = nil
            if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: value) }
        }
    }
    @MainActor private struct Context {
        let owner: Owner, storage: Storage, source: Source, baseline: ProjectEditDraft, editor: ProjectEditModel
        var chapterID: String { editor.draft.chapters[0].id }
    }
    private func fields(id: Int = 41, title: String = "Saved game", album: Bool = false) throws -> ProjectEditJSON {
        var value: [String: ProjectEditJSON] = ["id": .number(Decimal(id)), "memberId": .number(7), "draftStatus": .number(0),
            "delFlag": .number(0), "title": .string(title), "validationMethod": .number(0), "answer": .string("private answer"), "revision": .string("r1")]
        if album {
            let config: [String: ProjectEditJSON] = ["schemaVersion": .number(1), "album": .object(["enabled": .bool(true), "images": .array([
                .object(["url": .string("https://example.com/e%CC%81.jpg?x=1"), "line": .string("e\u{301}")]),
                .object(["url": .string("https://example.com/second.jpg")])])])]
            value["advancedConfigJson"] = .string(String(decoding: try JSONEncoder().encode(config), as: UTF8.self))
        }
        return .object(value)
    }
    private func context(album: Bool = false, change: ((inout ProjectEditDraft) -> Void)? = nil) async throws -> Context {
        let owner = Owner(), storage = Storage(), raw = try fields(album: album)
        let source = Source(owner: owner, rows: [raw], details: [41: raw])
        var draft = ProjectEditSyntheticFixtures.draft(); let chapter = draft.chapters[0]
        draft.preserved["publishMode"] = .string("pro")
        draft.chapters[0].blocks = [.init(kind: .text, content: chapter.description), .init(kind: .node, nodeID: chapter.nodes[0].id), .init(kind: .text, content: "Tail")]
        var material = ProjectEditNode(); material.name = "Keep pending"; material.description = "e\u{301}"; material.templateID = 77
        material.longitude = "121.5"; material.latitude = "31.2"
        material.localMetadata = ["future": .object(["null": .null])]; draft.pendingMaterials = [.init(node: material)]
        change?(&draft)
        let editor = makeEditor(draft, owner: owner, storage: storage, source: source)
        await editor.load(); editor.saveLocal()
        return .init(owner: owner, storage: storage, source: source, baseline: draft, editor: editor)
    }
    private func makeEditor(_ draft: ProjectEditDraft, owner: Owner, storage: Storage, source: (any ProjectStoryTemplateReading)?) -> ProjectEditModel {
        .init(coordinator: .init(initial: .init(draft: draft), service: ProjectEditSyntheticService(), store: .init(storage: storage),
                                storyTemplateSource: source, currentSession: { owner.session }))
    }
    private func saved(_ c: Context) throws -> ProjectEditDraft {
        guard case .ready(let value) = ProjectEditLocalStore(storage: c.storage).load(session: try XCTUnwrap(c.owner.session), identity: try XCTUnwrap(c.editor.coordinator.identity), baseline: c.baseline) else { throw ProjectEditError.persistenceUnavailable }
        return value.draft
    }
    private func open(_ c: Context, _ controller: ProjectStoryTemplatePresentation, before anchor: String? = nil) async throws -> ProjectStoryTemplatePresentation.Opening {
        let opening = try XCTUnwrap(controller.capture(chapterID: c.chapterID, before: anchor))
        let task = try XCTUnwrap(controller.open(opening)); await task.value
        XCTAssertEqual(controller.state, .ready); return opening
    }
    private func select(_ controller: ProjectStoryTemplatePresentation, _ opening: ProjectStoryTemplatePresentation.Opening) async throws -> ProjectStoryTemplatePresentation.Review {
        let row = try XCTUnwrap(controller.rows.first), task = try XCTUnwrap(controller.select(row, original: opening))
        await task.value; return try XCTUnwrap(controller.review)
    }
    private func waitForHeldDetail(_ source: Source) async {
        for _ in 0..<200 where source.pendingDetail == nil { await Task.yield() }
        XCTAssertNotNil(source.pendingDetail)
    }
    func testRealModelOrdinaryAndAlbumFirstMiddleEndSaveAndColdReopenExactly() async throws {
        for album in [false, true] {
            for index in [0, 1, 3] {
                let c = try await context(album: album), original = c.editor.draft, old = try XCTUnwrap(original.chapters[0].blocks)
                let controller = ProjectStoryTemplatePresentation(editor: c.editor)
                let opening = try await open(c, controller, before: index < old.count ? old[index].id : nil)
                let review = try await select(controller, opening), preview = ProjectEditPendingMaterials.exactData(review.draft)
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), ProjectEditPendingMaterials.exactData(original))
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(try saved(c)), ProjectEditPendingMaterials.exactData(original))
                let task = try XCTUnwrap(controller.apply(review, original: opening))
                XCTAssertNil(controller.apply(review, original: opening), "Double tap cannot start a second adoption")
                await task.value
                XCTAssertNil(controller.opening); XCTAssertEqual(controller.state, .idle)
                XCTAssertEqual(c.source.detailCalls, [41, 41], "Review and apply each reread owner detail")
                let result = try saved(c), blocks = try XCTUnwrap(result.chapters[0].blocks), inserted = blocks[index]
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(result), preview)
                XCTAssertEqual(blocks.filter { $0.id != inserted.id }, old)
                XCTAssertEqual(inserted.kind, album ? .dream : .node)
                XCTAssertEqual(result.chapters[0].nodes.count, original.chapters[0].nodes.count + (album ? 0 : 1))
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(result.pendingMaterials), ProjectEditPendingMaterials.exactData(original.pendingMaterials))
                c.editor.leave()
                let cold = makeEditor(c.baseline, owner: c.owner, storage: c.storage, source: c.source)
                await cold.load(); XCTAssertTrue(cold.canRestore); cold.restore()
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(cold.draft), preview)
                XCTAssertEqual(c.source.listCalls, [1]); XCTAssertEqual(c.source.detailCalls, [41, 41])
            }
        }
    }
    func testActualSyntheticClientMultipartListDetailAndApplyReachRealLocalPersistence() async throws {
        for templateID in [811, 812] {
            let c = try await context(), storage = Storage(), session = try XCTUnwrap(c.owner.session)
            let source = try ProjectStoryTemplateSynthetic(session: session, currentSession: { c.owner.session })
            let editor = makeEditor(c.baseline, owner: c.owner, storage: storage, source: source)
            await editor.load(); editor.saveLocal()
            let controller = ProjectStoryTemplatePresentation(editor: editor)
            let opening = try XCTUnwrap(controller.capture(chapterID: editor.draft.chapters[0].id, before: editor.draft.chapters[0].blocks?[1].id))
            let load = try XCTUnwrap(controller.open(opening)); await load.value
            XCTAssertEqual(controller.state, .ready); XCTAssertEqual(controller.rows.map(\.id.rawValue), [811, 812])
            XCTAssertEqual(source.listCount, 1); XCTAssertEqual(source.detailCount, 0)
            let row = try XCTUnwrap(controller.rows.first { $0.id.rawValue == templateID })
            let resolve = try XCTUnwrap(controller.select(row, original: opening)); await resolve.value
            let review = try XCTUnwrap(controller.review), exact = ProjectEditPendingMaterials.exactData(review.draft)
            XCTAssertEqual(source.detailCount, 1); XCTAssertEqual(editor.draft.chapters[0].blocks?.count, 3)
            let apply = try XCTUnwrap(controller.apply(review, original: opening)); await apply.value
            XCTAssertNil(controller.opening); XCTAssertEqual(source.listCount, 1); XCTAssertEqual(source.detailCount, 2)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(editor.draft), exact)
            let inserted = try XCTUnwrap(editor.draft.chapters[0].blocks?[1])
            XCTAssertEqual(inserted.kind, templateID == 812 ? .dream : .node)
            if templateID == 812 {
                let images = try XCTUnwrap(inserted.sourceFields?["images"]?.array)
                XCTAssertEqual(images.count, 2)
                XCTAssertEqual(Array(try XCTUnwrap(images[0].object?["url"]?.text).utf8), Array("https://example.com/synthetic/story/e%CC%81.jpg?version=1".utf8))
                XCTAssertEqual(Array(try XCTUnwrap(images[0].object?["line"]?.text).utf8), Array("Synthetic e\u{301} caption".utf8))
                XCTAssertEqual(editor.draft.chapters[0].nodes, c.baseline.chapters[0].nodes)
            } else {
                XCTAssertEqual(editor.draft.chapters[0].nodes.last?.templateID, 811)
                XCTAssertEqual(inserted.sourceFields, ["locationRequired": .bool(false)])
            }
            editor.leave()
            let cold = makeEditor(c.baseline, owner: c.owner, storage: storage, source: source)
            await cold.load(); XCTAssertTrue(cold.canRestore); cold.restore()
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(cold.draft), exact)
            XCTAssertEqual(source.listCount, 1); XCTAssertEqual(source.detailCount, 2)
        }
    }
    func testBrowseBackAndCancelNeverPersistOrMutateAndPreviewCopyIsImmutable() async throws {
        let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
        let before = ProjectEditPendingMaterials.exactData(c.editor.draft), storage = c.storage.data, writes = c.storage.writeCount
        let opening = try await open(c, controller), first = try await select(controller, opening)
        var copy = first.draft; copy.chapters[0].blocks?.removeAll(); copy.pendingMaterials = []
        XCTAssertNotEqual(ProjectEditPendingMaterials.exactData(copy), ProjectEditPendingMaterials.exactData(first.draft))
        controller.back(opening); XCTAssertNil(controller.review); XCTAssertEqual(controller.state, .ready)
        XCTAssertNil(controller.apply(first, original: opening))
        let second = try await select(controller, opening); XCTAssertNotEqual(first.id, second.id)
        controller.close(opening)
        XCTAssertNil(controller.apply(second, original: opening)); XCTAssertNil(controller.opening)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before); XCTAssertEqual(c.storage.data, storage)
        XCTAssertEqual(c.storage.writeCount, writes); XCTAssertEqual(c.source.detailCalls, [41, 41])
    }
    func testRefreshAndReopenReadFreshListAndDetailWithoutReusingPriorReview() async throws {
        let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
        let opening = try await open(c, controller), review = try await select(controller, opening)
        let updated = try fields(id: 42, title: "New draft")
        c.source.rows = [updated]; c.source.details[42] = updated
        let refresh = try XCTUnwrap(controller.refresh(opening)); await refresh.value
        XCTAssertNil(controller.review); XCTAssertEqual(controller.rows.map(\.id.rawValue), [42])
        XCTAssertNil(controller.apply(review, original: opening))
        let fresh = try await select(controller, opening); XCTAssertEqual(fresh.source.row.id.rawValue, 42)
        controller.close(opening)
        let reopened = try await open(c, controller); XCTAssertNotEqual(reopened.id, opening.id)
        XCTAssertNil(controller.review); _ = try await select(controller, reopened)
        XCTAssertEqual(c.source.listCalls, [1, 1, 1]); XCTAssertEqual(c.source.detailCalls, [41, 42, 42])
    }
    func testChangedSourceWithSameVisibleRowCannotApplyOldReview() async throws {
        let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
        let opening = try await open(c, controller), review = try await select(controller, opening), storage = c.storage.data
        var changed = try XCTUnwrap(c.source.details[41]?.object); changed["answer"] = .string("new invisible answer")
        c.source.details[41] = .object(changed)
        let task = try XCTUnwrap(controller.apply(review, original: opening)); await task.value
        XCTAssertEqual(controller.state, .changed); XCTAssertNil(controller.review)
        XCTAssertEqual(c.storage.data, storage); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 3)
        XCTAssertNil(controller.apply(review, original: opening))
    }
    func testChangedRowOwnerPublishedDeletedAndArrivalDetailCannotCreateReview() async throws {
        for (key, value) in [("title", ProjectEditJSON.string("Renamed")), ("memberId", .number(8)), ("draftStatus", .number(1)), ("delFlag", .number(1)), ("validationMethod", .number(4)), ("validationMethod", .number(5))] {
            let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor), opening = try await open(c, controller)
            var fields = try XCTUnwrap(c.source.details[41]?.object); fields[key] = value; c.source.details[41] = .object(fields)
            let before = c.storage.data, task = try XCTUnwrap(controller.select(try XCTUnwrap(controller.rows.first), original: opening)); await task.value
            XCTAssertEqual(controller.state, .failed); XCTAssertNil(controller.review); XCTAssertEqual(c.storage.data, before)
            XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 3)
        }
    }
    func testCapturedGapRejectsDeletionReorderContentChangeABAAndSameByteSetter() async throws {
        for mutation in 0..<9 {
            let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
            let original = c.editor.draft, anchor = try XCTUnwrap(original.chapters[0].blocks?[1].id)
            let opening = try XCTUnwrap(controller.capture(chapterID: c.chapterID, before: anchor))
            switch mutation {
            case 0: c.editor.draft.chapters[0].blocks?.remove(at: 1)
            case 1: c.editor.draft.chapters[0].blocks?.swapAt(0, 1)
            case 2: c.editor.draft.chapters[0].blocks?[1].content = "Replacement"
            case 3: c.editor.draft.chapters[0].blocks?.reverse(); c.editor.draft = original
            case 4: c.editor.draft.chapters[0].blocks?.remove(at: 1); c.editor.draft = original
            case 5: c.editor.draft.chapters[0].blocks?[1].content = "Temporary"; c.editor.draft = original
            case 6: c.editor.draft = original
            case 7: c.editor.draft.pendingMaterials?[0].node.name = "Changed pending"
            default: c.editor.draft.name = "Changed title"
            }
            let after = ProjectEditPendingMaterials.exactData(c.editor.draft), storage = c.storage.data
            XCTAssertFalse(controller.isCurrent(opening)); XCTAssertNil(controller.open(opening)); XCTAssertNil(controller.opening)
            XCTAssertEqual(c.source.listCalls.count, 0); XCTAssertEqual(c.storage.data, storage)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), after)
        }
    }
    func testReviewedGapCannotApplyAfterContentABAOrSameByteReplacement() async throws {
        for sameBytes in [false, true] {
            let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
            let opening = try await open(c, controller), review = try await select(controller, opening), original = c.editor.draft
            if !sameBytes { c.editor.draft.chapters[0].blocks?[0].content = "Temporary" }
            c.editor.draft = original
            let storage = c.storage.data
            XCTAssertNil(controller.apply(review, original: opening)); XCTAssertNil(controller.binding(opening).wrappedValue)
            XCTAssertEqual(c.source.detailCalls, [41]); XCTAssertEqual(c.storage.data, storage)
        }
    }
    func testAccountEpochViewerConfigurationNamespaceSourceIdentityAndPermissionChangesRetireOpening() async throws {
        for mutation in 0..<8 {
            let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
            let opening = try await open(c, controller), review = try await select(controller, opening), old = try XCTUnwrap(c.owner.session)
            switch mutation {
            case 0: c.owner.session = try .init(accountID: 8, epoch: old.epoch, storageNamespace: old.storageNamespace)
            case 1: c.owner.session = try .init(accountID: 7, epoch: old.epoch + 1, storageNamespace: old.storageNamespace)
            case 2: c.owner.session = try .init(accountID: 7, epoch: old.epoch, storageNamespace: old.storageNamespace, viewerRevision: 1)
            case 3: c.owner.session = try .init(accountID: 7, epoch: old.epoch, storageNamespace: old.storageNamespace, configurationRevision: 1)
            case 4: c.owner.session = try .init(accountID: 7, epoch: old.epoch, storageNamespace: "another-deployment")
            case 5: c.source.identity = UUID()
            case 6: c.source.permitted = false
            default: c.owner.session = nil
            }
            let storage = c.storage.data
            XCTAssertFalse(controller.isCurrent(opening)); XCTAssertNil(controller.apply(review, original: opening))
            XCTAssertNil(controller.refresh(opening)); XCTAssertNil(controller.binding(opening).wrappedValue)
            XCTAssertEqual(c.source.detailCalls, [41]); XCTAssertEqual(c.storage.data, storage)
        }
    }
    func testUnconfiguredDeniedAndDifferentEditorCannotOpenCapturedSource() async throws {
        let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
        let opening = try XCTUnwrap(controller.capture(chapterID: c.chapterID, before: nil))
        let other = makeEditor(c.baseline, owner: c.owner, storage: Storage(), source: c.source); await other.load()
        XCTAssertNil(ProjectStoryTemplatePresentation(editor: other).open(opening))
        let unconfigured = makeEditor(c.baseline, owner: c.owner, storage: Storage(), source: nil); await unconfigured.load()
        XCTAssertNil(ProjectStoryTemplatePresentation(editor: unconfigured).capture(chapterID: c.chapterID, before: nil))
        c.source.permitted = false; XCTAssertNil(controller.capture(chapterID: c.chapterID, before: nil))
        XCTAssertEqual(c.source.listCalls.count, 0); XCTAssertEqual(c.source.detailCalls.count, 0)
    }
    func testHeldDetailAfterCloseSuccessOrErrorCannotPopulateReopenedChooser() async throws {
        for fails in [false, true] {
            let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor), opening = try await open(c, controller)
            c.source.holdNextDetail = true
            let task = try XCTUnwrap(controller.select(try XCTUnwrap(controller.rows.first), original: opening)); await waitForHeldDetail(c.source)
            controller.close(opening); let fresh = try await open(c, controller), storage = c.storage.data
            c.source.releaseDetail(error: fails ? ProjectStoryTemplateError.sourceChanged : nil); await task.value
            XCTAssertEqual(controller.opening?.id, fresh.id); XCTAssertEqual(controller.state, .ready); XCTAssertNil(controller.review)
            XCTAssertEqual(c.storage.data, storage); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 3)
        }
    }
    func testHeldApplyCompletionAfterCloseOwnerChangeABAOrPermissionRevocationNeverSaves() async throws {
        for mutation in 0..<5 {
            for fails in [false, true] {
                let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
                let opening = try await open(c, controller), review = try await select(controller, opening)
                c.source.holdNextDetail = true
                let task = try XCTUnwrap(controller.apply(review, original: opening)); await waitForHeldDetail(c.source)
                XCTAssertNil(controller.apply(review, original: opening))
                switch mutation {
                case 0: controller.close(opening)
                case 1: c.owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "story-template-app")
                case 2:
                    let original = c.editor.draft; c.editor.draft.chapters[0].blocks?[1].content = "Temporary"; c.editor.draft = original
                case 3: c.source.permitted = false
                default: c.source.identity = UUID()
                }
                let before = ProjectEditPendingMaterials.exactData(c.editor.draft), storage = c.storage.data
                c.source.releaseDetail(error: fails ? ProjectStoryTemplateError.invalidResponse : nil); await task.value
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before); XCTAssertEqual(c.storage.data, storage)
                XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 3)
            }
        }
    }
    func testHeldListAfterCloseAndReopenCannotOverwriteNewRowsOnSuccessOrFailure() async throws {
        for fails in [false, true] {
            let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
            let opening = try XCTUnwrap(controller.capture(chapterID: c.chapterID, before: nil)); c.source.holdNextList = true
            let task = try XCTUnwrap(controller.open(opening))
            for _ in 0..<200 where c.source.pendingList == nil { await Task.yield() }; XCTAssertNotNil(c.source.pendingList)
            controller.close(opening); c.source.rows = [try fields(id: 42, title: "Fresh")]
            let fresh = try await open(c, controller)
            c.source.releaseList(error: fails ? ProjectStoryTemplateError.invalidResponse : nil); await task.value
            XCTAssertEqual(controller.opening?.id, fresh.id); XCTAssertEqual(controller.rows.map(\.id.rawValue), [42]); XCTAssertEqual(controller.state, .ready)
        }
    }
    func testFailedPersistenceRetainsSameCandidateAndRetryCannotInsertTwice() async throws {
        for album in [false, true] {
            let c = try await context(album: album), controller = ProjectStoryTemplatePresentation(editor: c.editor)
            let opening = try await open(c, controller), review = try await select(controller, opening)
            let storage = c.storage.data, before = ProjectEditPendingMaterials.exactData(c.editor.draft), preview = ProjectEditPendingMaterials.exactData(review.draft)
            c.storage.failWrites = true
            let failed = try XCTUnwrap(controller.apply(review, original: opening)); await failed.value
            XCTAssertEqual(controller.state, .saveFailed); XCTAssertEqual(controller.review?.id, review.id)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before); XCTAssertEqual(c.storage.data, storage)
            c.storage.failWrites = false
            let retry = try XCTUnwrap(controller.apply(review, original: opening)); XCTAssertNil(controller.apply(review, original: opening)); await retry.value
            XCTAssertNil(controller.opening); XCTAssertEqual(ProjectEditPendingMaterials.exactData(try saved(c)), preview)
            XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 4); XCTAssertEqual(c.source.detailCalls, [41, 41, 41])
            XCTAssertNil(controller.apply(review, original: opening))
        }
    }
    func testRefreshRetriesReadFailureAndClearsStaleReview() async throws {
        let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
        let opening = try await open(c, controller); _ = try await select(controller, opening)
        c.source.listError = ProjectStoryTemplateError.invalidResponse
        let failed = try XCTUnwrap(controller.refresh(opening)); await failed.value
        XCTAssertEqual(controller.state, .failed); XCTAssertTrue(controller.rows.isEmpty); XCTAssertNil(controller.review)
        c.source.listError = nil
        let retry = try XCTUnwrap(controller.refresh(opening)); await retry.value
        XCTAssertEqual(controller.state, .ready); XCTAssertEqual(controller.rows.count, 1); XCTAssertEqual(c.source.listCalls, [1, 1, 1])
    }
    func testFailedDetailOrChangedApplyCanSelectAnotherValidRowWithoutRefresh() async throws {
        for failedApply in [false, true] {
            let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor), secondRaw = try fields(id: 42, title: "Other game")
            c.source.rows.append(secondRaw); c.source.details[42] = secondRaw
            let opening = try await open(c, controller), storage = c.storage.data
            if failedApply {
                let review = try await select(controller, opening)
                c.source.detailError = ProjectStoryTemplateError.sourceChanged
                let failure = try XCTUnwrap(controller.apply(review, original: opening)); await failure.value
                XCTAssertEqual(controller.state, .changed)
            } else {
                c.source.detailError = ProjectStoryTemplateError.invalidResponse
                let failure = try XCTUnwrap(controller.select(try XCTUnwrap(controller.rows.first), original: opening)); await failure.value
                XCTAssertEqual(controller.state, .failed)
            }
            XCTAssertNil(controller.review); XCTAssertEqual(controller.rows.count, 2)
            c.source.detailError = nil
            let second = try XCTUnwrap(controller.rows.first { $0.id.rawValue == 42 })
            let retry = try XCTUnwrap(controller.select(second, original: opening)); await retry.value
            XCTAssertEqual(controller.state, .ready); XCTAssertEqual(controller.review?.source.row.id.rawValue, 42)
            XCTAssertEqual(c.source.listCalls, [1]); XCTAssertEqual(c.storage.data, storage)
            XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 3)
        }
    }
    func testPaginationAppendsUniqueRowsAndRejectsRepeatedIDsAcrossPages() async throws {
        for repeats in [false, true] {
            let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
            let firstRows = try (1...20).map { try fields(id: $0, title: "Draft \($0)") }
            c.source.pages[1] = try .decode(.object(["rows": .array(firstRows), "total": .number(21)]), accountID: 7, page: 1)
            c.source.pages[2] = try .decode(.object(["rows": .array([try fields(id: repeats ? 1 : 21)]), "total": .number(21)]), accountID: 7, page: 2)
            let opening = try await open(c, controller); XCTAssertEqual(controller.nextPage, 2)
            let more = try XCTUnwrap(controller.loadMore(opening)); XCTAssertNil(controller.loadMore(opening)); await more.value
            XCTAssertEqual(c.source.listCalls, [1, 2]); XCTAssertNil(controller.nextPage)
            XCTAssertEqual(controller.state, repeats ? .failed : .ready)
            XCTAssertEqual(controller.rows.count, repeats ? 0 : 21); XCTAssertEqual(c.source.detailCalls.count, 0)
        }
    }
    func testRealModelCapacity199To200AndFullCaptureDenial() async throws {
        let c = try await context(change: { draft in
            draft.chapters[0].nodes = []; draft.chapters[0].blocks = (0..<199).map { .init(kind: .text, content: "Block \($0)") }
        }), controller = ProjectStoryTemplatePresentation(editor: c.editor)
        let opening = try await open(c, controller), review = try await select(controller, opening)
        let task = try XCTUnwrap(controller.apply(review, original: opening)); await task.value
        XCTAssertEqual(try saved(c).chapters[0].blocks?.count, 200)
        XCTAssertNil(controller.capture(chapterID: c.chapterID, before: nil)); XCTAssertEqual(c.source.listCalls, [1])
    }
    func testTypedPendingHostAdoptsTemplateWithoutConsumingPendingAndRetiredHostCannotAct() async throws {
        let c = try await context(), pending = ProjectEditPendingController(model: c.editor)
        let pendingBytes = ProjectEditPendingMaterials.exactData(c.editor.draft.pendingMaterials), materialID = try XCTUnwrap(c.editor.draft.pendingMaterials?.first?.id)
        pending.chooseChapter(c.chapterID, target: pending.capture(materialID))
        let destination = try XCTUnwrap(pending.destination), scope = try XCTUnwrap(pending.captureStoryMediaScope(destination))
        let controller = ProjectStoryTemplatePresentation(editor: c.editor, host: .pending(scope))
        let opening = try await open(c, controller), review = try await select(controller, opening)
        let task = try XCTUnwrap(controller.apply(review, original: opening)); await task.value
        XCTAssertTrue(pending.isCurrent(destination)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft.pendingMaterials), pendingBytes)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try saved(c).pendingMaterials), pendingBytes)
        let next = try await open(c, controller), second = try await select(controller, next), storage = c.storage.data
        pending.close(destination)
        XCTAssertNil(controller.apply(second, original: next)); XCTAssertEqual(c.storage.data, storage)
        XCTAssertNil(controller.capture(chapterID: c.chapterID, before: nil))
        XCTAssertNil(ProjectStoryTemplatePresentation(editor: c.editor, host: .unavailable).capture(chapterID: c.chapterID, before: nil))
    }
    func testDiscardOrLeavingEditorRetiresReviewWithoutFurtherReads() async throws {
        for leave in [false, true] {
            let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
            let opening = try await open(c, controller), review = try await select(controller, opening)
            if leave { c.editor.leave() } else { c.editor.discard() }
            let storage = c.storage.data
            XCTAssertNil(controller.apply(review, original: opening)); XCTAssertFalse(controller.isCurrent(opening))
            XCTAssertEqual(c.source.detailCalls, [41]); XCTAssertEqual(c.storage.data, storage)
        }
    }
    func testNarrowApplyDoesNotHaveASecondPointerWriteToFail() async throws {
        for album in [false, true] {
            let c = try await context(album: album), controller = ProjectStoryTemplatePresentation(editor: c.editor)
            let opening = try await open(c, controller), review = try await select(controller, opening)
            let attempts = c.storage.writeAttempts
            c.storage.failAtAttempt = attempts + 2
            let task = try XCTUnwrap(controller.apply(review, original: opening)); await task.value
            XCTAssertNil(controller.opening); XCTAssertEqual(c.storage.writeAttempts, attempts + 1)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), ProjectEditPendingMaterials.exactData(review.draft))
            c.storage.failAtAttempt = nil
            // Do not call old editor.leave(): that would overwrite disk and mask failure.
            let cold = makeEditor(c.baseline, owner: c.owner, storage: c.storage, source: c.source)
            await cold.load(); XCTAssertTrue(cold.canRestore); cold.restore()
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(cold.draft), ProjectEditPendingMaterials.exactData(review.draft))
        }
    }
    func testFailedSingleCommitCancelColdRestoreKeepsOldDraftAndRetryIsOneInsert() async throws {
        for album in [false, true] {
            for cancel in [false, true] {
                let c = try await context(album: album), controller = ProjectStoryTemplatePresentation(editor: c.editor)
                let opening = try await open(c, controller), review = try await select(controller, opening)
                let old = c.editor.draft, bytes = c.storage.data, attempts = c.storage.writeAttempts
                c.storage.failAtAttempt = attempts + 1
                let failed = try XCTUnwrap(controller.apply(review, original: opening)); await failed.value
                XCTAssertEqual(controller.state, .saveFailed); XCTAssertEqual(c.storage.data, bytes)
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), ProjectEditPendingMaterials.exactData(old))
                c.storage.failAtAttempt = nil
                let expected: ProjectEditDraft
                if cancel { controller.close(opening); expected = old }
                else {
                    let retry = try XCTUnwrap(controller.apply(review, original: opening))
                    XCTAssertNil(controller.apply(review, original: opening)); await retry.value
                    XCTAssertEqual(c.storage.writeAttempts, attempts + 2)
                    expected = review.draft; XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 4)
                }
                let cold = makeEditor(c.baseline, owner: c.owner, storage: c.storage, source: c.source)
                await cold.load(); XCTAssertTrue(cold.canRestore); cold.restore()
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(cold.draft), ProjectEditPendingMaterials.exactData(expected))
                XCTAssertEqual(cold.draft.pendingMaterials, old.pendingMaterials)
            }
        }
    }
    func testUnsavedDirtyAndUnreadablePreimagesCloseBeforeAnyListAndNeverFallback() async throws {
        for mutation in 0..<3 {
            let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
            if mutation == 0 { c.storage.data.removeAll() }
            if mutation == 1 { c.editor.draft.name = "Not saved yet" }
            if mutation == 2 { c.storage.failReads = true }
            let opening = try XCTUnwrap(controller.capture(chapterID: c.chapterID, before: nil))
            let bytes = c.storage.data, attempts = c.storage.writeAttempts
            XCTAssertNil(controller.open(opening)); XCTAssertNil(controller.opening)
            XCTAssertEqual(controller.state, .saveRequired); XCTAssertEqual(c.source.listCalls, [])
            XCTAssertEqual(c.storage.data, bytes); XCTAssertEqual(c.storage.writeAttempts, attempts)
            c.storage.failReads = false; c.editor.saveLocal()
            let refreshed = try XCTUnwrap(controller.capture(chapterID: c.chapterID, before: nil))
            let load = try XCTUnwrap(controller.open(refreshed)); await load.value
            XCTAssertEqual(controller.state, .ready); XCTAssertEqual(c.source.listCalls, [1])
        }
    }
    func testConflictingPointerAfterReviewPreventsCommitWithoutSwitchingAnyDraft() async throws {
        let c = try await context(), controller = ProjectStoryTemplatePresentation(editor: c.editor)
        let opening = try await open(c, controller), review = try await select(controller, opening)
        let identity = try XCTUnwrap(c.editor.coordinator.identity)
        let pointer = try XCTUnwrap(c.storage.data.first(where: {
            guard let stored = try? JSONDecoder().decode(ProjectEditDraftIdentity.self, from: $0.value) else { return false }
            return stored == identity && stored.draftUUID.flatMap(UUID.init(uuidString:)) != nil
        })?.key)
        c.storage.data[pointer] = try JSONEncoder().encode(ProjectEditDraftIdentity())
        let bytes = c.storage.data, attempts = c.storage.writeAttempts
        let task = try XCTUnwrap(controller.apply(review, original: opening)); await task.value
        XCTAssertEqual(controller.state, .saveFailed); XCTAssertEqual(c.storage.data, bytes)
        XCTAssertEqual(c.storage.writeAttempts, attempts); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 3)
    }

}
#endif
