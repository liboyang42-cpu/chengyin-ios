import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic Core boundaries only. These tests do not prove an App transport's final-forward fence.
@MainActor final class NativeWebhookRuntimeRetirementTests: XCTestCase {
    private func fixture() throws -> (NativeWebhookCoordinator, NativeWebhookHTTPService, NativeWebhookFixtureTransport, NativeWebhookMemoryJournal) {
        let provider = NativeWebhookFixtureProvider(try NativeWebhookFixtures.context())
        let transport = NativeWebhookFixtureTransport { request in
            if request.httpMethod != "GET" {
                return (NativeWebhookFixtures.envelope(NativeWebhookFixtures.resourceJSON(revision: 5, keyVersion: 3)), 200)
            }
            if request.url?.path == NativeWebhookRuntimeRoute.collection(.subscription) {
                return (NativeWebhookFixtures.list(), 200)
            }
            return (NativeWebhookFixtures.envelope(NativeWebhookFixtures.resourceJSON()), 200)
        }
        let journal = NativeWebhookMemoryJournal()
        let service = NativeWebhookHTTPService(provider: provider, authorizer: provider, transport: transport)
        let flow = NativeWebhookCoordinator(service: service, provider: provider,
            journal: NativeWebhookPendingJournal(journal: journal))
        return (flow, service, transport, journal)
    }

