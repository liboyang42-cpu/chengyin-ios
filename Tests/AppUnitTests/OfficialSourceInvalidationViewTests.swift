import XCTest
import SwiftUI
import UIKit
import Combine
@testable import Questify

@MainActor private final class DisplayInvalidationReader: OfficialEventReading {
    let invalidationSignal: OfficialReadInvalidationSignal? = OfficialReadInvalidationSignal()
    var scope = UUID()
    var isConfigured = true, isAuthenticated = true, isOfflineExample = true
    var calls = 0, rowID = 71
    var pauseNext = false
    var onRead: (() -> Void)?, onPause: (() -> Void)?
    private var pending: CheckedContinuation<[OfficialEvent], Error>?
    private var pendingRows: [OfficialEvent] = []
    var isPaused: Bool { pending != nil }
    func invalidateSource() { scope = UUID(); invalidationSignal?.invalidate() }
    func rows() throws -> [OfficialEvent] {
        try JSONDecoder().decode([OfficialEvent].self, from: Data("[{\"id\":\(rowID),\"title\":\"Synthetic recruitment\",\"status\":2,\"fulfillmentPolicy\":\"REQUIRED_FULFILLMENT\"}]".utf8))
    }
    func finish() { let value = pending; pending = nil; value?.resume(returning: pendingRows) }
    func events(city: String?) async throws -> [OfficialEvent] {
        calls += 1; onRead?(); let rows = try rows()
        if pauseNext {
            pauseNext = false; pendingRows = rows
            return try await withCheckedThrowingContinuation { pending = $0; onPause?() }
        }
        return rows
    }
    func detail(id: Int) async throws -> OfficialEvent { try XCTUnwrap(rows().first) }
    func myEvents() async throws -> [OfficialEvent] { try rows() }
    func partyInbox() async throws -> [OfficialPartyInvite] { throw APIError.notConfigured }
    func canPublish() async throws -> Bool { false }
    func myPublished() async throws -> OfficialPublished { throw APIError.notConfigured }
    func broadcastStats(id: Int) async throws -> OfficialBroadcastStats { throw APIError.notConfigured }
}
@MainActor private final class DisplayInvalidationWire: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(#"{"code":200,"data":{"id":71,"title":"Synthetic detail","status":3}}"#.utf8), 200)
    }
}
@MainActor private final class DisplayInvalidationVault: AppTokenStorage {
    func read() throws -> String? { nil }
    func write(_ token: String) throws { XCTFail("Presentation invalidation saved a credential") }
    func clear() throws { XCTFail("Presentation invalidation removed a credential") }
}
@MainActor private final class DisplayInvalidationMerchant: MerchantReading {
    @Published var isConfigured = true
    @Published var isSignedIn = true
    @Published var sessionRevision: UInt64 = 1
    var membershipReads = 0
    func merchantAccess() async throws -> MerchantAccess {
        membershipReads += 1
        return try JSONDecoder().decode(MerchantAccess.self, from: Data(#"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":[]}"#.utf8))
    }
    func merchantDashboard(access: MerchantAccess) async throws -> MerchantDashboard { throw APIError.notConfigured }
    func merchantTodo(access: MerchantAccess) async throws -> MerchantTodo { throw APIError.notConfigured }
    func merchantEvents(access: MerchantAccess) async throws -> [MerchantEvent] { throw APIError.notConfigured }
    func merchantOrders(access: MerchantAccess, filter: MerchantOrderFilter) async throws -> [MerchantOrder] { throw APIError.notConfigured }
    func merchantProjects(access: MerchantAccess) async throws -> MerchantProjectPage { throw APIError.notConfigured }
}

@MainActor final class OfficialSourceInvalidationViewTests: XCTestCase {
    private func root(_ wire: DisplayInvalidationWire) throws -> AppCompositionRoot {
        let suite = "official-invalidation-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let vault = DisplayInvalidationVault()
        let reviewed = try ReviewedAppDeployment(market: .china, baseURL: "https://example.test/native",
            approvedBaseURLs: [.china: ["https://example.test/native"]], verifiedCapabilities: [],
            bundleIdentifier: "test.questify.invalidation", realm: "synthetic", reads: [.officialPublicEventCatalogAndDetail])
        return AppCompositionRoot(deployment: .reviewed(reviewed), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    private func select(_ root: AppCompositionRoot) throws -> OfficialPublicEventReadSource {
        let review = try XCTUnwrap(root.reviewed)
        let source = try OfficialPublicEventReadSource(baseURL: XCTUnwrap(review.regional.apiConfiguration).baseURL, namespace: review.storageScope.service)
        root.officialPublicEventReadSelection.select(source); return source
    }
    private func coop(_ reader: DisplayInvalidationReader) -> MerchantCoopCenterModel {
        let content = MerchantContentService(configuration: nil, transport: DisplayInvalidationWire(), currentSession: { nil })
        return .init(content: content, official: reader, focusTopicID: nil, now: { Date(timeIntervalSince1970: 1_783_211_400) })
    }
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testObserverStopsReceivingAfterDisappearAndCanBindAgain() {
        let reader = DisplayInvalidationReader(), observer = OfficialReadInvalidationObserver()
        observer.bind(reader); let original = observer.revision
        reader.invalidateSource(); XCTAssertNotEqual(observer.revision, original)
        observer.stop(); let stopped = observer.revision
        reader.invalidateSource(); XCTAssertEqual(observer.revision, stopped); XCTAssertFalse(observer.isBound(to: reader))
        observer.bind(reader); reader.invalidateSource(); XCTAssertNotEqual(observer.revision, stopped)
    }
    func testOldReaderCannotInvalidateNewBoundOwnerOrDuplicateSubscriptions() {
        let old = DisplayInvalidationReader(), next = DisplayInvalidationReader(), observer = OfficialReadInvalidationObserver()
        observer.bind(old); observer.bind(next); observer.bind(next)
        let current = observer.revision
        old.invalidateSource(); XCTAssertEqual(observer.revision, current)
        var updates = 0
        let token = observer.objectWillChange.sink { updates += 1 }
        next.invalidateSource(); XCTAssertNotEqual(observer.revision, current); XCTAssertEqual(updates, 1)
        withExtendedLifetime(token) {}
    }
    func testSourceDoesNotRetainDisappearedObserver() {
        let reader = DisplayInvalidationReader()
        var observer: OfficialReadInvalidationObserver? = .init()
        observer?.bind(reader); weak var released = observer; observer = nil
        XCTAssertNil(released); reader.invalidateSource()
    }
    func testNormalSessionPublishesSourceRevocationWithoutAuthenticationOrSessionChange() throws {
        let wire = DisplayInvalidationWire(), root = try self.root(wire)
        let source = try select(root), session = root.makeSession()
        let revision = session.sessionRevision, scope = session.officialEventReader.scope
        XCTAssertTrue(session.officialEventReader.invalidationSignal === root.officialPublicEventReadSelection.invalidations)
        var publications = 0
        let token = session.objectWillChange.sink { publications += 1 }
        source.revoke()
        XCTAssertEqual(publications, 1); XCTAssertEqual(session.sessionRevision, revision)
        XCTAssertNotEqual(session.officialEventReader.scope, scope)
        XCTAssertNil(session.account); XCTAssertTrue(wire.requests.isEmpty)
        withExtendedLifetime(token) {}
    }
    func testDefaultNilSourceAndRemovedSourceDoNotStartReads() throws {
        let wire = DisplayInvalidationWire(), root = try self.root(wire), session = root.makeSession()
        XCTAssertNil(root.officialPublicEventReadSelection.source)
        let observer = OfficialReadInvalidationObserver(); observer.bind(session.officialEventReader)
        let source = try select(root), selected = observer.revision
        root.officialPublicEventReadSelection.select(nil)
        XCTAssertNotEqual(observer.revision, selected)
        let removed = observer.revision; source.revoke()
        XCTAssertEqual(observer.revision, removed); XCTAssertTrue(wire.requests.isEmpty); XCTAssertNil(session.account)
    }
    func testMountedSharedScreenRetiresLoadedContentAfterRealSourceRevocation() async throws {
        let wire = DisplayInvalidationWire(), root = try self.root(wire)
        let source = try select(root), session = root.makeSession()
        let shown = expectation(description: "Original loaded detail is presented")
        let retired = expectation(description: "Original detail leaves the mounted shared screen")
        var didShow = false, didRetire = false
        let host = UIHostingController(rootView: OfficialReadScreen(reader: session.officialEventReader,
            load: { try await session.officialEventReader.detail(id: 71) }) { event in
                Text(verbatim: event.title)
                    .onAppear { if !didShow { didShow = true; shown.fulfill() } }
                    .onDisappear { if didShow && !didRetire { didRetire = true; retired.fulfill() } }
            })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [shown], timeout: 2)
        guard didShow else { return }
        source.revoke()
        await fulfillment(of: [retired], timeout: 2)
        XCTAssertEqual(wire.requests.count, 1, "Revoked reload must stop at the original composition gate")
        XCTAssertNil(session.account)
    }
    func testMerchantAdapterForwardsInvalidationAndRetiresItsOriginalScope() async throws {
        let official = DisplayInvalidationReader(), merchant = DisplayInvalidationMerchant()
        let adapter = MerchantOfficialRecruitmentReader(merchant: merchant, official: official, sourceIsCurrent: { true })
        XCTAssertTrue(adapter.invalidationSignal === official.invalidationSignal)
        _ = try await adapter.events(city: nil)
        let previous = adapter.scope
        official.invalidateSource()
        XCTAssertNotEqual(adapter.scope, previous); XCTAssertFalse(adapter.isAuthenticated)
        do { _ = try await adapter.events(city: nil); XCTFail("Retired adapter read a replacement source") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(merchant.membershipReads, 1); XCTAssertEqual(official.calls, 1)
    }
    func testMerchantReentryUsesFreshAdapterAndRechecksOriginalMembership() async throws {
        let official = DisplayInvalidationReader(), merchant = DisplayInvalidationMerchant()
        let old = MerchantOfficialRecruitmentReader(merchant: merchant, official: official, sourceIsCurrent: { true })
        _ = try await old.events(city: nil)
        official.invalidateSource()
        let reopened = MerchantOfficialRecruitmentReader(merchant: merchant, official: official, sourceIsCurrent: { true })
        let rows = try await reopened.events(city: nil)
        XCTAssertEqual(rows.map(\.id), [71]); XCTAssertEqual(merchant.membershipReads, 2)
        XCTAssertFalse(old.isAuthenticated); XCTAssertTrue(reopened.isAuthenticated)
    }
    func testCoopClearsOnlyOfficialRowsImmediatelyAndWaitsForExplicitRetry() async throws {
        let official = DisplayInvalidationReader(), model = coop(official)
        let loaded = expectation(description: "Official recruitment rows loaded")
        let token = model.$events.filter { !$0.isEmpty }.first().sink { _ in loaded.fulfill() }
        model.loadEvents(); await fulfillment(of: [loaded], timeout: 2)
        XCTAssertEqual(model.events.map(\.id), [71])
        let routes = model.routes.map(\.id), routesLoading = model.routesLoading, routesIssue = model.routesIssue
        official.invalidateSource()
        XCTAssertTrue(model.events.isEmpty); XCTAssertFalse(model.eventsLoading); XCTAssertEqual(model.eventsIssue, .failed(nil))
        XCTAssertEqual(model.routes.map(\.id), routes); XCTAssertEqual(model.routesLoading, routesLoading); XCTAssertEqual(model.routesIssue, routesIssue)
        XCTAssertEqual(official.calls, 1)
        withExtendedLifetime(token) {}
    }
    func testCoopOldPendingReplyCannotClearOrReplaceNewSourceRows() async throws {
        let official = DisplayInvalidationReader(), model = coop(official)
        official.pauseNext = true
        let started = expectation(description: "Old recruitment read is suspended")
        official.onPause = { started.fulfill() }
        model.loadEvents(); await fulfillment(of: [started], timeout: 2)
        guard official.isPaused else { official.finish(); XCTFail(); return }
        official.invalidateSource(); official.rowID = 72
        let loaded = expectation(description: "Replacement recruitment read completes")
        let token = model.$events.filter { $0.first?.id == 72 }.first().sink { _ in loaded.fulfill() }
        model.loadEvents(); await fulfillment(of: [loaded], timeout: 2)
        let overwritten = expectation(description: "Old reply must not overwrite replacement rows")
        overwritten.isInverted = true
        let oldMutation = model.$events.dropFirst().filter { $0.map(\.id) != [72] }.sink { _ in overwritten.fulfill() }
        official.finish()
        await fulfillment(of: [overwritten], timeout: 0.1)
        XCTAssertEqual(model.events.map(\.id), [72]); XCTAssertFalse(model.eventsLoading); XCTAssertNil(model.eventsIssue)
        withExtendedLifetime((token, oldMutation)) {}
    }
    func testCoopQueuedOldIntentDoesNotReadAfterSourceInvalidation() async {
        let official = DisplayInvalidationReader(), model = coop(official)
        let read = expectation(description: "No old queued source read")
        read.isInverted = true; official.onRead = { read.fulfill() }
        model.loadEvents(); official.invalidateSource()
        await fulfillment(of: [read], timeout: 0.1)
        XCTAssertEqual(official.calls, 0); XCTAssertTrue(model.events.isEmpty); XCTAssertFalse(model.eventsLoading)
    }
    func testCoopModelDoesNotRemainAliveInSourceObservers() {
        let official = DisplayInvalidationReader()
        var model: MerchantCoopCenterModel? = coop(official)
        weak var released = model; model = nil
        XCTAssertNil(released); official.invalidateSource(); XCTAssertEqual(official.calls, 0)
    }
    func testEveryConsumerKeepsOriginalOwnerGatesAndRetiresOnlyOfficialDisplay() throws {
        let screen = try source("App/OfficialEventComponents.swift")
        XCTAssertTrue(screen.contains("guard loadedKey != key else { return }"))
        XCTAssertTrue(screen.contains("value = nil; issue = nil; copy = nil; loadedKey = nil"))
        XCTAssertTrue(screen.contains("guard !Task.isCancelled, generation == operation, key == captured else { return }"))
        let square = try source("App/SquareXcxPostCard.swift")
        XCTAssertTrue(square.contains("if loadedScope == reader.scope, !items.isEmpty"))
        XCTAssertTrue(square.contains("if loadingScope != reader.scope")); XCTAssertTrue(square.contains("generation == loadGeneration"))
        let detail = try source("App/OfficialEventDetailView.swift")
        XCTAssertTrue(detail.contains("reader.scope == officialScope, visit == detailVisit"))
        let browser = try source("App/OfficialEventsBrowserView.swift")
        XCTAssertTrue(browser.contains("if publisherScope != reader.scope"))
        let observer = try source("App/OfficialReadInvalidationObserver.swift")
        for forbidden in ["URLRequest", "Task {", "logout(", "loginWith", ".select("] { XCTAssertFalse(observer.contains(forbidden), forbidden) }
    }
}
