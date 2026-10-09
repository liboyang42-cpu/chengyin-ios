import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ExploreCompletionReadTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player", token: String = "synthetic-seven",
                         namespace: String = "completion-fixture", market: RegionalMarket = .china, baseURL: URL? = nil) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: baseURL ?? base, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    private func order(_ extra: [String: Any] = [:]) throws -> ProfileOrder {
        var value: [String: Any] = ["id": 41, "memberId": 7, "purchaseKind": 3, "paymentStatus": 2, "registrationStatus": 2]
        value.merge(extra) { _, new in new }
        return try JSONDecoder().decode(ProfileOrder.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func target(_ extra: [String: Any] = [:]) throws -> ExploreCompletionTarget {
        try XCTUnwrap(ExploreCompletionTarget(order: order(extra), requestedID: 41, accountID: 7))
    }
    private func body() -> [String: Any] {
        ["registrationId": 41, "topicId": 9, "completed": false, "requiredChapterCount": 2, "redeemedChapterCount": 1,
         "stamps": [["chapterId": 10, "title": "Synthetic chapter", "collected": true, "obtainedAt": "2026-10-09 10:00:00"],
                    ["chapterId": 11, "collected": false]],
         "awards": ["credited": false, "points": NSNull(), "earnedXp": NSNull(), "couponGranted": NSNull(), "items": []],
         "revisit": ["clubId": NSNull(), "clubLeaderMemberId": NSNull(), "followed": false, "joined": false, "nextEdition": NSNull()]]
    }
    private func decode(_ body: [String: Any]) throws -> ExploreCompletionSnapshot {
        try JSONDecoder().decode(ExploreCompletionSnapshot.self, from: JSONSerialization.data(withJSONObject: body))
    }
    private func envelope(_ body: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 200, "data": body])
    }
    private final class Wire: HTTPTransport {
        var response = Data()
        var status = 200
        var requests: [URLRequest] = []
        var beforeReply: (() -> Void)?
        var failure: Error?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); await Task.yield(); beforeReply?()
            if let failure { throw failure }
            return (response, status)
        }
    }
    private func reader(_ wire: Wire, approval: ExploreCompletionReadApproval? = nil,
                        current: @escaping () -> RuntimeDependencyContext?,
                        unauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) throws -> ExploreCompletionSessionReader {
        .init(configuration: try APIConfiguration(baseURL: base), http: wire, approval: approval, current: current, onUnauthorized: unauthorized)
    }
    private func form(_ fields: [String: String], path: String = ExploreCompletionReadRoute.path) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: fields,
                                              token: "synthetic-seven", boundary: "Completion")
    }
    func testPurchaseKindProjectionPreservesUnknownAndDoesNotInferProduct() throws {
        XCTAssertEqual(try order(["purchaseKind": "3"]).purchaseKind, 3)
        XCTAssertEqual(try order(["purchaseKind": 99]).purchaseKind, 99)
        for value in [NSNull(), "03", true, ["kind": 3]] as [Any] {
            let row = try order(["purchaseKind": value, "cmsTopic": ["productType": 2], "ticketId": 8])
            XCTAssertNil(row.purchaseKind)
            XCTAssertNil(ExploreCompletionTarget(order: row, requestedID: 41, accountID: 7))
        }
    }
    func testTargetRequiresExactOwnedExploreRegistrationAndPaidUiGate() throws {
        for extra in [["memberId": 8], ["purchaseKind": 1], ["purchaseKind": 2], ["purchaseKind": 0], ["paymentStatus": 1, "registrationStatus": 1]] {
            XCTAssertNil(ExploreCompletionTarget(order: try order(extra), requestedID: 41, accountID: 7))
        }
        for id in [0, -1, 42] { XCTAssertNil(ExploreCompletionTarget(order: try order(), requestedID: id, accountID: 7)) }
        XCTAssertNotNil(ExploreCompletionTarget(order: try order(["paymentStatus": 2, "registrationStatus": 4]), requestedID: 41, accountID: 7))
        XCTAssertNotNil(ExploreCompletionTarget(order: try order(["paymentStatus": 1, "registrationStatus": 2]), requestedID: 41, accountID: 7))
    }
    func testNullableAwardFactsStayUnknownWhileActualZeroIsRetained() throws {
        let missing = try decode(body())
        XCTAssertNil(missing.awards.points); XCTAssertNil(missing.awards.earnedXP); XCTAssertNil(missing.awards.couponGranted)
        XCTAssertNil(missing.revisit?.nextEdition); XCTAssertNil(missing.revisit?.clubID)
        var value = body(); value["awards"] = ["credited": true, "points": 0, "earnedXp": 0, "couponGranted": false,
                                              "items": [["kind": "POINTS", "amount": 0]]]
        let zero = try decode(value)
        XCTAssertEqual(zero.awards.points, 0); XCTAssertEqual(zero.awards.items[0].amount, 0)
        XCTAssertEqual(zero.awards.couponGranted, false)
    }
    func testCollectedAndCompletionFlagsAreNotInferredFromCountsOrAwards() throws {
        let result = try decode(body())
        XCTAssertFalse(result.completed); XCTAssertTrue(result.stamps[0].collected); XCTAssertFalse(result.stamps[1].collected)
        XCTAssertNil(result.stamps[1].obtainedAt)
        var complete = body(); complete["completed"] = true
        let value = try decode(complete); XCTAssertTrue(value.completed); XCTAssertFalse(value.awards.credited)
    }
    func testMissingTopicShellIsDistinctFromZeroProgressCompletion() throws {
        var value = body(); value["topicId"] = NSNull(); value["requiredChapterCount"] = 0
        value["redeemedChapterCount"] = 0; value["stamps"] = []
        let empty = try decode(value); XCTAssertFalse(empty.hasTopic); XCTAssertFalse(empty.completed)
        XCTAssertTrue(empty.stamps.isEmpty); XCTAssertNil(empty.awards.points)
    }
    func testStrictRecordIdentityBooleanCountsAndCollectionShapes() throws {
        for (key, value) in [("registrationId", 0), ("registrationId", "41"), ("topicId", 0), ("completed", "true"),
                             ("requiredChapterCount", -1), ("requiredChapterCount", 2_001), ("redeemedChapterCount", 3),
                             ("stamps", NSNull()), ("awards", [])] as [(String, Any)] {
            var invalid = body(); invalid[key] = value; XCTAssertThrowsError(try decode(invalid), key)
        }
        var invalid = body(); invalid["stamps"] = [["chapterId": -1, "collected": true]]; XCTAssertThrowsError(try decode(invalid))
        invalid["stamps"] = [["chapterId": 1, "collected": 1]]; XCTAssertThrowsError(try decode(invalid))
    }
    func testBoundedCollectionsTextAndTypedOptionalFields() throws {
        var invalid = body(); invalid["stamps"] = Array(repeating: ["chapterId": 1, "collected": false] as [String: Any], count: 2_001)
        XCTAssertThrowsError(try decode(invalid))
        invalid = body(); invalid["awards"] = ["credited": false, "items": [["kind": "BADGE", "title": String(repeating: "x", count: 4_097)]]]
        XCTAssertThrowsError(try decode(invalid))
        invalid["awards"] = ["credited": false, "points": "0", "items": []]; XCTAssertThrowsError(try decode(invalid))
        invalid["awards"] = ["credited": false, "couponGranted": 0, "items": []]; XCTAssertThrowsError(try decode(invalid))
    }
    func testDateScalarsHaveNoSecondsMagnitudeGuessAndUnknownKindsStayLiteral() throws {
        var value = body(); value["stamps"] = [["chapterId": 10, "collected": true, "obtainedAt": 1_700_000_000_000]]
        value["awards"] = ["credited": true, "items": [["kind": "FUTURE_REWARD", "amount": -2, "grantedAt": "2026-10-09T10:00:00+08:00"]]]
        let result = try decode(value)
        XCTAssertEqual(result.stamps[0].obtainedAt, .milliseconds(1_700_000_000_000))
        XCTAssertEqual(result.awards.items[0].kind, "FUTURE_REWARD"); XCTAssertEqual(result.awards.items[0].amount, -2)
        for raw in ["true", "-1", "253402300800000", "1.5", "{}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(ExploreCompletionTime.self, from: Data(raw.utf8)))
        }
    }
    func testRevisitAndNextEditionRequirePositiveTypedIdentifiers() throws {
        var value = body(); value["revisit"] = ["clubId": 7, "clubName": "Synthetic club", "clubLeaderMemberId": 70,
                                              "followed": true, "joined": false, "nextEdition": ["topicId": 88, "name": "Next synthetic edition"]]
        let result = try decode(value); XCTAssertEqual(result.revisit?.nextEdition?.topicID, 88)
        XCTAssertTrue(result.revisit?.followed == true); XCTAssertTrue(result.revisit?.joined == false)
        value["revisit"] = ["clubId": 0, "followed": false, "joined": false]; XCTAssertThrowsError(try decode(value))
        value["revisit"] = ["clubId": 7, "followed": false, "joined": false, "nextEdition": ["topicId": -1]]; XCTAssertThrowsError(try decode(value))
    }
    func testExactIdOnlyMultipartRouteRejectsAdjacentRoutesExtraKeysAndDuplicates() throws {
        XCTAssertEqual(ExploreCompletionReadRoute(request: try form(["id": "41"]), baseURL: base)?.registrationID, 41)
        for fields in [[:], ["id": "0"], ["id": "041"], ["id": "-1"], ["id": "41", "memberId": "7"], ["id": "41", "topicId": "9"]] {
            XCTAssertNil(ExploreCompletionReadRoute(request: try form(fields), baseURL: base))
        }
        for path in ["api/registration/info", "api/registration/cancel", "api/user/follow/action", "api/club/join"] {
            XCTAssertNil(ExploreCompletionReadRoute(request: try form(["id": "41"], path: path), baseURL: base))
        }
        var request = try form(["id": "41"]); let raw = String(data: request.httpBody!, encoding: .utf8)!
        request.httpBody = Data(raw.replacingOccurrences(of: "--Completion--\r\n", with: "--Completion\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n42\r\n--Completion--\r\n").utf8)
        XCTAssertNil(ExploreCompletionReadRoute(request: request, baseURL: base))
    }
    func testRouteRejectsQueryFragmentMethodsEncodingAndBodyStreams() throws {
        let request = try form(["id": "41"])
        for method in ["GET", "PUT", "DELETE"] { var value = request; value.httpMethod = method; XCTAssertNil(ExploreCompletionReadRoute(request: value, baseURL: base)) }
        for suffix in ["?id=41", "#fragment", "/"] { var value = request; value.url = URL(string: request.url!.absoluteString + suffix); XCTAssertNil(ExploreCompletionReadRoute(request: value, baseURL: base)) }
        var value = request; value.httpBodyStream = InputStream(data: Data()); XCTAssertNil(ExploreCompletionReadRoute(request: value, baseURL: base))
        value = request; value.setValue("application/json", forHTTPHeaderField: "Content-Type"); XCTAssertNil(ExploreCompletionReadRoute(request: value, baseURL: base))
        value = request; value.setValue("text/plain", forHTTPHeaderField: "Accept"); XCTAssertNil(ExploreCompletionReadRoute(request: value, baseURL: base))
    }
    func testIndependentApprovalEveryContextDimensionAndUnicodeIdentity() throws {
        let source = try context(namespace: "\u{00E9}"); let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        for other in [try context(account: 8, namespace: "\u{00E9}"), try context(epoch: 2, namespace: "\u{00E9}"),
                      try context(role: "merchant", namespace: "\u{00E9}"), try context(token: "different", namespace: "\u{00E9}"),
                      try context(namespace: "e\u{0301}"), try context(namespace: "\u{00E9}", market: .unitedStates),
                      try context(namespace: "\u{00E9}", baseURL: URL(string: "https://other.test/native")!)] {
            XCTAssertFalse(approval.matches(other))
        }
        XCTAssertTrue(approval.matches(source))
    }
    func testLeaseExpiryRevocationAndInvalidIssuance() throws {
        let source = try context(); let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        XCTAssertFalse(approval.matches(source, now: approval.expiresAt))
        approval.expireIfNeeded(now: approval.expiresAt)
        XCTAssertTrue(approval.isRevoked); XCTAssertFalse(approval.matches(source, now: Date.distantPast))
        XCTAssertThrowsError(try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(-1)))
        XCTAssertThrowsError(try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(90_000)))
        XCTAssertThrowsError(try ExploreCompletionReadApproval(context: context(market: .unitedStates), expiresAt: Date().addingTimeInterval(600)))
    }
    func testDefaultOffAndDifferentAccountBlockBeforeTransport() async throws {
        let source = try context(), wire = Wire(); wire.response = try envelope(body())
        var contextReads = 0
        let closed = try reader(wire, current: { contextReads += 1; return source })
        XCTAssertFalse(closed.isConfigured); XCTAssertNil(closed.identity)
        do { _ = try await closed.read(target()); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(contextReads, 0)
        let other = try context(account: 8), approval = try ExploreCompletionReadApproval(context: other, expiresAt: Date().addingTimeInterval(600))
        let scoped = try reader(wire, approval: approval, current: { other })
        do { _ = try await scoped.read(target()); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testApprovedReadUsesOnlyIdAndReturnsMatchingTypedFacts() async throws {
        let source = try context(), wire = Wire(); wire.response = try envelope(body())
        let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { source }); let result = try await client.read(target())
        XCTAssertEqual(result.registrationID, 41); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(ExploreCompletionReadRoute(request: wire.requests[0], baseURL: base)?.registrationID, 41)
        XCTAssertEqual(wire.requests[0].value(forHTTPHeaderField: "Authorization"), source.session.token)
    }
    func testWrongResponseIdAndMalformedSuccessNeverBecomeEmptyRecords() async throws {
        let source = try context(), wire = Wire(), approval = try ExploreCompletionReadApproval(context: context(), expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { source })
        var wrong = body(); wrong["registrationId"] = 42; wire.response = try envelope(wrong)
        do { _ = try await client.read(target()); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        for json in ["{}", "[]", "{\"code\":200,\"data\":null}", "{\"code\":200,\"data\":{}}"] {
            wire.response = Data(json.utf8)
            do { _ = try await client.read(target()); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testResponseSizeIsBounded() async throws {
        let source = try context(), wire = Wire(), approval = try ExploreCompletionReadApproval(context: context(), expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { source })
        wire.response = Data(repeating: 32, count: ExploreCompletionSessionReader.maximumResponseBytes + 1)
        do { _ = try await client.read(target()); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testExplicit401And403DifferFromCode500LoginProse() async throws {
        let source = try context(), wire = Wire(); var unauthorized = 0
        let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { source }, unauthorized: { _ in unauthorized += 1 })
        for (http, code, expected) in [(401, 200, APIError.unauthorized), (403, 200, .httpStatus(403)), (200, 401, .unauthorized), (200, 403, .businessCode(403))] {
            wire.status = http; wire.response = Data("{\"code\":\(code),\"msg\":\"synthetic\",\"data\":[]}".utf8)
            do { _ = try await client.read(target()); XCTFail() } catch { XCTAssertEqual(error as? APIError, expected) }
        }
        XCTAssertEqual(unauthorized, 2)
        wire.status = 200; wire.response = Data("{\"code\":500,\"msg\":\"请先登录\",\"data\":[]}".utf8)
        do { _ = try await client.read(target()); XCTFail() } catch { XCTAssertEqual(error as? ExploreCompletionFailure, .rejected(code: 500, message: "请先登录")) }
        XCTAssertEqual(unauthorized, 2)
    }
    func testOwnerChangeAtSuccessOr401ReceiptCancelsWithoutSigningOutNewOwner() async throws {
        let initial = try context(), later = try context(account: 8); var current = initial; var unauthorized = 0
        let wire = Wire(); wire.response = try envelope(body())
        let approval = try ExploreCompletionReadApproval(context: initial, expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { current }, unauthorized: { _ in unauthorized += 1 })
        wire.beforeReply = { current = later }
        do { _ = try await client.read(target()); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        current = initial; wire.status = 401
        do { _ = try await client.read(target()); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(unauthorized, 0)
    }
    func testLeaseRevocationAndOriginRetirementCancelInFlightRead() async throws {
        let source = try context(), wire = Wire(); wire.response = try envelope(body())
        let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { source })
        wire.beforeReply = { approval.revoke() }
        do { _ = try await client.read(target()); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(client.identity)
        let fresh = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        let second = try reader(wire, approval: fresh, current: { source }); var current = true
        wire.beforeReply = { current = false }
        do { _ = try await second.read(target(), isCurrent: { current }); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testStaleTransportFailureCannotSurfaceAfterOwnerChange() async throws {
        let initial = try context(); var current: RuntimeDependencyContext? = initial
        let wire = Wire(); wire.failure = APIError.unauthorized; wire.beforeReply = { current = nil }; var unauthorized = 0
        let approval = try ExploreCompletionReadApproval(context: initial, expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { current }, unauthorized: { _ in unauthorized += 1 })
        do { _ = try await client.read(target()); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(unauthorized, 0)
    }
    func testModelClearsFactsOnRefreshFailureAndImmediatelyHidesRevokedIdentity() async throws {
        let source = try context(), wire = Wire(); wire.response = try envelope(body())
        let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { source }), model = ExploreCompletionReadModel(reader: client)
        let identity = try XCTUnwrap(client.identity), request = try target(), presentation = model.beginPresentation()
        await model.load(request, expectedIdentity: identity, presentationID: presentation); XCTAssertNotNil(model.value)
        wire.status = 503; await model.load(request, expectedIdentity: identity, presentationID: presentation)
        XCTAssertNil(model.value); XCTAssertNotNil(model.error)
        wire.status = 200; await model.load(request, expectedIdentity: identity, presentationID: presentation); XCTAssertNotNil(model.value)
        approval.revoke(); XCTAssertNil(model.value)
    }
    func testModelInvalidationRetiresLateCompletionAndBlocksWrongExpectedIdentity() async throws {
        let source = try context(), wire = Wire(); wire.response = try envelope(body())
        let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { source }), model = ExploreCompletionReadModel(reader: client)
        let identity = try XCTUnwrap(client.identity), request = try target(), presentation = model.beginPresentation()
        wire.beforeReply = { model.invalidate() }
        await model.load(request, expectedIdentity: identity, presentationID: presentation); XCTAssertNil(model.value); XCTAssertNil(model.error)
        let wrong = ExploreCompletionReadIdentity(readerScope: UUID(), approvalRevision: identity.approvalRevision, accountID: 7, epoch: 1)
        let prior = wire.requests.count; await model.load(request, expectedIdentity: wrong, presentationID: presentation)
        XCTAssertEqual(wire.requests.count, prior); XCTAssertNil(model.value)
    }
    func testOriginRetiredBeforeDispatchMakesNoRequest() async throws {
        let source = try context(), wire = Wire(); wire.response = try envelope(body())
        let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { source })
        do { _ = try await client.read(target(), isCurrent: { false }); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testQueuedRetryAfterDepartureWithSameAuthorityMakesNoRequestOrFacts() async throws {
        let source = try context(), wire = Wire(); wire.response = try envelope(body())
        let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { source }), model = ExploreCompletionReadModel(reader: client)
        let identity = try XCTUnwrap(client.identity), request = try target(), captured = model.beginPresentation()
        // Like Retry, capture the ticket before its asynchronous body gets an executor turn.
        let queuedRetry = { await model.load(request, expectedIdentity: identity, presentationID: captured) }
        model.endPresentation()
        XCTAssertEqual(client.identity, identity); XCTAssertTrue(client.isConfigured)
        await queuedRetry()
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertNil(model.value); XCTAssertNil(model.error)
        XCTAssertFalse(model.isLoading); XCTAssertNil(model.presentationID)
    }
    func testOldQueuedRetryCannotDispatchOrClearNewPresentationFactsAfterReopen() async throws {
        let source = try context(), wire = Wire(); wire.response = try envelope(body())
        let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { source }), model = ExploreCompletionReadModel(reader: client)
        let identity = try XCTUnwrap(client.identity), request = try target(), old = model.beginPresentation()
        model.endPresentation(); let fresh = model.beginPresentation()
        XCTAssertNotEqual(old, fresh)
        await model.load(request, expectedIdentity: identity, presentationID: fresh)
        XCTAssertNotNil(model.value); XCTAssertEqual(wire.requests.count, 1)
        await model.load(request, expectedIdentity: identity, presentationID: old)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertNotNil(model.value)
        XCTAssertEqual(model.presentationID, fresh); XCTAssertFalse(model.isLoading)
    }
    func testDepartureAtReceiptRetiresFactsWithoutChangingAuthority() async throws {
        let source = try context(), wire = Wire(); wire.response = try envelope(body())
        let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        let client = try reader(wire, approval: approval, current: { source }), model = ExploreCompletionReadModel(reader: client)
        let identity = try XCTUnwrap(client.identity), request = try target(), captured = model.beginPresentation()
        wire.beforeReply = { model.endPresentation() }
        await model.load(request, expectedIdentity: identity, presentationID: captured)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(client.identity, identity)
        XCTAssertNil(model.value); XCTAssertNil(model.error); XCTAssertFalse(model.isLoading)
    }
    private final class SuspendedWire: HTTPTransport {
        var pending: [CheckedContinuation<(Data, Int), Error>] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            try await withCheckedThrowingContinuation { pending.append($0) }
        }
    }
    func testConcurrentRefreshKeepsOnlyNewestAcceptedResponse() async throws {
        let source = try context(), wire = SuspendedWire()
        let approval = try ExploreCompletionReadApproval(context: source, expiresAt: Date().addingTimeInterval(600))
        let client = ExploreCompletionSessionReader(configuration: try APIConfiguration(baseURL: base), http: wire,
                                                    approval: approval, current: { source })
        let model = ExploreCompletionReadModel(reader: client), request = try target(), identity = try XCTUnwrap(client.identity)
        let presentation = model.beginPresentation()
        let first = Task { await model.load(request, expectedIdentity: identity, presentationID: presentation) }
        for _ in 0..<100 where wire.pending.isEmpty { await Task.yield() }
        guard wire.pending.count == 1 else { first.cancel(); XCTFail("First read did not suspend"); return }
        let second = Task { await model.load(request, expectedIdentity: identity, presentationID: presentation) }
        for _ in 0..<100 where wire.pending.count < 2 { await Task.yield() }
        guard wire.pending.count == 2 else {
            wire.pending[0].resume(throwing: CancellationError()); first.cancel(); second.cancel(); XCTFail("Second read did not suspend"); return
        }
        var newest = body(); newest["completed"] = true; newest["redeemedChapterCount"] = 2
        wire.pending[1].resume(returning: (try envelope(newest), 200)); await second.value
        wire.pending[0].resume(returning: (try envelope(body()), 200)); await first.value
        XCTAssertTrue(model.value?.completed == true); XCTAssertEqual(model.value?.redeemedChapterCount, 2)
        XCTAssertFalse(model.isLoading); XCTAssertNil(model.error)
    }
}
