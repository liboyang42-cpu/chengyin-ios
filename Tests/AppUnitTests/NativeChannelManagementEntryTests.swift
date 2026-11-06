import XCTest
import Foundation
import SwiftUI
import UIKit
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Questify

@MainActor final class NativeChannelManagementEntryTests: XCTestCase {
    func testUnavailableNativeEntryConstructsWithoutInventingScopeOrOpeningAService() throws {
        let scope = try NativeChannelManagementScope(guildKind: 1, guildID: .init("42"))
        var factories = 0
        let entry = NativeChannelManagementEntry(scope: scope, makeFlow: { _ in factories += 1; return nil })
        let host = UIHostingController(rootView: NavigationStack { entry })
        host.loadViewIfNeeded()
        // A normal link does not allocate a command, request credential or instantiate a destination flow.
        XCTAssertEqual(factories, 0); XCTAssertNotNil(host.view)
    }
    func testBindingWithoutIndependentEndpointLeaseDoesNotConstructCoordinator() throws {
        let api = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let session = try PlayExperienceSession(accountID: 11, epoch: 1, namespace: "CN:test", token: "test-token")
        let context = RuntimeDependencyContext(market: .china, baseURL: api.baseURL, role: "player", session: session)
        let scope = try NativeChannelManagementScope(guildKind: 1, guildID: .init("42"))
        let dispatcher = NativeChannelManagementDispatchTransport { _, _ in XCTFail("Must not dispatch without lease"); throw APIError.notConfigured }
        let result = NativeChannelManagementBinding.make(context: context, viewerRevision: 0, scope: scope,
            configuration: api, transport: dispatcher, storage: ForbiddenStorage(), current: { context }, viewer: { 0 },
            selectedApproval: { nil }, onUnauthorized: { _ in XCTFail("No HTTP performed") })
        XCTAssertNil(result)
    }
    func testUnavailableAndPermissionBlockedScreensRenderWithNativeViews() {
        let host = UIHostingController(rootView: NativeChannelManagementUnavailableView())
        host.loadViewIfNeeded(); XCTAssertNotNil(host.view)
        let blocked = UIHostingController(rootView: NativeChannelManagementIssueView(issue: .permissionCASUnavailable))
        blocked.loadViewIfNeeded(); XCTAssertNotNil(blocked.view)
    }
    func testRetainedP45StateDropsAWhenAReturnsBeforeOrAfterB() async throws {
        for firstReturnsBeforeSecond in [true, false] {
            let provider = try SuspendedChannelProvider(); let state = NativeChannelManagementWebhookEntryState()
            let a = try NativeChannelManagementID("9012"), b = try NativeChannelManagementID("9013")
            let enteredA = expectation(description: "A waiting"), enteredB = expectation(description: "B waiting")
            provider.onRequest = { id in if id == a { enteredA.fulfill() } else if id == b { enteredB.fulfill() } }
            let taskA = Task { await state.load(channels: provider, channelID: a) }
            await fulfillment(of: [enteredA], timeout: 2)
            let taskB = Task { await state.load(channels: provider, channelID: b) }
            await fulfillment(of: [enteredB], timeout: 2)
            XCTAssertNil(state.readyScope(for: b, channels: provider)); XCTAssertNil(state.channel)
            if firstReturnsBeforeSecond {
                provider.succeed(a); await taskA.value
                XCTAssertNil(state.channel); XCTAssertFalse(state.failed)
                provider.succeed(b); await taskB.value
            } else {
                provider.succeed(b); await taskB.value
                provider.succeed(a); await taskA.value
            }
            XCTAssertEqual(state.channel?.channelID, b)
            XCTAssertEqual(state.readyScope(for: b, channels: provider)?.channelID.rawValue, b.rawValue)
            XCTAssertNil(state.readyScope(for: a, channels: provider)); XCTAssertFalse(state.failed)
            state.invalidate(for: a) // A's late disappearance must not erase B's current presentation.
            XCTAssertNotNil(state.readyScope(for: b, channels: provider))
        }
    }
    func testLateAErrorCannotFailBAndCancelledCompletionCannotInstallScope() async throws {
        let provider = try SuspendedChannelProvider(); let state = NativeChannelManagementWebhookEntryState()
        let a = try NativeChannelManagementID("9012"), b = try NativeChannelManagementID("9013")
        let enteredA = expectation(description: "A waiting"), enteredB = expectation(description: "B waiting")
        provider.onRequest = { id in if id == a { enteredA.fulfill() } else if id == b { enteredB.fulfill() } }
        let taskA = Task { await state.load(channels: provider, channelID: a) }
        await fulfillment(of: [enteredA], timeout: 2)
        let taskB = Task { await state.load(channels: provider, channelID: b) }
        await fulfillment(of: [enteredB], timeout: 2)
        provider.succeed(b); await taskB.value
        provider.fail(a); await taskA.value
        XCTAssertFalse(state.failed); XCTAssertEqual(state.channel?.channelID, b)
        state.invalidate(for: b)
        let cancelledStarted = expectation(description: "Cancelled A waiting")
        provider.onRequest = { _ in cancelledStarted.fulfill() }
        let cancelled = Task { await state.load(channels: provider, channelID: a) }
        await fulfillment(of: [cancelledStarted], timeout: 2)
        cancelled.cancel(); provider.succeed(a); await cancelled.value
        XCTAssertNil(state.channel); XCTAssertNil(state.scope); XCTAssertFalse(state.failed)
    }
    func testReadyP45ScopeIsHiddenImmediatelyWhenInputChangesBeforeNewTaskStarts() async throws {
        let provider = try SuspendedChannelProvider(); let state = NativeChannelManagementWebhookEntryState()
        let a = try NativeChannelManagementID("9012"), b = try NativeChannelManagementID("9013")
        let enteredA = expectation(description: "A waiting"); provider.onRequest = { _ in enteredA.fulfill() }
        let task = Task { await state.load(channels: provider, channelID: a) }
        await fulfillment(of: [enteredA], timeout: 2); provider.succeed(a); await task.value
        XCTAssertNotNil(state.readyScope(for: a, channels: provider))
        XCTAssertNil(state.readyScope(for: b, channels: provider), "Body must reject A even before B's keyed task starts")
        provider.invalidateSource()
        XCTAssertNil(state.readyScope(for: a, channels: provider), "Retired source cannot keep a factory visible")
    }
    func testRetainedHostingViewChannelSwitchCanOnlyConstructBFactory() async throws {
        let provider = try SuspendedChannelProvider(); let state = NativeChannelManagementWebhookEntryState()
        let a = try NativeChannelManagementID("9012"), b = try NativeChannelManagementID("9013")
        let enteredA = expectation(description: "Hosted A waiting"), enteredB = expectation(description: "Hosted B waiting")
        let builtB = expectation(description: "Original entry factory received B")
        provider.onRequest = { id in if id == a { enteredA.fulfill() } else if id == b { enteredB.fulfill() } }
        let inputs = RetainedWebhookInputs(channelID: a)
        let view = RetainedWebhookHost(inputs: inputs, channels: provider, state: state, onFactory: { scope in
            if inputs.factoryScopes.isEmpty { builtB.fulfill() }
            inputs.factoryScopes.append(scope)
            XCTAssertEqual(scope.channelID.rawValue, b.rawValue, "An A callback cannot construct a factory under the B input")
        })
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; provider.finishAll() }
        await fulfillment(of: [enteredA], timeout: 2)
        inputs.channelID = b // Same host/view position; SwiftUI retains the entry state object.
        await fulfillment(of: [enteredB], timeout: 2)
        provider.succeed(b); await fulfillment(of: [builtB], timeout: 2)
        provider.succeed(a)
        await Task.yield()
        XCTAssertEqual(state.channel?.channelID, b)
        XCTAssertFalse(inputs.factoryScopes.isEmpty)
        XCTAssertTrue(inputs.factoryScopes.allSatisfy { $0.channelID.rawValue == b.rawValue })
    }
}

