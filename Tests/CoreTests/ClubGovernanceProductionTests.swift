import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ClubGovernanceProductionTests: XCTestCase {
    private let url = URL(string: "https://example.com")!
    private let target = ClubGovernanceScope(clubID: 81, memberID: 704)
    private func command() throws -> ClubGovernanceCommand {
        try .init(operation: .saveCustomer, scope: target, values: ["tags": .array([]), "remark": .string("Reviewed note"), "requestId": .string("test-operation")])
    }
    private func context(epoch: UInt64 = 1, role: String = "club", namespace: String = "test-cn") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: url, role: role, session: try .init(accountID: 701, epoch: epoch, namespace: namespace, token: "test-token"))
    }
    private func approval(_ command: ClubGovernanceCommand, additional: [ClubGovernanceCommand] = []) throws -> ClubGovernanceProductionApproval {
        let commands = [command] + additional
        let paths = Set(commands.flatMap { ["api/club/access/me", $0.operation.reviewRead.path, "api/club/members", $0.operation.path] })
        return try .init(market: .china, endpoints: .init(baseURL: url, namespace: "test-cn", accountID: 701, paths: paths),
            grants: Set(commands.map { try .init(command: $0, risk: $0.operation.risk) }), reviewedPolicyVersion: "review-1")
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func access(_ wire: Wire, _ command: ClubGovernanceCommand, additionalCommands: [ClubGovernanceCommand] = [], current: @escaping () -> RuntimeDependencyContext?) throws -> ClubGovernanceSessionAccess {
        let api = try APIConfiguration(baseURL: url), approval = try self.approval(command, additional: additionalCommands)
        return ClubGovernanceSessionAccess(service: .init(configuration: api, transport: wire), currentSession: {
            guard let c = current() else { return nil }
            return try? .init(accountID: c.session.accountID, epoch: c.session.epoch, token: c.session.token, storageNamespace: c.session.namespace)
        }, productionService: { command in
            ClubGovernanceProductionFactory(api: api, approval: approval, transport: wire, current: current).service(for: command)
        }, runtimeContext: current)
    }
    func testDefaultFactoryDoesNotDispatch() throws {
        let c = try context(), command = try self.command(), wire = Wire()
        let factory = ClubGovernanceProductionFactory(api: try .init(baseURL: url), transport: wire, current: { c })
        XCTAssertNil(factory.service(for: command)); XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExactTargetRiskAndNamespaceRequired() throws {
        let command = try self.command(), approval = try self.approval(command)
        XCTAssertTrue(approval.permits(command, context: try context()))
        XCTAssertFalse(approval.permits(command, context: try context(namespace: "different")))
        let another = try ClubGovernanceCommand(operation: .saveCustomer, scope: .init(clubID: 82, memberID: 704), values: ["tags": .array([]), "remark": .string("note"), "requestId": .string("test-operation")])
        XCTAssertFalse(approval.permits(another, context: try context()))
        XCTAssertThrowsError(try ClubGovernanceActionGrant(command: command, risk: .financial))
    }
    func testGrantBindsFieldTargetRoleAndNotificationAudience() throws {
        let scope = ClubGovernanceScope(clubID: 81)
        func ban(_ member: Int) throws -> ClubGovernanceCommand {
            try .init(operation: .ban, scope: scope, values: ["targetMemberId": .integer(member), "reason": .string("Reviewed reason"), "expiresAt": .string("2026-10-10"), "requestId": .string("test-request")])
        }
        let c = try context(), first = try ban(704), grant = try self.approval(first)
        XCTAssertTrue(grant.permits(first, context: c)); XCTAssertFalse(grant.permits(try ban(705), context: c))
        func role(_ role: String) throws -> ClubGovernanceCommand {
            try .init(operation: .assignRole, scope: scope, values: ["targetMemberId": .integer(704), "roleCode": .string(role), "requestId": .string("test-request")])
        }
        XCTAssertFalse(try self.approval(role("CLUB_OPERATOR")).permits(role("CLUB_CO_OWNER"), context: c))
        func notification(_ audience: String) throws -> ClubGovernanceCommand {
            try .init(operation: .sendNotification, scope: scope, values: ["audienceType": .string(audience), "title": .string("Notice"), "content": .string("Reviewed content"), "requestId": .string("test-request")])
        }
        XCTAssertFalse(try self.approval(notification("ADMINS")).permits(notification("ALL_MEMBERS"), context: c))
    }
    func testPreparedReviewCannotBypassCoordinatorJournal() async throws {
        let c = try context(), command = try self.command(), wire = Wire()
        let access = try self.access(wire, command, current: { c })
        let coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(command)
        do { _ = try await access.send(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .notConfigured) }
        do { _ = try await access.send(review, check: {}); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .notConfigured) }
        XCTAssertEqual(wire.writes, 0)
    }
    func testMixedOfflineBaseCannotDispatchProductionWithoutJournal() async throws {
        let c = try context(), command = try self.command(), live = Wire(), offline = OfflineWire(), api = try APIConfiguration(baseURL: url)
        let approval = try self.approval(command)
        let access = ClubGovernanceSessionAccess(service: .init(offlineConfiguration: api, offlineTransport: offline),
            currentSession: { try? .init(accountID: 701, epoch: 1, token: "test-token", storageNamespace: "test-cn") },
            productionService: { command in ClubGovernanceProductionFactory(api: api, approval: approval, transport: live, current: { c }).service(for: command) }, runtimeContext: { c })
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command)
        _ = try await coordinator.confirm(review)
        XCTAssertTrue(access.allowsOfflineWrites); XCTAssertEqual(offline.wire.writes, 1); XCTAssertTrue(live.requests.isEmpty)
    }
    func testBothChapterMultipartActionsReuseApprovedRequestBytes() async throws {
        for operation in [ClubGovernanceMutation.chapterRecruit, .chapterFinish] {
            let c = try context(), wire = Wire(), dir = directory()
            defer { try? FileManager.default.removeItem(at: dir) }
            wire.chapterFlow = true
            let command = try ClubGovernanceCommand(operation: operation, scope: .init(clubID: 81, topicID: 91, chapterID: 151), values: operation == .chapterRecruit ? ["enabled": .integer(1)] : [:])
            let coordinator = ClubGovernanceCoordinator(access: try self.access(wire, command, current: { c }), journal: ClubGovernanceFileIntentStore(directory: dir))
            let review = try await coordinator.prepare(command); _ = try await coordinator.confirm(review)
            XCTAssertEqual(wire.writes, 1); XCTAssertEqual(coordinator.state, .acknowledged)
            let request = try XCTUnwrap(wire.requests.last)
            let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
            let prefix = "multipart/form-data; boundary="
            XCTAssertTrue(contentType.hasPrefix(prefix))
            let boundary = String(contentType.dropFirst(prefix.count))
            XCTAssertFalse(boundary.isEmpty)
            let fields: [(String, String)] = operation == .chapterRecruit
                ? [("chapterId", "151"), ("enabled", "1"), ("scope", "")]
                : [("chapterId", "151"), ("scope", "")]
            let envelope = fields.map { "--\(boundary)\r\nContent-Disposition: form-data; name=\"\($0.0)\"\r\n\r\n\($0.1)\r\n" }.joined() + "--\(boundary)--\r\n"
            XCTAssertEqual(request.httpBody, Data(envelope.utf8))
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url, url.appendingPathComponent(operation.path))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        }
    }
    func testProductionHTTPPathRequiresDurableJournal() async throws {
        let c = try context(), command = try self.command(), wire = Wire(), access = try self.access(wire, try self.command(), current: { c })
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command)
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .notConfigured) }
        XCTAssertEqual(wire.writes, 0)
    }
    func testProductionUsesFreshAccessAndExactHTTPBody() async throws {
        let c = try context(), command = try self.command(), wire = Wire(), dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let access = try self.access(wire, command, current: { c })
        let coordinator = ClubGovernanceCoordinator(access: access, journal: ClubGovernanceFileIntentStore(directory: dir))
        let review = try await coordinator.prepare(command); _ = try await coordinator.confirm(review)
        XCTAssertFalse(access.allowsOfflineWrites); XCTAssertEqual(wire.writes, 1)
        XCTAssertGreaterThanOrEqual(wire.requests.filter { $0.url?.path == "/api/club/access/me" }.count, 3)
        let request = try XCTUnwrap(wire.requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(try JSONDecoder().decode(ClubGovernanceValue.self, from: XCTUnwrap(request.httpBody)), .object(command.fields))
        let reopened = ClubGovernanceCoordinator(access: access, journal: ClubGovernanceFileIntentStore(directory: dir))
        do { _ = try await reopened.prepare(command); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .outcomeLocked) }
    }
    func testUnrelatedNavigationScopeCannotBypassDurableTargetLock() async throws {
        let c = try context(), command = try self.command(), wire = Wire(), dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        wire.failWrite = true
        let access = try self.access(wire, command, current: { c })
        let coordinator = ClubGovernanceCoordinator(access: access, journal: ClubGovernanceFileIntentStore(directory: dir))
        let review = try await coordinator.prepare(command)
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        let otherRoute = try ClubGovernanceCommand(operation: .saveCustomer, scope: .init(clubID: 81, topicID: 91, activityID: 101, memberID: 704),
            values: ["tags": .array([]), "remark": .string("Changed draft"), "requestId": .string("another-request")])
        let reopened = ClubGovernanceCoordinator(access: access, journal: ClubGovernanceFileIntentStore(directory: dir))
        do { _ = try await reopened.prepare(otherRoute); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .outcomeLocked) }
        XCTAssertEqual(wire.writes, 1)
    }
    func testCanonicalLocksKeepDifferentMemberTargetsIndependent() async throws {
        let c = try context(), wire = Wire(), dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        wire.banFlow = true
        func command(_ member: Int) throws -> ClubGovernanceCommand {
            try .init(operation: .ban, scope: .init(clubID: 81), values: ["targetMemberId": .integer(member), "reason": .string("Reviewed reason"), "expiresAt": .string("2026-10-10"), "requestId": .string("test-\(member)")])
        }
        let first = try command(704), second = try command(705)
        let access = try self.access(wire, first, additionalCommands: [second], current: { c })
        let coordinator = ClubGovernanceCoordinator(access: access, journal: ClubGovernanceFileIntentStore(directory: dir))
        let review = try await coordinator.prepare(first); _ = try await coordinator.confirm(review)
        XCTAssertTrue(coordinator.isLocked(first, identity: review.identity)); XCTAssertFalse(coordinator.isLocked(second, identity: review.identity))
        let next = try await coordinator.prepare(second); _ = try await coordinator.confirm(next)
        XCTAssertEqual(wire.writes, 2)
    }
    func testRevokedPermissionCannotUseRuntimeGrant() async throws {
        let c = try context(), command = try self.command(), wire = Wire(), dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let coordinator = ClubGovernanceCoordinator(access: try self.access(wire, command, current: { c }), journal: ClubGovernanceFileIntentStore(directory: dir))
        let review = try await coordinator.prepare(command); wire.allowed = false
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertEqual(wire.writes, 0)
    }
    func testRoleChangeWithSameAccountAndEpochInvalidatesReview() async throws {
        var c = try context(); let command = try self.command(), wire = Wire(), dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let coordinator = ClubGovernanceCoordinator(access: try self.access(wire, command, current: { c }), journal: ClubGovernanceFileIntentStore(directory: dir))
        let review = try await coordinator.prepare(command); c = try context(role: "player")
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .staleReview) }
        XCTAssertEqual(wire.writes, 0)
    }
    func testDismissalDuringJournalSuspensionCannotSend() async throws {
        let c = try context(), command = try self.command(), wire = Wire(), journal = SuspendingJournal()
        let coordinator = ClubGovernanceCoordinator(access: try self.access(wire, command, current: { c }), journal: journal)
        journal.onReserve = { coordinator.cancelReview() }
        let review = try await coordinator.prepare(command)
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .staleReview) }
        XCTAssertEqual(wire.writes, 0); XCTAssertTrue(journal.reserved)
    }
    func testDismissalDuringPostJournalAccessCannotSend() async throws {
        let c = try context(), command = try self.command(), wire = Wire(), dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let coordinator = ClubGovernanceCoordinator(access: try self.access(wire, command, current: { c }), journal: ClubGovernanceFileIntentStore(directory: dir))
        let review = try await coordinator.prepare(command)
        wire.onThirdAccess = { coordinator.cancelReview() }
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertEqual(wire.writes, 0)
    }
    func testUnknownTransportIsDurableAndNeverRetried() async throws {
        let c = try context(), command = try self.command(), wire = Wire(), dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        wire.failWrite = true
        let access = try self.access(wire, command, current: { c })
        let coordinator = ClubGovernanceCoordinator(access: access, journal: ClubGovernanceFileIntentStore(directory: dir))
        let review = try await coordinator.prepare(command)
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        let reopened = ClubGovernanceCoordinator(access: access, journal: ClubGovernanceFileIntentStore(directory: dir))
        do { _ = try await reopened.prepare(command); XCTFail() } catch {}
        XCTAssertEqual(wire.writes, 1); XCTAssertEqual(coordinator.state, .unknown)
    }
    @MainActor private final class SuspendingJournal: ClubGovernanceIntentStoring {
        let isDurable = true; var reserved = false; var onReserve: (() -> Void)?
        func contains(_ key: String) throws -> Bool { reserved }
        func reserve(_ key: String) async throws { reserved = true; await Task.yield(); onReserve?() }
    }
    @MainActor private final class OfflineWire: ClubGovernanceOfflineTransport {
        let wire = Wire()
        func send(_ request: URLRequest) async throws -> (Data, Int) { try await wire.send(request) }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []; var chapterFlow = false; var banFlow = false; var allowed = true; var failWrite = false; var onThirdAccess: (() -> Void)?; var accessCount = 0
        var writes: Int { requests.filter { ["/api/club/crm/customers/tag-remark", "/api/topic/chapter/recruit", "/api/topic/chapter/finish", "/api/club/governance/ban"].contains($0.url?.path ?? "") }.count }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let payload: String
            switch request.url?.path {
            case "/api/club/access/me":
                accessCount += 1
                if accessCount == 3 { onThirdAccess?() }
                payload = "{\"active\":true,\"club\":{\"id\":81},\"roleCodes\":[\"CLUB_MEMBER\"],\"permissions\":\(allowed ? (chapterFlow ? "[\"club:content:manage\"]" : (banFlow ? "[\"club:member:manage\"]" : "[\"club:member:list:read\"]")) : "[]"),\"canManageRoles\":false}"
            case "/api/club/members": payload = #"[{"memberId":704,"isOwner":false},{"memberId":705,"isOwner":false}]"#
            case "/api/club/governance/ban": payload = "null"
            case "/api/club/topic-setting/detail": payload = #"{"canManage":true,"coopOpen":false,"pinned":false,"memberOnly":true,"chapters":[{"chapterId":151,"name":"Chapter","recruiting":false,"merchantCount":0,"finishTime":""}]}"#
            case "/api/topic/chapter/recruit", "/api/topic/chapter/finish": payload = "null"
            case "/api/club/crm/customers/detail": payload = #"{"summary":{"memberId":704,"arrivedCount":0,"pendingCount":0,"refundedCount":0},"records":[],"tags":[],"canEdit":true}"#
            case "/api/club/crm/customers/tag-remark": if failWrite { throw URLError(.timedOut) }; payload = "null"
            default: throw URLError(.unsupportedURL)
            }
            return (Data("{\"code\":200,\"data\":\(payload)}".utf8), 200)
        }
    }
}
