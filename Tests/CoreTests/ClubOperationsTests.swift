import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

private let opsIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
private func opsProfile(owner: Bool = true, admin: Bool = false, supportsJoin: Bool = true) throws -> ClubOperationsProfile {
    try JSONDecoder().decode(ClubOperationsProfile.self, from: Data("""
    {"id":81,"name":"Fixture club","city":"Fixture city","isOwner":\(owner),"viewerIsAdmin":\(admin),"isJoined":true,"clubType":"兴趣社群","activityPrefs":"轻社交","joinPolicySupported":\(supportsJoin),"prioritySignupEnabled":1,"memberReservedQuota":4,"publicVisible":1,"memberPostAllowed":0,"merchantUndertakeOpen":1}
    """.utf8))
}
private func opsMembers(_ json: String = #"[{"memberId":701,"isOwner":true,"role":1},{"memberId":704,"role":0}]"#) throws -> [ClubMember] {
    try JSONDecoder().decode([ClubMember].self, from: Data(json.utf8))
}
private func opsSnapshot(owner: Bool = true, admin: Bool = false) throws -> ClubOperationsSnapshot {
    .init(target: .club(81), profile: try opsProfile(owner: owner, admin: admin), members: try opsMembers())
}
private func opsCreateDraft() -> ClubOperationsDraft {
    var d = ClubOperationsDraft(); d.name = "New club"; d.city = "New city"; d.clubType = "兴趣社群"; return d
}

