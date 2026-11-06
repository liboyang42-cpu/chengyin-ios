import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityParticipationRuntimeOwnerTests: XCTestCase {
    private static let code = "00000000-0000-0000-0000-000000000001"
    private static let binding: [String: Any] = ["releaseId": 1, "regionId": "region", "boardId": "board", "seasonId": "season", "rulesReleaseId": "rules",
        "contentHash": String(repeating: "a", count: 64), "revision": 1, "title": "Fake source",
        "rules": ["mode": "CITY_TEAM", "minMembers": 1, "maxMembers": 2, "joinPolicy": "INVITE_CODE", "rosterPolicy": "CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM",
                  "replacementPolicy": "FORBIDDEN_AFTER_LOCK", "reentryPolicy": "RESUME_ORIGINAL_SESSION", "roundPolicy": "FIXED_PUBLISHED_ROUND", "roundId": "round"]]
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            if request.url?.path.contains("/request/") == true {
                return (Data(#"{"code":202,"errorCode":"OUTCOME_UNKNOWN","data":{"requestId":"persisted-original","requestStatus":"UNKNOWN"}}"#.utf8),202)
            }
            let data: [String: Any]
            if request.url?.path.hasSuffix("/invite") == true {
                data = ["binding": CityParticipationRuntimeOwnerTests.binding, "teamId": CityParticipationRuntimeOwnerTests.code, "version": 3, "memberCount": 1]
            } else {
                data = ["contract": "CITY_TEAM_PARTICIPATION_V1", "scope": "CITY", "status": "NOT_JOINED", "writeApproved": true,
                        "pointsStatus": "UNAVAILABLE", "taskExecutionStatus": "UNAVAILABLE", "actionBudgetStatus": "UNAVAILABLE", "binding": CityParticipationRuntimeOwnerTests.binding]
            }
            return (try JSONSerialization.data(withJSONObject: ["code":200,"data":data]),200)
        }
    }
    @MainActor private final class Harness {
        let original: RuntimeDependencyContext
        var current: RuntimeDependencyContext?
        var revision: UInt64 = 3
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let wire = Wire()
        var stateIssued: CityParticipationReadGrant?
        var invitationIssued: CityParticipationInvitationGrant?
        var receiptIssued: CityOriginalReceiptReadGrant?
        var requestedCodes: [String] = []
        var references: [CityOriginalReceiptReference] = []
        init() throws {
            let session = try PlayExperienceSession(accountID:7,epoch:1,namespace:"runtime-city",token:"fake-token",role:"player")
            original = .init(market:.china,baseURL:URL(string:"https://city.example.test/native/")!,role:"player",session:session)
            current = original
        }
        func scope() throws -> CityParticipationCommandScope {
            try .init(market:original.market,baseURL:original.baseURL,namespace:original.session.namespace,
                      accountID:original.session.accountID,epoch:original.session.epoch,token:original.session.token)
        }
        func owner(reads: Bool = false) throws -> CityParticipationRuntimeOwner {
            try .init(context:original,revision:3,regionID:"region",directory:directory,transport:wire,
                currentContext:{self.current},currentRevision:{self.revision},
                stateGrant:{ requested in
                    guard reads else { return nil }
                    if self.stateIssued == nil { self.stateIssued = .init(scope:requested) }
                    return self.stateIssued
                }, invitationGrant:{ scope,region,code in
                    guard reads else { return nil }; self.requestedCodes.append(code)
                    if self.invitationIssued == nil { self.invitationIssued = .init(scope:scope,regionID:region,code:code) }
                    return self.invitationIssued
                }, receiptGrant:{ reference in
                    guard reads else { return nil }; self.references.append(reference)
                    if self.receiptIssued == nil { self.receiptIssued = .init(reference:reference) }
                    return self.receiptIssued
                })
        }
        func context(role: String = "player", epoch: UInt64 = 1, token: String = "fake-token", namespace: String = "runtime-city", account: Int = 7) throws -> RuntimeDependencyContext {
            let session = try PlayExperienceSession(accountID:account,epoch:epoch,namespace:namespace,token:token,role:role)
            return .init(market:.china,baseURL:original.baseURL,role:role,session:session)
        }
    }
    func testDefaultNilProvidersCannotReadOrSubmit() async throws {
        let h = try Harness(), owner = try h.owner(), form = try XCTUnwrap(owner.form)
        await form.open(); XCTAssertTrue(form.unavailable); XCTAssertNil(form.state); XCTAssertFalse(form.hasApprovalHost)
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testCompleteRuntimeChangesPermanentlyRetireOriginalOwner() throws {
        for kind in 0..<6 {
            let h = try Harness(), owner = try h.owner()
            switch kind {
            case 0: h.current = try h.context(role:"merchant")
            case 1: h.current = try h.context(epoch:2)
            case 2: h.current = try h.context(token:"changed-token")
            case 3: h.current = try h.context(namespace:"another-deployment")
            case 4: h.current = try h.context(account:8)
            default: h.revision = 4
            }
            owner.synchronize(); XCTAssertTrue(owner.isRetired); XCTAssertFalse(owner.isCurrent)
            h.current = h.original; h.revision = 3; XCTAssertFalse(owner.isCurrent)
        }
    }
    func testInconsistentOuterRoleAndSessionRoleCannotConstructOwner() throws {
        let h = try Harness()
        let inconsistent = RuntimeDependencyContext(market:.china,baseURL:h.original.baseURL,role:"merchant",session:h.original.session)
        h.current = inconsistent
        XCTAssertThrowsError(try CityParticipationRuntimeOwner(context:inconsistent,revision:3,regionID:"region",directory:h.directory,transport:h.wire,
            currentContext:{h.current},currentRevision:{h.revision}))
    }
    func testInviteProviderReceivesActualInputWithoutMintingByOwner() async throws {
        let h = try Harness(), owner = try h.owner(reads:true), form = try XCTUnwrap(owner.form)
        await form.open(); await form.inspectInvite(Self.code)
        XCTAssertNotNil(form.invitation); XCTAssertFalse(h.requestedCodes.isEmpty)
        XCTAssertTrue(h.requestedCodes.allSatisfy{$0 == Self.code}); XCTAssertFalse(form.hasApprovalHost)
        XCTAssertTrue(h.wire.requests.allSatisfy{$0.httpMethod == "GET"})
    }
    func testRestoredReceiptProviderGetsOriginalPersistentReferenceOnly() async throws {
        let h = try Harness(), scope = try h.scope(), journal = try CityParticipationCommandJournal(directory:h.directory)
        let command = try CityParticipationCommand(kind:.create,requestID:"persisted-original",regionID:"region",releaseID:1,
            contentHash:String(repeating:"a",count:64),expectedVersion:0)
        _ = try journal.begin(command.wireBytes(),scope:scope)
        let owner = try h.owner(reads:true), form = try XCTUnwrap(owner.form)
        await form.open(); await form.recovery.recheck()
        XCTAssertEqual(form.recovery.display,.unknown); XCTAssertFalse(h.references.isEmpty)
        XCTAssertTrue(h.references.allSatisfy{$0.requestID == "persisted-original" && $0.domain == .participation && $0.session == scope.session})
        XCTAssertTrue(h.wire.requests.allSatisfy{$0.httpMethod == "GET"}); XCTAssertNil(try journal.load(scope)?.terminalStatus)
    }
    func testLateRoleChangeRetiresAndHidesReadResult() async throws {
        let h = try Harness(), owner = try h.owner(reads:true), form = try XCTUnwrap(owner.form)
        let changed = try h.context(role:"club"); h.wire.beforeReply = {h.current = changed}
        await form.open(); XCTAssertTrue(owner.isRetired); XCTAssertNil(form.state); XCTAssertEqual(form.recovery.display,.hidden)
    }
    func testContextualNilProviderDoesNotFallBackToOldGrant() async throws {
        let h = try Harness(), scope = try h.scope(), api = try APIConfiguration(baseURL:h.original.baseURL)
        let oldGrant = CityParticipationInvitationGrant(scope:scope,regionID:"region",code:Self.code)
        let reader = CityParticipationInvitationReader(configuration:api,transport:h.wire,currentScope:{scope},grant:{oldGrant},grantForRequest:{_,_,_ in nil})
        do { _ = try await reader.read(scope:scope,regionID:"region",code:Self.code); XCTFail("Expected closed") } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
}
