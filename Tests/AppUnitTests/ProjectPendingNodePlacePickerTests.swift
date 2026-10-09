import XCTest
@testable import Questify

@MainActor final class ProjectPendingNodePlacePickerTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "pending-place") }
    private final class Reader: SearchMapReading {
        var isConfigured = true, isAuthenticated = true, isOfflineExample = false
        var scope = UUID(), manualAreaRevision: UInt64 = 0, requests = 0
        var rows: [SearchMapCityNode] = []
        var paused = false
        var continuation: CheckedContinuation<[SearchMapCityNode], Error>?
        func selectManualArea(_ area: RoamSearchArea?) { manualAreaRevision += 1 }
        func cityNodes(_ q: CityNodeSearchQuery) async throws -> [SearchMapCityNode] { requests += 1; if paused { return try await withCheckedThrowingContinuation { continuation = $0 } }; return rows }
        func finish() { continuation?.resume(returning: rows); continuation = nil }
        func categories() async throws -> [DiscoveryCategory] { throw APIError.notConfigured }
        func search(_ q: GlobalSearchQuery) async throws -> GlobalSearchResults { throw APIError.notConfigured }
        func citySearch(_ q: CityNodeSearchQuery) async throws -> CityNodeSearchResults { throw APIError.notConfigured }
        func nearby(area: RoamSearchArea) async throws -> SearchMapNearbyResults { throw APIError.notConfigured }
        func cityNode(id: Int) async throws -> SearchMapCityNode { throw APIError.notConfigured }
        func merchant(id: Int) async throws -> RoamMerchantDetail { throw APIError.notConfigured }
    }
    private struct Fixture {
        let owner: Owner, model: ProjectEditModel, pending: ProjectEditPendingController, destination: ProjectEditPendingController.Destination
        let reader: Reader, picker: ProjectNodePlacePickerController, storage: ProjectEditMemoryStorage
    }
    private func setup() async throws -> Fixture {
        let owner = Owner(), reader = Reader(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        var node = draft.chapters[0].nodes[0]; node.id = "pending"; node.name = "Keep pending name"; node.localMetadata["unknown"] = .string("keep")
        draft.pendingMaterials = [.init(node: node, kind: .place)]
        reader.rows = [try JSONDecoder().decode(SearchMapCityNode.self, from: Data(#"{"poiId":7,"name":"Chosen label","lat":32.25,"lng":122.5}"#.utf8))]
        let initial = ProjectEditSnapshot(scope: .full, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); let pending = ProjectEditPendingController(model: model); pending.open(pending.capture("pending"))
        let destination = try XCTUnwrap(pending.destination)
        let picker = ProjectNodePlacePickerController(model: model, reader: reader, chapterID: "", nodeID: "pending", pendingTarget: .init(controller: pending, destination: destination)); picker.setActive(true)
        return .init(owner: owner, model: model, pending: pending, destination: destination, reader: reader, picker: picker, storage: storage)
    }
    private func selected(_ f: Fixture) async throws -> ProjectNodePlacePickerController.Opening {
        f.picker.open(try XCTUnwrap(f.picker.capture())); let o = try XCTUnwrap(f.picker.opening)
        f.picker.edit(.init(latitude: "31", longitude: "121", keyword: "park"), in: o)
        await f.picker.search(o, action: f.picker.captureSearch(o)); f.picker.choose(f.reader.rows[0], in: o); return o
    }
    func testApplyChangesOnlyPendingCandidateUntilExplicitSaveMaterial() async throws {
        let f = try await setup(), before = ProjectEditPendingMaterials.exactData(f.model.draft), storage = f.storage.data, original = f.pending.candidate
        let o = try await selected(f); XCTAssertTrue(f.picker.apply(o)); XCTAssertFalse(f.picker.apply(o))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(f.model.draft), before); XCTAssertEqual(f.storage.data, storage)
        var expected = original; expected.latitude = "32.25"; expected.longitude = "122.5"; expected.address = "Chosen label"
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(f.pending.candidate), ProjectEditPendingMaterials.exactData(expected)); XCTAssertTrue(f.pending.isCurrent(f.destination))
        f.pending.save(f.destination); XCTAssertEqual(f.model.draft.pendingMaterials?[0].node.latitude, "32.25"); XCTAssertEqual(f.model.draft.pendingMaterials?[0].kind, .place)
    }
    func testPickerCancelAndParentCancelPreserveSavedMaterial() async throws {
        let f = try await setup(), before = ProjectEditPendingMaterials.exactData(f.model.draft), candidate = ProjectEditPendingMaterials.exactData(f.pending.candidate)
        let first = try await selected(f); f.picker.close(first); XCTAssertEqual(ProjectEditPendingMaterials.exactData(f.pending.candidate), candidate)
        let next = try await selected(f); XCTAssertTrue(f.picker.apply(next)); f.pending.close(f.destination)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(f.model.draft), before)
    }
    func testCandidateReplacementAndSameByteABARejectSelection() async throws {
        for aba in [true, false] {
            let f = try await setup(), o = try await selected(f); var node = f.pending.candidate; if !aba { node.name += "!" }
            f.pending.node(for: f.destination).wrappedValue = node
            XCTAssertNil(f.picker.opening); XCTAssertFalse(f.picker.apply(o)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(f.pending.candidate), ProjectEditPendingMaterials.exactData(node))
        }
    }
    func testDestinationReplacementOldBindingCannotChangeNewCandidate() async throws {
        let f = try await setup(), o = try await selected(f), binding = f.picker.binding(o)
        f.pending.close(f.destination); f.pending.open(f.pending.capture("pending")); let next = try XCTUnwrap(f.pending.destination)
        binding.wrappedValue = nil; XCTAssertFalse(f.picker.apply(o)); XCTAssertEqual(f.pending.destination?.id, next.id); XCTAssertNotEqual(next.id, f.destination.id)
    }
    func testOwnerLossReaderExpiryAndBackgroundRejectApply() async throws {
        for change in ["owner", "reader", "background"] {
            let f = try await setup(), o = try await selected(f), before = ProjectEditPendingMaterials.exactData(f.pending.candidate)
            if change == "owner" { f.owner.session = nil } else if change == "reader" { f.reader.scope = UUID() } else { f.picker.setActive(false) }
            XCTAssertFalse(f.picker.apply(o)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(f.pending.candidate), before)
        }
    }
    func testPendingChangesDuringReadDiscardLateResults() async throws {
        let f = try await setup(); f.reader.paused = true; f.picker.open(try XCTUnwrap(f.picker.capture())); let o = try XCTUnwrap(f.picker.opening)
        f.picker.edit(.init(latitude: "31", longitude: "121"), in: o); let action = f.picker.captureSearch(o), task = Task { await f.picker.search(o, action: action) }
        for _ in 0..<100 where f.reader.continuation == nil { await Task.yield() }
        f.pending.node(for: f.destination).wrappedValue = f.pending.candidate; f.reader.finish(); await task.value
        XCTAssertNil(f.picker.opening); XCTAssertTrue(f.picker.rows.isEmpty); XCTAssertNil(f.picker.selected)
    }
    func testSavedAndPendingTargetKindsCannotBeConfused() async throws {
        let f = try await setup(), saved = ProjectNodePlacePickerController(model: f.model, reader: f.reader, chapterID: "", nodeID: "pending")
        saved.setActive(true); XCTAssertNil(saved.capture()); XCTAssertNotNil(f.picker.capture())
        let capture = try XCTUnwrap(f.picker.capture()); saved.open(capture); XCTAssertNil(saved.opening)
        if case .pending = capture.snapshot {} else { XCTFail("wrong target kind") }
    }
    func testReplacementOwnerHasDistinctHostAndCannotUseCapturedPendingTarget() async throws {
        let f = try await setup(), other = try await setup()
        let captured = try XCTUnwrap(ProjectPendingNodePlaceContext(controller: f.pending, destination: f.destination).capture())
        XCTAssertFalse(captured.isCurrent(model: other.model)); XCTAssertFalse(captured.apply(f.reader.rows[0], model: other.model))
        let a = ProjectPendingNodePlaceHostIdentity(owner: ObjectIdentifier(f.model), controller: ObjectIdentifier(f.pending), reader: nil, destination: f.destination.id, node: Data("pending".utf8))
        let b = ProjectPendingNodePlaceHostIdentity(owner: ObjectIdentifier(other.model), controller: ObjectIdentifier(other.pending), reader: nil, destination: f.destination.id, node: Data("pending".utf8)); XCTAssertNotEqual(a, b)
    }
}