final class ClubOperationsContractTests: XCTestCase {
    func testCanonicalValuesRemainSourceValues() {
        XCTAssertEqual(ClubOperationsCatalog.types.count, 6); XCTAssertEqual(ClubOperationsCatalog.directions.count, 10)
        XCTAssertTrue(ClubOperationsCatalog.directions.contains("RPG体验"))
    }
    func testCreateRequiresServerLeaderAndBelowLimit() throws {
        let command = ClubOperationsCommand.create(opsCreateDraft())
        XCTAssertNoThrow(try command.validate(snapshot: .init(target: .create, accountRole: "club", ownedClubIDs: [81]), identity: opsIdentity))
        for role in ["merchant", "player", "", "owner"] {
            XCTAssertThrowsError(try command.validate(snapshot: .init(target: .create, accountRole: role), identity: opsIdentity))
        }
        for ids in [[81,82], [81,81], [81,82,83]] {
            XCTAssertThrowsError(try command.validate(snapshot: .init(target: .create, accountRole: "club", ownedClubIDs: ids), identity: opsIdentity))
        }
    }
    func testRequiredFieldsLengthsDirectionsAndQuotaFailClosed() throws {
        var draft = opsCreateDraft()
        draft.name = " \n "; XCTAssertThrowsError(try draft.validate(original: nil))
        draft = opsCreateDraft(); draft.name = String(repeating: "x", count: 31); XCTAssertThrowsError(try draft.validate(original: nil))
        draft = opsCreateDraft(); draft.activityPrefs = Array(ClubOperationsCatalog.directions.prefix(4)); XCTAssertThrowsError(try draft.validate(original: nil))
        draft.activityPrefs = ["轻社交", "轻社交"]; XCTAssertThrowsError(try draft.validate(original: nil))
        draft = opsCreateDraft(); draft.logo = "https://example.com/upload.png"; XCTAssertThrowsError(try draft.validate(original: nil))
        for invalid in ["-1", "1.5", "99999999999999999999999999999999", "１２", "two"] {
            draft = opsCreateDraft(); draft.memberReservedQuota = invalid; XCTAssertThrowsError(try draft.validate(original: nil))
        }
    }
    func testEditPreservesLegacyTypeAndUnknownDirectionsWhenUnchanged() throws {
        let old = try JSONDecoder().decode(ClubOperationsProfile.self, from: Data(#"{"id":81,"name":"Old","city":"City","clubType":"legacy type","activityPrefs":"legacy direction","isOwner":true}"#.utf8))
        var draft = ClubOperationsDraft(profile: old)
        XCTAssertNoThrow(try draft.validate(original: old))
        draft.activityPrefs.append("invented"); XCTAssertThrowsError(try draft.validate(original: old))
    }
    func testAdminMayEditButCannotChangeOwnerSettingsOrRoles() throws {
        let snapshot = try opsSnapshot(owner: false, admin: true), profile = try XCTUnwrap(snapshot.profile)
        var draft = ClubOperationsDraft(profile: profile); draft.name = "Edited"
        XCTAssertNoThrow(try ClubOperationsCommand.update(draft, original: profile).validate(snapshot: snapshot, identity: opsIdentity))
        XCTAssertThrowsError(try ClubOperationsCommand.openSetting(.publicVisible, enabled: false, previous: true).validate(snapshot: snapshot, identity: opsIdentity))
        XCTAssertThrowsError(try ClubOperationsCommand.memberRole(memberID: 704, admin: true, previousRole: 0).validate(snapshot: snapshot, identity: opsIdentity))
    }
    func testOwnerSelfDuplicateUnknownRoleAndAdminLimitAreBlocked() throws {
        let profile = try opsProfile()
        for rows in [#"[{"memberId":701,"role":0}]"#, #"[{"memberId":704,"role":0,"isOwner":true}]"#, #"[{"memberId":704,"role":7}]"#, #"[{"memberId":704,"role":0},{"memberId":704,"role":0}]"#, #"[{"memberId":704,"role":0},{"memberId":705,"role":1},{"memberId":706,"role":1}]"#] {
            let snapshot = ClubOperationsSnapshot(target: .club(81), profile: profile, members: try opsMembers(rows))
            XCTAssertThrowsError(try ClubOperationsCommand.memberRole(memberID: 704, admin: true, previousRole: 0).validate(snapshot: snapshot, identity: opsIdentity))
        }
    }
    func testSettingAndProfileChangesInvalidateReview() throws {
        let snapshot = try opsSnapshot(), profile = try XCTUnwrap(snapshot.profile)
        XCTAssertThrowsError(try ClubOperationsCommand.openSetting(.publicVisible, enabled: true, previous: false).validate(snapshot: snapshot, identity: opsIdentity))
        let stale = try JSONDecoder().decode(ClubOperationsProfile.self, from: Data(#"{"id":81,"name":"Old","city":"City","isOwner":true}"#.utf8))
        XCTAssertThrowsError(try ClubOperationsCommand.update(ClubOperationsDraft(profile: profile), original: stale).validate(snapshot: snapshot, identity: opsIdentity))
    }
    func testMissingAndUnsupportedSettingsRemainUnknown() throws {
        let profile = try JSONDecoder().decode(ClubOperationsProfile.self, from: Data(#"{"id":81,"publicVisible":9,"memberPostAllowed":null}"#.utf8))
        XCTAssertNil(profile.publicVisible); XCTAssertNil(profile.memberPostAllowed); XCTAssertNil(profile.merchantUndertakeOpen)
    }
}

private final class OperationsTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var replies: [String] = []
    var status = 200
    var onSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?()
        return (Data((replies.isEmpty ? "{}" : replies.removeFirst()).utf8), status)
    }
}
final class ClubOperationsServiceTests: XCTestCase {
    private func service(_ transport: OperationsTransport) throws -> ClubOperationsService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/")!), transport: transport)
    }
    func testSixExactRoutesJSONAndOmitRetiredPrice() throws {
        let transport = OperationsTransport(), service = try service(transport)
        let snapshot = try opsSnapshot(), profile = try XCTUnwrap(snapshot.profile)
        var draft = ClubOperationsDraft(profile: profile); draft.name = " Updated "
        let cases: [(ClubOperationsCommand, ClubOperationsSnapshot, String)] = [
            (.create(opsCreateDraft()), .init(target: .create, accountRole: "club"), "/api/club/create"),
            (.update(draft, original: profile), snapshot, "/api/club/update-mine"),
            (.openSetting(.publicVisible, enabled: false, previous: true), snapshot, "/api/club/open-settings/public-visible"),
            (.openSetting(.memberPostAllowed, enabled: true, previous: false), snapshot, "/api/club/open-settings/member-post"),
            (.openSetting(.merchantUndertakeOpen, enabled: false, previous: true), snapshot, "/api/club/open-settings/merchant-coop"),
            (.memberRole(memberID: 704, admin: true, previousRole: 0), snapshot, "/api/club/set-member-role")]
        for (command, source, path) in cases {
            let request = try service.makeReviewRequest(command, snapshot: source, identity: opsIdentity, token: "synthetic-token")
            XCTAssertEqual(request.url?.path, path); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertNil(fields["memberDiscountPrice"]); XCTAssertNil(fields["member_discount_price"])
            if path.hasSuffix("update-mine") {
                XCTAssertEqual(fields["name"] as? String, "Updated"); XCTAssertEqual(fields["city"] as? String, fields["address"] as? String)
                XCTAssertEqual(fields["operationConfigUpdated"] as? Bool, true); XCTAssertEqual(fields["prioritySignupEnabled"] as? Int, 1)
            }
        }
        XCTAssertTrue(transport.requests.isEmpty, "Building contracts must never send a request")
    }
    func testUnsupportedJoinPolicyIsOmittedAndMediaPreserved() throws {
        let profile = try opsProfile(supportsJoin: false), transport = OperationsTransport()
        let snapshot = ClubOperationsSnapshot(target: .club(81), profile: profile)
        let request = try service(transport).makeReviewRequest(.update(ClubOperationsDraft(profile: profile), original: profile), snapshot: snapshot, identity: opsIdentity, token: "synthetic-token")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertNil(fields["joinPolicy"]); XCTAssertEqual(fields["logo"] as? String, "")
    }
    func testCreationMissingOwnedArrayFailsClosed() async throws {
        let t = OperationsTransport(); t.replies = [#"{"code":200,"appUser":{"id":701,"role":"club"}}"#, #"{"code":200,"data":{}}"#]
        do { _ = try await service(t).snapshot(target: .create, token: "synthetic-token", accountID: 701, checkSession: {}); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/userInfo", "/api/club/my"])
    }
    func testReceiptRequiresSettingReadbackAndPreservesExplicitServerValue() throws {
        let command = ClubOperationsCommand.openSetting(.publicVisible, enabled: false, previous: true)
        let receipt = try ClubOperationsService.decodeReceipt(command: command, data: Data(#"{"code":200,"msg":"server value","data":{"publicVisible":1,"extra":"ignored"}}"#.utf8), status: 200)
        XCTAssertEqual(receipt.settingValue, true); XCTAssertEqual(receipt.message, "server value")
        XCTAssertThrowsError(try ClubOperationsService.decodeReceipt(command: command, data: Data(#"{"code":200,"data":{}}"#.utf8), status: 200))
    }
    func testCreationAcknowledgmentNeverInventsID() throws {
        let command = ClubOperationsCommand.create(opsCreateDraft())
        XCTAssertNil(try ClubOperationsService.decodeReceipt(command: command, data: Data(#"{"code":200}"#.utf8), status: 200).clubID)
        XCTAssertEqual(try ClubOperationsService.decodeReceipt(command: command, data: Data(#"{"code":200,"data":{"clubId":82}}"#.utf8), status: 200).clubID, 82)
    }
    @MainActor func testProductionPerformIsHardOffBeforeAllNetworkCalls() async throws {
        let t = OperationsTransport(), access = ClubOperationsSessionAccess(service: try service(t), currentSession: { try? .init(accountID: 701, epoch: 1, token: "synthetic-token") })
        do { _ = try await access.perform(.create(opsCreateDraft()), target: .create, expectedIdentity: opsIdentity); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.notConfigured)) }
        XCTAssertTrue(t.requests.isEmpty); XCTAssertEqual(access.writeAvailability, .unverified)
    }
    @MainActor func testSameIdentityTokenReplacementStopsSecondRead() async throws {
        let t = OperationsTransport(); t.replies = [#"{"code":200,"appUser":{"id":701,"role":"club"}}"#]
        var session: ClubOperationsSession? = try .init(accountID: 701, epoch: 1, token: "first")
        t.onSend = { session = try? .init(accountID: 701, epoch: 1, token: "replacement") }
        let access = ClubOperationsSessionAccess(service: try service(t), currentSession: { session })
        do { _ = try await access.snapshot(target: .create); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(t.requests.count, 1)
    }
}

@MainActor final class ClubOperationsCoordinatorTests: XCTestCase {
    private let target = ClubOperationsTarget.club(81)
    private let owner = UUID()
    private var command: ClubOperationsCommand { .openSetting(.publicVisible, enabled: false, previous: true) }
    private func prepare(_ access: ClubOperationsFixtureAccess, _ coordinator: ClubOperationsCoordinator) async throws -> ClubOperationsReview {
        try await coordinator.prepare(command, target: target, expectedIdentity: XCTUnwrap(access.identity), ownerID: owner)
    }
    func testReviewCancellationAndRepeatedConfirmSendOnce() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .owner), coordinator = ClubOperationsCoordinator(access: access)
        let cancelled = try await prepare(access, coordinator); XCTAssertEqual(access.writeCount, 0)
        coordinator.cancel(cancelled); await coordinator.confirm(cancelled); XCTAssertEqual(access.writeCount, 0)
        let review = try await prepare(access, coordinator); await coordinator.confirm(review); await coordinator.confirm(review)
        XCTAssertEqual(access.writeCount, 1)
        guard case .acknowledged = coordinator.state(target: target) else { return XCTFail() }
        guard case .received(let readback) = coordinator.readback(target: target) else { return XCTFail() }
        XCTAssertEqual(readback.profile?.publicVisible, false)
    }
    func testUnknownReadbackNeverUnlocksOrReplaysAcrossEpochs() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .unknown), coordinator = ClubOperationsCoordinator(access: access)
        let review = try await prepare(access, coordinator); await coordinator.confirm(review)
        await coordinator.readBack(target: target, ownerID: owner)
        guard case .outcomeUnknown = coordinator.state(target: target) else { return XCTFail() }
        access.reloginSameAccount(); coordinator.synchronizeSession()
        do { _ = try await prepare(access, coordinator); XCTFail() } catch { XCTAssertEqual(error as? ClubOperationsBlock, .pending) }
        XCTAssertEqual(access.writeCount, 1)
    }
    func testUnknownIsAccountScopedAndReturningAccountStaysLocked() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .unknown), coordinator = ClubOperationsCoordinator(access: access)
        await coordinator.confirm(try await prepare(access, coordinator)); access.switchAccount(); coordinator.synchronizeSession()
        XCTAssertEqual(coordinator.state(target: target), .idle)
        access.switchAccount(); coordinator.synchronizeSession()
        guard case .outcomeUnknown = coordinator.state(target: target) else { return XCTFail() }
    }
    func testUnverifiedFixtureCannotDispatchThroughCoordinator() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .unverified), coordinator = ClubOperationsCoordinator(access: access)
        await coordinator.confirm(try await prepare(access, coordinator))
        XCTAssertEqual(coordinator.state(target: target), .notSent); XCTAssertEqual(access.writeCount, 0)
    }
    func testRoleRevokedAfterReviewPreventsDispatch() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .changed), coordinator = ClubOperationsCoordinator(access: access)
        _ = try await access.snapshot(target: target) // first screen read
        let review = try await prepare(access, coordinator); await coordinator.confirm(review)
        XCTAssertEqual(access.writeCount, 0); XCTAssertEqual(coordinator.state(target: target), .notSent)
    }
    func testAccountSwitchInvalidatesReviewBeforeDispatch() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .owner), coordinator = ClubOperationsCoordinator(access: access)
        let review = try await prepare(access, coordinator); access.switchAccount(); coordinator.synchronizeSession()
        await coordinator.confirm(review); XCTAssertEqual(access.writeCount, 0)
    }
    func testOlderScreenCannotCancelNewReview() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .owner), coordinator = ClubOperationsCoordinator(access: access)
        let review = try await prepare(access, coordinator)
        coordinator.leaveScreen(target: target, expectedIdentity: try XCTUnwrap(access.identity), ownerID: UUID())
        await coordinator.confirm(review); XCTAssertEqual(access.writeCount, 1)
    }
    func testAcknowledgedWriteReadbackFailureDoesNotPretendCurrentValue() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .readbackUnavailable), coordinator = ClubOperationsCoordinator(access: access)
        await coordinator.confirm(try await prepare(access, coordinator))
        guard case .acknowledged = coordinator.state(target: target) else { return XCTFail() }
        XCTAssertEqual(coordinator.readback(target: target), .unavailable); XCTAssertEqual(access.writeCount, 1)
    }
    func testCreationUnknownBlocksSecondCreateEvenAfterReadback() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .unknown), coordinator = ClubOperationsCoordinator(access: access)
        let review = try await coordinator.prepare(.create(opsCreateDraft()), target: .create, expectedIdentity: XCTUnwrap(access.identity), ownerID: owner)
        await coordinator.confirm(review); await coordinator.readBack(target: .create, ownerID: owner)
        guard case .outcomeUnknown = coordinator.state(target: .create) else { return XCTFail() }
        XCTAssertEqual(access.writeCount, 1)
    }
    func testLeavingAfterDispatchKeepsUnknownLockAndDiscardsLateReceipt() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .delayed), coordinator = ClubOperationsCoordinator(access: access)
        let review = try await prepare(access, coordinator)
        let task = Task { await coordinator.confirm(review) }
        for _ in 0..<1000 { if access.writeCount == 1 { break }; await Task.yield() }
        XCTAssertEqual(access.writeCount, 1)
        coordinator.leaveScreen(target: target, expectedIdentity: try XCTUnwrap(access.identity), ownerID: owner)
        await task.value
        guard case .outcomeUnknown = coordinator.state(target: target) else { return XCTFail() }
        XCTAssertEqual(coordinator.readback(target: target), .idle)
    }
    func testCancellationBeforeConfirmationDispatchSendsNothing() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .owner), coordinator = ClubOperationsCoordinator(access: access)
        let review = try await prepare(access, coordinator)
        let task = Task { await coordinator.confirm(review) }
        task.cancel(); await task.value
        XCTAssertEqual(access.writeCount, 0); XCTAssertEqual(coordinator.state(target: target), .idle)
    }

}
