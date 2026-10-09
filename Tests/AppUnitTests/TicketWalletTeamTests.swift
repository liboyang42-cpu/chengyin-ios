import SwiftUI
import XCTest
@testable import Questify

@MainActor private final class TicketTeamReaderFixture: TicketWalletReading {
    var scope = UUID()
    var isConfigured = true
    var isAuthenticated = true
    var isOfflineExample = true
    func ticketWallet() async throws -> TicketWalletSnapshot { .init(tickets: []) }
    func ticketDetail(id: Int) async throws -> TicketWalletTicket { throw APIError.notConfigured }
}
@MainActor private final class TicketTeamJournalFixture: TeamPendingJournal {
    var writes = 0
    func pending(ownerKey: String, targetKey: String) throws -> TeamPendingRecord? { nil }
    func write(_ record: TeamPendingRecord) throws { writes += 1; throw TeamFailure.persistence }
    func clear(_ record: TeamPendingRecord) throws { writes += 1; throw TeamFailure.persistence }
}
@MainActor private final class TicketTeamServiceFixture: TeamServing {
    var authority = TeamServiceAuthority.readOnly
    var rows: [OwnedTeam] = []
    var teamDetail: TeamDetail?
    var failure: Error?
    var beforeReply: (() async -> Void)?
    var lists = 0
    var detailIDs: [Int] = []
    var writes = 0
    func myTeams(session: TeamSession) async throws -> [OwnedTeam] {
        lists += 1; if let beforeReply { await beforeReply() }
        if let failure { throw failure }; return rows
    }
    func detail(_ lookup: TeamLookup, session: TeamSession) async throws -> TeamDetail {
        guard case .id(let id) = lookup else { throw TeamFailure.invalidRequest }
        detailIDs.append(id); if let beforeReply { await beforeReply() }
        if let failure { throw failure }; guard let teamDetail else { throw TeamFailure.invalidContract }; return teamDetail
    }
    func creationContext(ownerID: Int, session: TeamSession) async throws -> TeamCreationContext { throw TeamFailure.notConfigured }
    func submit(_ action: TeamAction, operationID: UUID, session: TeamSession) async -> TeamWriteOutcome { writes += 1; return .notSent }
    func receipt(operationID: UUID, session: TeamSession) async throws -> TeamWriteOutcome? { nil }
}
@MainActor final class TicketWalletTeamTests: XCTestCase {
    private func ticket(_ fields: [String: Any] = [:]) throws -> TicketWalletTicket {
        var value: [String: Any] = ["id": 41, "ownerType": 1, "ownerId": 9, "registrationStatus": 2]
        value.merge(fields) { _, new in new }
        return try JSONDecoder().decode(TicketWalletTicket.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func team(id: Int = 101, type: Int = 1, owner: Int = 9, status: Int = 0) throws -> OwnedTeam {
        try JSONDecoder().decode(OwnedTeam.self, from: JSONSerialization.data(withJSONObject: ["id": id, "ownerType": type, "ownerId": owner, "status": status, "title": "Synthetic team"]))
    }
    private func detail(id: Int = 101, type: Int = 1, owner: Int = 9, status: Int = 0, joined: Bool? = true) throws -> TeamDetail {
        var value: [String: Any] = ["team": ["id": id, "ownerType": type, "ownerId": owner, "status": status, "title": "Synthetic team"], "members": [["memberId": 7, "memberName": "Synthetic member", "role": 0]]]
        value["joined"] = joined
        return try JSONDecoder().decode(TeamDetail.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func session(epoch: UInt64 = 1) throws -> TeamSession {
        let account = try JSONDecoder().decode(Account.self, from: Data(#"{"id":7,"role":"player"}"#.utf8))
        return try .init(account: account, epoch: epoch, region: "CN", storageNamespace: "ticket-team-fixture", token: "synthetic-seven")
    }
    private func target(_ reader: TicketTeamReaderFixture) throws -> TicketWalletTeamEntryState.Target {
        let context = try XCTUnwrap(TicketWalletTeamContext(ticket: ticket(), requestedID: 41))
        var entry = TicketWalletTeamEntryState(); entry.appear()
        entry.activate(context: context, reader: reader, presentationID: entry.presentationID)
        return try XCTUnwrap(entry.target)
    }
    private func model(_ reader: TicketTeamReaderFixture, _ service: TicketTeamServiceFixture,
                       journal: TicketTeamJournalFixture? = nil,
                       current: (() -> TeamSession?)? = nil) throws -> TicketWalletTeamModel {
        let fixed = try session()
        let coordinator = TeamCoordinator(service: service, journal: journal ?? TicketTeamJournalFixture(), currentSession: current ?? { fixed })
        return try .init(target: target(reader), reader: reader, coordinator: coordinator)
    }
    func testTicketContextRequiresExactTypedOwnerWithoutNameOrProductInference() throws {
        XCTAssertEqual(try XCTUnwrap(TicketWalletTeamContext(ticket: ticket(), requestedID: 41)).owner, TeamOwnerKey(type: 1, id: 9))
        XCTAssertEqual(try XCTUnwrap(TicketWalletTeamContext(ticket: ticket(["ownerType": 2]), requestedID: 41)).owner, TeamOwnerKey(type: 2, id: 9))
        for invalid in [["ownerType": 3], ["ownerId": 0], ["topicId": 10], ["activityId": 9]] {
            XCTAssertNil(TicketWalletTeamContext(ticket: try ticket(invalid), requestedID: 41))
        }
        XCTAssertNil(TicketWalletTeamContext(ticket: try ticket(), requestedID: 42))
        XCTAssertNil(TicketWalletTeamContext(ticket: try ticket(), requestedID: 0))
    }
    func testNoServiceReadOccursAtConstructionOrPresentationWithoutLookup() throws {
        let reader = TicketTeamReaderFixture(), service = TicketTeamServiceFixture(), model = try model(reader, service)
        XCTAssertEqual(service.lists, 0); XCTAssertTrue(service.detailIDs.isEmpty)
        XCTAssertNotNil(model.appear()); XCTAssertEqual(service.lists, 0)
    }
    func testOwnedTeamLookupUsesExactOwnerAndKnownActiveStatesPreservingMultipleMatches() async throws {
        let reader = TicketTeamReaderFixture(), service = TicketTeamServiceFixture()
        service.rows = try [team(id: 103, status: 2), team(id: 102, status: 1), team(id: 101), team(id: 104, type: 2), team(id: 105, owner: 10), team(id: 106, status: 3), team(id: 107, status: 4), team(id: 108, status: 99)]
        let model = try model(reader, service), permit = try XCTUnwrap(model.appear())
        await model.loadTeams(presentation: permit)
        XCTAssertEqual(model.rows.map(\.id), [103, 102, 101]); XCTAssertTrue(model.loaded)
        XCTAssertTrue(service.detailIDs.isEmpty); XCTAssertNil(model.detail)
    }
    func testFailedReadCannotClaimNoTeamAndExplicitRetryCanReturnSuccessfulEmpty() async throws {
        let reader = TicketTeamReaderFixture(), service = TicketTeamServiceFixture(); service.failure = TeamFailure.unavailable
        let model = try model(reader, service), permit = try XCTUnwrap(model.appear())
        await model.loadTeams(presentation: permit); XCTAssertFalse(model.loaded); XCTAssertEqual(model.issue, .failed)
        service.failure = nil
        await model.loadTeams(presentation: permit); XCTAssertTrue(model.loaded); XCTAssertTrue(model.rows.isEmpty); XCTAssertNil(model.issue)
    }
    func testFreshJoinedExactTeamDetailIsRequiredAndNoWritesArePossible() async throws {
        let reader = TicketTeamReaderFixture(), service = TicketTeamServiceFixture(), journal = TicketTeamJournalFixture()
        let row = try team(); service.rows = [row]; service.teamDetail = try detail()
        let model = try model(reader, service, journal: journal), permit = try XCTUnwrap(model.appear())
        await model.loadTeams(presentation: permit); await model.loadDetail(row, presentation: permit)
        XCTAssertEqual(service.detailIDs, [101]); XCTAssertEqual(model.detail?.members.map(\.id), [7])
        XCTAssertEqual(service.writes, 0); XCTAssertEqual(journal.writes, 0)
    }
    func testChangedOwnerStatusIdOrMembershipNeverPublishesRoster() async throws {
        for response in [try detail(owner: 10), try detail(type: 2), try detail(status: 3), try detail(id: 102), try detail(joined: false), try detail(joined: nil)] {
            let reader = TicketTeamReaderFixture(), service = TicketTeamServiceFixture(), row = try team()
            service.rows = [row]; service.teamDetail = response
            let model = try model(reader, service), permit = try XCTUnwrap(model.appear())
            await model.loadTeams(presentation: permit); await model.loadDetail(row, presentation: permit)
            XCTAssertNil(model.detail); XCTAssertNotNil(model.issue)
        }
    }
    func testUnlistedOrUnrelatedTeamCannotDispatchDetail() async throws {
        let reader = TicketTeamReaderFixture(), service = TicketTeamServiceFixture(); service.rows = [try team()]
        let model = try model(reader, service), permit = try XCTUnwrap(model.appear())
        await model.loadTeams(presentation: permit)
        await model.loadDetail(try team(id: 102), presentation: permit)
        await model.loadDetail(try team(owner: 10), presentation: permit)
        XCTAssertTrue(service.detailIDs.isEmpty)
    }
    func testQueuedLookupAfterDepartureAndOldPermitAfterReopenCannotDispatch() async throws {
        let reader = TicketTeamReaderFixture(), service = TicketTeamServiceFixture(), model = try model(reader, service)
        let old = try XCTUnwrap(model.appear()); let queued = { await model.loadTeams(presentation: old) }
        model.end(); await queued(); XCTAssertEqual(service.lists, 0)
        let current = try XCTUnwrap(model.appear()); XCTAssertNotEqual(old, current)
        await model.loadTeams(presentation: current); XCTAssertEqual(service.lists, 1); XCTAssertTrue(model.loaded)
        await queued(); XCTAssertEqual(service.lists, 1); XCTAssertTrue(model.loaded)
    }
    func testLateTicketReaderChangeOrTeamSessionChangeCannotPublish() async throws {
        for changeTeamSession in [false, true] {
            let reader = TicketTeamReaderFixture(), service = TicketTeamServiceFixture(); service.rows = [try team()]
            var current: TeamSession? = try session()
            let model = try model(reader, service, current: { current }), permit = try XCTUnwrap(model.appear())
            service.beforeReply = { if changeTeamSession { current = nil } else { reader.scope = UUID() } }
            await model.loadTeams(presentation: permit)
            XCTAssertFalse(model.ownerIsCurrent); XCTAssertFalse(model.loaded); XCTAssertTrue(model.rows.isEmpty)
        }
    }
    func testEntryRejectsDuplicateAndRetiredTapsButRetainsActivePushTarget() throws {
        let reader = TicketTeamReaderFixture(), context = try XCTUnwrap(TicketWalletTeamContext(ticket: ticket(), requestedID: 41))
        var entry = TicketWalletTeamEntryState(); entry.appear(); let permit = entry.presentationID
        entry.activate(context: context, reader: reader, presentationID: permit); let target = try XCTUnwrap(entry.target)
        entry.activate(context: context, reader: reader, presentationID: permit); XCTAssertEqual(entry.target, target)
        entry.disappear(); XCTAssertTrue(entry.matches(target, context: context, reader: reader))
        entry.retire(); entry.activate(context: context, reader: reader, presentationID: permit); XCTAssertNil(entry.target)
    }
    func testDuplicateTeamIdsRejectAmbiguousProjectionAndUnknownCountsRemainUnknown() async throws {
        let reader = TicketTeamReaderFixture(), service = TicketTeamServiceFixture(), row = try team()
        XCTAssertNil(row.joinedCount); XCTAssertNil(row.maxMembers)
        service.rows = [row, row]
        let model = try model(reader, service), permit = try XCTUnwrap(model.appear())
        await model.loadTeams(presentation: permit); XCTAssertFalse(model.loaded); XCTAssertEqual(model.issue, .failed)
    }
    func testUnconfiguredCoordinatorCannotStartAndScopeReplacementRejectsSavedTarget() throws {
        let reader = TicketTeamReaderFixture(), service = TicketTeamServiceFixture(); service.authority = .unconfigured
        let model = try model(reader, service); XCTAssertNil(model.appear()); XCTAssertEqual(model.issue, .unavailable)
        let saved = try target(reader); reader.scope = UUID()
        let coordinator = TeamCoordinator(service: service, journal: TicketTeamJournalFixture(), currentSession: { nil })
        let stale = TicketWalletTeamModel(target: saved, reader: reader, coordinator: coordinator)
        XCTAssertNil(stale.appear()); XCTAssertFalse(stale.ownerIsCurrent); XCTAssertEqual(service.lists, 0)
    }
}
