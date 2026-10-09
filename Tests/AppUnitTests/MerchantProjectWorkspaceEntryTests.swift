import XCTest
import SwiftUI
@testable import Questify

@MainActor final class MerchantProjectWorkspaceEntryTests: XCTestCase {
    @MainActor private final class Reader: MerchantReading {
        @Published var sessionRevision: UInt64 = 1
        var isConfigured = true, isSignedIn = true
        func merchantAccess() async throws -> MerchantAccess { try Fixture.access() }
        func merchantDashboard(access: MerchantAccess) async throws -> MerchantDashboard { throw URLError(.unsupportedURL) }
        func merchantTodo(access: MerchantAccess) async throws -> MerchantTodo { throw URLError(.unsupportedURL) }
        func merchantEvents(access: MerchantAccess) async throws -> [MerchantEvent] { [] }
        func merchantOrders(access: MerchantAccess, filter: MerchantOrderFilter) async throws -> [MerchantOrder] { [] }
        func merchantProjects(access: MerchantAccess) async throws -> MerchantProjectPage { try Fixture.page() }
    }
    @MainActor private final class Service: MerchantContentServing {
        var scope = UUID(), isConfigured = true, isAuthenticated = true
        let permitsWrites = false
        var readCount = 0, performCount = 0, reconcileCount = 0, retryCount = 0, hold = false, fail = false
        var merchant = 31, topic: MerchantContentValue = .integer(70)
        var returnedQuery: MerchantContentQuery?, returnedScope: UUID?
        let journal = MerchantContentMemoryPendingStorage()
        var continuation: CheckedContinuation<Void, Never>?
        func load(_ query: MerchantContentQuery) async throws -> MerchantContentSnapshot {
            readCount += 1
            if hold { await withCheckedContinuation { continuation = $0 } }
            if fail { throw URLError(.notConnectedToInternet) }
            return try Fixture.detail(query: returnedQuery ?? query, scope: returnedScope ?? scope, merchant: merchant, topic: topic)
        }
        func resume() { let pending = continuation; continuation = nil; hold = false; pending?.resume() }
        func perform(_ command: MerchantContentCommand, baseline: MerchantContentSnapshot) async throws -> MerchantContentReceipt { performCount += 1; throw MerchantContentFailure.disabled }
        func pending() throws -> [MerchantContentPendingRecord] { try journal.records() }
        func reconcile(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt { reconcileCount += 1; throw MerchantContentFailure.disabled }
        func retryStation(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt { retryCount += 1; throw MerchantContentFailure.disabled }
    }
    private enum Fixture {
        static func access(id: Int = 31, allowed: Bool = true) throws -> MerchantAccess {
            let raw = "{\"active\":true,\"merchant\":{\"id\":\(id)},\"roleCode\":\"MERCHANT_MANAGER\",\"permissions\":\(allowed ? "[\"merchant:project:manage\"]" : "[]")}"
            return try JSONDecoder().decode(MerchantAccess.self, from: Data(raw.utf8))
        }
        static func page(biz: String = "topic", duplicates: Bool = false) throws -> MerchantProjectPage {
            let row = "{\"id\":70,\"bizType\":\"\(biz)\",\"title\":\"Synthetic project\",\"stateText\":\"Example\"}"
            return try JSONDecoder().decode(MerchantProjectPage.self, from: Data("{\"rows\":[\(row)\(duplicates ? "," + row : "")],\"total\":\(duplicates ? 2 : 1)}".utf8))
        }
        static func detail(query: MerchantContentQuery = .project(topicID: 70), scope: UUID = UUID(), merchant: Int = 31, topic: MerchantContentValue = .integer(70)) throws -> MerchantContentSnapshot {
            .init(query: query, scope: scope, access: try access(id: merchant), value: .object(["topic": .object(["id": topic]), "host": .object([:])]), observedAt: Date())
        }
    }
    @MainActor private final class Harness {
        let reader = Reader(), service = Service(), model = MerchantProjectWorkspacePresentation()
        var context: MerchantProjectWorkspaceContext { .init(reader: reader, service: service) }
        func snapshot(biz: String = "topic", duplicates: Bool = false, merchant: Int = 31, allowed: Bool = true) throws -> MerchantProjectWorkspaceSnapshot {
            .init(page: try Fixture.page(biz: biz, duplicates: duplicates), access: try Fixture.access(id: merchant, allowed: allowed), context: context)
        }
        func open(_ snapshot: MerchantProjectWorkspaceSnapshot) throws -> MerchantProjectWorkspacePresentation.Selection {
            model.openSummary(project: snapshot.page.rows[0], snapshot: snapshot, context: context, permit: model.permit(snapshot: snapshot))
            return try XCTUnwrap(model.selection)
        }
    }
    func testCurrentTopicSelectionOpensExactExistingWorkspaceWithoutAnyRequest() throws {
        let h = Harness(), snapshot = try h.snapshot(); let selected = try h.open(snapshot)
        h.model.openWorkspace(selected, snapshot: snapshot, context: h.context, sourceFresh: true)
        let route = try XCTUnwrap(h.model.route)
        XCTAssertEqual(route.topicID, 70); XCTAssertEqual(route.merchantID, 31)
        XCTAssertTrue(h.model.workspaceIsCurrent(route, snapshot: snapshot, context: h.context, sourceFresh: true))
        XCTAssertEqual(h.service.readCount, 0); XCTAssertEqual(h.service.performCount, 0)
    }
    func testActivityAndUnknownTypeKeepSummaryWithoutInventingWorkspace() throws {
        for biz in ["activity", "TOPIC", "unknown"] {
            let h = Harness(), snapshot = try h.snapshot(biz: biz); let selected = try h.open(snapshot)
            XCTAssertEqual(selected.project.bizType, biz)
            h.model.openWorkspace(selected, snapshot: snapshot, context: h.context, sourceFresh: true)
            XCTAssertNil(h.model.route)
        }
    }
    func testMissingSuppliedServiceNeverCreatesDestination() throws {
        let h = Harness(); let context = MerchantProjectWorkspaceContext(reader: h.reader, service: nil)
        let snapshot = MerchantProjectWorkspaceSnapshot(page: try Fixture.page(), access: try Fixture.access(), context: context)
        h.model.openSummary(project: snapshot.page.rows[0], snapshot: snapshot, context: context, permit: h.model.permit(snapshot: snapshot))
        let selected = try XCTUnwrap(h.model.selection)
        h.model.openWorkspace(selected, snapshot: snapshot, context: context, sourceFresh: true); XCTAssertNil(h.model.route)
    }
    func testDuplicateRowsCannotChooseAmbiguousIdentity() throws {
        let h = Harness(), snapshot = try h.snapshot(duplicates: true)
        h.model.openSummary(project: snapshot.page.rows[0], snapshot: snapshot, context: h.context, permit: h.model.permit(snapshot: snapshot))
        XCTAssertNil(h.model.selection)
    }
    func testAbsentProjectPermissionDoesNotOpenEvenSummary() throws {
        let h = Harness(), snapshot = try h.snapshot(allowed: false)
        h.model.openSummary(project: snapshot.page.rows[0], snapshot: snapshot, context: h.context, permit: h.model.permit(snapshot: snapshot))
        XCTAssertNil(h.model.selection)
    }
    func testOldRenderedPermitFailsAfterRetirementAndSameReaderReturn() throws {
        let h = Harness(), snapshot = try h.snapshot(); let old = h.model.permit(snapshot: snapshot)
        h.model.retire(); h.model.activate()
        h.model.openSummary(project: snapshot.page.rows[0], snapshot: snapshot, context: h.context, permit: old)
        XCTAssertNil(h.model.selection)
    }
    func testOldSelectionCannotOpenAfterReloadGenerationRetirement() throws {
        let h = Harness(), snapshot = try h.snapshot(); let selected = try h.open(snapshot)
        h.model.invalidate(); h.model.openWorkspace(selected, snapshot: snapshot, context: h.context, sourceFresh: true)
        XCTAssertNil(h.model.route)
    }
    func testReplacedSnapshotWithIdenticalRowsCannotReuseOldSelection() throws {
        let h = Harness(), snapshot = try h.snapshot(); let selected = try h.open(snapshot), newer = try h.snapshot()
        XCTAssertFalse(h.model.selectionIsCurrent(selected, snapshot: newer, context: h.context))
        h.model.openWorkspace(selected, snapshot: newer, context: h.context, sourceFresh: true); XCTAssertNil(h.model.route)
    }
    func testFailedOrInProgressReloadCannotOpenWorkspaceFromRetainedSummary() throws {
        let h = Harness(), snapshot = try h.snapshot(); let selected = try h.open(snapshot)
        XCTAssertFalse(h.model.canOpenWorkspace(selected, snapshot: snapshot, context: h.context, sourceFresh: false))
        h.model.openWorkspace(selected, snapshot: snapshot, context: h.context, sourceFresh: false); XCTAssertNil(h.model.route)
    }
    func testOwnerRevisionServiceScopeAndConfigurationChangesDenyDestination() throws {
        for change in 0..<5 {
            let h = Harness(), snapshot = try h.snapshot(); let selected = try h.open(snapshot)
            switch change { case 0: h.reader.sessionRevision += 1
            case 1: h.service.scope = UUID()
            case 2: h.reader.isSignedIn = false
            case 3: h.service.isAuthenticated = false
            default: h.service.isConfigured = false }
            h.model.openWorkspace(selected, snapshot: snapshot, context: h.context, sourceFresh: true); XCTAssertNil(h.model.route)
        }
    }
    func testReplacedReaderOrServiceCannotUseOldSnapshot() throws {
        let h = Harness(), snapshot = try h.snapshot(); let selected = try h.open(snapshot)
        for context in [MerchantProjectWorkspaceContext(reader: Reader(), service: h.service), MerchantProjectWorkspaceContext(reader: h.reader, service: Service())] {
            h.model.openWorkspace(selected, snapshot: snapshot, context: context, sourceFresh: true); XCTAssertNil(h.model.route)
        }
    }
    func testOldSummaryBindingCannotDismissReopenedSummary() throws {
        let h = Harness(), snapshot = try h.snapshot(); let old = try h.open(snapshot), binding = h.model.summaryBinding()
        h.model.closeSummary(id: old.id); let newer = try h.open(snapshot)
        binding.wrappedValue = nil
        XCTAssertNil(binding.wrappedValue); XCTAssertEqual(h.model.selection?.id, newer.id)
    }
    func testOldWorkspaceBindingCannotPopReopenedWorkspace() throws {
        let h = Harness(), snapshot = try h.snapshot(); let selected = try h.open(snapshot)
        h.model.openWorkspace(selected, snapshot: snapshot, context: h.context, sourceFresh: true)
        let old = h.model.workspaceBinding(); old.wrappedValue = nil
        h.model.openWorkspace(selected, snapshot: snapshot, context: h.context, sourceFresh: true)
        let newID = try XCTUnwrap(h.model.route).id; old.wrappedValue = nil
        XCTAssertNil(old.wrappedValue); XCTAssertEqual(h.model.route?.id, newID)
    }
    func testDepartureRetiresPresentedRouteWithoutWrites() throws {
        let h = Harness(), snapshot = try h.snapshot(); let selected = try h.open(snapshot)
        h.model.openWorkspace(selected, snapshot: snapshot, context: h.context, sourceFresh: true)
        let route = try XCTUnwrap(h.model.route); h.model.retire()
        XCTAssertFalse(h.model.workspaceIsCurrent(route, snapshot: snapshot, context: h.context, sourceFresh: true))
        XCTAssertNil(h.model.selection); XCTAssertNil(h.model.route); XCTAssertEqual(h.service.performCount, 0)
    }
    func testFreshWorkspaceMustMatchExactRequestedStoreTopicAndQuery() throws {
        XCTAssertTrue(MerchantProjectWorkspacePresentation.matches(snapshot: try Fixture.detail(), topicID: 70, merchantID: 31))
        for snapshot in [try Fixture.detail(merchant: 32), try Fixture.detail(topic: .integer(71)), try Fixture.detail(topic: .string("70")), try Fixture.detail(topic: .null), try Fixture.detail(query: .players(topicID: 70))] {
            XCTAssertFalse(MerchantProjectWorkspacePresentation.matches(snapshot: snapshot, topicID: 70, merchantID: 31))
        }
    }
    func testRetiredQueuedLoadDoesNotReadExistingService() async throws {
        let source = Service(); var current = false
        let model = MerchantContentViewModel(service: source, query: .project(topicID: 70), focusedTopicID: 70, focusedMerchantID: 31, projectEntryIsCurrent: { current })
        await model.load(); XCTAssertEqual(source.readCount, 0); XCTAssertNil(model.coordinator.snapshot)
        current = true; await model.load(); XCTAssertEqual(source.readCount, 1); XCTAssertNotNil(model.coordinator.snapshot)
    }
    func testSuspendedReadCannotPublishAfterEntryRetirement() async throws {
        let source = Service(); source.hold = true; var current = true
        let model = MerchantContentViewModel(service: source, query: .project(topicID: 70), focusedTopicID: 70, focusedMerchantID: 31, projectEntryIsCurrent: { current })
        let task = Task { await model.load() }
        for _ in 0..<100 { if source.continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(source.continuation); current = false; source.resume(); await task.value
        XCTAssertNil(model.coordinator.snapshot); XCTAssertEqual(source.readCount, 1); XCTAssertEqual(source.performCount, 0)
    }
    func testUnrelatedDocumentWithNoEntryGuardKeepsOriginalLoadBehavior() async throws {
        let source = Service(); let model = MerchantContentViewModel(service: source, query: .project(topicID: 70))
        await model.load(); XCTAssertNotNil(model.coordinator.snapshot); XCTAssertEqual(source.readCount, 1)
    }

    private func pendingRecord(merchant: Int) -> MerchantContentPendingRecord {
        .init(storageScope: "synthetic-workspace", accountID: 1, merchantID: merchant, target: "game:80", action: "STATION_READY",
              station: .init(activityID: 80, nodeID: 62, expectedRevision: 3, requestID: "synthetic-request", action: .ready))
    }
    func testWrongStorePendingProjectionCannotPresentRecoverOrPerformAndJournalRemainsExact() async throws {
        let source = Service(); source.merchant = 32
        let record = pendingRecord(merchant: 32); try source.journal.insert(record)
        let model = MerchantContentViewModel(service: source, query: .project(topicID: 70), focusedTopicID: 70, focusedMerchantID: 31, projectEntryIsCurrent: { true })
        await model.load()
        XCTAssertFalse(model.projectPresentationIsCurrent); XCTAssertFalse(model.projectActionsAreCurrent)
        XCTAssertNil(model.coordinator.snapshot); XCTAssertNil(model.coordinator.loadedScope)
        let command = MerchantContentCommand.reviewCircle(topicID: 70, scope: "MERCHANT")
        let frozen = MerchantContentReview(id: UUID(), command: command, baseline: try Fixture.detail(scope: source.scope, merchant: 32), scope: source.scope)
        model.prepare(command); await model.confirm(frozen); await model.reconcile(); await model.retryStation()
        XCTAssertNil(model.coordinator.review); XCTAssertEqual(source.performCount, 0)
        XCTAssertEqual(source.reconcileCount, 0); XCTAssertEqual(source.retryCount, 0)
        XCTAssertEqual(try source.journal.records(), [record]); XCTAssertEqual(source.readCount, 1)
    }
    func testWrongTopicQueryAndResponseScopeAreRejectedByActualModel() async throws {
        for change in 0..<4 {
            let source = Service()
            switch change { case 0: source.topic = .integer(71)
            case 1: source.topic = .string("70")
            case 2: source.returnedQuery = .players(topicID: 70)
            default: source.returnedScope = UUID() }
            let model = MerchantContentViewModel(service: source, query: .project(topicID: 70), focusedTopicID: 70, focusedMerchantID: 31, projectEntryIsCurrent: { true })
            await model.load(); await model.reconcile(); await model.retryStation()
            XCTAssertFalse(model.projectPresentationIsCurrent); XCTAssertNil(model.coordinator.snapshot)
            XCTAssertEqual(source.reconcileCount, 0); XCTAssertEqual(source.retryCount, 0)
        }
    }
    func testSuspendedWrongStoreReadCannotAcceptPendingProjection() async throws {
        let source = Service(); source.hold = true
        let record = pendingRecord(merchant: 32); try source.journal.insert(record)
        let model = MerchantContentViewModel(service: source, query: .project(topicID: 70), focusedTopicID: 70, focusedMerchantID: 31, projectEntryIsCurrent: { true })
        let task = Task { await model.load() }
        for _ in 0..<100 { if source.continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(source.continuation); source.merchant = 32; source.resume(); await task.value
        XCTAssertFalse(model.projectPresentationIsCurrent); XCTAssertNil(model.coordinator.snapshot)
        await model.reconcile(); await model.retryStation()
        XCTAssertEqual(source.reconcileCount, 0); XCTAssertEqual(source.retryCount, 0)
        XCTAssertEqual(try source.journal.records(), [record])
    }
    func testMatchingPendingProjectionKeepsExistingExplicitRecoveryBehavior() async throws {
        let source = Service(), record = pendingRecord(merchant: 31); try source.journal.insert(record)
        let model = MerchantContentViewModel(service: source, query: .project(topicID: 70), focusedTopicID: 70, focusedMerchantID: 31, projectEntryIsCurrent: { true })
        await model.load()
        XCTAssertTrue(model.projectPresentationIsCurrent); XCTAssertTrue(model.projectActionsAreCurrent); XCTAssertTrue(model.coordinator.locked)
        await model.reconcile(); await model.retryStation()
        XCTAssertEqual(source.reconcileCount, 1); XCTAssertEqual(source.retryCount, 1)
        XCTAssertEqual(try source.journal.records(), [record])
    }
    func testRejectedResponseCanOnlyRecoverThroughAnotherExplicitMatchingLoad() async throws {
        let source = Service(); source.merchant = 32
        let model = MerchantContentViewModel(service: source, query: .project(topicID: 70), focusedTopicID: 70, focusedMerchantID: 31, projectEntryIsCurrent: { true })
        await model.load(); XCTAssertFalse(model.projectPresentationIsCurrent)
        source.merchant = 31; XCTAssertFalse(model.projectPresentationIsCurrent)
        await model.load(); XCTAssertTrue(model.projectPresentationIsCurrent); XCTAssertTrue(model.projectActionsAreCurrent)
        XCTAssertEqual(source.readCount, 2); XCTAssertEqual(source.performCount, 0)
    }
    func testMissingFocusedIdentityFailsClosedOnlyForGuardedEntry() async throws {
        let source = Service()
        let model = MerchantContentViewModel(service: source, query: .project(topicID: 70), projectEntryIsCurrent: { true })
        await model.load(); XCTAssertFalse(model.projectPresentationIsCurrent); XCTAssertNil(model.coordinator.snapshot)
        let ordinary = MerchantContentViewModel(service: source, query: .project(topicID: 70))
        source.merchant = 32; await ordinary.load()
        XCTAssertTrue(ordinary.projectPresentationIsCurrent); XCTAssertEqual(ordinary.coordinator.snapshot?.access.merchantID, 32)
    }
}
