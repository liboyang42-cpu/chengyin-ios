import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityParticipationFormTests: XCTestCase {
    private static let teamID = "00000000-0000-0000-0000-000000000001"
    private static let inviteCode = "00000000-0000-0000-0000-000000000002"
    private static let sessionID = "00000000-0000-0000-0000-000000000003"
    private static var binding: [String: Any] { ["releaseId": 12, "regionId": "region", "boardId": "board", "seasonId": "season", "rulesReleaseId": "rules",
        "contentHash": String(repeating: "a", count: 64), "revision": 2, "title": "Frozen original",
        "rules": ["mode": "CITY_TEAM", "minMembers": 2, "maxMembers": 6, "joinPolicy": "INVITE_CODE", "rosterPolicy": "CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM",
                  "replacementPolicy": "FORBIDDEN_AFTER_LOCK", "reentryPolicy": "RESUME_ORIGINAL_SESSION", "roundPolicy": "FIXED_PUBLISHED_ROUND", "roundId": "round"]] }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var writeApproved = true
        var team: [String: Any]?
        var inviteBinding = CityParticipationFormTests.binding
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            if request.httpMethod == "POST" {
                let command = try JSONDecoder().decode(CityParticipationCommand.self, from: XCTUnwrap(request.httpBody))
                return (try JSONSerialization.data(withJSONObject: ["code": 202, "errorCode": "OUTCOME_UNKNOWN", "data": ["requestId": command.requestId, "requestStatus": "UNKNOWN"]]), 202)
            }
            if request.url?.path.hasSuffix("/invite") == true {
                return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["binding": inviteBinding, "teamId": CityParticipationFormTests.teamID, "version": 7, "memberCount": 2]]), 200)
            }
            var data: [String: Any] = ["contract": "CITY_TEAM_PARTICIPATION_V1", "scope": "CITY", "status": "NOT_JOINED", "writeApproved": writeApproved,
                "pointsStatus": "UNAVAILABLE", "taskExecutionStatus": "UNAVAILABLE", "actionBudgetStatus": "UNAVAILABLE", "binding": CityParticipationFormTests.binding]
            if let team {
                data["team"] = team
                data["status"] = team["present"] as? Bool == true && team["confirmed"] as? Bool == true ? "JOINED" : "PENDING"
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
    }
    @MainActor private final class Harness {
        let api: APIConfiguration
        let scope: CityParticipationCommandScope
        let readScope: CityParticipationReadScope
        let wire = Wire()
        let journal: CityParticipationCommandJournal
        var current: CityParticipationCommandScope?
        var writeGrant: CityParticipationCommandGrant?
        var inviteGrant: CityParticipationInvitationGrant?
        var readGrant: CityParticipationReadGrant?
        init() throws {
            api = try .init(baseURL: URL(string: "https://city.example.test/native/")!)
            scope = try .init(market: .china, baseURL: api.baseURL, namespace: "form-test", accountID: 7, epoch: 1, token: "fake-token")
            readScope = try .init(market: .china, baseURL: api.baseURL, namespace: "form-test", accountID: 7, epoch: 1, token: "fake-token", regionID: "region")
            current = scope; readGrant = .init(scope: readScope)
            journal = try .init(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        }
        func inviteReader() -> CityParticipationInvitationReader {
            .init(configuration: api, transport: wire, currentScope: { self.current }, grant: { self.inviteGrant })
        }
        func model(approval: Bool = false, interruptApproval: Bool = false) -> CityParticipationFormModel {
            let recovery = CityParticipationCommandRecovery(configuration: api, transport: wire, journal: journal,
                currentScope: { self.current }, grant: { self.writeGrant })
            let reader = CityParticipationStateReader(configuration: api, transport: wire,
                currentScope: { self.current == self.scope ? self.readScope : nil }, grant: { self.readGrant })
            let approve: (@MainActor (CityParticipationCommand) async -> Bool)?
            if approval {
                approve = { command in
                    if interruptApproval { self.current = nil }
                    self.writeGrant = try? .init(scope: self.scope, command: command)
                    return self.writeGrant != nil
                }
            } else { approve = nil }
            return .init(regionID: "region", recovery: recovery, currentScope: { self.current }, stateReader: reader,
                         invitationReader: inviteReader(), approve: approve)
        }
        func approveInvite() { inviteGrant = .init(scope: scope, regionID: "region", code: CityParticipationFormTests.inviteCode) }
    }
    private func team(present: Bool = true, confirmed: Bool = false, locked: Bool = false, captain: Bool = true) -> [String: Any] {
        var t: [String: Any] = ["teamId": Self.teamID, "version": 4, "state": locked ? "LOCKED" : "FORMING", "captain": captain,
            "memberCount": 2, "presentCount": present ? 2 : 1, "confirmedCount": confirmed ? 2 : 0, "present": present, "confirmed": confirmed]
        if locked { t["session"] = ["sessionId": Self.sessionID, "version": 3, "state": "AWAITING_CONFIRMATION"] }
        return t
    }
    func testServerWriteApprovedDoesNotCreateApprovalOrPost() async throws {
        let h = try Harness(), model = h.model(); await model.open(); model.prepare(.create); await model.submitPrepared()
        XCTAssertFalse(model.hasApprovalHost); XCTAssertNotNil(model.prepared); XCTAssertTrue(h.wire.requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertNil(try h.journal.load(h.scope))
    }
    func testJoinUsesOnlyReadInvitationVersionAndFrozenBinding() async throws {
        let h = try Harness(); h.approveInvite(); let model = h.model(approval: true)
        await model.open(); model.prepare(.join); XCTAssertNil(model.prepared)
        await model.inspectInvite(Self.inviteCode); model.prepare(.join)
        let command = try XCTUnwrap(model.prepared)
        XCTAssertEqual(command.teamId, Self.teamID); XCTAssertEqual(command.expectedVersion, 7); XCTAssertEqual(command.releaseId, 12)
        XCTAssertEqual(command.inviteCode, Self.inviteCode)
        await model.submitPrepared(); XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertEqual(model.recovery.display, .unknown); XCTAssertTrue(model.availableKinds.isEmpty)
        XCTAssertEqual(try h.journal.load(h.scope)?.bytes, try command.wireBytes())
    }
    func testChangedInviteBindingAndEditedCodeNeverReuseOldTeam() async throws {
        let h = try Harness(); h.approveInvite(); let model = h.model(approval: true); await model.open()
        h.wire.inviteBinding["releaseId"] = 13; await model.inspectInvite(Self.inviteCode); XCTAssertNil(model.invitation)
        h.wire.inviteBinding = Self.binding; await model.inspectInvite(Self.inviteCode); model.prepare(.join); XCTAssertNotNil(model.prepared)
        model.invitationInputChanged(); XCTAssertNil(model.invitation); XCTAssertNil(model.prepared)
    }
    func testRosterAndOriginalPersonalStateOfferCorrectKindsWithoutGrant() async throws {
        let h = try Harness(), model = h.model()
        h.wire.team = team(); await model.open(); XCTAssertEqual(model.availableKinds, [.lock, .exit])
        h.wire.team = team(locked: true, captain: false); await model.open(); XCTAssertEqual(model.availableKinds, [.confirm, .exit])
        h.wire.team = team(present: false, confirmed: true, locked: true, captain: false); await model.open()
        XCTAssertEqual(model.availableKinds, [.resume]); model.prepare(.resume)
        XCTAssertEqual(model.prepared?.teamId, Self.teamID); XCTAssertEqual(model.prepared?.expectedVersion, 4)
    }
    func testAccountChangesDuringReadOrApprovalCannotSubmit() async throws {
        let h = try Harness(), model = h.model(approval: true, interruptApproval: true)
        await model.open(); model.prepare(.create); await model.submitPrepared()
        XCTAssertNil(model.state); XCTAssertNil(model.prepared); XCTAssertFalse(h.wire.requests.contains { $0.httpMethod == "POST" })
        h.current = h.scope; h.wire.beforeReply = { h.current = nil }; await model.open(); XCTAssertNil(model.state)
    }
    func testInvitationNilOrRevokedGrantNeverDispatches() async throws {
        let h = try Harness(), reader = h.inviteReader()
        do { _ = try await reader.read(scope: h.scope, regionID: "region", code: Self.inviteCode); XCTFail("Expected disabled") } catch {}
        h.approveInvite(); h.inviteGrant?.revoke()
        do { _ = try await reader.read(scope: h.scope, regionID: "region", code: Self.inviteCode); XCTFail("Expected disabled") } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testBackendWriteDisabledHidesAllCommandCandidates() async throws {
        let h = try Harness(); h.wire.writeApproved = false; let model = h.model(approval: true)
        await model.open(); XCTAssertTrue(model.availableKinds.isEmpty); model.prepare(.create); XCTAssertNil(model.prepared)
    }
    func testEditedInputDuringReadDiscardsLateInvitation() async throws {
        let h = try Harness(); h.approveInvite(); let model = h.model(approval: true); await model.open()
        h.wire.beforeReply = { model.invitationInputChanged() }
        await model.inspectInvite(Self.inviteCode)
        XCTAssertNil(model.invitation); model.prepare(.join); XCTAssertNil(model.prepared)
        XCTAssertFalse(h.wire.requests.contains { $0.httpMethod == "POST" })
    }

}
