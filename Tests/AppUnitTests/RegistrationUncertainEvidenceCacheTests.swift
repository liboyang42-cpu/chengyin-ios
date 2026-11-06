#if DEBUG
import Foundation
import XCTest
@testable import Questify

/// Synthetic, in-memory registration boundary. No endpoint, credential or payment exists here.
@MainActor
private final class EvidenceCacheService: RegistrationCoordinatingService {
    var quoteJSON = #"{"payAmount":12.5,"pointsUsable":true,"quoteSign":"parity-fixture-sign"}"#
    var createError: Error?
    private(set) var quotes: [RegistrationQuoteRequest] = []
    private(set) var creates: [RegistrationCreateIntent] = []
    private(set) var reads: [Int] = []
    func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote {
        quotes.append(selection)
        return try JSONDecoder().decode(RegistrationQuote.self, from: Data(quoteJSON.utf8))
    }
    func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult {
        creates.append(intent)
        if let createError { throw createError }
        return try JSONDecoder().decode(RegistrationCreateResult.self, from: Data(#"{"registrationId":41,"payableAmount":12.5}"#.utf8))
    }
    func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot {
        reads.append(registrationID)
        return try JSONDecoder().decode(RegistrationStatusSnapshot.self, from: Data(#"{"id":41,"registrationStatus":1,"paymentStatus":1}"#.utf8))
    }
}

@MainActor
private final class EvidenceCacheReader: ProfileReading {
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var isConfigured = true
    var orders: [ProfileOrder] = []
    private(set) var orderListReads = 0
    func profileOrders() async throws -> [ProfileOrder] { orderListReads += 1; return orders }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.invalidRequest }
    func profileParticipants() async throws -> [ProfileParticipant] { [] }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.invalidRequest }
    func profileBadges() async throws -> ProfileBadgeWall { .init(identities: [], medals: []) }
}

@MainActor final class RegistrationUncertainEvidenceCacheTests: XCTestCase {
    private func unknownFlow(_ reader: EvidenceCacheReader) async throws -> (RegistrationUIFlow, EvidenceCacheService) {
        let service = EvidenceCacheService(); service.createError = URLError(.timedOut)
        let coordinator = RegistrationCoordinator(service: service, makeRequestID: { "evidence-fixture-request" })
        try coordinator.setAccount(id: 1, token: "fixture-only-token")
        let activity = try JSONDecoder().decode(ActivityDetail.self, from: Data(#"{"id":7,"name":"Fixture","omsTicketList":[{"id":11,"name":"Ticket","price":12.5,"remainingInventory":3}]}"#.utf8))
        let flow = RegistrationUIFlow(activity: activity, coordinator: coordinator,
            currentIdentity: { .init(accountID: 1, epoch: 1) }, quoteEnabled: true, creationPolicy: .offlineFixture)
        flow.open(); flow.setName("Fixture Person"); flow.setPhone("13800000000")
        flow.setConsent(true); await flow.requestQuote()
        XCTAssertTrue(flow.prepareConfirmation()); await flow.confirmAndReadBack()
        return (flow, service)
    }
    private func scope(_ flow: RegistrationUIFlow, _ reader: EvidenceCacheReader, active: Bool = true) -> RegistrationUncertainEvidenceScope? {
        .capture(flow: flow, reader: reader, isActive: active)
    }
    func testRealUnknownReadCachesWithoutUnlockingOrReplaying() async throws {
        let reader = EvidenceCacheReader(), (flow, service) = try await unknownFlow(reader)
        let captured = try XCTUnwrap(scope(flow, reader)), intent = flow.coordinator.retainedIntent
        var cache = RegistrationUncertainEvidenceCache(); let token = cache.begin(captured)
        let result = try await flow.uncertainOutcomeEvidence(orders: reader)
        cache.finish(result, for: token, current: scope(flow, reader))
        XCTAssertEqual(cache.evidence, .noMatchingOrder); XCTAssertTrue(cache.isCurrent(scope(flow, reader)))
        XCTAssertEqual(reader.orderListReads, 1); XCTAssertEqual(service.creates.count, 1)
        XCTAssertEqual(flow.coordinator.retainedIntent, intent); XCTAssertFalse(flow.canEdit)
        guard case .outcomeUnknown = flow.creationState else { return XCTFail("Evidence is not a create receipt") }
    }
    func testRevokedReaderImmediatelyHidesCachedIDs() async throws {
        let reader = EvidenceCacheReader(), (flow, _) = try await unknownFlow(reader)
        var cache = RegistrationUncertainEvidenceCache(); let token = cache.begin(try XCTUnwrap(scope(flow, reader)))
        cache.finish(.matchingOrders([41]), for: token, current: scope(flow, reader))
        reader.isConfigured = false
        XCTAssertNil(scope(flow, reader)); XCTAssertFalse(cache.isCurrent(scope(flow, reader)))
        cache.clear(); reader.isConfigured = true
        XCTAssertFalse(cache.isCurrent(scope(flow, reader))); XCTAssertNil(cache.evidence)
    }
    func testReaderReplacementRevisionAndAccountChangeCannotReuseEvidence() async throws {
        let reader = EvidenceCacheReader(), (flow, _) = try await unknownFlow(reader)
        var cache = RegistrationUncertainEvidenceCache(); _ = cache.begin(try XCTUnwrap(scope(flow, reader)))
        XCTAssertFalse(cache.isCurrent(scope(flow, EvidenceCacheReader())))
        reader.identity = .init(accountID: 1, epoch: 1, viewerRevision: 2)
        XCTAssertNil(scope(flow, reader))
        reader.identity = .init(accountID: 2, epoch: 1)
        XCTAssertNil(scope(flow, reader))
    }
    func testLateCompletionCannotCrossBackgroundAndNewRead() async throws {
        let reader = EvidenceCacheReader(), (flow, _) = try await unknownFlow(reader)
        var cache = RegistrationUncertainEvidenceCache(); let captured = try XCTUnwrap(scope(flow, reader))
        let old = cache.begin(captured)
        XCTAssertFalse(cache.isCurrent(scope(flow, reader, active: false)))
        cache.clear(); let fresh = cache.begin(captured)
        cache.finish(.matchingOrders([41]), for: old, current: captured)
        cache.fail(for: old, current: captured, cancelled: false)
        XCTAssertTrue(cache.reading); XCTAssertNil(cache.evidence); XCTAssertFalse(cache.failed)
        cache.finish(.noMatchingOrder, for: fresh, current: captured)
        XCTAssertEqual(cache.evidence, .noMatchingOrder)
    }
    func testFailureAllowsNewReadAndCancellationIsNotFailure() async throws {
        let reader = EvidenceCacheReader(), (flow, service) = try await unknownFlow(reader)
        var cache = RegistrationUncertainEvidenceCache(); let captured = try XCTUnwrap(scope(flow, reader))
        let first = cache.begin(captured); cache.fail(for: first, current: captured, cancelled: false)
        XCTAssertTrue(cache.failed); XCTAssertFalse(cache.reading); XCTAssertNil(cache.evidence)
        let second = cache.begin(captured); cache.fail(for: second, current: captured, cancelled: true)
        XCTAssertFalse(cache.failed); XCTAssertFalse(cache.reading)
        let third = cache.begin(captured); cache.finish(.notApplicable, for: third, current: captured)
        XCTAssertNil(cache.evidence); XCTAssertFalse(cache.failed); XCTAssertEqual(service.creates.count, 1)
    }
    func testLeaveAndReopenCannotReusePriorVisit() async throws {
        let reader = EvidenceCacheReader(), (flow, service) = try await unknownFlow(reader)
        var cache = RegistrationUncertainEvidenceCache(); _ = cache.begin(try XCTUnwrap(scope(flow, reader)))
        let intent = flow.coordinator.retainedIntent
        flow.leave(); XCTAssertNil(scope(flow, reader)); flow.open()
        XCTAssertNotNil(scope(flow, reader)); XCTAssertFalse(cache.isCurrent(scope(flow, reader)))
        XCTAssertEqual(flow.coordinator.retainedIntent, intent); XCTAssertEqual(service.creates.count, 1)
    }
}
#endif
