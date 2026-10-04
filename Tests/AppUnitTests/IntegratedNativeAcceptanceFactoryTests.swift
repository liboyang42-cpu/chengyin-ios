import XCTest
@testable import Questify

@MainActor final class IntegratedNativeAcceptanceFactoryTests: XCTestCase {
    private func container(_ mode: String = "ready") throws -> (AppSessionContainer, IntegratedNativeAcceptanceFixture, AppSession) {
        let container = AppSessionContainer(arguments: [IntegratedNativeAcceptanceFixture.flag, mode])
        let fixture = try XCTUnwrap(container.integratedAcceptance)
        let defaults = try XCTUnwrap(fixture.defaults), suite = fixture.suiteName
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (container, fixture, try XCTUnwrap(container.session))
    }
    private func signIn(_ session: AppSession, owner: Int = 7) async {
        // Unit proof invokes the same channel coordinator. The UI journey types and taps.
        await session.authChannels.loginWithPhone(phone: owner == 7 ? "10000000000" : "10000000001", code: "123456")
        XCTAssertEqual(session.account?.id, owner)
    }
    private func context(_ fixture: IntegratedNativeAcceptanceFixture, _ session: AppSession, owner: Int = 7) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: IntegratedNativeAcceptanceFixture.base, role: "player",
            session: try .init(accountID: owner, epoch: session.sessionRevision, namespace: fixture.deployment.storageScope.service, token: "synthetic-\(owner)"))
    }
    private enum PhoneProjectionFault: CaseIterable { case tokenOnly, malformedID, nonPositiveID, mismatchedID }
    /// Test-only fault injection around the same sealed recorder, never a live transport.
    @MainActor private final class FaultedPhoneProjection: HTTPTransport {
        let underlying: IntegratedNativeAcceptanceFixture
        let fault: PhoneProjectionFault
        init(underlying: IntegratedNativeAcceptanceFixture, fault: PhoneProjectionFault) {
            self.underlying = underlying; self.fault = fault
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let (data, status) = try await underlying.send(request)
            guard request.url?.path == "/native/api/login/phone" else { return (data, status) }
            var body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            switch fault {
            case .tokenOnly: body.removeValue(forKey: "data")
            case .malformedID: body["data"] = ["id": "not-an-id", "role": "player"]
            case .nonPositiveID: body["data"] = ["id": 0, "role": "player"] as [String: Any]
            case .mismatchedID: body["data"] = ["id": 8, "role": "player"] as [String: Any]
            }
            return (try JSONSerialization.data(withJSONObject: body), status)
        }
    }
    private func assertPhoneProjectionRejected(_ fault: PhoneProjectionFault) async throws {
        let fixture = try IntegratedNativeAcceptanceFixture(mode: .ready)
        let defaults = try XCTUnwrap(fixture.defaults), suite = fixture.suiteName
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let wire = FaultedPhoneProjection(underlying: fixture, fault: fault)
        let root = AppCompositionRoot(deployment: .reviewed(fixture.deployment),
            storage: .init(defaults: defaults, tokenStore: { _ in fixture.vault }), makeTransport: { wire })
        let session = root.makeSession(); fixture.session = session
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNil(session.account); XCTAssertNil(fixture.vault.value)
        XCTAssertEqual(session.authChannels.state.issue, .invalidResponse)
        XCTAssertEqual(fixture.ledger.map(\.route), fault == .mismatchedID ? ["phone", "userInfo"] : ["phone"])
        XCTAssertTrue(fixture.violations.isEmpty)
    }
    func testFactoryIsOptInUsesRealContainerAndKeepsProductionDefaultsClosed() async throws {
        XCTAssertNil(IntegratedNativeAcceptanceFixture.selected(arguments: []))
        XCTAssertNil(RegionalLaunchConfiguration.composition.reviewed)
        let (container, fixture, session) = try container()
        XCTAssertTrue(container.session === session); XCTAssertTrue(fixture.session === session)
        if case .synthetic = fixture.makeComposition().storage.playRecovery {} else {
            XCTFail("Integrated acceptance must never select system Play recovery storage")
        }
        XCTAssertNil(session.account); XCTAssertNil(fixture.vault.value)
        await session.bootstrap(); XCTAssertTrue(fixture.ledger.isEmpty)
        await session.authChannels.sendSMSCode(phone: "10000000000")
        XCTAssertTrue(session.authChannels.state.smsSent)
        await signIn(session)
        XCTAssertEqual(fixture.ledger.map(\.route), ["sms-send", "phone", "userInfo"])
        XCTAssertEqual(fixture.ledger.first?.fields, ["phone": "10000000000"])
        XCTAssertEqual(session.account?.nickname, "Synthetic owner 7")
        XCTAssertEqual(fixture.vault.value, "synthetic-7")
        for fault in PhoneProjectionFault.allCases { try await assertPhoneProjectionRejected(fault) }
        let supplied = AppSessionContainer(composition: .init(), arguments: [IntegratedNativeAcceptanceFixture.flag, "ready"])
        XCTAssertNil(supplied.integratedAcceptance); XCTAssertFalse(try XCTUnwrap(supplied.session).isConfigured)
        withExtendedLifetime(container) {}
    }
    func testStableTypedIssuanceCurrentOwnerFenceAndLogoutReset() async throws {
        let (container, fixture, session) = try container(); await signIn(session)
        let root = fixture.makeComposition(), first = try context(fixture, session)
        let config = try XCTUnwrap(root.sessionDependencies(first).configuration)
        XCTAssertEqual(config.play, [.reads]); XCTAssertFalse(config.nearbyLocation); XCTAssertTrue(config.devices.isEmpty)
        XCTAssertEqual(config.playReadApprovalID, root.sessionDependencies(first).configuration?.playReadApprovalID)
        XCTAssertEqual(root.manualMapReadApproval(first)?.revision, root.manualMapReadApproval(first)?.revision)
        let oldOrderApproval = try XCTUnwrap(root.ownedOrderReadApproval(first))
        XCTAssertTrue(oldOrderApproval === root.ownedOrderReadApproval(first))
        let retainedReader = session.ownedOrderReader, oldPlay = session.playReader(for: .activity(21))
        let oldIdentity = try XCTUnwrap(retainedReader.identity)
        let capturedTransport = root.transport()
        capturedTransport.current = {
            .init(epoch: first.session.epoch, accountID: first.session.accountID, role: first.role, token: first.session.token)
        }
        let oldRequest = try AuthRequestBuilder.makeFormRequest(
            url: IntegratedNativeAcceptanceFixture.base.appendingPathComponent("api/registration/info"),
            fields: ["id": "41"], token: first.session.token)
        XCTAssertEqual(OwnedOrderReadRoute(request: oldRequest, baseURL: IntegratedNativeAcceptanceFixture.base), .detail(41))
        session.roamArea = IntegratedNativeAcceptanceFixture.area
        let places = try await session.roamReader.roamPlaces(radiusM: 3000); XCTAssertEqual(places.map(\.id), [42])
        let snapshot = try await oldPlay.playSession(); XCTAssertEqual(snapshot.visibleNodes.map(\.id), [1])
        let rows = try await retainedReader.profileOrders(), detail = try await retainedReader.profileOrder(id: 41)
        XCTAssertEqual(rows.first?.title, "Owner 7 list snapshot"); XCTAssertEqual(detail.title, "Owner 7 fresh detail")
        XCTAssertEqual(detail.payableAmount, Decimal(string: "12.3456"))
        await session.logout()
        XCTAssertNil(session.account); XCTAssertNil(fixture.vault.value); XCTAssertNil(session.roamArea)
        XCTAssertTrue(oldOrderApproval.isRevoked); XCTAssertNil(root.ownedOrderReadApproval(first)); XCTAssertNil(root.sessionDependencies(first).configuration)
        XCTAssertNil(oldPlay.identity); XCTAssertNil(retainedReader.identity)
        await signIn(session, owner: 8)
        let next = try context(fixture, session, owner: 8)
        XCTAssertNotEqual(config.playReadApprovalID, root.sessionDependencies(next).configuration?.playReadApprovalID)
        XCTAssertNil(root.manualMapReadApproval(first)); XCTAssertNil(root.ownedOrderReadApproval(first))
        let count = fixture.ledger.count
        // An old context cannot select a new owner's lease, even with a canonical request.
        do { _ = try await capturedTransport.send(oldRequest); XCTFail("Escaped owner context") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(fixture.ledger.count, count)
        // A current context still cannot dispatch an old owner's credential.
        capturedTransport.current = {
            .init(epoch: next.session.epoch, accountID: next.session.accountID, role: next.role, token: next.session.token)
        }
        do { _ = try await capturedTransport.send(oldRequest); XCTFail("Escaped owner credential") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fixture.ledger.count, count)
        XCTAssertFalse(oldOrderApproval.matches(first)); XCTAssertFalse(oldOrderApproval.matches(next))
        XCTAssertNil(oldPlay.identity)
        // AppSession intentionally retains this dynamic reader; new calls bind the current owner.
        XCTAssertTrue(retainedReader === session.ownedOrderReader)
        XCTAssertNotEqual(retainedReader.identity, oldIdentity)
        let current = try await retainedReader.profileOrder(id: 41)
        XCTAssertEqual(current.memberID, 8); XCTAssertEqual(current.title, "Owner 8 fresh detail")
        XCTAssertEqual(fixture.ledger.count, count + 1)
        XCTAssertEqual(fixture.ledger.last?.accountID, 8); XCTAssertEqual(fixture.ledger.last?.token, "synthetic-8")
        XCTAssertEqual(fixture.ledger.last?.epoch, next.session.epoch)
        XCTAssertTrue(fixture.violations.isEmpty)
        withExtendedLifetime(container) {}
    }
    func testMissingApprovalsAndUnexpectedMutationFailBeforeSyntheticDispatch() async throws {
        let (container, fixture, session) = try container("denied"); await signIn(session)
        session.roamArea = IntegratedNativeAcceptanceFixture.area
        let count = fixture.ledger.count
        do { _ = try await session.roamReader.roamPlaces(radiusM: 3000); XCTFail() } catch {}
        do { _ = try await session.playReader(for: .activity(21)).playSession(); XCTFail() } catch {}
        do { _ = try await session.ownedOrderReader.profileOrders(); XCTFail() } catch {}
        XCTAssertEqual(fixture.ledger.count, count); XCTAssertTrue(fixture.violations.isEmpty)
        let root = fixture.makeComposition().transport()
        root.current = { .init(epoch: session.sessionRevision, accountID: 7, role: "player", token: "synthetic-7") }
        for path in ["api/registration/create", "api/registration/pay", "api/play/answer", "api/roam/presence", "api/map/reverse-geocode"] {
            let request = try AuthRequestBuilder.makeFormRequest(url: IntegratedNativeAcceptanceFixture.base.appendingPathComponent(path), fields: [:], token: "synthetic-7")
            do { _ = try await root.send(request); XCTFail(path) } catch {}
        }
        XCTAssertEqual(fixture.ledger.count, count); XCTAssertTrue(fixture.violations.isEmpty)
        // Also prove the sealed recorder itself has no permissive fallback.
        let unexpected = try AuthRequestBuilder.makeFormRequest(url: IntegratedNativeAcceptanceFixture.base.appendingPathComponent("api/registration/pay"), fields: [:], token: "synthetic-7")
        do { _ = try await fixture.send(unexpected); XCTFail() } catch {}
        XCTAssertEqual(fixture.ledger.count, count); XCTAssertEqual(fixture.violations.count, 1)
        withExtendedLifetime(container) {}
    }
}
