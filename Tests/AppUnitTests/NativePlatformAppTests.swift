import XCTest
import CryptoKit
import AVFoundation
import UIKit
@testable import Questify

@MainActor final class NativePlatformAppTests: XCTestCase {
    func testShippedRuntimeApprovalIsAbsent() {
        XCTAssertNil(NativeRuntimeDependencies.dormant.nativePlatform)
        XCTAssertFalse(NativePlatformAcceptance().validPurpose)
    }
    func testDormantPedometerCannotRequestPermissionOrRead() async {
        let provider = IPhonePedometerProvider()
        XCTAssertEqual(provider.permission, .unsupported)
        do { _ = try await provider.read(from: Date().addingTimeInterval(-10), to: Date()); XCTFail() }
        catch { XCTAssertEqual(error as? NativePlatformIssue, .disabled) }
    }
    func testDormantNotificationProviderCannotPromptOrSchedule() async {
        let provider = AppleLocalReminderProvider()
        let permission = await provider.permission(); XCTAssertEqual(permission, .unsupported)
        do { _ = try await provider.requestPermission(); XCTFail() }
        catch { XCTAssertEqual(error as? NativePlatformIssue, .disabled) }
        let pending = await provider.pending(); XCTAssertTrue(pending.isEmpty)
    }
    func testDormantAppAttestDoesNotCreateAKey() async {
        let provider = AppAttestStepAssertionProvider()
        XCTAssertFalse(provider.supported)
        do { _ = try await provider.assertion(clientData: Data("synthetic".utf8)); XCTFail() }
        catch { XCTAssertEqual(error as? NativePlatformIssue, .unsupported) }
    }
    func testBackendGoldenVectorSHA256() throws {
        let fixture = #"{"challenge":{"challengeId":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","provider":"IOS_CMPEDOMETER_V1","accountId":7,"sessionId":51,"attemptStartedAt":1790935140000,"deviceKeyId":"device-key","sessionVersion":1,"issuedAt":1790935200000,"expiresAt":1790935320000,"timeZone":"Asia/Shanghai","dayKey":"2026-10-02","dayStartAt":1790870400000,"dayEndAt":1790956800000},"request":{"sessionId":51,"version":1,"idempotencyKey":"submit-1","action":"SUBMIT_NATIVE_STEPS","payload":{"provider":"IOS_CMPEDOMETER_V1","deviceKeyId":"device-key","challengeId":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","dayKey":"2026-10-02","sampleStartAt":1790870400000,"sampleEndAt":1790935201000,"cumulativeSteps":4000,"assertion":"dGVzdC1vbmx5"}},"canonicalPayload":"CHENGYIN_NATIVE_STEPS_V1\nIOS_CMPEDOMETER_V1\n7\n51\n1790935140000\ndevice-key\n0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n1790935200000\n1790935320000\nAsia/Shanghai\n2026-10-02\n1790870400000\n1790956800000\n1790870400000\n1790935201000\n4000\n1\nsubmit-1","clientDataHashHex":"4b1f0eab9f480291c632216a2445ebb8c16a2c9ee7b838af43f1fa6bc7f8dce7","note":"Synthetic cross-client fixture only. Assertion is not a valid App Attest proof."}"#
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: Data(fixture.utf8))
        let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic")
        let challenge = try NativeStepChallenge(raw["challenge"], owner: owner, sessionID: 51, version: 1, deviceKeyID: "device-key")
        let reading = try NativePedometerReading(start: Date(timeIntervalSince1970: 1_790_870_400), end: Date(timeIntervalSince1970: 1_790_935_201), steps: 4000)
        let data = try NativeStepCanonical.clientData(challenge: challenge, reading: reading, idempotencyKey: "submit-1")
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actual, raw["clientDataHashHex"].text)
    }
}

