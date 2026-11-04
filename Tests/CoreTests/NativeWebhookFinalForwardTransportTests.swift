import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent synthetic fixtures. No URLSession, real HTTP, deployed grant or App host.
/// This suite exercises the final forwarder, not only an upstream authorizer's checks.
@MainActor final class NativeWebhookFinalForwardTransportTests: XCTestCase {
    private static let contextPath = "api/im/webhook/context"
    private static let subscriptions = "api/im/webhook/subscriptions"
    private static let endpoints = "api/im/webhook/endpoints"
    private static let resourceID = "9007199254740993"
    private static let deliveryID = "9007199254740997"
    private static let scope = NativeWebhookScope(ownerID: NativeWebhookID(rawValue: "9007199254740995")!,
        channelID: NativeWebhookID(rawValue: "9223372036854775807")!)
    private static let requestID = NativeWebhookRequestID(rawValue: "synthetic-original-request-7")!
    private static var allPaths: Set<String> {
        [contextPath, subscriptions, endpoints, subscriptions + "/" + resourceID, endpoints + "/" + resourceID,
         subscriptions + "/" + resourceID + "/deliveries", endpoints + "/" + resourceID + "/logs",
         subscriptions + "/" + resourceID + "/rotate-secret", endpoints + "/" + resourceID + "/rotate-token",
         subscriptions + "/" + resourceID + "/test",
         subscriptions + "/" + resourceID + "/deliveries/" + deliveryID + "/retry"]
    }
    private func context(account: Int = 19, epoch: UInt64 = 7, token: String = "synthetic-final-forward-token",
                         namespace: String = "synthetic-final-forward", role: String = "player",
                         sessionRole: String = "player", market: RegionalMarket = .china,
                         base: String = "https://webhook-forward.test:9443/native/v1") throws -> RuntimeDependencyContext {
        RuntimeDependencyContext(market: market, baseURL: URL(string: base)!, role: role,
            session: try PlayExperienceSession(accountID: account, epoch: epoch, namespace: namespace,
                token: token, role: sessionRole))
    }
    private func grant(_ captured: RuntimeDependencyContext, paths: Set<String>? = nil,
                       namespace: String? = nil, account: Int? = nil, base: URL? = nil) throws -> OperationEndpointApproval {
        try OperationEndpointApproval(baseURL: base ?? captured.baseURL,
            namespace: namespace ?? captured.session.namespace, accountID: account ?? captured.session.accountID,
            paths: paths ?? Self.allPaths)
    }
    private func state(_ captured: RuntimeDependencyContext? = nil, paths: Set<String>? = nil) throws -> State {
        let value: RuntimeDependencyContext
        if let captured { value = captured } else { value = try context() }
        return State(captured: value, issued: try grant(value, paths: paths))
    }
    private func fence(_ state: State, wire: any HTTPTransport) throws -> NativeWebhookFinalForwardTransport {
        try XCTUnwrap(makeFence(state, wire: wire))
    }
    private func makeFence(_ state: State, wire: any HTTPTransport) -> NativeWebhookFinalForwardTransport? {
        NativeWebhookFinalForwardTransport(captured: state.captured, scope: Self.scope, issued: state.issued,
            underlying: wire, current: { state.current }, approval: { state.approval }, presentation: { state.present })
    }
    private func request(_ state: State, path: String = "api/im/webhook/context", method: String = "GET",
                         query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        var parts = try XCTUnwrap(URLComponents(url: state.captured.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false))
        parts.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: try XCTUnwrap(parts.url))
        request.httpMethod = method; request.httpBody = body; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 17
        request.setValue(state.captured.session.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("synthetic-trace-7", forHTTPHeaderField: "X-Synthetic-Trace")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    private var contextQuery: [URLQueryItem] {
        [.init(name: "owner_id", value: Self.scope.ownerID.rawValue), .init(name: "channel_id", value: Self.scope.channelID.rawValue)]
    }
    private func listQuery(limit: String = "20", cursor: String? = nil) -> [URLQueryItem] {
        var result = [URLQueryItem(name: "limit", value: limit), .init(name: "owner_type", value: "CLUB")] + contextQuery
        if let cursor { result.append(.init(name: "cursor", value: cursor)) }
        return result
    }
    private func change(_ family: NativeWebhookFamily, revision: Int? = nil) -> NativeWebhookChange {
        NativeWebhookChange(requestID: Self.requestID, ownerType: "CLUB", ownerID: Self.scope.ownerID.requestNumber,
            channelID: Self.scope.channelID.requestNumber, name: "Synthetic integration / 保留原文",
            url: family == .subscription ? "https://synthetic-target.test/hook?a=1&b=%2F" : nil,
            avatarURL: family == .endpoint ? "https://synthetic-image.test/avatar.png" : nil,
            events: family == .subscription ? ["channel.message.created"] : nil,
            allowedIPs: family == .endpoint ? ["192.0.2.7"] : nil,
            rateLimitPerMinute: family == .endpoint ? 31 : nil, status: .active, revision: revision)
    }
    private func action(revision: Int? = 4, event: String? = nil) throws -> Data {
        try NativeWebhookHTTPService.encoded(NativeWebhookAction(requestID: Self.requestID, revision: revision, eventType: event))
    }
    private func assertRejected(_ request: URLRequest, by fence: NativeWebhookFinalForwardTransport, wire: Wire,
                                _ label: String = "", file: StaticString = #filePath, line: UInt = #line) async {
        let before = wire.requests.count
        do { _ = try await fence.send(request); XCTFail("Unexpected dispatch: " + label, file: file, line: line) }
        catch { XCTAssertEqual(error as? NativeWebhookClientError, .scopeChanged, label, file: file, line: line) }
        XCTAssertEqual(wire.requests.count, before, "Underlying transport must remain untouched: " + label, file: file, line: line)
    }
    private func assertPreserved(_ original: URLRequest, _ forwarded: URLRequest,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(forwarded, original, file: file, line: line)
        XCTAssertEqual(forwarded.url?.absoluteString, original.url?.absoluteString, file: file, line: line)
        XCTAssertEqual(forwarded.httpMethod, original.httpMethod, file: file, line: line)
        XCTAssertEqual(forwarded.httpBody, original.httpBody, file: file, line: line)
        XCTAssertEqual(forwarded.allHTTPHeaderFields, original.allHTTPHeaderFields, file: file, line: line)
        XCTAssertEqual(forwarded.timeoutInterval, original.timeoutInterval, file: file, line: line)
        XCTAssertEqual(forwarded.cachePolicy, original.cachePolicy, file: file, line: line)
        XCTAssertFalse(forwarded.httpShouldHandleCookies, file: file, line: line)
    }

    func testConstructionRequiresExactContextGrantAndLiveInputs() throws {
        let captured = try context(), wire = Wire()
        let invalidGrants = [
            try grant(captured, paths: []), try grant(captured, paths: [Self.subscriptions]),
            try grant(captured, namespace: "other-synthetic-namespace"), try grant(captured, account: 20),
            try grant(captured, base: URL(string: "https://other.test/native/v1")!)
        ]
        for approval in invalidGrants {
            XCTAssertNil(makeFence(State(captured: captured, issued: approval), wire: wire))
        }
        let missing = try state(); missing.approval = nil
        XCTAssertNil(makeFence(missing, wire: wire))
        let replacement = try state(); replacement.approval = try grant(captured, paths: [Self.contextPath])
        XCTAssertNil(makeFence(replacement, wire: wire))
        let signedOut = try state(); signedOut.current = nil
        XCTAssertNil(makeFence(signedOut, wire: wire))
        let absent = try state(); absent.present = false
        XCTAssertNil(makeFence(absent, wire: wire))
        XCTAssertTrue(wire.requests.isEmpty)
    }

    /// Regression: NSString-style canonical equivalence cannot grant a different namespace.
    func testCanonicallyEquivalentButByteDifferentIssuedNamespaceIsRejected() throws {
        let captured = try context(namespace: "synthetic-e\u{301}")
        let approval = try grant(captured, namespace: "synthetic-\u{e9}")
        XCTAssertFalse(approval.namespace.utf8.elementsEqual(captured.session.namespace.utf8))
        XCTAssertNil(makeFence(State(captured: captured, issued: approval), wire: Wire()))
    }

    func testExactContextOnlyGrantDoesNotManufactureCollectionOrActionApproval() async throws {
        let state = try state(paths: [Self.contextPath]), wire = Wire(), fence = try fence(state, wire: wire)
        _ = try await fence.send(request(state, query: contextQuery))
        for path in [Self.subscriptions, Self.endpoints, Self.subscriptions + "/" + Self.resourceID] {
            await assertRejected(try request(state, path: path, query: listQuery()), by: fence, wire: wire, path)
        }
        await assertRejected(try request(state, path: Self.subscriptions + "/" + Self.resourceID + "/rotate-secret",
            method: "POST", body: action()), by: fence, wire: wire)
        XCTAssertEqual(wire.requests.count, 1)
    }

    func testBasePrefixAndPortArePreservedAndCannotBeDroppedOrReplaced() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        let original = try request(state, query: contextQuery)
        _ = try await fence.send(original)
        XCTAssertEqual(wire.requests[0].url?.path, "/native/v1/api/im/webhook/context")
        XCTAssertEqual(wire.requests[0].url?.port, 9443)
        assertPreserved(original, wire.requests[0])
        for base in ["https://webhook-forward.test:9443", "https://webhook-forward.test:9443/native/v2",
                     "https://webhook-forward.test/native/v1", "https://webhook-forward.test:9444/native/v1"] {
            var changed = original
            changed.url = URL(string: base + "/api/im/webhook/context?owner_id=" + Self.scope.ownerID.rawValue
                + "&channel_id=" + Self.scope.channelID.rawValue)
            await assertRejected(changed, by: fence, wire: wire, base)
        }
    }

