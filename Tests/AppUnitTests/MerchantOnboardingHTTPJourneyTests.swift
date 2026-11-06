import XCTest
import Combine
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Questify

/// Synthetic HTTP only. No live registration, upload, or device permission.
@MainActor final class MerchantOnboardingHTTPJourneyTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var application = #"{"code":200,"applicationState":"NONE","data":null}"#
        var identity = #"{"code":200,"data":{"registered":true}}"#
        var writeBody = #"{"code":200}"#
        var writeStatus = 200
        var loseWrite = false
        var failReadback = false
        var onWrite: (() -> Void)?
        var writes: [URLRequest] { requests.filter { $0.url?.path == "/api/merchant/merchant_registration" } }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            switch request.url?.path {
            case "/api/merchant/info":
                if failReadback && !writes.isEmpty { throw URLError(.networkConnectionLost) }
                return (Data(application.utf8), 200)
            case "/api/publisher/identity/status": return (Data(identity.utf8), 200)
            case "/api/merchant/merchant_registration":
                onWrite?()
                if loseWrite { throw URLError(.networkConnectionLost) }
                return (Data(writeBody.utf8), writeStatus)
            default: XCTFail("Unexpected HTTP endpoint"); throw APIError.invalidRequest
            }
        }
    }
    @MainActor private final class Harness {
        let wire = Wire()
        var session: MerchantOnboardingSession?
        var unauthorized: [ProfileReadIdentity] = []
        let service: MerchantOnboardingService
        lazy var adapter = MerchantOnboardingSessionAdapter(service: service,
            currentSession: { [weak self] in self?.session },
            onUnauthorized: { [weak self] in self?.unauthorized.append($0.identity) })
        lazy var coordinator = MerchantOnboardingCoordinator(server: adapter)
        lazy var model = MerchantOnboardingModel(coordinator: coordinator)
        init() throws {
            session = try .init(accountID: 7, epoch: 1, token: "synthetic-first")
            service = MerchantOnboardingService(configuration: try APIConfiguration(baseURL: URL(string: "https://onboarding.example.test")!), transport: wire)
        }
        func ready() async throws {
            model.reset(); await model.load(); await model.checkIdentity()
            var draft = MerchantOnboardingDraft()
            draft.name = " Exact synthetic store "
            draft.phone = "2025550100"; draft.address = "Synthetic address"
            draft.businessTime = "Stored hours"
            draft.license = try .init(serverURL: "https://fixtures.example/license.jpg")
            model.draft = draft
        }
    }
    private func submit(_ h: Harness) async throws {
        h.model.prepare()
        _ = try XCTUnwrap(h.model.confirmation)
        let finished = expectation(description: "Real app model finishes original HTTP submission")
        let subscription = h.model.$isBusy.dropFirst().filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
        h.model.submitConfirmed()
        await fulfillment(of: [finished], timeout: 2)
        withExtendedLifetime(subscription) {}
    }
    func testAcknowledgedWireThenFailedReadbackStaysLockedWithoutInventingApproval() async throws {
        let h = try Harness(); try await h.ready()
        h.wire.failReadback = true
        try await submit(h)
        XCTAssertEqual(h.coordinator.submission, .acknowledged)
        XCTAssertEqual(h.coordinator.loadState, .unavailable)
        XCTAssertTrue(h.coordinator.submission.isLocked)
        XCTAssertEqual(h.wire.writes.count, 1)
        h.model.prepare(); XCTAssertNil(h.model.confirmation)
        XCTAssertEqual(h.wire.writes.count, 1)
        let body = try XCTUnwrap(h.wire.writes.first?.httpBody)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(fields["name"] as? String, "Exact synthetic store")
        XCTAssertEqual(fields["businessLicense"] as? String, "https://fixtures.example/license.jpg")
        XCTAssertNil(fields["status"]); XCTAssertNil(fields["accountStatus"]); XCTAssertNil(fields["roleCode"])
        XCTAssertEqual(h.wire.requests.compactMap { $0.url?.path }, [
            "/api/merchant/info", "/api/publisher/identity/status",
            "/api/merchant/info", "/api/publisher/identity/status",
            "/api/merchant/merchant_registration", "/api/merchant/info"])
    }
    func testUnknownHTTPOutcomeRemainsLockedOnSameCoordinatorReentryAndExplicitNone() async throws {
        let h = try Harness(); try await h.ready()
        h.wire.loseWrite = true
        try await submit(h)
        XCTAssertEqual(h.coordinator.submission, .outcomeUnknown)
        h.model.leave(); h.model.reset(); await h.model.load()
        XCTAssertEqual(h.coordinator.loadState, .loaded(.none))
        XCTAssertEqual(h.coordinator.submission, .outcomeUnknown)
        XCTAssertTrue(h.coordinator.submission.isLocked)
        h.model.prepare(); h.model.submitConfirmed()
        XCTAssertNil(h.model.confirmation)
        XCTAssertEqual(h.wire.writes.count, 1)
    }
    func testIdentityRevokedAtFinalHTTPPreflightDoesNotDispatchRegistration() async throws {
        let h = try Harness(); try await h.ready()
        h.wire.identity = #"{"code":200,"data":{"registered":false}}"#
        try await submit(h)
        XCTAssertEqual(h.coordinator.identityGate, .required)
        XCTAssertEqual(h.coordinator.submission, .notSent)
        XCTAssertTrue(h.wire.writes.isEmpty)
        XCTAssertFalse(h.model.draft.name.isEmpty)
    }
    func testOldTokenLate401CannotLogOutReplacementSessionOrUnlockOriginalAccount() async throws {
        let h = try Harness(); try await h.ready()
        h.model.prepare(); let review = try XCTUnwrap(h.model.confirmation)
        let replacement = try MerchantOnboardingSession(accountID: 8, epoch: 2, token: "synthetic-replacement")
        h.wire.onWrite = { h.session = replacement; h.model.reset() }
        h.wire.writeStatus = 401; h.wire.writeBody = #"{"code":401}"#
        await h.coordinator.confirm(review)
        XCTAssertEqual(h.session, replacement)
        XCTAssertTrue(h.unauthorized.isEmpty)
        XCTAssertEqual(h.model.identity, replacement.identity)
        XCTAssertEqual(h.model.draft, MerchantOnboardingDraft())
        XCTAssertEqual(h.wire.writes.count, 1)
        XCTAssertEqual(h.wire.writes.first?.value(forHTTPHeaderField: "Authorization"), "synthetic-first")
        h.session = try .init(accountID: 7, epoch: 3, token: "synthetic-return")
        h.model.reset(); await h.model.load()
        XCTAssertEqual(h.coordinator.submission, .outcomeUnknown)
        XCTAssertTrue(h.coordinator.submission.isLocked)
        XCTAssertEqual(h.wire.writes.count, 1)
    }
}
