import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ClubRoleOriginalDispatchRestoreTests: XCTestCase {
    @MainActor final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var assigning = true, allowed = true, receiptApplied = true, timeoutWriter = false
        var wrongReceipt = false
        var onWrite: (() -> Void)?
        var onReceipt: (() -> Void)?
        var writes: Int { requests.filter { ["/api/club/roles/assign", "/api/club/roles/revoke"].contains($0.url?.path ?? "") }.count }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url!.path
            var value: ClubGovernanceValue
            switch path {
            case "/api/club/access/me":
                var access = ClubGovernanceFixtures.permissions.object!
                if !allowed { access["canManageRoles"] = .bool(false); access["roleCodes"] = .array([]); access["permissions"] = .array([]) }
                value = .object(access)
            case "/api/club/members":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                value = ClubGovernanceFixtures.value(.members)
            case "/api/club/roles/list":
                var roles = ClubGovernanceFixtures.value(.roles, scope: .init(clubID: 81)).object!
                if assigning { roles["assignments"] = .array([]) }; value = .object(roles)
            case "/api/club/roles/assign", "/api/club/roles/revoke":
                onWrite?(); if timeoutWriter { throw URLError(.timedOut) }; value = .null
            case "/api/club/roles/assign-receipt", "/api/club/roles/revoke-receipt":
                var fields = try JSONDecoder().decode([String: ClubGovernanceValue].self, from: XCTUnwrap(request.httpBody))
                fields["state"] = .string(receiptApplied ? "APPLIED" : "UNKNOWN")
                if receiptApplied {
                    fields["auditId"] = .integer(500); fields["appliedAt"] = .integer(1000)
                    if assigning { fields["assignmentId"] = .integer(181); fields["version"] = .integer(0) }
                }
                if wrongReceipt { fields["targetMemberId"] = .integer(999) }
                onReceipt?(); value = .object(fields)
            default: throw URLError(.unsupportedURL)
            }
            return (try JSONEncoder().encode(ClubGovernanceValue.object(["code": .integer(200), "data": value])), 200)
        }
    }
    @MainActor final class Fixture {
        let wire = Wire()
        let scope = ClubGovernanceScope(clubID: 81)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context: RuntimeDependencyContext, command: ClubGovernanceCommand
        var current: RuntimeDependencyContext?
        var assignApproval: ClubRoleAssignmentApproval?
        var revokeApproval: ClubRoleRevocationApproval?
        lazy var assignJournal = ClubRoleAssignmentJournal(directory: directory.appendingPathComponent("assign"))
        lazy var revokeJournal = ClubRoleRevocationJournal(directory: directory.appendingPathComponent("revoke"))
        lazy var generic = ClubGovernanceFileIntentStore(directory: directory.appendingPathComponent("legacy"))
        lazy var assignRecovery = ClubRoleAssignmentRecovery(current: { self.current }, approval: { _ in self.assignApproval },
            client: ClubRoleAssignmentClient(transport: wire, current: { self.current }, approval: { _ in self.assignApproval }), journal: assignJournal)
        lazy var revokeRecovery = ClubRoleRevocationRecovery(current: { self.current }, approval: { _ in self.revokeApproval },
            client: ClubRoleRevocationClient(transport: wire, current: { self.current }, approval: { _ in self.revokeApproval }), journal: revokeJournal)
        lazy var access: ClubGovernanceSessionAccess = {
            let api = try! APIConfiguration(baseURL: context.baseURL)
            return ClubGovernanceSessionAccess(service: .init(configuration: api, transport: wire), currentSession: {
                self.current.flatMap { try? ClubGovernanceSession(accountID: $0.session.accountID, epoch: $0.session.epoch,
                    token: $0.session.token, storageNamespace: $0.session.namespace) }
            }, productionService: { command in
                let approval = command.operation == .assignRole ? self.assignApproval?.productionApproval : self.revokeApproval?.productionApproval
                return ClubGovernanceProductionFactory(api: api, approval: approval, transport: self.wire, current: { self.current }).service(for: command)
            }, runtimeContext: { self.current })
        }()
        lazy var coordinator = ClubGovernanceCoordinator(access: access, journal: generic,
            roleAssignment: assignRecovery, roleRevocation: revokeRecovery)
        init(assign: Bool = true, enabled: Bool = true) throws {
            wire.assigning = assign
            let session = try PlayExperienceSession(accountID: 701, epoch: 1, namespace: "role-original-fixture", token: "synthetic-token")
            context = .init(market: .china, baseURL: URL(string: "https://example.test/")!, role: "club", session: session); current = context
            let requestID = "club-native-00000000-0000-0000-0000-000000000001"
            if assign {
                command = try .init(operation: .assignRole, scope: scope,
                    values: ["targetMemberId": .integer(704), "roleCode": .string("CLUB_OPERATOR"), "requestId": .string(requestID)])
            } else {
                command = try .init(operation: .revokeRole, scope: scope,
                    values: ["assignmentId": .integer(181), "version": .integer(2),
                             "reason": .string(ClubGovernanceFormDraft.revokeRoleReason), "requestId": .string(requestID)])
            }
            let endpoints = try OperationEndpointApproval(baseURL: context.baseURL, namespace: session.namespace, accountID: 701,
                paths: ClubRoleAssignmentRoute.paths.union(ClubRoleRevocationRoute.paths))
            let grant = try ClubGovernanceActionGrant(command: command, risk: command.operation.risk)
            if assign { assignApproval = try .init(endpoints: endpoints, scopes: [scope], grants: [grant], reviewedPolicyVersion: "fixture", reads: enabled, writes: enabled) }
            else { revokeApproval = try .init(endpoints: endpoints, scopes: [scope], grants: [grant], reviewedPolicyVersion: "fixture", reads: enabled, writes: enabled) }
        }
        func submit() async throws -> ClubGovernanceValue {
            let review = try await coordinator.prepare(command); return try await coordinator.confirm(review)
        }
    }
    func fixture(assign: Bool = true, enabled: Bool = true) throws -> Fixture {
        let f = try Fixture(assign: assign, enabled: enabled)
        addTeardownBlock { try? FileManager.default.removeItem(at: f.directory) }; return f
    }
    func testDisabledDedicatedApprovalCannotBorrowGenericWriter() async throws {
        for assign in [true, false] {
            let f = try fixture(assign: assign, enabled: false)
            XCTAssertFalse(f.coordinator.canDispatch(f.command))
            do { _ = try await f.submit(); XCTFail() } catch {}
            XCTAssertEqual(f.wire.writes, 0)
        }
    }
    func testTypedOriginalIsDurablyReservedBeforeExactlyOneWriterAndReceipt() async throws {
        for assign in [true, false] {
            let f = try fixture(assign: assign)
            f.wire.onWrite = {
                if assign { XCTAssertEqual(try? f.assignJournal.read(f.context, clubID: 81).first?.outcome, "UNKNOWN") }
                else { XCTAssertEqual(try? f.revokeJournal.read(f.context, clubID: 81).first?.outcome, "UNKNOWN") }
            }
            let value = try await f.submit()
            XCTAssertEqual(value["state"], .string("APPLIED")); XCTAssertEqual(f.wire.writes, 1)
            XCTAssertEqual(f.coordinator.state, .acknowledged)
            if assign { XCTAssertEqual(try f.assignJournal.read(f.context, clubID: 81).first?.outcome, "APPLIED") }
            else { XCTAssertEqual(try f.revokeJournal.read(f.context, clubID: 81).first?.outcome, "APPLIED") }
        }
    }
    func testLegacyGenericPendingIsNotMigratedClearedOrBypassed() async throws {
        let f = try fixture()
        let key = "\(f.access.journalRealm)|701|assignRole|activityId=&clubId=81&targetMemberId=704"
        try await f.generic.reserve(key)
        do { _ = try await f.submit(); XCTFail() } catch {}
        XCTAssertEqual(f.wire.writes, 0); XCTAssertTrue(try f.generic.contains(key))
        XCTAssertTrue(try f.assignJournal.read(f.context, clubID: 81).isEmpty)
    }
    func testUnknownWriterSurvivesRelaunchWithoutResend() async throws {
        for assign in [true, false] {
            let f = try fixture(assign: assign); f.wire.timeoutWriter = true
            do { _ = try await f.submit(); XCTFail() } catch {}
            let again = ClubGovernanceCoordinator(access: f.access, journal: f.generic,
                roleAssignment: f.assignRecovery, roleRevocation: f.revokeRecovery)
            do { _ = try await again.prepare(f.command); XCTFail() } catch {}
            XCTAssertEqual(f.wire.writes, 1)
        }
    }
    func testHttpSuccessWithoutImmutableAppliedProofRemainsUnknown() async throws {
        let f = try fixture(); f.wire.receiptApplied = false
        do { _ = try await f.submit(); XCTFail() } catch {}
        XCTAssertEqual(try f.assignJournal.read(f.context, clubID: 81).first?.outcome, "UNKNOWN")
        XCTAssertEqual(f.coordinator.state, .unknown); XCTAssertEqual(f.wire.writes, 1)
    }
    func testReadonlyHistorySettlesExactOriginalWithoutWriter() async throws {
        let f = try fixture(); f.wire.timeoutWriter = true
        do { _ = try await f.submit(); XCTFail() } catch {}
        f.wire.timeoutWriter = false
        let values = try await f.assignRecovery.history(scope: f.scope, identity: f.access.identity, access: f.access, check: {})
        XCTAssertEqual(values.first?.receipt?.state, "APPLIED"); XCTAssertEqual(f.wire.writes, 1)
        XCTAssertEqual(try f.assignJournal.read(f.context, clubID: 81).first?.outcome, "APPLIED")
    }
    func testAuthorityRevocationBeforeEmptyHistoryStillRejects() async throws {
        let f = try fixture(); f.wire.allowed = false
        do { _ = try await f.assignRecovery.history(scope: f.scope, identity: f.access.identity, access: f.access, check: {}); XCTFail() } catch {}
        XCTAssertFalse(f.wire.requests.contains { $0.url?.path.hasSuffix("receipt") == true })
    }
    func testLateAccountChangeOrForeignReceiptCannotSettleOriginal() async throws {
        for changeAccount in [true, false] {
            let f = try fixture()
            if changeAccount { f.wire.onReceipt = { f.current = nil } } else { f.wire.wrongReceipt = true }
            do { _ = try await f.submit(); XCTFail() } catch {}
            XCTAssertEqual(try f.assignJournal.read(f.context, clubID: 81).first?.outcome, "UNKNOWN")
            XCTAssertEqual(f.wire.writes, 1)
        }
    }
}
