import XCTest
@testable import QuestifyCore

final class ClubOpsGovernanceInactiveReadTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81)
    private let ban = ClubGovernanceValue.object(["id": .integer(9), "clubId": .integer(81), "status": .string("ACTIVE"), "sourceType": .string("CLUB"),
        "banReason": .string("Synthetic"), "bannedAt": .string("2026-10-01 08:00:00"), "expiresAt": .string("2026-10-31 08:00:00")])
    private func inactive(club: Int = 81) -> ClubGovernanceValue {
        .object(["active": .bool(false), "club": .object(["id": .integer(club)]), "permissions": .array([]), "roleCodes": .array([])])
    }
    private func read(_ operation: ClubGovernanceRead, wire: Wire) async throws -> ClubGovernanceSnapshot {
        let service = ClubGovernanceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire)
        return try await service.read(operation, scope: scope, session: .init(accountID: 701, epoch: 1, token: "synthetic"), check: {})
    }

    func testBannedViewerReadsOwnCasesWithActiveBanButNothingElse() async throws {
        let wire = Wire(access: inactive(), cases: .object(["code": .integer(200), "data": .array([]), "activeBan": ban]))
        let snapshot = try await read(.cases, wire: wire)
        XCTAssertNil(snapshot.permissions)
        let list = try ClubOpsCaseList(snapshot: snapshot)
        guard case .ban(let active) = list.appeal else { return XCTFail("known active ban must offer the appeal") }
        XCTAssertEqual(active.id, 9); XCTAssertEqual(active.source, .club); XCTAssertFalse(list.canReport)
        do { _ = try await read(.bans, wire: wire); XCTFail("inactive viewer must not read governance records") }
        catch { XCTAssertEqual(error as? ClubGovernanceFailure, .forbidden) }
    }
    func testInactiveAnswerForAnotherClubNeverOpensOwnCases() async throws {
        let wire = Wire(access: inactive(club: 82), cases: .object(["code": .integer(200), "data": .array([]), "activeBan": ban]))
        do { _ = try await read(.cases, wire: wire); XCTFail("mismatched club must fail closed") }
        catch { XCTAssertNotNil(error as? ClubGovernanceFailure) }
        XCTAssertEqual(wire.paths, ["/" + ClubGovernanceRead.access.path])
    }

    private final class Wire: HTTPTransport {
        let access: ClubGovernanceValue, cases: ClubGovernanceValue
        var paths: [String] = []
        init(access: ClubGovernanceValue, cases: ClubGovernanceValue) { self.access = access; self.cases = cases }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let path = request.url?.path ?? ""; paths.append(path)
            let body: ClubGovernanceValue = path == "/" + ClubGovernanceRead.access.path
                ? .object(["code": .integer(200), "data": access]) : path == "/" + ClubGovernanceRead.cases.path ? cases : .object(["code": .integer(200), "data": .array([])])
            return (try JSONEncoder().encode(body), 200)
        }
    }
}
