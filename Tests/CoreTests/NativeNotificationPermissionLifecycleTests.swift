import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class NativeNotificationPermissionLifecycleTests: XCTestCase {
    private enum Failure: Error { case unavailable }
    private final class Provider: NativeNotificationPermissionProviding {
        var authorization: NativeNotificationPermissionAuthorization = .notDetermined
        var reads = 0, requests = 0, settings = 0, active = 0, maxActive = 0
        var failRead = false, failRequest = false, failSettings = false
        var holdRead = false, holdRequest = false, holdSettings = false
        var readGate: CheckedContinuation<Void, Never>?
        var requestGate: CheckedContinuation<Void, Never>?
        var settingsGate: CheckedContinuation<Void, Never>?
        private func start() { active += 1; maxActive = max(maxActive, active) }
        func read() async throws -> NativeNotificationPermissionSnapshot {
            reads += 1; start(); defer { active -= 1 }
            let value = authorization
            if holdRead { holdRead = false; await withCheckedContinuation { readGate = $0 } }
            if failRead { throw Failure.unavailable }
            return .init(authorization: value, alerts: .disabled, sounds: .unsupported, badges: .enabled)
        }
        func requestFromUserAction() async throws {
            requests += 1; start(); defer { active -= 1 }
            if holdRequest { await withCheckedContinuation { requestGate = $0 } }
            if failRequest { throw Failure.unavailable }
            authorization = .provisional
        }
        func openSettingsFromUserAction() async throws {
            settings += 1; start(); defer { active -= 1 }
            if holdSettings { await withCheckedContinuation { settingsGate = $0 } }
            if failSettings { throw Failure.unavailable }
        }
    }
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 { if condition() { return }; await Task.yield() }
        XCTFail("Expected deterministic actor work to complete")
    }
    func testAppearanceAndReentryOnlyReadOriginalOSState() async {
        let provider = Provider()
        // Construction itself performs no OS action.
        XCTAssertEqual(provider.reads, 0)
        let original = NativeNotificationPermissionState(provider: provider)
        await original.refresh(); original.retire(); provider.authorization = .denied
        await original.refresh(expectedRevision: original.revision)
        XCTAssertEqual(original.snapshot?.authorization, .denied)
        XCTAssertEqual(provider.reads, 2); XCTAssertEqual(provider.requests, 0); XCTAssertEqual(provider.settings, 0)
    }
    func testCancelledRefreshAndPromptNeverReachProvider() async {
        let provider = Provider()
        let original = NativeNotificationPermissionState(provider: provider)
        await original.refresh()
        let work = Task { await original.refresh(); await original.requestFromUserAction() }
        work.cancel(); await work.value
        XCTAssertEqual(provider.reads, 1); XCTAssertEqual(provider.requests, 0)
        XCTAssertFalse(original.busy)
    }
    func testCancelledSettingsGestureNeverOpensSystemSettings() async {
        let provider = Provider(); provider.authorization = .denied
        let model = NativeNotificationPermissionState(provider: provider); await model.refresh()
        let work = Task { await model.openSettingsFromUserAction() }
        work.cancel(); await work.value
        XCTAssertEqual(provider.settings, 0); XCTAssertEqual(provider.reads, 1)
    }
    func testRetiredGestureRevisionCannotReadPromptOrOpenSettings() async {
        let provider = Provider()
        let original = NativeNotificationPermissionState(provider: provider)
        await original.refresh(); let stale = original.revision; original.retire()
        await original.refresh(expectedRevision: stale)
        await original.refresh(expectedRevision: original.revision)
        await original.requestFromUserAction(expectedRevision: stale)
        provider.authorization = .denied; await original.refresh()
        await original.openSettingsFromUserAction(expectedRevision: stale)
        XCTAssertEqual(provider.reads, 3); XCTAssertEqual(provider.requests, 0); XCTAssertEqual(provider.settings, 0)
    }
    func testRetirementDiscardsLateReadAndSerializesFreshVisit() async {
        let provider = Provider(); provider.holdRead = true
        let model = NativeNotificationPermissionState(provider: provider)
        let old = Task { await model.refresh() }; await until { provider.readGate != nil }
        model.retire(); provider.authorization = .denied
        await model.refresh(expectedRevision: model.revision)
        XCTAssertEqual(provider.reads, 1); XCTAssertTrue(model.busy)
        provider.readGate?.resume(); provider.readGate = nil; await old.value
        await until { model.snapshot?.authorization == .denied && !model.busy }
        XCTAssertEqual(provider.reads, 2); XCTAssertEqual(provider.maxActive, 1)
    }
    func testForegroundRefreshDuringSettingsActionIsNotLost() async {
        let provider = Provider(); provider.authorization = .denied; provider.holdSettings = true
        let model = NativeNotificationPermissionState(provider: provider); await model.refresh()
        let action = Task { await model.openSettingsFromUserAction() }; await until { provider.settingsGate != nil }
        provider.authorization = .authorized
        await model.refresh(); await model.refresh() // coalesce foreground/manual reads
        provider.settingsGate?.resume(); provider.settingsGate = nil; await action.value
        await until { provider.reads == 3 && !model.busy }
        XCTAssertEqual(model.snapshot?.authorization, .authorized)
        XCTAssertEqual(provider.settings, 1); XCTAssertEqual(provider.requests, 0); XCTAssertEqual(provider.maxActive, 1)
    }
    func testExplicitPromptReadsActualResultAndRefusesSecondPrompt() async {
        let provider = Provider()
        let original = NativeNotificationPermissionState(provider: provider); await original.refresh()
        await original.requestFromUserAction(); await original.requestFromUserAction()
        XCTAssertEqual(provider.requests, 1); XCTAssertEqual(provider.reads, 2)
        XCTAssertEqual(original.snapshot?.authorization, .provisional)
    }
    func testCancelledInFlightPromptCannotPublishSuccessOrRetainPromptableSnapshot() async {
        let provider = Provider(); provider.holdRequest = true
        let model = NativeNotificationPermissionState(provider: provider); await model.refresh()
        let action = Task { await model.requestFromUserAction() }; await until { provider.requestGate != nil }
        action.cancel(); provider.requestGate?.resume(); provider.requestGate = nil; await action.value
        XCTAssertNil(model.snapshot); XCTAssertEqual(provider.reads, 1); XCTAssertFalse(model.busy)
        await model.requestFromUserAction(); XCTAssertEqual(provider.requests, 1)
        await model.refresh(); XCTAssertEqual(model.snapshot?.authorization, .provisional)
    }
    func testRetirementCancelsQueuedRefreshAndDoesNotReplayPrompt() async {
        let provider = Provider(); provider.holdRequest = true
        let model = NativeNotificationPermissionState(provider: provider); await model.refresh()
        let action = Task { await model.requestFromUserAction() }; await until { provider.requestGate != nil }
        await model.refresh(); model.retire()
        provider.requestGate?.resume(); provider.requestGate = nil; await action.value
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(model.snapshot); XCTAssertEqual(provider.reads, 1); XCTAssertEqual(provider.requests, 1); XCTAssertFalse(model.busy)
    }
    func testPromptFailureRequiresFreshReadBeforeAnotherUserAction() async {
        let provider = Provider(); provider.failRequest = true
        let model = NativeNotificationPermissionState(provider: provider); await model.refresh()
        await model.requestFromUserAction(); XCTAssertNil(model.snapshot); XCTAssertNotNil(model.issue)
        provider.failRequest = false; await model.requestFromUserAction(); XCTAssertEqual(provider.requests, 1)
        await model.refresh(); await model.requestFromUserAction()
        XCTAssertEqual(provider.requests, 2); XCTAssertEqual(model.snapshot?.authorization, .provisional)
    }
    func testSettingsOpenFailureAndReadbackFailureRemainDistinctAndRetryable() async {
        let provider = Provider(); provider.authorization = .denied; provider.failSettings = true
        let model = NativeNotificationPermissionState(provider: provider); await model.refresh()
        await model.openSettingsFromUserAction()
        XCTAssertEqual(model.snapshot?.authorization, .denied)
        XCTAssertEqual(model.issue, "无法打开系统设置，请稍后重试。")
        provider.failSettings = false; provider.failRead = true
        await model.openSettingsFromUserAction()
        XCTAssertNil(model.snapshot); XCTAssertEqual(model.issue, "无法读取系统通知权限，请重试。")
        provider.failRead = false; await model.refresh()
        XCTAssertEqual(model.snapshot?.authorization, .denied); XCTAssertNil(model.issue)
    }
    func testFutureAuthorizationIsPreservedAndDoesNotPermitPrompt() async {
        let provider = Provider(); provider.authorization = .unknown(999)
        let model = NativeNotificationPermissionState(provider: provider); await model.refresh()
        await model.requestFromUserAction()
        XCTAssertEqual(model.snapshot?.authorization, .unknown(999)); XCTAssertEqual(provider.requests, 0)
    }
}
