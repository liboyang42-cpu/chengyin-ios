import XCTest
@testable import Questify

/// Exercises real service construction and composition admission with synthetic HTTP only.
@MainActor final class TemplateMetadataReadCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private typealias Identity = CompositionHTTPTransport.SessionIdentity
    private var guest: Identity { .init(epoch: 0, accountID: nil, role: nil, token: nil) }
    private var member: Identity { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
    private func deployment(reads: Set<ReviewedAppDeployment.ReadGrant> = [.homeAndSearch],
                            auth: Bool = false, configured: Bool = true) throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: configured ? base.absoluteString : "", approvedBaseURLs: [.china: [base.absoluteString]],
            verifiedCapabilities: auth ? [.domesticChinaPhone] : [],
            bundleIdentifier: "test.template-metadata", realm: "synthetic", reads: reads)
    }
    private func session(_ wire: Wire, reads: Set<ReviewedAppDeployment.ReadGrant> = [.homeAndSearch],
                         configured: Bool = true) throws -> (AppSession, Vault) {
        let suite = "template-metadata-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault()
        let root = AppCompositionRoot(deployment: configured ? .reviewed(try deployment(reads: reads, auth: true)) : .unconfigured,
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
        return (root.makeSession(), vault)
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    private func request(value: String = "app_template_players", token: String? = nil) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/common/dict"),
            fields: ["dictType": value], token: token, boundary: "metadata-test")
    }
    private func blocked(_ request: URLRequest, transport: CompositionHTTPTransport, wire: Wire,
                         file: StaticString = #filePath, line: UInt = #line) async {
        let before = wire.requests.count
        do { _ = try await transport.send(request); XCTFail("Unapproved metadata request dispatched", file: file, line: line) }
        catch { XCTAssertTrue(error is CancellationError || error as? APIError == .notConfigured, file: file, line: line) }
        XCTAssertEqual(wire.requests.count, before, file: file, line: line)
    }

    func testNormalGuestSessionDispatchesExactlyBothDictionariesAndTypeFourCategories() async throws {
        let wire = Wire(); let (session, vault) = try session(wire)
        await session.bootstrap()
        let players = try await session.templateMetadataDictionary(kind: .players)
        let duration = try await session.templateMetadataDictionary(kind: .duration)
        let categories = try await session.discoveryCategories(type: 4)
        XCTAssertEqual(players.map(\.value), [" 6+ ", "60", " 6+ "])
        XCTAssertEqual(players.map(\.label), [" Group ", "One hour", "Alternate"])
        XCTAssertEqual(duration, players); XCTAssertEqual(categories.map(\.id), [4])
        XCTAssertEqual(wire.requests.count, 3)
        XCTAssertEqual(wire.requests.prefix(2).compactMap { TemplateMetadataReadRoute(request: $0, baseURL: base)?.kind }, [.players, .duration])
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "Authorization") == nil })
        let category = try XCTUnwrap(wire.requests.last)
        XCTAssertEqual(category.url?.path, "/native/api/category/list")
        let type = try XCTUnwrap(category.value(forHTTPHeaderField: "Content-Type"))
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        let expected = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/category/list"),
            fields: ["parentid": "0", "type": "4"], token: nil, boundary: boundary)
        XCTAssertEqual(category.httpBody, expected.httpBody)
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
    }
    func testCurrentSignedInTokenAndEmptyMetadataDoNotChangeDraftOrEnableWriter() async throws {
        let wire = Wire(); let (session, vault) = try session(wire)
        await login(session)
        let editor = session.templateAuthoringEditor()
        var draft = TemplateAuthoringDraft(title: "Keep local draft")
        draft.players = " legacy "; draft.duration = 37
        editor.change(draft)
        let before = editor.draft
        wire.json = #"{"code":"200","data":[]}"#
        wire.requests = []
        for kind in TemplateMetadataKind.allCases {
            let result = try await session.templateMetadataDictionary(kind: kind)
            XCTAssertTrue(result.isEmpty)
        }
        XCTAssertEqual(wire.requests.count, 2)
        XCTAssertTrue(wire.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "synthetic-7" })
        XCTAssertEqual(editor.draft, before)
        XCTAssertFalse(editor.canSubmit); XCTAssertFalse(editor.canRead)
        XCTAssertEqual(vault.value, "synthetic-7")
    }
    func testUnconfiguredInactiveAndUnrelatedGrantsRejectBeforeUnderlyingDispatch() async throws {
        let grantSets: [Set<ReviewedAppDeployment.ReadGrant>] = [[], [.manualMap], [.publicTopicTemplateCatalogAndDetail], [.playNodesAndRouteState]]
        for grants in grantSets {
            let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(reads: grants), underlying: wire)
            transport.current = { self.guest }
            await blocked(try request(), transport: transport, wire: wire)
        }
        let wire = Wire()
        XCTAssertThrowsError(try deployment(configured: false)) { error in
            XCTAssertEqual(error as? APIError, .invalidConfiguration)
        }
        let transport = CompositionHTTPTransport(deployment: nil, underlying: wire)
        transport.current = { self.guest }
        await blocked(try request(), transport: transport, wire: wire)
        let (unconfigured, _) = try session(wire, configured: false)
        do { _ = try await unconfigured.templateMetadataDictionary(kind: .players); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
        XCTAssertNil(RegionalLaunchConfiguration.composition.reviewed)
    }
    func testOnlyCanonicalDictionaryNamesAreAdmitted() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { self.guest }
        for value in ["app_template_difficulty", "anything", "", "APP_TEMPLATE_PLAYERS", " app_template_players",
                      "app_template_players ", "app_template_player", "app_template_players_extra", "app_template_duration\n"] {
            await blocked(try request(value: value), transport: transport, wire: wire)
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testWrongVerbsMissingBodiesStreamsAndNoncanonicalHeadersNeverDispatch() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { self.guest }
        let original = try request()
        for method in ["GET", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"] {
            var altered = original; altered.httpMethod = method
            await blocked(altered, transport: transport, wire: wire)
        }
        var altered = original; altered.httpBody = nil
        await blocked(altered, transport: transport, wire: wire)
        altered = original; altered.httpBody = Data()
        await blocked(altered, transport: transport, wire: wire)
        altered = original; altered.httpBodyStream = InputStream(data: Data("stream".utf8))
        await blocked(altered, transport: transport, wire: wire)
        let accepts: [String?] = [nil, "*/*", "Application/JSON", "application/json, text/plain"]
        for accept in accepts {
            altered = original; altered.setValue(accept, forHTTPHeaderField: "Accept")
            await blocked(altered, transport: transport, wire: wire)
        }
        let types: [String?] = [nil, "application/json", "application/x-www-form-urlencoded",
            "multipart/form-data; boundary=wrong", "multipart/form-data; boundary=", "multipart/form-data; boundary=metadata_test",
            "multipart/form-data; boundary=\"metadata-test\"", "multipart/form-data; boundary=metadata-test; charset=utf-8",
            "multipart/form-data; boundary=" + String(repeating: "x", count: 71), "multipart/form-data; boundary=非ASCII"]
        for type in types {
            altered = original; altered.setValue(type, forHTTPHeaderField: "Content-Type")
            await blocked(altered, transport: transport, wire: wire)
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExtraDuplicateFilePartsFramingAndMixedEncodingsNeverDispatch() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { self.guest }
        let original = try request(), canonical = try XCTUnwrap(String(data: try XCTUnwrap(original.httpBody), encoding: .utf8))
        let extra = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/common/dict"),
            fields: ["dictType": "app_template_players", "extra": "1"], token: nil, boundary: "metadata-test")
        await blocked(extra, transport: transport, wire: wire)
        let duplicate = "--metadata-test\r\nContent-Disposition: form-data; name=\"dictType\"\r\n\r\napp_template_players\r\n"
        let maliciousBodies = [
            duplicate + canonical,
            duplicate.replacingOccurrences(of: "app_template_players", with: "app_template_duration") + canonical,
            canonical.replacingOccurrences(of: "name=\"dictType\"", with: "name=\"dictType\"; filename=\"option.txt\""),
            canonical.replacingOccurrences(of: "\r\n\r\n", with: "\r\nContent-Type: text/plain\r\n\r\n"),
            canonical.replacingOccurrences(of: "\r\n", with: "\n"),
            canonical.replacingOccurrences(of: "--metadata-test", with: "--other-boundary"),
            canonical + "trailing content", "prefix" + canonical,
            canonical.replacingOccurrences(of: "app_template_players", with: "app%5Ftemplate%5Fplayers"),
            "{\"dictType\":\"app_template_players\"}", "dictType=app_template_players"]
        for body in maliciousBodies {
            var altered = original; altered.httpBody = Data(body.utf8)
            await blocked(altered, transport: transport, wire: wire)
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testOriginPortPathEncodingQueryFragmentAndUnrelatedRoutesNeverDispatch() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { self.guest }
        let original = try request(), exact = try XCTUnwrap(original.url?.absoluteString)
        let aliases = [exact + "/", exact + "/extra", exact + "?", exact + "?dictType=app_template_players", exact + "#fragment",
            exact.replacingOccurrences(of: "https:", with: "http:"), exact.replacingOccurrences(of: "example.test", with: "other.test"),
            exact.replacingOccurrences(of: "example.test", with: "example.test:443"), exact.replacingOccurrences(of: "example.test", with: "example.test:8443"),
            exact.replacingOccurrences(of: "example.test", with: "user@example.test"), exact.replacingOccurrences(of: "/native/", with: "/other/"),
            exact.replacingOccurrences(of: "/api/common/", with: "/api//common/"), exact.replacingOccurrences(of: "/dict", with: "/%64ict")]
        for value in aliases {
            var altered = original; altered.url = try XCTUnwrap(URL(string: value))
            await blocked(altered, transport: transport, wire: wire)
        }
        for path in ["api/common/upload", "api/common/other", "api/template/draft", "api/template/publish", "api/template/delete",
                     "api/template/updateLibraryStatus", "api/template/myinfo", "api/template/my-list"] {
            var altered = original; altered.url = base.appendingPathComponent(path)
            await blocked(altered, transport: transport, wire: wire)
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testHomeGrantDoesNotAdmitCanonicalOwnedTemplateReads() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { self.member }
        let detail = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/template/myinfo"),
            fields: ["id": "41"], token: member.token, boundary: "owned-detail-test")
        await blocked(detail, transport: transport, wire: wire)
        let shelf = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/template/my-list"),
            fields: ["is_quote": "", "keyword": "", "category_id": "", "pageNum": "1", "pageSize": "10"],
            token: member.token, boundary: "owned-list-test")
        await blocked(shelf, transport: transport, wire: wire)
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testMismatchedCredentialsMissingIdentityAndPartialIdentitiesNeverDispatch() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { self.member }
        await blocked(try request(), transport: transport, wire: wire)
        await blocked(try request(token: "old-token"), transport: transport, wire: wire)
        transport.current = { self.guest }
        await blocked(try request(token: "synthetic-7"), transport: transport, wire: wire)
        transport.current = { nil }
        await blocked(try request(), transport: transport, wire: wire)
        let partials = [Identity(epoch: 1, accountID: nil, role: nil, token: "synthetic-7"),
                        Identity(epoch: 1, accountID: nil, role: "merchant", token: nil),
                        Identity(epoch: 1, accountID: 7, role: "player", token: nil),
                        Identity(epoch: 1, accountID: 7, role: nil, token: "synthetic-7"),
                        Identity(epoch: 1, accountID: 0, role: "player", token: "synthetic-7")]
        for partial in partials {
            transport.current = { partial }
            await blocked(try request(token: partial.token), transport: transport, wire: wire)
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testCancellationAndIdentityChangeBeforeForwardCauseZeroDispatch() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { self.guest }
        let request = try request()
        let cancelled = Task { try await transport.send(request) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
        var checks = 0
        transport.current = { checks += 1; return checks == 1 ? self.guest : self.member }
        await blocked(request, transport: transport, wire: wire)
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testEveryIdentityChangeAndCancellationFenceLateSuccess401AndThrownFailure() async throws {
        let original = member
        let changes: [Identity?] = [nil, guest,
            .init(epoch: 2, accountID: 7, role: "player", token: "synthetic-7"),
            .init(epoch: 1, accountID: 8, role: "player", token: "synthetic-7"),
            .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7"),
            .init(epoch: 1, accountID: 7, role: "player", token: "new-token"),
            .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 2)]
        for changed in changes {
            for outcome in [200, 401, -1] {
                let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
                var identity: Identity? = original
                transport.current = { identity }
                let paused = expectation(description: "Metadata transport paused")
                wire.pauseNext = true; wire.onPaused = { paused.fulfill() }
                let request = try request(token: original.token)
                let pending = Task { try await transport.send(request) }
                await fulfillment(of: [paused], timeout: 2)
                identity = changed
                wire.resume(outcome: outcome)
                do { _ = try await pending.value; XCTFail("Late metadata crossed identity") }
                catch is CancellationError {} catch { XCTFail("\(error)") }
                XCTAssertEqual(wire.requests.count, 1)
            }
        }
        for outcome in [200, 401, -1] {
            let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
            transport.current = { original }
            let paused = expectation(description: "Cancelled metadata transport")
            wire.pauseNext = true; wire.onPaused = { paused.fulfill() }
            let request = try request(token: original.token)
            let pending = Task { try await transport.send(request) }
            await fulfillment(of: [paused], timeout: 2)
            pending.cancel(); wire.resume(outcome: outcome)
            do { _ = try await pending.value; XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
            XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testSessionRoleABARejectsLateMetadataWithoutExpiringReplacementAndFreshReadWorks() async throws {
        for outcome in [200, 401, -1] {
            let wire = Wire(); let (session, vault) = try session(wire)
            await login(session)
            let paused = expectation(description: "Session metadata paused")
            wire.pauseNext = true; wire.onPaused = { paused.fulfill() }
            let pending = Task { try await session.templateMetadataDictionary(kind: .players) }
            await fulfillment(of: [paused], timeout: 2)
            wire.role = "merchant"; await session.refreshOwnAccount()
            wire.role = "player"; await session.refreshOwnAccount()
            wire.resume(outcome: outcome)
            do { _ = try await pending.value; XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
            XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7"); XCTAssertNil(session.errorKey)
            let fresh = try await session.templateMetadataDictionary(kind: .duration)
            XCTAssertEqual(fresh.count, 3)
        }
    }
    func testCapturedSelectorRequestsRejectRoleABAAndCurrentUnauthorizedStillExpires() async throws {
        let wire = Wire(); let (session, vault) = try session(wire)
        await login(session)
        let captured = session.templateMetadataDictionaryRequest(kind: .players)
        wire.role = "merchant"; await session.refreshOwnAccount()
        wire.role = "player"; await session.refreshOwnAccount()
        let before = wire.requests.count
        do { _ = try await captured.read(); XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
        captured.onUnauthorized()
        XCTAssertEqual(wire.requests.count, before); XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
        wire.json = #"{"code":"401","data":null}"#
        do { _ = try await session.templateMetadataDictionary(kind: .duration); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        XCTAssertEqual(session.errorKey, "auth.expired")
    }

    func testRealSessionSelectorCloseDiscardAndNewerSheetFenceCategoryAndDictionary401() async throws {
        for field in [TemplateMetadataField.players, .duration, .categories] {
            for action in ["close", "discard", "newer"] {
                let wire = Wire(); let (session, vault) = try session(wire)
                await login(session)
                let model = TemplateAuthoringModel(coordinator: session.templateAuthoringEditor()); model.load()
                model.draft.title = "Retained local draft"; model.changed()
                let old = TemplateAuthoringMetadataEditor(model: model, reader: session, field: field)
                let started = expectation(description: "Real selector request started")
                wire.pauseNext = true; wire.onPaused = { started.fulfill() }
                let pending = Task { await old.load() }
                await fulfillment(of: [started], timeout: 2)
                var newer: TemplateAuthoringMetadataEditor?
                switch action {
                case "discard": model.discard()
                case "newer":
                    old.close()
                    let replacement = TemplateAuthoringMetadataEditor(model: model, reader: session, field: field)
                    await replacement.load(); XCTAssertEqual(replacement.state, .loaded)
                    newer = replacement
                default: old.close()
                }
                let before = model.draft
                wire.resume(outcome: 401); await pending.value
                XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
                XCTAssertNil(session.errorKey); XCTAssertEqual(model.draft, before)
                XCTAssertTrue(old.visibleOptions.isEmpty); XCTAssertTrue(old.visibleCategories.isEmpty)
                XCTAssertFalse(old.saveCategories()); XCTAssertFalse(model.coordinator.canSubmit)
                if let newer { XCTAssertTrue(newer.canRead); XCTAssertEqual(newer.state, .loaded) }
            }
        }
    }
    func testRealSessionAcceptedCategoryAndDictionary401ExpireOnlyAtAcceptedSheet() async throws {
        for field in [TemplateMetadataField.players, .duration, .categories] {
            let wire = Wire(); let (session, vault) = try session(wire)
            await login(session)
            let model = TemplateAuthoringModel(coordinator: session.templateAuthoringEditor()); model.load()
            let editor = TemplateAuthoringMetadataEditor(model: model, reader: session, field: field)
            let started = expectation(description: "Accepted selector request started")
            wire.pauseNext = true; wire.onPaused = { started.fulfill() }
            let pending = Task { await editor.load() }
            await fulfillment(of: [started], timeout: 2)
            XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
            wire.resume(outcome: 401); await pending.value
            XCTAssertNil(session.account); XCTAssertNil(vault.value); XCTAssertEqual(session.errorKey, "auth.expired")
            XCTAssertFalse(editor.canRead); XCTAssertTrue(editor.visibleOptions.isEmpty)
        }
    }
    func testRealMetadataReadsAndSyntheticAuthoringDispatchHaveIndependentCounts() async throws {
        let wire = Wire(); let (session, _) = try session(wire)
        await login(session)
        let writes = TemplateAuthoringSyntheticTransport(scenario: .accepted)
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: writes),
            store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session.currentTemplateAuthoringSession })
        coordinator.open(seed: .init(title: "Synthetic metadata counting"))
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        wire.requests = []
        for field in TemplateMetadataField.allCases {
            let editor = TemplateAuthoringMetadataEditor(model: model, reader: session, field: field)
            await editor.load(); XCTAssertEqual(editor.state, .loaded); editor.close()
            XCTAssertEqual(writes.requests.count, 0)
        }
        XCTAssertEqual(wire.requests.count, 3)
        model.prepare(.saveDraft); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertEqual(writes.requests.count, 1); XCTAssertEqual(wire.requests.count, 3)
        XCTAssertEqual(coordinator.state, .simulated)
    }

    @MainActor private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var role = "player"
        var json = #"{"code":200,"data":[{"dictValue":" 6+ ","dictLabel":" Group "},{"dictValue":"60","dictLabel":"One hour"},{"dictValue":" 6+ ","dictLabel":"Alternate"}]}"#
        var pauseNext = false
        var onPaused: (() -> Void)?
        private var continuation: CheckedContinuation<(Data, Int), Error>?
        func resume(outcome: Int) {
            let pending = continuation; continuation = nil
            if outcome == -1 { pending?.resume(throwing: APIError.unauthorized) }
            else { pending?.resume(returning: (Data(json.utf8), outcome)) }
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url!.path
            if pauseNext, path.hasSuffix("/api/common/dict") || path.hasSuffix("/api/category/list") {
                pauseNext = false
                return try await withCheckedThrowingContinuation { continuation = $0; onPaused?() }
            }
            if path.hasSuffix("/api/common/dict") { return (Data(json.utf8), 200) }
            if path.hasSuffix("/api/category/list") { return (Data(#"{"code":200,"data":[{"id":4,"categoryName":"Four","type":4}]}"#.utf8), 200) }
            if path.hasSuffix("/api/login/phone") { return (Data("{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200) }
            if path.hasSuffix("/api/userInfo") { return (Data("{\"code\":200,\"appUser\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200) }
            return (Data(#"{"code":200}"#.utf8), 200)
        }
    }
}
