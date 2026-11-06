import Foundation
import XCTest
@testable import Questify

@MainActor final class ClubRoleOriginalCompositionRestoreTests: XCTestCase {
    @MainActor final class Wire: HTTPTransport {
        var calls = 0
        var afterSend: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            calls += 1; afterSend?(); return (Data(#"{"code":200,"data":null}"#.utf8), 200)
        }
    }
    @MainActor final class Fixture {
        let base = URL(string: "https://example.test/native")!
        let identity = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 701, role: "club", token: "synthetic-token")
        let wire = Wire(), deployment: ReviewedAppDeployment, context: RuntimeDependencyContext
        var assignment: ClubRoleAssignmentApproval?
        var revocation: ClubRoleRevocationApproval?
        lazy var transport: CompositionHTTPTransport = {
            let t = CompositionHTTPTransport(deployment: deployment, underlying: wire)
            t.current = { self.identity }
            t.clubRoleAssignmentApproval = { _ in self.assignment }
            t.clubRoleRevocationApproval = { _ in self.revocation }; return t
        }()
        init() throws {
            deployment = try .init(market: .china, baseURL: base.absoluteString,
                approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [],
                bundleIdentifier: "tests.club-original", realm: "synthetic")
            context = .init(market: .china, baseURL: base, role: "club", session: try .init(accountID: 701, epoch: 1,
                namespace: deployment.storageScope.service, token: "synthetic-token"))
        }
        func enable(assign: Bool, writes: Bool = false) throws {
            let scope = ClubGovernanceScope(clubID: 81)
            let command = try ClubGovernanceCommand(operation: assign ? .assignRole : .revokeRole, scope: scope,
                values: assign ? ["targetMemberId": .integer(704), "roleCode": .string("CLUB_OPERATOR"), "requestId": .string(Self.requestID)]
                    : ["assignmentId": .integer(181), "version": .integer(2), "reason": .string(ClubGovernanceFormDraft.revokeRoleReason), "requestId": .string(Self.requestID)])
            let endpoints = try OperationEndpointApproval(baseURL: base, namespace: context.session.namespace, accountID: 701,
                paths: ClubRoleAssignmentRoute.paths.union(ClubRoleRevocationRoute.paths))
            let grant = try ClubGovernanceActionGrant(command: command, risk: command.operation.risk)
            if assign { assignment = try .init(endpoints: endpoints, scopes: [scope], grants: [grant], reviewedPolicyVersion: "fixture", reads: true, writes: writes) }
            else { revocation = try .init(endpoints: endpoints, scopes: [scope], grants: [grant], reviewedPolicyVersion: "fixture", reads: true, writes: writes) }
        }
        static let requestID = "club-native-00000000-0000-0000-0000-000000000001"
        func request(assign: Bool, receipt: Bool, target: Int = 704) throws -> URLRequest {
            let path = assign ? "api/club/roles/assign" : "api/club/roles/revoke"
            var fields: [String: ClubGovernanceValue] = ["clubId": .integer(81), "requestId": .string(Self.requestID)]
            if assign {
                fields["targetMemberId"] = .integer(target); fields["roleCode"] = .string("CLUB_OPERATOR")
                if receipt { fields["expiresAtEpochMs"] = .null }
            } else {
                fields["assignmentId"] = .integer(181); fields["version"] = .integer(2)
                if receipt { fields["targetMemberId"] = .integer(target); fields["roleCode"] = .string("CLUB_OPERATOR"); fields["reasonSHA256"] = .string(String(repeating: "a", count: 64)) }
                else { fields["reason"] = .string(ClubGovernanceFormDraft.revokeRoleReason) }
            }
            var r = URLRequest(url: base.appendingPathComponent(path + (receipt ? "-receipt" : "")))
            r.httpMethod = "POST"; r.httpBody = try JSONEncoder().encode(fields)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.setValue("synthetic-token", forHTTPHeaderField: "Authorization"); return r
        }
    }
    func reject(_ request: URLRequest, _ transport: CompositionHTTPTransport, _ wire: Wire) async {
        let before = wire.calls
        do { _ = try await transport.send(request); XCTFail("Unapproved role dispatch") } catch {}
        XCTAssertEqual(wire.calls, before)
    }
    func testDefaultsKeepRoleReceiptsAndWritersClosed() async throws {
        let f = try Fixture(); let root = AppCompositionRoot()
        XCTAssertNil(root.clubRoleAssignmentJournalDirectory); XCTAssertNil(root.clubRoleRevocationJournalDirectory)
        XCTAssertNil(root.clubRoleAssignmentApproval(f.context)); XCTAssertNil(root.clubRoleRevocationApproval(f.context))
        for assign in [true, false] { for receipt in [true, false] { await reject(try f.request(assign: assign, receipt: receipt), f.transport, f.wire) } }
    }
    func testEachReadonlyGrantAdmitsOnlyItsOriginalReceipt() async throws {
        for assign in [true, false] {
            let f = try Fixture(); try f.enable(assign: assign)
            _ = try await f.transport.send(f.request(assign: assign, receipt: true))
            XCTAssertEqual(f.wire.calls, 1)
            await reject(try f.request(assign: assign, receipt: false), f.transport, f.wire)
            await reject(try f.request(assign: !assign, receipt: true), f.transport, f.wire)
        }
    }
    func testExactWriterGrantCannotBeBorrowedForForeignTarget() async throws {
        let f = try Fixture(); try f.enable(assign: true, writes: true)
        _ = try await f.transport.send(f.request(assign: true, receipt: false))
        XCTAssertEqual(f.wire.calls, 1)
        await reject(try f.request(assign: true, receipt: false, target: 999), f.transport, f.wire)
    }
    func testClonedTransportSeesOriginalGrantRevocation() async throws {
        for assign in [true, false] {
            let f = try Fixture(); try f.enable(assign: assign)
            let clone = f.transport.replacingUnderlying(f.wire)
            _ = try await clone.send(f.request(assign: assign, receipt: true))
            f.assignment = nil; f.revocation = nil
            await reject(try f.request(assign: assign, receipt: true), clone, f.wire)
        }
    }
    func testLateGrantRevocationDiscardsResponseWithoutRetry() async throws {
        for assign in [true, false] {
            let f = try Fixture(); try f.enable(assign: assign)
            f.wire.afterSend = { f.assignment = nil; f.revocation = nil }
            do { _ = try await f.transport.send(f.request(assign: assign, receipt: true)); XCTFail() } catch {}
            XCTAssertEqual(f.wire.calls, 1)
        }
    }
    func testStrictRoleRequestRejectsExtraKeysForeignScopeAndMissingToken() async throws {
        let f = try Fixture(); try f.enable(assign: true)
        var r = try f.request(assign: true, receipt: true)
        var fields = try JSONDecoder().decode([String: ClubGovernanceValue].self, from: XCTUnwrap(r.httpBody))
        fields["topicId"] = .integer(91); r.httpBody = try JSONEncoder().encode(fields)
        await reject(r, f.transport, f.wire)
        fields.removeValue(forKey: "topicId"); fields["clubId"] = .integer(99); r.httpBody = try JSONEncoder().encode(fields)
        await reject(r, f.transport, f.wire)
        r = try f.request(assign: true, receipt: true); r.setValue(nil, forHTTPHeaderField: "Authorization")
        await reject(r, f.transport, f.wire)
    }
}
