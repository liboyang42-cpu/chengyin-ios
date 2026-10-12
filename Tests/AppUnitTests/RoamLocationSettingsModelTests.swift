import XCTest
import Combine
import CoreLocation
@testable import Questify

@MainActor private final class LocationSettingsProviderFixture: RoamLocationSettingsProviding {
    var reads: [CheckedContinuation<RoamLocationSettingsSnapshot, Error>] = []
    var opens: [CheckedContinuation<Bool, Never>] = []
    var didRead: (() -> Void)?
    var didOpen: (() -> Void)?
    func readStatus() async throws -> RoamLocationSettingsSnapshot {
        try await withCheckedThrowingContinuation { reads.append($0); didRead?() }
    }
    func openAppSettings() async -> Bool {
        await withCheckedContinuation { opens.append($0); didOpen?() }
    }
}

@MainActor final class RoamLocationSettingsModelTests: XCTestCase {
    private var subscriptions: Set<AnyCancellable> = []
    private let denied = RoamLocationSettingsSnapshot(authorization: .denied, servicesEnabled: true)
    private func readStarted(_ provider: LocationSettingsProviderFixture) -> XCTestExpectation {
        let result = expectation(description: "Read started"); provider.didRead = { result.fulfill() }; return result
    }
    private func openStarted(_ provider: LocationSettingsProviderFixture) -> XCTestExpectation {
        let result = expectation(description: "Open started"); provider.didOpen = { result.fulfill() }; return result
    }
    private func stateReached(_ model: RoamLocationSettingsModel, _ match: @escaping (RoamLocationSettingsState) -> Bool) -> XCTestExpectation {
        let result = expectation(description: "State reached")
        model.$state.filter(match).first().sink { _ in result.fulfill() }.store(in: &subscriptions)
        return result
    }
    private func drain() async { for _ in 0..<12 { await Task.yield() } }
    func testMapsFiveAppleStatesWithoutCollapsingDeniedOrRestricted() {
        XCTAssertEqual(RoamSystemLocationSettingsProvider.map(.notDetermined), .notDetermined)
        XCTAssertEqual(RoamSystemLocationSettingsProvider.map(.denied), .denied)
        XCTAssertEqual(RoamSystemLocationSettingsProvider.map(.restricted), .restricted)
        XCTAssertEqual(RoamSystemLocationSettingsProvider.map(.authorizedWhenInUse), .whenInUse)
        XCTAssertEqual(RoamSystemLocationSettingsProvider.map(.authorizedAlways), .always)
    }
    func testConstructionDoesNotReadOrOpenSettings() async {
        let provider = LocationSettingsProviderFixture(); let model = RoamLocationSettingsModel(provider: provider)
        await drain(); XCTAssertEqual(provider.reads.count, 0); XCTAssertEqual(provider.opens.count, 0)
        XCTAssertEqual(model.state.phase, .idle)
    }
    func testActivationReadsActualStatusWithoutOpeningSettings() async {
        let provider = LocationSettingsProviderFixture(), started = expectation(description: "Started")
        provider.didRead = { started.fulfill() }; let model = RoamLocationSettingsModel(provider: provider)
        let loaded = stateReached(model) { $0.phase == .loaded(self.denied) }
        model.activate(); await fulfillment(of: [started], timeout: 1)
        provider.reads[0].resume(returning: denied); await fulfillment(of: [loaded], timeout: 1)
        XCTAssertEqual(provider.opens.count, 0)
    }
    func testExplicitRefreshSupersedesOlderRead() async {
        let provider = LocationSettingsProviderFixture()
        let subject = RoamLocationSettingsModel(provider: provider), first = readStarted(provider)
        subject.activate(); await fulfillment(of: [first], timeout: 1)
        let second = readStarted(provider); subject.refresh(); await fulfillment(of: [second], timeout: 1)
        let current = RoamLocationSettingsSnapshot(authorization: .always, servicesEnabled: false)
        let loaded = stateReached(subject) { $0.phase == .loaded(current) }
        provider.reads[1].resume(returning: current); await fulfillment(of: [loaded], timeout: 1)
        provider.reads[0].resume(returning: denied); await drain()
        XCTAssertEqual(subject.state.phase, .loaded(current))
    }
    func testReadErrorShowsFailureAndRetryCanLoad() async {
        let provider = LocationSettingsProviderFixture()
        let model = RoamLocationSettingsModel(provider: provider), first = readStarted(provider)
        model.activate(); await fulfillment(of: [first], timeout: 1)
        let failed = stateReached(model) { $0.phase == .failed }
        provider.reads[0].resume(throwing: NSError(domain: "Fixture", code: 1)); await fulfillment(of: [failed], timeout: 1)
        let second = readStarted(provider); model.refresh(); await fulfillment(of: [second], timeout: 1)
        let loaded = stateReached(model) { $0.phase == .loaded(self.denied) }
        provider.reads[1].resume(returning: denied); await fulfillment(of: [loaded], timeout: 1)
    }
    func testDismissBeforeReadTaskStartsDoesNotRead() async {
        let provider = LocationSettingsProviderFixture(); let subject = RoamLocationSettingsModel(provider: provider)
        subject.activate(); subject.suspend(); await drain()
        XCTAssertEqual(provider.reads.count, 0); XCTAssertEqual(subject.state.phase, .idle)
    }
    func testSuspendDuringReadDropsCompletionAndInactiveActions() async {
        let provider = LocationSettingsProviderFixture(); let model = RoamLocationSettingsModel(provider: provider), first = readStarted(provider)
        model.activate(); await fulfillment(of: [first], timeout: 1); model.suspend()
        model.refresh(); model.openSettings(); provider.reads[0].resume(returning: denied); await drain()
        XCTAssertEqual(model.state.phase, .idle); XCTAssertEqual(provider.reads.count, 1); XCTAssertEqual(provider.opens.count, 0)
    }
    func testRepeatedOpenTapsDispatchOnceAndFailureCanRetry() async {
        let provider = LocationSettingsProviderFixture(); let model = RoamLocationSettingsModel(provider: provider), read = readStarted(provider)
        model.activate(); await fulfillment(of: [read], timeout: 1); provider.reads[0].resume(returning: denied)
        let open = openStarted(provider); model.openSettings(); model.openSettings()
        await fulfillment(of: [open], timeout: 1); XCTAssertEqual(provider.opens.count, 1)
        let failed = stateReached(model) { $0.settingsOpenFailed }; provider.opens[0].resume(returning: false)
        await fulfillment(of: [failed], timeout: 1)
        let retry = openStarted(provider); model.openSettings(); await fulfillment(of: [retry], timeout: 1)
        let done = stateReached(model) { !$0.isOpeningSettings && !$0.settingsOpenFailed }
        provider.opens[1].resume(returning: true); await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(model.state.phase, .loaded(denied))
    }
    func testDismissBeforeOpenTaskStartsNeverOpensSettings() async {
        let provider = LocationSettingsProviderFixture(); let model = RoamLocationSettingsModel(provider: provider)
        model.activate(); model.openSettings(); model.suspend(); await drain()
        XCTAssertEqual(provider.opens.count, 0); XCTAssertEqual(provider.reads.count, 0)
    }
    func testBackgroundDropsOpenFailureAndActiveReturnReadsAgain() async {
        let provider = LocationSettingsProviderFixture(); let model = RoamLocationSettingsModel(provider: provider), read = readStarted(provider)
        model.activate(); await fulfillment(of: [read], timeout: 1); provider.reads[0].resume(returning: denied)
        let open = openStarted(provider); model.openSettings(); await fulfillment(of: [open], timeout: 1)
        model.suspend(); provider.opens[0].resume(returning: false); await drain()
        XCTAssertFalse(model.state.settingsOpenFailed)
        let returned = readStarted(provider); model.activate(); await fulfillment(of: [returned], timeout: 1)
        let current = RoamLocationSettingsSnapshot(authorization: .whenInUse, servicesEnabled: true)
        let loaded = stateReached(model) { $0.phase == .loaded(current) }
        provider.reads[1].resume(returning: current); await fulfillment(of: [loaded], timeout: 1)
        XCTAssertEqual(provider.opens.count, 1)
    }
    func testRefreshDropsOlderSettingsCompletion() async {
        let provider = LocationSettingsProviderFixture(); let model = RoamLocationSettingsModel(provider: provider), first = readStarted(provider)
        model.activate(); await fulfillment(of: [first], timeout: 1); provider.reads[0].resume(returning: denied)
        let open = openStarted(provider); model.openSettings(); await fulfillment(of: [open], timeout: 1)
        let refresh = readStarted(provider); model.refresh(); await fulfillment(of: [refresh], timeout: 1)
        provider.opens[0].resume(returning: false); provider.reads[1].resume(returning: denied); await drain()
        XCTAssertFalse(model.state.settingsOpenFailed); XCTAssertEqual(model.state.phase, .loaded(denied))
    }
}