@MainActor @Observable private final class RetainedWebhookInputs {
    var channelID: NativeChannelManagementID
    var factoryScopes: [NativeWebhookScope] = []
    init(channelID: NativeChannelManagementID) { self.channelID = channelID }
}
@MainActor private struct RetainedWebhookHost: View {
    let inputs: RetainedWebhookInputs
    let channels: SuspendedChannelProvider
    let state: NativeChannelManagementWebhookEntryState
    let onFactory: (NativeWebhookScope) -> Void
    var body: some View {
        NativeChannelManagementWebhookEntry(channels: channels, channelID: inputs.channelID, makeCoordinator: { scope in
            onFactory(scope)
            throw NativeWebhookClientError.sourceUnavailable("FIXTURE_FACTORY_NO_NETWORK")
        }, state: state)
    }
}

/// Uses the real channel decoder/service and suspends only the final context delivery to the UI.
/// Cancellation is deliberately not automatic, reproducing a late provider callback after an input change.
@MainActor private final class SuspendedChannelProvider: NativeChannelManagementIntegrationContextProviding {
    private struct Waiting {
        let context: NativeChannelManagementIntegrationContext
        let continuation: CheckedContinuation<NativeChannelManagementIntegrationContext, Error>
    }
    private let source: NativeChannelManagementHTTPService
    private var waiting: [NativeChannelManagementID: Waiting] = [:]
    var onRequest: ((NativeChannelManagementID) -> Void)?
    init() throws {
        let api = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let session = try PlayExperienceSession(accountID: 11, epoch: 1, namespace: "CN:test", token: "test-token")
        let runtime = RuntimeDependencyContext(market: .china, baseURL: api.baseURL, role: "player", session: session)
        let scope = try NativeChannelManagementScope(guildKind: 1, guildID: .init("42"))
        let approval = try NativeChannelManagementApproval(context: runtime, viewerRevision: 2, scope: scope,
            operations: [.detail], expiresAt: Date().addingTimeInterval(60))
        let dispatcher = NativeChannelManagementDispatchTransport { request, fence in
            guard fence.isCurrent, let id = request.url?.path.split(separator: "/").last.map(String.init) else {
                throw NativeChannelManagementError.changedIdentity
            }
            let row: [String: Any] = ["id": id, "guild_kind": 1, "guild_id": "42", "parent_id": "0", "kind": 1,
                "name": "Fixture", "position": 0, "is_default": 0, "status": 0, "version": "5", "perm_version": "8",
                "visibility": 1, "slowmode_sec": 0, "my_permissions_list": ["VIEW_CHANNEL", "READ_HISTORY", "MANAGE_WEBHOOKS"]]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": row]), 200)
        }
        source = try .init(context: runtime, viewerRevision: 2, scope: scope, configuration: api, transport: dispatcher,
            current: { runtime }, viewer: { 2 }, selectedApproval: { approval })
    }
    func currentChannelContext(channelID: NativeChannelManagementID) async throws -> NativeChannelManagementIntegrationContext {
        let context = try await source.currentChannelContext(channelID: channelID)
        return try await withCheckedThrowingContinuation { continuation in
            guard waiting[channelID] == nil else { continuation.resume(throwing: NativeChannelManagementError.pendingOriginal); return }
            waiting[channelID] = Waiting(context: context, continuation: continuation)
            onRequest?(channelID)
        }
    }
    func contextIsCurrent(_ context: NativeChannelManagementIntegrationContext) -> Bool { source.contextIsCurrent(context) }
    func succeed(_ id: NativeChannelManagementID) {
        guard let pending = waiting.removeValue(forKey: id) else { XCTFail("Expected suspended channel request"); return }
        pending.continuation.resume(returning: pending.context)
    }
    func fail(_ id: NativeChannelManagementID) {
        guard let pending = waiting.removeValue(forKey: id) else { XCTFail("Expected suspended channel request"); return }
        pending.continuation.resume(throwing: NativeChannelManagementError.outcomeUnknown)
    }
    func invalidateSource() { source.invalidate() }
    func finishAll() {
        let pending = Array(waiting.values); waiting.removeAll()
        for item in pending { item.continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor private final class ForbiddenStorage: ProjectEditDataStorage {
    func read(_ key: String) throws -> Data? { XCTFail("No journal access without approved binding"); throw APIError.notConfigured }
    func write(_ data: Data, key: String) throws { XCTFail("No journal write without approved binding"); throw APIError.notConfigured }
    func remove(_ key: String) throws { XCTFail("No journal deletion without approved binding"); throw APIError.notConfigured }
}