    func testOriginalReadRoutesAndAllWireEnumsRemainAcceptedWithoutPayloadRewrite() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        let payload = Data(#"{"opaque_payload":[9007199254740993,"e\u0301"],"code":200}"#.utf8)
        wire.respond = { _ in (payload, 207) }
        var requests = [try request(state, query: contextQuery)]
        for path in [Self.subscriptions, Self.endpoints] {
            for limit in ["1", "20", "100"] {
                requests.append(try request(state, path: path, query: listQuery(limit: limit)))
            }
            requests.append(try request(state, path: path, query: listQuery(cursor: String(repeating: "x", count: 512))))
            requests.append(try request(state, path: path + "/" + Self.resourceID))
        }
        for includePayload in ["0", "1"] {
            for deliveryState in NativeWebhookDeliveryState.allCases {
                requests.append(try request(state, path: Self.subscriptions + "/" + Self.resourceID + "/deliveries", query: [
                    .init(name: "limit", value: "20"), .init(name: "include_payload", value: includePayload),
                    .init(name: "state", value: deliveryState.rawValue), .init(name: "cursor", value: "synthetic+/=% cursor")]))
            }
        }
        for result in NativeWebhookInboundState.allCases {
            requests.append(try request(state, path: Self.endpoints + "/" + Self.resourceID + "/logs", query: [
                .init(name: "limit", value: "20"), .init(name: "result", value: result.rawValue)]))
        }
        for original in requests {
            let (body, status) = try await fence.send(original)
            XCTAssertEqual(body, payload); XCTAssertEqual(status, 207)
            assertPreserved(original, try XCTUnwrap(wire.requests.last))
        }
        XCTAssertEqual(wire.requests.count, requests.count)
    }

