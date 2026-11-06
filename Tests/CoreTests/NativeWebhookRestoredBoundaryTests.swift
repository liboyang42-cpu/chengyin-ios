import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Offline regression boundaries for restored leaves. No runtime wiring or live grants.
/// RECEIVED/UNKNOWN remain fail-closed until their wire identity contract is proven.
@MainActor final class NativeWebhookRestoredBoundaryTests: XCTestCase {
    private func fixture(_ suppliedJournal: NativeWebhookMemoryJournal? = nil) throws -> (NativeWebhookCoordinator, NativeWebhookHTTPService, NativeWebhookFixtureProvider, NativeWebhookFixtureTransport, NativeWebhookMemoryJournal) {
        let journal = suppliedJournal ?? NativeWebhookMemoryJournal()
        let provider = NativeWebhookFixtureProvider(try NativeWebhookFixtures.context())
        var stored = NativeWebhookFixtures.resourceJSON()
        let transport = NativeWebhookFixtureTransport { request in
            if request.httpMethod != "GET" { stored = NativeWebhookFixtures.resourceJSON(revision: 5, keyVersion: 3); return (NativeWebhookFixtures.envelope(stored), 200) }
            let json = request.url?.path == NativeWebhookRuntimeRoute.collection(.subscription)
                ? "{\"list\":[" + stored + "],\"has_more\":false,\"next_cursor\":null}"
                : stored
            return (NativeWebhookFixtures.envelope(json), 200)
        }
        let service = NativeWebhookHTTPService(provider: provider, authorizer: provider, transport: transport)
        return (NativeWebhookCoordinator(service: service, provider: provider, journal: NativeWebhookPendingJournal(journal: journal)), service, provider, transport, journal)
    }

    func testJournalBeforeDispatchUnknownDoesNotAutomaticallyResendOrMintNewID() async throws {
        let (flow, _, _, transport, journal) = try fixture()
        await flow.load()
        flow.prepareAction(.rotate, resource: try NativeWebhookFixtures.resource())
        let confirmation = try XCTUnwrap(flow.confirmation)
        transport.respond = { request in
            XCTAssertEqual(journal.record?.nativeWebhook?.requestID, confirmation.requestID)
            if request.httpMethod == "POST" { throw URLError(.timedOut) }
            return (NativeWebhookFixtures.list(), 200)
        }
        await flow.confirm(confirmation.id)
        XCTAssertEqual(flow.phase, .unknown); XCTAssertEqual(flow.pending?.requestID, confirmation.requestID)
        let count = transport.requests.count
        flow.prepareAction(.rotate, resource: try NativeWebhookFixtures.resource())
        XCTAssertNil(flow.confirmation); XCTAssertEqual(transport.requests.count, count)
        flow.background(); XCTAssertNotNil(journal.record)
    }

    func testCompleteURLsAreNotPersistedAndWrongOriginalURLCannotReplay() throws {
        let (_, service, provider, _, journal) = try fixture()
        var draft = NativeWebhookEditorDraft(); draft.name = "fixture"; draft.url = "https://target.invalid/path?credential=synthetic-private"; draft.events = ["channel.message.created"]
        let change = try draft.change(family: .subscription, context: provider.value, original: nil, requestID: .make())
        let request = try service.changeRequest(.subscription, change: change, original: nil, context: provider.value)
        let adapter = NativeWebhookPendingJournal(journal: journal); try adapter.reserve(request)
        let metadata = try XCTUnwrap(adapter.pending(provider.value.binding))
        let encoded = String(decoding: try JSONEncoder().encode(XCTUnwrap(journal.record)), as: UTF8.self)
        XCTAssertFalse(encoded.contains("synthetic-private")); XCTAssertFalse(encoded.contains("target.invalid"))
        XCTAssertTrue(metadata.needsOriginalInput); XCTAssertThrowsError(try metadata.originalRequest())
        XCTAssertThrowsError(try metadata.originalRequest(url: "https://target.invalid/changed"))
        XCTAssertEqual(try metadata.originalRequest(url: draft.url).body, request.body)
    }

