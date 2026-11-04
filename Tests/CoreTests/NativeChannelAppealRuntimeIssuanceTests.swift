import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelAppealRuntimeIssuanceTests: XCTestCase {
    func testConcreteAssemblyIssuesFreshRandomReceiptForEveryOriginalOperation() async throws {
        var identifiers = Set<String>()
        for operation in [NativeChannelAppealFlow.Operation.submit, .evidence, .withdraw] {
            let h = try CAIssuerHarness(operation: operation)
            await h.flow.activate(); XCTAssertTrue(h.flow.prepare(operation, text: "original explanation")); await h.flow.confirm()
            XCTAssertEqual(h.flow.state, .applied); XCTAssertEqual(h.wire.posts.count, 1)
            let request = try XCTUnwrap(h.wire.posts.first)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let id = try XCTUnwrap(body[operation == .submit ? "submit_request_id" : "request_id"] as? String)
            XCTAssertNotNil(UUID(uuidString: id)); XCTAssertTrue(identifiers.insert(id).inserted)
            XCTAssertTrue(h.journal.rows.isEmpty); XCTAssertEqual(h.journal.writes, 1)
            XCTAssertEqual(h.flow.appealDetails?.reason, "independent current")
        }
        XCTAssertEqual(identifiers.count, 3, "The normal assembly does not inject a fixed request UUID")
    }

    func testAllFreshOperationsWithoutIndependentReceiptApprovalNeverSaveOrSend() async throws {
        for operation in [NativeChannelAppealFlow.Operation.submit, .evidence, .withdraw] {
            let h = try CAIssuerHarness(operation: operation, rights: CAIssuerHarness.allRights.subtracting([.originalReceipt]))
            await h.flow.activate(); XCTAssertTrue(h.flow.prepare(operation, text: "reviewed")); await h.flow.confirm()
            XCTAssertEqual(h.flow.state, .unavailable); XCTAssertFalse(h.flow.hasPending)
            XCTAssertEqual(h.journal.writes, 0); XCTAssertTrue(h.wire.posts.isEmpty)
        }
    }

    func testReceiptOnlyColdRecoveryUsesOriginalUUIDAndNeverReinstatesWriter() async throws {
        for operation in [NativeChannelAppealFlow.Operation.submit, .evidence, .withdraw] {
            let original = try CAIssuerHarness(operation: operation); await original.flow.activate()
            original.wire.loseResponse = true
            XCTAssertTrue(original.flow.prepare(operation, text: "original bytes")); await original.flow.confirm()
            let saved = original.journal.rows; let id = try XCTUnwrap(original.flow.requestID)
            original.flow.deactivate()
            let cold = try CAIssuerHarness(operation: operation, rights: [.originalReceipt], journal: original.journal, epoch: 9)
            cold.wire.receipt = original.wire.receipt
            await cold.flow.activate()
            XCTAssertEqual(cold.wire.paths.first, "/api/channel-platform/governance/moderation/requests/" + id)
            XCTAssertFalse(saved.isEmpty); XCTAssertTrue(cold.journal.rows.isEmpty)
            XCTAssertEqual(cold.flow.state, .applied); XCTAssertTrue(cold.flow.currentReadFailed)
            XCTAssertFalse(cold.flow.canRetry); XCTAssertFalse(cold.flow.canSupplement); XCTAssertTrue(cold.wire.posts.isEmpty)
        }
    }

    func testColdDifferentOwnerCannotBorrowOriginalJournalOrReceipt() async throws {
        let first = try CAIssuerHarness(operation: .submit); await first.flow.activate(); first.wire.loseResponse = true
        XCTAssertTrue(first.flow.prepare(.submit, text: "private original")); await first.flow.confirm()
        let saved = first.journal.rows; first.flow.deactivate()
        for change in ["account", "namespace", "baseURL"] {
            let other = try CAIssuerHarness(operation: .submit, journal: first.journal,
                account: change == "account" ? 18 : 17, namespace: change == "namespace" ? "other" : "issuer",
                baseURL: change == "baseURL" ? "https://other.test/" : "https://example.test/")
            XCTAssertFalse(other.flow.hasPending); await other.flow.activate()
            XCTAssertFalse(other.wire.paths.contains(where: { $0.contains("/requests/") }))
            XCTAssertTrue(other.wire.posts.isEmpty); XCTAssertEqual(first.journal.rows, saved)
        }
    }

    func testUnknownPendingAndNotFoundNeverAutomaticallyPostButExplicitRetryKeepsBytes() async throws {
        let h = try CAIssuerHarness(operation: .evidence); await h.flow.activate(); h.wire.loseResponse = true
        XCTAssertTrue(h.flow.prepare(.evidence, text: "same bytes")); await h.flow.confirm()
        let saved = h.journal.rows; let first = try XCTUnwrap(h.wire.posts.first)
        h.wire.lookup = ["state": "NOT_FOUND", "retry_with_original_request": true]
        await h.flow.refresh(); XCTAssertEqual(h.wire.posts.count, 1); XCTAssertEqual(h.journal.rows, saved)
        await h.flow.retryOriginal()
        XCTAssertEqual(h.wire.posts.count, 2); XCTAssertEqual(h.wire.posts.last?.httpBody, first.httpBody)
        XCTAssertEqual(h.wire.posts.last?.url, first.url); XCTAssertEqual(h.journal.rows, saved)
    }

    func testRevocationAfterReviewAndAfterDurableWriteCannotForward() async throws {
        let before = try CAIssuerHarness(operation: .submit); await before.flow.activate()
        XCTAssertTrue(before.flow.prepare(.submit, text: "review")); before.policyStore.replace(with: nil); await before.flow.confirm()
        XCTAssertEqual(before.journal.writes, 0); XCTAssertTrue(before.wire.posts.isEmpty); XCTAssertFalse(before.flow.isCurrent)
        let after = try CAIssuerHarness(operation: .evidence); await after.flow.activate()
        after.journal.afterWrite = { after.policyStore.replace(with: nil) }
        XCTAssertTrue(after.flow.prepare(.evidence, text: "review")); await after.flow.confirm()
        XCTAssertEqual(after.journal.writes, 1); XCTAssertTrue(after.flow.hasPending)
        XCTAssertFalse(after.journal.rows.isEmpty); XCTAssertTrue(after.wire.posts.isEmpty)
    }

    func testSameRightsReplacementStillInvalidatesOldIssuedObjects() async throws {
        let h = try CAIssuerHarness(operation: .submit); await h.flow.activate()
        XCTAssertTrue(h.flow.prepare(.submit, text: "review"))
        let selected = try XCTUnwrap(h.policyStore.selected); h.policyStore.replace(with: selected)
        await h.flow.confirm()
        XCTAssertFalse(h.flow.isCurrent); XCTAssertTrue(h.wire.posts.isEmpty); XCTAssertEqual(h.journal.writes, 0)
    }

    func testRevocationDuringResponseCannotPublishOrHandleOldUnauthorized() async throws {
        let h = try CAIssuerHarness(operation: .evidence)
        h.wire.unauthorized = true; h.wire.beforeReturn = { h.policyStore.replace(with: nil) }
        await h.flow.activate()
        XCTAssertEqual(h.unauthorizedCount, 0); XCTAssertNil(h.flow.appealDetails)
        XCTAssertTrue(h.locators.rows.isEmpty); XCTAssertFalse(h.flow.isCurrent)
    }

    func testAccountEpochAndServerContextChangesDenyOldFlightAndPreserveJournal() async throws {
        for change in ["account", "epoch", "namespace", "baseURL"] {
            let h = try CAIssuerHarness(operation: .submit); await h.flow.activate()
            let changed = RuntimeDependencyContext(market: .china,
                baseURL: change == "baseURL" ? URL(string: "https://other.test/")! : h.context.baseURL, role: "player",
                session: try .init(accountID: change == "account" ? 18 : 17, epoch: change == "epoch" ? 9 : 3,
                    namespace: change == "namespace" ? "other" : "issuer", token: change == "epoch" ? "fixture-9" : "fixture-3"))
            h.wire.beforeReturn = { h.selectedContext = changed }
            XCTAssertTrue(h.flow.prepare(.submit, text: change)); await h.flow.confirm()
            XCTAssertTrue(h.flow.hasPending); XCTAssertFalse(h.journal.rows.isEmpty)
            XCTAssertEqual(h.wire.posts.count, 1); XCTAssertNil(h.flow.appealDetails)
        }
    }

    func testUnreviewedWrongRealmWrongEndpointOrWrongNoticeDoesNotConstructRuntime() throws {
        let h = try CAIssuerHarness(operation: .submit)
        h.policyStore.replace(with: nil); XCTAssertNil(h.makeFlow())
        for policy in [try NativeChannelAppealEndpointPolicy(baseURL: URL(string: "https://other.test/")!, namespace: "issuer", rights: [.submit]),
                       try NativeChannelAppealEndpointPolicy(baseURL: h.context.baseURL, namespace: "other", rights: [.submit])] {
            h.policyStore.replace(with: policy); XCTAssertNil(h.makeFlow())
        }
        h.policyStore.replace(with: try .init(baseURL: h.context.baseURL, namespace: "issuer", rights: CAIssuerHarness.allRights))
        let wrong = NativeChannelGovernanceNotice(messageID: 1, conversationID: 2, recipientID: 18, actionID: "51", guildKind: 1, guildID: "42")
        XCTAssertNil(NativeChannelAppealRuntime.makeFlow(notice: wrong, context: h.context, policyStore: h.policyStore, underlying: h.wire,
            storage: h.journal, locatorStorage: h.locators, current: { true }, unauthorized: {}))
    }

    func testExactIssuerRejectsSiblingUUIDChangedBodyAndChangedTarget() throws {
        let h = try CAIssuerHarness(operation: .submit)
        let binding = try XCTUnwrap(NativeChannelAppealRuntime.binding(notice: h.notice, context: h.context, policyStore: h.policyStore, underlying: h.wire, current: { h.live }))
        let command = try h.command()
        h.journal.rows["proof"] = command.body
        XCTAssertTrue(binding.authorization.issue(command, recovering: false, pendingMatches: { h.journal.rows["proof"] == command.body }))
        let receipt = "api/channel-platform/governance/moderation/requests/" + command.requestID
        XCTAssertTrue(binding.authorization.permits("GET", receipt))
        XCTAssertFalse(binding.authorization.permits("GET", "api/channel-platform/governance/moderation/requests/22222222-2222-4222-8222-222222222222"))
        let changedBody = try h.command(text: "different body")
        XCTAssertFalse(binding.authorization.issue(changedBody, recovering: false, pendingMatches: { h.journal.rows["proof"] == changedBody.body }))
        let wrongAction = try h.command(action: "52")
        XCTAssertFalse(binding.authorization.issue(wrongAction, recovering: false, pendingMatches: { h.journal.rows["proof"] == wrongAction.body }))
        let changedPath = NativeChannelAppealOriginalCommand(operation: .submit, requestID: command.requestID, path: "api/im/appeals/61/evidence", body: command.body)
        XCTAssertFalse(binding.authorization.issue(changedPath, recovering: false, pendingMatches: { h.journal.rows["proof"] == command.body }))
    }

    func testFinalTransportRequiresExactEnvelopeAndDurableOriginalBytes() async throws {
        let h = try CAIssuerHarness(operation: .submit)
        let binding = try XCTUnwrap(NativeChannelAppealRuntime.binding(notice: h.notice, context: h.context, policyStore: h.policyStore, underlying: h.wire, current: { h.live }))
        let command = try h.command()
        XCTAssertTrue(binding.authorization.issue(command, recovering: false, pendingMatches: { h.journal.rows["proof"] == command.body }))
        let good = h.request(command)
        XCTAssertFalse(binding.authorization.accepts(good), "Issuance alone cannot replace journal persistence")
        h.journal.rows["proof"] = command.body; XCTAssertTrue(binding.authorization.accepts(good))
        for change in ["query", "fragment", "token", "cookie", "method", "body", "host", "stream"] {
            var bad = good
            switch change {
            case "query": bad.url = URL(string: good.url!.absoluteString + "?other=1")
            case "fragment": bad.url = URL(string: good.url!.absoluteString + "#ignored")
            case "token": bad.setValue("other", forHTTPHeaderField: "Authorization")
            case "cookie": bad.setValue("x=1", forHTTPHeaderField: "Cookie")
            case "method": bad.httpMethod = "GET"
            case "body": bad.httpBody = try h.command(text: "changed").body
            case "host": bad.url = URL(string: "https://other.test/api/im/appeals")
            default: bad.httpBodyStream = InputStream(data: command.body)
            }
            XCTAssertFalse(binding.authorization.accepts(bad), change)
            do { _ = try await binding.transport.send(bad); XCTFail("Invalid envelope forwarded: \(change)") } catch { }
        }
        XCTAssertTrue(h.wire.requests.isEmpty)
        h.journal.rows["proof"] = nil; XCTAssertFalse(binding.authorization.accepts(good))
    }

    func testCurrentReadGrantsAreExactIndependentAndNeverBecomeWriterApproval() throws {
        let h = try CAIssuerHarness(operation: .submit, rights: [.moderationRead, .appealRead])
        let binding = try XCTUnwrap(NativeChannelAppealRuntime.binding(notice: h.notice, context: h.context, policyStore: h.policyStore, underlying: h.wire, current: { h.live }))
        var request = h.request(try h.command()); request.httpMethod = "GET"; request.httpBody = nil
        var url = URLComponents(url: h.context.baseURL.appendingPathComponent("api/im/moderation/me"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "guild_kind", value: "1"), URLQueryItem(name: "guild_id", value: "42")]
        request.url = url.url; XCTAssertTrue(binding.authorization.accepts(request))
        url.queryItems = [URLQueryItem(name: "guild_kind", value: "1"), URLQueryItem(name: "guild_id", value: "43")]
        request.url = url.url; XCTAssertFalse(binding.authorization.accepts(request))
        binding.authorization.locateCurrentAppeal("api/im/appeals/61")
        request.url = h.context.baseURL.appendingPathComponent("api/im/appeals/61"); XCTAssertTrue(binding.authorization.accepts(request))
        request.url = h.context.baseURL.appendingPathComponent("api/im/appeals/62"); XCTAssertFalse(binding.authorization.accepts(request))
        binding.authorization.acceptCurrentAppeal("61")
        XCTAssertFalse(binding.authorization.permits("POST", "api/im/appeals/61/evidence"))
        XCTAssertFalse(binding.authorization.permits("POST", "api/im/appeals/61/withdraw"))
        XCTAssertFalse(binding.authorization.permits("POST", "api/im/appeals"))
    }

    func testReceiptOnlyIssuerDoesNotGrantWriterOrUnprovenRestoration() throws {
        let h = try CAIssuerHarness(operation: .submit, rights: [.originalReceipt])
        let binding = try XCTUnwrap(NativeChannelAppealRuntime.binding(notice: h.notice, context: h.context, policyStore: h.policyStore, underlying: h.wire, current: { h.live }))
        let command = try h.command()
        XCTAssertFalse(binding.authorization.issue(command, recovering: false, pendingMatches: { h.journal.rows["proof"] == command.body }))
        XCTAssertFalse(binding.authorization.issue(command, recovering: true, pendingMatches: { h.journal.rows["proof"] == command.body }))
        h.journal.rows["proof"] = command.body
        XCTAssertTrue(binding.authorization.issue(command, recovering: true, pendingMatches: { h.journal.rows["proof"] == command.body }))
        XCTAssertTrue(binding.authorization.permits("GET", "api/channel-platform/governance/moderation/requests/" + command.requestID))
        XCTAssertFalse(binding.authorization.permits("POST", command.path)); XCTAssertFalse(binding.authorization.accepts(h.request(command)))
    }
}

