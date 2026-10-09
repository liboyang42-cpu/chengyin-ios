import SwiftUI
import XCTest
@testable import Questify

@MainActor private final class WalletPlayReaderFixture: TicketWalletReading {
    var scope = UUID()
    var isConfigured = true
    var isAuthenticated = true
    let isOfflineExample = true
    var reads = 0
    func ticketWallet() async throws -> TicketWalletSnapshot { reads += 1; return .init(tickets: []) }
    func ticketDetail(id: Int) async throws -> TicketWalletTicket { reads += 1; throw APIError.notConfigured }
}
@MainActor final class TicketWalletPlayEntryTests: XCTestCase {
    private func ticket(id: Int = 41, status: Int = 2, type: Int? = 1, owner: Int? = 9,
                        activity: Int? = nil, topic: Int? = nil, verification: Int = 0) throws -> TicketWalletTicket {
        var value: [String: Any] = ["id": id, "registrationStatus": status, "verificationStatus": verification]
        value["ownerType"] = type; value["ownerId"] = owner; value["activityId"] = activity; value["topicId"] = topic
        return try JSONDecoder().decode(TicketWalletTicket.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func provider(_ reader: WalletPlayReaderFixture, revision: UInt64 = 1,
                          current: @escaping @MainActor () -> UInt64 = { 1 },
                          build: @escaping @MainActor (ParticipationPlayEntry) -> AnyView = { _ in AnyView(EmptyView()) }) -> TicketWalletPlayProvider {
        .init(reader: reader, revision: revision, currentRevision: current, destination: build)
    }
    private func opened(_ reader: WalletPlayReaderFixture, _ provider: TicketWalletPlayProvider) throws -> TicketWalletPlayEntry {
        var value = TicketWalletPlayEntry(); value.appear()
        value.activate(ticket: try ticket(), requestedID: 41, reader: reader, provider: provider, presentationID: value.presentationID)
        XCTAssertNotNil(value.target); return value
    }
    func testExactTopicAndActivityOwnerRoutesRetainRegistrationID() throws {
        let topic = try XCTUnwrap(TicketWalletPlayEntry.entry(ticket: ticket(), requestedID: 41))
        let activity = try XCTUnwrap(TicketWalletPlayEntry.entry(ticket: ticket(type: 2), requestedID: 41))
        XCTAssertEqual(topic.scope, .topic(9)); XCTAssertEqual(activity.scope, .activity(9))
        XCTAssertEqual(topic.registrationID, 41); XCTAssertEqual(activity.registrationID, 41)
    }
    func testOnlyExactReadyRegistrationStatusIsEligible() throws {
        for status in [-1, 0, 1, 3, 4, 5, 99] {
            XCTAssertNil(TicketWalletPlayEntry.entry(ticket: try ticket(status: status, verification: 1), requestedID: 41))
        }
        XCTAssertNotNil(TicketWalletPlayEntry.entry(ticket: try ticket(status: 2, verification: 1), requestedID: 41))
    }
    func testRequestedRegistrationMustBePositiveAndMatchFreshTicket() throws {
        for id in [-1, 0, 40, 42] { XCTAssertNil(TicketWalletPlayEntry.entry(ticket: try ticket(), requestedID: id)) }
    }
    func testMissingUnknownOwnerTypeOrNonpositiveOwnerHasNoFallback() throws {
        for type in [Int?.none, Int?.some(0), Int?.some(3)] {
            XCTAssertNil(TicketWalletPlayEntry.entry(ticket: try ticket(type: type), requestedID: 41))
        }
        for owner in [Int?.none, Int?.some(0), Int?.some(-1)] {
            XCTAssertNil(TicketWalletPlayEntry.entry(ticket: try ticket(owner: owner, topic: 9), requestedID: 41))
        }
    }
    func testContradictoryOrCrossDomainIDsAreRejected() throws {
        for value in [try ticket(activity: 9), try ticket(topic: 10), try ticket(type: 2, topic: 9), try ticket(type: 2, activity: 10)] {
            XCTAssertNil(TicketWalletPlayEntry.entry(ticket: value, requestedID: 41))
        }
        XCTAssertNotNil(TicketWalletPlayEntry.entry(ticket: try ticket(topic: 9), requestedID: 41))
        XCTAssertNotNil(TicketWalletPlayEntry.entry(ticket: try ticket(type: 2, activity: 9), requestedID: 41))
    }
    func testProviderAndTargetConstructionDoNotBuildDestinationOrRead() throws {
        let reader = WalletPlayReaderFixture(); var builds = 0
        let source = provider(reader, build: { _ in builds += 1; return AnyView(EmptyView()) })
        _ = try opened(reader, source)
        XCTAssertEqual(builds, 0); XCTAssertEqual(reader.reads, 0)
    }
    func testMatchingExplicitNavigationBuildsWithExactRegistrationAndScope() throws {
        let reader = WalletPlayReaderFixture(); var received: [ParticipationPlayEntry] = []
        let source = provider(reader, build: { received.append($0); return AnyView(EmptyView()) })
        let entry = try opened(reader, source); let target = try XCTUnwrap(entry.target)
        XCTAssertTrue(entry.matches(target, ticket: try ticket(), requestedID: 41, reader: reader, provider: source))
        XCTAssertNotNil(source.destination(target: target, reader: reader))
        XCTAssertEqual(received, [ParticipationPlayEntry(registrationID: 41, scope: .topic(9))!])
        XCTAssertEqual(reader.reads, 0)
    }
    func testDifferentReaderWithSameOpaqueScopeCannotUseProvider() throws {
        let reader = WalletPlayReaderFixture(), proxy = WalletPlayReaderFixture(); proxy.scope = reader.scope
        let source = provider(reader); let entry = try opened(reader, source); let target = try XCTUnwrap(entry.target)
        XCTAssertFalse(source.matches(reader: proxy)); XCTAssertNil(source.destination(target: target, reader: proxy))
        XCTAssertFalse(entry.matches(target, ticket: try ticket(), requestedID: 41, reader: proxy, provider: source))
    }
    func testScopeAuthAndConfigurationChangesRejectActivationAndDestination() throws {
        let reader = WalletPlayReaderFixture(); let source = provider(reader); let entry = try opened(reader, source)
        let target = try XCTUnwrap(entry.target); let scope = reader.scope
        reader.scope = UUID(); XCTAssertNil(source.destination(target: target, reader: reader))
        reader.scope = scope; reader.isAuthenticated = false; XCTAssertNil(source.destination(target: target, reader: reader))
        reader.isAuthenticated = true; reader.isConfigured = false; XCTAssertNil(source.destination(target: target, reader: reader))
        XCTAssertEqual(reader.reads, 0)
    }
    func testSessionRevisionRevokesOldProviderEvenBeforeViewRendersAgain() throws {
        let reader = WalletPlayReaderFixture(); var revision: UInt64 = 1
        let source = provider(reader, current: { revision }); let entry = try opened(reader, source); let target = try XCTUnwrap(entry.target)
        revision = 2
        XCTAssertFalse(source.matches(reader: reader)); XCTAssertNil(source.destination(target: target, reader: reader))
        XCTAssertFalse(entry.matches(target, ticket: try ticket(), requestedID: 41, reader: reader, provider: source))
    }
    func testNewProviderOwnerCannotAdoptOldSelection() throws {
        let reader = WalletPlayReaderFixture(); let source = provider(reader); let entry = try opened(reader, source); let target = try XCTUnwrap(entry.target)
        let replacement = provider(reader, revision: 2, current: { 2 })
        XCTAssertNil(replacement.destination(target: target, reader: reader))
        XCTAssertFalse(entry.matches(target, ticket: try ticket(), requestedID: 41, reader: reader, provider: replacement))
    }
    func testChangedFreshTicketFactsRevokeNavigationMatch() throws {
        let reader = WalletPlayReaderFixture(); let source = provider(reader); let entry = try opened(reader, source); let target = try XCTUnwrap(entry.target)
        for value in [try ticket(status: 4), try ticket(owner: 10), try ticket(type: 2)] {
            XCTAssertFalse(entry.matches(target, ticket: value, requestedID: 41, reader: reader, provider: source))
        }
    }
    func testDuplicateTapPreservesOneTarget() throws {
        let reader = WalletPlayReaderFixture(); let source = provider(reader); var entry = try opened(reader, source); let original = entry.target
        entry.activate(ticket: try ticket(), requestedID: 41, reader: reader, provider: source, presentationID: entry.presentationID)
        XCTAssertEqual(entry.target, original)
    }
    func testPushBackAndReopenRejectStaleTapWithoutPoppingLiveDestination() throws {
        let reader = WalletPlayReaderFixture(); let source = provider(reader); var entry = try opened(reader, source)
        let target = try XCTUnwrap(entry.target); let presentation = entry.presentationID
        entry.disappear()
        XCTAssertTrue(entry.matches(target, ticket: try ticket(), requestedID: 41, reader: reader, provider: source))
        entry.target = nil; entry.appear() // Native Back binding, then source reappears.
        entry.activate(ticket: try ticket(), requestedID: 41, reader: reader, provider: source, presentationID: presentation)
        XCTAssertNil(entry.target)
        entry.activate(ticket: try ticket(), requestedID: 41, reader: reader, provider: source, presentationID: entry.presentationID)
        XCTAssertNotEqual(entry.target?.id, target.id)
    }
    func testRefreshAndOwnerRetirementRevokeSelectionAndOldCallback() throws {
        let reader = WalletPlayReaderFixture(); let source = provider(reader); var entry = try opened(reader, source)
        let target = try XCTUnwrap(entry.target); let presentation = entry.presentationID; entry.retire()
        XCTAssertNil(entry.target); XCTAssertFalse(entry.matches(target, ticket: try ticket(), requestedID: 41, reader: reader, provider: source))
        entry.activate(ticket: try ticket(), requestedID: 41, reader: reader, provider: source, presentationID: presentation)
        XCTAssertNil(entry.target)
    }
}
