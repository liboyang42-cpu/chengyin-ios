import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// The real production observer is mounted here; these tests do not drive an IME.
@MainActor final class ProjectEditExactAutosaveTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession?
        init() throws { session = try .init(accountID: 901, epoch: 1, storageNamespace: "exact-autosave") }
    }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]
        var envelopes: [ProjectEditEnvelope] = []
        var saved: XCTestExpectation?
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws {
            data[key] = value
            if let envelope = try? JSONDecoder().decode(ProjectEditEnvelope.self, from: value) {
                envelopes.append(envelope); saved?.fulfill(); saved = nil
            }
        }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private final class Mount {
        let window = UIWindow(frame: UIScreen.main.bounds)
        init(model: ProjectEditModel, appeared: @escaping () -> Void) {
            window.rootViewController = UIHostingController(rootView: Color.clear
                .modifier(ProjectEditAutosaveObservation(model: model)).onAppear(perform: appeared))
            window.makeKeyAndVisible()
        }
        func close() { window.isHidden = true; window.rootViewController = nil }
    }
    private func setup() async throws -> (ProjectEditModel, Owner, Storage) {
        let owner = try Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        draft.chapters[0].nodes[0].description = "  é\n"
        let initial = ProjectEditSnapshot(draft: draft), service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: store,
            currentSession: { owner.session }))
        await model.load(); return (model, owner, storage)
    }
    private func mount(_ model: ProjectEditModel) async -> Mount {
        let appeared = expectation(description: "Production autosave observer mounted")
        let mount = Mount(model: model) { appeared.fulfill() }
        await fulfillment(of: [appeared], timeout: 3)
        return mount
    }
    private func noSave(_ storage: Storage) async {
        let none = expectation(description: "No autosave after no-op or retired edit")
        none.isInverted = true; storage.saved = none
        await fulfillment(of: [none], timeout: 0.65)
        storage.saved = nil
    }
    private func exact(_ actual: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(actual.utf8), Array(expected.utf8), file: file, line: line)
    }

    func testMountedProductionObserverAutosavesCanonicalEquivalentDescriptionBytes() async throws {
        let (model, _, storage) = try await setup(), mount = await mount(model)
        defer { mount.close() }
        let original = model.draft
        let saved = expectation(description: "NFD-only mutation autosaved without calling changed")
        storage.saved = saved
        model.draft.chapters[0].nodes[0].description = "  e\u{301}\n"
        XCTAssertEqual(model.draft, original, "Synthesized Equatable cannot detect this mutation.")
        XCTAssertNotEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(original))
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertEqual(storage.envelopes.count, 1)
        exact(try XCTUnwrap(storage.envelopes.last).draft.chapters[0].nodes[0].description, "  e\u{301}\n")
    }

    func testNoOpAndDelayedObservationPreserveTheNewPreparedReview() async throws {
        let (model, _, storage) = try await setup(), mount = await mount(model)
        defer { mount.close() }
        model.draft.name = "Latest before Review"
        model.review() // Before SwiftUI can deliver the mutation observer.
        let prepared = try XCTUnwrap(model.confirmation), count = storage.envelopes.count
        model.observeDraftMutation()
        let same = model.draft; model.draft = same
        await noSave(storage)
        XCTAssertEqual(model.confirmation?.id, prepared.id)
        XCTAssertEqual(model.coordinator.confirmation?.id, prepared.id)
        XCTAssertTrue(model.reviewIsCurrent(prepared)); XCTAssertTrue(model.reviewLocalSaveConfirmed)
        XCTAssertEqual(storage.envelopes.count, count)
    }

    func testDebounceSavesOnlyFinalExactMutationAndSameBytesDoNotReschedule() async throws {
        let (model, _, storage) = try await setup(), mount = await mount(model)
        defer { mount.close() }
        let saved = expectation(description: "Final exact edit survives the original debounce")
        storage.saved = saved
        for value in ["  e\u{301}\n", "  e\u{301}a\n", "  e\u{301}ab\n"] {
            model.draft.chapters[0].nodes[0].description = value
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(storage.envelopes.isEmpty)
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertEqual(storage.envelopes.count, 1)
        exact(try XCTUnwrap(storage.envelopes.last).draft.chapters[0].nodes[0].description, "  e\u{301}ab\n")
        let same = model.draft; model.draft = same
        await noSave(storage)
        XCTAssertEqual(storage.envelopes.count, 1)
    }

    func testLoadRestoreAndDiscardRetireQueuedAutosaveWithoutRecreatingLocalData() async throws {
        let (model, _, storage) = try await setup()
        model.saveLocal(); let count = storage.envelopes.count
        model.draft.chapters[0].nodes[0].description = "unsaved old input"
        model.observeDraftMutation()
        await model.load(force: true); XCTAssertTrue(model.canRestore)
        model.restore(); model.observeDraftMutation()
        await noSave(storage)
        exact(model.draft.chapters[0].nodes[0].description, "  é\n")
        XCTAssertEqual(storage.envelopes.count, count)
        model.draft.chapters[0].nodes[0].description = "discarded queued input"
        model.observeDraftMutation(); model.discard(); model.observeDraftMutation()
        await noSave(storage)
        XCTAssertFalse(storage.data.values.contains { (try? JSONDecoder().decode(ProjectEditEnvelope.self, from: $0)) != nil })
        XCTAssertEqual(storage.envelopes.count, count)
    }

    func testAccountEpochAndSignOutCannotSaveOldQueuedDescription() async throws {
        for action in ["account", "epoch", "signOut"] {
            let (model, owner, storage) = try await setup()
            model.draft.chapters[0].nodes[0].description = "old scoped input"
            model.observeDraftMutation()
            switch action {
            case "account": owner.session = try .init(accountID: 902, epoch: 1, storageNamespace: "exact-autosave")
            case "epoch": owner.session = try .init(accountID: 901, epoch: 2, storageNamespace: "exact-autosave")
            default: owner.session = nil
            }
            await noSave(storage)
            XCTAssertTrue(storage.envelopes.isEmpty, action)
            XCTAssertTrue(storage.data.isEmpty, action)
        }
    }

    func testExplicitSavedMutationAcknowledgesObservationButFollowingEditStillAutosaves() async throws {
        let (model, _, storage) = try await setup()
        model.draft.chapters[0].nodes[0].description = "explicit e\u{301}"
        model.saveLocal(); model.observeDraftMutation()
        await noSave(storage)
        XCTAssertEqual(storage.envelopes.count, 1)
        let saved = expectation(description: "A later edit still schedules normally")
        storage.saved = saved
        model.draft.chapters[0].nodes[0].description = "later e\u{301}"
        model.observeDraftMutation()
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertEqual(storage.envelopes.count, 2)
        exact(try XCTUnwrap(storage.envelopes.last).draft.chapters[0].nodes[0].description, "later e\u{301}")
    }
}
