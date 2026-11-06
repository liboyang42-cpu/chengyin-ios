import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileInviteHistoryReadTests: XCTestCase {
    private let base = URL(string: "https://invite.example/native")!
    private func root(_ wire: Wire, _ grants: Grants? = nil, vault: Vault? = nil) throws -> AppCompositionRoot {
        let vault = vault ?? Vault(), suite = "invite-read-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.profile-invite", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, profileInviteHistoryReadAccess: { grants?.select($0) })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    private func request(path: String = ProfileInviteHistoryReadRoute.invitations, page: String = "1", size: String = "100") throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: ["pageNum": page, "pageSize": size], token: "synthetic-invite")
    }
    func testNormalSessionDefaultNilIsUnavailableWithoutInvitationDispatch() async throws {
        let wire = Wire(), session = try root(wire).makeSession(); await login(session); wire.requests = []
        let reader = session.profileInviteHistoryReader
        XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.invitationHistory(page: 1); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
        XCTAssertTrue(session.socialAccountReader.isConfigured)
    }
    func testFullNormalReaderPagesRewardsProjectionAndCoveredReturn() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession(); await login(session); wire.requests = []
        let reader = session.profileInviteHistoryReader, model = SocialInviteHistoryModel()
        await model.appear(reader)?.value
        XCTAssertEqual(model.pagination.members.map(\.id), [201, 202]); XCTAssertTrue(model.scan?.isComplete == true)
        XCTAssertEqual(wire.paths, ["invite_list", "list"])
        await model.start(reader, permit: model.permit(reader), reset: false)?.value
        XCTAssertEqual(model.pagination.members.map(\.id), [201, 202, 203]); XCTAssertFalse(model.pagination.hasMore)
        XCTAssertEqual(model.timeline(reader)?.months.map(\.id), ["2026-10", "", "2026-09"])
        XCTAssertEqual(ProfileInviteRewardReview(scan: model.scan).cumulativePoints, Decimal(string: "2.5"))
        let old = model.permit(reader); model.suspend()
        XCTAssertEqual(model.pagination.members.count, 3); XCTAssertNil(model.start(reader, permit: old, reset: true))
        let count = wire.requests.count; await model.appear(reader)?.value
        XCTAssertEqual(model.pagination.members.map(\.id), [201, 202]); XCTAssertEqual(wire.requests.count, count + 2)
    }
    func testFailedPageRetriesThatSamePageWithoutSkippingOrLosingLoadedRows() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session)
        let model = SocialInviteHistoryModel(), reader = session.profileInviteHistoryReader
        await model.appear(reader)?.value; wire.failPageTwoOnce = true
        await model.start(reader, permit: model.permit(reader), reset: false)?.value
        XCTAssertNotNil(model.error); XCTAssertEqual(model.pagination.nextPage, 2); XCTAssertEqual(model.pagination.members.count, 2)
        await model.start(reader, permit: model.permit(reader), reset: false)?.value
        XCTAssertNil(model.error); XCTAssertEqual(model.pagination.members.count, 3); XCTAssertEqual(wire.invitationPages, [1, 2, 2])
    }
    func testRewardFailureRetainsInvitationRowsAndUnknownInsteadOfZero() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.rewardFailure = true
        let value = try await session.profileInviteHistoryReader.invitationHistory(page: 1)
        XCTAssertEqual(value.page.members.count, 2); XCTAssertNil(value.rewardScan)
        XCTAssertNil(ProfileInviteRewardReview(scan: value.rewardScan).cumulativePoints)
        wire.rewardFailure = false
        let retried = try await session.profileInviteHistoryReader.invitationHistory(page: 1)
        XCTAssertNotNil(retried.rewardScan)
    }
    func testMalformedOrMissingInvitationDataIsNeverSuccessfulEmptyState() async throws {
        for malformed in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{"rows":{}}}"#, #"{"code":200,"data":{"rows":[{"id":0}],"total":1}}"#] {
            let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.invitationOverride = malformed; wire.requests = []
            do { _ = try await session.profileInviteHistoryReader.invitationHistory(page: 1); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
            XCTAssertEqual(wire.paths, ["invite_list"])
        }
    }
    func testExplicitSuccessfulEmptyInvitationsRemainRealEmptyResult() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session)
        wire.invitationOverride = #"{"code":200,"data":{"rows":[],"total":0}}"#
        let value = try await session.profileInviteHistoryReader.invitationHistory(page: 1)
        XCTAssertTrue(value.page.members.isEmpty); XCTAssertEqual(value.page.total, 0)
    }
    func testLiveRevocationAndNewIssuanceChangeVisibleReaderRevision() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession(); await login(session)
        let reader = session.profileInviteHistoryReader; XCTAssertTrue(reader.isConfigured); let first = reader.presentationRevision
        grants.retained?.revoke(); XCTAssertFalse(reader.isConfigured); XCTAssertNotEqual(reader.presentationRevision, first)
        wire.requests = []; do { _ = try await reader.invitationHistory(page: 1); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
        grants.retained = nil; XCTAssertTrue(reader.isConfigured)
        _ = try await reader.invitationHistory(page: 1); XCTAssertEqual(wire.requests.count, 2)
    }
    func testRevocationAfterInvitesPreventsRewardReadAndAnyPartialPublish() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession(); await login(session); wire.requests = []
        wire.afterInvitation = { grants.retained?.revoke() }
        let model = SocialInviteHistoryModel(); await model.appear(session.profileInviteHistoryReader)?.value
        XCTAssertTrue(model.pagination.members.isEmpty); XCTAssertNil(model.scan); XCTAssertEqual(wire.paths, ["invite_list"])
    }
    func testTransportClonesKeepPurposeAndRejectWrongTokenAndOtherTargets() async throws {
        let wire = Wire(), transport = try root(wire, Grants()).transport()
        transport.current = { .init(epoch: 1, accountID: 81, role: "player", token: "synthetic-invite", viewerRevision: 1) }
        let clone = transport.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
        _ = try await clone.send(request())
        for path in ["api/user/public-info", "api/user/points/statistics", "api/points/list", "api/user/update"] {
            var wrong = try request(); wrong.url = base.appendingPathComponent(path)
            do { _ = try await clone.send(wrong); XCTFail() } catch {}
        }
        var wrong = try request(); wrong.setValue("other-synthetic", forHTTPHeaderField: "Authorization")
        do { _ = try await clone.send(wrong); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testStaleOwnerEpochTokenViewerOrGrantRejectsLateSuccessAnd401() async throws {
        for change in ["owner", "epoch", "token", "viewer", "role", "revoke", "replace", "remove"] {
            for status in [200, 401] {
                let wire = Wire(), grants = Grants(), transport = try root(wire, grants).transport()
                var identity = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 81, role: "player", token: "synthetic-invite", viewerRevision: 1)
                transport.current = { identity }; wire.hold = true
                let pending = expectation(description: "held invitation"); wire.onHeld = { pending.fulfill() }
                let task = Task { try await transport.send(request()) }; await fulfillment(of: [pending], timeout: 2)
                let access = try XCTUnwrap(grants.retained)
                switch change {
                case "owner": identity = .init(epoch: 2, accountID: 82, role: "player", token: "synthetic-invite", viewerRevision: 2)
                case "epoch": identity = .init(epoch: 2, accountID: 81, role: "player", token: "synthetic-invite", viewerRevision: 1)
                case "token": identity = .init(epoch: 1, accountID: 81, role: "player", token: "changed", viewerRevision: 1)
                case "role": identity = .init(epoch: 1, accountID: 81, role: "merchant", token: "synthetic-invite", viewerRevision: 1)
                case "viewer": identity = .init(epoch: 1, accountID: 81, role: "player", token: "synthetic-invite", viewerRevision: 2)
                case "revoke": access.revoke()
                case "replace": grants.retained = try .init(context: access.context, approval: access.endpoints)
                default: grants.enabled = false
                }
                wire.finish(status: status)
                do { _ = try await task.value; XCTFail(change) } catch { XCTAssertTrue(error is CancellationError) }
            }
        }
    }
    func testCurrent401ExpiresCurrentAccountAndClearsItsVault() async throws {
        for reward in [false, true] {
            let wire = Wire(), vault = Vault(), session = try root(wire, Grants(), vault: vault).makeSession(); await login(session)
            wire.unauthorizedPath = reward ? "list" : "invite_list"
            do { _ = try await session.profileInviteHistoryReader.invitationHistory(page: 1); XCTFail() } catch {}
            XCTAssertNil(session.account); XCTAssertNil(vault.value)
        }
    }
    func testMissingAccessGuestAndWrongPurposeCannotDispatch() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession()
        XCTAssertFalse(session.profileInviteHistoryReader.isConfigured)
        do { _ = try await session.profileInviteHistoryReader.invitationHistory(page: 1); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
        await login(session); grants.enabled = false; wire.requests = []
        do { _ = try await session.profileInviteHistoryReader.invitationHistory(page: 1); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testDefaultNilTransportRejectsBothExactRoutesBeforeUnderlyingDispatch() async throws {
        let wire = Wire(), transport = try root(wire).transport()
        transport.current = { .init(epoch: 1, accountID: 81, role: "player", token: "synthetic-invite", viewerRevision: 1) }
        for r in [try request(), try request(path: ProfileInviteHistoryReadRoute.rewards, size: "200")] {
            do { _ = try await transport.send(r); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testApprovalInstalledLaterEnablesExistingReaderWithoutBorrowingOtherApproval() async throws {
        let wire = Wire(), grants = Grants(); grants.enabled = false
        let session = try root(wire, grants).makeSession(); await login(session); wire.requests = []
        let reader = session.profileInviteHistoryReader; XCTAssertFalse(reader.isConfigured)
        let revision = reader.presentationRevision; grants.enabled = true
        XCTAssertTrue(reader.isConfigured); XCTAssertNotEqual(reader.presentationRevision, revision)
        let value = try await reader.invitationHistory(page: 1)
        XCTAssertEqual(value.page.members.count, 2); XCTAssertEqual(wire.requests.count, 2)
    }
    func testMalformedRewardDataCannotBecomeZeroOrSynchronized() async throws {
        for malformed in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{"rows":{},"total":0}}"#] {
            let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session)
            wire.rewardOverride = malformed
            let value = try await session.profileInviteHistoryReader.invitationHistory(page: 1)
            XCTAssertEqual(value.page.members.count, 2); XCTAssertNil(value.rewardScan); XCTAssertFalse(value.rewardsReady)
            XCTAssertNil(ProfileInviteRewardReview(scan: value.rewardScan).cumulativePoints)
        }
    }
    func testOrdinaryHistoryDestinationUsesSameSessionReaderAndLoadsTwoRequests() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.requests = []
        let host = UIHostingController(rootView: NavigationStack {
            SocialInviteHistoryView(reader: session.profileInviteHistoryReader, squareReader: session.squareReader)
        })
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        for _ in 0..<100 where wire.requests.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(wire.paths, ["invite_list", "list"])
    }
    @MainActor private final class Grants {
        var enabled = true; var retained: ProfileInviteHistoryReadAccess?
        func select(_ context: RuntimeDependencyContext) -> ProfileInviteHistoryReadAccess? {
            guard enabled else { return nil }
            if retained == nil {
                let approved = try? OperationEndpointApproval(baseURL: context.baseURL, namespace: context.session.namespace,
                    accountID: context.session.accountID, paths: ProfileInviteHistoryReadRoute.paths)
                if let approved { retained = try? .init(context: context, approval: approved) }
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
        var requests: [URLRequest] = [], invitationPages: [Int] = []
        var failPageTwoOnce = false, rewardFailure = false, hold = false
        var invitationOverride: String?, rewardOverride: String?, unauthorizedPath: String?
        var afterInvitation: (() -> Void)?, onHeld: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?
        var paths: [String] { requests.compactMap { $0.url?.lastPathComponent } }
        func finish(status: Int) { pending?.resume(returning: (Data(#"{"code":200,"data":{"rows":[],"total":0}}"#.utf8), status)); pending = nil }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.lastPathComponent
            if path == "phone" { return (Data(#"{"code":200,"token":"synthetic-invite","data":{"id":81,"role":"player"}}"#.utf8), 200) }
            if path == "userInfo" { return (Data(#"{"code":200,"appUser":{"userId":81,"role":"player"}}"#.utf8), 200) }
            if hold { return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
            if path == unauthorizedPath { return (Data(#"{"code":401}"#.utf8), 401) }
            if path == "invite_list" {
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                let page = body.contains("name=\"pageNum\"\r\n\r\n2\r\n") ? 2 : 1; invitationPages.append(page)
                if page == 2 && failPageTwoOnce { failPageTwoOnce = false; return (Data(), 503) }
                afterInvitation?()
                if let invitationOverride { return (Data(invitationOverride.utf8), 200) }
                let rows: [[String: Any]] = page == 1 ? [["id":201,"nickname":"Synthetic A","createTime":"2026-10-01 00:30:00"],["id":202,"nickname":"Synthetic B"]] : [["id":203,"nickname":"Synthetic C","createTime":"2026-09-30"]]
                return (try JSONSerialization.data(withJSONObject: ["code":200,"data":["rows":rows,"total":3]]), 200)
            }
            if path == "list" {
                if rewardFailure { return (Data(), 503) }
                if let rewardOverride { return (Data(rewardOverride.utf8), 200) }
                return (Data(#"{"code":200,"data":{"rows":[{"eventType":5,"eventId":"201","changePoints":"2.5","createTime":"2026-10-02 10:00:00"}],"total":1}}"#.utf8), 200)
            }
            return (Data(#"{"code":404}"#.utf8), 404)
        }
    }
}
