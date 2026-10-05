import XCTest
@testable import QuestifyCore

@available(macOS 14.0, *)
@MainActor final class NativePlatformLifecycleTests: XCTestCase {
    func testReminderRefreshNeverRequestsPermissionAndEnableUsesReadback() async throws {
        let provider = NativeReminderTestProvider()
        let model = reminder(provider)
        let window = try NativeTimeWindow(nativeWindow())
        await model.refresh(window)
        XCTAssertEqual(provider.prompts, 0); XCTAssertNil(model.scheduled)
        await model.enable(reviewed: window, title: "Synthetic", body: "Synthetic")
        XCTAssertEqual(provider.prompts, 1); XCTAssertEqual(provider.writes, 1)
        XCTAssertEqual(model.scheduled?.fireAt, window.nextOpenAt)
        model.cancel(); XCTAssertNil(model.scheduled); XCTAssertTrue(provider.items.isEmpty)
    }
    func testDeniedReminderNeverSchedules() async throws {
        let provider = NativeReminderTestProvider(); provider.status = .denied
        let model = reminder(provider), window = try NativeTimeWindow(nativeWindow())
        await model.refresh(window); await model.enable(reviewed: window, title: "Synthetic", body: "Synthetic")
        XCTAssertEqual(provider.writes, 0); XCTAssertEqual(model.issue, .denied)
    }
    func testMissingReadbackIsNeverReportedAsScheduled() async throws {
        let provider = NativeReminderTestProvider(); provider.discardWrite = true
        let model = reminder(provider), window = try NativeTimeWindow(nativeWindow())
        await model.refresh(window); await model.enable(reviewed: window, title: "Synthetic", body: "Synthetic")
        XCTAssertNil(model.scheduled); XCTAssertEqual(model.issue, .notificationMissing)
    }
    func testChangedServerWindowCancelsWithoutReoptingUserIn() async throws {
        let provider = NativeReminderTestProvider(); let model = reminder(provider)
        let first = try NativeTimeWindow(nativeWindow())
        await model.refresh(first); await model.enable(reviewed: first, title: "Synthetic", body: "Synthetic")
        await model.refresh(try NativeTimeWindow(nativeWindow(version: "window-2", offset: 7_200_000)))
        XCTAssertNil(model.scheduled); XCTAssertTrue(provider.items.isEmpty); XCTAssertEqual(model.issue, .windowChanged)
        XCTAssertEqual(provider.writes, 1)
        await model.enable(reviewed: first, title: "Synthetic", body: "Synthetic")
        XCTAssertEqual(provider.writes, 1)
    }
    func testLogoutDuringPermissionCannotSchedule() async throws {
        let provider = NativeReminderTestProvider(); var current = true
        let model = NativeLocalReminderCoordinator(identifier: "synthetic-id", owner: "owner", provider: provider, current: { current }, now: { nativeNow })
        let window = try NativeTimeWindow(nativeWindow()); await model.refresh(window)
        provider.onPermission = { current = false }
        await model.enable(reviewed: window, title: "Synthetic", body: "Synthetic")
        XCTAssertEqual(provider.writes, 0); XCTAssertNil(model.scheduled)
    }
    func testLogoutAfterAddCancelsLateReminder() async throws {
        let provider = NativeReminderTestProvider(); var current = true
        let model = NativeLocalReminderCoordinator(identifier: "synthetic-id", owner: "owner", provider: provider, current: { current }, now: { nativeNow })
        let window = try NativeTimeWindow(nativeWindow()); await model.refresh(window)
        provider.onWrite = { current = false }
        await model.enable(reviewed: window, title: "Synthetic", body: "Synthetic")
        XCTAssertEqual(provider.writes, 1); XCTAssertTrue(provider.items.isEmpty); XCTAssertNil(model.scheduled)
    }
    func testClockChangeAndExpiredWindowRemovePending() async throws {
        let provider = NativeReminderTestProvider(); let model = reminder(provider), window = try NativeTimeWindow(nativeWindow())
        await model.refresh(window); await model.enable(reviewed: window, title: "Synthetic", body: "Synthetic")
        model.clockChanged(); XCTAssertTrue(provider.items.isEmpty); XCTAssertNil(model.window)
        await model.refresh(nil); XCTAssertEqual(model.issue, .expired)
    }
    func testNativeStepsRequireReviewAndNeverCreateRewardFields() async throws {
        let owner = try nativeOwner(); let service = NativePlatformTestService(), pedometer = NativePedometerTestProvider(), assertion = NativeAssertionTestProvider()
        let model = NativeStepCoordinator(owner: owner, service: service, pedometer: pedometer, assertion: assertion, current: { owner }, now: { nativeNow }, uptime: { 100 })
        await model.read(sessionID: 11, version: 1)
        XCTAssertEqual(model.phase, "review"); XCTAssertEqual(pedometer.reads, 1); XCTAssertEqual(assertion.calls, 0)
        XCTAssertEqual(service.requests.map(\.action), [.issue])
        await model.submitReviewed()
        XCTAssertEqual(model.phase, "recorded"); XCTAssertEqual(assertion.calls, 1)
        XCTAssertEqual(service.requests.map(\.action), [.issue, .submit])
        XCTAssertFalse(service.requests.last!.payload.keys.contains("encryptedData")); XCTAssertFalse(service.requests.last!.payload.keys.contains("reward"))
        XCTAssertEqual(model.receipt?["acceptedDelta"].integer, 0)
    }
    func testUnknownSubmitOnlyRetriesFrozenRequest() async throws {
        let owner = try nativeOwner(); let service = NativePlatformTestService(), assertion = NativeAssertionTestProvider()
        let model = NativeStepCoordinator(owner: owner, service: service, pedometer: NativePedometerTestProvider(), assertion: assertion, current: { owner }, now: { nativeNow }, uptime: { 100 })
        await model.read(sessionID: 11, version: 1); service.failNextSubmit = true
        await model.submitReviewed(); let pending = try XCTUnwrap(model.pending)
        XCTAssertEqual(model.phase, "unknown")
        await model.read(sessionID: 11, version: 2); XCTAssertEqual(service.requests.count, 2)
        await model.retryExact()
        XCTAssertEqual(service.requests.last, pending); XCTAssertEqual(assertion.calls, 1); XCTAssertEqual(model.phase, "recorded")
    }
    func testPermissionDeniedDoesNotIssueChallenge() async throws {
        let owner = try nativeOwner(); let service = NativePlatformTestService(), device = NativePedometerTestProvider(); device.permission = .denied
        let model = NativeStepCoordinator(owner: owner, service: service, pedometer: device, assertion: NativeAssertionTestProvider(), current: { owner }, now: { nativeNow })
        await model.read(sessionID: 11, version: 1)
        XCTAssertEqual(model.issue, .denied); XCTAssertTrue(service.requests.isEmpty); XCTAssertEqual(device.reads, 0)
    }
    func testBackgroundAndSessionChangeEraseReview() async throws {
        let owner = try nativeOwner(); let service = NativePlatformTestService(), device = NativePedometerTestProvider()
        let model = NativeStepCoordinator(owner: owner, service: service, pedometer: device, assertion: NativeAssertionTestProvider(), current: { owner }, now: { nativeNow }, uptime: { 100 })
        await model.read(sessionID: 11, version: 1); model.interrupt()
        XCTAssertNil(model.reading); XCTAssertNil(model.challenge)
        await model.submitReviewed(); XCTAssertEqual(service.requests.count, 1)
        model.invalidate(); XCTAssertNil(model.receipt); XCTAssertEqual(model.phase, "stale")
    }
    private func reminder(_ provider: NativeReminderTestProvider) -> NativeLocalReminderCoordinator {
        .init(identifier: "synthetic-id", owner: "owner", provider: provider, current: { true }, now: { nativeNow })
    }
}