    func testCorruptedRecoveryRouteAndFlagsFailBeforeAnyMutation() async throws {
        let (flow, service, provider, transport, journal) = try fixture()
        let request = try service.actionRequest(.rotate, family: .subscription, resource: NativeWebhookFixtures.resource(), context: provider.value, requestID: .make())
        let adapter = NativeWebhookPendingJournal(journal: journal); try adapter.reserve(request)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(XCTUnwrap(journal.record?.nativeWebhook))) as? [String: Any])
        object["path"] = NativeWebhookRuntimeRoute.rotate(.subscription, id: NativeWebhookID(rawValue: "12")!)
        let corrupted = try JSONDecoder().decode(NativeWebhookPendingMetadata.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try corrupted.originalRequest())
        journal.record?.nativeWebhook = corrupted
        await flow.load(); flow.prepareRecovery()
        XCTAssertNil(flow.confirmation); XCTAssertFalse(transport.requests.contains { $0.httpMethod != "GET" })
        XCTAssertEqual(journal.record?.nativeWebhook?.requestID, request.requestID)
    }

    func testBackgroundDuringMutationSuppressesLateCredentialAndLeaveClearsAllPresentation() async throws {
        let (flow, _, _, transport, journal) = try fixture(); await flow.load()
        flow.prepareAction(.rotate, resource: try NativeWebhookFixtures.resource())
        transport.respond = { request in
            if request.httpMethod == "POST" {
                flow.background()
                return (NativeWebhookFixtures.envelope(NativeWebhookFixtures.resourceJSON(revision: 5, keyVersion: 3, extra: #", "secret_shown_once":true,"secret":"synthetic-secret""#)), 200)
            }
            return request.url?.path == NativeWebhookRuntimeRoute.collection(.subscription)
                ? (NativeWebhookFixtures.list(), 200) : (NativeWebhookFixtures.envelope(NativeWebhookFixtures.resourceJSON()), 200)
        }
        await flow.confirm(try XCTUnwrap(flow.confirmation).id)
        XCTAssertNil(flow.credential); XCTAssertNil(journal.record)
        flow.leave(); XCTAssertTrue(flow.resources.isEmpty); XCTAssertNil(flow.selected); XCTAssertNil(flow.context); XCTAssertNil(flow.confirmation)
    }

    func testIndependentEndpointApprovalRevokedDuringReadClearsPrivatePresentation() async throws {
        let (flow, _, provider, transport, _) = try fixture(); await flow.load()
        XCTAssertFalse(flow.resources.isEmpty)
        transport.respond = { _ in provider.endpointApproved = false; return (NativeWebhookFixtures.list(), 200) }
        await flow.load()
        XCTAssertTrue(flow.resources.isEmpty); XCTAssertNil(flow.context); XCTAssertEqual(flow.phase, .unavailable)
        XCTAssertEqual(flow.issue, .sourceUnavailable("WEBHOOK_REVIEWED_ENDPOINT_APPROVAL_UNAVAILABLE"))
    }

    private func inboundRow(_ state: NativeWebhookInboundState, inserted: Bool) -> [String: Any] {
        var row: [String: Any] = ["id": "71", "result": state.rawValue, "state": state.rawValue,
            "endpoint_id": NativeWebhookFixtures.resourceID.rawValue]
        if inserted {
            row["webhook_id"] = NativeWebhookFixtures.resourceID.rawValue
            row["sender_type"] = 4
            row["message_id"] = "72"
            row["original_message_stored"] = true
        }
        return row
    }

    private func readInbound(_ row: [String: Any], filter: NativeWebhookInboundState) async throws -> NativeWebhookPage<NativeWebhookInboundLog> {
        let provider = NativeWebhookFixtureProvider(try NativeWebhookFixtures.context())
        let data = try JSONSerialization.data(withJSONObject: ["code": 200,
            "data": ["list": [row], "has_more": false, "next_cursor": NSNull()]])
        let transport = NativeWebhookFixtureTransport { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, NativeWebhookRuntimeRoute.inboundLogs(NativeWebhookFixtures.resourceID))
            let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first(where: { $0.name == "result" })?.value, filter.rawValue)
            XCTAssertEqual(query?.first(where: { $0.name == "cursor" })?.value, "opaque+==")
            return (data, 200)
        }
        let service = NativeWebhookHTTPService(provider: provider, authorizer: provider, transport: transport)
        return try await service.inboundLogs(NativeWebhookFixtures.resourceID, context: provider.value,
            result: filter, cursor: "opaque+==")
    }

    private func assertInvalidInbound(_ row: [String: Any], state: NativeWebhookInboundState,
                                      file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await readInbound(row, filter: state)
            XCTFail("Invalid identity must fail closed", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? NativeWebhookClientError, .invalidWire, file: file, line: line)
        }
    }

    func testSupportedInboundIdentityShapesPreserveOriginalMessageIdentity() async throws {
        for state in [NativeWebhookInboundState.accepted, .pendingReview, .blocked] {
            let page = try await readInbound(inboundRow(state, inserted: true), filter: state)
            XCTAssertEqual(page.list.count, 1)
            XCTAssertEqual(page.list.first?.messageID?.rawValue, "72")
            XCTAssertEqual(page.list.first?.senderType, 4)
            XCTAssertEqual(page.list.first?.webhookID, NativeWebhookFixtures.resourceID)
        }
        // Legacy accepted rows may omit endpoint_id, but still require original message identity.
        var accepted = inboundRow(.accepted, inserted: true)
        accepted.removeValue(forKey: "endpoint_id")
        let acceptedPage = try await readInbound(accepted, filter: .accepted)
        XCTAssertEqual(acceptedPage.list.first?.result, .accepted)
        for state in [NativeWebhookInboundState.rejected, .blocked, .rateLimited] {
            let page = try await readInbound(inboundRow(state, inserted: false), filter: state)
            XCTAssertEqual(page.list.first?.endpointID, NativeWebhookFixtures.resourceID)
            XCTAssertNil(page.list.first?.messageID)
            XCTAssertNil(page.list.first?.senderType)
            XCTAssertNil(page.list.first?.webhookID)
        }
    }

    func testInsertedInboundIdentityMismatchCannotBePresentedAsAcceptedOrStored() async {
        for state in [NativeWebhookInboundState.accepted, .pendingReview, .blocked] {
            for field in ["endpoint_id", "webhook_id", "sender_type", "message_id", "state"] {
                var row = inboundRow(state, inserted: true)
                switch field {
                case "sender_type": row[field] = 1
                case "message_id": row.removeValue(forKey: field)
                case "state": row[field] = "UNKNOWN"
                default: row[field] = "99"
                }
                await assertInvalidInbound(row, state: state)
            }
        }
        for state in [NativeWebhookInboundState.pendingReview, .blocked] {
            var row = inboundRow(state, inserted: true)
            row["original_message_stored"] = false
            await assertInvalidInbound(row, state: state)
        }
    }

    func testPreinsertRejectionCannotInventStoredMessageOrSender() async {
        for state in [NativeWebhookInboundState.rejected, .blocked, .rateLimited] {
            for field in ["endpoint_id", "webhook_id", "sender_type", "message_id", "original_message_stored"] {
                var row = inboundRow(state, inserted: false)
                switch field {
                case "sender_type": row[field] = 4
                case "original_message_stored": row[field] = true
                default: row[field] = "99"
                }
                await assertInvalidInbound(row, state: state)
            }
        }
    }

    func testReceivedAndUnknownRemainFailClosedWithoutProvenWireContract() async {
        for state in [NativeWebhookInboundState.received, .unknown] {
            await assertInvalidInbound(inboundRow(state, inserted: false), state: state)
            await assertInvalidInbound(inboundRow(state, inserted: true), state: state)
        }
    }

    func testCurrentAuthorityRebindRequiresExplicitConfirmationAndPreservesOriginalBytes() async throws {
        let (_, service, provider, _, journal) = try fixture()
        let original = try service.actionRequest(.rotate, family: .subscription,
            resource: NativeWebhookFixtures.resource(), context: provider.value,
            requestID: NativeWebhookRequestID(rawValue: "original-rebound-rotation")!)
        try NativeWebhookPendingJournal(journal: journal).reserve(original)
        let historical = try XCTUnwrap(journal.record)
        let (flow, _, current, transport, _) = try fixture(journal)
        current.value = try NativeWebhookFixtures.context(version: "fixture-permission-version-8")
        await flow.load()
        XCTAssertEqual(flow.pending?.binding, original.binding)
        XCTAssertFalse(transport.requests.contains { $0.httpMethod != "GET" })
        flow.prepareRecovery()
        let confirmation = try XCTUnwrap(flow.confirmation)
        XCTAssertEqual(confirmation.requestID, original.requestID)
        XCTAssertEqual(journal.record, historical)
        XCTAssertFalse(transport.requests.contains { $0.httpMethod != "GET" })
        let rebound = try XCTUnwrap(flow.pending).rebound(to: current.value.binding)
        let request = try rebound.originalRequest()
        XCTAssertEqual(request.binding, current.value.binding)
        XCTAssertEqual(request.requestID, original.requestID)
        XCTAssertEqual(request.body, original.body)
        XCTAssertEqual(request.path, original.path)
        XCTAssertEqual(request.method, original.method)
        transport.respond = { request in
            if request.httpMethod != "GET" {
                XCTAssertEqual(journal.record, historical)
                XCTAssertEqual(request.httpBody, original.body)
                XCTAssertEqual(request.url?.path, original.path)
                // Unknown outcome must preserve the historically stored binding as well.
                throw URLError(.timedOut)
            }
            return (NativeWebhookFixtures.list(), 200)
        }
        await flow.confirm(confirmation.id)
        XCTAssertEqual(transport.requests.filter { $0.httpMethod != "GET" }.count, 1)
        XCTAssertEqual(flow.phase, .unknown)
        XCTAssertEqual(journal.record, historical)
        XCTAssertEqual(flow.pending?.requestID, original.requestID)
    }

    func testRecoveryCannotRebindAcrossAnyDurableIdentityBoundary() throws {
        let (_, service, provider, transport, journal) = try fixture()
        let original = try service.actionRequest(.rotate, family: .subscription,
            resource: NativeWebhookFixtures.resource(), context: provider.value, requestID: .make())
        let adapter = NativeWebhookPendingJournal(journal: journal)
        try adapter.reserve(original)
        let metadata = try XCTUnwrap(adapter.pending(original.binding))
        let old = original.binding
        let historical = journal.record
        for field in ["account", "market", "namespace", "origin", "owner", "channel"] {
            let binding = try NativeWebhookBinding(accountID: field == "account" ? "20" : old.accountID,
                market: field == "market" ? "US" : old.market,
                namespace: field == "namespace" ? "other" : old.namespace,
                origin: field == "origin" ? URL(string: "https://other.invalid")! : old.origin,
                scope: NativeWebhookScope(ownerID: field == "owner" ? NativeWebhookID(rawValue: "21")! : old.scope.ownerID,
                    channelID: field == "channel" ? NativeWebhookID(rawValue: "22")! : old.scope.channelID),
                authorizationVersion: "current-version")
            XCTAssertThrowsError(try metadata.rebound(to: binding)) { error in
                XCTAssertEqual(error as? NativeWebhookClientError, .scopeChanged)
            }
            XCTAssertEqual(journal.record, historical)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testWebhookRoutesPreserveApprovedDeploymentPrefixAndOpaqueQuery() throws {
        for base in ["https://webhook.example.com", "https://webhook.example.com/prod-api", "https://webhook.example.com/prod-api/"] {
            let origin = try XCTUnwrap(URL(string: base))
            let binding = try NativeWebhookBinding(accountID: "19", market: "CN", namespace: "fixture-only",
                origin: origin, scope: NativeWebhookFixtures.scope, authorizationVersion: "current")
            let path = NativeWebhookRuntimeRoute.collection(.subscription)
            let url = try NativeWebhookRuntimeRoute.url(binding: binding, path: path,
                query: [URLQueryItem(name: "cursor", value: "opaque+/=&")])
            var expected = try XCTUnwrap(URLComponents(url: origin.appendingPathComponent(String(path.dropFirst())), resolvingAgainstBaseURL: false))
            expected.queryItems = [URLQueryItem(name: "cursor", value: "opaque+/=&")]
            XCTAssertEqual(url.absoluteString, expected.url?.absoluteString)
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "opaque+/=&")
            for invalid in ["/api/other", "/api/im/webhook/../other", "/api/im/webhook/endpoints?x=1", "/api/im/webhook/endpoints#fragment",
                            "/api/im/webhook/%2e%2e/other", "/api/im/webhook/endpoints%2f99",
                            "/api/im/webhook/./endpoints", "/api/im/webhook//endpoints",
                            "/api/im/webhook/endpoints\\99"] {
                XCTAssertThrowsError(try NativeWebhookRuntimeRoute.url(binding: binding, path: invalid))
            }
        }
        XCTAssertThrowsError(try NativeWebhookBinding(accountID: "19", market: "CN", namespace: "fixture-only",
            origin: URL(string: "https://webhook.example.com/prod-api/../other")!,
            scope: NativeWebhookFixtures.scope, authorizationVersion: "current"))
    }

    func testRuntimeAuthorizerMatchesExactApprovedRelativePathUnderDeploymentPrefix() async throws {
        let origin = URL(string: "https://webhook.example.com/prod-api")!
        let session = try PlayExperienceSession(accountID: 19, epoch: 7, namespace: "fixture-only", token: "synthetic-token")
        let captured = RuntimeDependencyContext(market: .china, baseURL: origin, role: "player", session: session)
        var current: RuntimeDependencyContext? = captured
        let binding = try NativeWebhookBinding(accountID: "19", market: captured.market.rawValue, namespace: session.namespace,
            origin: origin, scope: NativeWebhookFixtures.scope, authorizationVersion: "current")
        let context = NativeWebhookContext(binding: binding, eventCatalogue: .unavailable(code: "fixture"))
        let path = "api/im/webhook/subscriptions"
        let approval = try OperationEndpointApproval(baseURL: origin, namespace: session.namespace, accountID: 19, paths: [path])
        let provider = NativeWebhookRuntimeScopeProvider(captured: captured, scope: binding.scope,
            current: { current }, lookup: { context }, endpointApproval: { approval }, onUnauthorized: { _ in })
        let url = try NativeWebhookRuntimeRoute.url(binding: binding, path: "/" + path,
            query: [URLQueryItem(name: "cursor", value: "opaque+/=&")])
        var request = URLRequest(url: url); request.httpMethod = "GET"
        let authorized = try await provider.authorize(request, binding: binding)
        XCTAssertEqual(authorized.url?.absoluteString, url.absoluteString)
        XCTAssertEqual(authorized.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        for raw in ["https://webhook.example.com/api/im/webhook/subscriptions",
                    "https://webhook.example.com/prod-api/api/im/webhook/endpoints",
                    "https://webhook.example.com/prod-api-other/api/im/webhook/subscriptions",
                    "https://other.example.com/prod-api/api/im/webhook/subscriptions",
                    "https://webhook.example.com/prod-api/api/im/webhook/%73ubscriptions"] {
            do {
                _ = try await provider.authorize(URLRequest(url: URL(string: raw)!), binding: binding)
                XCTFail("Unapproved exact URL must not receive credentials: \(raw)")
            } catch {
                guard let failure = error as? NativeWebhookClientError, case .sourceUnavailable = failure else {
                    return XCTFail("Expected endpoint approval rejection, got \(error)")
                }
            }
        }
        current = nil
        do {
            _ = try await provider.authorize(request, binding: binding)
            XCTFail("Revoked session must not receive credentials")
        } catch {
            XCTAssertEqual(error as? NativeWebhookClientError, .scopeChanged)
        }
    }

    func testManagementContextSourceAndResourceRouteShareDeploymentPrefix() async throws {
        let origin = URL(string: "https://webhook.example.com/prod-api")!
        let session = try PlayExperienceSession(accountID: 19, epoch: 7, namespace: "fixture-only", token: "synthetic-token")
        let captured = RuntimeDependencyContext(market: .china, baseURL: origin, role: "player", session: session)
        let scope = NativeWebhookFixtures.scope
        let approval = try OperationEndpointApproval(baseURL: origin, namespace: session.namespace, accountID: 19,
            paths: ["api/im/webhook/context", "api/im/webhook/subscriptions"])
        let data = try JSONSerialization.data(withJSONObject: ["code": 200, "data": [
            "actor_id": "19", "owner_type": "CLUB", "owner_id": scope.ownerID.rawValue,
            "channel_id": scope.channelID.rawValue, "authorization_version": "current",
            "management_permission": "im:webhook:manage", "event_revision": "event-1", "events": []
        ]])
        let transport = NativeWebhookFixtureTransport { request in
            XCTAssertEqual(request.url?.path, "/prod-api/api/im/webhook/context")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            return (data, 200)
        }
        let source = NativeWebhookManagementContextSource(transport: transport, current: { captured },
            approval: { _, _ in approval }, onUnauthorized: { _ in XCTFail("Unexpected unauthorized") })
        let context = try await source.context(captured, scope: scope)
        XCTAssertEqual(context.binding.origin.absoluteString, origin.absoluteString)
        let resourceURL = try NativeWebhookRuntimeRoute.url(binding: context.binding,
            path: NativeWebhookRuntimeRoute.collection(.subscription))
        XCTAssertEqual(resourceURL.absoluteString, "https://webhook.example.com/prod-api/api/im/webhook/subscriptions")
        XCTAssertEqual(transport.requests.count, 1)
    }
}
