import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileOwnedCouponReadTests: XCTestCase {
    private let base = URL(string: "https://coupon.example/native")!
    private func root(_ wire: Wire, _ grants: Grants? = nil, vault: Vault? = nil) throws -> AppCompositionRoot {
        let vault = vault ?? Vault(), suite = "owned-coupon-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.owned-coupon", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, profileOwnedCouponReadAccess: { grants?.select($0) })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    private func request(_ fields: [String: String] = [:]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(ProfileOwnedCouponReadRoute.path), fields: fields, token: "synthetic-coupon")
    }
    func testDefaultNilNormalReaderHonestUnavailableAndZeroDispatch() async throws {
        let wire = Wire(), session = try root(wire).makeSession(); await login(session); wire.requests = []
        let reader = session.profileOwnedCouponReader, model = OwnedCouponReadScreenModel()
        XCTAssertTrue(reader.isAuthenticated); XCTAssertFalse(reader.isConfigured)
        let request = OwnedCouponReadRequest.list(ownerScope: reader.scope, keyword: nil)
        let permit = model.beginPresentation(for: request, foreground: true)
        await model.refresh(request: request, reader: reader, presentation: permit)
        XCTAssertEqual(model.issue(for: request), .notConfigured); XCTAssertNil(model.rows(for: request))
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertTrue(session.accountCollectionReader.isConfigured)
    }
    func testNormalReaderSearchFilterDetailAndReturnRefreshUseOnlyMetadataRoute() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.requests = []
        let reader = session.profileOwnedCouponReader, model = OwnedCouponReadScreenModel()
        let list = OwnedCouponReadRequest.list(ownerScope: reader.scope, keyword: nil)
        let first = model.beginPresentation(for: list, foreground: true)
        await model.refresh(request: list, reader: reader, presentation: first)
        XCTAssertEqual(model.rows(for: list)?.map(\.id), [101,102,103,104])
        XCTAssertEqual(model.selections(for: list, filter: .unused).map(\.historyID), [101])
        XCTAssertEqual(model.selections(for: list, filter: .used).map(\.historyID), [102])
        XCTAssertEqual(model.selections(for: list, filter: .expired).map(\.historyID), [103])
        let search = OwnedCouponReadRequest.list(ownerScope: reader.scope, keyword: "Tea")
        let searched = model.beginPresentation(for: search, foreground: true)
        await model.refresh(request: search, reader: reader, presentation: searched)
        XCTAssertEqual(model.rows(for: search)?.map(\.id), [101]); XCTAssertEqual(wire.keywords, [nil,"Tea"])
        let selection = try XCTUnwrap(model.selections(for: search, filter: .all).first)
        XCTAssertTrue(model.endPresentation(presentation: searched))
        let detail = OwnedCouponReadScreenModel(), detailRequest = OwnedCouponReadRequest.detail(selection)
        let detailPermit = detail.beginPresentation(for: detailRequest, foreground: true)
        await detail.refresh(request: detailRequest, reader: reader, presentation: detailPermit)
        XCTAssertEqual(detail.detail(for: detailRequest)?.id, 101); XCTAssertEqual(wire.keywords, [nil,"Tea",nil])
        XCTAssertTrue(detail.endPresentation(presentation: detailPermit))
        XCTAssertNil(model.offerRead(request: search, reader: reader, presentation: searched))
        let returned = model.beginPresentation(for: search, foreground: true)
        await model.refresh(request: search, reader: reader, presentation: returned)
        XCTAssertEqual(model.rows(for: search)?.map(\.id), [101]); XCTAssertEqual(wire.keywords, [nil,"Tea",nil,"Tea"])
        XCTAssertEqual(Set(wire.paths), ["myrecvlist"])
    }
    func testOrdinaryFailureRetriesSameSearchAndSuccessfulEmptyIsExplicit() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.requests = []
        let reader = session.profileOwnedCouponReader, model = OwnedCouponReadScreenModel()
        let request = OwnedCouponReadRequest.list(ownerScope: reader.scope, keyword: "Tea")
        let permit = model.beginPresentation(for: request, foreground: true); wire.status = 503
        await model.refresh(request: request, reader: reader, presentation: permit)
        XCTAssertNotNil(model.issue(for: request)); XCTAssertNil(model.rows(for: request))
        wire.status = 200; await model.refresh(request: request, reader: reader, presentation: permit)
        XCTAssertNil(model.issue(for: request)); XCTAssertEqual(model.rows(for: request)?.count, 1)
        wire.responseOverride = #"{"code":200,"data":[]}"#
        await model.refresh(request: request, reader: reader, presentation: permit)
        XCTAssertEqual(model.rows(for: request)?.count, 0); XCTAssertNil(model.issue(for: request))
        XCTAssertEqual(wire.keywords, ["Tea","Tea","Tea"])
    }
    func testMalformedOrOtherOwnerSuccessNeverBecomesEmptyOrRows() async throws {
        for malformed in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":[{"id":101,"memberId":82}]}"#, #"{"code":200,"data":[{"id":101}]}"#, #"{"code":200,"data":[{"id":101,"memberId":true}]}"#] {
            let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.responseOverride = malformed
            do { _ = try await session.profileOwnedCouponReader.ownedCoupons(keyword: nil); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testMissingOrDuplicateSelectedHistoryCannotOpenAnotherCoupon() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session)
        do { _ = try await session.profileOwnedCouponReader.ownedCoupon(id: 999); XCTFail() }
        catch { XCTAssertEqual(error as? AccountCollectionReadFailure, .unavailable) }
        wire.responseOverride = #"{"code":200,"data":[{"id":101,"memberId":81},{"id":101,"memberId":81}]}"#
        do { _ = try await session.profileOwnedCouponReader.ownedCoupon(id: 101); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        XCTAssertFalse(wire.paths.contains("qr-token"))
    }
    func testDedicatedReaderNeverProvidesFavoritesOrRedemptionPermission() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.requests = []
        do { _ = try await session.profileOwnedCouponReader.favoriteTopics(pageNumber: 1, pageSize: 10); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await session.profileOwnedCouponReader.favoritePosts(pageNumber: 1, pageSize: 10); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await session.accountCollectionReader.favoriteTopics(pageNumber: 1, pageSize: 10); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExistingNormalLinksKeepFavoriteAndRewardReaderSeparate() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session)
        let original = AccountCollectionAccountLinks(reader: session.accountCollectionReader, onOpenTopic: { _ in })
        XCTAssertNil(original.couponReader)
        let linked = AccountCollectionAccountLinks(reader: session.accountCollectionReader, onOpenTopic: { _ in }, couponReader: session.profileOwnedCouponReader)
        XCTAssertTrue(linked.reader === session.accountCollectionReader)
        XCTAssertTrue(linked.couponReader === session.profileOwnedCouponReader)
    }
    func testDefaultNilTransportRejectsBeforeUnderlyingDispatch() async throws {
        let wire = Wire(), transport = try root(wire).transport()
        transport.current = { .init(epoch: 1, accountID: 81, role: "player", token: "synthetic-coupon", viewerRevision: 1) }
        do { _ = try await transport.send(request()); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testTransportClonePreservesSelectorAndRejectsOtherTargetsAndWrongToken() async throws {
        let wire = Wire(), transport = try root(wire, Grants()).transport()
        transport.current = { .init(epoch: 1, accountID: 81, role: "player", token: "synthetic-coupon", viewerRevision: 1) }
        let clone = transport.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
        _ = try await clone.send(request(["keyword":"Tea"]))
        for path in ["api/coupon/qr-token", "api/coupon/receive", "api/coupon/mypublishlist", "api/topic/like_list"] {
            var wrong = try request(); wrong.url = base.appendingPathComponent(path)
            do { _ = try await clone.send(wrong); XCTFail() } catch {}
        }
        var wrong = try request(); wrong.setValue("other-token", forHTTPHeaderField: "Authorization")
        do { _ = try await clone.send(wrong); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testEveryTransportIdentityAndIssuanceChangeRejectsLateSuccessAnd401() async throws {
        for change in ["owner", "epoch", "token", "viewer", "role", "revoke", "replace", "remove"] {
            for status in [200,401] {
                let wire = Wire(), grants = Grants(), transport = try root(wire, grants).transport()
                var identity = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 81, role: "player", token: "synthetic-coupon", viewerRevision: 1)
                transport.current = { identity }; wire.hold = true
                let held = expectation(description: "held metadata"); wire.onHeld = { held.fulfill() }
                let task = Task { try await transport.send(request()) }; await fulfillment(of: [held], timeout: 2)
                let access = try XCTUnwrap(grants.retained)
                switch change {
                case "owner": identity = .init(epoch: 2, accountID: 82, role: "player", token: "synthetic-coupon", viewerRevision: 2)
                case "epoch": identity = .init(epoch: 2, accountID: 81, role: "player", token: "synthetic-coupon", viewerRevision: 1)
                case "token": identity = .init(epoch: 1, accountID: 81, role: "player", token: "new-token", viewerRevision: 1)
                case "viewer": identity = .init(epoch: 1, accountID: 81, role: "player", token: "synthetic-coupon", viewerRevision: 2)
                case "role": identity = .init(epoch: 1, accountID: 81, role: "merchant", token: "synthetic-coupon", viewerRevision: 1)
                case "revoke": access.revoke()
                case "replace": grants.retained = try .init(context: access.context, approval: access.endpoints)
                default: grants.enabled = false
                }
                wire.finish(status: status)
                do { _ = try await task.value; XCTFail(change) } catch { XCTAssertTrue(error is CancellationError) }
            }
        }
    }
    func testApprovalInstalledRevokedAndReissuedChangesExistingReaderScope() async throws {
        let wire = Wire(), grants = Grants(); grants.enabled = false
        let session = try root(wire, grants).makeSession(); await login(session); wire.requests = []
        let reader = session.profileOwnedCouponReader, absent = reader.scope
        XCTAssertFalse(reader.isConfigured); grants.enabled = true
        XCTAssertTrue(reader.isConfigured); let approved = reader.scope; XCTAssertNotEqual(approved, absent)
        _ = try await reader.ownedCoupons(keyword: nil)
        grants.retained?.revoke(); XCTAssertFalse(reader.isConfigured); XCTAssertNotEqual(reader.scope, approved)
        let count = wire.requests.count
        do { _ = try await reader.ownedCoupons(keyword: nil); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, count)
        grants.retained = nil; XCTAssertTrue(reader.isConfigured); XCTAssertNotEqual(reader.scope, approved)
        _ = try await reader.ownedCoupon(id: 101); XCTAssertEqual(wire.requests.count, count + 1)
    }
    func testCurrentTransportOrBusiness401ExpiresOnlyCurrentAccount() async throws {
        for status in [200,401] {
            let wire = Wire(), vault = Vault(), session = try root(wire, Grants(), vault: vault).makeSession(); await login(session)
            wire.status = status; wire.responseOverride = #"{"code":401}"#
            do { _ = try await session.profileOwnedCouponReader.ownedCoupons(keyword: nil); XCTFail() } catch {}
            XCTAssertNil(session.account); XCTAssertNil(vault.value)
        }
    }
    func testHiddenReadLifetimeRejectsLate401WithoutSigningOut() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session)
        let reader = session.profileOwnedCouponReader, lifetime = OwnedCouponReadLifetime(ownerScope: session.profileOwnedCouponReader.scope)
        wire.hold = true; let held = expectation(description: "held hidden"); wire.onHeld = { held.fulfill() }
        let task = Task { try await reader.ownedCoupons(keyword: nil, lifetime: lifetime) }
        await fulfillment(of: [held], timeout: 2); lifetime.invalidate(); wire.finish(status: 401)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNotNil(session.account)
    }
    func testOldSelectionAndPendingReplyCannotPopulateAfterOwnerSwitch() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession(); await login(session)
        let reader = session.profileOwnedCouponReader, model = OwnedCouponReadScreenModel()
        let request = OwnedCouponReadRequest.list(ownerScope: reader.scope, keyword: nil)
        let permit = model.beginPresentation(for: request, foreground: true)
        wire.hold = true; let held = expectation(description: "held old owner"); wire.onHeld = { held.fulfill() }
        let task = Task { await model.refresh(request: request, reader: reader, presentation: permit) }
        await fulfillment(of: [held], timeout: 2)
        await session.logout(); wire.hold = false; wire.account = 82; grants.retained = nil; await login(session)
        wire.finish(status: 401); await task.value
        XCTAssertEqual(session.account?.id, 82); XCTAssertNil(model.rows(for: request)); XCTAssertNotEqual(reader.scope, request.ownerScope)
        XCTAssertNil(model.offerRead(request: request, reader: reader, presentation: permit))
    }
    func testWrongLifetimeAndGuestFailBeforeAnyDispatch() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession()
        do { _ = try await session.profileOwnedCouponReader.ownedCoupons(keyword: nil); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertTrue(wire.requests.isEmpty); await login(session); wire.requests = []
        do { _ = try await session.profileOwnedCouponReader.ownedCoupons(keyword: nil, lifetime: .init(ownerScope: UUID())); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testOrdinaryCouponDestinationActuallyStartsConfiguredMetadataRead() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.requests = []
        let host = UIHostingController(rootView: NavigationStack {
            AccountCollectionCouponsView(reader: session.profileOwnedCouponReader)
        }.environment(\.scenePhase, .active))
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        for _ in 0..<100 where wire.requests.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(wire.paths, ["myrecvlist"])
    }
    func testSelfProfileCouponEntryRequiresOwnerPlayerOrClubAndIndependentApproval() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession()
        await login(session); wire.requests = []
        let social = SelfCouponSocial()
        let access = ProfileSelfCouponAccess(reader: session.profileOwnedCouponReader, owner: social.identity)
        XCTAssertNotNil(ProfileSelfCouponContext.capture(memberID: 81, accountReader: social, access: access, isCurrent: true))
        XCTAssertNil(ProfileSelfCouponContext.capture(memberID: 82, accountReader: social, access: access, isCurrent: true))
        XCTAssertNil(ProfileSelfCouponContext.capture(memberID: 81, accountReader: social, access: access, isCurrent: false))
        social.identity = .init(accountID: 81, epoch: 1, role: "merchant")
        let merchant = ProfileSelfCouponAccess(reader: session.profileOwnedCouponReader, owner: social.identity)
        XCTAssertNil(ProfileSelfCouponContext.capture(memberID: 81, accountReader: social, access: merchant, isCurrent: true))
        social.identity = .init(accountID: 81, epoch: 1, role: "club")
        let club = ProfileSelfCouponAccess(reader: session.profileOwnedCouponReader, owner: social.identity)
        XCTAssertNotNil(ProfileSelfCouponContext.capture(memberID: 81, accountReader: social, access: club, isCurrent: true))
        grants.enabled = false
        XCTAssertNil(ProfileSelfCouponContext.capture(memberID: 81, accountReader: social, access: club, isCurrent: true))
        XCTAssertTrue(wire.requests.isEmpty) // Rendering the entry never fetches a count/list.
    }
    func testSelfProfileCouponMetadataListAndDetailReuseExactReader() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession()
        await login(session); wire.requests = []
        let social = SelfCouponSocial(), access = ProfileSelfCouponAccess(reader: session.profileOwnedCouponReader, owner: .init(accountID: 81, epoch: 1, role: "player"))
        let context = try XCTUnwrap(ProfileSelfCouponContext.capture(memberID: 81, accountReader: social, access: access, isCurrent: true))
        let scoped = ProfileSelfCouponScopedReader(context: context, accountReader: social, access: access, isCurrent: { true })
        let model = OwnedCouponReadScreenModel(), request = OwnedCouponReadRequest.list(ownerScope: scoped.scope, keyword: "Tea")
        let permit = model.beginPresentation(for: request, foreground: true)
        await model.refresh(request: request, reader: scoped, presentation: permit)
        let selection = try XCTUnwrap(model.selections(for: request, filter: .unused).first)
        let detail = try await scoped.ownedCoupon(id: selection.historyID, lifetime: .init(ownerScope: scoped.scope))
        XCTAssertEqual(detail.id, 101)
        XCTAssertEqual(model.rows(for: request)?.map(\.id), [101])
        XCTAssertEqual(Set(wire.paths), ["myrecvlist"])
        do { _ = try await scoped.favoriteTopics(pageNumber: 1, pageSize: 10); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
    }
    func testRetainedSelfProfileCouponEntryCannotFollowReissuedApprovalOrViewer() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession()
        await login(session); wire.requests = []
        let social = SelfCouponSocial(), access = ProfileSelfCouponAccess(reader: session.profileOwnedCouponReader, owner: .init(accountID: 81, epoch: 1, role: "player"))
        let context = try XCTUnwrap(ProfileSelfCouponContext.capture(memberID: 81, accountReader: social, access: access, isCurrent: true))
        let scoped = ProfileSelfCouponScopedReader(context: context, accountReader: social, access: access, isCurrent: { true })
        social.presentationRevision += 1
        XCTAssertFalse(scoped.associationIsCurrent)
        do { _ = try await scoped.ownedCoupons(keyword: nil); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        social.presentationRevision = 0
        grants.retained = nil
        XCTAssertFalse(scoped.associationIsCurrent)
        do { _ = try await scoped.ownedCoupons(keyword: nil); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testSelfProfileCouponRetiredRouteRejectsLateResult() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession()
        await login(session)
        let social = SelfCouponSocial(), access = ProfileSelfCouponAccess(reader: session.profileOwnedCouponReader, owner: .init(accountID: 81, epoch: 1, role: "player"))
        let context = try XCTUnwrap(ProfileSelfCouponContext.capture(memberID: 81, accountReader: social, access: access, isCurrent: true))
        var current = true
        let scoped = ProfileSelfCouponScopedReader(context: context, accountReader: social, access: access, isCurrent: { current })
        wire.hold = true; let started = expectation(description: "self coupon pending"); wire.onHeld = { started.fulfill() }
        let task = Task { try await scoped.ownedCoupons(keyword: nil) }
        await fulfillment(of: [started], timeout: 2)
        current = false; wire.finish(status: 200)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(scoped.isConfigured)
    }
    func testSelfProfileCouponRetiredRouteLate401DoesNotExpireSameAccount() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession()
        await login(session)
        let social = SelfCouponSocial(), access = ProfileSelfCouponAccess(reader: session.profileOwnedCouponReader, owner: .init(accountID: 81, epoch: 1, role: "player"))
        let context = try XCTUnwrap(ProfileSelfCouponContext.capture(memberID: 81, accountReader: social, access: access, isCurrent: true))
        var current = true
        let scoped = ProfileSelfCouponScopedReader(context: context, accountReader: social, access: access, isCurrent: { current })
        wire.hold = true; let started = expectation(description: "self coupon pending 401"); wire.onHeld = { started.fulfill() }
        let task = Task { try await scoped.ownedCoupons(keyword: nil, lifetime: .init(ownerScope: scoped.scope)) }
        await fulfillment(of: [started], timeout: 2)
        current = false; wire.finish(status: 401)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.account?.id, 81)
    }
    @MainActor private final class SelfCouponSocial: SocialAccountReading {
        var identity = SocialAccountIdentity(accountID: 81, epoch: 1, role: "player")
        var presentationRevision: UInt64 = 0
        var isConfigured = true
        var isOfflineExample = false
        func publicProfile(memberID: Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
        func informationList() async throws -> [SocialInformation] { throw APIError.notConfigured }
        func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
        func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
    }
    @MainActor private final class Grants {
        var enabled = true; var retained: ProfileOwnedCouponReadAccess?
        func select(_ context: RuntimeDependencyContext) -> ProfileOwnedCouponReadAccess? {
            guard enabled else { return nil }
            if retained == nil, let approval = try? OperationEndpointApproval(baseURL: context.baseURL,
                namespace: context.session.namespace, accountID: context.session.accountID, paths: ProfileOwnedCouponReadRoute.paths) {
                retained = try? .init(context: context, approval: approval)
            }
            return retained
        }
    }
    @MainActor private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], keywords: [String?] = []
        var account = 81, status = 200
        var responseOverride: String?, hold = false, onHeld: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?
        var paths: [String] { requests.compactMap { $0.url?.lastPathComponent } }
        func finish(status: Int) { let saved = pending; pending = nil; saved?.resume(returning: (Data(#"{"code":200,"data":[]}"#.utf8), status)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.lastPathComponent
            if path == "phone" { return (try JSONSerialization.data(withJSONObject: ["code":200,"token":"synthetic-coupon","data":["id":account,"role":"player"]]), 200) }
            if path == "userInfo" { return (try JSONSerialization.data(withJSONObject: ["code":200,"appUser":["userId":account,"role":"player"]]), 200) }
            guard path == "myrecvlist" else { return (Data(#"{"code":404}"#.utf8), 404) }
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            let searched = body.contains("name=\"keyword\"\r\n\r\nTea\r\n"); keywords.append(searched ? "Tea" : nil)
            if hold { return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
            if let responseOverride { return (Data(responseOverride.utf8), status) }
            let rows: [[String: Any]] = (searched ? [0] : [0,1,2,3]).map { ["id":101+$0,"memberId":account,"couponId":501+$0,"useStatus":$0,"couponName":$0 == 0 ? "Tea" : "Other","couponCode":"never projected","qrcodeUrl":"never projected"] }
            return (try JSONSerialization.data(withJSONObject: ["code":200,"data":rows]), status)
        }
    }
}
