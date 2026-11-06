import XCTest
import SwiftUI
@testable import Questify

import UIKit

@MainActor private final class NearbyMapRecoveryReadProbe: RoamReading {
    var identity: RoamReadIdentity? = .init(accountID: 7001, epoch: 1)
    var isConfigured = true
    let isOfflineExample = true
    var searchArea: RoamSearchArea? = .init(coordinate: RoamCoordinate(latitude: 37.78, longitude: -122.42)!, label: "")
    var failPlaces = false
    var eventsError: APIError?
    private(set) var placeRadii: [Int] = []
    private(set) var eventRadii: [Int] = []
    var holdEvents = false
    var pendingEvents: CheckedContinuation<RoamEvents, Error>?
    private(set) var placeReads = 0
    private(set) var eventReads = 0
    private(set) var nodeIDs: [Int] = []
    func roamPlaces(radiusM: Int) async throws -> [RoamPlace] {
        placeReads += 1; placeRadii.append(radiusM)
        if failPlaces { throw APIError.httpStatus(503) }
        return try JSONDecoder().decode([RoamPlace].self, from: Data(#"[{"id":7,"type":1,"name":"Original place fixture","lat":37.78,"lng":-122.42,"tags":"walk"},{"id":8,"type":2,"name":"Original merchant point fixture","lat":37.781,"lng":-122.421,"tags":"coffee,walk"}]"#.utf8))
    }
    func roamEvents(radiusM: Int) async throws -> RoamEvents {
        eventReads += 1; eventRadii.append(radiusM)
        if let eventsError { throw eventsError }
        if holdEvents { return try await withCheckedThrowingContinuation { pendingEvents = $0 } }
        return try events()
    }
    func events() throws -> RoamEvents {
        try JSONDecoder().decode(RoamEvents.self, from: Data(#"{"items":[{"id":71,"kind":"activity","name":"Original activity fixture","lat":37.78,"lng":-122.42},{"id":81,"kind":"topic","name":"Free exploration","productType":2},{"id":82,"kind":"topic","name":"City orientation","productType":1},{"id":83,"kind":"topic","name":"Unknown topic"},{"id":84,"kind":"hangout","name":"Retired"}]}"#.utf8))
    }
    func roamNodeDetail(id: Int) async throws -> RoamNodeDetail {
        nodeIDs.append(id)
        return try JSONDecoder().decode(RoamNodeDetail.self, from: Data("{\"id\":\(id),\"name\":\"Original node read\",\"validationMethod\":4}".utf8))
    }
    func roamRouteNodes(radiusM: Int) async throws -> [RoamRouteNode] { throw APIError.notConfigured }
    func roamPlayers(radiusM: Int) async throws -> [RoamPlayer] { throw APIError.notConfigured }
    func roamExploreDay() async throws -> RoamExploreDay? { throw APIError.notConfigured }
    func roamMerchantDetail(id: Int) async throws -> RoamMerchantDetail { throw APIError.notConfigured }
}

@MainActor final class NearbyMapDiscoveryRecoveryTests: XCTestCase {
    private func waitFor(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(message); throw APIError.invalidRequest
    }
    /// Exercise the real SwiftUI control, not the reader/model method it ultimately invokes.
    private func control(_ root: NSObject, id: String? = nil, label: String? = nil,
                         seen: inout Set<ObjectIdentifier>) -> NSObject? {
        guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
        if let id, (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
        if let label, root.accessibilityLabel == label { return root }
        if let view = root as? UIView {
            for child in view.subviews {
                if let found = control(child, id: id, label: label, seen: &seen) { return found }
            }
        }
        if let children = root.accessibilityElements {
            for child in children {
                if let child = child as? NSObject, let found = control(child, id: id, label: label, seen: &seen) { return found }
            }
        }
        let count = root.accessibilityElementCount()
        if count > 0 && count < 1000 {
            for index in 0..<count {
                if let child = root.accessibilityElement(at: index) as? NSObject,
                   let found = control(child, id: id, label: label, seen: &seen) { return found }
            }
        }
        return nil
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        return control(window, id: id, seen: &seen)
    }
    private func tap(_ id: String? = nil, label: String? = nil, in window: UIWindow) async throws {
        var resolved: NSObject?
        try await waitFor("The hosted flow must expose " + (id ?? label ?? "control")) {
            var seen = Set<ObjectIdentifier>()
            resolved = self.control(window, id: id, label: label, seen: &seen)
            return resolved != nil
        }
        let target = try XCTUnwrap(resolved)
        if let button = target as? UIControl { button.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(target.accessibilityActivate(), "Actual accessibility control must activate") }
    }
    private func isEnabled(_ id: String, in window: UIWindow) -> Bool {
        guard let target = find(id, in: window) else { return false }
        if let control = target as? UIControl { return control.isEnabled }
        return !target.accessibilityTraits.contains(.notEnabled)
    }

    func testNearbyDiscoveryUsesOnlyOriginalLayerKindsAndSourceDerivedTags() async throws {
        let reader = NearbyMapRecoveryReadProbe(), model = NearbyMapDiscoveryModel()
        let sources = NearbyMapDiscoverySources(places: reader, events: reader, selectManualArea: { _ in }, destination: { _ in AnyView(EmptyView()) })
        model.load(sources: sources, query: NearbyTeamSyntheticFixtures.context, active: true)
        try await waitFor("Both independent original reads") { model.placesPhase == .loaded && model.eventsPhase == .loaded }
        XCTAssertEqual(model.visibleItems.map(\.id), ["event-activity-71", "event-topic-81", "place-7", "place-8"])
        XCTAssertEqual(NearbyMapDiscoveryFilter.options(items: model.visibleItems, layer: .place), ["活动", "主题", "walk"])
        XCTAssertEqual(NearbyMapDiscoveryFilter.options(items: model.visibleItems, layer: .shop), ["coffee", "walk"])
        XCTAssertEqual(model.visibleItems.filter(NearbyMapDiscoveryFilter(layer: .shop, tag: "coffee").includes).map(\.id), ["place-8"])
        XCTAssertNil(model.select(try XCTUnwrap(model.visibleItems.first), rendered: UUID(), active: true))
        XCTAssertNil(model.select(try XCTUnwrap(model.visibleItems.first), rendered: model.snapshotID, active: false))
    }
    func testNearbyDiscoveryFailureNilLayerAndLateOwnerResponseDoNotEraseOtherLayerOrReopenOldDetail() async throws {
        let reader = NearbyMapRecoveryReadProbe(), model = NearbyMapDiscoveryModel()
        reader.failPlaces = true
        let sources = NearbyMapDiscoverySources(places: reader, events: reader, selectManualArea: { _ in }, destination: { _ in AnyView(EmptyView()) })
        model.load(sources: sources, query: NearbyTeamSyntheticFixtures.context, active: true)
        try await waitFor("One failed and one successful independent layer") { model.placesPhase == .failed && model.eventsPhase == .loaded }
        XCTAssertEqual(model.visibleItems.count, 2)
        let selection = try XCTUnwrap(model.select(try XCTUnwrap(model.visibleItems.first), rendered: model.snapshotID, active: true))
        reader.holdEvents = true
        let noPlaces = NearbyMapDiscoverySources(places: nil, events: reader, selectManualArea: { _ in }, destination: { _ in AnyView(EmptyView()) })
        model.load(sources: noPlaces, query: NearbyTeamSyntheticFixtures.context, active: true, force: true)
        try await waitFor("Held original read") { reader.pendingEvents != nil }
        XCTAssertEqual(model.placesPhase, .unavailable)
        reader.identity = .init(accountID: 7002, epoch: 2)
        model.cancel(); reader.pendingEvents?.resume(returning: try reader.events()); reader.pendingEvents = nil
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(model.visibleItems.isEmpty); XCTAssertFalse(model.mayRemainOpen(selection))
        reader.holdEvents = false
        model.load(sources: noPlaces, query: NearbyTeamSyntheticFixtures.context, active: true)
        try await waitFor("Current original event read") { model.eventsPhase == .loaded }
        XCTAssertEqual(model.visibleItems.count, 2); XCTAssertEqual(reader.placeReads, 1)
    }
    private func revealDiscoveryRow(in window: UIWindow) async throws {
        func scroll(_ view: UIView) -> UIScrollView? {
            if let value = view as? UIScrollView, value.contentSize.height > value.bounds.height { return value }
            return view.subviews.lazy.compactMap { scroll($0) }.first
        }
        for _ in 0..<25 {
            if find("nearby.discovery.row.place-7", in: window) != nil { return }
            if let list = scroll(window) {
                let end = max(-list.adjustedContentInset.top, list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom)
                list.setContentOffset(CGPoint(x: 0, y: min(end, list.contentOffset.y + 280)), animated: false); list.layoutIfNeeded()
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Real nearby page did not expose its original place row")
    }
    /// Real SwiftUI page and original detail with memory readers, not production AppSession acceptance.
    func testHostedNearbyMapSurvivesMyTeamsFailureAndExactPOIDetailReturnsToFreshRead() async throws {
        let reader = NearbyMapRecoveryReadProbe(), coordinator = NearbyTeamSyntheticFixtures.coordinator()
        let sources = NearbyMapDiscoverySources(places: reader, events: reader, selectManualArea: { _ in }, destination: {
            AnyView(RoamItemDetailView(item: $0, reader: reader))
        })
        let host = UIHostingController(rootView: NavigationStack {
            NearbyTeamsView(coordinator: coordinator, context: NearbyTeamSyntheticFixtures.context,
                joinedTeamsStatus: .failed("team.loadFailed"), discoverySources: sources)
        }.environment(\.scenePhase, .active).environment(\.locale, Locale(identifier: "en_US")))
        let scene = try HostedNavigationSceneWindow(), window = scene.window
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        defer { scene.retire() }
        try await waitFor("Nearby still reads while my-teams source is failed") { !coordinator.teams.isEmpty && reader.placeReads > 0 && reader.eventReads > 0 }
        try await revealDiscoveryRow(in: window)
        try await tap("nearby.discovery.row.place-7", in: window)
        try await waitFor("Original node detail reads the exact POI, not merchant or array index") { reader.nodeIDs == [7] }
        let before = reader.placeReads
        try await tap(label: appLocalized("roam.close", locale: Locale(identifier: "en_US")), in: window)
        try await waitFor("Returning rereads original layer") { reader.placeReads > before }
        XCTAssertFalse(coordinator.uncertain)
    }

    private func sources(_ places: NearbyMapRecoveryReadProbe?, _ events: NearbyMapRecoveryReadProbe?) -> NearbyMapDiscoverySources {
        .init(places: places, events: events, selectManualArea: { _ in }, destination: { _ in AnyView(EmptyView()) })
    }
    private func drain() async { for _ in 0..<20 { await Task.yield() } }
    func testCancelledQueuedIntentNeverInvokesEitherOriginalReader() async {
        let reader = NearbyMapRecoveryReadProbe(), model = NearbyMapDiscoveryModel()
        model.load(sources: sources(reader, reader), query: NearbyTeamSyntheticFixtures.context, active: true)
        model.cancel()
        await drain()
        XCTAssertEqual(reader.placeReads, 0); XCTAssertEqual(reader.eventReads, 0)
        XCTAssertTrue(model.visibleItems.isEmpty)
    }
    func testReaderReplacementBeforeDispatchOnlyReadsCurrentObject() async throws {
        let first = NearbyMapRecoveryReadProbe(), current = NearbyMapRecoveryReadProbe(), model = NearbyMapDiscoveryModel()
        model.load(sources: sources(first, first), query: NearbyTeamSyntheticFixtures.context, active: true)
        model.load(sources: sources(current, current), query: NearbyTeamSyntheticFixtures.context, active: true)
        try await waitFor("Replacement original sources settle") { model.placesPhase == .loaded && model.eventsPhase == .loaded }
        XCTAssertEqual(first.placeReads, 0); XCTAssertEqual(first.eventReads, 0)
        XCTAssertEqual(current.placeReads, 1); XCTAssertEqual(current.eventReads, 1)
    }
    func testInactiveMissingIdentityAndMismatchedAreaNeverDispatch() async {
        let reader = NearbyMapRecoveryReadProbe(), model = NearbyMapDiscoveryModel()
        model.load(sources: sources(reader, reader), query: NearbyTeamSyntheticFixtures.context, active: false)
        await drain(); XCTAssertEqual(reader.placeReads + reader.eventReads, 0)
        reader.identity = nil
        model.load(sources: sources(reader, reader), query: NearbyTeamSyntheticFixtures.context, active: true)
        XCTAssertEqual(model.placesPhase, .failed); XCTAssertEqual(model.eventsPhase, .failed)
        await drain(); XCTAssertEqual(reader.placeReads + reader.eventReads, 0)
        reader.identity = .init(accountID: 7001, epoch: 1)
        reader.searchArea = .init(coordinate: RoamCoordinate(latitude: 1, longitude: 2)!, label: "Different manual area")
        model.load(sources: sources(reader, reader), query: NearbyTeamSyntheticFixtures.context, active: true)
        await drain(); XCTAssertEqual(reader.placeReads + reader.eventReads, 0)
        XCTAssertEqual(model.placesPhase, .waiting); XCTAssertTrue(model.visibleItems.isEmpty)
    }
    func testDeniedEventLayerDoesNotEraseIndependentPlacesAndRetryRestoresOnlyOriginalSources() async throws {
        let places = NearbyMapRecoveryReadProbe(), events = NearbyMapRecoveryReadProbe(), model = NearbyMapDiscoveryModel()
        events.eventsError = .httpStatus(403)
        model.load(sources: sources(places, events), query: NearbyTeamSyntheticFixtures.context, active: true)
        try await waitFor("Independent place success and actual event denial") { model.placesPhase == .loaded && model.eventsPhase == .failed }
        XCTAssertEqual(model.visibleItems.map(\.id), ["place-7", "place-8"])
        events.eventsError = nil
        model.load(sources: sources(places, events), query: NearbyTeamSyntheticFixtures.context, active: true, force: true)
        try await waitFor("Explicit retry rereads original sources") { model.placesPhase == .loaded && model.eventsPhase == .loaded }
        XCTAssertEqual(places.placeReads, 2); XCTAssertEqual(places.eventReads, 0)
        XCTAssertEqual(events.eventReads, 2); XCTAssertEqual(events.placeReads, 0)
    }
    func testExactQueryRadiusAndOriginalSnapshotCannotBeReusedAfterRefresh() async throws {
        let reader = NearbyMapRecoveryReadProbe(), model = NearbyMapDiscoveryModel()
        let query = NearbyQueryContext(latitude: 37.78, longitude: -122.42, radius: 1000)
        model.load(sources: sources(reader, reader), query: query, active: true)
        try await waitFor("First original reads") { model.placesPhase == .loaded && model.eventsPhase == .loaded }
        let rendered = model.snapshotID, item = try XCTUnwrap(model.visibleItems.first)
        let selected = try XCTUnwrap(model.select(item, rendered: rendered, active: true))
        let next = NearbyQueryContext(latitude: 37.78, longitude: -122.42, radius: 5000)
        model.load(sources: sources(reader, reader), query: next, active: true)
        XCTAssertNil(model.select(item, rendered: rendered, active: true)); XCTAssertFalse(model.mayRemainOpen(selected))
        try await waitFor("Current original radius") { model.placesPhase == .loaded && model.eventsPhase == .loaded }
        XCTAssertEqual(reader.placeRadii, [1000, 5000]); XCTAssertEqual(reader.eventRadii, [1000, 5000])
        XCTAssertNil(model.select(item, rendered: rendered, active: true))
    }
    func testIdentityOrConfigurationChangeImmediatelyHidesLoadedRowsAndOpenDetail() async throws {
        for revoke in [false, true] {
            let reader = NearbyMapRecoveryReadProbe(), model = NearbyMapDiscoveryModel()
            model.load(sources: sources(reader, reader), query: NearbyTeamSyntheticFixtures.context, active: true)
            try await waitFor("Owned original rows") { model.placesPhase == .loaded && model.eventsPhase == .loaded }
            let item = try XCTUnwrap(model.visibleItems.first)
            let selected = try XCTUnwrap(model.select(item, rendered: model.snapshotID, active: true))
            if revoke { reader.isConfigured = false } else { reader.identity = .init(accountID: 7002, epoch: 2) }
            XCTAssertTrue(model.visibleItems.isEmpty); XCTAssertFalse(model.mayRemainOpen(selected))
            XCTAssertNil(model.select(item, rendered: model.snapshotID, active: true))
        }
    }
    func testLateSuccessAndErrorAfterRetirementCannotReplaceCurrentRows() async throws {
        for fail in [false, true] {
            let old = NearbyMapRecoveryReadProbe(), current = NearbyMapRecoveryReadProbe(), model = NearbyMapDiscoveryModel()
            old.holdEvents = true
            model.load(sources: sources(nil, old), query: NearbyTeamSyntheticFixtures.context, active: true)
            try await waitFor("Old request dispatched") { old.pendingEvents != nil }
            model.load(sources: sources(current, nil), query: NearbyTeamSyntheticFixtures.context, active: true)
            try await waitFor("Current independent original places") { model.placesPhase == .loaded }
            old.pendingEvents?.resume(with: fail ? .failure(APIError.unauthorized) : .success(try old.events()))
            old.pendingEvents = nil; await drain()
            XCTAssertEqual(model.visibleItems.map(\.id), ["place-7", "place-8"])
            XCTAssertEqual(model.eventsPhase, .unavailable); XCTAssertNil(model.eventsIssue)
        }
    }
    func testSameInFlightInputDeduplicatesForcedReadAndNoSourcesRemainUnavailable() async throws {
        let reader = NearbyMapRecoveryReadProbe(), model = NearbyMapDiscoveryModel()
        reader.holdEvents = true
        let offered = sources(nil, reader)
        model.load(sources: offered, query: NearbyTeamSyntheticFixtures.context, active: true)
        try await waitFor("Original event request held") { reader.pendingEvents != nil }
        model.load(sources: offered, query: NearbyTeamSyntheticFixtures.context, active: true, force: true)
        await drain(); XCTAssertEqual(reader.eventReads, 1)
        reader.pendingEvents?.resume(returning: try reader.events()); reader.pendingEvents = nil
        try await waitFor("One original event completion") { model.eventsPhase == .loaded }
        model.load(sources: nil, query: NearbyTeamSyntheticFixtures.context, active: true)
        XCTAssertTrue(model.visibleItems.isEmpty); XCTAssertEqual(model.placesPhase, .unavailable); XCTAssertEqual(model.eventsPhase, .unavailable)
    }
    func testChangedHostSourceCannotDisplayOldRowsBeforeInputCallbackRuns() async throws {
        let reader = NearbyMapRecoveryReadProbe(), replacement = NearbyMapRecoveryReadProbe(), model = NearbyMapDiscoveryModel()
        let query = NearbyTeamSyntheticFixtures.context, offered = sources(reader, reader)
        model.load(sources: offered, query: query, active: true)
        try await waitFor("Original supplied source settles") { model.placesPhase == .loaded && model.eventsPhase == .loaded }
        XCTAssertEqual(model.currentItems(sources: offered, query: query).count, 4)
        XCTAssertTrue(model.currentItems(sources: sources(replacement, replacement), query: query).isEmpty)
        XCTAssertTrue(model.currentItems(sources: nil, query: query).isEmpty)
        XCTAssertTrue(model.currentItems(sources: offered, query: .init(latitude: 37.78, longitude: -122.42, radius: 1000)).isEmpty)
        XCTAssertEqual(reader.placeReads, 1); XCTAssertEqual(replacement.placeReads, 0)
    }
}
