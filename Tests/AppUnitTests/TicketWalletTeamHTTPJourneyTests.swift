import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Questify

/// HTTP-level read journeys using the production read-only team service.
@MainActor final class TicketWalletTeamHTTPJourneyTests: XCTestCase {
    @MainActor private final class TicketReader: TicketWalletReading {
        var scope = UUID()
        var isConfigured = true
        var isAuthenticated = true
        var isOfflineExample = true
        func ticketWallet() async throws -> TicketWalletSnapshot { .init(tickets: []) }
        func ticketDetail(id: Int) async throws -> TicketWalletTicket { throw APIError.notConfigured }
    }
    @MainActor private final class Journal: TeamPendingJournal {
        var mutations = 0
        func pending(ownerKey: String, targetKey: String) throws -> TeamPendingRecord? { nil }
        func write(_ record: TeamPendingRecord) throws { mutations += 1; throw TeamFailure.persistence }
        func clear(_ record: TeamPendingRecord) throws { mutations += 1; throw TeamFailure.persistence }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var fail = false
        var joined = true
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            if fail { throw URLError(.networkConnectionLost) }
            let payload: String
            switch request.url?.path {
            case "/api/team/my":
                payload = #"[{"id":101,"ownerType":1,"ownerId":9,"status":0,"title":"Synthetic team"},{"id":102,"ownerType":1,"ownerId":99,"status":0,"title":"Other owner"}]"#
            case "/api/team/info":
                payload = "{\"team\":{\"id\":101,\"ownerType\":1,\"ownerId\":9,\"status\":0,\"title\":\"Synthetic team\"},\"members\":[{\"memberId\":7,\"memberName\":\"Synthetic member\",\"role\":0}],\"joined\":\(joined)}"
            default: XCTFail("Read-only ticket journey attempted another endpoint"); throw TeamFailure.invalidRequest
            }
            return (Data("{\"code\":200,\"data\":\(payload)}".utf8), 200)
        }
    }
    @MainActor private final class Harness {
        let reader = TicketReader(), journal = Journal(), wire = Wire()
        var session: TeamSession?
        let configuration: APIConfiguration
        let approval: OperationEndpointApproval
        lazy var service = TeamReadOnlyService(configuration: configuration, transport: wire,
            readApproval: approval, currentSession: { [weak self] in self?.session }, requiresIDMembership: true)
        lazy var coordinator = TeamCoordinator(service: service, journal: journal, currentSession: { [weak self] in self?.session })
        init() throws {
            let account = try JSONDecoder().decode(Account.self, from: Data(#"{"id":7,"role":"player"}"#.utf8))
            session = try TeamSession(account: account, epoch: 1, region: "CN", storageNamespace: "ticket-http-test", token: "synthetic-ticket-token")
            configuration = try APIConfiguration(baseURL: URL(string: "https://ticket.example.test")!)
            approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: "ticket-http-test", accountID: 7, paths: ["api/team/my", "api/team/info"])
        }
        func model() throws -> TicketWalletTeamModel {
            let ticket = try JSONDecoder().decode(TicketWalletTicket.self, from: Data(#"{"id":41,"ownerType":1,"ownerId":9,"registrationStatus":2}"#.utf8))
            let context = try XCTUnwrap(TicketWalletTeamContext(ticket: ticket, requestedID: 41))
            var entry = TicketWalletTeamEntryState(); entry.appear()
            entry.activate(context: context, reader: reader, presentationID: entry.presentationID)
            return TicketWalletTeamModel(target: try XCTUnwrap(entry.target), reader: reader, coordinator: coordinator)
        }
    }
    func testOwnedTicketListThenJoinedDetailUsesExactReadBodiesAndNoJournalWrites() async throws {
        let h = try Harness(), model = try h.model()
        XCTAssertTrue(h.wire.requests.isEmpty)
        let permit = try XCTUnwrap(model.appear())
        await model.loadTeams(presentation: permit)
        XCTAssertEqual(model.rows.map(\.id), [101])
        let row = try XCTUnwrap(model.rows.first)
        await model.loadDetail(row, presentation: permit)
        XCTAssertEqual(model.detail?.team.id, 101)
        XCTAssertEqual(model.detail?.joined, true)
        XCTAssertEqual(h.wire.requests.compactMap { $0.url?.path }, ["/api/team/my", "/api/team/info"])
        let first = try XCTUnwrap(h.wire.requests.first?.httpBody)
        XCTAssertEqual(try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any]).count, 0)
        let body = try XCTUnwrap(h.wire.requests.last?.httpBody)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Int])
        XCTAssertEqual(fields, ["teamId": 101])
        XCTAssertTrue(h.wire.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "synthetic-ticket-token" })
        XCTAssertEqual(h.journal.mutations, 0)
    }
    func testFreshHTTPMembershipLossDoesNotRetainPreviouslyVisibleRoster() async throws {
        let h = try Harness(), model = try h.model(), permit = try XCTUnwrap(model.appear())
        await model.loadTeams(presentation: permit)
        let row = try XCTUnwrap(model.rows.first)
        await model.loadDetail(row, presentation: permit)
        XCTAssertNotNil(model.detail)
        h.wire.joined = false
        await model.loadDetail(row, presentation: permit)
        XCTAssertNil(model.detail)
        XCTAssertEqual(model.issue, .failed)
        XCTAssertEqual(h.journal.mutations, 0)
    }
    func testEndedVisitDropsLateHTTPListAndForegroundRequiresNewPermit() async throws {
        let h = try Harness(), model = try h.model(), old = try XCTUnwrap(model.appear())
        h.wire.beforeReply = { model.end() }
        await model.loadTeams(presentation: old)
        XCTAssertTrue(model.rows.isEmpty); XCTAssertNil(model.presentation)
        h.wire.beforeReply = nil
        await model.loadTeams(presentation: old)
        XCTAssertEqual(h.wire.requests.count, 1)
        let fresh = try XCTUnwrap(model.appear()); XCTAssertNotEqual(old, fresh)
        await model.loadTeams(presentation: fresh)
        XCTAssertEqual(model.rows.map(\.id), [101])
        XCTAssertEqual(h.wire.requests.count, 2)
        XCTAssertEqual(h.journal.mutations, 0)
    }
    func testTransientHTTPFailureCanReloadButChangedAccountCannotAcceptReply() async throws {
        let h = try Harness(), model = try h.model(), permit = try XCTUnwrap(model.appear())
        h.wire.fail = true
        await model.loadTeams(presentation: permit)
        XCTAssertEqual(model.issue, .failed); XCTAssertTrue(model.rows.isEmpty)
        h.wire.fail = false
        await model.loadTeams(presentation: permit)
        XCTAssertEqual(model.rows.map(\.id), [101])
        h.wire.beforeReply = { h.session = nil; h.reader.scope = UUID(); h.reader.isAuthenticated = false }
        await model.loadTeams(presentation: permit)
        XCTAssertFalse(model.ownerIsCurrent); XCTAssertTrue(model.rows.isEmpty); XCTAssertNil(model.detail)
        let count = h.wire.requests.count
        await model.loadTeams(presentation: permit)
        XCTAssertEqual(h.wire.requests.count, count)
        XCTAssertEqual(h.journal.mutations, 0)
    }
}