    func testContextQueryRequiresOnlyTheExactOwnerAndChannel() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        let invalid: [[URLQueryItem]] = [[], [contextQuery[0]], [contextQuery[1]],
            contextQuery + [.init(name: "owner_type", value: "CLUB")],
            contextQuery + [.init(name: "owner_id", value: Self.scope.ownerID.rawValue)],
            [.init(name: "owner_id", value: "19"), contextQuery[1]],
            [contextQuery[0], .init(name: "channel_id", value: "19")],
            [.init(name: "owner_id", value: nil), contextQuery[1]],
            [.init(name: "owner_id", value: ""), contextQuery[1]]]
        for query in invalid { await assertRejected(try request(state, query: query), by: fence, wire: wire) }
        // Query ordering is not a new API and must be preserved as supplied.
        let reordered = try request(state, query: Array(contextQuery.reversed()))
        _ = try await fence.send(reordered); assertPreserved(reordered, try XCTUnwrap(wire.requests.last))
    }

    func testCollectionQueryBoundsDuplicatesScopeAndUnknownKeysFailClosed() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        var invalid = [listQuery(limit: "0"), listQuery(limit: "101"), listQuery(limit: "020"),
            listQuery(limit: "+20"), listQuery(limit: "20.0"), listQuery(limit: " 20"),
            listQuery() + [.init(name: "limit", value: "20")],
            listQuery() + [.init(name: "include_payload", value: "1")],
            listQuery() + [.init(name: "cursor", value: nil)]]
        for key in ["limit", "owner_type", "owner_id", "channel_id"] {
            invalid.append(listQuery().filter { $0.name != key })
            invalid.append(listQuery().map { $0.name == key ? URLQueryItem(name: key, value: "synthetic-wrong") : $0 })
        }
        for path in [Self.subscriptions, Self.endpoints] {
            for query in invalid { await assertRejected(try request(state, path: path, query: query), by: fence, wire: wire, path) }
        }
    }

    func testOriginalOpaqueCursorHasNoInventedLengthOrNonemptyConstraint() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        for cursor in ["", String(repeating: "x", count: 513), String(repeating: "界+/=%", count: 300)] {
            for path in [Self.subscriptions, Self.endpoints] {
                let original = try request(state, path: path, query: listQuery(cursor: cursor))
                _ = try await fence.send(original)
                assertPreserved(original, try XCTUnwrap(wire.requests.last))
            }
            for (path, extra) in [(Self.subscriptions + "/" + Self.resourceID + "/deliveries", [URLQueryItem(name: "include_payload", value: "0")]),
                                  (Self.endpoints + "/" + Self.resourceID + "/logs", [])] {
                let original = try request(state, path: path, query: [URLQueryItem(name: "limit", value: "20"),
                    .init(name: "cursor", value: cursor)] + extra)
                _ = try await fence.send(original)
                assertPreserved(original, try XCTUnwrap(wire.requests.last))
            }
        }
        XCTAssertEqual(wire.requests.count, 12)
    }

    func testDetailDeliveryAndInboundQueriesCannotBroadenTheOriginalAPI() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        let subscription = Self.subscriptions + "/" + Self.resourceID, endpoint = Self.endpoints + "/" + Self.resourceID
        for path in [subscription, endpoint] {
            await assertRejected(try request(state, path: path, query: [.init(name: "include_payload", value: "1")]), by: fence, wire: wire)
        }
        let deliveryQuery = [URLQueryItem(name: "limit", value: "20"), .init(name: "include_payload", value: "0")]
        for query in [[URLQueryItem(name: "limit", value: "20")],
                      [.init(name: "limit", value: "20"), .init(name: "include_payload", value: "true")],
                      deliveryQuery + [.init(name: "state", value: "sent")],
                      deliveryQuery + [.init(name: "result", value: "ACCEPTED")],
                      deliveryQuery + [.init(name: "include_payload", value: "1")]] {
            await assertRejected(try request(state, path: subscription + "/deliveries", query: query), by: fence, wire: wire)
        }
        for query in [[URLQueryItem(name: "limit", value: "20"), .init(name: "result", value: "accepted")],
                      [.init(name: "limit", value: "20"), .init(name: "include_payload", value: "1")],
                      [.init(name: "limit", value: "20"), .init(name: "state", value: "SENT")]] {
            await assertRejected(try request(state, path: endpoint + "/logs", query: query), by: fence, wire: wire)
        }
    }

    func testExplicitApprovalDoesNotAuthorizeInventedMethodsRoutesOrMalformedIDs() async throws {
        let extras: Set<String> = ["api/im/webhook/subscriptions/01", "api/im/webhook/subscriptions/0",
            "api/im/webhook/subscriptions/9223372036854775808", "api/im/webhook/subscriptions/7/status",
            "api/im/webhook/subscriptions/7/receipt", "api/im/webhook/endpoints/7/test",
            "api/im/webhook/context/extra", "api/im/legacy/webhook/context",
            "api/im/webhook/subscriptions/./7", "api/im/webhook/subscriptions//7",
            "api/im/webhook/subscriptions/%37", "api/im/webhook/subscriptions/7#fragment"]
        let state = try state(paths: Self.allPaths.union(extras)), wire = Wire(), fence = try fence(state, wire: wire)
        for path in extras {
            await assertRejected(try request(state, path: path), by: fence, wire: wire, path)
        }
        for method in ["POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"] {
            await assertRejected(try request(state, method: method, query: contextQuery), by: fence, wire: wire, method)
        }
        var withBody = try request(state, query: contextQuery); withBody.httpBody = Data()
        await assertRejected(withBody, by: fence, wire: wire, "GET with even an empty body")
    }

    func testCookiesAlternateCredentialsExternalOriginsAndStreamsNeverForward() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        let original = try request(state, query: contextQuery)
        let edits: [(String, (inout URLRequest) -> Void)] = [
            ("automatic cookies", { $0.httpShouldHandleCookies = true }),
            ("cookie header", { $0.setValue("sid=synthetic", forHTTPHeaderField: "Cookie") }),
            ("empty cookie header", { $0.setValue("", forHTTPHeaderField: "Cookie") }),
            ("proxy authorization", { $0.setValue("synthetic", forHTTPHeaderField: "Proxy-Authorization") }),
            ("missing authorization", { $0.setValue(nil, forHTTPHeaderField: "Authorization") }),
            ("bearer rewrite", { $0.setValue("Bearer synthetic-final-forward-token", forHTTPHeaderField: "Authorization") }),
            ("different token", { $0.setValue("synthetic-other-token", forHTTPHeaderField: "Authorization") }),
            ("body stream", { $0.httpBodyStream = InputStream(data: Data("synthetic".utf8)) })
        ]
        for (label, edit) in edits {
            var changed = original; edit(&changed)
            await assertRejected(changed, by: fence, wire: wire, label)
        }
        for prefix in ["https://other.test:9443", "https://webhook-forward.test.attacker.test:9443",
                       "http://webhook-forward.test:9443", "https://synthetic-user@webhook-forward.test:9443",
                       "https://synthetic-user:synthetic-password@webhook-forward.test:9443"] {
            var changed = original
            changed.url = URL(string: prefix + "/native/v1/api/im/webhook/context?owner_id=" + Self.scope.ownerID.rawValue
                + "&channel_id=" + Self.scope.channelID.rawValue)
            await assertRejected(changed, by: fence, wire: wire, prefix)
        }
        var fragment = original; fragment.url = URL(string: original.url!.absoluteString + "#synthetic")
        await assertRejected(fragment, by: fence, wire: wire, "fragment")
        XCTAssertTrue(fence.isCurrent, "A malformed request alone does not retire an unchanged visit")
    }

    func testAllOriginalMutationMethodsAndCanonicalBodiesAreForwardedVerbatim() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        var originals: [URLRequest] = []
        for family in NativeWebhookFamily.allCases {
            let collection = family == .subscription ? Self.subscriptions : Self.endpoints
            let resource = collection + "/" + Self.resourceID
            originals.append(try request(state, path: collection, method: "POST", body: NativeWebhookHTTPService.encoded(change(family))))
            originals.append(try request(state, path: resource, method: "PUT", body: NativeWebhookHTTPService.encoded(change(family, revision: 4))))
            originals.append(try request(state, path: resource, method: "DELETE", body: action()))
            originals.append(try request(state, path: resource + (family == .subscription ? "/rotate-secret" : "/rotate-token"),
                method: "POST", body: action()))
        }
        originals.append(try request(state, path: Self.subscriptions + "/" + Self.resourceID + "/test", method: "POST",
            body: action(event: "channel.message.created")))
        originals.append(try request(state, path: Self.subscriptions + "/" + Self.resourceID + "/deliveries/" + Self.deliveryID + "/retry",
            method: "POST", body: action()))
        for original in originals {
            _ = try await fence.send(original)
            assertPreserved(original, try XCTUnwrap(wire.requests.last))
            let body = try XCTUnwrap(original.httpBody)
            XCTAssertTrue(String(decoding: body, as: UTF8.self).contains(Self.requestID.rawValue))
        }
        let createBody = String(decoding: try XCTUnwrap(originals.first?.httpBody), as: UTF8.self)
        XCTAssertTrue(createBody.contains("\"owner_id\":9007199254740995"))
        XCTAssertTrue(createBody.contains("\"channel_id\":9223372036854775807"))
        XCTAssertEqual(wire.requests.count, 10)
    }

    func testMutationBodyScopeRevisionAndCanonicalEncodingCannotChange() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        var invalid: [NativeWebhookChange] = []
        var wrongOwner = change(.subscription); wrongOwner.ownerID = 19; invalid.append(wrongOwner)
        var wrongChannel = change(.subscription); wrongChannel.channelID = 19; invalid.append(wrongChannel)
        var wrongType = change(.subscription); wrongType.ownerType = "USER"; invalid.append(wrongType)
        var absentOwner = change(.subscription); absentOwner.ownerID = nil; invalid.append(absentOwner)
        invalid.append(change(.subscription, revision: 4))
        for body in invalid {
            await assertRejected(try request(state, path: Self.subscriptions, method: "POST",
                body: NativeWebhookHTTPService.encoded(body)), by: fence, wire: wire)
        }
        for revision in [nil, 0, -1] as [Int?] {
            await assertRejected(try request(state, path: Self.subscriptions + "/" + Self.resourceID, method: "PUT",
                body: NativeWebhookHTTPService.encoded(change(.subscription, revision: revision))), by: fence, wire: wire)
        }
        let canonical = try NativeWebhookHTTPService.encoded(change(.subscription))
        let canonicalText = String(decoding: canonical, as: UTF8.self)
        let bodies: [Data?] = [nil, Data(), Data("{}".utf8), Data("[]".utf8), Data((" " + canonicalText).utf8),
            Data((String(canonicalText.dropLast()) + ",\"unexpected\":true}").utf8)]
        for body in bodies {
            await assertRejected(try request(state, path: Self.subscriptions, method: "POST", body: body), by: fence, wire: wire)
        }
        for contentType in [nil, "application/x-www-form-urlencoded", "application/json; charset=utf-8"] as [String?] {
            var changed = try request(state, path: Self.subscriptions, method: "POST", body: canonical)
            changed.setValue(contentType, forHTTPHeaderField: "Content-Type")
            await assertRejected(changed, by: fence, wire: wire)
        }
        await assertRejected(try request(state, path: Self.subscriptions, method: "POST", query: [.init(name: "limit", value: "1")],
            body: canonical), by: fence, wire: wire)
    }

    func testActionRouteVerbRevisionAndEventShapeRemainExact() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        let subscription = Self.subscriptions + "/" + Self.resourceID
        let endpoint = Self.endpoints + "/" + Self.resourceID
        for revision in [nil, 0, -1] as [Int?] {
            await assertRejected(try request(state, path: subscription + "/rotate-secret", method: "POST", body: action(revision: revision)), by: fence, wire: wire)
        }
        for (path, method) in [(subscription, "POST"), (subscription + "/rotate-secret", "DELETE"),
                               (endpoint + "/rotate-token", "PUT")] {
            await assertRejected(try request(state, path: path, method: method, body: action()), by: fence, wire: wire)
        }
        for (path, method) in [(subscription, "DELETE"), (endpoint, "DELETE"),
                               (subscription + "/rotate-secret", "POST"), (endpoint + "/rotate-token", "POST"),
                               (subscription + "/deliveries/" + Self.deliveryID + "/retry", "POST")] {
            await assertRejected(try request(state, path: path, method: method, body: action(event: "channel.message.created")), by: fence, wire: wire)
        }
        for event in [nil, ""] as [String?] {
            await assertRejected(try request(state, path: subscription + "/test", method: "POST", body: action(event: event)), by: fence, wire: wire)
        }
    }

    func testAnyObservedRuntimeChangePermanentlyRetiresTheCapturedTransport() async throws {
        let variants: [RuntimeDependencyContext?] = [nil, try context(account: 20), try context(epoch: 8),
            try context(token: "synthetic-replaced-token"), try context(namespace: "synthetic-other"),
            try context(role: "merchant"), try context(sessionRole: "merchant"), try context(market: .unitedStates),
            try context(base: "https://webhook-forward.test:9443/native/v2")]
        for current in variants {
            let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
            let original = try request(state, query: contextQuery)
            state.current = current
            await assertRejected(original, by: fence, wire: wire, "changed current")
            state.current = state.captured
            XCTAssertFalse(fence.isCurrent)
            await assertRejected(original, by: fence, wire: wire, "restored current cannot revive")
        }
    }

    func testMissingRemovedExpandedAndReplacedApprovalPermanentlyRetire() async throws {
        let captured = try context()
        let replacements: [OperationEndpointApproval?] = [nil, try grant(captured, paths: [Self.contextPath]),
            try grant(captured, paths: Self.allPaths.union(["api/im/webhook/subscriptions/77"])),
            try grant(captured, account: 20), try grant(captured, namespace: "synthetic-other"),
            try grant(captured, base: URL(string: "https://other.test/native/v1")!)]
        for replacement in replacements {
            let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
            let original = try request(state, query: contextQuery)
            state.approval = replacement
            await assertRejected(original, by: fence, wire: wire)
            state.approval = state.issued
            XCTAssertFalse(fence.isCurrent)
            await assertRejected(original, by: fence, wire: wire, "old grant cannot revive")
        }
    }

    /// Regression: replacing namespace bytes must retire even if String == remains true.
    func testCanonicallyEquivalentLiveApprovalReplacementPermanentlyRetires() async throws {
        let state = try state(context(namespace: "synthetic-e\u{301}")), wire = Wire(), fence = try fence(state, wire: wire)
        let original = try request(state, query: contextQuery)
        state.approval = try grant(state.captured, namespace: "synthetic-\u{e9}")
        await assertRejected(original, by: fence, wire: wire)
        state.approval = state.issued
        XCTAssertFalse(fence.isCurrent)
        await assertRejected(original, by: fence, wire: wire)
    }

    func testCanonicallyEquivalentRuntimeRoleAndApprovalPathBytesStillRetire() async throws {
        let captured = try context(role: "synthetic-e\u{301}")
        let roleState = try state(captured), roleWire = Wire(), roleFence = try fence(roleState, wire: roleWire)
        roleState.current = try context(role: "synthetic-\u{e9}")
        await assertRejected(try request(roleState, query: contextQuery), by: roleFence, wire: roleWire)
        roleState.current = captured; XCTAssertFalse(roleFence.isCurrent)

        let paths = Self.allPaths.union(["api/im/webhook/synthetic-e\u{301}"])
        let pathState = try state(paths: paths), pathWire = Wire(), pathFence = try fence(pathState, wire: pathWire)
        pathState.approval = try grant(pathState.captured, paths: Self.allPaths.union(["api/im/webhook/synthetic-\u{e9}"]))
        await assertRejected(try request(pathState, query: contextQuery), by: pathFence, wire: pathWire)
        pathState.approval = pathState.issued; XCTAssertFalse(pathFence.isCurrent)
    }

    func testPresentationRetirementCannotBeUndoneByRestoringTheBoolean() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        let original = try request(state, query: contextQuery)
        state.present = false
        XCTAssertFalse(fence.isCurrent)
        state.present = true
        XCTAssertFalse(fence.isCurrent)
        await assertRejected(original, by: fence, wire: wire)
    }

    func testSuspendedSuccessAndBare401AreDroppedAfterEveryFenceChanges() async throws {
        for status in [200, 401] {
            for reason in ["current", "approval", "presentation"] {
                let state = try state(), wire = PausedWire(), fence = try fence(state, wire: wire)
                let original = try request(state, query: contextQuery)
                let task = Task { @MainActor in try await fence.send(original) }
                await fulfillment(of: [wire.started], timeout: 2)
                switch reason {
                case "current": state.current = nil
                case "approval": state.approval = nil
                default: state.present = false
                }
                wire.finish((Data(), status))
                do { _ = try await task.value; XCTFail("Late response escaped for \(reason), HTTP \(status)") }
                catch { XCTAssertEqual(error as? NativeWebhookClientError, .scopeChanged) }
                XCTAssertEqual(wire.requests.count, 1); assertPreserved(original, wire.requests[0])
                state.current = state.captured; state.approval = state.issued; state.present = true
                XCTAssertFalse(fence.isCurrent, "Completing a late response must not revive the transport")
            }
        }
    }

    func testCancellationBeforeDispatchLeavesUnderlyingUntouched() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        let original = try request(state, query: contextQuery)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fence.send(original)
        }
        do { _ = try await task.value; XCTFail("Cancelled request dispatched") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testCancellationWhileSuspendedDropsEvenBare401() async throws {
        let state = try state(), wire = PausedWire(), fence = try fence(state, wire: wire)
        let original = try request(state, query: contextQuery)
        let task = Task { @MainActor in try await fence.send(original) }
        await fulfillment(of: [wire.started], timeout: 2)
        task.cancel(); wire.finish((Data(), 401))
        do { _ = try await task.value; XCTFail("Cancelled late 401 escaped") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(wire.requests.count, 1)
    }

    func testCurrentBare401StillPassesThroughWithoutInventingAResponse() async throws {
        let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
        wire.respond = { _ in (Data(), 401) }
        let result = try await fence.send(request(state, query: contextQuery))
        XCTAssertTrue(result.0.isEmpty); XCTAssertEqual(result.1, 401); XCTAssertTrue(fence.isCurrent)
    }

    func testProviderExpirationDoesNotReceiveLate401ButDoesReceiveCurrent401() async throws {
        for retire in [false, true] {
            let state = try state(), wire = Wire(), fence = try fence(state, wire: wire)
            let binding = try binding(state), context = NativeWebhookContext(binding: binding,
                eventCatalogue: .available(revision: "synthetic-events-1", options: []))
            var expirations = 0
            let provider = provider(state, context: context, onUnauthorized: { expirations += 1 })
            let service = NativeWebhookHTTPService(provider: provider, authorizer: provider, transport: fence)
            wire.respond = { _ in if retire { state.present = false }; return (Data(), 401) }
            do { _ = try await service.resources(.subscription, context: context); XCTFail("Bare 401 succeeded") }
            catch { XCTAssertTrue(error is NativeWebhookClientError) }
            XCTAssertEqual(expirations, retire ? 0 : 1)
            XCTAssertEqual(wire.requests.count, 1)
        }
    }

    func testRetiredMutationKeepsTheExactOriginalPendingRequestAndNeverReplays() async throws {
        for status in [200, 401] {
            let state = try state(), wire = Wire(), fence = try fence(state, wire: wire), storage = Journal()
            let context = NativeWebhookContext(binding: try binding(state), eventCatalogue: .available(
                revision: "synthetic-events-1", options: [.init(id: "channel.message.created", title: "Synthetic event")]))
            var expirations = 0
            let provider = provider(state, context: context, onUnauthorized: { expirations += 1 })
            let service = NativeWebhookHTTPService(provider: provider, authorizer: provider, transport: fence)
            let flow = NativeWebhookCoordinator(service: service, provider: provider, journal: .init(journal: storage))
            XCTAssertTrue(flow.bindRuntimeRetirement({ state.present = false }, presentationIsCurrent: { fence.isCurrent }))
            wire.respond = { _ in (Self.resourcePage(), 200) }
            await flow.load(); XCTAssertEqual(flow.resources.count, 1)
            flow.prepareAction(.rotate, resource: try XCTUnwrap(flow.resources.first))
            let confirmation = try XCTUnwrap(flow.confirmation)
            var reserved: OperationPendingRecord?
            wire.respond = { request in
                XCTAssertEqual(request.httpMethod, "POST")
                reserved = storage.record
                state.present = false
                return (status == 401 ? Data() : Data(#"{"code":200,"data":{"secret":"synthetic-never-display"}}"#.utf8), status)
            }
            await flow.confirm(confirmation.id)
            let pending = try XCTUnwrap(storage.record?.nativeWebhook)
            let original = try pending.originalRequest()
            let sent = try XCTUnwrap(wire.requests.last)
            XCTAssertNotNil(reserved); XCTAssertEqual(storage.record, reserved)
            XCTAssertEqual(pending.requestID, confirmation.requestID)
            XCTAssertEqual(original.requestID, confirmation.requestID)
            XCTAssertEqual(original.method.rawValue, sent.httpMethod)
            XCTAssertEqual(original.path, NativeWebhookRuntimeRoute.rotate(.subscription, id: NativeWebhookID(rawValue: Self.resourceID)!))
            XCTAssertEqual(original.body, sent.httpBody)
            XCTAssertEqual(pending.bodySHA256, NativeWebhookPendingMetadata.digest(try XCTUnwrap(sent.httpBody)))
            XCTAssertEqual(storage.clearCount, 0); XCTAssertEqual(storage.writeCount, 1)
            XCTAssertEqual(expirations, 0); XCTAssertNil(flow.credential); XCTAssertNil(flow.notice)
            XCTAssertEqual(wire.requests.filter { $0.httpMethod != "GET" }.count, 1)
            XCTAssertEqual(wire.requests.count, 2, "No receipt read, automatic retry, or replay after retirement")
            state.present = true
            await flow.load(); flow.prepareRecovery(); await flow.confirm(confirmation.id)
            XCTAssertEqual(wire.requests.count, 2)
            XCTAssertEqual(storage.record, reserved)
        }
    }

    private func binding(_ state: State) throws -> NativeWebhookBinding {
        try NativeWebhookBinding(accountID: String(state.captured.session.accountID), market: state.captured.market.rawValue,
            namespace: state.captured.session.namespace, origin: state.captured.baseURL, scope: Self.scope,
            authorizationVersion: "synthetic-permission-version-7")
    }
    private func provider(_ state: State, context: NativeWebhookContext,
                          onUnauthorized: @escaping () -> Void) -> NativeWebhookRuntimeScopeProvider {
        NativeWebhookRuntimeScopeProvider(captured: state.captured, scope: Self.scope, current: { state.current },
            lookup: { context }, endpointApproval: { state.approval }, onUnauthorized: { _ in onUnauthorized() })
    }
    private static func resourcePage() -> Data {
        let resource = "{\"id\":\"\(resourceID)\",\"channel_id\":\"\(scope.channelID.rawValue)\",\"owner_type\":\"CLUB\","
            + "\"owner_id\":\"\(scope.ownerID.rawValue)\",\"name\":\"Synthetic integration\",\"status\":1,\"deleted\":false,"
            + "\"revision\":4,\"key_version\":2,\"events\":[\"channel.message.created\"]}"
        return Data(("{\"code\":200,\"data\":{\"list\":[" + resource + "],\"has_more\":false,\"next_cursor\":null}}").utf8)
    }

    @MainActor private final class State {
        let captured: RuntimeDependencyContext
        let issued: OperationEndpointApproval
        var current: RuntimeDependencyContext?
        var approval: OperationEndpointApproval?
        var present = true
        init(captured: RuntimeDependencyContext, issued: OperationEndpointApproval) {
            self.captured = captured; self.issued = issued; current = captured; approval = issued
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var respond: (URLRequest) async throws -> (Data, Int) = { _ in (Data("synthetic-response".utf8), 200) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); return try await respond(request)
        }
    }
    @MainActor private final class PausedWire: HTTPTransport {
        var requests: [URLRequest] = []
        let started = XCTestExpectation(description: "Synthetic underlying transport reached")
        private var result: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return try await withCheckedThrowingContinuation { continuation in
                result = continuation
                started.fulfill()
            }
        }
        func finish(_ value: (Data, Int)) {
            let pending = result; result = nil; pending?.resume(returning: value)
        }
    }
    @MainActor private final class Journal: OperationPendingJournal {
        var record: OperationPendingRecord?
        var writeCount = 0, clearCount = 0
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            guard let record, record.ownerKey == ownerKey, record.targetKey == targetKey else { return nil }
            return record
        }
        func write(_ value: OperationPendingRecord) throws { record = value; writeCount += 1 }
        func clear(_ value: OperationPendingRecord) throws {
            guard record == value else { throw APIError.invalidRequest }
            record = nil; clearCount += 1
        }
    }
}