@MainActor private final class CAIssuerStore: ProjectEditDataStorage {
    var rows: [String: Data] = [:]; var writes = 0; var afterWrite: (() -> Void)?
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { writes += 1; rows[key] = data; afterWrite?() }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class CAIssuerWire: HTTPTransport {
    var requests: [URLRequest] = []; var posts: [URLRequest] = []; var paths: [String] = []
    var existingAppeal = false; var withdrawn = false; var loseResponse = false; var unauthorized = false
    var receipt: [String: Any] = [:]; var lookup: [String: Any]?; var beforeReturn: (() -> Void)?
    func detail() -> [String: Any] {
        ["appeal_id": "61", "action_id": "51", "appellant_member_id": "17", "status": withdrawn ? "WITHDRAWN" : "PENDING",
         "can_add_evidence": withdrawn ? 0 : 1, "reason_text": "independent current", "evidence_json": NSNull(), "supplements": [], "timeline": []]
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); let path = try XCTUnwrap(request.url).path; paths.append(path)
        let result: [String: Any]
        if request.httpMethod == "POST" {
            posts.append(request); existingAppeal = true; withdrawn = path.hasSuffix("/withdraw")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            receipt = detail(); receipt["request_id"] = body["request_id"] ?? body["submit_request_id"]
            receipt["state"] = "APPLIED"; receipt["reason_text"] = "historical result"
            if loseResponse { throw URLError(.timedOut) }; result = receipt
        } else if path.contains("/requests/") { result = lookup ?? ["state": "APPLIED", "result": receipt] }
        else if path.hasSuffix("/moderation/me") {
            var row: [String: Any] = ["action_id": "51", "guild_kind": 1, "guild_id": "42", "target_member_id": "17", "appealable": existingAppeal ? 0 : 1]
            if existingAppeal { row["existing_appeal_id"] = "61" }; result = ["list": [row]]
        } else if path.hasSuffix("/appeals/61") { result = detail() }
        else { XCTFail("Unexpected exact path \(path)"); throw APIError.invalidRequest }
        let status = unauthorized ? 401 : 200
        let bytes = try JSONSerialization.data(withJSONObject: ["code": status, "data": result]); beforeReturn?()
        return (bytes, status)
    }
}
@MainActor private final class CAIssuerHarness {
    static let allRights: Set<NativeChannelAppealEndpointPolicy.Right> = [.moderationRead, .appealRead, .submit, .evidence, .withdraw, .originalReceipt]
    let journal: CAIssuerStore; let locators = CAIssuerStore(); let wire = CAIssuerWire()
    let context: RuntimeDependencyContext; let notice: NativeChannelGovernanceNotice; let policyStore: NativeChannelAppealPolicyStore
    var flow: NativeChannelAppealFlow!; var live = true; var unauthorizedCount = 0
    var selectedContext: RuntimeDependencyContext?
    init(operation: NativeChannelAppealFlow.Operation, rights: Set<NativeChannelAppealEndpointPolicy.Right> = CAIssuerHarness.allRights,
         journal: CAIssuerStore? = nil, epoch: UInt64 = 3, account: Int = 17, namespace: String = "issuer", baseURL: String = "https://example.test/") throws {
        self.journal = journal ?? CAIssuerStore(); wire.existingAppeal = operation != .submit
        context = RuntimeDependencyContext(market: .china, baseURL: URL(string: baseURL)!, role: "player",
            session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: "fixture-\(epoch)"))
        notice = NativeChannelGovernanceNotice(messageID: 1, conversationID: 2, recipientID: account, actionID: "51", guildKind: 1, guildID: "42")
        policyStore = NativeChannelAppealPolicyStore(try .init(baseURL: context.baseURL, namespace: context.session.namespace, rights: rights))
        selectedContext = context
        flow = try XCTUnwrap(makeFlow())
    }
    func makeFlow() -> NativeChannelAppealFlow? {
        NativeChannelAppealRuntime.makeFlow(notice: notice, context: context, policyStore: policyStore, underlying: wire,
            storage: journal, locatorStorage: locators, current: { self.live && self.selectedContext == self.context }, unauthorized: { self.unauthorizedCount += 1 })
    }
    func command(text: String = "original", action: String = "51") throws -> NativeChannelAppealOriginalCommand {
        let id = "11111111-1111-4111-8111-111111111111"
        let body: [String: Any] = ["guild_kind": 1, "guild_id": "42", "action_id": action, "reason_code": "MISJUDGE", "reason_text": text, "submit_request_id": id]
        return .init(operation: .submit, requestID: id, path: "api/im/appeals", body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes]))
    }
    func request(_ command: NativeChannelAppealOriginalCommand) -> URLRequest {
        var request = URLRequest(url: context.baseURL.appendingPathComponent(command.path)); request.httpMethod = "POST"
        request.httpShouldHandleCookies = false; request.httpBody = command.body
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
