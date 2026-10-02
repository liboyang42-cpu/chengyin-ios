import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class ClubGovernanceContractTests: XCTestCase {
    let scope = ClubGovernanceFixtures.scope
    func testExplicitInactiveAccessIsDeniedEvenWithoutClubProjection() {
        XCTAssertThrowsError(try ClubGovernancePermissions(value: .object(["active": .bool(false)]), scope: scope)) { XCTAssertEqual($0 as? ClubGovernanceFailure, .forbidden) }
    }
    func testSevenSourcePersonasUsePermissionsNotLegacyFlags() throws {
        let personas: [(String, [String], [String], Bool)] = [
            ("owner", ["CLUB_OWNER"], ["club:finance:read"], true),
            ("co-owner", ["CLUB_CO_OWNER"], ["club:activity:manage", "club:member:manage"], false),
            ("operator", ["CLUB_OPERATOR"], ["club:content:manage", "club:notify:send"], false),
            ("legacy administrator", [], [], false),
            ("event lead", ["EVENT_LEAD"], ["club:event:operate", "club:event:checkin"], false),
            ("event check-in", ["EVENT_CHECKIN"], ["club:event:checkin"], false),
            ("member", ["CLUB_MEMBER"], [], false)
        ]
        for (_, roles, permissions, managesRoles) in personas {
            let raw = ClubGovernanceValue.object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array(roles.map(ClubGovernanceValue.string)), "permissions": .array(permissions.map(ClubGovernanceValue.string)), "canManageRoles": .bool(managesRoles), "viewerIsAdmin": .bool(true)])
            let value = try ClubGovernancePermissions(value: raw, scope: scope)
            XCTAssertEqual(value.allows("ROLES", scope: scope), managesRoles)
            XCTAssertEqual(value.allows("club:finance:read", scope: scope), roles.contains("CLUB_OWNER"))
        }
    }
    func testAllReadFixturesSatisfyStrictSchemas() throws {
        for read in ClubGovernanceRead.allCases { XCTAssertNoThrow(try ClubGovernanceValidation.validate(ClubGovernanceFixtures.value(read), operation: read, scope: scope), read.rawValue) }
    }
    func testAllMutationDraftsHaveExactKnownSourceFields() throws {
        for mutation in ClubGovernanceMutation.allCases { XCTAssertNoThrow(try ClubGovernanceFixtures.command(mutation), mutation.rawValue) }
    }
    func testEveryMutationHasConcretePath() {
        XCTAssertEqual(Set(ClubGovernanceMutation.allCases.map(\.path)).count, ClubGovernanceMutation.allCases.count)
        XCTAssertFalse(ClubGovernanceMutation.allCases.contains { $0.path.contains("withdraw") || $0.path.contains("reconcile") })
    }
    func testSourceIDsAreNotInterchangeable() throws {
        XCTAssertEqual(try ClubGovernanceRead.leaderboard.fields(scope: scope), ["id": .integer(81), "sortBy": .string("composite")])
        XCTAssertEqual(try ClubGovernanceRead.editions.fields(scope: scope), ["clubId": .integer(81)])
        XCTAssertEqual(try ClubGovernanceRead.topicOverview.fields(scope: scope), ["id": .string("91")])
        XCTAssertEqual(try ClubGovernanceFixtures.command(.issueGroupCode).fields, ["activityId": .integer(101)])
        XCTAssertEqual(try ClubGovernanceFixtures.command(.retryNotification).fields, ["campaignId": .integer(131)])
    }
    func testActivityNullMustRemainExplicit() throws {
        let club = ClubGovernanceScope(clubID: 81, topicID: 91)
        for read in [ClubGovernanceRead.audienceCounts, .topicStats] { XCTAssertEqual(try read.fields(scope: club)["activityId"], .null) }
        XCTAssertNil(try ClubGovernanceRead.roles.fields(scope: club)["activityId"])
        XCTAssertNil(try ClubGovernanceRead.access.fields(scope: club)["activityId"])
    }
    func testUnknownFieldsAndInvalidScopesCannotEnterRequests() throws {
        XCTAssertThrowsError(try ClubGovernanceRead.customers.fields(scope: scope, options: ["phone": .string("secret")]))
        XCTAssertThrowsError(try ClubGovernanceRead.seriesDetail.fields(scope: .init(clubID: 81)))
        XCTAssertThrowsError(try ClubGovernanceRead.topics.fields(scope: .init(clubID: -1)))
        var values = try ClubGovernanceFixtures.command(.saveTopicSettings).fields.filter { !["clubId", "topicId"].contains($0.key) }
        values["canManage"] = .bool(true)
        XCTAssertThrowsError(try ClubGovernanceCommand(operation: .saveTopicSettings, scope: scope, values: values))
    }
    func testNoLegacyRoleCanGrantGovernance() throws {
        let raw = ClubGovernanceFixtures.json(#"{"active":true,"club":{"id":81},"roleCodes":["CLUB_MEMBER"],"permissions":[],"viewerIsAdmin":true,"isOwner":true,"canManageRoles":false}"#)
        let permissions = try ClubGovernancePermissions(value: raw, scope: scope)
        XCTAssertFalse(permissions.allows("club:member:manage", scope: scope))
        XCTAssertFalse(permissions.allows("OWNER", scope: scope)); XCTAssertFalse(permissions.allows("ROLES", scope: scope))
    }
    func testBadAccessIsNotMisreportedAsExplicitDenial() {
        let raw = ClubGovernanceFixtures.json(#"{"active":1,"club":{"id":81},"permissions":[],"roleCodes":[]}"#)
        XCTAssertThrowsError(try ClubGovernancePermissions(value: raw, scope: scope)) { XCTAssertEqual($0 as? ClubGovernanceFailure, .malformed) }
    }
    func testEventPermissionNeverCrossesEventScope() throws {
        let raw = ClubGovernanceFixtures.json(#"{"active":true,"club":{"id":81},"roleCodes":["CLUB_MEMBER"],"permissions":[],"canManageRoles":false,"eventAccesses":[{"activityId":101,"topicId":91,"roleCodes":["EVENT_CHECKIN"],"permissions":["club:event:checkin"]}]}"#)
        let p = try ClubGovernancePermissions(value: raw, scope: scope)
        XCTAssertTrue(p.allows("club:event:checkin", scope: scope))
        XCTAssertFalse(p.allows("club:event:checkin", scope: .init(clubID: 81, activityID: 102)))
        XCTAssertFalse(p.allows("club:member:list:read", scope: scope)); XCTAssertFalse(p.allows("club:finance:read", scope: scope))
    }
    func testCanManageRolesUsesExplicitServerBoolean() throws {
        let raw = ClubGovernanceFixtures.json(#"{"active":true,"club":{"id":81},"roleCodes":["CLUB_OWNER"],"permissions":[],"canManageRoles":true}"#)
        XCTAssertTrue(try ClubGovernancePermissions(value: raw, scope: scope).allows("ROLES", scope: scope))
    }
    func testRoleAssignmentHasOnlyFourDelegableRoleCodes() throws {
        XCTAssertEqual(ClubGovernancePermissions.assignableClubRoles, ["CLUB_CO_OWNER", "CLUB_OPERATOR"])
        XCTAssertEqual(ClubGovernancePermissions.assignableEventRoles, ["EVENT_LEAD", "EVENT_CHECKIN"])
        for role in ["CLUB_OWNER", "CLUB_MEMBER", "ADMIN", "CLUB_OPERATOR"] {
            XCTAssertThrowsError(try ClubGovernanceCommand(operation: .assignRole, scope: scope, values: ["targetMemberId": .integer(704), "roleCode": .string(role), "requestId": .string("fixed")]))
        }
    }
    func testRoleResponseRejectsCrossScope() throws {
        var raw = ClubGovernanceFixtures.value(.roles).object!
        var assignment = raw["assignments"]!.array![0].object!; assignment["scopeId"] = .integer(999)
        raw["assignments"] = .array([.object(assignment)])
        XCTAssertThrowsError(try ClubGovernanceValidation.validate(.object(raw), operation: .roles, scope: scope))
    }
    func testRosterRejectsPhoneExposureAndMissingBuckets() {
        for text in [#"{"phoneIncluded":true,"registered":[],"waitlist":[],"arrived":[],"noShow":[]}"#, #"{"phoneIncluded":false,"registered":[],"waitlist":[],"arrived":[]}"#] {
            XCTAssertThrowsError(try ClubGovernanceValidation.validate(ClubGovernanceFixtures.json(text), operation: .roster, scope: scope))
        }
    }
    func testRawPhoneCredentialsDroppedRecursively() throws {
        let raw = ClubGovernanceFixtures.json(#"{"total":1,"monthNew":0,"items":[{"memberId":704,"verifiedCount":0,"pendingCount":0,"phone":"secret","phoneText":"Hidden","token":"secret"}]}"#)
        let value = try ClubGovernanceValidation.validate(raw, operation: .customers, scope: scope)
        XCTAssertEqual(value["items"].array![0]["phone"], .null); XCTAssertEqual(value["items"].array![0]["token"], .null)
        XCTAssertEqual(value["items"].array![0]["phoneText"], .string("Hidden"))
    }
    func testUnknownCountsAndMoneyRemainNull() throws {
        let audience = try ClubGovernanceValidation.validate(ClubGovernanceFixtures.value(.audienceCounts), operation: .audienceCounts, scope: scope)
        XCTAssertEqual(audience["counts"]["WAITLIST"], .null)
        XCTAssertEqual(ClubGovernanceFixtures.value(.leaderboard).array![0]["pace"], .null)
        XCTAssertEqual(ClubGovernanceFixtures.value(.customer)["summary"]["paidAmount"], .null)
    }
    func testUnverifiedSettlementAndVoidAreAccepted() throws {
        XCTAssertNoThrow(try ClubGovernanceValidation.validate(ClubGovernanceFixtures.value(.settlement), operation: .settlement, scope: scope))
        let raw = ClubGovernanceFixtures.json(#"{"settledAmountText":"Source total","settledAmountStatus":"verified","unverifiedSettledCount":0,"topics":[{"id":2,"topicId":91,"name":"Void","status":"void","amountStatus":"verified","amountText":"Source amount","originalAmountText":"Source","executedAdjustmentText":"Source","netAmountText":"Source","arrivedText":"Source","paidText":"Source"}]}"#)
        XCTAssertNoThrow(try ClubGovernanceValidation.validate(raw, operation: .settlement, scope: scope))
    }
    func testContradictorySettlementAndDuplicateIDsReject() {
        var object = ClubGovernanceFixtures.value(.settlement).object!; object["unverifiedSettledCount"] = .integer(0)
        XCTAssertThrowsError(try ClubGovernanceValidation.validate(.object(object), operation: .settlement, scope: scope))
        XCTAssertThrowsError(try ClubGovernanceValidation.validate(.array([ClubGovernanceFixtures.value(.seriesDetail), ClubGovernanceFixtures.value(.seriesDetail)]), operation: .series, scope: scope))
    }
    func testCancellationStatusCannotClaimRefundCompletion() throws {
        let receipt = ClubGovernanceFixtures.receipt(.cancelOccurrence)
        XCTAssertEqual(receipt["refundStatus"], .string("ACCEPTED_WITH_MANUAL_REVIEW"))
        var raw = ClubGovernanceFixtures.value(.occurrenceStatus).object!; raw["activityCancelled"] = .bool(true)
        XCTAssertThrowsError(try ClubGovernanceValidation.validate(.object(raw), operation: .occurrenceStatus, scope: scope))
    }
    func testMissingCorrectionVersionCannotBeAssumedZero() throws {
        var value = ClubGovernanceFixtures.value(.roster).object!
        value["registered"] = ClubGovernanceFixtures.json(#"[{"memberId":704,"state":"REGISTERED"}]"#)
        let p = try ClubGovernancePermissions(value: ClubGovernanceFixtures.permissions, scope: scope)
        let snapshot = ClubGovernanceSnapshot(operation: .roster, scope: scope, permissions: p, value: .object(value))
        XCTAssertThrowsError(try ClubGovernanceFixtures.command(.correctAttendance).validateReview(snapshot, accountID: 701))
    }
    func testPlatformBanCannotBeUnbannedByClub() throws {
        var ban = ClubGovernanceFixtures.value(.bans).array![0].object!; ban["sourceType"] = .string("PLATFORM")
        let p = try ClubGovernancePermissions(value: ClubGovernanceFixtures.permissions, scope: scope)
        XCTAssertThrowsError(try ClubGovernanceFixtures.command(.unban).validateReview(.init(operation: .bans, scope: scope, permissions: p, value: .array([.object(ban)])), accountID: 701))
    }
    func testInvalidTagsHoursHashAndBroadcastLengthReject() throws {
        var tags = ClubGovernanceFormDraft(operation: .saveCustomer, scope: scope); tags.text["tags"] = String(repeating: "x", count: 13); XCTAssertThrowsError(try tags.command())
        for input in ["-1", "nan", "infinity", ""] { var draft = ClubGovernanceFormDraft(operation: .reportHours, scope: scope); draft.text["actualHours"] = input; XCTAssertThrowsError(try draft.command()) }
        var hash = ClubGovernanceFormDraft(operation: .submitEvidence, scope: scope); hash.text["evidenceHash"] = "invalid"; XCTAssertThrowsError(try hash.command())
        var notify = ClubGovernanceFormDraft(operation: .sendNotification, scope: scope); notify.text["title"] = String(repeating: "x", count: 81); notify.text["content"] = "content"; XCTAssertThrowsError(try notify.command())
    }
    func testCancellationAndAttendanceReasonSourceLimits() throws {
        for operation in [ClubGovernanceMutation.cancelOccurrence, .correctAttendance] {
            var values = try ClubGovernanceFixtures.command(operation).fields.filter { !["clubId", "activityId", "memberId"].contains($0.key) }
            values["reason"] = .string("x")
            XCTAssertThrowsError(try ClubGovernanceCommand(operation: operation, scope: scope, values: values))
        }
        var values = try ClubGovernanceFixtures.command(.cancelOccurrence).fields.filter { !["clubId", "activityId"].contains($0.key) }
        values["reason"] = .string(String(repeating: "x", count: 256))
        XCTAssertThrowsError(try ClubGovernanceCommand(operation: .cancelOccurrence, scope: scope, values: values))
    }
    func testNoInventedRequestIDForNonIdempotentSource() throws {
        for operation in [ClubGovernanceMutation.hostApply, .updateSeries, .saveTopicSettings, .endTopic, .reportHours, .submitEvidence, .dissolve, .issueGroupCode, .retryNotification] { XCTAssertNil(try ClubGovernanceFixtures.command(operation).fields["requestId"]) }
    }
    func testNotificationPreviewExactChannelAndNullRequestID() throws {
        let fields = try ClubGovernanceRead.notificationPreview.fields(scope: scope, options: ["audienceType": .string("REGISTERED"), "title": .string("Title"), "content": .string("Content")])
        XCTAssertEqual(fields["channel"], .string("IN_APP")); XCTAssertEqual(fields["requestId"], .null)
    }
    func testNotificationPrivacyAndProviderGate() {
        let raw = ClubGovernanceFixtures.json(#"{"recipientCount":8,"phoneIncluded":false,"inApp":"AVAILABLE","wechatSubscription":"AVAILABLE"}"#)
        XCTAssertThrowsError(try ClubGovernanceValidation.validate(raw, operation: .notificationPreview, scope: scope))
    }
}

private final class GovernanceTransport: ClubGovernanceOfflineTransport {
    var requests: [URLRequest] = []
    var status = 200
    var code = 200
    var omitEnvelope = false
    var failure = false
    var afterSend: (() -> Void)?
    var override: ClubGovernanceValue?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); afterSend?()
        if failure { throw URLError(.timedOut) }
        let path = request.url!.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == "api/userInfo" { return (Data(#"{"code":200,"appUser":{"id":701,"role":"player"}}"#.utf8), 200) }
        var value = override ?? .null
        if override == nil {
            if let read = ClubGovernanceRead.allCases.first(where: { $0.path == path }) { value = ClubGovernanceFixtures.value(read) }
            else if let mutation = ClubGovernanceMutation.allCases.first(where: { $0.path == path }) { value = ClubGovernanceFixtures.receipt(mutation) }
        }
        if omitEnvelope { return (Data("{}".utf8), status) }
        return (try JSONEncoder().encode(ClubGovernanceValue.object(["code": .integer(code), "data": value, "msg": .string("Fixture response")])), status)
    }
}
final class ClubGovernanceServiceTests: XCTestCase {
    private func service(_ transport: GovernanceTransport, writes: Bool = false, risks: Set<ClubGovernanceRisk> = [.administrative]) throws -> ClubGovernanceService {
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com/")!)
        return writes ? .init(offlineConfiguration: config, offlineTransport: transport, risks: risks) : .init(configuration: config, transport: transport)
    }
    private func session() throws -> ClubGovernanceSession { try .init(accountID: 701, epoch: 1, token: "synthetic-token") }
    func testAllReadRoutesExecuteThroughInjectedTransport() async throws {
        for read in ClubGovernanceRead.allCases {
            let transport = GovernanceTransport(), service = try service(transport)
            let options = read == .notificationPreview ? ["audienceType": ClubGovernanceValue.string("REGISTERED"), "title": .string("Fixture"), "content": .string("Fixture")] : [:]
            _ = try await service.read(read, scope: ClubGovernanceFixtures.scope, options: options, session: session(), check: {})
            XCTAssertTrue(transport.requests.contains { $0.url?.path == "/" + read.path }, read.rawValue)
            XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "POST" })
        }
    }
    func testAllDormantMutationsActuallyDispatchAndDecodeOffline() async throws {
        for mutation in ClubGovernanceMutation.allCases {
            let transport = GovernanceTransport(), service = try service(transport, writes: true, risks: [.administrative, .financial, .identity, .provider])
            _ = try await service.dispatch(ClubGovernanceFixtures.command(mutation), session: session(), check: {})
            XCTAssertEqual(transport.requests.count, 1)
            XCTAssertEqual(transport.requests[0].url?.path, "/" + mutation.path)
        }
    }
    func testEveryJSONMutationBodyEqualsItsSourceBackedClosedFields() async throws {
        for operation in ClubGovernanceMutation.allCases where ![.chapterRecruit, .chapterFinish].contains(operation) {
            let transport = GovernanceTransport(), command = try ClubGovernanceFixtures.command(operation)
            _ = try await service(transport, writes: true, risks: [.administrative, .financial, .identity, .provider]).dispatch(command, session: session(), check: {})
            let body = try XCTUnwrap(transport.requests.first?.httpBody)
            XCTAssertEqual(try JSONDecoder().decode([String: ClubGovernanceValue].self, from: body), command.fields)
        }
    }
    func testProductionConstructionAlwaysBlocksBeforeTransport() async throws {
        let transport = GovernanceTransport(), service = try service(transport)
        do { _ = try await service.dispatch(ClubGovernanceFixtures.command(.saveCustomer), session: session(), check: {}); XCTFail() }
        catch { XCTAssertEqual(error as? ClubGovernanceFailure, .notConfigured) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testFinancialIdentityAndProviderRemainIndependentGates() async throws {
        let transport = GovernanceTransport(), service = try service(transport, writes: true)
        for operation in [ClubGovernanceMutation.reportHours, .cancelOccurrence, .hostApply, .issueGroupCode] {
            do { _ = try await service.dispatch(ClubGovernanceFixtures.command(operation), session: session(), check: {}); XCTFail() }
            catch { XCTAssertEqual(error as? ClubGovernanceFailure, .notConfigured) }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testEncodingRespectsJSONVersusFormExceptions() throws {
        let transport = GovernanceTransport(), service = try service(transport)
        for read in ClubGovernanceRead.allCases where read != .notificationPreview {
            let request = try service.request(path: read.path, fields: read.fields(scope: ClubGovernanceFixtures.scope), form: [.topicOverview, .members].contains(read), token: "synthetic")
            if [.topicOverview, .members].contains(read) { XCTAssertFalse(request.value(forHTTPHeaderField: "Content-Type") == "application/json") }
            else { XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json"); XCTAssertNotNil(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody))) }
        }
    }
    func testTimeoutAndMalformedAcknowledgmentAreUnknownNoRetry() async throws {
        for mode in ["timeout", "malformed", "server"] {
            let transport = GovernanceTransport(); transport.failure = mode == "timeout"; transport.omitEnvelope = mode == "malformed"; transport.status = mode == "server" ? 503 : 200
            do { _ = try await service(transport, writes: true).dispatch(ClubGovernanceFixtures.command(.saveCustomer), session: session(), check: {}); XCTFail() }
            catch { if let failure = error as? ClubGovernanceFailure, case .unknown = failure {} else { XCTFail("Expected unknown") } }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testBusiness409IsConflictAndBusiness415IsExplicitRejection() async throws {
        for code in [409, 415] {
            let transport = GovernanceTransport(); transport.code = code
            do { _ = try await service(transport, writes: true).dispatch(ClubGovernanceFixtures.command(.saveCustomer), session: session(), check: {}); XCTFail() }
            catch {
                if code == 409 { XCTAssertEqual(error as? ClubGovernanceFailure, .conflict(message: "Fixture response")) }
                else { XCTAssertEqual(error as? ClubGovernanceFailure, .rejected(code: 415, message: "Fixture response")) }
            }
        }
    }
    func testMismatchedReceiptAndPartialRefundDetails() async throws {
        let transport = GovernanceTransport(); transport.override = .object(["activityId": .integer(999), "refundStatus": .string("ACCEPTED")])
        do { _ = try await service(transport, writes: true, risks: [.financial]).dispatch(ClubGovernanceFixtures.command(.cancelOccurrence), session: session(), check: {}); XCTFail() }
        catch { XCTAssertEqual(error as? ClubGovernanceFailure, .unknown(message: nil)) }
        transport.override = nil
        let result = try await service(transport, writes: true, risks: [.financial]).dispatch(ClubGovernanceFixtures.command(.endTopic), session: session(), check: {})
        XCTAssertEqual(result["manualOrders"], .integer(2)); XCTAssertEqual(result["failedSessions"].array?.count, 1)
    }
    @MainActor func testStaleReadCannotReachReplacementSession() async throws {
        let transport = GovernanceTransport(); var current: ClubGovernanceSession? = try session()
        let access = ClubGovernanceSessionAccess(service: try service(transport), currentSession: { current })
        transport.afterSend = { current = try? .init(accountID: 701, epoch: 2, token: "replacement") }
        do { _ = try await access.read(.customers, scope: ClubGovernanceFixtures.scope); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(transport.requests.count, 1)
    }
}

final class ClubGovernanceGroupCodeTests: XCTestCase {
    func testTTLIsMillisecondsAndExpiredCodesCannotBeReused() throws {
        let instant = Date(timeIntervalSince1970: 1_000)
        let code = try ClubGovernanceGroupCode(receipt: ClubGovernanceFixtures.receipt(.issueGroupCode), receivedAt: instant)
        XCTAssertTrue(code.isActive(at: instant)); XCTAssertTrue(code.isActive(at: instant.addingTimeInterval(59)))
        XCTAssertFalse(code.isActive(at: instant.addingTimeInterval(60))); XCTAssertFalse(code.isActive(at: instant.addingTimeInterval(-1)))
    }
    func testInvalidURLsAndTTLReject() throws {
        for url in ["http://example.com/q.png", "https://secret:password@example.com/q.png", "file:///tmp/q.png"] {
            let value = ClubGovernanceValue.object(["qrcodeUrl": .string(url), "code": .string("synthetic"), "ttlMs": .integer(1000)])
            XCTAssertThrowsError(try ClubGovernanceGroupCode(receipt: value, receivedAt: Date()))
        }
        XCTAssertThrowsError(try ClubGovernanceGroupCode(receipt: .object(["qrcodeUrl": .string("https://example.com/q.png"), "code": .string("synthetic"), "ttlMs": .integer(0)]), receivedAt: Date()))
    }
    func testPublicProjectionNeverRetainsProtectedAnswers() throws {
        let raw = ClubGovernanceFixtures.json(#"{"id":91,"name":"Public topic","chaptersList":[{"nodes":[{"answer":"secret","hints":["secret"]}]}],"answerReveal":"secret"}"#)
        let value = try ClubGovernanceValidation.validate(raw, operation: .topicOverview, scope: ClubGovernanceFixtures.scope)
        XCTAssertEqual(value["answerReveal"], .null)
        XCTAssertEqual(value["chaptersList"].array![0]["nodes"].array![0]["answer"], .null)
    }
}

private final class GovernanceImageTransport: ClubGovernanceOfflineTransport {
    var request: URLRequest?
    var response = Data([1, 2, 3])
    func send(_ request: URLRequest) async throws -> (Data, Int) { self.request = request; return (response, 200) }
}
final class ClubGovernanceMediaTests: XCTestCase {
    func testQRCodeImageGETNeverForwardsAuthentication() async throws {
        let now = Date(), transport = GovernanceImageTransport()
        let code = try ClubGovernanceGroupCode(receipt: ClubGovernanceFixtures.receipt(.issueGroupCode), receivedAt: now)
        let service = ClubGovernanceGroupCodeMediaService(offlineTransport: transport, approvedFixtureHosts: ["example.com"])
        let bytes = try await service.imageBytes(code, now: now)
        XCTAssertEqual(bytes.count, 3); XCTAssertEqual(transport.request?.httpMethod, "GET")
        XCTAssertNil(transport.request?.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(transport.request?.value(forHTTPHeaderField: "Cookie"))
    }
    func testQRMediaDefaultsOffAndExpiredCodeSendsNothing() async throws {
        let now = Date(), transport = GovernanceImageTransport()
        let code = try ClubGovernanceGroupCode(receipt: ClubGovernanceFixtures.receipt(.issueGroupCode), receivedAt: now)
        do { _ = try await ClubGovernanceGroupCodeMediaService().imageBytes(code, now: now); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .notConfigured) }
        do { _ = try await ClubGovernanceGroupCodeMediaService(offlineTransport: transport, approvedFixtureHosts: ["example.com"]).imageBytes(code, now: now.addingTimeInterval(61)); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .invalidRequest) }
        XCTAssertNil(transport.request)
    }
}
