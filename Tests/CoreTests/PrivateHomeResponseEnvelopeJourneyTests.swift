import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Real CRUD service/coordinator with in-memory transport and journal only.
/// No network, location, Keychain, production grant or backend writer is invoked.
@available(macOS 14.0, *) @MainActor final class PrivateHomeResponseEnvelopeJourneyTests: XCTestCase {
    private static let methods = ["GET", "PUT", "DELETE"]
    private static func snapshot(version: Int64 = 3, active: Bool = true) -> String {
        if !active { return "{\"version\":\(version),\"status\":\"DELETED\"}" }
        return "{\"version\":\(version),\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"Synthetic\",\"latitude\":12.123456,\"longitude\":45.654321,\"datum\":\"WGS84\"}"
    }
    private static func receipt(_ method: String, id: String = "original", decision: String? = nil, version: Int64 = 4) -> String {
        "{\"requestId\":\"\(id)\",\"decision\":\"\(decision ?? (method == "PUT" ? "SAVED" : "DELETED"))\",\"version\":\(version)}"
    }
    private static func payload(_ method: String) -> String { method == "GET" ? snapshot() : receipt(method) }
    private static func envelope(_ payload: String) -> String { "{\"code\":200,\"data\":\(payload),\"msg\":\"success\"}" }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var bodies: [String: Data] = [:], statuses: [String: Int] = [:]
        var respond: ((URLRequest) throws -> (Data, Int))?
        var afterSend: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); afterSend?()
            if let respond { return try respond(request) }
            let method = request.httpMethod ?? "GET"
            return (bodies[method] ?? Data(PrivateHomeResponseEnvelopeJourneyTests.envelope(PrivateHomeResponseEnvelopeJourneyTests.payload(method)).utf8), statuses[method] ?? 200)
        }
    }
    @MainActor private final class Journal: PrivateHomeSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: PrivateHomeMutation?
        var saves = 0, clears = 0
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() throws -> PrivateHomeMutation? { value }
        func save(_ mutation: PrivateHomeMutation) throws {
            guard value == nil || value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = mutation; saves += 1
        }
        func clear(matching mutation: PrivateHomeMutation) throws {
            guard value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = nil; clears += 1
        }
    }
    @MainActor private final class Session {
        var current: PlayExperienceSession?
        init(_ owner: PlayExperienceSession) { current = owner }
    }
    @MainActor private final class Fixture {
        let owner: PlayExperienceSession, session: Session, wire: Wire, service: PrivateHomeService
        init(enabled: Bool = true) throws {
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic-home", token: "synthetic-token")
            let session = Session(owner), wire = Wire()
            self.owner = owner; self.session = session; self.wire = wire
            service = PrivateHomeService(api: try APIConfiguration(baseURL: URL(string: "https://example.test")!),
                transport: wire, owner: owner, enabled: enabled, current: { session.current })
        }
        func model(_ journal: Journal) -> PrivateHomeCoordinator {
            PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { self.session.current })
        }
    }
    private func point() throws -> PrivateHomePoint { try .parse(latitude: "12.123456", longitude: "45.654321") }
    private func mutation(_ method: String) throws -> PrivateHomeMutation {
        try .init(requestId: "original", expectedVersion: 3, label: method == "PUT" ? "Synthetic" : nil,
            point: method == "PUT" ? point() : nil)
    }
    private func perform(_ method: String, _ f: Fixture) async throws {
        if method == "GET" { _ = try await f.service.load() }
        else { _ = try await f.service.mutate(mutation(method)) }
    }
    private func rejects(_ method: String, _ data: Data, expected: PrivateHomeIssue = .invalid) async throws {
        let f = try Fixture(); f.wire.bodies[method] = data
        do { try await perform(method, f); XCTFail("Ambiguous body must not become a snapshot or receipt") }
        catch { XCTAssertEqual(error as? PrivateHomeIssue, expected) }
        XCTAssertEqual(f.wire.requests.count, 1)
    }

    func testOriginalGetPutDeleteResponsesAndOutgoingPrivacyBoundaryRemainUnchanged() async throws {
        let f = try Fixture()
        for method in Self.methods { try await perform(method, f) }
        XCTAssertEqual(f.wire.requests.compactMap(\.httpMethod), Self.methods)
        for request in f.wire.requests {
            XCTAssertEqual(request.url?.absoluteString, "https://example.test/api/native/home")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), f.owner.token)
            if request.httpMethod == "GET" { XCTAssertNil(request.httpBody) }
            else {
                let original = try mutation(XCTUnwrap(request.httpMethod))
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                XCTAssertEqual(request.httpBody, try encoder.encode(original))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                XCTAssertNil(object["ownerId"]); XCTAssertNil(object["accountId"])
            }
        }
    }

    func testRepeatedEnvelopeCodeAndDataFailForEveryCrudMethod() async throws {
        for method in Self.methods {
            let value = Self.payload(method)
            for extra in [#""code":200,"code":200"#, #""code":403,"code":200"#] {
                try await rejects(method, Data("{\(extra),\"data\":\(value)}".utf8))
            }
            try await rejects(method, Data("{\"code\":200,\"data\":\(value),\"data\":\(value)}".utf8))
        }
    }

    func testEveryOriginalReceiptFieldRejectsDuplicateEvenIdenticalDeclarations() async throws {
        for method in ["PUT", "DELETE"] {
            let fields = [#""requestId":"original""#, "\"decision\":\"\(method == "PUT" ? "SAVED" : "DELETED")\"", #""version":4"#]
            for field in fields {
                let value = Self.payload(method).replacingOccurrences(of: field, with: field + "," + field)
                try await rejects(method, Data(Self.envelope(value).utf8))
            }
        }
    }

    func testEveryPrivateSnapshotFieldRejectsDuplicateBeforeItCanBePresented() async throws {
        for field in [#""version":3"#, #""status":"ACTIVE""#, #""changedAt":1"#, #""effectiveAt":1"#,
                      #""label":"Synthetic""#, #""latitude":12.123456"#, #""longitude":45.654321"#, #""datum":"WGS84""#] {
            let value = Self.snapshot().replacingOccurrences(of: field, with: field + "," + field)
            try await rejects("GET", Data(Self.envelope(value).utf8))
        }
    }

    func testEscapedAliasesStillConflictButOneEscapedKeyRemainsValid() async throws {
        let value = Self.receipt("PUT")
        try await rejects("PUT", Data("{\"code\":200,\"\\u0063ode\":200,\"data\":\(value)}".utf8))
        let alias = value.replacingOccurrences(of: #""requestId":"original""#, with: #""requestId":"original","\u0072equestId":"original""#)
        try await rejects("PUT", Data(Self.envelope(alias).utf8))
        let f = try Fixture(); f.wire.bodies["PUT"] = Data(Self.envelope(value.replacingOccurrences(of: "requestId", with: "\\u0072equestId")).utf8)
        let receipt = try await f.service.mutate(mutation("PUT")); XCTAssertEqual(receipt.requestId, "original")
    }

    func testIgnoredExtensionCannotHideNestedDuplicateKeys() async throws {
        for method in Self.methods {
            let value = String(Self.payload(method).dropLast()) + #", "future":{"items":[{"state":true,"state":false}]}}"#
            try await rejects(method, Data(Self.envelope(value).utf8))
        }
    }

    func testUniqueUnknownFieldsUnicodeAndPreciseCoordinatesStayCompatible() async throws {
        let f = try Fixture()
        for method in Self.methods {
            let value = String(Self.payload(method).dropLast()) + #", "future":{"text":"仅为测试","items":[null,true,false,123456789012345678901234567890,1.1234567890123456789]}}"#
            f.wire.bodies[method] = Data(Self.envelope(value).utf8)
            try await perform(method, f)
        }
        let home = try await f.service.load()
        XCTAssertEqual(home.latitude, Decimal(string: "12.123456")); XCTAssertEqual(home.longitude, Decimal(string: "45.654321"))
    }

    func testDeletedHomeAndMaximumInt64VersionRemainReadableWithoutNarrowing() async throws {
        let f = try Fixture(); f.wire.bodies["GET"] = Data(Self.envelope(Self.snapshot(version: Int64.max, active: false)).utf8)
        let home = try await f.service.load(); XCTAssertEqual(home.version, Int64.max); XCTAssertEqual(home.status, .deleted)
        let request = try PrivateHomeMutation(requestId: "original", expectedVersion: Int64.max - 1)
        f.wire.bodies["DELETE"] = Data(Self.envelope(Self.receipt("DELETE", version: Int64.max)).utf8)
        let receipt = try await f.service.mutate(request); XCTAssertEqual(receipt.version, Int64.max)
    }

    func testAbsentNullAndBusinessFailureCannotBecomeCrudSuccess() async throws {
        for method in Self.methods {
            for raw in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":409,"msg":"PRIVATE_HOME_REQUEST_ID_CONFLICT"}"#] {
                try await rejects(method, Data(raw.utf8), expected: .unavailable)
            }
        }
    }

    func testMalformedNonObjectTrailingAndInvalidUtf8FailBeforeTypedDecoding() async throws {
        for method in Self.methods {
            for raw in ["[]", "null", "[{}]", "{\"code\":200,\"data\":", Self.envelope(Self.payload(method)) + "{}"] {
                try await rejects(method, Data(raw.utf8))
            }
            var bytes = Data(Self.envelope(Self.payload(method)).utf8); bytes.append(0xff)
            try await rejects(method, bytes)
        }
    }

    func testExisting32768ByteLimitStillRunsBeforeTheParser() async throws {
        for method in Self.methods {
            let base = Self.envelope(Self.payload(method)), f = try Fixture()
            let boundary = Data((base + String(repeating: " ", count: 32_768 - base.utf8.count)).utf8)
            f.wire.bodies[method] = boundary; try await perform(method, f)
            try await rejects(method, boundary + Data([32]), expected: .unavailable)
        }
    }

    func testSharedDepthAndExponentBoundsApplyWithoutChangingTheParser() async throws {
        for extensionValue in [String(repeating: "[", count: 129) + "null" + String(repeating: "]", count: 129), "1e1000000000"] {
            let value = String(Self.receipt("PUT").dropLast()) + ",\"future\":" + extensionValue + "}"
            try await rejects("PUT", Data(Self.envelope(value).utf8))
        }
        let f = try Fixture()
        let value = String(Self.receipt("PUT").dropLast()) + ",\"future\":" + String(repeating: "[", count: 64) + "null" + String(repeating: "]", count: 64) + "}"
        f.wire.bodies["PUT"] = Data(Self.envelope(value).utf8); try await perform("PUT", f)
    }

    func testNon2xxStillMapsToUnavailableBeforeInspectingAnyBody() async throws {
        for method in Self.methods {
            for status in [199, 301, 400, 401, 403, 409, 503] {
                let f = try Fixture(); f.wire.statuses[method] = status; f.wire.bodies[method] = Data([0xff])
                do { try await perform(method, f); XCTFail() }
                catch { XCTAssertEqual(error as? PrivateHomeIssue, .unavailable) }
            }
        }
    }

    func testDisabledAndStaleSessionDoNotDispatchAndPostSendOwnerCheckStillWins() async throws {
        let disabled = try Fixture(enabled: false)
        do { try await perform("GET", disabled); XCTFail() }
        catch { XCTAssertEqual(error as? PrivateHomeIssue, .disabled) }
        XCTAssertTrue(disabled.wire.requests.isEmpty)
        let stale = try Fixture(); stale.session.current = nil
        do { try await perform("GET", stale); XCTFail() }
        catch { XCTAssertEqual(error as? PrivateHomeIssue, .staleSession) }
        XCTAssertTrue(stale.wire.requests.isEmpty)
        let f = try Fixture(); f.wire.afterSend = { f.session.current = nil }
        f.wire.bodies["PUT"] = Data(#"{"code":200,"code":200}"#.utf8)
        do { try await perform("PUT", f); XCTFail() }
        catch { XCTAssertEqual(error as? PrivateHomeIssue, .staleSession) }
        XCTAssertEqual(f.wire.requests.count, 1)
    }

    func testAmbiguousPutAndDeleteStayUnknownAcrossGetAndRecreationUntilExactRetry() async throws {
        for method in ["PUT", "DELETE"] {
            let f = try Fixture(), journal = Journal(f.owner), first = f.model(journal)
            var ambiguous = true
            // Start from version 3, active for both operations; later current reads independently report 4.
            await first.load()
            if method == "PUT" { first.prepareSet(label: "Synthetic", point: try point()) } else { first.prepareDelete() }
            let original = try XCTUnwrap(first.review)
            f.wire.respond = { request in
                if request.httpMethod == "GET" { return (Data(Self.envelope(Self.snapshot(version: 4, active: method == "PUT")).utf8), 200) }
                let sent = try JSONDecoder().decode(PrivateHomeMutation.self, from: XCTUnwrap(request.httpBody)); XCTAssertEqual(sent, original)
                let receipt = Self.receipt(method, id: original.requestId)
                let raw = ambiguous ? "{\"code\":200,\"data\":\(receipt),\"data\":\(receipt)}" : Self.envelope(receipt)
                return (Data(raw.utf8), 200)
            }
            await first.confirm()
            XCTAssertEqual(first.phase, .unknown); XCTAssertEqual(first.issue, .unknownOutcome); XCTAssertNil(first.decision)
            XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clears, 0); XCTAssertEqual(journal.saves, 1)
            await first.load(); XCTAssertEqual(first.phase, .unknown); XCTAssertFalse(first.canEdit); XCTAssertEqual(journal.value, original)
            first.invalidate(); let resumed = f.model(journal)
            await resumed.load(); XCTAssertEqual(resumed.phase, .unknown); XCTAssertTrue(resumed.canRetry)
            XCTAssertEqual(f.wire.requests.filter { $0.httpMethod != "GET" }.count, 1)
            ambiguous = false; await resumed.retryExact()
            XCTAssertNil(journal.value); XCTAssertEqual(journal.clears, 1); XCTAssertEqual(journal.saves, 1)
            XCTAssertEqual(resumed.decision, method == "PUT" ? .saved : .deleted); XCTAssertEqual(resumed.home?.version, 4)
            XCTAssertEqual(resumed.phase, .ready); XCTAssertTrue(resumed.canEdit)
            let writes = f.wire.requests.filter { $0.httpMethod != "GET" }
            XCTAssertEqual(writes.count, 2); XCTAssertEqual(writes[0].httpBody, writes[1].httpBody)
        }
    }

    func testAmbiguousGetBlocksEditingAndCannotAuthorizeAnotherMutation() async throws {
        let f = try Fixture(), journal = Journal(f.owner), model = f.model(journal)
        f.wire.bodies["GET"] = Data(Self.envelope(Self.snapshot().replacingOccurrences(of: #""status":"ACTIVE""#, with: #""status":"DELETED","status":"ACTIVE""#)).utf8)
        await model.load(); XCTAssertEqual(model.phase, .blocked); XCTAssertNil(model.home); XCTAssertFalse(model.canEdit)
        model.prepareSet(label: "Must not stage", point: try point()); model.prepareDelete(); await model.confirm()
        XCTAssertNil(model.review); XCTAssertNil(journal.value); XCTAssertEqual(journal.saves, 0)
        XCTAssertEqual(f.wire.requests.map(\.httpMethod), ["GET"])
    }

    func testValidHistoricalDenialsStillSettleButDoNotBecomeSuccessfulWrites() async throws {
        for (decision, version) in [("VERSION_CONFLICT", Int64(5)), ("HOME_CHANGE_COOLDOWN", Int64(3)), ("PLACE_NOT_ALLOWED", Int64(3))] {
            // PLACE_NOT_ALLOWED remains a client-contract compatibility case, not a claim that current writer produces it.
            let f = try Fixture(), journal = Journal(f.owner), model = f.model(journal), original = try mutation("PUT")
            journal.value = original
            f.wire.bodies["PUT"] = Data(Self.envelope(Self.receipt("PUT", decision: decision, version: version)).utf8)
            f.wire.bodies["GET"] = Data(Self.envelope(Self.snapshot(version: version)).utf8)
            await model.load(); await model.retryExact()
            XCTAssertNil(journal.value); XCTAssertEqual(journal.clears, 1); XCTAssertEqual(model.decision?.rawValue, decision)
            XCTAssertEqual(model.phase, .ready); XCTAssertNil(model.review); XCTAssertEqual(journal.saves, 0)
            XCTAssertEqual(f.wire.requests.filter { $0.httpMethod == "PUT" }.count, 1)
        }
    }

    func testDuplicateDenialCannotClearPendingEvenWhenOneValueWouldValidate() async throws {
        let f = try Fixture(), journal = Journal(f.owner), model = f.model(journal), original = try mutation("PUT")
        journal.value = original; await model.load()
        let value = Self.receipt("PUT", decision: "HOME_CHANGE_COOLDOWN", version: 3)
            .replacingOccurrences(of: #""decision":"HOME_CHANGE_COOLDOWN""#, with: #""decision":"HOME_CHANGE_COOLDOWN","decision":"PLACE_NOT_ALLOWED""#)
        f.wire.bodies["PUT"] = Data(Self.envelope(value).utf8); await model.retryExact()
        XCTAssertEqual(model.phase, .unknown); XCTAssertNil(model.decision); XCTAssertEqual(journal.value, original)
        XCTAssertEqual(journal.clears, 0); XCTAssertEqual(journal.saves, 0); XCTAssertFalse(model.canEdit)
        XCTAssertEqual(f.wire.requests.filter { $0.httpMethod == "PUT" }.count, 1)
    }
}
