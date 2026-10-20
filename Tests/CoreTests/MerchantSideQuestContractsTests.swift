import XCTest
@testable import QuestifyCore

final class MerchantSideQuestContractsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 3_000_000)
    private func instance(_ id: String = "i1", status: SideQuestSpawnInstance.Status = .open, capacity: Int? = 3,
                          from: TimeInterval = -60, until: TimeInterval = 3600, theme: String? = nil) throws -> SideQuestSpawnInstance {
        try .init(instanceID: id, definitionID: "d1", definitionVersion: 2, place: .init(type: .store, id: "77"), themeReleaseID: theme,
                  visibleFrom: now.addingTimeInterval(from), visibleUntil: now.addingTimeInterval(until), status: status,
                  remainingCapacity: capacity, title: "Synthetic side quest")
    }
    func testAcceptStaysDisabled() throws {
        XCTAssertFalse(SideQuestFeature.acceptEnabled)
        var book = SideQuestAttemptBook()
        XCTAssertThrowsError(try book.prepareAccept(instance(), now: now)) { XCTAssertEqual($0 as? SideQuestFailure, .featureDisabled) }
    }
    func testThemeIsOptionalAndPlaceMustBeStoreOrPOI() throws {
        XCTAssertNil(try instance().themeReleaseID)
        XCTAssertThrowsError(try SideQuestSpawnInstance(instanceID: "x", definitionID: "d", definitionVersion: 1, place: .init(type: .themeNode, id: "1"),
                                                        themeReleaseID: nil, visibleFrom: now, visibleUntil: now.addingTimeInterval(1),
                                                        status: .open, remainingCapacity: nil, title: "t"))
    }
    func testVisibilityWindowStatusAndCapacity() throws {
        XCTAssertTrue(try instance().offersAccept(now: now))
        XCTAssertFalse(try instance(from: 10).isDiscoverable(now: now))
        XCTAssertFalse(try instance(until: -1).isDiscoverable(now: now))
        XCTAssertFalse(try instance(status: .closed).isDiscoverable(now: now))
        let full = try instance(capacity: 0)
        XCTAssertTrue(full.isDiscoverable(now: now)); XCTAssertFalse(full.offersAccept(now: now))
        XCTAssertEqual(full.markerState(now: now), .unavailable)
        XCTAssertEqual(try instance(status: .paused).markerState(now: now), .unavailable)
        XCTAssertEqual(try instance().markerState(now: now), .interactive)
    }
    func testAttemptTransitions() {
        XCTAssertTrue(SideQuestAttemptStatus.accepted.canMove(to: .active))
        XCTAssertTrue(SideQuestAttemptStatus.active.canMove(to: .completed))
        XCTAssertFalse(SideQuestAttemptStatus.accepted.canMove(to: .completed))
        for terminal in SideQuestAttemptStatus.allCases where terminal.isTerminal {
            for next in SideQuestAttemptStatus.allCases { XCTAssertFalse(terminal.canMove(to: next)) }
        }
    }
    func testUnknownAcceptReusesSameRequestUntilReadback() throws {
        var book = SideQuestAttemptBook(); let quest = try instance()
        let first = try book.prepareAcceptForContract(quest, now: now, requestID: UUID())
        XCTAssertEqual(first.attemptNo, 1)
        book.finishAccept(first, attempt: nil)
        XCTAssertEqual(book.pending, .unknown(first))
        XCTAssertEqual(try book.prepareAcceptForContract(quest, now: now, requestID: UUID()), first)
        try book.applyReadback(.init(instanceID: "i1", attemptNo: 1, status: .accepted, revision: 1))
        XCTAssertEqual(book.pending, .idle)
        XCTAssertThrowsError(try book.prepareAcceptForContract(quest, now: now, requestID: UUID()))
    }
    func testConfirmedNotAcceptedAllowsIdenticalResend() throws {
        var book = SideQuestAttemptBook(); let quest = try instance()
        let request = try book.prepareAcceptForContract(quest, now: now, requestID: UUID())
        book.finishAccept(request, attempt: nil)
        book.confirmNotAccepted(instanceID: "i1")
        XCTAssertEqual(book.pending, .sending(request))
    }
    func testAcceptedAttemptSurvivesInstanceExpiryAndRejectsIllegalJumps() throws {
        var book = SideQuestAttemptBook(); let quest = try instance()
        let request = try book.prepareAcceptForContract(quest, now: now, requestID: UUID())
        book.finishAccept(request, attempt: .init(instanceID: "i1", attemptNo: 1, status: .accepted, revision: 1))
        XCTAssertFalse(quest.isDiscoverable(now: now.addingTimeInterval(7200)))
        XCTAssertEqual(book.attempts["i1"]?.status, .accepted)
        XCTAssertThrowsError(try book.applyReadback(.init(instanceID: "i1", attemptNo: 1, status: .completed, revision: 2)))
        try book.applyReadback(.init(instanceID: "i1", attemptNo: 1, status: .active, revision: 2))
        try book.applyReadback(.init(instanceID: "i1", attemptNo: 1, status: .accepted, revision: 1))
        XCTAssertEqual(book.attempts["i1"]?.status, .active)
        try book.applyReadback(.init(instanceID: "i1", attemptNo: 1, status: .expired, revision: 3))
        XCTAssertEqual(try book.prepareAcceptForContract(quest, now: now, requestID: UUID()).attemptNo, 2)
    }
    func testLateResponseForOtherRequestIgnored() throws {
        var book = SideQuestAttemptBook(); let quest = try instance()
        let request = try book.prepareAcceptForContract(quest, now: now, requestID: UUID())
        let stranger = SideQuestAcceptRequest(instanceID: "i1", definitionVersion: 2, attemptNo: 1, requestID: UUID())
        book.finishAccept(stranger, attempt: .init(instanceID: "i1", attemptNo: 1, status: .accepted, revision: 1))
        XCTAssertEqual(book.pending, .sending(request)); XCTAssertTrue(book.attempts.isEmpty)
    }
}