    func testUnboundFixtureKeepsCurrentPresentationAndOriginalBackgroundSemantics() async throws {
        let (flow, _, transport, journal) = try fixture()
        XCTAssertTrue(flow.presentationIsCurrent())
        await flow.load()
        flow.prepareAction(.rotate, resource: try NativeWebhookFixtures.resource())
        let confirmation = try XCTUnwrap(flow.confirmation)
        transport.respond = { request in
            if request.httpMethod != "GET" {
                flow.background()
                return (NativeWebhookFixtures.envelope(NativeWebhookFixtures.resourceJSON(revision: 5, keyVersion: 3,
                    extra: #", "secret_shown_once":true,"secret":"synthetic-secret""#)), 200)
            }
            if request.url?.path == NativeWebhookRuntimeRoute.collection(.subscription) {
                return (NativeWebhookFixtures.list(), 200)
            }
            return (NativeWebhookFixtures.envelope(NativeWebhookFixtures.resourceJSON()), 200)
        }
        await flow.confirm(confirmation.id)
        XCTAssertTrue(flow.presentationIsCurrent())
        XCTAssertNil(flow.credential)
        XCTAssertNil(journal.record)
    }

    func testInvalidateBackgroundAndLeaveRetireBeforeAnyPresentationCallback() throws {
        for action in ["invalidate", "background", "leave"] {
            let (flow, _, _, _) = try fixture()
            var retired = false
            var retirementCalls = 0
            var changes = 0
            XCTAssertTrue(flow.bindRuntimeRetirement({ retired = true; retirementCalls += 1 },
                presentationIsCurrent: { !retired }))
            flow.onChange = {
                changes += 1
                XCTAssertTrue(retired, "Retirement must precede onChange for \(action)")
                XCTAssertFalse(flow.presentationIsCurrent())
            }
            switch action {
            case "invalidate": flow.invalidate()
            case "background": flow.background()
            default: flow.leave()
            }
            XCTAssertEqual(retirementCalls, 1)
            XCTAssertGreaterThan(changes, 0)
            XCTAssertFalse(flow.presentationIsCurrent())
        }
    }

    func testDuplicateBindingCannotReplaceEitherOriginalClosure() throws {
        let (flow, _, _, _) = try fixture()
        var originalCalls = 0
        var replacementCalls = 0
        var originalCurrent = true
        XCTAssertTrue(flow.bindRuntimeRetirement({ originalCalls += 1 }, presentationIsCurrent: { originalCurrent }))
        XCTAssertFalse(flow.bindRuntimeRetirement({ replacementCalls += 1 }, presentationIsCurrent: { true }))
        originalCurrent = false
        XCTAssertFalse(flow.presentationIsCurrent(), "The replacement predicate must not revive the original visit")
        flow.invalidate()
        XCTAssertEqual(originalCalls, 1)
        XCTAssertEqual(replacementCalls, 0)
    }

    func testRetirementFromConfirmOnChangePreventsReservationAndDispatch() async throws {
        let (flow, _, transport, journal) = try fixture()
        var current = true
        XCTAssertTrue(flow.bindRuntimeRetirement({ current = false }, presentationIsCurrent: { current }))
        await flow.load()
        flow.prepareAction(.rotate, resource: try NativeWebhookFixtures.resource())
        let confirmation = try XCTUnwrap(flow.confirmation)
        let count = transport.requests.count
        var revokedDuringChange = false
        flow.onChange = {
            if flow.busy && !revokedDuringChange {
                revokedDuringChange = true
                current = false
            }
        }
        await flow.confirm(confirmation.id)
        XCTAssertTrue(revokedDuringChange)
        XCTAssertFalse(flow.presentationIsCurrent())
        XCTAssertNil(journal.record, "An already retired visit must not reserve a new original request")
        XCTAssertEqual(transport.requests.count, count)
        XCTAssertFalse(transport.requests.contains { $0.httpMethod != "GET" })
    }

    func testRetirementDuringMutationResponseRetainsExactOriginalJournal() async throws {
        let (flow, _, transport, journal) = try fixture()
        var current = true
        XCTAssertTrue(flow.bindRuntimeRetirement({ current = false }, presentationIsCurrent: { current }))
        await flow.load()
        flow.prepareAction(.rotate, resource: try NativeWebhookFixtures.resource())
        let confirmation = try XCTUnwrap(flow.confirmation)
        var original: OperationPendingRecord?
        transport.respond = { request in
            XCTAssertNotEqual(request.httpMethod, "GET", "Retired receipt must not start follow-up reads")
            original = journal.record
            XCTAssertEqual(original?.nativeWebhook?.requestID, confirmation.requestID)
            current = false
            return (NativeWebhookFixtures.envelope(NativeWebhookFixtures.resourceJSON(revision: 5, keyVersion: 3,
                extra: #", "secret_shown_once":true,"secret":"synthetic-secret""#)), 200)
        }
        await flow.confirm(confirmation.id)
        XCTAssertNotNil(original)
        XCTAssertEqual(journal.record, original)
        XCTAssertEqual(journal.record?.nativeWebhook?.requestID, confirmation.requestID)
        XCTAssertNil(flow.credential)
        XCTAssertNil(flow.notice)
        XCTAssertEqual(transport.requests.filter { $0.httpMethod != "GET" }.count, 1)
    }

    func testRetiredPresentationCannotLoadOrPrepareNewRequests() async throws {
        let (flow, _, transport, journal) = try fixture()
        XCTAssertTrue(flow.bindRuntimeRetirement({}, presentationIsCurrent: { false }))
        await flow.load()
        flow.prepareAction(.rotate, resource: try NativeWebhookFixtures.resource())
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertNil(flow.confirmation)
        XCTAssertNil(journal.record)
    }

    func testReadAndMutationRequestsDisableAutomaticCookies() async throws {
        let (flow, _, transport, _) = try fixture()
        await flow.load()
        flow.prepareAction(.rotate, resource: try NativeWebhookFixtures.resource())
        await flow.confirm(try XCTUnwrap(flow.confirmation).id)
        XCTAssertTrue(transport.requests.contains { $0.httpMethod == "GET" })
        XCTAssertTrue(transport.requests.contains { $0.httpMethod == "POST" })
        for request in transport.requests {
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
    }
    func testRestrictionsComposeAndCannotRestoreOriginalFalsePredicate() throws {
        let (flow, _, _, _) = try fixture()
        var original = true, child = true
        var retired = 0
        XCTAssertTrue(flow.bindRuntimeRetirement({ retired += 1 }, presentationIsCurrent: { original }))
        flow.restrictPresentation(to: { child })
        XCTAssertTrue(flow.presentationIsCurrent())
        child = false
        flow.restrictPresentation(to: { true })
        XCTAssertFalse(flow.presentationIsCurrent())
        XCTAssertEqual(retired, 1)
        child = true; original = false
        XCTAssertFalse(flow.presentationIsCurrent())
    }

    func testFalseRestrictionRetiresSynchronouslyBeforePresentationCallback() throws {
        let (flow, _, _, _) = try fixture()
        var retired = false, observed = false
        XCTAssertTrue(flow.bindRuntimeRetirement({ retired = true }))
        flow.onChange = { observed = true; XCTAssertTrue(retired); XCTAssertFalse(flow.presentationIsCurrent()) }
        flow.restrictPresentation(to: { false })
        XCTAssertTrue(retired); XCTAssertTrue(observed)
        XCTAssertEqual(flow.phase, .revoked)
    }

    func testRestrictionInstalledBeforeBindingCannotBeReplacedByBinding() throws {
        let (flow, _, _, _) = try fixture()
        flow.restrictPresentation(to: { false })
        var retired = 0
        XCTAssertTrue(flow.bindRuntimeRetirement({ retired += 1 }, presentationIsCurrent: { true }))
        XCTAssertFalse(flow.presentationIsCurrent()); XCTAssertEqual(retired, 1)
        XCTAssertFalse(flow.bindRuntimeRetirement({}, presentationIsCurrent: { true }))
        XCTAssertFalse(flow.presentationIsCurrent()); XCTAssertEqual(retired, 1)
    }

    func testCancellationDuringAuthorizationCannotReachTransport() async throws {
        let provider = NativeWebhookFixtureProvider(try NativeWebhookFixtures.context())
        let wire = NativeWebhookFixtureTransport { _ in XCTFail("Cancelled authorization cannot dispatch"); return (Data(), 200) }
        let authorizer = RetirementAuthorizer(provider: provider, cancel: true)
        let service = NativeWebhookHTTPService(provider: provider, authorizer: authorizer, transport: wire)
        let task = Task { try await service.resources(.subscription, context: provider.value) }
        do { _ = try await task.value; XCTFail("Cancellation must escape before send") }
        catch is CancellationError { }
        catch { XCTFail("Expected cancellation, got \(error)") }
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testAuthorizerCannotReenableCookiesBeforeDispatch() async throws {
        let provider = NativeWebhookFixtureProvider(try NativeWebhookFixtures.context())
        let wire = NativeWebhookFixtureTransport { _ in XCTFail("Cookie-enabling authorizer cannot dispatch"); return (Data(), 200) }
        let authorizer = RetirementAuthorizer(provider: provider, cancel: false)
        let service = NativeWebhookHTTPService(provider: provider, authorizer: authorizer, transport: wire)
        do { _ = try await service.resources(.subscription, context: provider.value); XCTFail("Cookie handling must stay disabled") }
        catch { XCTAssertEqual(error as? NativeWebhookClientError, .scopeChanged) }
        XCTAssertTrue(wire.requests.isEmpty)
    }

}


@MainActor private final class RetirementAuthorizer: NativeWebhookRequestAuthorizer {
    private let provider: NativeWebhookFixtureProvider
    private let cancel: Bool
    init(provider: NativeWebhookFixtureProvider, cancel: Bool) { self.provider = provider; self.cancel = cancel }
    func authorize(_ request: URLRequest, binding: NativeWebhookBinding) async throws -> URLRequest {
        var result = try await provider.authorize(request, binding: binding)
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        else { result.httpShouldHandleCookies = true }
        return result
    }
    func unauthorized(_ binding: NativeWebhookBinding) { provider.unauthorized(binding) }
}
