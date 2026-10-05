import XCTest
@testable import Questify

/// Synthetic recorder only; exercises real AppSession, outer fence and disk journals.
@MainActor final class CouponRuntimeCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coupon-runtime-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func root(_ wire: Wire, _ grants: Grants, directory: URL, locks: (any CouponManagementLocking)? = nil) throws -> AppCompositionRoot {
        let suite = "coupon-runtime-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.coupon-runtime", realm: "synthetic")
        let journal = try CouponManagementFileLocks(directory: directory), vault = Vault()
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, couponLocks: { locks ?? journal },
            couponReadApproval: { grants.read($0) }, couponWriteApproval: { grants.write($0) })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    private func reviewed(_ session: AppSession) async throws -> (CouponManagementCoordinator, CouponManagementReview) {
        let core = session.couponManagementCoordinator
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish()
        return (core, try XCTUnwrap(core.review))
    }
    func testNormalSessionCreateAndStopReadbackWithoutAISubscription() async throws {
        let wire = Wire(), session = try root(wire, Grants(), directory: directory()).makeSession(); await login(session)
        let pair = try await reviewed(session); await pair.0.confirm(pair.1)
        XCTAssertTrue(pair.0.acknowledged); XCTAssertEqual(pair.0.verifiedRecord?.id.value, 910)
        XCTAssertEqual(wire.writes, 1); XCTAssertFalse(wire.requests.contains { $0.url!.path.contains("subscription") })
        await pair.0.prepareStop(try CouponDefinitionID(910)); await pair.0.confirm(try XCTUnwrap(pair.0.review))
        XCTAssertEqual(pair.0.verifiedRecord?.state, .stopped); XCTAssertEqual(wire.writes, 2)
        for request in wire.requests.filter({ $0.url!.path.contains("/coupon/") }) {
            if request.url!.path.hasSuffix("publish") {
                let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
                XCTAssertEqual(fields["scope"] as? String, "MERCHANT")
                XCTAssertEqual(Set(fields.keys), ["scope", "name", "startTime", "endTime", "couponType", "publishCount"])
            } else { XCTAssertTrue(String(decoding: request.httpBody!, as: UTF8.self).contains("name=\"scope\"\r\n\r\nMERCHANT")) }
        }
    }
    func testMissingReadOrWriteLeaseAndArbitraryDormantTransportCannotWrite() async throws {
        for gate in ["read", "write"] {
            let wire = Wire(), grants = Grants(); grants.readEnabled = gate != "read"; grants.writeEnabled = gate != "write"
            let composition = try root(wire, grants, directory: directory()), session = composition.makeSession(); await login(session)
            let core = session.couponManagementCoordinator; await core.load()
            XCTAssertEqual(core.rows.count, gate == "read" ? 0 : 1)
            core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish()
            if let review = core.review { await core.confirm(review) }
            XCTAssertEqual(wire.writes, 0)
            let outer = composition.transport(); outer.current = { .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7") }
            let scope = try XCTUnwrap(composition.reviewed?.storageScope.service)
            let s = try CouponManagementSession(accountID: 7, namespace: scope, epoch: 1, authorizationRevision: "fake")
            let inner = CouponManagementHTTPDormantTransport(configuration: try XCTUnwrap(composition.reviewed?.regional.apiConfiguration), http: outer,
                dormantWritesEnabled: true, credentials: { try? .init(session: s, token: "synthetic-7") })
            let adapter = CouponManagementAdapter(transport: inner, dormantWritesEnabled: true)
            _ = await adapter.submit(try CouponManagementContract.publish(CouponManagementSyntheticFixtures.draft()), session: s)
            XCTAssertEqual(wire.writes, 0)
        }
    }
    func testFreshExplicitPermissionAndMerchantScopeAtReviewAndConfirm() async throws {
        for role in ["MERCHANT_OWNER", "MERCHANT_MANAGER", "MERCHANT_MARKETING", "MERCHANT_FINANCE", "MERCHANT_CHECKIN"] {
            let wire = Wire(); wire.roleCode = role
            let session = try root(wire, Grants(), directory: directory()).makeSession(); await login(session)
            let core = session.couponManagementCoordinator; core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish()
            if ["MERCHANT_FINANCE", "MERCHANT_CHECKIN"].contains(role) { XCTAssertNil(core.review); continue }
            let review = try XCTUnwrap(core.review); wire.permission = false; await core.confirm(review)
            XCTAssertFalse(core.acknowledged); XCTAssertEqual(wire.writes, 0)
        }
        for change in ["inactive", "foreign", "missing"] {
            let wire = Wire(), session = try root(wire, Grants(), directory: directory()).makeSession(); await login(session)
            let pair = try await reviewed(session)
            if change == "inactive" { wire.active = false }; if change == "foreign" { wire.merchantID = 99 }; if change == "missing" { wire.permission = false }
            await pair.0.confirm(pair.1); XCTAssertEqual(wire.writes, 0)
        }
    }
    func testStopRequiresFreshPermissionAndUnchangedOwnedStatus() async throws {
        for change in ["permission", "foreign", "status2", "status3", "status4", "status99"] {
            let wire = Wire(), session = try root(wire, Grants(), directory: directory()).makeSession(); await login(session)
            let core = session.couponManagementCoordinator; await core.prepareStop(try CouponDefinitionID(710)); let review = try XCTUnwrap(core.review)
            if change == "permission" { wire.permission = false }
            else if change == "foreign" { wire.rowID = 800 }
            else { wire.rowStatus = Int(change.dropFirst(6))! }
            await core.confirm(review); XCTAssertEqual(wire.writes, 0)
        }
    }
    func testUnknownPersistsAcrossDiskReopenLogoutAndDuplicateCoordinators() async throws {
        let disk = try directory(), wire = Wire(), composition = try root(wire, Grants(), directory: disk), session = composition.makeSession(); await login(session)
        let pair = try await reviewed(session), other = session.makeCouponManagementCoordinator()
        other.change(CouponManagementSyntheticFixtures.draft()); await other.preparePublish(); let second = try XCTUnwrap(other.review)
        wire.mode = "timeout"; await pair.0.confirm(pair.1); await other.confirm(second); await pair.0.confirm(pair.1)
        XCTAssertEqual(wire.writes, 1); XCTAssertEqual(pair.0.issue, .changed)
        let owner = try XCTUnwrap(session.couponManagementSession?.ownerKey)
        let reopened = try CouponManagementFileLocks(directory: disk)
        let pending = try XCTUnwrap(reopened.pending(ownerKey: owner, resource: "publish"))
        XCTAssertNotNil(pending.wire); XCTAssertFalse(String(decoding: try JSONEncoder().encode(pending), as: UTF8.self).contains("synthetic-7"))
        await session.logout(); await login(session)
        let next = session.couponManagementCoordinator; var draft = CouponManagementSyntheticFixtures.draft(); draft.name = "Different"; next.change(draft); await next.preparePublish()
        XCTAssertEqual(next.issue, .locked); XCTAssertEqual(wire.writes, 1)
        let restarted = try root(wire, Grants(), directory: disk).makeSession(); await login(restarted)
        let again = restarted.couponManagementCoordinator; again.change(draft); await again.preparePublish()
        XCTAssertEqual(again.issue, .locked); XCTAssertEqual(wire.writes, 1)
    }
    func testMalformedSuccessUnknownAndAcknowledgedReadbackFailureNeverRetry() async throws {
        for mode in ["missingID", "booleanID", "booleanCode", "stringCode", "nullCode", "fractionCode", "postcommit500", "unexpected201", "accepted202", "malformed", "500", "redirect", "timeout", "cancel", "mismatch", "readbackFail", "quota"] {
            let disk = try directory(), wire = Wire(), session = try root(wire, Grants(), directory: disk).makeSession(); await login(session)
            let pair = try await reviewed(session); wire.mode = mode; await pair.0.confirm(pair.1)
            XCTAssertEqual(wire.writes, 1)
            let pending = try CouponManagementFileLocks(directory: disk).pending(ownerKey: try XCTUnwrap(session.couponManagementSession).ownerKey, resource: "publish")
            if ["mismatch", "readbackFail"].contains(mode) { XCTAssertTrue(pair.0.acknowledged); XCTAssertNil(pair.0.verifiedRecord); XCTAssertNil(pending) }
            else if mode == "quota" { XCTAssertEqual(pair.0.serverMessage, "Capacity exhausted"); XCTAssertNotNil(pending); XCTAssertEqual(pair.0.issue, .locked) }
            else { XCTAssertNotNil(pending); XCTAssertFalse(pair.0.acknowledged) }
            XCTAssertEqual(wire.writes, 1)
        }
    }
    func testRevocationAfterJournalAcquirePreventsDispatchAndRetainsRecord() async throws {
        let disk = try directory(), grants = Grants(), wire = Wire(), locks = try HookLocks(directory: disk)
        let session = try root(wire, grants, directory: disk, locks: locks).makeSession(); await login(session)
        let pair = try await reviewed(session); locks.afterAcquire = { grants.writeLease?.revoke() }
        await pair.0.confirm(pair.1); XCTAssertEqual(wire.writes, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: disk.path).count, 1)
    }
    func testLateWriteSuccessAndFailureRemainUnknownAfterRoleABAOrLeaseRevocation() async throws {
        for transition in ["roleABA", "logout", "revoke"] {
            for fail in [false, true] {
                let disk = try directory(), wire = Wire(), grants = Grants(), session = try root(wire, grants, directory: disk).makeSession(); await login(session)
                let pair = try await reviewed(session), owner = try XCTUnwrap(session.couponManagementSession).ownerKey
                let paused = expectation(description: "write suspended"); wire.pause = true; wire.onPaused = { paused.fulfill() }
                let task = Task { await pair.0.confirm(pair.1) }; await fulfillment(of: [paused], timeout: 2)
                if transition == "roleABA" { wire.displayRole = "player"; await session.refreshOwnAccount(); wire.displayRole = "merchant"; await session.refreshOwnAccount() }
                else if transition == "logout" { await session.logout(); await login(session) }
                else { grants.writeLease?.revoke() }
                wire.finish(fail: fail); await task.value
                XCTAssertFalse(pair.0.acknowledged); XCTAssertNil(pair.0.verifiedRecord)
                XCTAssertNotNil(try CouponManagementFileLocks(directory: disk).pending(ownerKey: owner, resource: "publish"))
                XCTAssertEqual(wire.writes, 1)
            }
        }
    }
    func testCanonicalReadClonesAndAdjacentRoutesStayClosed() async throws {
        let wire = Wire(), grants = Grants(), composition = try root(wire, grants, directory: directory()), outer = composition.transport()
        outer.current = { .init(epoch: 1, accountID: 7, role: "club", token: "synthetic-7", viewerRevision: 2) }
        let clone = outer.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
        let boundary = "Canonical-Coupon"
        func request(_ path: String, fields: [String: String]? = nil) throws -> URLRequest {
            try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: fields ?? [:], token: "synthetic-7", includesBody: fields != nil, boundary: boundary)
        }
        _ = try await clone.send(request("api/merchant/access/me"))
        _ = try await clone.send(request("api/merchant/marketing-home"))
        let valid = try request("api/coupon/mypublishlist", fields: ["scope":"MERCHANT", "keyword":"gift"])
        _ = try await clone.send(valid)
        let count = wire.requests.count
        var invalid = [URLRequest]()
        for fields in [[String: String](), ["scope":"CLUB"], ["scope":"MERCHANT","ownerId":"7"], ["scope":"MERCHANT","keyword":""]] { invalid.append(try request("api/coupon/mypublishlist", fields: fields)) }
        for path in ["api/coupon/publish", "api/coupon/stop", "api/coupon/claim", "api/coupon/delete", "api/coupon/qr-token", "api/merchant/dashboard", "api/merchant/subscription"] { invalid.append(try request(path)) }
        for suffix in ["?scope=MERCHANT", "#fragment"] { var bad = valid; bad.url = URL(string: valid.url!.absoluteString + suffix); invalid.append(bad) }
        var bad = valid; bad.httpMethod = "GET"; invalid.append(bad)
        bad = valid; bad.url = URL(string: "https://example.test/other/api/coupon/mypublishlist"); invalid.append(bad)
        bad = valid; bad.httpBodyStream = InputStream(data: valid.httpBody!); invalid.append(bad)
        bad = valid; bad.setValue("application/json", forHTTPHeaderField: "Content-Type"); invalid.append(bad)
        for value in invalid { do { _ = try await clone.send(value); XCTFail("Unexpected dispatch: \(value)") } catch {} }
        XCTAssertEqual(wire.requests.count, count)
        grants.readLease?.revoke()
        do { _ = try await clone.send(valid); XCTFail("Revoked clone") } catch {}
        XCTAssertEqual(wire.requests.count, count)
    }
    func testFinalPreNetworkBarrierRechecksExpiredWriteLease() async throws {
        let wire = Wire(), grants = Grants(), disk = try directory(), composition = try root(wire, grants, directory: disk), outer = composition.transport()
        let runtimeSession = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: try XCTUnwrap(composition.reviewed?.storageScope.service), token: "synthetic-7")
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "merchant", session: runtimeSession)
        let read = grants.read(context), write = grants.write(context)
        let scope = try XCTUnwrap(CouponManagementRuntimeIdentity.session(context: context, viewerRevision: 2, read: read, write: write))
        outer.current = { .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7", viewerRevision: 2) }
        outer.couponBeforeForward = { if let write { write.expireIfNeeded(now: write.expiresAt) } }
        let config = try XCTUnwrap(composition.reviewed?.regional.apiConfiguration)
        let current: () -> CouponManagementSession? = { scope }
        let transport = CouponManagementRuntimeTransport(configuration: config, http: outer.replacingUnderlying(wire), actions: [.publish, .stop], credentials: { try? .init(session: scope, token: "synthetic-7") })
        let core = CouponManagementCoordinator(adapter: .init(transport: transport, dormantWritesEnabled: true),
            authorizer: CouponMerchantPublisherAuthorizer(configuration: config, http: outer, context: context, merchantID: 21, current: current),
            locks: try CouponManagementFileLocks(directory: disk), currentSession: current)
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish(); await core.confirm(try XCTUnwrap(core.review))
        XCTAssertEqual(wire.writes, 0); XCTAssertEqual(core.issue, .locked)
        XCTAssertNotNil(try CouponManagementFileLocks(directory: disk).pending(ownerKey: scope.ownerKey, resource: "publish"))
    }
    func testLateReadSuccessAndErrorSuppressedAcrossIdentityAndLeaseChanges() async throws {
        for transition in ["token", "roleABA", "owner", "revoke", "replace", "expire"] {
            for fail in [false, true] {
                let wire = Wire(), grants = Grants(), composition = try root(wire, grants, directory: directory()), outer = composition.transport()
                var identity = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7", viewerRevision: 2)
                outer.current = { identity }
                let clone = outer.replacingUnderlying(wire)
                let request = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/coupon/mypublishlist"), fields: ["scope":"MERCHANT"], token: "synthetic-7")
                wire.pauseList = true; let paused = expectation(description: "read suspended"); wire.onPaused = { paused.fulfill() }
                let task = Task { try await clone.send(request) }; await fulfillment(of: [paused], timeout: 2)
                let lease = try XCTUnwrap(grants.readLease)
                switch transition {
                case "token": identity = .init(epoch: 1, accountID: 7, role: "merchant", token: "rotated", viewerRevision: 2)
                case "roleABA": identity = .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7", viewerRevision: 4)
                case "owner": identity = .init(epoch: 2, accountID: 8, role: "merchant", token: "synthetic-8", viewerRevision: 3)
                case "revoke": lease.revoke()
                case "replace": grants.readLease = try .init(context: lease.context, merchantID: 21, expiresAt: Date().addingTimeInterval(600))
                default: lease.expireIfNeeded(now: lease.expiresAt)
                }
                wire.finish(fail: fail)
                do { _ = try await task.value; XCTFail(transition) } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(wire.writes, 0)
            }
        }
    }
    func testRevokedWriteLeaseLeavesIndependentReadCapabilityUsable() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants, directory: directory()).makeSession(); await login(session)
        let pair = try await reviewed(session); grants.writeLease?.revoke()
        await pair.0.confirm(pair.1); XCTAssertEqual(wire.writes, 0)
        let reader = session.couponManagementCoordinator
        XCTAssertFalse(reader.canSubmit); await reader.load(); XCTAssertEqual(reader.rows.count, 1)
        XCTAssertEqual(wire.writes, 0)
    }
    func testPerActionLeasesDenyOtherActionWithoutCreatingPendingRecord() async throws {
        for allowed in CouponManagementWriteApproval.Action.allCases {
            let disk = try directory(), wire = Wire(), grants = Grants(); grants.actions = [allowed]
            let session = try root(wire, grants, directory: disk).makeSession(); await login(session)
            let core = session.couponManagementCoordinator
            core.change(CouponManagementSyntheticFixtures.draft())
            if allowed == .stop {
                XCTAssertFalse(core.canReviewPublish); await core.preparePublish()
            } else {
                XCTAssertFalse(core.canReviewStop); await core.prepareStop(try CouponDefinitionID(710))
            }
            XCTAssertNil(core.review); XCTAssertEqual(core.issue, .unavailable); XCTAssertEqual(wire.writes, 0)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: disk.path).isEmpty)
            if allowed == .publish { await core.preparePublish() } else { await core.prepareStop(try CouponDefinitionID(710)) }
            let review = try XCTUnwrap(core.review); XCTAssertTrue(core.canConfirm(review)); await core.confirm(review)
            XCTAssertEqual(wire.writes, 1); XCTAssertTrue(core.acknowledged)
        }
    }
    func testPostcommitCode500RetainsOriginalPublicationLockAcrossRestart() async throws {
        let disk = try directory(), wire = Wire(), session = try root(wire, Grants(), directory: disk).makeSession(); await login(session)
        let pair = try await reviewed(session); wire.mode = "postcommit500"; await pair.0.confirm(pair.1)
        XCTAssertNotNil(wire.published); XCTAssertEqual(wire.writes, 1); XCTAssertEqual(pair.0.issue, .locked)
        XCTAssertEqual(pair.0.serverMessage, "Response construction failed after insert")
        let restarted = try root(wire, Grants(), directory: disk).makeSession(); await login(restarted)
        let again = restarted.couponManagementCoordinator; again.change(CouponManagementSyntheticFixtures.draft()); await again.preparePublish()
        XCTAssertNil(again.review); XCTAssertEqual(again.issue, .locked); XCTAssertEqual(wire.writes, 1)
    }
    func testV1NormalCompositionPersistsThenReadOnlyRecoveryAfterRestart() async throws {
        let disk = try directory(), wire = Wire(), grants = Grants(); grants.commandEnabled = true
        wire.coopPermission = true; wire.roleCode = "MERCHANT_MARKETING"; wire.mode = "timeout"
        let app = try root(wire, grants, directory: disk).makeSession(); await login(app)
        let pair = try await reviewed(app); await pair.0.confirm(pair.1)
        let key = try XCTUnwrap(app.couponManagementSession?.ownerKey)
        let locks = try CouponManagementFileLocks(directory: disk), pending = try XCTUnwrap(locks.pending(ownerKey: key, resource: "publish"))
        let command = try XCTUnwrap(pending.command)
        XCTAssertEqual(command.ownerMemberID, 9001); XCTAssertEqual(command.actorMemberID, 7)
        XCTAssertEqual(wire.writes, 1); XCTAssertEqual(pair.0.issue, .locked)
        XCTAssertEqual(wire.requests.last { $0.url!.path.hasSuffix("/publish") }?.value(forHTTPHeaderField: "X-Coupon-Command-Id"), command.requestID)
        let receipt: [String: Any] = ["version": 1, "requestId": command.requestID, "operation": "PUBLISH", "scope": "MERCHANT", "merchantId": 21,
            "ownerMemberId": 9001, "actorMemberId": 7, "payloadHash": command.payloadHash, "outcome": "SUCCEEDED", "reasonCode": "PUBLISHED", "couponId": 910, "couponStatusAtExecution": 1, "completedAt": "2026-10-04T22:00:00.123+08:00"]
        wire.receiptResponse = try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["id": 910, "commandReceipt": receipt]])
        let fresh = Grants(); fresh.commandEnabled = true; fresh.writeEnabled = false
        let restarted = try root(wire, fresh, directory: disk).makeSession(); await login(restarted)
        let core = restarted.couponManagementCoordinator; XCTAssertFalse(core.canSubmit); XCTAssertTrue(core.canRecoverCommands)
        await core.recoverPendingCommands()
        XCTAssertEqual(core.recoveredCommandCount, 1); XCTAssertNil(try locks.pending(ownerKey: key, resource: "publish")); XCTAssertEqual(wire.writes, 1)
        XCTAssertEqual(wire.requests.filter { $0.url!.path.hasSuffix("/command-receipt") }.count, 1)
    }
    func testV1OwnerReadIsNotGrantedByLegacyLeaseOrCouponPermissionAlone() async throws {
        for enabled in [false, true] {
            let wire = Wire(), grants = Grants(); grants.commandEnabled = enabled
            let composition = try root(wire, grants, directory: directory()), app = composition.makeSession(); await login(app)
            let core = app.couponManagementCoordinator; core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish()
            if enabled { XCTAssertNil(core.review); XCTAssertEqual(core.issue, .forbidden) }
            else { XCTAssertNotNil(core.review) }
            XCTAssertFalse(wire.requests.contains { $0.url!.path.hasSuffix("/coop-profile") }); XCTAssertEqual(wire.writes, 0)
            if !enabled {
                let outer = composition.transport(); outer.current = { .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7") }
                let request = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/merchant/coop-profile"), fields: [:], token: "synthetic-7", includesBody: false)
                do { _ = try await outer.replacingUnderlying(wire).send(request); XCTFail("Legacy lease admitted owner read") } catch {}
            }
        }
    }
    func testV1FinalBoundaryRevocationRetainsJournalWithoutDispatch() async throws {
        let wire = Wire(), grants = Grants(), disk = try directory(); grants.commandEnabled = true; wire.coopPermission = true
        let composition = try root(wire, grants, directory: disk), outer = composition.transport()
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "merchant", session: try .init(accountID: 7, epoch: 1, namespace: XCTUnwrap(composition.reviewed?.storageScope.service), token: "synthetic-7"))
        let read = try XCTUnwrap(grants.read(context)), write = grants.write(context), capability = try XCTUnwrap(read.commandProtocol)
        let session = try XCTUnwrap(CouponManagementRuntimeIdentity.session(context: context, viewerRevision: 2, read: read, write: write))
        outer.current = { .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7", viewerRevision: 2) }
        outer.couponBeforeForward = { capability.revoke() }
        let configuration = try XCTUnwrap(composition.reviewed?.regional.apiConfiguration)
        let transport = CouponManagementRuntimeTransport(configuration: configuration, http: outer.replacingUnderlying(wire), actions: [.publish], commandProtocol: capability, credentials: { try? .init(session: session, token: "synthetic-7") })
        let core = CouponManagementCoordinator(adapter: .init(transport: transport, dormantWritesEnabled: true),
            authorizer: CouponMerchantPublisherAuthorizer(configuration: configuration, http: outer, context: context, merchantID: 21, commandProtocol: capability, current: { session }),
            locks: try CouponManagementFileLocks(directory: disk), currentSession: { session })
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish(); await core.confirm(try XCTUnwrap(core.review))
        XCTAssertEqual(wire.writes, 0); XCTAssertEqual(core.issue, .locked)
        XCTAssertNotNil(try CouponManagementFileLocks(directory: disk).pending(ownerKey: session.ownerKey, resource: "publish"))
    }
    func testV1ReceiptCloneDiscardsLateResponseWhenCapabilityRevoked() async throws {
        let wire = Wire(), grants = Grants(); grants.commandEnabled = true; wire.pauseReceipt = true
        let composition = try root(wire, grants, directory: directory()), outer = composition.transport()
        outer.current = { .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7", viewerRevision: 2) }
        let request = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/coupon/command-receipt"), fields: ["requestId": "11111111-1111-4111-8111-111111111111", "merchantId": "21", "scope": "MERCHANT"], token: "synthetic-7")
        let paused = expectation(description: "receipt suspended"); wire.onPaused = { paused.fulfill() }
        let task = Task { try await outer.replacingUnderlying(wire).send(request) }; await fulfillment(of: [paused], timeout: 2)
        grants.readLease?.commandProtocol?.revoke(); wire.finish(fail: false)
        do { _ = try await task.value; XCTFail("Revoked late receipt accepted") } catch {}
        XCTAssertEqual(wire.writes, 0)
    }
    func testActualCouponFixtureNormalSessionReachesMarketingHomeInEveryMode() async throws {
        // Exercise the exact UI fixture, normal composition and original content service.
        // A coupon-only transport test misses the recruiting screen's project permission gate.
        for mode in ["ready", "readOnly", "unknown", "revokeOnConfirm", "commandUnknown", "commandReadOnly", "commandNotFound"] {
            let fixture = try CouponRuntimeFixture(mode: mode), session = fixture.composition().makeSession()
            fixture.session = session; await login(session)
            let before = fixture.routes.count
            let snapshot = try await session.merchantContentService.load(.recruiting)
            XCTAssertEqual(Array(fixture.routes.dropFirst(before)), ["api/merchant/access/me", "api/merchant/marketing-home"], mode)
            XCTAssertEqual(snapshot.query, .recruiting); XCTAssertEqual(snapshot.access.merchantID, 21)
            XCTAssertTrue(snapshot.access.allows(.projects)); XCTAssertTrue(snapshot.rows.isEmpty)
            let coupons = session.couponManagementCoordinator; await coupons.load()
            XCTAssertEqual(coupons.rows.first?.id.value, 710, mode)
            XCTAssertEqual(fixture.writes, 0); XCTAssertEqual(fixture.violations, [])
        }
    }
    func testActualFixtureCouponRevocationPreservesRecruitingButStillDeniesCouponWrite() async throws {
        let fixture = try CouponRuntimeFixture(mode: "revokeOnConfirm"), session = fixture.composition().makeSession()
        fixture.session = session; await login(session)
        _ = try await session.merchantContentService.load(.recruiting)
        let coupons = session.couponManagementCoordinator; await coupons.load()
        coupons.change(CouponManagementSyntheticFixtures.draft()); await coupons.preparePublish()
        let review = try XCTUnwrap(coupons.review); await coupons.confirm(review)
        XCTAssertEqual(coupons.issue, .forbidden); XCTAssertFalse(coupons.acknowledged)
        XCTAssertEqual(fixture.writes, 0); XCTAssertEqual(fixture.violations, [])
        let before = fixture.routes.count
        let snapshot = try await session.merchantContentService.load(.recruiting)
        XCTAssertEqual(Array(fixture.routes.dropFirst(before)), ["api/merchant/access/me", "api/merchant/marketing-home"])
        XCTAssertTrue(snapshot.access.allows(.projects)); XCTAssertEqual(snapshot.access.merchantID, 21)
        XCTAssertNil(try fixture.locks.pending(ownerKey: try XCTUnwrap(session.couponManagementSession?.ownerKey), resource: "publish"))
    }
    @MainActor private final class Grants {
        var readEnabled = true, writeEnabled = true, commandEnabled = false
        var actions: Set<CouponManagementWriteApproval.Action> = [.publish, .stop]
        var readLease: CouponManagementReadApproval?, writeLease: CouponManagementWriteApproval?
        func read(_ context: RuntimeDependencyContext) -> CouponManagementReadApproval? {
            guard readEnabled else { return nil }
            if readLease == nil || readLease?.context != context {
                readLease?.revoke()
                let command: CouponCommandProtocolApproval?
                if commandEnabled { command = try? CouponCommandProtocolApproval(context: context, merchantID: 21, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600)) } else { command = nil }
                readLease = try? .init(context: context, merchantID: 21, expiresAt: Date().addingTimeInterval(600), commandProtocol: command)
            }; return readLease
        }
        func write(_ context: RuntimeDependencyContext) -> CouponManagementWriteApproval? {
            guard writeEnabled else { return nil }
            if writeLease == nil || writeLease?.context != context { writeLease?.revoke(); writeLease = try? .init(context: context, merchantID: 21, actions: actions, expiresAt: Date().addingTimeInterval(600)) }; return writeLease
        }
    }
    private final class HookLocks: CouponManagementLocking {
        let store: CouponManagementFileLocks; var afterAcquire: (() -> Void)?
        init(directory: URL) throws { store = try .init(directory: directory) }
        func pending(ownerKey: String, resource: String) throws -> CouponManagementPending? { try store.pending(ownerKey: ownerKey, resource: resource) }
        func acquire(_ pending: CouponManagementPending) throws { try store.acquire(pending); afterAcquire?() }
        func release(_ pending: CouponManagementPending) throws { try store.release(pending) }
    }
    private final class Vault: AppTokenStorage { var value: String?; func read() throws -> String? { value }; func write(_ token: String) throws { value = token }; func clear() throws { value = nil } }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], writes = 0, roleCode = "MERCHANT_OWNER", displayRole = "merchant", merchantID = 21
        var permission = true, active = true, mode = "success", rowID = 710, rowStatus = 1
        var coopPermission = false, ownerMemberID = 9001, pauseReceipt = false
        var receiptResponse = Data(#"{"code":404,"data":{"reasonCode":"COMMAND_NOT_FOUND"}}"#.utf8)
        var published: [String: Any]?, pause = false, pauseList = false, pendingReadData: Data?, onPaused: (() -> Void)?
        var continuation: CheckedContinuation<(Data, Int), Error>?
        func finish(fail: Bool) { let saved = continuation; continuation = nil; if fail { saved?.resume(throwing: URLError(.timedOut)) } else { saved?.resume(returning: (pendingReadData ?? Data(#"{"code":200,"data":{"id":910}}"#.utf8), 200)) } }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.path
            if path.hasSuffix("/phone") { return (Data("{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(displayRole)\"}}".utf8), 200) }
            if path.hasSuffix("/userInfo") { return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(displayRole)\"}}".utf8), 200) }
            if path.hasSuffix("/logout") { return (Data(#"{"code":200}"#.utf8), 200) }
            if path.hasSuffix("/access/me") { return (try JSONSerialization.data(withJSONObject: ["code":200,"data":["active":active,"merchant":["id":merchantID],"roleCode":roleCode,"permissions":(permission ? ["merchant:coupon:manage", "merchant:marketing:read"] : ["merchant:marketing:read"]) + (coopPermission ? ["merchant:coop:manage"] : [])]]), 200) }
            if path.hasSuffix("/coop-profile") { return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["id": merchantID, "memberId": ownerMemberID]]), 200) }
            if path.hasSuffix("/command-receipt") {
                if pauseReceipt { pendingReadData = receiptResponse; return try await withCheckedThrowingContinuation { continuation = $0; onPaused?() } }
                return (receiptResponse, 200)
            }
            if path.hasSuffix("/marketing-home") { return (Data(#"{"code":200,"data":{"recruiting":{"items":[]}}}"#.utf8), 200) }
            if path.hasSuffix("/mypublishlist") {
                if writes > 0, mode == "readbackFail" { throw URLError(.timedOut) }
                var row = published ?? ["id": rowID, "name":"Owned", "status": rowStatus]
                row["id"] = published == nil ? rowID : 910; row["status"] = rowStatus
                if mode == "mismatch" { row["name"] = "Different" }
                let data = try JSONSerialization.data(withJSONObject: ["code":200,"data":[row]])
                if pauseList { pendingReadData = data; return try await withCheckedThrowingContinuation { continuation = $0; onPaused?() } }
                return (data, 200)
            }
            guard path.hasSuffix("/publish") || path.hasSuffix("/stop") else { throw APIError.notConfigured }
            writes += 1
            if path.hasSuffix("/publish") { published = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any] }
            else { rowStatus = 4 }
            if pause { return try await withCheckedThrowingContinuation { continuation = $0; onPaused?() } }
            if mode == "timeout" { throw URLError(.timedOut) }; if mode == "cancel" { throw CancellationError() }
            if mode == "500" { return (Data(#"{"code":500,"msg":"Server failure"}"#.utf8), 500) }
            if mode == "redirect" { return (Data(), 302) }
            if mode == "unexpected201" { return (Data(#"{"code":200,"data":{"id":910}}"#.utf8), 201) }
            if mode == "accepted202" { return (Data(#"{"code":200,"data":{"id":910}}"#.utf8), 202) }
            if mode == "quota" { return (Data(#"{"code":500,"msg":"Capacity exhausted"}"#.utf8), 200) }
            if mode == "postcommit500" { return (Data(#"{"code":500,"msg":"Response construction failed after insert"}"#.utf8), 200) }
            if mode == "booleanCode" { return (Data(#"{"code":true,"msg":"Malformed"}"#.utf8), 200) }
            if mode == "stringCode" { return (Data(#"{"code":"500","msg":"Malformed"}"#.utf8), 400) }
            if mode == "nullCode" { return (Data(#"{"code":null,"msg":"Malformed"}"#.utf8), 200) }
            if mode == "fractionCode" { return (Data(#"{"code":409.5,"msg":"Malformed"}"#.utf8), 400) }
            if mode == "malformed" { return (Data("invalid".utf8), 200) }
            if mode == "missingID" { return (Data(#"{"code":200}"#.utf8), 200) }
            if mode == "booleanID" { return (Data(#"{"code":200,"data":{"id":true}}"#.utf8), 200) }
            return (Data(#"{"code":200,"data":{"id":910}}"#.utf8), 200)
        }
    }
}
