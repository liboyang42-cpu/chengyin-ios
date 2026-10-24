import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ClubEnrollmentNavigationTests: XCTestCase {
    private let access = ClubGovernanceFixtureAccess()
    private let profile = ClubEnrollmentTestProfile()
    private let square = ClubEnrollmentTestSquare()
    private var profileContext: ClubEnrollmentProfileContext { .init(reader: profile, squareReader: square) }
    private var context: ClubEnrollmentHostContext { .init(clubID: 81, focusTopicID: 91, identity: access.identity, access: access, profile: profileContext) }
    private func loaded() async -> ClubEnrollmentReader {
        let reader = ClubEnrollmentReader(clubID: 81, focusTopicID: 91, access: access)
        await reader.activate(identity: access.identity); return reader
    }
    private func source(_ reader: ClubEnrollmentReader) throws -> ClubEnrollmentNavigation.Source {
        let row = try XCTUnwrap(reader.rosters[91]?.tickets.first?.registrants.first)
        return try XCTUnwrap(.init(host: context, reader: reader, access: access, topicID: 91, registrant: row))
    }
    private func open(_ owner: ClubEnrollmentNavigation, _ source: ClubEnrollmentNavigation.Source, kind: ClubEnrollmentNavigation.Kind = .checkin) throws -> ClubEnrollmentNavigation.Item {
        owner.appear(); owner.open(kind, source: source, current: source, active: true)
        return try XCTUnwrap(owner.item)
    }
    func testExactAcceptedRegistrantGoesToExistingProfileOrCheckin() async throws {
        let reader = await loaded(), owner = ClubEnrollmentNavigation(), value = try source(reader)
        let checkin = try open(owner, value)
        XCTAssertEqual(checkin.source.registrant.id, 121); XCTAssertEqual(checkin.source.topicID, 91)
        XCTAssertEqual(checkin.source.host.clubID, 81); XCTAssertEqual(checkin.kind, .checkin)
        owner.retire(); let person = try open(owner, value, kind: .profile)
        XCTAssertEqual(person.source.registrant.memberID, 704); XCTAssertEqual(person.kind, .profile)
        XCTAssertTrue(access.sent.isEmpty)
    }
    func testCheckinCloseIsConsumedOnceAndProfileCloseKeepsItsKind() async throws {
        let reader = await loaded(), owner = ClubEnrollmentNavigation(), value = try source(reader)
        let item = try open(owner, value), binding = owner.binding(item, source: { value })
        XCTAssertNil(owner.closed(item, source: value))
        binding.wrappedValue = false
        XCTAssertEqual(owner.closed(item, source: value), .checkin); XCTAssertNil(owner.closed(item, source: value))
        let person = try open(owner, value, kind: .profile)
        owner.binding(person, source: { value }).wrappedValue = false
        XCTAssertEqual(owner.closed(person, source: value), .profile)
        XCTAssertTrue(access.sent.isEmpty)
    }
    func testPushedPageCoverRetainsAcceptedRouteButPreventsAnotherOpen() async throws {
        let reader = await loaded(), owner = ClubEnrollmentNavigation(), value = try source(reader)
        let item = try open(owner, value)
        reader.suspend(); owner.hide()
        XCTAssertEqual(try source(reader), value)
        XCTAssertTrue(owner.binding(item, source: { value }).wrappedValue)
        owner.retire(); owner.open(.checkin, source: value, current: value, active: true)
        XCTAssertNil(owner.item)
        owner.appear(); owner.open(.checkin, source: value, current: value, active: true)
        XCTAssertNotNil(owner.item)
    }
    func testOldBindingAndCloseCannotRetireReopenedSameRow() async throws {
        let reader = await loaded(), owner = ClubEnrollmentNavigation(), value = try source(reader)
        let old = try open(owner, value), binding = owner.binding(old, source: { value })
        owner.retire(); let fresh = try open(owner, value)
        XCTAssertNotEqual(old.id, fresh.id)
        binding.wrappedValue = false; owner.retire(old)
        XCTAssertNil(owner.closed(old, source: value)); XCTAssertEqual(owner.item?.id, fresh.id); XCTAssertTrue(owner.isPresented)
        XCTAssertFalse(binding.wrappedValue)
    }
    func testActualAttachmentDepartureRetiresButOldDepartureCannotKillReopen() async throws {
        let reader = await loaded(), owner = ClubEnrollmentNavigation(), value = try source(reader)
        let old = try open(owner, value)
        XCTAssertTrue(owner.depart(old.attachment)); XCTAssertNil(owner.item)
        let fresh = try open(owner, value)
        XCTAssertFalse(owner.depart(old.attachment)); XCTAssertEqual(owner.item?.id, fresh.id)
        XCTAssertNotEqual(old.attachment, fresh.attachment)
    }
    func testBackgroundAndAbsentOrChangedCurrentSourceCannotOpen() async throws {
        let reader = await loaded(), owner = ClubEnrollmentNavigation(), value = try source(reader)
        owner.appear(); owner.open(.checkin, source: value, current: value, active: false)
        XCTAssertNil(owner.item)
        owner.open(.checkin, source: value, current: nil, active: true); XCTAssertNil(owner.item)
        await reader.refresh(); let fresh = try source(reader)
        XCTAssertNotEqual(value, fresh)
        owner.open(.checkin, source: value, current: fresh, active: true); XCTAssertNil(owner.item)
    }
    func testFreshReadRejectsOldRouteAndCloseReceipt() async throws {
        let reader = await loaded(), owner = ClubEnrollmentNavigation(), value = try source(reader)
        let item = try open(owner, value)
        await reader.refresh(); let fresh = try source(reader)
        let binding = owner.binding(item, source: { fresh })
        XCTAssertFalse(binding.wrappedValue); binding.wrappedValue = false
        XCTAssertNil(owner.closed(item, source: fresh)); XCTAssertFalse(owner.current(item, source: fresh))
    }
    func testProfileAccountEpochAndConfigurationAreRequired() async throws {
        let reader = await loaded(), owner = ClubEnrollmentNavigation()
        for identity in [SocialAccountIdentity(accountID: 81, epoch: 1), .init(accountID: 701, epoch: 2), .init(accountID: nil, epoch: 1)] {
            profile.identity = identity
            let value = try source(reader)
            XCTAssertFalse(value.host.permitsProfile)
            owner.appear(); owner.open(.profile, source: value, current: value, active: true); XCTAssertNil(owner.item)
            owner.open(.checkin, source: value, current: value, active: true); XCTAssertNotNil(owner.item); owner.retire()
        }
        profile.identity = .init(accountID: 701, epoch: 1); profile.isConfigured = false
        XCTAssertFalse(context.permitsProfile)
    }
    func testReaderProfileAndSquareReplacementChangePageIdentity() {
        let original = context, replacement = ClubGovernanceFixtureAccess()
        XCTAssertNotEqual(original, ClubEnrollmentHostContext(clubID: 81, focusTopicID: 91, identity: replacement.identity, access: replacement, profile: profileContext))
        profile.presentationRevision += 1; XCTAssertNotEqual(original, context)
        let beforeSquare = context; square.scope = UUID(); XCTAssertNotEqual(beforeSquare, context)
        XCTAssertNotEqual(context, ClubEnrollmentHostContext(clubID: 81, focusTopicID: 91, identity: access.identity, access: access, profile: .init(reader: ClubEnrollmentTestProfile(), squareReader: square)))
    }
    func testDifferentClubTopicAndCollapsedRowCannotMintSource() async throws {
        let reader = await loaded(), value = try source(reader)
        let wrongClub = ClubEnrollmentHostContext(clubID: 82, focusTopicID: 91, identity: access.identity, access: access, profile: profileContext)
        XCTAssertNil(ClubEnrollmentNavigation.Source(host: wrongClub, reader: reader, access: access, topicID: 91, registrant: value.registrant))
        XCTAssertNil(ClubEnrollmentNavigation.Source(host: context, reader: reader, access: access, topicID: 92, registrant: value.registrant))
        await reader.toggle(topicID: 91)
        XCTAssertNil(ClubEnrollmentNavigation.Source(host: context, reader: reader, access: access, topicID: 91, registrant: value.registrant))
    }
    func testRefreshFailureAndIdentitySwitchCannotMintOldSource() async throws {
        let reader = await loaded(), value = try source(reader)
        access.readFailure = .rejected(code: 503, message: nil); await reader.refresh()
        XCTAssertNil(ClubEnrollmentNavigation.Source(host: context, reader: reader, access: access, topicID: 91, registrant: value.registrant))
        access.identity = .init(accountID: 799, epoch: 2)
        XCTAssertNil(ClubEnrollmentNavigation.Source(host: value.host, reader: reader, access: access, topicID: 91, registrant: value.registrant))
    }
    func testReturnReadInterruptedByBackgroundResumesWithoutOldCompletionConsumingNewRead() async throws {
        let access = ClubEnrollmentHeldAccess(), owner = ClubEnrollmentNavigation()
        let reader = ClubEnrollmentReader(clubID: 81, focusTopicID: 91, access: access)
        await reader.activate(identity: access.identity)
        let host = ClubEnrollmentHostContext(clubID: 81, focusTopicID: 91, identity: access.identity, access: access, profile: nil)
        let row = try XCTUnwrap(reader.rosters[91]?.tickets.first?.registrants.first)
        let source = try XCTUnwrap(ClubEnrollmentNavigation.Source(host: host, reader: reader, access: access, topicID: 91, registrant: row))
        let item = try open(owner, source)
        owner.binding(item, source: { source }).wrappedValue = false
        XCTAssertEqual(owner.closed(item, source: source), .checkin)
        let original = reader.completedRefreshRevision
        access.hold = .topics
        let old = Task { await owner.refreshReturn(using: reader, active: { true }, isCurrent: { true }) }
        await access.waitUntilHeld()
        owner.pauseReturnRead(); reader.suspend()
        XCTAssertTrue(owner.hasPendingReturn); XCTAssertEqual(reader.completedRefreshRevision, original)
        await owner.refreshReturn(using: reader, active: { false }, isCurrent: { true })
        XCTAssertNil(owner.returnRead)
        await owner.refreshReturn(using: reader, active: { true }, isCurrent: { true })
        XCTAssertFalse(owner.hasPendingReturn); XCTAssertGreaterThan(reader.completedRefreshRevision, original)
        let accepted = reader.completedRefreshRevision
        access.release(); await old.value
        XCTAssertFalse(owner.hasPendingReturn); XCTAssertNil(owner.returnRead)
        XCTAssertEqual(reader.completedRefreshRevision, accepted)
    }
    func testInterruptedExpandedRosterRemainsPendingUntilCompleteRefresh() async throws {
        let access = ClubEnrollmentHeldAccess(), owner = ClubEnrollmentNavigation()
        let reader = ClubEnrollmentReader(clubID: 81, focusTopicID: 91, access: access)
        await reader.activate(identity: access.identity)
        let host = ClubEnrollmentHostContext(clubID: 81, focusTopicID: 91, identity: access.identity, access: access, profile: nil)
        let row = try XCTUnwrap(reader.rosters[91]?.tickets.first?.registrants.first)
        let source = try XCTUnwrap(ClubEnrollmentNavigation.Source(host: host, reader: reader, access: access, topicID: 91, registrant: row))
        let item = try open(owner, source)
        owner.binding(item, source: { source }).wrappedValue = false
        _ = owner.closed(item, source: source)
        let completed = reader.completedRefreshRevision
        access.hold = .registrations
        let old = Task { await owner.refreshReturn(using: reader, active: { true }, isCurrent: { true }) }
        await access.waitUntilHeld(); owner.pauseReturnRead(); reader.suspend(); access.release(); await old.value
        XCTAssertTrue(owner.hasPendingReturn); XCTAssertEqual(reader.completedRefreshRevision, completed)
        access.fixture.readFailure = .rejected(code: 503, message: nil)
        await owner.refreshReturn(using: reader, active: { true }, isCurrent: { true })
        XCTAssertTrue(owner.hasPendingReturn); XCTAssertNotNil(reader.failure)
        access.fixture.readFailure = nil
        await owner.refreshReturn(using: reader, active: { true }, isCurrent: { true })
        XCTAssertFalse(owner.hasPendingReturn); XCTAssertGreaterThan(reader.completedRefreshRevision, completed)
    }
    func testReturnTicketRejectsOldAttachmentHiddenAndChangedSource() async throws {
        let reader = await loaded(), owner = ClubEnrollmentNavigation(), value = try source(reader)
        let item = try open(owner, value)
        owner.binding(item, source: { value }).wrappedValue = false
        _ = owner.closed(item, source: value)
        let ticket = try XCTUnwrap(owner.beginReturnRead(active: true))
        XCTAssertNil(owner.beginReturnRead(active: true))
        owner.pauseReturnRead(); owner.hide()
        let before = reader.completedRefreshRevision
        await owner.refreshReturn(using: reader, active: { true }, isCurrent: { true })
        XCTAssertEqual(reader.completedRefreshRevision, before); XCTAssertTrue(owner.hasPendingReturn)
        owner.appear()
        await owner.refreshReturn(using: reader, active: { true }, isCurrent: { false })
        XCTAssertEqual(reader.completedRefreshRevision, before)
        XCTAssertTrue(owner.depart(item.attachment)); owner.appear()
        owner.finishReturnRead(ticket, completed: true)
        XCTAssertFalse(owner.hasPendingReturn); XCTAssertNil(owner.returnRead)
    }

}

