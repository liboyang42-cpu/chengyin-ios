#if DEBUG
import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Authored offline. No live transport, URLSession, account, or device provider is used.
/// These tests require the combined local editor candidate; Apple execution is unverified.
@available(macOS 14.0, *)
@MainActor final class TemplateLocalConfigurationWriteFenceTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); return (Data(#"{"code":200}"#.utf8), 200)
        }
    }
    private func session(_ account: Int = 7, epoch: UInt64 = 1) throws -> TemplateAuthoringSession {
        try .init(accountID: account, namespace: "local-fence", epoch: epoch, authorizationRevision: "fixture")
    }
    private func descriptor(_ path: String, method: TemplateAuthoringJSON? = nil,
                            extra: [String: TemplateAuthoringJSON] = [:], mutates: Bool = true) -> TemplateAuthoringRequest {
        var fields: [String: TemplateAuthoringJSON] = ["title": .string("Offline fence"), "description": .string(""), "isSync": .number(1)]
        fields["validationMethod"] = method
        fields.merge(extra) { _, new in new }
        return .init(path: path, body: .json(fields), mutates: mutates)
    }
    private func assertRejected(_ request: TemplateAuthoringRequest, file: StaticString = #filePath, line: UInt = #line) async throws {
        let config = try APIConfiguration(baseURL: base)
        XCTAssertFalse(TemplateAuthoringContract.permitsRemoteConfiguration(request), file: file, line: line)
        XCTAssertThrowsError(try TemplateAuthoringWireRequestBuilder.make(request, configuration: config, token: "fixture-token"), file: file, line: line)
        // Direct adapter injection cannot rely on the HTTP wire builder for protection.
        let synthetic = TemplateAuthoringSyntheticTransport()
        let outcome = await TemplateAuthoringAdapter(transport: synthetic).submit(request)
        XCTAssertEqual(outcome, .notSent, file: file, line: line)
        XCTAssertTrue(synthetic.requests.isEmpty, file: file, line: line)
        // Bypass the adapter and invoke the real HTTP transport with a recording fake.
        let wire = Wire(), owner = try session()
        let http = TemplateAuthoringHTTPTransport(configuration: config, http: wire, session: owner,
            enabled: true, credentials: { (owner, "fixture-token") })
        do { _ = try await http.send(request); XCTFail("Forged descriptor dispatched", file: file, line: line) } catch {}
        XCTAssertTrue(wire.requests.isEmpty, file: file, line: line)
    }
    func testAliasesAndWrongOperationsCannotLeakLocalConfigurationToAnyAdapter() async throws {
        for path in ["/api/template/publish/", "/api/template/draft/", "/api/template/delete", "/api/template/updateLibraryStatus", "/api/common/dict", "/api/template/unknown"] {
            // A mutated path must not avoid the adapter-level fence, even with an otherwise old-shaped body.
            try await assertRejected(descriptor(path, method: .number(0)))
            try await assertRejected(descriptor(path, method: .number(6)))
            try await assertRejected(descriptor(path, method: .number(7)))
            for key in ["preferenceJson", "sensorType", "sensorConfig", "sensorChallengeType", "sensorConfigJson"] {
                try await assertRejected(descriptor(path, extra: [key: .null]))
                try await assertRejected(.init(path: path, body: .form(["template_id": "1", key: "private local text"]), mutates: true))
            }
            try await assertRejected(.init(path: path, body: .form(["template_id": "1", "validationMethod": "7"]), mutates: true))
        }
    }
    func testLocalMethodsRejectPayloadAndBothIntentsRegardlessOfFinishToggle() throws {
        for raw in [6, 7] {
            for finish in [false, true] {
                var draft = TemplateAuthoringSyntheticFixtures.draft()
                draft.validationMethod = try XCTUnwrap(TemplateAuthoringMethod(rawValue: raw))
                draft.finishEnabled = finish
                XCTAssertThrowsError(try TemplateAuthoringContract.payload(draft))
                for intent in TemplateAuthoringIntent.allCases {
                    XCTAssertThrowsError(try TemplateAuthoringContract.request(draft, intent: intent))
                }
            }
        }
    }
    func testForgedLocalAndUnknownMethodsRejectAtEveryDispatchBoundary() async throws {
        let rejected: [TemplateAuthoringJSON] = [.number(6), .number(7), .string("6"), .string("7"),
            .string(" 6 "), .string("7.0"), .number(8), .number(-1), .number(6.5), .number(.nan), .number(.infinity), .string("0"), .string("5"),
            .string("future"), .string(""), .string("NaN"), .null, .bool(true), .array([]), .object([:])]
        for path in ["/api/template/draft", "/api/template/publish"] {
            for value in rejected { for mutates in [false, true] {
                try await assertRejected(descriptor(path, method: value, mutates: mutates))
            } }
        }
    }
    func testLocalConfigurationKeysCannotBeSmuggledWithLegacyOrMissingMethod() async throws {
        for path in ["/api/template/draft", "/api/template/publish"] {
            for key in ["preferenceJson", "sensorType", "sensorConfig", "sensorChallengeType", "sensorConfigJson"] {
                let values: [TemplateAuthoringJSON] = [.string("{}"), .null, .object([:])]
                let methods: [TemplateAuthoringJSON?] = [nil, .number(0), .number(5)]
                for value in values {
                    for method in methods {
                        try await assertRejected(descriptor(path, method: method, extra: [key: value]))
                    }
                }
            }
            try await assertRejected(.init(path: path, body: .form(["title": "Offline", "validationMethod": "7"]), mutates: true))
        }
    }
    func testAbsentAndLegacyMethodsStillRequireExactCreateOperationShape() async throws {
        let methods: [TemplateAuthoringJSON?] = [nil, .number(0), .number(5)]
        for path in ["/api/template/draft", "/api/template/publish"] {
            for method in methods {
                let valid = descriptor(path, method: method)
                guard case .json(let baseline) = valid.body else { return XCTFail("Fixture must use JSON") }
                // Unknown and alternate local field names cannot exploit an omitted method.
                for key in ["future", "sensorDraft", "preference_json", "sensor_type", "sensor_config", "validation_method", "finishEnabled"] {
                    var fields = baseline; fields[key] = .string("local-only configuration")
                    try await assertRejected(.init(path: path, body: .json(fields), mutates: true))
                }
                let ids: [TemplateAuthoringJSON] = [.number(42), .null, .string("42")]
                for value in ids {
                    var fields = baseline; fields["id"] = value
                    try await assertRejected(.init(path: path, body: .json(fields), mutates: true))
                }
                let titles: [TemplateAuthoringJSON?] = [nil, .string(""), .string(" \n\t"), .null, .number(1), .bool(true), .object([:]), .array([])]
                for title in titles {
                    var fields = baseline; fields["title"] = title
                    try await assertRejected(.init(path: path, body: .json(fields), mutates: true))
                }
                for key in ["description", "isSync"] {
                    var fields = baseline; fields.removeValue(forKey: key)
                    try await assertRejected(.init(path: path, body: .json(fields), mutates: true))
                    fields[key] = .null
                    try await assertRejected(.init(path: path, body: .json(fields), mutates: true))
                }
                var malformedDescription = baseline; malformedDescription["description"] = .object([:])
                try await assertRejected(.init(path: path, body: .json(malformedDescription), mutates: true))
                var malformedSync = baseline; malformedSync["isSync"] = .string("1")
                try await assertRejected(.init(path: path, body: .json(malformedSync), mutates: true))
                try await assertRejected(.init(path: path, body: .json(baseline), mutates: false))
                try await assertRejected(.init(path: path, body: .form(["title": "Offline fence", "description": "", "isSync": "1"]), mutates: true))
                // Codable is a second manual construction surface despite the POST-only initializer.
                var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
                for verb in ["GET", "PUT", "post", ""] {
                    encoded["method"] = verb
                    let forged = try JSONDecoder().decode(TemplateAuthoringRequest.self, from: JSONSerialization.data(withJSONObject: encoded))
                    try await assertRejected(forged)
                }
            }
        }
    }
    func testAbsentMethodCannotCarryHiddenCompletionConfiguration() async throws {
        let textFields = ["questionName", "questionImg", "questionAudio", "questionAnswer", "questionA", "questionB", "questionC", "questionD",
            "correctAnswer", "questionOptionMediaJson", "hint1", "hint2", "answerReveal", "photoRequireDesc", "advancedConfigJson"]
        for path in ["/api/template/draft", "/api/template/publish"] {
            for key in textFields { try await assertRejected(descriptor(path, extra: [key: .string("retained")])) }
            try await assertRejected(descriptor(path, extra: ["photoReview": .number(0)]))
        }
    }
    func testLegacyZeroThroughFiveRetainExactPayloadAndWireBytes() async throws {
        for raw in 0...5 {
            var draft = TemplateAuthoringDraft(title: "Legacy")
            draft.validationMethod = try XCTUnwrap(TemplateAuthoringMethod(rawValue: raw))
            // A retained local-only buffer must never silently enter legacy wire payloads.
            draft.preferenceJson = #"{"unknown":"keep exact local text"}"#
            var expected: [String: TemplateAuthoringJSON] = ["title": .string("Legacy"), "description": .string(""),
                "isSync": .number(1), "validationMethod": .number(Double(raw))]
            if raw == 2 { expected["photoReview"] = .number(0) }
            XCTAssertEqual(try TemplateAuthoringContract.payload(draft), expected)
            let request = try TemplateAuthoringContract.request(draft, intent: .saveDraft)
            XCTAssertEqual(request.body, .json(expected))
            let config = try APIConfiguration(baseURL: base)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let wire = try TemplateAuthoringWireRequestBuilder.make(request, configuration: config, token: "fixture-token")
            XCTAssertEqual(wire.httpBody, try encoder.encode(expected))
            XCTAssertEqual(wire.url?.path, "/native/api/template/draft")
            XCTAssertEqual(wire.httpMethod, "POST")
            XCTAssertEqual(wire.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let transport = TemplateAuthoringSyntheticTransport()
            let outcome = await TemplateAuthoringAdapter(transport: transport).submit(request)
            XCTAssertEqual(outcome, .simulated); XCTAssertEqual(transport.requests, [request])
        }
    }
    func testLegacyFinishDisabledOmitsMethodAndPreservesBothEndpointDescriptors() async throws {
        for raw in 0...5 {
            var draft = TemplateAuthoringDraft(title: "Disabled finish")
            draft.finishEnabled = false; draft.validationMethod = try XCTUnwrap(TemplateAuthoringMethod(rawValue: raw))
            let expected: [String: TemplateAuthoringJSON] = ["title": .string("Disabled finish"), "description": .string(""), "isSync": .number(1)]
            XCTAssertEqual(try TemplateAuthoringContract.payload(draft), expected)
            for path in ["/api/template/draft", "/api/template/publish"] {
                let request = TemplateAuthoringRequest(path: path, body: .json(expected), mutates: true)
                XCTAssertTrue(TemplateAuthoringContract.permitsRemoteConfiguration(request))
                XCTAssertNoThrow(try TemplateAuthoringWireRequestBuilder.make(request, configuration: APIConfiguration(baseURL: base), token: "fixture-token"))
                let transport = TemplateAuthoringSyntheticTransport()
                let outcome = await TemplateAuthoringAdapter(transport: transport).submit(request)
                XCTAssertEqual(outcome, .simulated); XCTAssertEqual(transport.requests, [request])
                let owner = try session(), wire = Wire()
                let http = TemplateAuthoringHTTPTransport(configuration: try .init(baseURL: base), http: wire, session: owner,
                    enabled: true, credentials: { (owner, "fixture-token") })
                _ = try await http.send(request)
                XCTAssertEqual(wire.requests.count, 1)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                XCTAssertEqual(wire.requests.first?.httpBody, try encoder.encode(expected))
            }
        }
    }
    func testUnknownRawMethodCannotDecodeAsLocalDraft() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(TemplateAuthoringDraft(title: "Unknown"))) as? [String: Any])
        for raw in [-1, 8, 99] {
            json["validationMethod"] = raw
            XCTAssertThrowsError(try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONSerialization.data(withJSONObject: json)))
        }
    }
    func testRestoreLocalMethodsNeverCreatesRemoteReviewOrSends() throws {
        let owner = try session()
        for raw in [6, 7] {
            let storage = TemplateAuthoringMemoryStorage(), store = TemplateAuthoringLocalStore(storage: storage)
            let transport = TemplateAuthoringSyntheticTransport()
            var draft = TemplateAuthoringSyntheticFixtures.draft()
            draft.validationMethod = try XCTUnwrap(TemplateAuthoringMethod(rawValue: raw)); draft.preferenceJson = "  {}\n"
            let first = TemplateAuthoringCoordinator(adapter: .init(transport: transport), store: store, currentSession: { owner })
            first.open(seed: draft); first.saveLocal()
            let reopened = TemplateAuthoringCoordinator(adapter: .init(transport: transport), store: store, currentSession: { owner })
            reopened.open(); reopened.restoreDraft()
            XCTAssertEqual(reopened.draft, draft)
            for intent in TemplateAuthoringIntent.allCases { reopened.prepare(intent); XCTAssertNil(reopened.review) }
            XCTAssertNil(reopened.pending)
            XCTAssertNil(try store.pending(session: owner, identity: reopened.identity))
            XCTAssertTrue(transport.requests.isEmpty)
            XCTAssertEqual(store.load(session: try session(8), identity: first.identity), .missing)
        }
    }
    func testAccountEpochAndLogoutInvalidatePreviouslyPreparedLegacyReview() async throws {
        for change in 0...2 {
            var owner: TemplateAuthoringSession? = try session()
            let transport = TemplateAuthoringSyntheticTransport()
            let c = TemplateAuthoringCoordinator(adapter: .init(transport: transport), store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
            c.open(seed: TemplateAuthoringSyntheticFixtures.draft()); c.prepare(.saveDraft)
            let review = try XCTUnwrap(c.review)
            if change == 0 { owner = try session(8) }
            else if change == 1 { owner = try session(epoch: 2) }
            else { owner = nil }
            await c.confirm(review)
            XCTAssertTrue(transport.requests.isEmpty); XCTAssertNil(c.review)
        }
    }
    func testChangingLegacyReviewToLocalMethodInvalidatesOriginalReview() async throws {
        for raw in [6, 7] {
            let owner = try session(), transport = TemplateAuthoringSyntheticTransport()
            let c = TemplateAuthoringCoordinator(adapter: .init(transport: transport), store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
            c.open(seed: TemplateAuthoringSyntheticFixtures.draft()); c.prepare(.saveDraft)
            let review = try XCTUnwrap(c.review)
            var local = c.draft; local.validationMethod = try XCTUnwrap(TemplateAuthoringMethod(rawValue: raw))
            c.change(local); await c.confirm(review)
            XCTAssertTrue(transport.requests.isEmpty); XCTAssertNil(c.review)
        }
    }
    func testReadLeaseNeverGrantsLocalWritesAndRevocationBlocksEveryAttempt() async throws {
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "local-fence", token: "fixture-token"))
        let lease = try TemplateShelfReadApproval(context: context, expiresAt: Date().addingTimeInterval(600))
        let wire = Wire()
        let read = TemplateShelfReadTransport(configuration: try .init(baseURL: base), http: wire, approval: lease, current: { context })
        let adapter = TemplateAuthoringAdapter(shelfReadTransport: read)
        XCTAssertTrue(adapter.canRead); XCTAssertFalse(adapter.canSubmit)
        for revoked in [false, true] {
            if revoked { lease.revoke(); XCTAssertFalse(adapter.canRead) }
            for raw in [0, 5, 6, 7, 8] { for path in ["/api/template/draft", "/api/template/publish"] {
                let request = descriptor(path, method: .number(Double(raw)))
                let outcome = await adapter.submit(request); XCTAssertEqual(outcome, .notSent)
                do { _ = try await read.page(request); XCTFail("Read lease admitted write") } catch {}
            } }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
}
#endif
