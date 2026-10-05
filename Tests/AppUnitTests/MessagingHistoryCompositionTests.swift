import XCTest
@testable import Questify

/// Normal AppSession factory -> exact outer HTTP fence; synthetic requests only.
@MainActor final class MessagingHistoryCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func root(_ wire: Wire, _ grants: Grants, _ vault: Vault, sendEnabled: @escaping @MainActor () -> Bool = { false }) throws -> AppCompositionRoot {
        let suite = "im-history-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.im-history", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, sessionDependencies: { context in
                guard sendEnabled(), let configuration = try? BusinessRuntimeConfiguration(market: context.market,
                    baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID,
                    routes: [.imSend: [try .post("api/im/send")]]) else { return .dormant }
                return .init(businessConfiguration: configuration)
            }, messagingHistoryReadApproval: { grants.select($0) })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    func testNormalFactoryHistoryKeepsSenderPrivacyAndBlockedHistoryWithoutWrites() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession(); await login(session); wire.requests = []
        let reader = session.messagingReader
        XCTAssertNil(session.messageSender(for: 901)); XCTAssertFalse(session.imExpandedWriter.isConfigured)
        let conversations = try await reader.messagingConversations()
        XCTAssertEqual(conversations.map(\.id), [901])
        let page = try await reader.messagingMessages(conversationID: 901)
        XCTAssertEqual(page.messages.map(\.id), [12]); XCTAssertEqual(page.messages.first?.senderID, 8)
        XCTAssertEqual(page.messages.first?.senderName, "Other member")
        XCTAssertEqual(wire.requests.compactMap { MessagingHistoryReadRoute(request: $0, baseURL: base) }, [.conversations, .messages(conversationID: 901, cursor: 0, size: 30)])
        // The server deliberately permits existing history while blocked. No writer,
        // media fetch or read receipt is needed to consume the returned history.
        XCTAssertEqual(wire.requests.count, 2)
    }
    func testCachedLegacySenderIsWithheldWhenIndependentCapabilityIsRemoved() async throws {
        let wire = Wire(), grants = Grants(); var enabled = true
        let session = try root(wire, grants, Vault(), sendEnabled: { enabled }).makeSession(); await login(session)
        let cached = try XCTUnwrap(session.messageSender(for: 901))
        XCTAssertTrue(session.messageSender(for: 901) === cached)
        // Existing dependency configurations are session/context bound; rebuild on
        // role transition with the independent feature removed. No send is performed.
        enabled = false; wire.role = "merchant"; await session.refreshOwnAccount()
        XCTAssertNil(session.messageSender(for: 901))
        wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertNil(session.messageSender(for: 901))
        XCTAssertFalse(wire.requests.contains { $0.url?.path.hasSuffix("/send") == true })
    }
    func testDefaultNilGuestAndInnerServiceCannotBypassOuterFence() async throws {
        let wire = Wire(), grants = Grants(); grants.enabled = false
        let composition = try root(wire, grants, Vault()), session = composition.makeSession()
        XCTAssertFalse(session.messagingReader.isConfigured); XCTAssertTrue(wire.requests.isEmpty)
        await login(session); wire.requests = []
        XCTAssertFalse(session.messagingReader.isConfigured)
        do { _ = try await session.messagingReader.messagingConversations(); XCTFail() } catch {}
        let fence = composition.transport(); fence.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        let service = MessagingService(configuration: try APIConfiguration(baseURL: base), transport: fence)
        do { _ = try await service.conversations(token: "synthetic-7"); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testLoadedReaderInvalidatesOnRevocationExpiryRoleABAAndReissue() async throws {
        for transition in ["revoke", "expire", "roleABA", "reissue"] {
            let wire = Wire(), grants = Grants(), session = try root(wire, grants, Vault()).makeSession(); await login(session)
            let reader = session.messagingReader, key = session.messagingViewIdentity
            _ = try await reader.messagingConversations(); XCTAssertNotNil(reader.identity)
            let lease = try XCTUnwrap(grants.retained)
            switch transition {
            case "revoke": lease.revoke(); grants.enabled = false
            case "expire": lease.expireIfNeeded(now: lease.expiresAt)
            case "roleABA": wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
            default: grants.retained = try .init(context: lease.context, expiresAt: Date().addingTimeInterval(600))
            }
            XCTAssertNil(reader.identity); XCTAssertFalse(reader.isConfigured); XCTAssertNotEqual(key, session.messagingViewIdentity)
            grants.enabled = true; grants.retained = nil
            let fresh = session.messagingReader; XCTAssertTrue(fresh.isConfigured)
            XCTAssertNil(reader.identity); XCTAssertFalse(reader.isConfigured)
            let count = wire.requests.count
            do { _ = try await reader.messagingConversations(); XCTFail() } catch {}
            XCTAssertEqual(wire.requests.count, count)
            _ = try await fresh.messagingConversations()
        }
    }
    func testPendingSuccess401AndTransportErrorCannotOutliveExactIssuance() async throws {
        for transition in ["owner", "roleABA", "sessionABA", "revoke", "reissue", "expire", "cancel"] {
            for code in [200, 401, -1] {
                let wire = Wire(), grants = Grants(), vault = Vault(), session = try root(wire, grants, vault).makeSession(); await login(session)
                let reader = session.messagingReader, paused = expectation(description: "history suspended")
                wire.pause = true; wire.onPaused = { paused.fulfill() }
                let task = Task { try await reader.messagingMessages(conversationID: 901) }
                await fulfillment(of: [paused], timeout: 2)
                switch transition {
                case "owner": await session.logout(); wire.account = 8; await login(session)
                case "roleABA": wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
                case "sessionABA": await session.logout(); await login(session)
                case "revoke": grants.retained?.revoke(); grants.enabled = false
                case "reissue": let lease = try XCTUnwrap(grants.retained); grants.retained = try .init(context: lease.context, expiresAt: Date().addingTimeInterval(600))
                case "expire": let lease = try XCTUnwrap(grants.retained); lease.expireIfNeeded(now: lease.expiresAt)
                default: task.cancel()
                }
                wire.finish(code: code)
                do { _ = try await task.value; XCTFail(transition) } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
                XCTAssertEqual(session.account?.id, wire.account); XCTAssertEqual(vault.value, "synthetic-\(wire.account)")
            }
        }
    }
    func testCurrent401ExpiresButMembership403AndClosedHistoryDoNotExpireAccount() async throws {
        for code in [401, 403, 409] {
            let wire = Wire(), vault = Vault(), session = try root(wire, Grants(), vault).makeSession(); await login(session)
            wire.code = code
            do { _ = try await session.messagingReader.messagingMessages(conversationID: 901); XCTFail() }
            catch { if code != 401 { XCTAssertTrue(MessagingLoadIssue(error).isTerminal) } }
            XCTAssertEqual(session.account?.id, code == 401 ? nil : 7)
            XCTAssertEqual(vault.value, code == 401 ? nil : "synthetic-7")
        }
    }
    func testCanonicalClonesAllAdjacentMutationsAndCrossScopeStayClosed() async throws {
        let wire = Wire(), grants = Grants(), fence = try root(wire, grants, Vault()).transport()
        fence.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
        let clone = fence.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
        _ = try await clone.send(form("conversations")); _ = try await clone.send(form("messages", ["conversation_id": "901", "cursor_id": "42", "size": "30"]))
        let before = wire.requests.count
        var invalid = [URLRequest]()
        for path in ["read", "send", "start", "mute", "delete", "block", "unblock", "report", "unread-total"] { invalid.append(try form(path)) }
        for url in ["https://evil.test/native/api/im/conversations", "https://example.test/other/api/im/conversations", "https://example.test/native/api/im/conversations?x=1", "https://example.test/native/api/im/conversations#x", "https://example.test/native/api/im/%63onversations", "https://example.test/native/api/im/../im/conversations"] {
            var request = try form("conversations"); request.url = URL(string: url); invalid.append(request)
        }
        var request = try form("conversations"); request.httpMethod = "GET"; invalid.append(request)
        request = try form("conversations"); request.setValue("other-token", forHTTPHeaderField: "Authorization"); invalid.append(request)
        invalid.append(try form("conversations", ["member_id": "7"]))
        for request in invalid { do { _ = try await clone.send(request); XCTFail("Unexpected dispatch") } catch {} }
        for identity in [CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 8, role: "player", token: "synthetic-7"), .init(epoch: 2, accountID: 7, role: "player", token: "synthetic-7"), .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7"), .init(epoch: 1, accountID: nil, role: nil, token: nil)] {
            grants.freeze = true; fence.current = { identity }
            do { _ = try await clone.send(form("conversations")); XCTFail() } catch {}
        }
        XCTAssertEqual(wire.requests.count, before)
    }
    func testClonedPendingReadRejectsLeaseAndTokenRotation() async throws {
        for transition in ["revoke", "replace", "expiry", "token", "roleABA"] {
            for code in [200, 401, -1] {
                let wire = Wire(), grants = Grants(), fence = try root(wire, grants, Vault()).transport()
                fence.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
                let clone = fence.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
                wire.pause = true; let paused = expectation(description: "clone suspended"); wire.onPaused = { paused.fulfill() }
                let task = Task { try await clone.send(form("conversations")) }; await fulfillment(of: [paused], timeout: 2)
                let lease = try XCTUnwrap(grants.retained)
                switch transition {
                case "revoke": lease.revoke()
                case "replace": grants.retained = try .init(context: lease.context, expiresAt: Date().addingTimeInterval(600))
                case "expiry": lease.expireIfNeeded(now: lease.expiresAt)
                case "token": fence.current = { .init(epoch: 1, accountID: 7, role: "player", token: "rotated", viewerRevision: 1) }
                default: fence.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 3) }
                }
                wire.finish(code: code)
                do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            }
        }
    }
    private func form(_ path: String, _ fields: [String: String] = [:]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/im/" + path), fields: fields, token: "synthetic-7", boundary: "BOUNDARY")
    }
    @MainActor private final class Grants {
        var enabled = true, freeze = false; var retained: MessagingHistoryReadApproval?
        func select(_ context: RuntimeDependencyContext) -> MessagingHistoryReadApproval? {
            guard enabled else { return nil }
            if !freeze, retained == nil || !ContentDraftContextFence.matches(retained?.context, context) {
                retained?.revoke(); retained = try? .init(context: context, expiresAt: Date().addingTimeInterval(600))
            }
            return retained
        }
    }
    private final class Vault: AppTokenStorage { var value: String?; func read() throws -> String? { value }; func write(_ token: String) throws { value = token }; func clear() throws { value = nil } }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], account = 7, role = "player", code = 200, pause = false, onPaused: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?, pendingJSON = "{}"
        func finish(code: Int) { let saved = pending; pending = nil; if code == -1 { saved?.resume(throwing: APIError.httpStatus(503)); return }; saved?.resume(returning: (Data((code == 200 ? pendingJSON : "{\"code\":\(code)}").utf8), 200)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.path, json: String
            if path.hasSuffix("/phone") { json = "{\"code\":200,\"token\":\"synthetic-\(account)\",\"data\":{\"id\":\(account),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/userInfo") { json = "{\"code\":200,\"appUser\":{\"userId\":\(account),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/conversations") { json = "{\"code\":\(code),\"data\":[{\"conversationId\":901,\"type\":1,\"unread\":3}]}" }
            else if path.hasSuffix("/messages") { json = "{\"code\":\(code),\"errorCode\":\"HANGOUT_CLOSED\",\"data\":{\"list\":[{\"id\":12,\"conversationId\":901,\"senderId\":8,\"senderName\":\"Other member\",\"status\":0,\"msgType\":1,\"content\":\"Synthetic history\"}],\"nextCursor\":12,\"hasMore\":false,\"blocked\":true,\"blockedByMe\":true}}" }
            else { json = "{\"code\":200}" }
            if path.contains("/im/"), pause { pendingJSON = json; return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
            return (Data(json.utf8), 200)
        }
    }
}
