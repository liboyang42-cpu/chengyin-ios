import XCTest
import SwiftUI
import Combine
@testable import Questify

/// Buffer/write-through/lifetime tests. These do not establish native keyboard selection behavior.
@MainActor final class ProjectEditNodeDescriptionFieldTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession?
        init() throws { session = try .init(accountID: 901, epoch: 1, storageNamespace: "node-description") }
    }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]
        var saved: XCTestExpectation?
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws {
            data[key] = value; saved?.fulfill(); saved = nil
        }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private final class Standalone {
        var node = ProjectEditNode()
        var acceptsWrites = true
        var writes = 0
        var binding: Binding<ProjectEditNode> {
            .init(get: { self.node }, set: { value in
                guard self.acceptsWrites else { return }; self.writes += 1; self.node = value
            })
        }
    }
    private func setup() async throws -> (ProjectEditModel, Owner, ProjectEditLocalStore, Storage, ProjectEditSyntheticService) {
        let owner = try Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        let initial = ProjectEditSnapshot(draft: ProjectEditSyntheticFixtures.draft(product: .freeExplore))
        let service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: store, currentSession: { owner.session }))
        await model.load(); return (model, owner, store, storage, service)
    }
    private func source(_ model: ProjectEditModel) throws -> ProjectEditNodeDescriptionSource {
        let chapter = try XCTUnwrap(model.draft.chapters.first), nodeID = try XCTUnwrap(chapter.nodes.first?.id)
        let chapterBinding = model.chapter(chapter.id)
        let binding = Binding<ProjectEditNode>(get: {
            chapterBinding.wrappedValue.nodes.first { $0.id == nodeID } ?? .init()
        }, set: { next in
            var current = chapterBinding.wrappedValue
            guard let index = current.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            current.nodes[index] = next; chapterBinding.wrappedValue = current
        })
        return .init(node: binding, context: .init(model: model, sourceID: "saved:\(chapter.id):\(nodeID)",
            isCurrent: { model.fullEdit && chapterBinding.wrappedValue.nodes.contains { $0.id == nodeID } }))
    }
    private func isolatedSource(_ standalone: Standalone) async throws -> ProjectEditNodeDescriptionSource {
        let (model, _, _, _, _) = try await setup()
        return .init(node: standalone.binding, context: .init(model: model,
            sourceID: "isolated-buffer-test", isCurrent: { model.fullEdit }))
    }
    private func buffer(_ source: ProjectEditNodeDescriptionSource) -> ProjectEditNodeDescriptionBuffer {
        let value = ProjectEditNodeDescriptionBuffer(source: source); value.activate(); return value
    }
    private func exact(_ actual: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(actual.utf8), Array(expected.utf8), file: file, line: line)
    }

    func testUnscopedFieldsKeepTheOriginalBindingWithoutAnImplicitMerchantLease() {
        let standalone = Standalone()
        let fields = ProjectEditNodeFields(node: standalone.binding)
        XCTAssertNil(fields.descriptionContext); XCTAssertNil(fields.merchantDraftContext)
        fields.node.description = "  Direct e\u{301}\n"
        exact(standalone.node.description, "  Direct e\u{301}\n")
    }

    func testEachEditWritesThroughBeforeReturnAndExactParentEchoDoesNotPublishAgain() async throws {
        let (model, _, _, _, _) = try await setup(), source = try self.source(model), editor = buffer(source)
        let target = try XCTUnwrap(source.target), startingRevision = model.draftMutationRevision
        let binding = editor.binding // A native control may retain a binding through several key events.
        let original = editor.text
        var emitted: [String] = []
        let observation = editor.$text.dropFirst().sink { emitted.append($0) }
        for prefix in ["E", "Ed", "Edi", "Edit", "Edite", "Edited", "Edited "] {
            binding.wrappedValue = prefix + original
            exact(source.node.wrappedValue.description, prefix + original)
            editor.synchronize(); editor.synchronize()
            XCTAssertEqual(source.target, target)
        }
        XCTAssertEqual(emitted.count, 7)
        XCTAssertEqual(model.draftMutationRevision, startingRevision + 7)
        XCTAssertEqual(source.target?.lease, target.lease, "Normal per-key mutation revisions must not retire the editor lease.")
        withExtendedLifetime(observation) {}
    }

    func testNFCNFDWhitespaceNewlinesAndIntermediateCompositionRemainByteExact() async throws {
        let standalone = Standalone(), source = try await isolatedSource(standalone)
        let editor = buffer(source)
        for value in ["  e\u{301}\n", "  é\n", "n", "ni", "你", "你好 ", "\t你好\n👩🏽‍💻  "] {
            editor.binding.wrappedValue = value
            exact(editor.text, value); exact(standalone.node.description, value)
        }
        XCTAssertEqual(standalone.writes, 7)
    }

    func testMiddleInsertionAndDeletionPreserveUntouchedBytesAtEveryStep() async throws {
        let standalone = Standalone(); standalone.node.description = "  Left e\u{301} | Right\n"
        let editor = buffer(try await isolatedSource(standalone)), binding = editor.binding
        for insertion in ["E", "Ed", "Edi", "Edit", "Edited", "Edited ", "Edited", "Edite", "Edit", "Edi", "Ed", "E", ""] {
            let expected = "  Left e\u{301} " + insertion + "| Right\n"
            binding.wrappedValue = expected; editor.synchronize()
            exact(editor.text, expected); exact(standalone.node.description, expected)
        }
        exact(standalone.node.description, "  Left e\u{301} | Right\n")
        XCTAssertEqual(standalone.writes, 13)
    }

    func testExternalCanonicalEquivalentReplacementSynchronizesAndRetiresOldCallback() async throws {
        let standalone = Standalone(); standalone.node.description = "e\u{301}"
        let source = try await isolatedSource(standalone), editor = buffer(source)
        let old = editor.binding
        standalone.node.description = "é"
        XCTAssertEqual("e\u{301}", "é") // Swift String equality alone cannot drive this synchronization.
        XCTAssertNotEqual(Data("e\u{301}".utf8), Data("é".utf8))
        old.wrappedValue = "stale edit" // Arrives before the view's onChange callback.
        exact(editor.text, "é"); exact(standalone.node.description, "é"); XCTAssertEqual(standalone.writes, 0)
        editor.synchronize(); old.wrappedValue = "still stale"
        exact(standalone.node.description, "é")
        editor.binding.wrappedValue = "é  "
        exact(standalone.node.description, "é  ")
    }

    func testWriteThroughReadsCurrentNodeAndNeverOverwritesOtherFields() async throws {
        let (model, _, _, _, _) = try await setup(), source = try self.source(model), editor = buffer(source)
        model.draft.chapters[0].nodes[0].name = "Changed elsewhere"
        model.draft.chapters[0].nodes[0].imgUrl = "fixture:changed-elsewhere"
        editor.binding.wrappedValue = "description only"
        exact(model.draft.chapters[0].nodes[0].name, "Changed elsewhere")
        exact(model.draft.chapters[0].nodes[0].imgUrl, "fixture:changed-elsewhere")
        exact(model.draft.chapters[0].nodes[0].description, "description only")
    }

    func testSameNodeRestoreDiscardsOldLeaseEvenWhenDescriptionBytesAreIdentical() async throws {
        let (model, _, _, _, _) = try await setup(), source = try self.source(model), editor = buffer(source)
        let captured = source.target, old = editor.binding, original = source.node.wrappedValue.description
        model.saveLocal(); await model.load(force: true)
        XCTAssertTrue(model.canRestore)
        model.restore()
        exact(source.node.wrappedValue.description, original); XCTAssertNotEqual(source.target, captured)
        old.wrappedValue = "stale after restore"; editor.synchronize()
        exact(source.node.wrappedValue.description, original); XCTAssertFalse(editor.active)
        let reopened = buffer(try self.source(model)); reopened.binding.wrappedValue = "fresh edit"
        exact(model.draft.chapters[0].nodes[0].description, "fresh edit")
    }

    func testAccountEpochViewerConfigurationSignOutAndLeaveRejectQueuedEdits() async throws {
        for action in ["account", "epoch", "viewer", "configuration", "signOut", "leave"] {
            let (model, owner, _, _, _) = try await setup(), source = try self.source(model), editor = buffer(source)
            let old = editor.binding, original = ProjectEditPendingMaterials.exactData(model.draft)
            switch action {
            case "account": owner.session = try .init(accountID: 902, epoch: 1, storageNamespace: "node-description")
            case "epoch": owner.session = try .init(accountID: 901, epoch: 2, storageNamespace: "node-description")
            case "viewer": owner.session = try .init(accountID: 901, epoch: 1, storageNamespace: "node-description", viewerRevision: 1)
            case "configuration": owner.session = try .init(accountID: 901, epoch: 1, storageNamespace: "node-description", configurationRevision: 1)
            case "signOut": owner.session = nil
            default: model.leave()
            }
            old.wrappedValue = "stale \(action)"; editor.synchronize()
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), original, action)
            XCTAssertFalse(editor.active, action)
        }
    }

    func testNodeSwitchAndDisappearanceRejectOldInput() async throws {
        let standalone = Standalone(); standalone.node.description = "First"
        let source = try await isolatedSource(standalone), editor = buffer(source)
        let old = editor.binding
        standalone.node = .init(); standalone.node.description = "Second"
        old.wrappedValue = "old first edit"; editor.synchronize()
        exact(standalone.node.description, "Second"); XCTAssertEqual(standalone.writes, 0)
        let second = buffer(source), beforeHide = second.binding
        second.invalidate(); beforeHide.wrappedValue = "hidden"
        second.activate(); beforeHide.wrappedValue = "old mounted callback"
        exact(standalone.node.description, "Second")
        second.binding.wrappedValue = "New mounted edit"; exact(standalone.node.description, "New mounted edit")
    }

    func testRejectedFinalBindingSetterRollsBackTheLocalBuffer() async throws {
        let standalone = Standalone(); standalone.node.description = "Authorized source"; standalone.acceptsWrites = false
        let editor = buffer(try await isolatedSource(standalone))
        editor.binding.wrappedValue = "Rejected"
        exact(editor.text, "Authorized source"); exact(standalone.node.description, "Authorized source")
        XCTAssertEqual(standalone.writes, 0)
        standalone.acceptsWrites = true; editor.binding.wrappedValue = "Allowed"
        exact(standalone.node.description, "Allowed")
    }

    func testPendingAndStarterContextsDoNotRequireAMerchantSourceAndRetireOnClose() async throws {
        for pendingMode in [true, false] {
            let (model, _, _, _, _) = try await setup()
            XCTAssertNil(model.coordinator.merchantDraftSource)
            let source: ProjectEditNodeDescriptionSource, close: () -> Void
            if pendingMode {
                var node = ProjectEditNode(); node.name = "Pending"; model.draft.pendingMaterials = [.init(node: node)]
                let pending = ProjectEditPendingController(model: model); pending.open(pending.capture(node.id))
                let original = try XCTUnwrap(pending.destination)
                source = .init(node: pending.node(for: original), context: .init(model: model, sourceID: "pending:\(original.id)", isCurrent: { pending.isCurrent(original) }))
                close = { pending.close(original) }
            } else {
                let starter = ProjectEditStarterController(model: model)
                starter.createChapter(lease: model.captureStarterLease(), name: "New chapter")
                let original = try XCTUnwrap(starter.destination)
                source = .init(node: starter.node(for: original), context: .init(model: model, sourceID: "starter:\(original.id)", isCurrent: { starter.isCurrent(original) }))
                close = { starter.close(original) }
            }
            let editor = buffer(source), target = source.target, retained = editor.binding
            XCTAssertNotNil(source.target?.lease)
            for prefix in ["L", "Lo", "Loc", "Local"] {
                retained.wrappedValue = "  " + prefix + " candidate e\u{301}\n"
                editor.synchronize(); XCTAssertEqual(source.target, target)
                exact(source.node.wrappedValue.description, "  " + prefix + " candidate e\u{301}\n")
            }
            let old = editor.binding; close(); let closedDraft = ProjectEditPendingMaterials.exactData(model.draft)
            old.wrappedValue = "late callback"; editor.synchronize()
            XCTAssertFalse(editor.active); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), closedDraft)
        }
    }

    func testExistingDebounceAfterChangedDoesNotRetireBindingAndSaveReopenRestoreReviewStayExact() async throws {
        let (model, owner, store, storage, service) = try await setup(), source = try self.source(model), editor = buffer(source)
        let originalTarget = source.target, binding = editor.binding, first = "  Before e\u{301}\n", final = "  Before 中e\u{301}\n  "
        binding.wrappedValue = first
        let saved = expectation(description: "existing 400ms autosave completed"); storage.saved = saved
        // Exercise the existing scheduler explicitly. This is not a SwiftUI onChange/IME test.
        model.changed(); await fulfillment(of: [saved], timeout: 3)
        editor.synchronize(); XCTAssertEqual(source.target, originalTarget)
        binding.wrappedValue = final // Same control after the real existing autosave debounce.
        exact(model.draft.chapters[0].nodes[0].description, final)
        model.saveLocal(); let initial = try XCTUnwrap(model.coordinator.snapshot)
        model.leave()
        let fresh = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: store, currentSession: { owner.session }))
        await fresh.load(); XCTAssertTrue(fresh.canRestore); fresh.restore(); fresh.review()
        let review = try XCTUnwrap(fresh.confirmation)
        let reviewed = try XCTUnwrap(ProjectEditPreparedNodes(payload: review.payload).chapters?.first?.nodes?.first?.value(.description).text)
        exact(reviewed, final); XCTAssertTrue(service.submissions.isEmpty)
    }
}
