import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ClubViewerUnavailableCurrentContractTests: XCTestCase {
    private func record(_ fields: [String: Any] = [:]) throws -> ClubRecord {
        var value = fields; value["id"] = 7
        return try JSONDecoder().decode(ClubRecord.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func session() throws -> ClubActionSession {
        let account = try JSONDecoder().decode(Account.self, from: Data(#"{"id":1,"role":"player"}"#.utf8))
        return try .init(account: account, epoch: 1, token: "synthetic-token")
    }
    private func service(_ transport: UnavailableViewerTransport) throws -> ClubActionService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }

    func testExplicitUnavailableFencesDefaultAndContradictoryMembershipFlags() throws {
        let variants: [[String: Any]] = [[:], ["joinPolicy": 1], ["myJoinStatus": 2, "joinPolicy": 1],
            ["isJoined": true], ["isOwner": true], ["viewerIsAdmin": true], ["myJoinStatus": 0],
            ["isOwner": true, "isJoined": true, "viewerIsAdmin": true]]
        for var fields in variants {
            fields["viewerIdentityUnavailable"] = true
            let club = try record(fields)
            XCTAssertEqual(ClubActionAvailability.resolve(club, viewerIsMerchant: false), .unsupportedStatus)
            XCTAssertEqual(ClubActionAvailability.resolve(club, viewerIsMerchant: false), .unsupportedStatus)
            XCTAssertEqual(ClubActionAvailability.resolve(club, viewerIsMerchant: true), .unsupportedStatus)
            if case .available = ClubActionAvailability.resolve(club, viewerIsMerchant: true) {
                XCTFail("An unapproved merchant cannot acquire a membership action")
            }
        }
    }

    func testKnownViewerAndLegacyAbsentFlagKeepExistingActionMatrix() throws {
        let cases: [([String: Any], ClubActionAvailability)] = [
            ([:], .available(.join)), (["joinPolicy": 1], .available(.apply)),
            (["myJoinStatus": 2, "joinPolicy": 1], .available(.apply)),
            (["myJoinStatus": 0], .pending), (["myJoinStatus": 9], .unsupportedStatus),
            (["isJoined": true], .available(.leave)), (["isOwner": true], .owner),
            (["viewerIsAdmin": true], .available(.join))]
        for (fields, expected) in cases {
            XCTAssertEqual(ClubActionAvailability.resolve(try record(fields), viewerIsMerchant: false), expected)
            var explicit = fields; explicit["viewerIdentityUnavailable"] = false
            XCTAssertEqual(ClubActionAvailability.resolve(try record(explicit), viewerIsMerchant: false), expected)
        }
        XCTAssertEqual(ClubActionAvailability.resolve(try record(), viewerIsMerchant: true), .merchant)
    }

    func testPrepareFreshUnavailableReadCannotStageOrReserveAndKnownReentryWorks() async throws {
        let store = UnavailableViewerStore(detail: try record(["viewerIdentityUnavailable": true, "joinPolicy": 1]))
        let journal = UnavailableViewerJournal(), coordinator = ClubActionCoordinator(writer: store, reader: store, journal: journal)
        do {
            _ = try await coordinator.prepare(clubID: 7, action: .apply, expectedIdentity: store.clubIdentity, joinMessage: "Reviewed message")
            XCTFail("Unavailable viewer reached confirmation")
        } catch { XCTAssertEqual(error as? ClubActionBlock, .eligibilityChanged) }
        XCTAssertEqual(store.reads, 1); XCTAssertEqual(store.writes, 0); XCTAssertEqual(journal.reservations, 0)
        XCTAssertEqual(coordinator.state(clubID: 7), .idle)
        store.detail = try record(["joinPolicy": 1, "viewerIdentityUnavailable": false])
        let confirmation = try await coordinator.prepare(clubID: 7, action: .apply,
            expectedIdentity: store.clubIdentity, joinMessage: "Reviewed message")
        XCTAssertEqual(confirmation.action, .apply); XCTAssertEqual(confirmation.joinMessage, "Reviewed message")
        coordinator.cancel(confirmation)
        XCTAssertEqual(store.writes, 0); XCTAssertNil(journal.pendingValue)
    }

    func testLastFreshWriterPreflightRejectsJoinApplyAndLeaveWithoutDispatch() async throws {
        let current = try session()
        for action in [ClubAction.join, .apply, .leave] {
            var fields: [String: Any] = ["id": 7, "viewerIdentityUnavailable": true]
            if action == .apply { fields["joinPolicy"] = 1 }
            if action == .leave { fields["isJoined"] = true }
            var paths: [String] = []
            let transport = UnavailableViewerTransport { request in
                paths.append(try XCTUnwrap(request.url?.path))
                return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": fields]), 200)
            }
            let writer = ClubActionSessionWriter(service: try service(transport), currentSession: { current })
            do {
                _ = try await writer.perform(action, clubID: 7, expectedIdentity: current.identity,
                    joinMessage: action == .apply ? "Reviewed message" : "")
                XCTFail("Unavailable viewer dispatched a mutation")
            } catch { XCTAssertEqual(error as? ClubActionWriteError, .eligibilityChanged) }
            XCTAssertEqual(paths, ["/fixture/api/club/detail"])
        }
    }

    func testOldPreparedIntentCannotWriteWhenFinalDetailBecomesUnavailable() async throws {
        let current = try session(), store = UnavailableViewerStore(detail: try record(["joinPolicy": 1]))
        var paths: [String] = []
        let transport = UnavailableViewerTransport { request in
            paths.append(try XCTUnwrap(request.url?.path))
            return (Data(#"{"code":200,"data":{"id":7,"joinPolicy":1,"viewerIdentityUnavailable":true}}"#.utf8), 200)
        }
        let writer = ClubActionSessionWriter(service: try service(transport), currentSession: { current })
        let journal = UnavailableViewerJournal(), coordinator = ClubActionCoordinator(writer: writer, reader: store, journal: journal)
        let pending = try await coordinator.prepare(clubID: 7, action: .apply, expectedIdentity: current.identity, joinMessage: "Reviewed message")
        _ = await coordinator.confirm(pending)
        XCTAssertEqual(paths, ["/fixture/api/club/detail"])
        XCTAssertEqual(coordinator.state(clubID: 7), .notSent)
        XCTAssertEqual(journal.reservations, 1); XCTAssertNil(journal.pendingValue)
    }

    func testKnownViewerStillDispatchesExactJoinApplyAndLeaveOnce() async throws {
        let current = try session()
        for action in [ClubAction.join, .apply, .leave] {
            var fields: [String: Any] = ["id": 7, "viewerIdentityUnavailable": false]
            if action == .apply { fields["joinPolicy"] = 1 }
            if action == .leave { fields["isJoined"] = true }
            var paths: [String] = []
            let transport = UnavailableViewerTransport { request in
                paths.append(try XCTUnwrap(request.url?.path))
                let data = paths.count == 1
                    ? try JSONSerialization.data(withJSONObject: ["code": 200, "data": fields])
                    : Data(#"{"code":200,"data":{"state":"original-state"}}"#.utf8)
                return (data, 200)
            }
            let writer = ClubActionSessionWriter(service: try service(transport), currentSession: { current })
            let receipt = try await writer.perform(action, clubID: 7, expectedIdentity: current.identity,
                joinMessage: action == .apply ? "Reviewed message" : "")
            XCTAssertEqual(receipt.state, "original-state")
            XCTAssertEqual(paths, ["/fixture/api/club/detail", action == .leave ? "/fixture/api/club/quit" : "/fixture/api/club/join"])
        }
    }

    func testDeniedConfigurationAndChangedEpochStillNeverDispatch() async throws {
        var current: ClubActionSession? = try session()
        let expected = try XCTUnwrap(current).identity
        let unconfigured = ClubActionSessionWriter(service: nil, currentSession: { current })
        do { _ = try await unconfigured.perform(.join, clubID: 7, expectedIdentity: expected); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.notConfigured)) }
        for denied in [true, false] {
            current = try session()
            var paths: [String] = []
            let transport = UnavailableViewerTransport { request in
                paths.append(try XCTUnwrap(request.url?.path))
                if !denied {
                    let account = try JSONDecoder().decode(Account.self, from: Data(#"{"id":1,"role":"player"}"#.utf8))
                    current = try .init(account: account, epoch: 2, token: "replacement-token")
                }
                return (Data((denied ? #"{"code":403,"msg":"Denied"}"# : #"{"code":200,"data":{"id":7}}"#).utf8), 200)
            }
            let writer = ClubActionSessionWriter(service: try service(transport), currentSession: { current })
            do { _ = try await writer.perform(.join, clubID: 7, expectedIdentity: expected); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, denied ? .preflightFailed : .notSent(.unauthorized)) }
            XCTAssertEqual(paths, ["/fixture/api/club/detail"])
        }
    }

    func testUnavailableCurrentObservationNeverRetiresExistingUnknown() async throws {
        let store = UnavailableViewerStore(detail: try record()), journal = UnavailableViewerJournal()
        store.unknown = true
        let coordinator = ClubActionCoordinator(writer: store, reader: store, journal: journal)
        let pending = try await coordinator.prepare(clubID: 7, action: .join, expectedIdentity: store.clubIdentity)
        _ = await coordinator.confirm(pending)
        let original = try XCTUnwrap(journal.pendingValue)
        store.detail = try record(["viewerIdentityUnavailable": true])
        _ = await coordinator.readBack(clubID: 7)
        guard case .outcomeUnknown = coordinator.state(clubID: 7) else { return XCTFail("Current detail settled original UNKNOWN") }
        XCTAssertEqual(journal.pendingValue, original); XCTAssertEqual(store.writes, 1)
        XCTAssertEqual(ClubActionAvailability.resolve(store.detail, viewerIsMerchant: false), .unsupportedStatus)
        let restarted = ClubActionCoordinator(writer: store, reader: store, journal: journal)
        guard case .outcomeUnknown = restarted.state(clubID: 7) else { return XCTFail("Restart lost original fence") }
        _ = await restarted.readBack(clubID: 7)
        XCTAssertEqual(journal.pendingValue, original); XCTAssertEqual(store.writes, 1)
    }
}

private final class UnavailableViewerTransport: HTTPTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
@MainActor private final class UnavailableViewerJournal: ClubOrdinaryAdmissionJournaling {
    var pendingValue: ClubOrdinaryAdmissionPending?
    var reservations = 0
    func pending(accountID: Int, clubID: Int) throws -> ClubOrdinaryAdmissionPending? {
        guard pendingValue?.accountID == accountID, pendingValue?.clubID == clubID else { return nil }; return pendingValue
    }
    func reserve(_ value: ClubOrdinaryAdmissionPending) throws {
        guard pendingValue == nil else { throw APIError.invalidRequest }
        pendingValue = value; reservations += 1
    }
    func retire(_ value: ClubOrdinaryAdmissionPending) throws {
        guard pendingValue == value else { throw APIError.invalidRequest }; pendingValue = nil
    }
}
@MainActor private final class UnavailableViewerStore: ClubReading, ClubActionWriting {
    var detail: ClubRecord
    var clubIdentity = ClubReadIdentity(accountID: 1, epoch: 1)
    var identity: ClubReadIdentity? { clubIdentity }
    var isConfigured = true
    var isClubConfigured: Bool { isConfigured }
    let viewerIsMerchant = false
    var reads = 0, writes = 0
    var unknown = false
    init(detail: ClubRecord) { self.detail = detail }
    func clubDetail(id: Int) async throws -> ClubRecord { reads += 1; return detail }
    func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity, joinMessage: String) async throws -> ClubActionReceipt {
        writes += 1
        if unknown { throw ClubActionWriteError.outcomeUnknown(.transport) }
        return .init(state: nil, message: nil)
    }
    func clubHome() async throws -> ClubHome { throw APIError.notConfigured }
    func clubOwned() async throws -> [ClubRecord] { throw APIError.notConfigured }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw APIError.notConfigured }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw APIError.notConfigured }
}
