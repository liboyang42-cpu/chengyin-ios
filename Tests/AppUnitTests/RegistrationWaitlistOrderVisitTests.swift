import Foundation
import XCTest
@testable import Questify

@MainActor private final class WaitlistVisitReader: ProfileReading {
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 4)
    var isConfigured = true
    var reads = 0
    var suspended = false
    var continuation: CheckedContinuation<ProfileOrder, Error>?
    var started: CheckedContinuation<Void, Never>?
    func waitForRead() async { if continuation == nil { await withCheckedContinuation { started = $0 } } }
    func profileOrder(id: Int) async throws -> ProfileOrder {
        reads += 1
        if suspended {
            return try await withCheckedThrowingContinuation { continuation = $0; started?.resume(); started = nil }
        }
        return try Self.order()
    }
    static func order() throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self, from: Data("{\"id\":41,\"memberId\":1,\"ownerType\":2,\"ownerId\":7,\"ticketId\":11,\"registrationStatus\":0,\"paymentStatus\":0}".utf8))
    }
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.invalidRequest }
    func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.invalidRequest }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.invalidRequest }
    func profileBadges() async throws -> ProfileBadgeWall { throw APIError.invalidRequest }
}
@MainActor final class RegistrationWaitlistOrderVisitTests: XCTestCase {
    private final class Host {
        var current: RegistrationWaitlistOrderVisit?
        var destination: RegistrationWaitlistOrderDestination?
        var active = true
    }
    private func visit() throws -> RegistrationWaitlistOrderVisit {
        let status = try JSONDecoder().decode(RegistrationWaitlistStatus.self, from: Data("{\"id\":5,\"activityId\":7,\"ticketId\":11,\"memberId\":1,\"state\":\"CLAIMED\",\"eligibilityState\":\"ALREADY_REGISTERED\",\"waitlistJoinAllowed\":false,\"registrationId\":41}".utf8))
        let identity = ProfileReadIdentity(accountID: 1, epoch: 4)
        let destination = try XCTUnwrap(RegistrationWaitlistOrderDestination(status: status, scope: .init(activityID: 7, ticketID: 11), identity: identity))
        let presentation = try XCTUnwrap(RegistrationWaitlistOrderPresentation(destination: destination, readIdentity: identity))
        return .init(presentation: presentation)
    }
    private func reader(_ visit: RegistrationWaitlistOrderVisit, _ host: Host, _ base: WaitlistVisitReader) -> RegistrationWaitlistOrderReader {
        .init(presentation: visit.presentation, base: base, isCurrent: {
            RegistrationWaitlistOrderVisit.permits(visit, current: host.current, destination: host.destination, isActive: host.active)
        })
    }
    func testVisibleExactVisitReadsOriginalOrder() async throws {
        let visit = try visit(), host = Host(), base = WaitlistVisitReader()
        host.current = visit; host.destination = visit.presentation.destination
        let result = try await reader(visit, host, base).profileOrder(id: 41)
        XCTAssertEqual(result.id, 41); XCTAssertEqual(base.reads, 1)
    }
    func testDismissAndSameOrderReopenDoNotReviveOldReader() async throws {
        let visit = try visit(), host = Host(), base = WaitlistVisitReader()
        host.current = visit; host.destination = visit.presentation.destination
        let old = reader(visit, host, base)
        host.current = nil; XCTAssertNil(old.identity)
        host.current = .init(presentation: visit.presentation)
        XCTAssertNil(old.identity)
        do { _ = try await old.profileOrder(id: 41); XCTFail("Dismissed visit must remain unauthorized") } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(base.reads, 0)
    }
    func testInactiveOrChangedDestinationCannotRead() async throws {
        let visit = try visit(), host = Host(), base = WaitlistVisitReader()
        host.current = visit; host.destination = visit.presentation.destination; host.active = false
        let fenced = reader(visit, host, base)
        XCTAssertNil(fenced.identity)
        host.active = true; host.destination = nil
        XCTAssertNil(fenced.identity); XCTAssertEqual(base.reads, 0)
    }
    func testLateReadAfterBackgroundAndReopenIsDiscarded() async throws {
        let visit = try visit(), host = Host(), base = WaitlistVisitReader()
        host.current = visit; host.destination = visit.presentation.destination; base.suspended = true
        let fenced = reader(visit, host, base)
        let task = Task { try await fenced.profileOrder(id: 41) }
        await base.waitForRead()
        host.active = false; host.current = nil
        host.active = true; host.current = .init(presentation: visit.presentation)
        base.continuation?.resume(returning: try WaitlistVisitReader.order()); base.continuation = nil
        do { _ = try await task.value; XCTFail("Old completion must not cross visit boundary") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(base.reads, 1)
    }
}
