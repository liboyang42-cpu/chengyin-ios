import XCTest
@testable import Questify

private actor ViewportSearchWire: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let response = request.url!.path.hasSuffix("/activity/list")
            ? #"{"code":200,"data":{"rows":[],"total":0}}"# : #"{"code":200,"data":[]}"#
        return (Data(response.utf8), 200)
    }
}

@MainActor final class SearchMapViewportPresentationTests: XCTestCase {
    private let presentation = UUID()
    private func viewport() throws -> SearchMapViewport {
        try XCTUnwrap(.init(latitude: 39.916527, longitude: 116.397128, latitudeSpan: 0.04, longitudeSpan: 0.04, datum: .wgs84))
    }
    private func context(_ reader: any SearchMapReading) -> SearchMapViewportSelection.Context {
        .init(readerScope: reader.scope, manualAreaRevision: reader.manualAreaRevision, presentationID: presentation)
    }
    private func service(_ wire: ViewportSearchWire) throws -> SearchMapService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/")!), transport: wire)
    }
    func testPanningOnlyDraftsThenExplicitSearchUsesConvertedManualCenterAndExistingReads() async throws {
        let wire = ViewportSearchWire(), selection = ManualMapAreaSelection()
        let owner = try SearchMapContext(accountID: 1, epoch: 1, token: "synthetic", manualMapApprovalRevision: UUID())
        let reader = SearchMapSessionReader(service: try service(wire), currentContext: { owner }, manualAreaSelection: selection)
        let old = RoamSearchArea(coordinate: try XCTUnwrap(.init(latitude: 1, longitude: 2)), label: "Earlier manual area")
        reader.selectManualArea(old); let originalRevision = reader.manualAreaRevision
        var gate = SearchMapViewportSelection()
        gate.observe(try viewport(), context: context(reader))
        let noRequests = await wire.requests; XCTAssertTrue(noRequests.isEmpty)
        XCTAssertEqual(selection.snapshot?.area, old); XCTAssertEqual(reader.manualAreaRevision, originalRevision)
        let ticket = try XCTUnwrap(gate.current(in: context(reader)))
        let projected = try XCTUnwrap(gate.consume(ticket, context: context(reader), readerConfigured: reader.isConfigured, active: true))
        XCTAssertEqual(projected.datum, .gcj02)
        let chosen = RoamSearchArea(coordinate: projected.coordinate, label: "Visible map area")
        reader.selectManualArea(chosen)
        _ = try await reader.citySearch(.init(filter: .init(), area: chosen))
        let requests = await wire.requests
        XCTAssertEqual(requests.count, 2)
        let node = try XCTUnwrap(requests.first { $0.url?.path == "/api/city/nodes" })
        let fields = try XCTUnwrap(URLComponents(url: try XCTUnwrap(node.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(fields.first { $0.name == "lat" }?.value, String(projected.coordinate.latitude))
        XCTAssertEqual(fields.first { $0.name == "lng" }?.value, String(projected.coordinate.longitude))
        XCTAssertEqual(projected.coordinate.latitude, 39.91793074924595, accuracy: 0.000000001)
        XCTAssertEqual(projected.coordinate.longitude, 116.40337249402477, accuracy: 0.000000001)
        XCTAssertGreaterThan(reader.manualAreaRevision, originalRevision)
        XCTAssertNil(gate.consume(ticket, context: context(reader), readerConfigured: true, active: true))
    }
    func testAccountRoleSessionAndManualReadLeaseChangesRejectQueuedViewportAction() async throws {
        for transition in ["account", "role", "epoch", "leaseRevoked", "leaseReissued"] {
            let wire = ViewportSearchWire(), lease = UUID()
            var owner = try SearchMapContext(accountID: 1, epoch: 1, token: "synthetic", role: "player", manualMapApprovalRevision: lease)
            let reader = SearchMapSessionReader(service: try service(wire), currentContext: { owner }, manualAreaSelection: ManualMapAreaSelection())
            var gate = SearchMapViewportSelection(); gate.observe(try viewport(), context: context(reader))
            let ticket = try XCTUnwrap(gate.draft)
            owner = try SearchMapContext(accountID: transition == "account" ? 2 : 1,
                epoch: transition == "epoch" ? 2 : 1, token: "synthetic", role: transition == "role" ? "merchant" : "player",
                manualMapApprovalRevision: transition == "leaseRevoked" ? nil : transition == "leaseReissued" ? UUID() : lease)
            XCTAssertNil(gate.consume(ticket, context: context(reader), readerConfigured: reader.isConfigured, active: true), transition)
            let requests = await wire.requests; XCTAssertTrue(requests.isEmpty, transition)
        }
    }
    func testManualAreaABAAndMapDepartureRetireExistingDraftWithoutAnyQuery() async throws {
        let wire = ViewportSearchWire(), selection = ManualMapAreaSelection()
        let reader = SearchMapSessionReader(service: try service(wire), currentContext: { .init(guestEpoch: 1) }, manualAreaSelection: selection)
        let area = RoamSearchArea(coordinate: try viewport().center, label: "Manual")
        reader.selectManualArea(area)
        var gate = SearchMapViewportSelection(); gate.observe(try viewport(), context: context(reader))
        let ticket = try XCTUnwrap(gate.draft)
        reader.selectManualArea(nil); reader.selectManualArea(area)
        XCTAssertNil(gate.consume(ticket, context: context(reader), readerConfigured: true, active: true))
        gate.observe(try viewport(), context: context(reader)); let next = try XCTUnwrap(gate.draft)
        gate.invalidate()
        XCTAssertNil(gate.consume(next, context: context(reader), readerConfigured: true, active: true))
        let requests = await wire.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testUnconfiguredAndInactiveMapCannotPromoteDraftToManualArea() throws {
        let selection = ManualMapAreaSelection()
        let reader = SearchMapSessionReader(service: nil, currentContext: { .init(guestEpoch: 1) }, manualAreaSelection: selection)
        var gate = SearchMapViewportSelection(); gate.observe(try viewport(), context: context(reader))
        let ticket = try XCTUnwrap(gate.draft)
        XCTAssertNil(gate.consume(ticket, context: context(reader), readerConfigured: reader.isConfigured, active: true))
        XCTAssertNil(gate.consume(ticket, context: context(reader), readerConfigured: true, active: false))
        XCTAssertNil(selection.snapshot); XCTAssertEqual(selection.revision, 0)
    }
}