@MainActor final class NativeReminderTestProvider: NativeLocalReminderProviding {
    var status = NativePlatformPermission.notDetermined
    var prompts = 0, writes = 0
    var items: [NativeLocalReminder] = []
    var discardWrite = false
    var onPermission: (() -> Void)?; var onWrite: (() -> Void)?
    func permission() async -> NativePlatformPermission { status }
    func requestPermission() async throws -> NativePlatformPermission { prompts += 1; onPermission?(); if status == .notDetermined { status = .allowed }; return status }
    func pending() async -> [NativeLocalReminder] { items }
    func replace(_ reminder: NativeLocalReminder, title: String, body: String) async throws { writes += 1; if !discardWrite { items = [reminder] }; onWrite?() }
    func cancel(identifier: String) { items.removeAll { $0.identifier == identifier } }
    func cancelAllOwned(owner: String) { items.removeAll { $0.owner == owner } }
}
@MainActor final class NativePedometerTestProvider: NativePedometerProviding {
    var permission = NativePlatformPermission.allowed
    var reads = 0
    func read(from: Date, to: Date) async throws -> NativePedometerReading { reads += 1; return try .init(start: from, end: to, steps: 1234) }
    func cancel() {}
}
@MainActor final class NativeAssertionTestProvider: NativeStepAssertionProviding {
    let deviceKeyID = "fixture-key"; let supported = true; var calls = 0
    func assertion(clientData: Data) async throws -> String { calls += 1; return Data("synthetic-test-assertion".utf8).base64EncodedString() }
    func cancel() {}
}
@MainActor final class NativePlatformTestService: NativePlatformServing {
    var requests: [NativePlatformPending] = []; var failNextSubmit = false
    func action(_ pending: NativePlatformPending) async throws -> PlayAdvancedState {
        requests.append(pending)
        if pending.action == .submit, failNextSubmit { failNextSubmit = false; throw NativePlatformIssue.unknownResult }
        var native: [String: PlayWireValue] = ["protocolVersion": .int(1), "provider": .string(NativeStepChallenge.provider), "enabled": .bool(true), "rewardEnabled": .bool(false), "status": .string("AUDIT_ONLY"), "accountId": .int(7), "sessionId": .int(11), "sessionVersion": .int(pending.version + 1), "deviceKeyId": .string("fixture-key")]
        if pending.action == .issue { native["challenge"] = nativeChallenge(version: pending.version + 1) }
        else { native["baselineSteps"] = .int(1234); native["acceptedDelta"] = .int(0); native["lastSampleEndAt"] = pending.payload["sampleEndAt"] }
        return try PlayAdvancedState(.object(["sessionId": .int(11), "activityId": .int(0), "topicId": .int(71), "nodeId": .int(701), "version": .int(pending.version + 1), "status": .string("RUNNING"), "playKit": .object(["steps": .object(["nativeSteps": .object(native)])])]))
    }
    func timeWindow(activityID: Int, topicID: Int, nodeID: Int) async throws -> NativeTimeWindow { try NativeTimeWindow(nativeWindow()) }
}
