import XCTest
import SwiftUI
@testable import Questify

@MainActor final class MerchantPredictionReadCompositionTests: XCTestCase {
    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var role = "player", allowed = true, status = 200
        var holdPath: String?, onHeld: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?, heldBody = Data()
        let row = #"{"nodeId":17,"topicId":4,"nodeName":"Shop","playDay":"2026-10-19","question":"A or B?","options":[{"key":"a","label":"A"},{"key":"b","label":"B"}],"betCount":2,"daysLeft":1}"#
        func resume(status: Int = 200) { let p = pending; pending = nil; p?.resume(returning: (heldBody, status)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.lastPathComponent
            if path == "phone" { return (Data(#"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"#.utf8), 200) }
            if path == "userInfo" { return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200) }
            let value = path == "me" ? "{\"active\":true,\"merchant\":{\"id\":31},\"roleCode\":\"MERCHANT_MANAGER\",\"permissions\":\(allowed ? "[\"merchant:project:manage\"]" : "[]")}" : "[\(row)]"
            let body = Data("{\"code\":200,\"data\":\(value)}".utf8)
            if path == holdPath { holdPath = nil; heldBody = body; return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
            return (body, status)
        }
    }
    private func deployment() throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: "https://prediction.example/native", approvedBaseURLs: [.china: ["https://prediction.example/native"]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.prediction", realm: "synthetic", reads: [.homeAndSearch])
    }
    private func normal(_ wire: Wire, enabled: Bool = true, wrongAccount: Bool = false, projectOnly: Bool = false) throws -> AppSession {
        let suite = "prediction-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), vault = Vault()
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AppCompositionRoot(deployment: .reviewed(try deployment()), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire },
            sessionDependencies: { context in
                if projectOnly { return .init(merchantProjectBrowseApproval: try? .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID)) }
                return .init(merchantPredictionReadApproval: enabled ? try? .init(market: context.market, baseURL: context.baseURL,
                    namespace: context.session.namespace, accountID: wrongAccount ? 8 : context.session.accountID) : nil)
            }).makeSession()
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    private func reader(_ wire: Wire) async throws -> (AppSession, MerchantPredictionReader) {
        let session = try normal(wire); await login(session); wire.requests = []
        return (session, try XCTUnwrap(session.merchantPredictionReader))
    }
    func testNormalInboxReviewUsesOnlyFreshCookieFreeReadsAndNeverSettlement() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire)
        let round = try JSONDecoder().decode(MerchantPredictionInboxRound.self, from: Data(wire.row.utf8))
        XCTAssertTrue(reader.supportsReview); XCTAssertTrue(reader.isolatedReader().supportsReview)
        let model = MerchantPredictionReviewPreparationModel()
        await model.prepare(round: round, optionKey: "a", reader: reader, isCurrent: { true })
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.review?.round.topicID, 4)
        XCTAssertEqual(model.review?.option.key, "a")
        XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["me", "inbox"])
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpBody == nil && !$0.httpShouldHandleCookies })
        let service = try XCTUnwrap(reader.makeReviewService(isCurrent: { true }))
        XCTAssertFalse(service.permitsSettlement); XCTAssertFalse(service.permitsInsight)
        let review = try await service.prepare(round: MerchantPredictionRound(inbox: round), optionKey: "a")
        let count = wire.requests.count
        do { _ = try await service.settle(review, acknowledgedCouponEffects: true); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantMarketingFailure, .unavailable) }
        XCTAssertEqual(wire.requests.count, count); XCTAssertEqual(session.account?.id, 7)
    }
    func testRetiredReviewRejectsLate401WithoutExpiringCurrentAccount() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire)
        let round = try JSONDecoder().decode(MerchantPredictionInboxRound.self, from: Data(wire.row.utf8))
        let model = MerchantPredictionReviewPreparationModel(), started = expectation(description: "review inbox")
        wire.holdPath = "inbox"; wire.onHeld = { started.fulfill() }
        let task = Task { await model.prepare(round: round, optionKey: "a", reader: reader, isCurrent: { true }) }
        await fulfillment(of: [started], timeout: 2)
        model.retire(); wire.resume(status: 401); await task.value
        XCTAssertEqual(model.phase, .retired); XCTAssertNil(model.review); XCTAssertEqual(session.account?.id, 7)
    }
    func testReviewRoleABARejectsOldRowsAndCannotFollowReplacementIdentity() async throws {
        for status in [200, 401] {
            let wire = Wire(), (session, reader) = try await self.reader(wire)
            let round = try JSONDecoder().decode(MerchantPredictionInboxRound.self, from: Data(wire.row.utf8))
            let model = MerchantPredictionReviewPreparationModel(), started = expectation(description: "old review context")
            wire.holdPath = "inbox"; wire.onHeld = { started.fulfill() }
            let task = Task { await model.prepare(round: round, optionKey: "a", reader: reader, isCurrent: { true }) }
            await fulfillment(of: [started], timeout: 2)
            wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
            wire.resume(status: status); await task.value
            XCTAssertEqual(model.phase, .retired); XCTAssertNil(model.review); XCTAssertEqual(session.account?.id, 7)
            XCTAssertNil(reader.makeReviewService(isCurrent: { true }))
        }
    }
    func testCurrentReview401StillExpiresOnlyItsMatchingSession() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire)
        let round = try JSONDecoder().decode(MerchantPredictionInboxRound.self, from: Data(wire.row.utf8))
        let model = MerchantPredictionReviewPreparationModel(); wire.status = 401
        await model.prepare(round: round, optionKey: "a", reader: reader, isCurrent: { true })
        XCTAssertNil(session.account); XCTAssertNil(model.review)
    }
    func testClosedReviewDuringAccessCannotReadInboxOrExpireAccount() async throws {
        for status in [200, 401] {
            let wire = Wire(), (session, reader) = try await self.reader(wire)
            let round = try JSONDecoder().decode(MerchantPredictionInboxRound.self, from: Data(wire.row.utf8))
            let model = MerchantPredictionReviewPreparationModel(); var visible = true
            let started = expectation(description: "review access pending")
            wire.holdPath = "me"; wire.onHeld = { started.fulfill() }
            let task = Task { await model.prepare(round: round, optionKey: "a", reader: reader, isCurrent: { visible }) }
            await fulfillment(of: [started], timeout: 2)
            visible = false; wire.resume(status: status); await task.value
            XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["me"])
            XCTAssertEqual(model.phase, .retired); XCTAssertNil(model.review); XCTAssertEqual(session.account?.id, 7)
        }
    }
    func testQueuedReviewRetryAfterPresentationClosesCannotReadOrReopenReview() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire)
        let round = try JSONDecoder().decode(MerchantPredictionInboxRound.self, from: Data(wire.row.utf8))
        let model = MerchantPredictionReviewPreparationModel(); var visible = true
        let queued = { await model.prepare(round: round, optionKey: "a", reader: reader, isCurrent: { visible }) }
        visible = false; model.retire(); await queued()
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertNil(model.review)
        XCTAssertEqual(model.phase, .retired); XCTAssertEqual(session.account?.id, 7)
    }
    func testClosedParentSnapshotCannotStartReviewRead() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire)
        let round = try JSONDecoder().decode(MerchantPredictionInboxRound.self, from: Data(wire.row.utf8))
        let model = MerchantPredictionReviewPreparationModel()
        await model.prepare(round: round, optionKey: "a", reader: reader, isCurrent: { false })
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertNil(model.review); XCTAssertEqual(model.phase, .retired)
        XCTAssertEqual(session.account?.id, 7)
    }
    func testNormalAdmissionAndInboxUseOnlyTwoCookieFreeReadRoutes() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire)
        let access = try await reader.access(), rows = try await reader.inbox(access: access)
        XCTAssertEqual(rows.map(\.id), ["17:2026-10-19"])
        XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["me", "inbox"])
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpBody == nil && !$0.httpShouldHandleCookies && $0.value(forHTTPHeaderField: "Authorization") == "synthetic-7" })
        XCTAssertEqual(session.account?.id, 7)
    }
    func testDormantWrongAccountAndProjectOnlyGrantsCannotCreatePredictionReader() async throws {
        XCTAssertNil(NativeRuntimeDependencies.dormant.merchantPredictionReadApproval)
        for mode in 0..<3 {
            let wire = Wire(), session = try normal(wire, enabled: mode != 0, wrongAccount: mode == 1, projectOnly: mode == 2)
            await login(session); wire.requests = []; XCTAssertNil(session.merchantPredictionReader); XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testServerDeniedAccessNeverReadsInbox() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire); wire.allowed = false
        let access = try await reader.access()
        do { _ = try await reader.inbox(access: access); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["me"]); XCTAssertEqual(session.account?.id, 7)
    }
    func testScopedTransportRejectsSettlementOtherRoutesAndBodyVariants() async throws {
        let d = try deployment(), wire = Wire(), root = CompositionHTTPTransport(deployment: d, underlying: wire)
        let api = try XCTUnwrap(d.regional.apiConfiguration)
        let context = RuntimeDependencyContext(market: .china, baseURL: api.baseURL, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: d.storageScope.service, token: "synthetic-7"))
        let approval = try MerchantPredictionReadApproval(market: .china, baseURL: api.baseURL, namespace: d.storageScope.service, accountID: 7)
        root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        let child = root.scopedForMerchantPrediction(approval: approval, context: context, approved: { true })
        var valid = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent("api/merchant/predict/inbox"), fields: [:], token: "synthetic-7", includesBody: false)
        valid.httpShouldHandleCookies = false
        do { _ = try await root.send(valid); XCTFail() } catch {}
        var bad: [URLRequest] = []
        for path in ["api/merchant/predict/settle", "api/merchant/predict/pending", "api/play/advanced/action", "api/project/my", "api/merchant/list"] {
            var r = valid; r.url = api.baseURL.appendingPathComponent(path); bad.append(r)
        }
        for header in ["Authorization", "Content-Type", "Cookie", "Proxy-Authorization"] { var r = valid; r.setValue("invalid", forHTTPHeaderField: header); bad.append(r) }
        for suffix in ["?nodeId=17", "#x", "/"] { var r = valid; r.url = URL(string: valid.url!.absoluteString + suffix); bad.append(r) }
        var body = valid; body.httpBody = Data("{}".utf8); bad.append(body)
        var stream = valid; stream.httpBodyStream = InputStream(data: Data()); bad.append(stream)
        var cookie = valid; cookie.httpShouldHandleCookies = true; bad.append(cookie)
        var method = valid; method.httpMethod = "GET"; bad.append(method)
        for r in bad { do { _ = try await child.send(r); XCTFail() } catch {} }
        XCTAssertTrue(wire.requests.isEmpty)
        _ = try await child.replacingUnderlying(wire).send(valid); XCTAssertEqual(wire.requests.count, 1)
    }
    func testRoleABARejectsLateInboxSuccessAnd401WithoutExpiringSuccessor() async throws {
        for status in [200, 401] {
            let wire = Wire(), (session, reader) = try await self.reader(wire), access = try await reader.access()
            let started = expectation(description: "held inbox"); wire.holdPath = "inbox"; wire.onHeld = { started.fulfill() }
            let task = Task { try await reader.inbox(access: access) }
            await fulfillment(of: [started], timeout: 2)
            wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
            wire.resume(status: status)
            do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertFalse(reader.isConfigured); XCTAssertEqual(session.account?.id, 7)
        }
    }
    func testEntryRefreshCannotInvalidateSeparateInboxProofGeneration() async throws {
        let wire = Wire(), (session, entry) = try await self.reader(wire), inbox = entry.isolatedReader()
        XCTAssertNotEqual(entry.id, inbox.id)
        let access = try await inbox.access(), started = expectation(description: "independent inbox")
        wire.holdPath = "inbox"; wire.onHeld = { started.fulfill() }
        let task = Task { try await inbox.inbox(access: access) }
        await fulfillment(of: [started], timeout: 2)
        _ = try await entry.access(); wire.resume()
        let rows = try await task.value; XCTAssertEqual(rows.count, 1); XCTAssertEqual(session.account?.id, 7)
    }
    func testSupersededAccess401CannotExpireNewAccess() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire), started = expectation(description: "held access")
        wire.holdPath = "me"; wire.onHeld = { started.fulfill() }
        let task = Task { try await reader.access() }
        await fulfillment(of: [started], timeout: 2)
        let fresh = try await reader.access(); wire.resume(status: 401)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        _ = try await reader.inbox(access: fresh); XCTAssertEqual(session.account?.id, 7)
    }
    func testCurrent401StillExpiresMatchingSession() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire); wire.status = 401
        do { _ = try await reader.access(); XCTFail() } catch {}
        XCTAssertNil(session.account)
    }
    func testAdmissionReadsNoInboxAndFreshModelProducesSnapshotDetail() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire), model = MerchantPredictionInboxModel(reader: reader)
        await model.load(inbox: false); XCTAssertTrue(model.canEnter); XCTAssertEqual(model.phase, .admitted)
        XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["me"])
        await model.load(); let round = try XCTUnwrap(model.rows.first); model.open(round)
        let selected = try XCTUnwrap(model.selection); XCTAssertTrue(model.isCurrent(selected)); model.didPresent(id: selected.id)
        let count = wire.requests.count
        model.close(id: selected.id); model.open(round); XCTAssertNil(model.selection)
        model.didDismiss(id: selected.id); model.open(round); XCTAssertNotNil(model.selection)
        XCTAssertEqual(wire.requests.count, count); XCTAssertEqual(session.account?.id, 7)
    }
    func testUnpresentedSelectionInvalidationDoesNotBlockNextOpening() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire), model = MerchantPredictionInboxModel(reader: reader)
        await model.load(); model.open(try XCTUnwrap(model.rows.first)); let old = try XCTUnwrap(model.selection)
        model.retire(); await model.load(); model.open(try XCTUnwrap(model.rows.first))
        let fresh = try XCTUnwrap(model.selection); XCTAssertNotEqual(fresh.id, old.id)
        model.didDismiss(id: old.id); XCTAssertEqual(model.selection?.id, fresh.id); XCTAssertEqual(session.account?.id, 7)
    }
    func testOldBindingCannotDismissReplacementSnapshot() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire), model = MerchantPredictionInboxModel(reader: reader)
        await model.load(); model.open(try XCTUnwrap(model.rows.first))
        let oldBinding = model.selectionBinding(), old = try XCTUnwrap(oldBinding.wrappedValue); model.didPresent(id: old.id)
        await model.load(); XCTAssertFalse(model.isCurrent(old)); model.didDismiss(id: old.id)
        model.open(try XCTUnwrap(model.rows.first)); let fresh = try XCTUnwrap(model.selection)
        oldBinding.wrappedValue = nil; model.close(id: old.id)
        XCTAssertEqual(model.selection?.id, fresh.id); XCTAssertEqual(session.account?.id, 7)
    }
    func testRetirementDiscardsLateRowsAndRevokedPermissionClearsDetails() async throws {
        let wire = Wire(), (session, reader) = try await self.reader(wire), model = MerchantPredictionInboxModel(reader: reader)
        let started = expectation(description: "retired inbox"); wire.holdPath = "inbox"; wire.onHeld = { started.fulfill() }
        let task = Task { await model.load() }; await fulfillment(of: [started], timeout: 2)
        model.retire(); wire.resume(); await task.value
        XCTAssertTrue(model.rows.isEmpty); XCTAssertEqual(model.phase, .idle)
        await model.load(); model.open(try XCTUnwrap(model.rows.first)); wire.allowed = false; await model.load()
        XCTAssertEqual(model.phase, .denied); XCTAssertTrue(model.rows.isEmpty); XCTAssertNil(model.selection); XCTAssertEqual(session.account?.id, 7)
    }
}