/// These vectors use the real driver/coordinator with synthetic downloads, players,
/// notification delivery, and session operations. No device session or HTTP is touched.
@MainActor final class NativeAudioLifecycleTests: XCTestCase {
    private func model(_ fixture: NativeAudioFixture, path: String = "one.mp3") -> PlatformAudioPlayback {
        let value = PlatformAudioPlayback(driver: fixture.driver, policy: fixture.policy, enabled: true)
        value.select(fixture.source(path)); value.approveSelectedMedia(); value.toggle()
        return value
    }
    private func play(_ fixture: NativeAudioFixture) {
        fixture.downloads.last?.complete(Data([1, 2, 3])); fixture.delivery.drain()
    }
    func testOwnCategoryChangeAllowsStartAndExplicitPauseResume() {
        let fixture = NativeAudioFixture(); fixture.categoryChangeOnActivation = true
        let value = model(fixture); play(fixture)
        XCTAssertEqual(value.state, .playing)
        XCTAssertEqual(fixture.activations, 1); XCTAssertEqual(fixture.deactivations, 0)
        value.toggle(); XCTAssertEqual(value.state, .paused)
        value.toggle(); XCTAssertEqual(value.state, .playing)
        XCTAssertEqual(fixture.players[0].plays, 2)
        value.dispose(); value.dispose()
        XCTAssertEqual(fixture.deactivations, 1)
        XCTAssertEqual(fixture.players[0].stops, 1); XCTAssertNil(fixture.players[0].delegate)
    }
    func testOldQueuedInterruptionCannotStopReplacement() {
        let fixture = NativeAudioFixture(), value = model(fixture)
        play(fixture)
        fixture.post(AVAudioSession.interruptionNotification,
                     [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        value.select(fixture.source("two.mp3")); value.approveSelectedMedia(); value.toggle()
        fixture.downloads[1].complete(Data([4]))
        fixture.delivery.drain()
        XCTAssertEqual(value.state, .playing)
        XCTAssertEqual(fixture.players.count, 2); XCTAssertEqual(fixture.players[1].stops, 0)
        XCTAssertEqual(fixture.deactivations, 1)
        value.dispose()
    }
    func testIdleAndLoadingStopsDoNotDeactivateUnownedSession() {
        let fixture = NativeAudioFixture()
        fixture.driver.stop(); fixture.driver.stop()
        fixture.post(UIApplication.didEnterBackgroundNotification)
        fixture.delivery.drain(); XCTAssertEqual(fixture.deactivations, 0)
        let value = model(fixture)
        value.suspend(); fixture.downloads[0].complete(Data([1])); fixture.delivery.drain()
        XCTAssertEqual(value.state, .idle)
        XCTAssertEqual(fixture.activations, 0); XCTAssertEqual(fixture.deactivations, 0)
        XCTAssertEqual(fixture.downloads[0].cancels, 1)
        value.toggle(); XCTAssertEqual(fixture.downloads.count, 1)
        value.approveSelectedMedia(); value.toggle(); play(fixture)
        XCTAssertEqual(value.state, .playing); value.dispose()
    }
    func testBackgroundRouteLossAndResetStopLoadingPlayingAndPaused() {
        let notices: [(Notification.Name, [AnyHashable: Any])] = [
            (UIApplication.didEnterBackgroundNotification, [:]),
            (AVAudioSession.routeChangeNotification,
             [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]),
            (AVAudioSession.mediaServicesWereResetNotification, [:])
        ]
        for (name, info) in notices {
            for phase in 0...2 {
                let fixture = NativeAudioFixture(), value = model(fixture)
                if phase > 0 { play(fixture) }
                if phase == 2 { value.toggle() }
                fixture.post(name, info); fixture.post(name, info); fixture.delivery.drain()
                XCTAssertEqual(value.state, .idle)
                XCTAssertEqual(fixture.deactivations, phase == 0 ? 0 : 1)
                XCTAssertEqual(fixture.downloads[0].cancels, 1)
                fixture.downloads[0].complete(Data([1])); fixture.delivery.drain()
                XCTAssertEqual(value.state, .idle)
                XCTAssertEqual(fixture.activations, phase == 0 ? 0 : 1)
                value.dispose()
            }
        }
    }
    func testInterruptionEndedDoesNotResumeOrStopExplicitRestart() {
        let fixture = NativeAudioFixture(), value = model(fixture)
        play(fixture); value.toggle()
        let ended: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        ]
        fixture.post(AVAudioSession.interruptionNotification, ended); fixture.delivery.drain()
        XCTAssertEqual(value.state, .paused); XCTAssertEqual(fixture.players[0].plays, 1)
        fixture.post(AVAudioSession.interruptionNotification,
                     [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        fixture.delivery.drain(); XCTAssertEqual(value.state, .idle)
        fixture.post(AVAudioSession.interruptionNotification, ended); fixture.delivery.drain()
        XCTAssertEqual(fixture.downloads.count, 1)
        value.approveSelectedMedia(); value.toggle()
        fixture.post(AVAudioSession.interruptionNotification, ended)
        play(fixture)
        XCTAssertEqual(value.state, .playing); XCTAssertEqual(fixture.downloads.count, 2)
        value.dispose()
    }
    func testIncompatibleCategoryAndUnknownNotificationFailClosed() {
        let notices: [(Notification.Name, [AnyHashable: Any])] = [
            (AVAudioSession.routeChangeNotification,
             [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue]),
            (AVAudioSession.routeChangeNotification, [:]),
            (AVAudioSession.interruptionNotification, [:])
        ]
        for (name, info) in notices {
            let fixture = NativeAudioFixture(), value = model(fixture)
            play(fixture); fixture.playbackConfiguration = false
            fixture.post(name, info); fixture.delivery.drain()
            XCTAssertEqual(value.state, .idle); XCTAssertEqual(fixture.deactivations, 1)
            value.dispose()
        }
    }
    func testDownloadActivationDecodeAndPlayFailureReleaseBeforeRetry() {
        for failure in NativeAudioFixture.Failure.allCases {
            let fixture = NativeAudioFixture(); fixture.failure = failure
            let value = model(fixture)
            fixture.downloads[0].complete(failure == .download ? nil : Data([1]))
            fixture.delivery.drain()
            XCTAssertEqual(value.state, .failed)
            let activated = failure != .download && failure != .activation
            XCTAssertEqual(fixture.deactivations, activated ? 1 : 0)
            XCTAssertEqual(fixture.downloads[0].cancels, 1)
            if let player = fixture.players.first { XCTAssertNil(player.delegate); XCTAssertEqual(player.stops, 1) }
            fixture.failure = nil
            value.approveSelectedMedia(); value.toggle(); play(fixture)
            XCTAssertEqual(value.state, .playing)
            value.dispose(); XCTAssertEqual(fixture.deactivations, activated ? 2 : 1)
        }
    }
    func testResumeFailureCleansUpAndDisposedRunStaysStopped() {
        let fixture = NativeAudioFixture(), value = model(fixture)
        play(fixture); value.toggle(); fixture.players[0].canPlay = false
        value.toggle(); XCTAssertEqual(value.state, .failed); XCTAssertEqual(fixture.deactivations, 1)
        value.approveSelectedMedia(); value.toggle()
        let pending = fixture.downloads[1]
        fixture.post(UIApplication.didEnterBackgroundNotification)
        value.dispose(); pending.complete(Data([1])); fixture.delivery.drain()
        XCTAssertEqual(value.state, .disposed)
        XCTAssertEqual(fixture.activations, 1); XCTAssertEqual(fixture.deactivations, 1)
    }
    func testTerminalCallbackCanRetryWithoutOldCleanupStoppingIt() {
        let fixture = NativeAudioFixture()
        var events: [String] = []
        fixture.driver.start(source: fixture.source(), policy: fixture.policy) { event in
            if case .failed = event {
                events.append("failed")
                fixture.driver.start(source: fixture.source("retry.mp3"), policy: fixture.policy) { next in
                    if case .playing = next { events.append("playing") }
                }
            }
        }
        fixture.downloads[0].complete(nil); fixture.delivery.drain()
        play(fixture)
        XCTAssertEqual(events, ["failed", "playing"])
        XCTAssertEqual(fixture.players[0].stops, 0)
        fixture.driver.stop(); XCTAssertEqual(fixture.deactivations, 1)
    }
    func testDormantAndRejectedOriginsNeverStartNativeResources() {
        let fixture = NativeAudioFixture()
        let value = PlatformAudioPlayback(driver: fixture.driver, policy: fixture.policy)
        value.select(fixture.source()); value.approveSelectedMedia(); value.toggle()
        XCTAssertEqual(value.state, .gated)
        var failed = false
        fixture.driver.start(source: .init(url: URL(string: "https://unapproved.example.test/a")!, scope: UUID()),
                             policy: fixture.policy) { if case .failed = $0 { failed = true } }
        XCTAssertTrue(failed); XCTAssertTrue(fixture.downloads.isEmpty)
        XCTAssertEqual(fixture.activations, 0); XCTAssertEqual(fixture.deactivations, 0)
    }
    func testHeadphonePlugInKeepsPlayingAndUnplugStopsWithoutAutoResume() {
        let fixture = NativeAudioFixture(), value = model(fixture)
        play(fixture)
        fixture.post(AVAudioSession.routeChangeNotification,
                     [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])
        fixture.delivery.drain(); XCTAssertEqual(value.state, .playing); XCTAssertEqual(fixture.deactivations, 0)
        fixture.post(AVAudioSession.routeChangeNotification,
                     [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        fixture.delivery.drain(); XCTAssertEqual(value.state, .idle); XCTAssertEqual(fixture.deactivations, 1)
        fixture.post(AVAudioSession.interruptionNotification, [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        ])
        fixture.delivery.drain()
        XCTAssertEqual(value.state, .idle); XCTAssertEqual(fixture.players[0].plays, 1)
        XCTAssertEqual(fixture.downloads.count, 1); XCTAssertEqual(fixture.activations, 1)
        value.dispose()
    }
    func testNewDeviceUnderForeignCategoryStillStops() {
        let fixture = NativeAudioFixture(), value = model(fixture)
        play(fixture); fixture.playbackConfiguration = false
        fixture.post(AVAudioSession.routeChangeNotification,
                     [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])
        fixture.delivery.drain(); XCTAssertEqual(value.state, .idle); XCTAssertEqual(fixture.deactivations, 1)
        value.dispose()
    }
    func testRepeatedStartsKeepOneObserverSetAndDisposeReleasesAll() {
        let fixture = NativeAudioFixture()
        XCTAssertEqual(fixture.driver.lifecycleRegistrations, 0)
        let value = model(fixture)
        XCTAssertEqual(fixture.driver.lifecycleRegistrations, NativeAudioLifecycleObservation.names.count)
        for path in ["two.mp3", "three.mp3"] {
            value.select(fixture.source(path)); value.approveSelectedMedia(); value.toggle()
            XCTAssertEqual(fixture.driver.lifecycleRegistrations, NativeAudioLifecycleObservation.names.count)
        }
        play(fixture); XCTAssertEqual(value.state, .playing)
        // One interruption stops exactly once, not once per earlier run.
        fixture.post(AVAudioSession.interruptionNotification,
                     [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        fixture.delivery.drain()
        XCTAssertEqual(value.state, .idle); XCTAssertEqual(fixture.deactivations, 1)
        XCTAssertEqual(fixture.driver.lifecycleRegistrations, 0)
        value.dispose(); XCTAssertEqual(fixture.driver.lifecycleRegistrations, 0)
        XCTAssertEqual(fixture.deactivations, 1)
    }
}

private final class NativeAudioDeliveryQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [@MainActor @Sendable () -> Void] = []
    func enqueue(_ operation: @escaping @MainActor @Sendable () -> Void) {
        lock.lock(); operations.append(operation); lock.unlock()
    }
    @MainActor func drain() {
        while true {
            lock.lock()
            let operation = operations.isEmpty ? nil : operations.removeFirst()
            lock.unlock()
            guard let operation else { return }
            operation()
        }
    }
}
private final class NativeAudioDownloadStub: NativePlatformAudioDownloading {
    private var completion: (@Sendable (Data?) -> Void)?
    private(set) var cancels = 0
    func start(_ url: URL, completion: @escaping @Sendable (Data?) -> Void) { self.completion = completion }
    func cancel() { cancels += 1 } // Keep the callback to model a late URLSession completion.
    func complete(_ data: Data?) { let callback = completion; completion = nil; callback?(data) }
}
@MainActor private final class NativeAudioPlayerStub: NativePlatformAudioPlaying {
    weak var delegate: (any AVAudioPlayerDelegate)?
    var canPrepare = true, canPlay = true
    private(set) var plays = 0, pauses = 0, stops = 0
    func prepareToPlay() -> Bool { canPrepare }
    func play() -> Bool { plays += 1; return canPlay }
    func pause() { pauses += 1 }
    func stop() { stops += 1 }
}
@MainActor private final class NativeAudioFixture {
    enum Failure: CaseIterable { case download, activation, decode, prepare, play }
    enum FixtureError: Error { case expected }
    let notifications = NotificationCenter()
    let delivery = NativeAudioDeliveryQueue()
    let policy = PlatformMediaPolicy(approvedOrigins: ["https://audio.example.test"])
    var downloads: [NativeAudioDownloadStub] = []
    var players: [NativeAudioPlayerStub] = []
    var failure: Failure?
    var activations = 0, deactivations = 0
    var categoryChangeOnActivation = false, playbackConfiguration = true
    lazy var driver = NativePlatformAudioDriver(dependencies: .init(
        notifications: notifications,
        makeDownload: { [unowned self] _ in
            let value = NativeAudioDownloadStub(); downloads.append(value); return value
        },
        makePlayer: { [unowned self] _ in
            if failure == .decode { throw FixtureError.expected }
            let value = NativeAudioPlayerStub(); value.canPrepare = failure != .prepare; value.canPlay = failure != .play
            players.append(value); return value
        },
        activateSession: { [unowned self] in
            if failure == .activation { throw FixtureError.expected }
            activations += 1
            if categoryChangeOnActivation {
                post(AVAudioSession.routeChangeNotification,
                     [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue])
            }
        },
        deactivateSession: { [unowned self] in deactivations += 1 },
        hasPlaybackConfiguration: { [unowned self] in playbackConfiguration },
        enqueue: { [delivery] operation in delivery.enqueue(operation) }))
    func source(_ path: String = "one.mp3") -> PlatformMediaSource {
        .init(url: URL(string: "https://audio.example.test/" + path)!, scope: UUID())
    }
    func post(_ name: Notification.Name, _ info: [AnyHashable: Any] = [:]) {
        notifications.post(name: name, object: nil, userInfo: info)
    }
}
