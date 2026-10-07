import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ProjectStoryTemplateClientTests: XCTestCase {
    private let paths: Set<String> = [ProjectStoryTemplatePath.list, ProjectStoryTemplatePath.detail]
    private func session(account: Int = 7, epoch: UInt64 = 1, namespace: String = "story-selection-tests",
                         viewer: UInt64 = 0, configuration: UInt64 = 0) throws -> ProjectEditSession {
        try .init(accountID: account, epoch: epoch, storageNamespace: namespace,
                  viewerRevision: viewer, configurationRevision: configuration)
    }
    private func configuration() throws -> APIConfiguration {
        try .init(baseURL: URL(string: "https://example.test/native")!)
    }
    private func row(id: Int = 11) -> ProjectEditJSON {
        .object(["id": .number(Decimal(id)), "memberId": .number(7), "draftStatus": .number(0),
                 "delFlag": .number(0), "validationMethod": .number(1),
                 "title": .string("Personal game"), "advancedConfigJson": .string("")])
    }
    private func page(_ rows: [ProjectEditJSON]? = nil, total: Int = 1) -> ProjectEditJSON {
        .object(["rows": .array(rows ?? [row()]), "total": .number(Decimal(total))])
    }
    private func bytes(_ value: ProjectEditJSON, code: Int = 200) throws -> Data {
        try JSONEncoder().encode(["code": ProjectEditJSON.number(Decimal(code)), "data": value])
    }
    @MainActor private final class Wire: HTTPTransport {
        enum Failure: Error, Equatable { case offline }
        var requests: [URLRequest] = []
        var response = Data()
        var status = 200
        var failure: Failure?
        var hold = false
        var started: XCTestExpectation?
        var continuation: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); started?.fulfill()
            if hold { return try await withCheckedThrowingContinuation { continuation = $0 } }
            if let failure { throw failure }
            return (response, status)
        }
        func finish() {
            let pending = continuation; continuation = nil
            if let failure { pending?.resume(throwing: failure) }
            else { pending?.resume(returning: (response, status)) }
        }
    }
    private func client(_ session: ProjectEditSession, wire: Wire, approvedPaths: Set<String>? = nil,
                        current: @escaping () -> ProjectStoryTemplateCredentials?,
                        capability: @escaping (String) -> Bool = { _ in true }) throws -> ProjectStoryTemplateClient {
        let config = try configuration()
        let approval = try OperationEndpointApproval(baseURL: config.baseURL, namespace: session.storageNamespace,
            accountID: session.accountID, paths: approvedPaths ?? paths)
        return .init(configuration: config, approval: approval, transport: wire,
                     currentCredentials: current, currentCapability: capability)
    }
    private func assertForm(_ request: URLRequest, path: String, fields: [String: String],
                            file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(request.url, try configuration().baseURL.appendingPathComponent(path), file: file, line: line)
        XCTAssertEqual(request.httpMethod, "POST", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json", file: file, line: line)
        XCTAssertNil(request.httpBodyStream, file: file, line: line)
        XCTAssertNil(request.url?.query, file: file, line: line)
        XCTAssertNil(request.url?.fragment, file: file, line: line)
        let type = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"), file: file, line: line)
        let prefix = "multipart/form-data; boundary="
        XCTAssertTrue(type.hasPrefix(prefix), file: file, line: line)
        let boundary = String(type.dropFirst(prefix.count))
        let canonical = try AuthRequestBuilder.makeFormRequest(url: XCTUnwrap(request.url), fields: fields,
            token: "synthetic", boundary: boundary)
        XCTAssertEqual(request.httpBody, canonical.httpBody, "Only the exact source form fields are allowed", file: file, line: line)
    }

    func testCredentialsRejectEmptyWhitespaceAndHeaderInjection() throws {
        for token in ["", "  ", "a\rb", "a\nb", "a\u{7f}b", "é"] {
            XCTAssertThrowsError(try ProjectStoryTemplateCredentials(session: session(), token: token)) {
                XCTAssertEqual($0 as? APIError, .invalidRequest)
            }
        }
        _ = try ProjectStoryTemplateCredentials(session: session(), token: "synthetic")
    }

    func testDefaultConstructionNeverDispatchesEvenWithCredentials() async throws {
        let s = try session(), wire = Wire(), config = try configuration()
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        let noApproval = ProjectStoryTemplateClient(configuration: config, transport: wire,
            currentCredentials: { credentials }, currentCapability: { _ in true })
        let approval = try OperationEndpointApproval(baseURL: config.baseURL, namespace: s.storageNamespace,
            accountID: s.accountID, paths: paths)
        let noCapability = ProjectStoryTemplateClient(configuration: config, approval: approval, transport: wire,
            currentCredentials: { credentials })
        for service in [noApproval, noCapability] {
            XCTAssertFalse(service.isCurrent(session: s))
            do { _ = try await service.list(page: 1, session: s); XCTFail("Default read dispatched") }
            catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .notConfigured) }
            do { _ = try await service.detail(id: MemberPlayTemplateID(rawValue: 11)!, session: s); XCTFail("Default detail dispatched") }
            catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testBothExactApprovalsRequiredAndUnrelatedReadsOrWritesCannotSubstitute() async throws {
        let s = try session(), wire = Wire()
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        let invalid: [Set<String>] = [[], [ProjectStoryTemplatePath.list], [ProjectStoryTemplatePath.detail],
            ["api/template/info"], ["api/template/draft", "api/topic/v2/create"],
            ["api/merchant/authoring/draft-selection/list", "api/merchant/authoring/draft-selection/resolve"]]
        for grant in invalid {
            let service = try client(s, wire: wire, approvedPaths: grant, current: { credentials })
            XCTAssertFalse(service.isCurrent(session: s))
            do { _ = try await service.list(page: 1, session: s); XCTFail("Unrelated approval used") }
            catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testApprovalRequiresExactDeploymentNamespaceAndAccount() async throws {
        let s = try session(), wire = Wire(), config = try configuration()
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        let approvals = [
            try OperationEndpointApproval(baseURL: URL(string: "https://other.test/native")!, namespace: s.storageNamespace, accountID: 7, paths: paths),
            try OperationEndpointApproval(baseURL: URL(string: "https://example.test/other")!, namespace: s.storageNamespace, accountID: 7, paths: paths),
            try OperationEndpointApproval(baseURL: config.baseURL, namespace: "other", accountID: 7, paths: paths),
            try OperationEndpointApproval(baseURL: config.baseURL, namespace: s.storageNamespace, accountID: 8, paths: paths)
        ]
        for approval in approvals {
            let service = ProjectStoryTemplateClient(configuration: config, approval: approval, transport: wire,
                currentCredentials: { credentials }, currentCapability: { _ in true })
            XCTAssertFalse(service.isCurrent(session: s))
            do { _ = try await service.list(page: 1, session: s); XCTFail("Wrong deployment/account scope") }
            catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testListSendsOnlyDraftStatusPersonalScopeAndBoundedPagination() async throws {
        let s = try session(), wire = Wire()
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        let service = try client(s, wire: wire, current: { credentials })
        let identity = service.identity
        for number in [1, 2, ProjectStoryTemplatePage.maximumPages] {
            let value = page(total: (number - 1) * 20 + 1); wire.response = try bytes(value)
            let result = try await service.list(page: number, session: s)
            XCTAssertEqual(result, try ProjectStoryTemplatePage.decode(value, accountID: 7, page: number))
            try assertForm(XCTUnwrap(wire.requests.last), path: ProjectStoryTemplatePath.list,
                fields: ["draft_status": "0", "scope": "", "pageNum": String(number), "pageSize": "20"])
        }
        XCTAssertEqual(wire.requests.count, 3); XCTAssertEqual(service.identity, identity)
    }

    func testDetailSendsOnlyTypedMemberIDAndUsesStrictDraftDecoder() async throws {
        let s = try session(), wire = Wire(), id = MemberPlayTemplateID(rawValue: 11)!
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        let service = try client(s, wire: wire, current: { credentials }); wire.response = try bytes(row())
        let result = try await service.detail(id: id, session: s)
        XCTAssertEqual(result, try ProjectStoryTemplateDraft.decode(row(), accountID: 7, requestedID: id))
        XCTAssertEqual(result.content, .gameplay)
        XCTAssertEqual(wire.requests.count, 1)
        try assertForm(XCTUnwrap(wire.requests.first), path: ProjectStoryTemplatePath.detail, fields: ["id": "11"])
    }

    func testInvalidPagesAndAbsentOrMismatchedCredentialsNeverDispatch() async throws {
        let s = try session(), wire = Wire()
        var credentials: ProjectStoryTemplateCredentials? = try .init(session: s, token: "synthetic")
        let service = try client(s, wire: wire, current: { credentials })
        for number in [Int.min, -1, 0, ProjectStoryTemplatePage.maximumPages + 1, Int.max] {
            do { _ = try await service.list(page: number, session: s); XCTFail("Out-of-range page") }
            catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .invalidResponse) }
        }
        for replacement in [nil, try ProjectStoryTemplateCredentials(session: session(epoch: 2), token: "synthetic")] {
            credentials = replacement
            XCTAssertFalse(service.isCurrent(session: s))
            do { _ = try await service.list(page: 1, session: s); XCTFail("Stale credentials") }
            catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testOwnerDraftDeletedAndRequestedIdentityMismatchesNeverFallback() async throws {
        let s = try session(), id = MemberPlayTemplateID(rawValue: 11)!
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        let changes: [(String, ProjectEditJSON?)] = [("memberId", nil), ("memberId", .number(8)),
            ("memberId", .string("7")), ("draftStatus", nil), ("draftStatus", .number(1)),
            ("draftStatus", .string("0")), ("delFlag", .number(1)), ("id", .number(0))]
        for (key, value) in changes {
            var changed = try XCTUnwrap(row().object); changed[key] = value
            let wire = Wire(), service = try client(s, wire: wire, current: { credentials })
            wire.response = try bytes(page([.object(changed)]))
            do { _ = try await service.list(page: 1, session: s); XCTFail("Invalid owner draft row: \(key)") }
            catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .invalidResponse) }
            wire.response = try bytes(.object(changed))
            do { _ = try await service.detail(id: id, session: s); XCTFail("Invalid owner draft detail: \(key)") }
            catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .invalidResponse) }
            XCTAssertEqual(wire.requests.map { $0.url?.path }, ["/native/api/template/my-list", "/native/api/template/myinfo"])
        }
        let wire = Wire(), service = try client(s, wire: wire, current: { credentials })
        wire.response = try bytes(row(id: 12))
        do { _ = try await service.detail(id: id, session: s); XCTFail("Different template returned") }
        catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .invalidResponse) }
        XCTAssertEqual(wire.requests.count, 1)
    }

    func testMalformedEnvelopeOversizeAndDuplicateJSONFailClosed() async throws {
        let s = try session(), wire = Wire()
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        let service = try client(s, wire: wire, current: { credentials })
        let malformed = [Data(), Data("not-json".utf8), Data("[]".utf8), Data("{\"code\":\"200\",\"data\":{}}".utf8),
            Data("{\"code\":200}".utf8), Data("{\"code\":200,\"data\":null}".utf8),
            Data("{\"code\":200,\"code\":200,\"data\":{}}".utf8),
            Data("{\"code\":200,\"data\":{\"rows\":[],\"total\":0,\"total\":0}}".utf8),
            Data(repeating: 32, count: 1024 * 1024 + 1)]
        for data in malformed {
            wire.response = data
            do { _ = try await service.list(page: 1, session: s); XCTFail("Malformed response accepted") }
            catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .invalidResponse) }
        }
        XCTAssertEqual(wire.requests.count, malformed.count)
    }

    func testOneMiBResponseBoundaryAndValidEmptyPage() async throws {
        let s = try session(), wire = Wire()
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        let service = try client(s, wire: wire, current: { credentials })
        let value = page([], total: 0), encoded = try bytes(value), limit = 1024 * 1024
        // Whitespace padding keeps both sides valid JSON, isolating the byte limit.
        wire.response = encoded + Data(repeating: 32, count: limit - encoded.count)
        let result = try await service.list(page: 1, session: s)
        XCTAssertTrue(result.rows.isEmpty); XCTAssertNil(result.nextPage)
        wire.response.append(32)
        do { _ = try await service.list(page: 1, session: s); XCTFail("Oversized valid JSON accepted") }
        catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .invalidResponse) }
        XCTAssertEqual(wire.requests.count, 2)
    }

    func testDetailMissingDeletionProofAndUnsupportedMechanicsCannotBecomeGameplay() async throws {
        let s = try session(), wire = Wire(), id = MemberPlayTemplateID(rawValue: 11)!
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        let service = try client(s, wire: wire, current: { credentials })
        var missingProof = try XCTUnwrap(row().object); missingProof.removeValue(forKey: "delFlag")
        wire.response = try bytes(.object(missingProof))
        do { _ = try await service.detail(id: id, session: s); XCTFail("Missing deletion proof") }
        catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .invalidResponse) }
        let changes: [(String, ProjectEditJSON?)] = [("validationMethod", nil), ("validationMethod", .number(4)),
            ("validationMethod", .number(5)), ("advancedConfigJson", .string("{malformed}"))]
        for (key, value) in changes {
            var changed = try XCTUnwrap(row().object); changed[key] = value
            wire.response = try bytes(.object(changed))
            do { _ = try await service.detail(id: id, session: s); XCTFail("Unsupported detail accepted") }
            catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .unsupported) }
        }
        XCTAssertEqual(wire.requests.count, changes.count + 1)
        XCTAssertTrue(wire.requests.allSatisfy { $0.url?.path == "/native/api/template/myinfo" })
    }

    func testHTTPAndEnvelope401403AndOtherFailuresRemainDistinct() async throws {
        let s = try session(), wire = Wire()
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        let service = try client(s, wire: wire, current: { credentials })
        for status in [401, 403, 404, 503] {
            wire.status = status; wire.response = try bytes(page())
            do { _ = try await service.list(page: 1, session: s); XCTFail("HTTP failure accepted") }
            catch { XCTAssertEqual(error as? APIError, status == 401 ? .unauthorized : .httpStatus(status)) }
        }
        wire.status = 200
        for code in [401, 403, 404, 500] {
            wire.response = try bytes(page(), code: code)
            do { _ = try await service.list(page: 1, session: s); XCTFail("Business failure accepted") }
            catch { XCTAssertEqual(error as? APIError, code == 401 ? .unauthorized : .businessCode(code)) }
        }
        wire.response = try bytes(page(), code: 409)
        do { _ = try await service.list(page: 1, session: s); XCTFail("Changed source accepted") }
        catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .sourceChanged) }
        wire.status = 409; wire.response = Data()
        do { _ = try await service.list(page: 1, session: s); XCTFail("HTTP changed source accepted") }
        catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .sourceChanged) }
    }

    func testEveryLiveContextChangeDiscardsLateSuccessAndTransportFailure() async throws {
        for failing in [false, true] {
            for kind in ["account", "epoch", "namespace", "viewer", "configuration", "token", "logout", "list-capability", "detail-capability"] {
                let s = try session(), wire = Wire()
                wire.hold = true; wire.response = try bytes(page()); wire.failure = failing ? .offline : nil
                wire.started = expectation(description: "\(kind)-\(failing)")
                var credentials: ProjectStoryTemplateCredentials? = try .init(session: s, token: "synthetic")
                var allowed = paths
                let service = try client(s, wire: wire, current: { credentials }, capability: { allowed.contains($0) })
                let pending = Task { try await service.list(page: 1, session: s) }
                await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 2)
                switch kind {
                case "logout": credentials = nil
                case "token": credentials = try .init(session: s, token: "rotated")
                case "list-capability": allowed.remove(ProjectStoryTemplatePath.list)
                case "detail-capability": allowed.remove(ProjectStoryTemplatePath.detail)
                default:
                    credentials = try .init(session: session(account: kind == "account" ? 8 : 7,
                        epoch: kind == "epoch" ? 2 : 1, namespace: kind == "namespace" ? "other" : s.storageNamespace,
                        viewer: kind == "viewer" ? 1 : 0, configuration: kind == "configuration" ? 1 : 0), token: "synthetic")
                }
                wire.finish()
                do { _ = try await pending.value; XCTFail("Late \(kind) result accepted") }
                catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .changedContext, kind) }
                XCTAssertEqual(wire.requests.count, 1)
            }
        }
    }

    func testDetailPermissionRevocationSuppressesLateUnauthorizedError() async throws {
        let s = try session(), wire = Wire()
        wire.hold = true; wire.status = 401; wire.started = expectation(description: "detail started")
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        var allowed = true
        let service = try client(s, wire: wire, current: { credentials }, capability: { _ in allowed })
        let pending = Task { try await service.detail(id: MemberPlayTemplateID(rawValue: 11)!, session: s) }
        await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 2)
        allowed = false; wire.finish()
        do { _ = try await pending.value; XCTFail("Stale authorization error escaped") }
        catch { XCTAssertEqual(error as? ProjectStoryTemplateError, .changedContext) }
        XCTAssertEqual(wire.requests.count, 1)
    }

    func testCancellationSuppressesBothLateSuccessAndLateFailure() async throws {
        for failing in [false, true] {
            let s = try session(), wire = Wire()
            wire.hold = true; wire.response = try bytes(row()); wire.failure = failing ? .offline : nil
            wire.started = expectation(description: "cancel-\(failing)")
            let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
            let service = try client(s, wire: wire, current: { credentials })
            let pending = Task { try await service.detail(id: MemberPlayTemplateID(rawValue: 11)!, session: s) }
            await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 2)
            pending.cancel(); wire.finish()
            do { _ = try await pending.value; XCTFail("Cancelled read returned") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(wire.requests.count, 1)
        }
    }

    func testAlreadyCancelledReadNeverDispatchesAndCurrentTransportFailureIsPreserved() async throws {
        let s = try session(), wire = Wire()
        let credentials = try ProjectStoryTemplateCredentials(session: s, token: "synthetic")
        let service = try client(s, wire: wire, current: { credentials })
        let pending = Task { try await service.list(page: 1, session: s) }; pending.cancel()
        do { _ = try await pending.value; XCTFail("Cancelled read dispatched") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(wire.requests.isEmpty)
        wire.failure = .offline
        do { _ = try await service.list(page: 1, session: s); XCTFail("Transport failure accepted") }
        catch { XCTAssertEqual(error as? Wire.Failure, .offline) }
        XCTAssertEqual(wire.requests.count, 1)
    }
}
