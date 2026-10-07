import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ProjectMerchantDraftSelectionTests: XCTestCase {
    private let fixtureContentHash = String(repeating: "a", count: 64)
    private func session(_ account: Int = 7, epoch: UInt64 = 1, viewer: UInt64 = 0, configuration: UInt64 = 0) throws -> ProjectEditSession {
        try .init(accountID: account, epoch: epoch, storageNamespace: "merchant-draft-tests", viewerRevision: viewer, configurationRevision: configuration)
    }
    private func row(_ id: Int = 50, template: Int = 61, title: String = "Original draft", available: Bool = true) -> ProjectEditJSON {
        var value: [String: ProjectEditJSON] = ["sourceId": .number(Decimal(id)), "memberTemplateId": .number(Decimal(template)), "state": .string(available ? "READY" : "UNAVAILABLE")]
        if available {
            value["source"] = .object(["kind": .string("MERCHANT_AI_TEMPLATE_SOURCE_V1"), "sourceId": .number(Decimal(id)), "sourceVersion": .number(1), "contentHash": .string(fixtureContentHash)])
            value["templateTitle"] = .string(title); value["templateContentHash"] = .string(fixtureContentHash)
        }
        return .object(value)
    }
    private func common(profile: String = "MERCHANT_AUTHORING_DRAFT_SELECTION_PAGE_V1", currentness: String = "PAGE_CURRENT_NOT_SNAPSHOT", owner: Int = 7, merchant: Int = 8) -> [String: ProjectEditJSON] {
        ["profile": .string(profile), "ownerMemberId": .number(Decimal(owner)), "merchantRowId": .number(Decimal(merchant)),
         "templateIdNamespace": .string("CMS_MEMBER_TEMPLATE"), "currentness": .string(currentness),
         "merchantFactsFreshness": .string("HISTORICAL_INPUT_ONLY"), "approvalProof": .bool(false), "usageRightsProof": .bool(false), "publicationAuthority": .bool(false)]
    }
    private func page(_ rows: [ProjectEditJSON]? = nil, next: Int? = nil, owner: Int = 7, merchant: Int = 8) -> ProjectEditJSON {
        var value = common(owner: owner, merchant: merchant); value["rows"] = .array(rows ?? [row()]); value["nextBeforeSourceId"] = next.map { .number(Decimal($0)) } ?? .null; return .object(value)
    }
    private func resolved(_ row: ProjectEditJSON? = nil, owner: Int = 7, merchant: Int = 8) -> ProjectEditJSON {
        var value = common(profile: "MERCHANT_AUTHORING_DRAFT_SELECTION_RESOLVE_V1", currentness: "CURRENT_AT_READ_ONLY", owner: owner, merchant: merchant)
        value["row"] = row ?? self.row(); return .object(value)
    }
    private func choice() throws -> ProjectMerchantDraftChoice { try XCTUnwrap(ProjectMerchantDraftRow.decode(row()).choice) }
    private func bytes(_ value: ProjectEditJSON, code: Int = 200) throws -> Data { try JSONEncoder().encode(["code": ProjectEditJSON.number(Decimal(code)), "data": value]) }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var response: Data = Data(); var status = 200; var hold = false
        var started: XCTestExpectation?
        var continuation: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); started?.fulfill()
            if hold { return try await withCheckedThrowingContinuation { continuation = $0 } }
            return (response, status)
        }
        func finish() { let pending = continuation; continuation = nil; pending?.resume(returning: (response, status)) }
    }
    private func client(_ s: ProjectEditSession, wire: Wire, paths: Set<String>? = [ProjectMerchantDraftPath.list, ProjectMerchantDraftPath.resolve],
                        current: @escaping () -> ProjectMerchantDraftCredentials?, capability: @escaping (String) -> Bool = { _ in true }) throws -> ProjectMerchantDraftClient {
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let approval = try paths.map { try OperationEndpointApproval(baseURL: config.baseURL, namespace: s.storageNamespace, accountID: s.accountID, paths: $0) }
        return .init(configuration: config, approval: approval, transport: wire, currentCredentials: current, currentCapability: capability)
    }
    func testEmptyAndUnavailablePagesAreDifferentFromUnconfigured() throws {
        let empty = try ProjectMerchantDraftPage.decode(page([]), accountID: 7, beforeSourceID: nil)
        XCTAssertTrue(empty.rows.isEmpty); XCTAssertNil(empty.nextBeforeSourceID)
        let unavailable = try ProjectMerchantDraftPage.decode(page([row(available: false)]), accountID: 7, beforeSourceID: nil)
        XCTAssertEqual(unavailable.rows.count, 1); XCTAssertNil(unavailable.rows[0].choice)
    }
    func testStrictOwnerNamespaceAuthorityAndFreshnessProjection() throws {
        let edits: [(String, ProjectEditJSON)] = [("ownerMemberId", .number(8)), ("merchantRowId", .number(0)), ("templateIdNamespace", .string("W18")), ("publicationAuthority", .bool(true)), ("approvalProof", .bool(true)), ("usageRightsProof", .bool(true)), ("merchantFactsFreshness", .string("CURRENT")), ("currentness", .string("SNAPSHOT")), ("extra", .bool(false))]
        for (key, value) in edits {
            var v = try XCTUnwrap(page().object); v[key] = value
            XCTAssertThrowsError(try ProjectMerchantDraftPage.decode(.object(v), accountID: 7, beforeSourceID: nil), key)
        }
    }
    func testSourceAndRowsRejectInvalidDuplicateOutOfOrderOrProtectedShapes() throws {
        let cases = [[row(), row()], [row(), row(49, template: 61)], [row(49), row(50, template: 62)], (0...20).map { row(100 - $0, template: 200 - $0) }]
        for values in cases { XCTAssertThrowsError(try ProjectMerchantDraftPage.decode(page(values), accountID: 7, beforeSourceID: nil)) }
        var invalid = try XCTUnwrap(row().object); invalid["sourceId"] = .number(0)
        XCTAssertThrowsError(try ProjectMerchantDraftRow.decode(.object(invalid)))
        invalid = try XCTUnwrap(row(available: false).object); invalid["templateTitle"] = .string("body must not leak")
        XCTAssertThrowsError(try ProjectMerchantDraftRow.decode(.object(invalid)))
        invalid = try XCTUnwrap(row().object); invalid["source"] = .object(["kind": .string("W18"), "sourceId": .number(50), "sourceVersion": .number(1), "contentHash": .string(fixtureContentHash)])
        XCTAssertThrowsError(try ProjectMerchantDraftRow.decode(.object(invalid)))
        invalid = try XCTUnwrap(row().object); invalid["templateContentHash"] = .string(fixtureContentHash.uppercased())
        XCTAssertThrowsError(try ProjectMerchantDraftRow.decode(.object(invalid)))
    }
    func testFullUnavailablePageKeepsLastScannedCursor() throws {
        let rows = (0..<20).map { row(100 - $0, template: 200 - $0, available: false) }
        let result = try ProjectMerchantDraftPage.decode(page(rows, next: 81), accountID: 7, beforeSourceID: 101)
        XCTAssertEqual(result.rows.count, 20); XCTAssertEqual(result.nextBeforeSourceID, 81)
        XCTAssertThrowsError(try ProjectMerchantDraftPage.decode(page(rows, next: 82), accountID: 7, beforeSourceID: 101))
        XCTAssertThrowsError(try ProjectMerchantDraftPage.decode(page(rows, next: 81), accountID: 7, beforeSourceID: 100))
        XCTAssertThrowsError(try ProjectMerchantDraftPage.decode(page([row()], next: 50), accountID: 7, beforeSourceID: nil))
    }
    func testResolveMustMatchExactOwnerMerchantSourceHashAndUnicodeTitle() throws {
        let expected = try choice()
        _ = try ProjectMerchantDraftResolution.decode(resolved(), accountID: 7, merchantRowID: 8, expected: expected)
        for value in [resolved(owner: 8), resolved(merchant: 9), resolved(row(51)), resolved(row(available: false)), resolved(row(title: "Changed"))] {
            XCTAssertThrowsError(try ProjectMerchantDraftResolution.decode(value, accountID: 7, merchantRowID: 8, expected: expected))
        }
        let decomposed = try XCTUnwrap(ProjectMerchantDraftRow.decode(row(title: "e\u{301}")).choice)
        XCTAssertThrowsError(try ProjectMerchantDraftResolution.decode(resolved(row(title: "é")), accountID: 7, merchantRowID: 8, expected: decomposed))
    }
    func testApplyingOnlyChangesExistingTemplateIDAndPreservesNodeBytes() throws {
        var node = ProjectEditNode(); node.name = "  e\u{301}\n"; node.templateID = 999
        node.localMetadata = ["future": .array([.null, .number(123), .string("raw")])]; node.nodeTime = 0
        let result = try ProjectMerchantDraftResolution.decode(resolved(), accountID: 7, merchantRowID: 8, expected: choice()).applying(to: node)
        var expected = node; expected.templateID = 61
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(result), ProjectEditPendingMaterials.exactData(expected))
    }
    func testBothExactGrantsAreRequiredAndPublicOrWriteCannotSubstitute() async throws {
        let s = try session(), credentials = try ProjectMerchantDraftCredentials(session: s, token: "synthetic"), wire = Wire()
        let sets: [Set<String>?] = [nil, [ProjectMerchantDraftPath.list], [ProjectMerchantDraftPath.resolve], ["api/template/my-list"], ["api/topic/v2/create"]]
        for paths in sets {
            let service = try client(s, wire: wire, paths: paths, current: { credentials })
            XCTAssertFalse(service.isCurrent(session: s))
            do { _ = try await service.list(beforeSourceID: nil, session: s); XCTFail("unconfigured") }
            catch { XCTAssertEqual(error as? ProjectMerchantDraftError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testListAndResolveDispatchExactReadRequests() async throws {
        let s = try session(), credentials = try ProjectMerchantDraftCredentials(session: s, token: "synthetic"), wire = Wire()
        let service = try client(s, wire: wire, current: { credentials }); wire.response = try bytes(page())
        _ = try await service.list(beforeSourceID: nil, session: s)
        wire.response = try bytes(resolved()); _ = try await service.resolve(choice(), merchantRowID: 8, session: s)
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/" + ProjectMerchantDraftPath.list, "/" + ProjectMerchantDraftPath.resolve])
        let body = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(wire.requests[0].httpBody))
        XCTAssertEqual(body, ["beforeSourceId": .null]); XCTAssertEqual(wire.requests[0].httpMethod, "POST")
        let second = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(wire.requests[1].httpBody))
        XCTAssertEqual(second, try choice().resolveFields)
        XCTAssertNil(wire.requests[1].url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.query })
    }
    func testDefaultCapabilityClosureStaysClosedEvenWithPathApproval() throws {
        let s = try session(), wire = Wire(), config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let credentials = try ProjectMerchantDraftCredentials(session: s, token: "synthetic")
        let approval = try OperationEndpointApproval(baseURL: config.baseURL, namespace: s.storageNamespace, accountID: 7, paths: [ProjectMerchantDraftPath.list, ProjectMerchantDraftPath.resolve])
        let service = ProjectMerchantDraftClient(configuration: config, approval: approval, transport: wire, currentCredentials: { credentials })
        XCTAssertFalse(service.isCurrent(session: s))
    }
    func testChangingAccountEpochViewerConfigurationOrCapabilityDiscardsLateRead() async throws {
        for kind in ["account", "epoch", "viewer", "configuration", "capability"] {
            let s = try session(), wire = Wire(); wire.hold = true; wire.response = try bytes(page()); wire.started = expectation(description: kind)
            var credentials: ProjectMerchantDraftCredentials? = try .init(session: s, token: "synthetic"); var allowed = true
            let service = try client(s, wire: wire, current: { credentials }, capability: { _ in allowed })
            let pending = Task { try await service.list(beforeSourceID: nil, session: s) }
            await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 2)
            if kind == "capability" { allowed = false }
            else { credentials = try .init(session: session(kind == "account" ? 8 : 7, epoch: kind == "epoch" ? 2 : 1, viewer: kind == "viewer" ? 1 : 0, configuration: kind == "configuration" ? 1 : 0), token: "synthetic") }
            wire.finish()
            do { _ = try await pending.value; XCTFail("stale read") } catch { XCTAssertEqual(error as? ProjectMerchantDraftError, .changedContext) }
        }
    }
    func testCancelledTransportResultDoesNotReturnPage() async throws {
        let s = try session(), wire = Wire(); wire.hold = true; wire.response = try bytes(page()); wire.started = expectation(description: "held")
        let credentials = try ProjectMerchantDraftCredentials(session: s, token: "synthetic"), service = try client(s, wire: wire, current: { credentials })
        let pending = Task { try await service.list(beforeSourceID: nil, session: s) }
        await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 2); pending.cancel(); wire.finish()
        do { _ = try await pending.value; XCTFail("cancelled") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testHTTPAndEnvelopeErrorsRemainFailures() async throws {
        let s = try session(), wire = Wire(), credentials = try ProjectMerchantDraftCredentials(session: s, token: "synthetic")
        let service = try client(s, wire: wire, current: { credentials })
        for status in [401, 403, 409, 503] {
            wire.status = status; wire.response = try bytes(.null, code: status)
            do { _ = try await service.list(beforeSourceID: nil, session: s); XCTFail("failure") }
            catch {
                if status == 401 { XCTAssertEqual(error as? APIError, .unauthorized) }
                else { XCTAssertEqual(error as? ProjectMerchantDraftError, status == 403 ? .forbidden : status == 409 ? .sourceChanged : .unavailable) }
            }
        }
        wire.status = 200; wire.response = Data("{\"code\":200,\"code\":200,\"data\":{}}".utf8)
        do { _ = try await service.list(beforeSourceID: nil, session: s); XCTFail("duplicate JSON") } catch { XCTAssertEqual(error as? ProjectMerchantDraftError, .invalidResponse) }
    }
    func testFeatureCatalogKeepsOwnerDraftRoutesSeparateAndEmptyByDefault() throws {
        let config = try BusinessRuntimeConfiguration(market: .china, baseURL: URL(string: "https://example.com")!, namespace: "test", accountID: 7)
        XCTAssertTrue(config.routes.isEmpty)
        XCTAssertTrue(BusinessRuntimeFeature.merchantDraftSelectionList.accepts(try .post(ProjectMerchantDraftPath.list)))
        XCTAssertFalse(BusinessRuntimeFeature.merchantDraftSelectionList.accepts(try .post(ProjectMerchantDraftPath.resolve)))
        XCTAssertFalse(BusinessRuntimeFeature.merchantDraftSelectionResolve.accepts(try .post(ProjectMerchantDraftPath.list)))
        let features: [BusinessRuntimeFeature] = [.publishingRead, .projectRead, .projectWrite, .approvedTopicReviewPrepare]
        for feature in features {
            XCTAssertFalse(feature.accepts(try .post(ProjectMerchantDraftPath.list))); XCTAssertFalse(feature.accepts(try .post(ProjectMerchantDraftPath.resolve)))
        }
    }
    func testExactBackendHTTPGoldensDecodeWithoutInventingAuthority() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/MerchantDraftSelection")
        let listed = try ApprovedTopicReleaseWire.envelope(Data(contentsOf: root.appendingPathComponent("list.json")))
        let resolved = try ApprovedTopicReleaseWire.envelope(Data(contentsOf: root.appendingPathComponent("resolve.json")))
        XCTAssertEqual(listed["code"], .number(200)); XCTAssertEqual(resolved["code"], .number(200))
        let page = try ProjectMerchantDraftPage.decode(XCTUnwrap(listed["data"]), accountID: 7, beforeSourceID: nil)
        XCTAssertEqual(page.ownerMemberID, 7); XCTAssertEqual(page.merchantRowID, 19); XCTAssertEqual(page.rows.count, 1)
        let choice = try XCTUnwrap(page.rows.first?.choice)
        let resolution = try ProjectMerchantDraftResolution.decode(XCTUnwrap(resolved["data"]), accountID: 7, merchantRowID: 19, expected: choice)
        XCTAssertEqual(resolution.choice.memberTemplateID, 1); XCTAssertEqual(resolution.choice.title, "Human title")
        XCTAssertEqual(listed["data"]?.object?["publicationAuthority"], .bool(false))
        XCTAssertEqual(resolved["data"]?.object?["approvalProof"], .bool(false))
    }

}