@MainActor private final class ClubEnrollmentTestProfile: SocialAccountReading {
    var identity = SocialAccountIdentity(accountID: 701, epoch: 1)
    var presentationRevision: UInt64 = 0
    var isConfigured = true
    let isOfflineExample = true
    func publicProfile(memberID: Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
    func informationList() async throws -> [SocialInformation] { throw APIError.notConfigured }
    func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
    func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
}
@MainActor private final class ClubEnrollmentTestSquare: SquareReading {
    var scope = UUID()
    let isConfigured = true, isOfflineExample = true, isSignedIn = true
    func squareFeed(query: SquareQuery, cursor: SquareCursor?) async throws -> SquareFeedPage { throw APIError.notConfigured }
    func squareDetail(id: Int) async throws -> SquarePost { throw APIError.notConfigured }
    func squareComments(postID: Int, pageNumber: Int) async throws -> SquareCommentPage { throw APIError.notConfigured }
}

@MainActor private final class ClubEnrollmentHeldAccess: ClubGovernanceAccess {
    let fixture = ClubGovernanceFixtureAccess()
    var identity: ClubReadIdentity? { fixture.identity }
    let isConfigured = true, allowsOfflineWrites = false
    let storageNamespace = "enrollment-return-tests"
    var hold: ClubGovernanceRead?
    private var pending: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    func waitUntilHeld() async {
        if pending != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func release() { let value = pending; pending = nil; value?.resume() }
    func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
        let value = try await fixture.read(operation, scope: scope, options: options)
        if hold == operation {
            hold = nil
            await withCheckedContinuation { pending = $0; waiting?.resume(); waiting = nil }
        }
        return value
    }
    func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { XCTFail("Read-only return sent a command"); throw ClubGovernanceFailure.forbidden }
}
